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

// MARK: - Sentry Adapter
// Matches Expo/Android: try `execute("sentry.processSentryError", …)` first, then direct POST to `sdkErrors`.

@available(iOS 15.0, *)
final class SentryAdapter {
    private let domainName: () -> String

    weak var executeBridge: ExecuteBridge?

    init(domainName: @escaping () -> String) {
        self.domainName = domainName
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

        let normalizedEvent: [String: Any] = [
            "errorMessage": errorMessage,
            "tags": [
                "error_priority": priority,
                "severity": priority == "P0" ? "CRITICAL" : "HIGH",
                "errorType": source,
            ],
            "contexts": context,
        ]

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

        sendDirectToBackend(
            errorMessage: errorMessage,
            priority: priority,
            source: source,
            extra: context
        )
    }

    private func sendDirectToBackend(
        errorMessage: String,
        priority: String,
        source: String,
        extra: [String: Any]
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
            "contexts": [
                "user": [
                    "spotcheck_domain_name": domain,
                ],
            ],
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
func buildUserAgent() -> String {
    let device = UIDevice.current
    let version = device.systemVersion.replacingOccurrences(of: ".", with: "_")
    let model = device.model
    let isTablet = device.userInterfaceIdiom == .pad

    if isTablet {
        return "Mozilla/5.0 (iPad; CPU iOS \(version) like Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Version/16.0 Safari/537.36"
    }
    return "Mozilla/5.0 (\(model); CPU iPhone OS \(version) like Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/537.36"
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
func buildVisitorInfo() -> [String: Any] { return ["deviceType": "MOBILE", "operatingSystem": "iOS"] }
#endif
