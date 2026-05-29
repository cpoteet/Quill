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
        case .httpError(let code, let body): return Self.friendlyHTTPMessage(code: code, rawBody: body)
        case .decodingError(let e): return "Decode error: \(e.localizedDescription)"
        case .networkError(let e): return e.localizedDescription
        case .noCredentials: return "No credentials saved. Open Preferences to add your site."
        }
    }

    private static func friendlyHTTPMessage(code: Int, rawBody: String) -> String {
        // Log the raw body for debugging without surfacing it to the user.
        fputs("API HTTP \(code): \(rawBody)\n", stderr)
        switch code {
        case 400: return "WordPress rejected the request — your Application Password may be incorrectly formatted. Open Blog Settings to check."
        case 401: return "Authentication failed — your username or Application Password may be wrong. Open Blog Settings to fix this."
        case 403: return "You don't have permission to perform this action."
        case 404: return "The requested content was not found on the server."
        case 409: return "A conflict occurred — the post may have been modified elsewhere."
        case 500...599: return "Server error (\(code)). Try again in a moment."
        default: return "Request failed (HTTP \(code))."
        }
    }
}
