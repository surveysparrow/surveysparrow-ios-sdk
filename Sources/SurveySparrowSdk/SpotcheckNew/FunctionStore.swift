import Foundation

@available(iOS 15.0, *)
final class FunctionStore: ObservableObject {
    @Published private(set) var functions: [String: Any] = [:]
    @Published private(set) var isLoaded: Bool = false

    func load(from initResponse: [String: Any]) {
        var funcs: [String: Any] = [:]

        let topLevelKeys = [
            "initializeSpotcheckComponent", "trackScreen", "trackEvent",
            "handleNavigationChange", "handleExitAnimationComplete",
        ]
        for key in topLevelKeys {
            if let val = initResponse[key] as? String {
                funcs[key] = val
            }
        }

        let groupedKeys: [String: [String]] = [
            "webviewComponent": ["handleWebViewMessage", "handleWebViewError", "handleWebViewInjection",
                                 "classicWebViewRefCallback", "chatWebViewRefCallback"],
            "closeButton": ["handleCloseButton", "getCloseButtonStyles"],
            "wrapper": ["getWrapperStyles"],
            "spotCheckButton": ["handleSpotCheckButtonPress", "handleSideTabLayout", "getSpotCheckButtonStyles"],
            "sentry": ["processSentryError"],
        ]

        for (groupKey, subKeys) in groupedKeys {
            if let group = initResponse[groupKey] as? [String: Any] {
                var groupDict: [String: Any] = [:]
                for subKey in subKeys {
                    if let val = group[subKey] as? String {
                        groupDict[subKey] = val
                    }
                }
                funcs[groupKey] = groupDict
            }
        }

        self.functions = funcs
        self.isLoaded = true
    }

    func resolve(_ functionName: String) -> String? {
        let parts = functionName.split(separator: ".").map(String.init)
        var current: Any = functions
        for part in parts {
            guard let dict = current as? [String: Any], let next = dict[part] else {
                return nil
            }
            current = next
        }
        return current as? String
    }
}
