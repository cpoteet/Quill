import Foundation

public enum APIError: Error, LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, body: String)
    case decodingError(Error)
    case networkError(Error)
    case noCredentials

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid site URL."
        case .httpError(let code, let body): return "HTTP \(code): \(body)"
        case .decodingError(let e): return "Decode error: \(e.localizedDescription)"
        case .networkError(let e): return e.localizedDescription
        case .noCredentials: return "No credentials saved. Open Preferences to add your site."
        }
    }
}
