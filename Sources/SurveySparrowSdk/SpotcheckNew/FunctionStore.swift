import Foundation

@available(iOS 15.0, *)
final class FunctionStore: ObservableObject {
    @Published private(set) var functions: [String: Any] = [:]
    @Published private(set) var isLoaded: Bool = false

    private static let nonFunctionKeys: Set<String> = ["componentSchemas", "config"]

    func load(from initResponse: [String: Any]) {
        // Load every function the backend sends (non-function keys skipped).
        var funcs: [String: Any] = [:]
        for (key, value) in initResponse where !Self.nonFunctionKeys.contains(key) {
            if let fn = value as? String, !fn.isEmpty {
                funcs[key] = fn
            } else if let group = value as? [String: Any] {
                let fns = group.compactMapValues { v -> String? in
                    guard let fn = v as? String, !fn.isEmpty else { return nil }
                    return fn
                }
                if !fns.isEmpty { funcs[key] = fns }
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
