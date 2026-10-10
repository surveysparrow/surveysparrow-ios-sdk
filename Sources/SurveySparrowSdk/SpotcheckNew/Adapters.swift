import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Storage Adapter
// Dual behavior: saveData persists UUID, loadData(false) reads UUID, loadData(true) generates traceId

@available(iOS 15.0, *)
struct StorageAdapter {
    static func saveData(_ value: String) {
        UserDefaults.standard.set(value, forKey: "SurveySparrowUUID")
    }

    static func loadData(_ isTraceId: Bool) -> String {
        if isTraceId {
            let uuid = UUID().uuidString
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            return "\(uuid)-\(timestamp)"
        }
        return UserDefaults.standard.string(forKey: "SurveySparrowUUID") ?? ""
    }
}

// MARK: - Sentry Enricher (optional, ObjC runtime only)
// Expo pattern: used only when the host app links sentry-cocoa. Isolated SentryClient
// (dummy DSN, never SentrySDK.start, no crash handlers); beforeSend hands us the
// enriched event and returns nil, so nothing reaches Sentry or the host's Sentry.

final class SentryCocoaEnricher {
    private let client: NSObject
    private let lock = NSLock()
    private var pending: [String: Any] = [:]

    static var isAvailable: Bool {
        NSClassFromString("SentryOptions") != nil && NSClassFromString("SentryClient") != nil
    }

    // Weak ref so the beforeSend block doesn't retain the enricher.
    private final class WeakOwner { weak var value: SentryCocoaEnricher? }

    init?(onEvent: @escaping (_ event: [String: Any], _ info: [String: Any]) -> Void) {
        guard Self.isAvailable,
              let optCls = NSClassFromString("SentryOptions") as? NSObject.Type,
              let clientCls = NSClassFromString("SentryClient") as? NSObject.Type else { return nil }
        let options = optCls.init()
        // KVC on a missing key throws NSUndefinedKeyException; check setters first.
        func has(_ setter: String) -> Bool { options.responds(to: NSSelectorFromString(setter)) }
        guard has("setDsn:"), has("setBeforeSend:"),
              clientCls.instancesRespond(to: NSSelectorFromString("captureError:")) else { return nil }
        options.setValue("https://dummy@sentry.io/0", forKey: "dsn")
        if has("setAttachStacktrace:") { options.setValue(true, forKey: "attachStacktrace") }
        if has("setSendDefaultPii:") { options.setValue(false, forKey: "sendDefaultPii") }
        let owner = WeakOwner()
        let beforeSend: @convention(block) (NSObject) -> NSObject? = { event in
            let serializeSel = NSSelectorFromString("serialize")
            if event.responds(to: serializeSel),
               let dict = event.perform(serializeSel)?.takeUnretainedValue() as? [String: Any] {
                onEvent(dict, owner.value?.pending ?? [:])
            }
            return nil
        }
        options.setValue(beforeSend, forKey: "beforeSend")
        let initSel = NSSelectorFromString("initWithOptions:")
        // init consumes alloc's +1 and returns +1, so take the init result retained.
        guard let allocated = clientCls.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject,
              allocated.responds(to: initSel),
              let made = allocated.perform(initSel, with: options)?.takeRetainedValue() as? NSObject
        else { return nil }
        client = made
        owner.value = self
    }

    /// beforeSend runs synchronously inside captureError, so `pending` carries our tags.
    func capture(message: String, info: [String: Any]) {
        let error = NSError(domain: "SpotcheckSdkError", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        lock.lock()
        defer { lock.unlock() }
        pending = info
        _ = client.perform(NSSelectorFromString("captureError:"), with: error)
        pending = [:]
    }
}

// MARK: - Sentry Adapter
// Matches Expo/Android: try `execute("sentry.processSentryError", …)` first, then direct POST to `sdkErrors`.

@available(iOS 15.0, *)
final class SentryAdapter {
    private let domainName: () -> String

    weak var executeBridge: ExecuteBridge?

    private let breadcrumbLock = NSLock()
    private var breadcrumbs: [[String: Any]] = []

    init(domainName: @escaping () -> String) {
        self.domainName = domainName
        self.enricher = SentryCocoaEnricher { [weak self] event, info in
            self?.onEnrichedEvent(event, info)
        }
    }

    func addBreadcrumb(_ message: String, _ data: [String: Any] = [:]) {
        breadcrumbLock.lock()
        defer { breadcrumbLock.unlock() }
        breadcrumbs.append([
            "category": "spotcheck",
            "message": message,
            "data": data,
            "timestamp": Date().timeIntervalSince1970,
        ])
        if breadcrumbs.count > 30 { breadcrumbs.removeFirst() }
    }

    private func currentBreadcrumbs() -> [[String: Any]] {
        breadcrumbLock.lock()
        defer { breadcrumbLock.unlock() }
        return breadcrumbs
    }

    func captureP0Error(_ error: Any, _ source: String, _ context: [String: Any]) {
        Task { await sendError(error, source: source, context: context, priority: "P0") }
    }

    func captureP1Error(_ error: Any, _ source: String, _ context: [String: Any]) {
        Task { await sendError(error, source: source, context: context, priority: "P1") }
    }

    private func sendError(_ error: Any, source: String, context: [String: Any], priority: String) async {
        let domain = domainName()
        guard !domain.isEmpty else { return }

        var errorMessage = "Unknown error"
        if let err = error as? Error {
            errorMessage = err.localizedDescription
        } else if let str = error as? String {
            errorMessage = str
        }

        let info: [String: Any] = ["priority": priority, "source": source, "context": context, "message": errorMessage]
        if let enricher = enricher {
            enricher.capture(message: errorMessage, info: info)
            return
        }
        await route(basicEvent(errorMessage, priority: priority, source: source, context: context))
    }

