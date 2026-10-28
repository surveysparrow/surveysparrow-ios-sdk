import Foundation

@available(iOS 15.0, *)
final class ComponentStore: ObservableObject {
    @Published private(set) var schemas: [String: Any] = [:]
    @Published private(set) var isLoaded: Bool = false

    func load(from initResponse: [String: Any]) {
        guard let componentSchemas = initResponse["componentSchemas"] as? [String: Any] else {
            return
        }
        DispatchQueue.main.async {
            self.schemas = componentSchemas
            self.isLoaded = true
        }
    }

    func getSchema(for key: String) -> [String: Any]? {
        return schemas[key] as? [String: Any]
    }
}
