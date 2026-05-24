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
    let stopReason: String

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

public enum AnthropicError: LocalizedError {
    case httpError(Int, String)
    case noTextContent
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .httpError(let code, let msg): return "API error \(code): \(msg)"
        case .noTextContent: return "Claude returned no text content."
        case .invalidResponse: return "Unexpected response from API."
        }
    }
}

// MARK: - Client

public struct AnthropicClient {
    public let apiKey: String

    private static let session: URLSession = URLSession(configuration: .ephemeral)

    /// Sends a single-turn request and returns the full text response.
    /// - Parameters:
    ///   - userMessage: The user-turn content.
    ///   - systemPrompt: System instructions (cached with ephemeral cache_control).
    ///   - useWebSearch: Whether to include the web_search tool.
    public func complete(
        userMessage: String,
        systemPrompt: String,
        useWebSearch: Bool
    ) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var betas = ["prompt-caching-2024-07-31"]
        if useWebSearch { betas.append("web-search-2025-03-05") }
        request.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")

        let tools: [AnthropicTool]? = useWebSearch
            ? [AnthropicTool(type: "web_search_20250305", name: "web_search")]
            : nil

        let body = AnthropicRequest(
            model: "claude-haiku-4-5",
            maxTokens: 4096,
            system: [SystemBlock(text: systemPrompt, cacheControl: CacheControl())],
            messages: [AnthropicMessage(role: "user", content: userMessage)],
            tools: tools
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, urlResponse) = try await Self.session.data(for: request)

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
        return text
    }
}