    // Created once in init (lazy var is not thread-safe).
    private var enricher: SentryCocoaEnricher?

    private func onEnrichedEvent(_ event: [String: Any], _ info: [String: Any]) {
        let priority = info["priority"] as? String ?? "P1"
        var normalized = self.basicEvent(
            info["message"] as? String ?? "Unknown error",
            priority: priority,
            source: info["source"] as? String ?? "GENERAL",
            context: info["context"] as? [String: Any] ?? [:]
        )
        normalized["contexts"] = event["contexts"] ?? [String: Any]()
        let threads = (event["threads"] as? [String: Any])?["values"] as? [[String: Any]] ?? []
        let frames = (threads.first { $0["stacktrace"] != nil }?["stacktrace"] as? [String: Any])?["frames"] as? [Any] ?? []
        normalized["exceptions"] = [["type": "SpotcheckSdkError", "value": normalized["errorMessage"] ?? "", "stacktrace": Array(frames.suffix(10))]]
        normalized["eventId"] = event["event_id"] ?? ""
        Task { await self.route(normalized) }
    }

    private func basicEvent(_ errorMessage: String, priority: String, source: String, context: [String: Any]) -> [String: Any] {
        [
            "errorMessage": errorMessage,
            "tags": [
                "error_priority": priority,
                "severity": priority == "P0" ? "CRITICAL" : "HIGH",
                "errorType": source,
            ],
            "contexts": [String: Any](),
            "extra": context,
            "breadcrumbs": currentBreadcrumbs(),
            "timestamp": Date().timeIntervalSince1970,
            "platform": "ios",
        ]
    }

    // processSentryError first; direct POST to /sdkErrors as fallback.
    private func route(_ normalizedEvent: [String: Any]) async {
        if let bridge = executeBridge {
            let result = await bridge.execute("sentry.processSentryError", params: [
                "event": normalizedEvent,
                "sdkType": "ios",
                "sdkVersion": ExecuteBridge.spotcheckSdkVersion,
            ])
            if isProcessSentrySuccess(result) {
                return
            }
        }

        let tags = normalizedEvent["tags"] as? [String: Any] ?? [:]
        sendDirectToBackend(
            errorMessage: normalizedEvent["errorMessage"] as? String ?? "Unknown error",
            priority: tags["error_priority"] as? String ?? "P1",
            source: tags["errorType"] as? String ?? "GENERAL",
            extra: normalizedEvent["extra"] as? [String: Any] ?? [:],
            contexts: normalizedEvent["contexts"] as? [String: Any] ?? [:]
        )
    }

    private func sendDirectToBackend(
        errorMessage: String,
        priority: String,
        source: String,
        extra: [String: Any],
        contexts: [String: Any] = [:]
    ) {
        let domain = domainName()
        guard !domain.isEmpty,
              let url = URL(string: "https://\(domain)/api/internal/spotcheck/sdkErrors")
        else { return }

        let level = priority == "P0" ? "fatal" : "error"
        let body: [String: Any] = [
            "errorMessage": errorMessage,
            "sdkType": "ios",
            "sdkVersion": ExecuteBridge.spotcheckSdkVersion,
            "level": level,
            "tags": [
                "error_priority": priority,
                "severity": priority == "P0" ? "CRITICAL" : "HIGH",
                "errorType": source,
            ],
            "extra": extra,
            "breadcrumbs": currentBreadcrumbs(),
            "contexts": contexts.merging(["user": ["spotcheck_domain_name": domain]]) { _, new in new },
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    /// Bundled `processSentryError` returns `true` on success (`Bool` or `NSNumber` from JS).
    private func isProcessSentrySuccess(_ value: Any?) -> Bool {
        switch value {
        case let b as Bool:
            return b
        case let n as NSNumber:
            return n.boolValue
        default:
            return false
        }
    }
}

// MARK: - Keyboard Adapter (no-op on iOS — keyboard handled by OS)

struct KeyboardAdapter {
    static func pauseDefaultKeyboardBehavior() {}
    static func resumeDefaultKeyboardBehavior() {}
}

// MARK: - User Agent

#if canImport(UIKit)
/// Raw device facts; the backend builds the User-Agent from these.
func buildDeviceFacts() -> [String: Any] {
    let device = UIDevice.current
    return [
        "os": "ios",
        "osVersion": device.systemVersion,
        "deviceName": device.name,
        "model": device.model,
        "isTablet": device.userInterfaceIdiom == .pad,
    ]
}

func buildUserAgent() -> String {
    let device = UIDevice.current
    let version = device.systemVersion.replacingOccurrences(of: ".", with: "_")
    let model = device.model
    let isTablet = device.userInterfaceIdiom == .pad

    if isTablet {
        return "Mozilla/5.0 (iPad; CPU iOS \(version) like Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Version/16.0 Safari/537.36"
    }
    // Legacy format.
    return "Mozilla/5.0 (\(device.name) - \(model) CPU iOS \(version) like Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/537.36"
}

// MARK: - Visitor Info

func buildVisitorInfo() -> [String: Any] {
    let screen = UIScreen.main.bounds
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)

    return [
        "deviceType": "MOBILE",
        "operatingSystem": "iOS",
        "screenResolution": [
            "width": Int(screen.width),
            "height": Int(screen.height),
        ],
        "currentDate": formatter.string(from: Date()),
        "timezone": TimeZone.current.identifier,
    ]
}
#else
func buildUserAgent() -> String { return "Mozilla/5.0" }
func buildDeviceFacts() -> [String: Any] { return [:] }
func buildVisitorInfo() -> [String: Any] { return ["deviceType": "MOBILE", "operatingSystem": "iOS"] }
#endif
