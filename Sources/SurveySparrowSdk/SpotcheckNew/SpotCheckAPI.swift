import Foundation

@available(iOS 15.0, *)
final class SpotCheckAPI {
    private let domainName: String

    init(domainName: String) {
        self.domainName = domainName
    }

    func fetchInitData() async throws -> [String: Any] {
        guard let url = URL(string: "https://\(domainName)/api/internal/spotcheck/mobile/init?framework=ios") else {
            throw SpotCheckError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SpotCheckError.networkError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SpotCheckError.decodingError
        }

        return json
    }
}

enum SpotCheckError: Error, LocalizedError {
    case invalidURL
    case networkError
    case decodingError
    case executionError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .networkError: return "Network error"
        case .decodingError: return "Failed to decode response"
        case .executionError(let msg): return "Execution error: \(msg)"
        }
    }
}
