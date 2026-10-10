import Foundation
import JavaScriptCore

/// Serializes `execute()` so concurrent `trackScreen` / `trackEvent` / close handlers cannot race on JS + `dispatchWrapper`
/// (fixes alternating success when the host fires navigation quickly).
@available(iOS 15.0, *)
private actor ExecuteSerialGate {
    private var tail: Task<Any?, Never>?

    func enqueue(_ work: @Sendable @escaping () async -> Any?) async -> Any? {
        let previous = tail
        let task = Task<Any?, Never> {
            _ = await previous?.value
            return await work()
        }
        tail = task
        return await task.value
    }

    /// Runs `work` before any work already queued (e.g. `trackScreen` enqueued before `willShow` runs navigation).
    /// Jump completes first; the prior backlog runs after.
    func enqueueNext(_ work: @Sendable @escaping () async -> Any?) async -> Any? {
        let previous = tail
        let jump = Task<Any?, Never> {
            return await work()
        }
        let bridge = Task<Any?, Never> {
            _ = await jump.value
            _ = await previous?.value
            return nil as Any?
        }
        tail = bridge
        return await jump.value
    }
}

@available(iOS 15.0, *)
final class ExecuteBridge: @unchecked Sendable {
    /// Keep in sync with the released SDK version tag.
    static let spotcheckSdkVersion = "1.2.10-beta.1"

    private static let executeTimeout: TimeInterval = 15

    private let spotcheckStore: SpotCheckStateStore
    private let functionStore: FunctionStore
    private let sentry: SentryAdapter
    private weak var listener: ListenerBridge?
    private let serialGate = ExecuteSerialGate()

    /// One context for the SDK lifetime; every JS call happens on `jsQueue`.
    private let jsQueue = DispatchQueue(label: "com.surveysparrow.spotcheck.js")
    private let jsContext: JSContext
    private var timers: [Int: DispatchWorkItem] = [:]
    private var nextTimerId = 0
    /// Delegate calls run in the order JS made them (mutated on `jsQueue` only).
    private var listenerTail: Task<Void, Never>?
    /// Count of running `sentry.*` functions, so their JS exceptions aren't re-reported (jsQueue only).
    private var sentryRunDepth = 0

    /// Backend-driven script injection into the classic/chat webview (called on main).
    var onWebViewInject: ((String, String) -> Void)?

    init(spotcheckStore: SpotCheckStateStore, functionStore: FunctionStore, sentry: SentryAdapter) {
        self.spotcheckStore = spotcheckStore
        self.functionStore = functionStore
        self.sentry = sentry
        // Created on jsQueue so JSC's GC timers don't run on the main run loop.
        var context: JSContext?
        jsQueue.sync { context = JSContext() }
        self.jsContext = context!
        jsQueue.sync { setupJSContext() }
    }

    func setListener(_ listener: ListenerBridge?) {
        self.listener = listener
    }

    // MARK: Globals (installed once)

    private func setupJSContext() {
        let ctx = jsContext
        ctx.exceptionHandler = { [weak self] _, exception in
            let message = exception?.toString() ?? "Unknown JS exception"
            NSLog("[SurveySparrow Spotcheck] JS exception: %@", message)
            guard let self, self.sentryRunDepth == 0 else { return }
            self.sentry.captureP1Error(message, "GENERAL", ["action": "jsException"])
        }

        let console = JSValue(newObjectIn: ctx)!
        let log: @convention(block) () -> Void = {
            #if DEBUG
            let args = (JSContext.currentArguments() as? [JSValue])?.map { $0.toString() ?? "" } ?? []
            print("[SurveySparrow Spotcheck]", args.joined(separator: " "))
            #endif
        }
        // console.error stays visible in release so host developers see SDK errors.
        let error: @convention(block) () -> Void = {
            let args = (JSContext.currentArguments() as? [JSValue])?.map { $0.toString() ?? "" } ?? []
            NSLog("[SurveySparrow Spotcheck] %@", args.joined(separator: " "))
        }
        console.setObject(log, forKeyedSubscript: "log" as NSString)
        console.setObject(log, forKeyedSubscript: "warn" as NSString)
        console.setObject(error, forKeyedSubscript: "error" as NSString)
        ctx.setObject(console, forKeyedSubscript: "console" as NSString)

        let setTimeout: @convention(block) (JSValue, JSValue) -> Int = { [weak self] callback, ms in
            self?.schedule(callback, ms: ms, repeats: false) ?? 0
        }
        let setInterval: @convention(block) (JSValue, JSValue) -> Int = { [weak self] callback, ms in
            self?.schedule(callback, ms: ms, repeats: true) ?? 0
        }
        let clearTimer: @convention(block) (JSValue) -> Void = { [weak self] id in
            guard let self, id.isNumber else { return }
            self.timers.removeValue(forKey: Int(id.toInt32()))?.cancel()
        }
        ctx.setObject(setTimeout, forKeyedSubscript: "setTimeout" as NSString)
        ctx.setObject(setInterval, forKeyedSubscript: "setInterval" as NSString)
        ctx.setObject(clearTimer, forKeyedSubscript: "clearTimeout" as NSString)
        ctx.setObject(clearTimer, forKeyedSubscript: "clearInterval" as NSString)

        let fetch: @convention(block) (String, JSValue) -> JSValue = { [weak self] urlString, options in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return self.jsFetch(urlString, options: options)
        }
        ctx.setObject(fetch, forKeyedSubscript: "fetch" as NSString)

        ctx.evaluateScript(Self.responsePolyfill)
        ctx.evaluateScript(Self.urlSearchParamsPolyfill)
    }

