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
    /// Bundled helpers + API parity (keep in sync with `buildPayload` `sdkVersion`).
    static let spotcheckSdkVersion = "1.0.4-beta.1"

    private let spotcheckStore: SpotCheckStateStore
    private let functionStore: FunctionStore
    private let sentry: SentryAdapter
    private weak var listener: ListenerBridge?
    private let jsContext: JSContext
    private let serialGate = ExecuteSerialGate()

    init(spotcheckStore: SpotCheckStateStore, functionStore: FunctionStore, sentry: SentryAdapter) {
        self.spotcheckStore = spotcheckStore
        self.functionStore = functionStore
        self.sentry = sentry
        self.jsContext = JSContext()!
        setupJSContext()
    }

    func setListener(_ listener: ListenerBridge?) {
        self.listener = listener
    }

    private func setupJSContext() {
        jsContext.exceptionHandler = { [weak self] _, exception in
            guard let msg = exception?.toString() else { return }
            self?.sentry.captureP1Error(msg, "GENERAL", ["action": "jsContextException"])
        }

        let fetch: @convention(block) (String, JSValue) -> JSValue = { [weak self] urlString, options in
            guard let ctx = self?.jsContext else { return JSValue(undefinedIn: JSContext.current()) }
            return self?.jsFetch(urlString, options: options, context: ctx) ?? JSValue(undefinedIn: ctx)
        }
        jsContext.setObject(fetch, forKeyedSubscript: "nativeFetch" as NSString)

        let setTimeout: @convention(block) (JSValue, Int) -> Void = { callback, ms in
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) {
                callback.call(withArguments: [])
            }
        }
        jsContext.setObject(setTimeout, forKeyedSubscript: "setTimeout" as NSString)

        let consoleObj = JSValue(newObjectIn: jsContext)!
        let logBlock: @convention(block) (JSValue) -> Void = { _ in }
        let errorBlock: @convention(block) (JSValue) -> Void = { _ in }
        consoleObj.setObject(logBlock, forKeyedSubscript: "log" as NSString)
        consoleObj.setObject(errorBlock, forKeyedSubscript: "error" as NSString)
        jsContext.setObject(consoleObj, forKeyedSubscript: "console" as NSString)
    }

    @discardableResult
    func execute(_ functionName: String, params: [String: Any]? = nil) async -> Any? {
        await serialGate.enqueue { [weak self] in
            guard let self else { return nil }
            return await self.executeUnserialized(functionName, params: params)
        }
    }

    /// Native prelude + `executeUnserialized` in one unit that **jumps ahead** of pending `execute` work
    /// so navigation teardown (unmount + dismiss + reset) runs before an already-queued `trackScreen`.
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

    private func executeUnserialized(_ functionName: String, params: [String: Any]?) async -> Any? {
        if !functionStore.isLoaded {
            for _ in 0..<50 { // Max 5 seconds
                if functionStore.isLoaded { break }
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }

        guard functionStore.isLoaded else {
            return nil
        }

        guard let functionString = functionStore.resolve(functionName) else {
            return nil
        }

        let state = spotcheckStore.getState()
        let payload = buildPayload(params: params, state: state)

        do {
            let result = try await runFunction(functionString, payload: payload, functionName: functionName)
            return result
        } catch {
            sentry.captureP1Error(error, "GENERAL", ["action": "execute", "functionName": functionName])
            return nil
        }
    }

    private func buildPayload(params: [String: Any]?, state: [String: Any]) -> [String: Any] {
        var mergedParams = params ?? [:]
        mergedParams["sdkVersion"] = Self.spotcheckSdkVersion

        var payload: [String: Any] = [
            "params": mergedParams,
            "state": state,
        ]

        let dispatchRef: @convention(block) (JSValue) -> Void = { [weak self] jsUpdate in
            guard let update = jsUpdate.toDictionary() as? [String: Any] else { return }
            DispatchQueue.main.async {
                self?.spotcheckStore.dispatch(update)
            }
        }
        payload["dispatchWrapper"] = dispatchRef

        let saveData: @convention(block) (String) -> Void = { value in
            StorageAdapter.saveData(value)
        }
        let loadData: @convention(block) (Bool) -> String = { isTraceId in
            return StorageAdapter.loadData(isTraceId)
        }
        payload["storage"] = [
            "saveData": saveData,
            "loadData": loadData,
        ] as [String: Any]

        let captureP0: @convention(block) (JSValue, String, JSValue) -> Void = { [weak self] error, source, context in
            let ctx = context.toDictionary() as? [String: Any] ?? [:]
            self?.sentry.captureP0Error(error.toString() ?? "Unknown", source, ctx)
        }
        let captureP1: @convention(block) (JSValue, String, JSValue) -> Void = { [weak self] error, source, context in
            let ctx = context.toDictionary() as? [String: Any] ?? [:]
            self?.sentry.captureP1Error(error.toString() ?? "Unknown", source, ctx)
        }
        payload["sentry"] = [
            "captureP0Error": captureP0,
            "captureP1Error": captureP1,
        ] as [String: Any]

        payload["keyboard"] = [
            "pauseDefaultKeyboardBehavior": { KeyboardAdapter.pauseDefaultKeyboardBehavior() } as @convention(block) () -> Void,
            "resumeDefaultKeyboardBehavior": { KeyboardAdapter.resumeDefaultKeyboardBehavior() } as @convention(block) () -> Void,
        ] as [String: Any]

        let listenerRef = self.listener
        var listenerDict: [String: Any] = [:]
        let onSurveyResponse: @convention(block) (JSValue) -> Void = { data in
            let d = data.toDictionary() as? [String: Any] ?? [:]
            Task { @MainActor in await listenerRef?.delegate?.handleSurveyResponse(response: d as [String: AnyObject]) }
        }
        let onSurveyLoaded: @convention(block) (JSValue) -> Void = { data in
            let d = data.toDictionary() as? [String: Any] ?? [:]
            Task { @MainActor in await listenerRef?.delegate?.handleSurveyLoaded(response: d as [String: AnyObject]) }
        }
        let onPartialSubmission: @convention(block) (JSValue) -> Void = { data in
            let d = data.toDictionary() as? [String: Any] ?? [:]
            Task { @MainActor in await listenerRef?.delegate?.handlePartialSubmission(response: d as [String: AnyObject]) }
        }
        let onCloseButtonTap: @convention(block) () -> Void = {
            Task { @MainActor in await listenerRef?.delegate?.handleCloseButtonTap() }
        }
        listenerDict["onSurveyResponse"] = onSurveyResponse
        listenerDict["onSurveyLoaded"] = onSurveyLoaded
        listenerDict["onPartialSubmission"] = onPartialSubmission
        listenerDict["onCloseButtonTap"] = onCloseButtonTap
        payload["listener"] = listenerDict

        return payload
    }

    @Sendable
    private func runFunction(_ functionString: String, payload: [String: Any], functionName: String) async throws -> Any? {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }

                let ctx = JSContext()!
                ctx.exceptionHandler = { _, _ in }

                self.injectGlobals(into: ctx)

                ctx.setObject(payload["dispatchWrapper"], forKeyedSubscript: "__dispatchWrapper" as NSString)
                ctx.setObject(payload["storage"], forKeyedSubscript: "__storage" as NSString)
                ctx.setObject(payload["sentry"], forKeyedSubscript: "__sentry" as NSString)
                ctx.setObject(payload["keyboard"], forKeyedSubscript: "__keyboard" as NSString)
                ctx.setObject(payload["listener"], forKeyedSubscript: "__listener" as NSString)

                let stateJSON: String
                let paramsJSON: String
                do {
                    let stateData = try JSONSerialization.data(withJSONObject: payload["state"] as Any)
                    stateJSON = String(data: stateData, encoding: .utf8) ?? "{}"
                    let paramsData = try JSONSerialization.data(withJSONObject: payload["params"] as Any)
                    paramsJSON = String(data: paramsData, encoding: .utf8) ?? "{}"
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let script = """
                (async function() {
                    var func = (\(functionString));
                    var payload = {
                        params: \(paramsJSON),
                        state: \(stateJSON),
                        dispatchWrapper: __dispatchWrapper,
                        storage: __storage,
                        sentry: __sentry,
                        keyboard: __keyboard,
                        listener: __listener,
                    };
                    return await func(payload);
                })();
                """

                let result = ctx.evaluateScript(script)

                if let promiseResult = result, promiseResult.isObject {
                    let thenFunc = promiseResult.objectForKeyedSubscript("then")
                    if let thenFunc = thenFunc, !thenFunc.isUndefined {
                        let resolve: @convention(block) (JSValue) -> Void = { val in
                            if val.isNull || val.isUndefined {
                                continuation.resume(returning: nil)
                            } else {
                                continuation.resume(returning: val.toObject())
                            }
                        }
                        let reject: @convention(block) (JSValue) -> Void = { err in
                            continuation.resume(throwing: SpotCheckError.executionError(err.toString()))
                        }
                        promiseResult.invokeMethod("then", withArguments: [JSValue(object: resolve, in: ctx)!])
                        promiseResult.invokeMethod("catch", withArguments: [JSValue(object: reject, in: ctx)!])
                        return
                    }
                }

                if let r = result, !r.isUndefined && !r.isNull {
                    continuation.resume(returning: r.toObject())
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func injectGlobals(into ctx: JSContext) {
        let consoleObj = JSValue(newObjectIn: ctx)!
        let log: @convention(block) (JSValue) -> Void = { _ in }
        let err: @convention(block) (JSValue) -> Void = { _ in }
        consoleObj.setObject(log, forKeyedSubscript: "log" as NSString)
        consoleObj.setObject(err, forKeyedSubscript: "error" as NSString)
        consoleObj.setObject(log, forKeyedSubscript: "warn" as NSString)
        ctx.setObject(consoleObj, forKeyedSubscript: "console" as NSString)

        let fetch: @convention(block) (String, JSValue) -> JSValue = { [weak self] urlString, options in
            return self?.jsFetch(urlString, options: options, context: ctx) ?? JSValue(undefinedIn: ctx)
        }
        ctx.setObject(fetch, forKeyedSubscript: "fetch" as NSString)

        let setTimeoutBlock: @convention(block) (JSValue, JSValue) -> Void = { callback, ms in
            let delay = ms.isUndefined ? 0 : ms.toInt32()
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(delay))) {
                callback.call(withArguments: [])
            }
        }
        ctx.setObject(setTimeoutBlock, forKeyedSubscript: "setTimeout" as NSString)

        let setIntervalBlock: @convention(block) (JSValue, JSValue) -> JSValue = { callback, ms in
            let delay = ms.isUndefined ? 1000 : ms.toInt32()
            var timer: Timer?
            timer = Timer.scheduledTimer(withTimeInterval: Double(delay) / 1000.0, repeats: true) { _ in
                callback.call(withArguments: [])
            }
            RunLoop.main.add(timer!, forMode: .common)
            return JSValue(int32: 0, in: ctx)
        }
        ctx.setObject(setIntervalBlock, forKeyedSubscript: "setInterval" as NSString)

        ctx.evaluateScript(Self.urlSearchParamsPolyfill)
    }

    private func jsFetch(_ urlString: String, options: JSValue, context: JSContext) -> JSValue {
        let executor: @convention(block) (JSValue, JSValue) -> Void = { resolve, reject in
            guard let url = URL(string: urlString) else {
                reject.call(withArguments: ["Invalid URL: \(urlString)"])
                return
            }

            var request = URLRequest(url: url)
            if let opts = options.toDictionary() {
                request.httpMethod = (opts["method"] as? String)?.uppercased() ?? "GET"
                if let headers = opts["headers"] as? [String: String] {
                    for (k, v) in headers {
                        request.setValue(v, forHTTPHeaderField: k)
                    }
                }
                if let body = opts["body"] as? String {
                    request.httpBody = body.data(using: .utf8)
                }
            }

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    reject.call(withArguments: [error.localizedDescription])
                    return
                }
                let bodyString = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

                let responseObj = JSValue(newObjectIn: context)!
                responseObj.setObject(statusCode >= 200 && statusCode < 300, forKeyedSubscript: "ok" as NSString)
                responseObj.setObject(statusCode, forKeyedSubscript: "status" as NSString)

                let jsonFunc: @convention(block) () -> JSValue = {
                    context.evaluateScript("(function() { return \(bodyString); })()") ?? JSValue(undefinedIn: context)
                }
                responseObj.setObject(jsonFunc, forKeyedSubscript: "json" as NSString)

                let textFunc: @convention(block) () -> String = { bodyString }
                responseObj.setObject(textFunc, forKeyedSubscript: "text" as NSString)

                resolve.call(withArguments: [responseObj])
            }.resume()
        }

        let executorValue = JSValue(object: executor, in: context)!
        let promiseConstructor = context.objectForKeyedSubscript("Promise")!
        return promiseConstructor.construct(withArguments: [executorValue])!
    }

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
