import Foundation

// MARK: - Request types

private struct AnthropicRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: [SystemBlock]
    let messages: [AnthropicMessage]
    let tools: [AnthropicTool]?

    enum CodingKeys: String, CodingKey {
        case model, system, messages, tools
        case maxTokens = "max_tokens"
    }
}

private struct SystemBlock: Encodable {
    let type: String = "text"
    let text: String
    let cacheControl: CacheControl

    enum CodingKeys: String, CodingKey {
        case type, text
        case cacheControl = "cache_control"
    }
}

private struct CacheControl: Encodable {
    let type: String = "ephemeral"
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: String
}

private struct AnthropicTool: Encodable {
    let type: String
    let name: String
}

// MARK: - Response types

private struct AnthropicResponse: Decodable {
    let content: [ContentBlock]
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}

private struct ContentBlock: Decodable {
    let type: String
    let text: String?
}

// MARK: - Errors

public enum AnthropicError: Error, LocalizedError, Equatable {
    case httpError(Int, String)
    case noTextContent
    case invalidResponse
    case networkError(Error)

    public static func == (lhs: AnthropicError, rhs: AnthropicError) -> Bool {
        switch (lhs, rhs) {
        case (.httpError(let lCode, let lMsg), .httpError(let rCode, let rMsg)):
            return lCode == rCode && lMsg == rMsg
        case (.noTextContent, .noTextContent): return true
        case (.invalidResponse, .invalidResponse): return true
        case (.networkError(let lError), .networkError(let rError)):
            return String(describing: lError) == String(describing: rError)
        default: return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .httpError(let code, let msg): return "API error \(code): \(msg)"
        case .noTextContent: return "Claude returned no text content."
        case .invalidResponse: return "Unexpected response from API."
        case .networkError(let error):
            let msg = error.localizedDescription
            if NetworkErrorHeuristics.isConnectivityFailure(msg) {
                return "Couldn't reach the Anthropic API. Check your internet connection and try again."
            }
            return msg
        }
    }
}

// MARK: - Client

public struct AnthropicClient {
    public let apiKey: String
    private let session: URLSession

    private static let sharedSession: URLSession = URLSession(configuration: .ephemeral)

    public init(apiKey: String, session: URLSession? = nil) {
        self.apiKey = apiKey
        self.session = session ?? Self.sharedSession
    }

    public struct Result {
        public let text: String
        /// True when the API stopped due to the token budget rather than natural completion.
        public let truncated: Bool
    }

    /// Sends a single-turn request and returns the text response plus a truncation flag.
    /// - Parameters:
    ///   - userMessage: The user-turn content.
    ///   - systemPrompt: System instructions (cached with ephemeral cache_control).
    ///   - useWebSearch: Whether to include the web_search tool.
    ///   - maxTokens: Maximum output tokens (default 4096). Raise for long-form generation.
    ///   - model: Model ID (default claude-haiku-4-5).
    public func complete(
        userMessage: String,
        systemPrompt: String,
        useWebSearch: Bool,
        maxTokens: Int = 4096,
        model: String = "claude-haiku-4-5"
    ) async throws -> Result {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let tools: [AnthropicTool]? = useWebSearch
            ? [AnthropicTool(type: "web_search_20250305", name: "web_search")]
            : nil

        let body = AnthropicRequest(
            model: model,
            maxTokens: maxTokens,
            system: [SystemBlock(text: systemPrompt, cacheControl: CacheControl())],
            messages: [AnthropicMessage(role: "user", content: userMessage)],
            tools: tools
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, urlResponse): (Data, URLResponse)
        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw AnthropicError.networkError(error)
        }

        guard let http = urlResponse as? HTTPURLResponse else { throw AnthropicError.invalidResponse }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
            throw AnthropicError.httpError(http.statusCode, msg)
        }

        let response = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        // Web search fragments the reply across many small text blocks (one per citation span).
        // Join them all — the first block starts with "TITLE: …\n\nCONTENT:\n" and subsequent
        // blocks contain the inline cited text segments that make up the rest of the post body.
        let text = response.content
            .filter { $0.type == "text" }
            .compactMap { $0.text }
            .joined()
        guard !text.isEmpty else {
            throw AnthropicError.noTextContent
        }
        return Result(text: text, truncated: response.stopReason == "max_tokens")
    }
}
