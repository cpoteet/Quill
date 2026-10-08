import Foundation

// MARK: - Request options

public struct WebSearchUse: Sendable {
    public var maxUses: Int
    /// The tool version that last worked for this model, tried before any other.
    public var knownTool: String?

    public init(maxUses: Int, knownTool: String? = nil) {
        self.maxUses = maxUses
        self.knownTool = knownTool
    }
}

// jsonSchema holds only JSON property-list values, which are immutable once built.
public struct CompletionOptions: @unchecked Sendable {
    public var modelID: String
    public var model: AIModelInfo?
    public var reasoning: AIReasoning
    public var baseMaxTokens: Int
    public var webSearch: WebSearchUse?
    public var jsonSchema: [String: Any]?

    public init(modelID: String, model: AIModelInfo?, reasoning: AIReasoning, baseMaxTokens: Int = 4096,
                webSearch: WebSearchUse? = nil, jsonSchema: [String: Any]? = nil) {
        self.modelID = modelID
        self.model = model
        self.reasoning = reasoning
        self.baseMaxTokens = baseMaxTokens
        self.webSearch = webSearch
        self.jsonSchema = jsonSchema
    }

    public init(settings: AISettings, baseMaxTokens: Int = 4096, webSearch: WebSearchUse? = nil, jsonSchema: [String: Any]? = nil) {
        self.init(modelID: settings.resolvedModelID(), model: settings.resolvedModel(), reasoning: settings.normalizedReasoning(),
                  baseMaxTokens: baseMaxTokens, webSearch: webSearch, jsonSchema: jsonSchema)
    }
}

// MARK: - Models API types

private struct ModelsPage: Decodable {
    let data: [ModelObject]
    let hasMore: Bool?
    let lastID: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case lastID = "last_id"
    }
}

private struct Supported: Decodable {
    let supported: Bool?
}

private struct ModelObject: Decodable {
    let id: String
    let displayName: String
    let createdAt: Date
    let maxTokens: Int?
    let line: String?
    let capabilities: Capabilities?

    struct Capabilities: Decodable {
        let effort: Effort?
        let serverTools: ServerTools?
        let thinking: Thinking?

        enum CodingKeys: String, CodingKey {
            case effort, thinking
            case serverTools = "server_tools"
        }
    }

    struct Effort: Decodable {
        let low, medium, high, xhigh, max: Supported?

        var levels: [String] {
            [("low", low), ("medium", medium), ("high", high), ("xhigh", xhigh), ("max", max)]
                .filter { $0.1?.supported == true }.map(\.0)
        }
    }

    struct ServerTools: Decodable {
        let webSearch: Supported?
        enum CodingKeys: String, CodingKey { case webSearch = "web_search" }
    }

    struct Thinking: Decodable {
        let types: [String: Supported]?
    }

    enum CodingKeys: String, CodingKey {
        case id, line, capabilities
        case displayName = "display_name"
        case createdAt = "created_at"
        case maxTokens = "max_tokens"
    }

    var info: AIModelInfo {
        let thinking = capabilities?.thinking?.types ?? [:]
        return AIModelInfo(
            id: id,
            displayName: displayName,
            createdAt: createdAt,
            maxTokens: maxTokens ?? 4096,
            line: line,
            supportsAdaptiveThinking: thinking["adaptive"]?.supported == true,
            supportsEnabledThinking: thinking["enabled"]?.supported == true,
            effortLevels: capabilities?.effort?.levels ?? [],
            supportsWebSearch: capabilities?.serverTools?.webSearch?.supported == true
        )
    }
}

// MARK: - Errors

public enum AnthropicError: Error, LocalizedError, Equatable {
    case httpError(Int, String)
    case noTextContent
    case invalidResponse
    case networkError(Error)
    case invalidKey
    case refused
    /// A reply that hit `max_tokens` before any usable text, or a structured reply that can't be parsed because it was cut.
    case cutOff(webSearchTool: String?)

