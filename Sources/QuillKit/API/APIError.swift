import Foundation

public enum APIError: Error, LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, body: String)
    case decodingError(Error)
    case networkError(Error)
    case unexpectedHTML

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "That doesn't look like a valid site URL. Make sure it starts with https://."
        case .httpError(let code, let body): return Self.friendlyHTTPMessage(code: code, rawBody: body)
        case .decodingError: return "Quill couldn't read the response from WordPress. Try again, or check that your site is running a supported version."
        case .networkError(let e):
            let msg = e.localizedDescription
            if NetworkErrorHeuristics.isConnectivityFailure(msg) {
                return "Couldn't reach your site. Check the URL and make sure your site is online."
            }
            return msg
        case .unexpectedHTML: return "Your site returned a web page instead of data. Check that the Site URL is your WordPress home address, not a subfolder where WordPress is installed."
        }
    }

    private static func friendlyHTTPMessage(code: Int, rawBody: String) -> String {
        fputs("API HTTP \(code): \(rawBody)\n", stderr)
        switch code {
        case 400: return "WordPress didn't accept the request. Try re-entering your Application Password — make sure there are no extra spaces."
        case 401: return "Couldn't sign in. Double-check your username and Application Password."
        case 403: return "Your WordPress account doesn't have permission to do this. Check your role in WordPress Admin."
        case 404: return "That content doesn't exist anymore. It may have been deleted from WordPress."
        case 409: return "This post was edited somewhere else at the same time. Reload and try again."
        case 500...599: return "Something went wrong on your WordPress server. Try again in a moment."
        default: return "The request didn't go through (HTTP \(code)). Try again."
        }
    }
}