    /// Must run on `jsQueue`.
    private func schedule(_ callback: JSValue, ms: JSValue, repeats: Bool) -> Int {
        nextTimerId += 1
        let id = nextTimerId
        let delay = max(0, ms.isNumber ? Int(ms.toInt32()) : 0)
        func arm() {
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.timers[id] != nil else { return }
                if repeats {
                    arm()
                } else {
                    self.timers.removeValue(forKey: id)
                }
                callback.call(withArguments: [])
            }
            timers[id] = item
            jsQueue.asyncAfter(deadline: .now() + .milliseconds(delay), execute: item)
        }
        arm()
        return id
    }

    // MARK: Execute

    @discardableResult
    func execute(_ functionName: String, params: [String: Any]? = nil) async -> Any? {
        await serialGate.enqueue { [weak self] in
            guard let self else { return nil }
            return await self.executeUnserialized(functionName, params: params)
        }
    }

    /// Runs ahead of already-queued work (navigation teardown before a queued `trackScreen`).
    @discardableResult
    func executeWithNativePrelude(
        nativePrelude: @Sendable @escaping () async -> Void,
        functionName: String,
        params: [String: Any]? = nil
    ) async -> Any? {
        await serialGate.enqueueNext { [weak self] in
            guard let self else { return nil }
            await nativePrelude()
            return await self.executeUnserialized(functionName, params: params)
        }
    }

    // Reporting failures are not reported again (avoids loops).
    private static func isSentryFunction(_ name: String) -> Bool { name.hasPrefix("sentry.") }

    // Style getters run on every render; they would push useful breadcrumbs out.
    private static func isBreadcrumbWorthy(_ name: String) -> Bool {
        !isSentryFunction(name) && name.range(of: "\\.get\\w*Styles$", options: .regularExpression) == nil
    }

    // Message type only; never survey content.
    private static func describeParams(_ name: String, _ params: [String: Any]?) -> [String: Any] {
        guard name == "webviewComponent.handleWebViewMessage",
              let event = params?["event"] as? [String: Any],
              let native = event["nativeEvent"] as? [String: Any],
              let data = native["data"] as? String else { return [:] }
        if data == "captureImage" { return ["messageType": data] }
        guard let json = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
              let type = json["type"] as? String else { return [:] }
        return ["messageType": type]
    }

    private func executeUnserialized(_ functionName: String, params: [String: Any]?) async -> Any? {
        guard functionStore.isLoaded, let functionString = functionStore.resolve(functionName) else {
            return nil
        }
        let reportErrors = !Self.isSentryFunction(functionName)
        if Self.isBreadcrumbWorthy(functionName) {
            sentry.addBreadcrumb("execute", ["functionName": functionName].merging(Self.describeParams(functionName, params)) { a, _ in a })
        }

        var mergedParams = params ?? [:]
        mergedParams["sdkVersion"] = Self.spotcheckSdkVersion
        let state = await MainActor.run { spotcheckStore.getState() }

        let result: Any?
        do {
            result = try await runFunction(functionString, params: mergedParams, state: state, isSentry: !reportErrors)
        } catch {
            if reportErrors {
                sentry.captureP1Error(error, "GENERAL", ["action": "execute:runtime", "functionName": functionName])
            }
            result = nil
        }
        // Main queue is FIFO: state dispatched during the call is applied before we return.
        await MainActor.run {}
        return result
    }

    private func runFunction(_ functionString: String, params: [String: Any], state: [String: Any], isSentry: Bool = false) async throws -> Any? {
        let paramsJSON = try Self.json(params)
        let stateJSON = try Self.json(state)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            jsQueue.async { [weak self] in
                guard let self else { continuation.resume(returning: nil); return }
                var finished = false
                if isSentry { self.sentryRunDepth += 1 }
                let finish: (Result<Any?, Error>) -> Void = { [weak self] result in
                    guard !finished else { return }
                    finished = true
                    if isSentry { self?.sentryRunDepth -= 1 }
                    continuation.resume(with: result)
                }

                let ctx = self.jsContext
                ctx.setObject(self.makePayloadBridges(), forKeyedSubscript: "__ssBridges" as NSString)
                let script = """
                (async function() {
                    var func = (\(functionString));
                    var payload = Object.assign({ params: \(paramsJSON), state: \(stateJSON) }, __ssBridges);
                    return await func(payload);
                })();
                """
                guard let promise = ctx.evaluateScript(script), promise.isObject else {
                    finish(.success(nil))
                    return
                }

                let resolve: @convention(block) (JSValue) -> Void = { value in
                    finish(.success(value.isNull || value.isUndefined ? nil : value.toObject()))
                }
                let reject: @convention(block) (JSValue) -> Void = { error in
                    finish(.failure(SpotCheckError.executionError(error.toString())))
                }
                promise.invokeMethod("then", withArguments: [
                    JSValue(object: resolve, in: ctx)!,
                    JSValue(object: reject, in: ctx)!,
                ])

                self.jsQueue.asyncAfter(deadline: .now() + Self.executeTimeout) {
                    finish(.failure(SpotCheckError.executionError("Execution timed out")))
                }
            }
        }
    }

    /// Payload callbacks; all run on `jsQueue`.
    private func makePayloadBridges() -> [String: Any] {
        let store = spotcheckStore
        let listenerRef = listener

        // Async: main.sync while holding the JS lock deadlocks with JSC timers on the main run loop.
        // execute() waits for these before returning, so callers never read stale state.
        let dispatch: @convention(block) (JSValue) -> Void = { update in
            guard let dict = update.toDictionary() as? [String: Any] else { return }
            DispatchQueue.main.async { store.dispatch(dict) }
        }

        let saveData: @convention(block) (String) -> Void = { StorageAdapter.saveData($0) }
        let loadData: @convention(block) (Bool) -> JSValue = { isTraceId in
            let value = StorageAdapter.loadData(isTraceId)
            let ctx = JSContext.current()!
            return ctx.objectForKeyedSubscript("Promise").invokeMethod("resolve", withArguments: [value])
        }

        let capture: (String) -> @convention(block) (JSValue, String, JSValue) -> Void = { [weak self] priority in
            return { error, source, context in
                let message = error.objectForKeyedSubscript("message")?.toString().flatMap { $0 == "undefined" ? nil : $0 }
                    ?? error.toString() ?? "Unknown"
                let ctx = context.toDictionary() as? [String: Any] ?? [:]
                if priority == "P0" {
                    self?.sentry.captureP0Error(message, source, ctx)
                } else {
                    self?.sentry.captureP1Error(message, source, ctx)
                }
            }
        }

        let notify: (@escaping (SsSpotcheckDelegate, [String: AnyObject]) async -> Void) -> @convention(block) (JSValue) -> JSValue = { [weak self] call in
            return { data in
                let dict = (data.toDictionary() as? [String: Any] ?? [:]) as [String: AnyObject]
                let previous = self?.listenerTail
                self?.listenerTail = Task { @MainActor in
                    await previous?.value
                    if let delegate = listenerRef?.delegate { await call(delegate, dict) }
                }
                let ctx = JSContext.current()!
                return ctx.objectForKeyedSubscript("Promise").invokeMethod("resolve", withArguments: [])
            }
        }

        let inject: @convention(block) (String, String) -> Void = { [weak self] target, script in
            DispatchQueue.main.async { self?.onWebViewInject?(target, script) }
        }

        return [
            "dispatchWrapper": dispatch,
            "storage": ["saveData": saveData, "loadData": loadData] as [String: Any],
            "sentry": ["captureP0Error": capture("P0"), "captureP1Error": capture("P1")] as [String: Any],
            "keyboard": [
                "pauseDefaultKeyboardBehavior": { KeyboardAdapter.pauseDefaultKeyboardBehavior() } as @convention(block) () -> Void,
                "resumeDefaultKeyboardBehavior": { KeyboardAdapter.resumeDefaultKeyboardBehavior() } as @convention(block) () -> Void,
            ] as [String: Any],
            "listener": [
                "onSurveyResponse": notify { await $0.handleSurveyResponse(response: $1) },
                "onSurveyLoaded": notify { await $0.handleSurveyLoaded(response: $1) },
                "onPartialSubmission": notify { await $0.handlePartialSubmission(response: $1) },
                "onCloseButtonTap": notify { delegate, _ in await delegate.handleCloseButtonTap() },
            ] as [String: Any],
            "webview": ["inject": inject] as [String: Any],
        ]
    }

    private static func json(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: fetch

    /// Must run on `jsQueue`.
    private func jsFetch(_ urlString: String, options: JSValue) -> JSValue {
        let ctx = jsContext
        let executor: @convention(block) (JSValue, JSValue) -> Void = { [weak self] resolve, reject in
            guard let self else { return }
            guard let url = URL(string: urlString) else {
                reject.call(withArguments: ["Invalid URL: \(urlString)"])
                return
            }
            var request = URLRequest(url: url)
            if let opts = options.toDictionary() {
                request.httpMethod = (opts["method"] as? String)?.uppercased() ?? "GET"
                if let headers = opts["headers"] as? [String: Any] {
                    for (k, v) in headers { request.setValue("\(v)", forHTTPHeaderField: k) }
                }
                if let body = opts["body"] as? String {
                    request.httpBody = body.data(using: .utf8)
                }
            }
            URLSession.shared.dataTask(with: request) { data, response, error in
                self.jsQueue.async {
                    if let error = error {
                        reject.call(withArguments: [error.localizedDescription])
                        return
                    }
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let make = ctx.objectForKeyedSubscript("__ssMakeResponse")
                    resolve.call(withArguments: [make?.call(withArguments: [status, body]) as Any])
                }
            }.resume()
        }
        let promise = ctx.objectForKeyedSubscript("Promise")!
        return promise.construct(withArguments: [JSValue(object: executor, in: ctx)!])!
    }

    private static let responsePolyfill = """
    function __ssMakeResponse(status, body) {
        return {
            ok: status >= 200 && status < 300,
            status: status,
            headers: { get: function() { return null; } },
            json: function() { return Promise.resolve(JSON.parse(body)); },
            text: function() { return Promise.resolve(body); }
        };
    }
    """

    private static let urlSearchParamsPolyfill = """
    if (typeof URLSearchParams === 'undefined') {
        function URLSearchParams(init) {
            this._params = [];
            if (typeof init === 'string') {
                var str = init.startsWith('?') ? init.substring(1) : init;
                var pairs = str.split('&');
                for (var i = 0; i < pairs.length; i++) {
                    var kv = pairs[i].split('=');
                    this._params.push([decodeURIComponent(kv[0] || ''), decodeURIComponent(kv[1] || '')]);
                }
            } else if (init && typeof init === 'object') {
                var keys = Object.keys(init);
                for (var j = 0; j < keys.length; j++) {
                    this._params.push([keys[j], String(init[keys[j]])]);
                }
            }
        }
        URLSearchParams.prototype.get = function(name) {
            for (var i = 0; i < this._params.length; i++) {
                if (this._params[i][0] === name) return this._params[i][1];
            }
            return null;
        };
        URLSearchParams.prototype.set = function(name, value) {
            for (var i = 0; i < this._params.length; i++) {
                if (this._params[i][0] === name) { this._params[i][1] = String(value); return; }
            }
            this._params.push([name, String(value)]);
        };
        URLSearchParams.prototype.append = function(name, value) { this._params.push([name, String(value)]); };
        URLSearchParams.prototype.toString = function() {
            return this._params.map(function(p) { return encodeURIComponent(p[0]) + '=' + encodeURIComponent(p[1]); }).join('&');
        };
    }
    """
}

// MARK: - Listener Bridge

@available(iOS 15.0, *)
final class ListenerBridge {
    var delegate: SsSpotcheckDelegate?

    init(delegate: SsSpotcheckDelegate?) {
        self.delegate = delegate
    }
}
