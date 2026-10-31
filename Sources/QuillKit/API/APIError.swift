import Foundation

public enum APIError: Error, LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, body: String)
    case decodingError(Error)
    case networkError(Error)
    case unexpectedHTML
    case notConnected

    public var isFixedInSettings: Bool {
        switch self {
        case .invalidURL, .unexpectedHTML, .notConnected: return true
        case .httpError(let code, _): return [401, 403].contains(code) || (code == 400 && wordPressError == nil)
        case .networkError(let e):
            return NetworkFailure.isConnectivity(e) && (e as? URLError)?.code != .notConnectedToInternet
        case .decodingError: return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "That doesn't look like a valid site URL. Make sure it uses HTTPS."
        case .httpError(let code, let body):
            let friendly = Self.friendlyHTTPMessage(code: code, rawBody: body)
            guard code == 400, let message = wordPressError?.message else { return friendly }
            return "WordPress didn't accept the request: \(message)"
        case .decodingError: return "WordPress sent a reply Quill couldn't read. A plugin or theme may be adding text to it."
        case .networkError(let e):
            let msg = e.localizedDescription
            if (e as? URLError)?.code == .notConnectedToInternet {
                return "You're offline. Connect to the internet and try again."
            }
            if NetworkFailure.isConnectivity(e) {
                return "Couldn't reach your site. Check the URL and make sure your site is online."
            }
            return msg
        case .unexpectedHTML: return "Your site returned a web page instead of data. Check that the Site URL is your WordPress home address, not a subfolder where WordPress is installed."
        case .notConnected: return "Connect a WordPress site in Settings first."
        }
    }

    /// The term WordPress refused to create because one with the same slug exists.
    public var existingTermID: Int? {
        guard let error = wordPressError, error.code == "term_exists" else { return nil }
        return error.termID
    }

    private struct WordPressError: Decodable {
        let code: String
        let message: String
        let termID: Int?

        private enum CodingKeys: String, CodingKey { case code, message, data }
        private enum DataKeys: String, CodingKey { case termID = "term_id" }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(String.self, forKey: .code)
            message = try c.decode(String.self, forKey: .message)
            termID = try? c.nestedContainer(keyedBy: DataKeys.self, forKey: .data).decode(Int.self, forKey: .termID)
        }
    }

    private var wordPressError: WordPressError? {
        guard case .httpError(_, let body) = self,
              let error = try? JSONDecoder().decode(WordPressError.self, from: Data(body.utf8)),
              !error.message.isEmpty
        else { return nil }
        return error
    }

    private static func friendlyHTTPMessage(code: Int, rawBody: String) -> String {
        fputs("API HTTP \(code): \(rawBody)\n", stderr)
        switch code {
        case 400: return "WordPress didn't accept the request. Try re-entering your Application Password and check it has no extra spaces."
        case 401: return "Couldn't sign in. Double-check your username and Application Password."
        case 403: return "Your WordPress account doesn't have permission to do this. Check your role in WordPress Admin."
        case 404: return "That content doesn't exist anymore. It may have been deleted from WordPress."
        case 409: return "This post was edited somewhere else at the same time. Reload and try again."
        case 500...599: return "Something went wrong on your WordPress server. Try again in a moment."
        default: return "The request didn't go through (HTTP \(code)). Try again."
        }
    }
}