    public static func == (lhs: AnthropicError, rhs: AnthropicError) -> Bool {
        switch (lhs, rhs) {
        case (.httpError(let lCode, let lMsg), .httpError(let rCode, let rMsg)):
            return lCode == rCode && lMsg == rMsg
        case (.noTextContent, .noTextContent): return true
        case (.invalidResponse, .invalidResponse): return true
        case (.invalidKey, .invalidKey): return true
        case (.refused, .refused): return true
        case (.cutOff(let l), .cutOff(let r)): return l == r
        case (.networkError(let lError), .networkError(let rError)):
            return String(describing: lError) == String(describing: rError)
        default: return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .httpError(401, _): return AnthropicError.invalidKey.errorDescription
        case .httpError(429, _): return "You've hit Anthropic's rate limit. Wait a minute and try again."
        case .httpError(let code, _) where code >= 500:
            return "Anthropic's API is busy or having problems. Try again in a moment."
        case .httpError(let code, let body):
            if let message = Self.apiMessage(in: body) {
                return "Anthropic didn't accept the request: \(message)"
            }
            return "Anthropic returned an error (HTTP \(code)). Try again."
        case .noTextContent: return "Claude returned no text content."
        case .invalidResponse: return "Unexpected response from API."
        case .invalidKey: return "Anthropic didn't accept this key."
        case .refused: return "Claude declined this request."
        case .cutOff: return "Claude's reply was cut off before it finished. A lower reasoning level leaves more room for the answer."
        case .networkError(let error):
            let msg = error.localizedDescription
            if NetworkFailure.isConnectivity(error) {
                return "Couldn't reach the Anthropic API. Check your internet connection and try again."
            }
            return msg
        }
    }

    private static func apiMessage(in body: String) -> String? {
        struct Envelope: Decodable {
            struct Detail: Decodable { let message: String }
            let error: Detail
        }
        guard let data = body.data(using: .utf8),
              let message = try? JSONDecoder().decode(Envelope.self, from: data).error.message,
              !message.isEmpty
        else { return nil }
        return message
    }
}

// MARK: - Client

public struct AnthropicClient: Sendable {
    public let apiKey: String
    private let session: URLSession

    static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        // Responses don't stream, so nothing arrives until a long generation is done.
        config.timeoutIntervalForRequest = 600
        return URLSession(configuration: config)
    }()

    private static let enabledBudgets = ["low": 2048, "medium": 8192, "high": 16384]
    private static let adaptiveAllowance = 16000

    public init(apiKey: String, session: URLSession? = nil) {
        self.apiKey = apiKey
        self.session = session ?? Self.sharedSession
    }

    public struct Result: Sendable {
        public let text: String
        /// True when the API stopped due to the token budget rather than natural completion.
        public let truncated: Bool
        /// The web search tool type that was sent and accepted; nil when none was sent.
        public let webSearchTool: String?
    }

    /// Newest first. A future version goes at the front.
    public static let webSearchVersions = ["web_search_20260318", "web_search_20260209", "web_search_20250305"]
    private static let maxContinuations = 3

    static func requestBody(system: String, user: String, options: CompletionOptions, webSearchTool: String?,
                            continuation: [[String: Any]] = []) -> [String: Any] {
        var body: [String: Any] = [
            "model": options.modelID,
            "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": user]] + continuation,
        ]
        var outputConfig: [String: Any] = [:]
        var maxTokens = options.baseMaxTokens
        if let model = options.model {
            if model.supportsAdaptiveThinking {
                body["thinking"] = ["type": "adaptive"]
                if case .level(let level) = options.reasoning, model.effortLevels.contains(level) {
                    outputConfig["effort"] = level
                }
                maxTokens += adaptiveAllowance
            } else if model.supportsEnabledThinking, case .level(let level) = options.reasoning,
                      let budget = enabledBudgets[level] {
                body["thinking"] = ["type": "enabled", "budget_tokens": budget]
                maxTokens += budget
            }
            maxTokens = min(maxTokens, model.maxTokens)
        }
        body["max_tokens"] = maxTokens
        if let schema = options.jsonSchema {
            outputConfig["format"] = ["type": "json_schema", "schema": schema]
        }
        if !outputConfig.isEmpty { body["output_config"] = outputConfig }
        if let search = options.webSearch, let tool = webSearchTool {
            body["tools"] = [["type": tool, "name": "web_search", "max_uses": search.maxUses, "allowed_callers": ["direct"]]]
        }
        return body
    }

    /// Sends one request, trying web search versions newest first until the API accepts one.
    public func complete(userMessage: String, systemPrompt: String, options: CompletionOptions) async throws -> Result {
        guard let search = options.webSearch else {
            return try await run(userMessage: userMessage, systemPrompt: systemPrompt, options: options, tool: nil)
        }
        var candidates = Self.webSearchVersions
        if let known = search.knownTool {
            if let index = candidates.firstIndex(of: known) {
                candidates = Array(candidates[index...])
            } else {
                candidates.insert(known, at: 0)
            }
        }
        for (index, tool) in candidates.enumerated() {
            do {
                return try await run(userMessage: userMessage, systemPrompt: systemPrompt, options: options, tool: tool)
            } catch AnthropicError.httpError(400, let body) where index < candidates.count - 1 && Self.rejectsTool(body, tool) {
                continue
            }
        }
        throw AnthropicError.invalidResponse
    }

    /// JSON with each schema's `properties` written in its `required` order, which is the order Claude fills them in.
    static func orderedJSON(_ value: Any, propertyOrder: [String]? = nil) throws -> Data {
        guard let object = value as? [String: Any] else {
            if let array = value as? [Any] {
                var data = Data("[".utf8)
                for (index, element) in array.enumerated() {
                    if index > 0 { data.append(Data(",".utf8)) }
                    data.append(try orderedJSON(element))
                }
                data.append(Data("]".utf8))
                return data
            }
            return try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
        }
        let order = propertyOrder ?? []
        let keys = order.filter { object[$0] != nil } + object.keys.filter { !order.contains($0) }.sorted()
        var data = Data("{".utf8)
        for (index, key) in keys.enumerated() {
            if index > 0 { data.append(Data(",".utf8)) }
            data.append(try JSONSerialization.data(withJSONObject: key, options: .fragmentsAllowed))
            data.append(Data(":".utf8))
            let childOrder = key == "properties" ? object["required"] as? [String] : nil
            data.append(try orderedJSON(object[key]!, propertyOrder: childOrder))
        }
        data.append(Data("}".utf8))
        return data
    }

    /// Matches the 400 the API returns for a tool type it doesn't accept, and nothing else.
    static func rejectsTool(_ body: String, _ tool: String) -> Bool {
        body.contains("'\(tool)'") && body.contains("does not match any of the expected tags")
    }

    private func run(userMessage: String, systemPrompt: String, options: CompletionOptions, tool: String?) async throws -> Result {
        var continuation: [[String: Any]] = []
        var texts: [String] = []
        var stopReason: String?
        for _ in 0...Self.maxContinuations {
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try Self.orderedJSON(Self.requestBody(
                system: systemPrompt, user: userMessage, options: options, webSearchTool: tool, continuation: continuation))

            let (data, http) = try await send(request)
            guard http.statusCode == 200 else {
                throw AnthropicError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "unknown")
            }
            guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = response["content"] as? [[String: Any]]
            else { throw AnthropicError.invalidResponse }
            stopReason = response["stop_reason"] as? String
            if stopReason == "refusal" { throw AnthropicError.refused }
            // Web search splits the reply into one text block per citation span, so join every text block.
            texts.append(content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined())
            guard stopReason == "pause_turn" else { break }
            continuation.append(["role": "assistant", "content": content])
        }
        // Structured output arrives whole in the last response; earlier ones hold only search narration.
        let text = options.jsonSchema == nil ? texts.joined() : (texts.last ?? "")
        if stopReason == "max_tokens" && (text.isEmpty || options.jsonSchema != nil) {
            throw AnthropicError.cutOff(webSearchTool: tool)
        }
        guard !text.isEmpty else { throw AnthropicError.noTextContent }
        return Result(text: text, truncated: stopReason == "max_tokens", webSearchTool: tool)
    }

    public func verifyKey() async throws {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1")!)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, http) = try await send(request)
        if http.statusCode == 401 { throw AnthropicError.invalidKey }
        guard http.statusCode == 200 else {
            throw AnthropicError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "unknown")
        }
    }

    public func listModels() async throws -> [AIModelInfo] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var models: [AIModelInfo] = []
        var afterID: String?
        repeat {
            var components = URLComponents(string: "https://api.anthropic.com/v1/models")!
            components.queryItems = [URLQueryItem(name: "limit", value: "100")]
                + (afterID.map { [URLQueryItem(name: "after_id", value: $0)] } ?? [])
            var request = URLRequest(url: components.url!)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            let (data, http) = try await send(request)
            if http.statusCode == 401 { throw AnthropicError.invalidKey }
            guard http.statusCode == 200 else {
                throw AnthropicError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "unknown")
            }
            let page = try decoder.decode(ModelsPage.self, from: data)
            models += page.data.map(\.info)
            afterID = page.hasMore == true ? page.lastID : nil
        } while afterID != nil
        return models.sorted { $0.createdAt > $1.createdAt }
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
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
        return (data, http)
    }
}
