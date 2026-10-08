import Foundation
import Testing
@testable import QuillKit

@Suite(.serialized) struct AnthropicClientTests {
    var client: AnthropicClient
    var capturedRequest: URLRequest?

    init() {
        AnthropicMockURLProtocol.requestHandler = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AnthropicMockURLProtocol.self]
        let session = URLSession(configuration: config)
        client = AnthropicClient(apiKey: "test-key", session: session)
    }

    // MARK: - Helpers

    private func makeHandler(
        status: Int = 200,
        body: Data
    ) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, body)
        }
    }

    private func successBody(textBlocks: [String]) throws -> Data {
        let blocks = textBlocks
            .map { #"{"type":"text","text":"\#($0)"}"# }
            .joined(separator: ",")
        let json = #"{"content":[\#(blocks)],"stop_reason":"end_turn"}"#
        return json.data(using: .utf8)!
    }

    private func completeDefault(useWebSearch: Bool = false) async throws -> AnthropicClient.Result {
        try await client.complete(
            userMessage: "hello",
            systemPrompt: "be helpful",
            options: CompletionOptions(modelID: "claude-haiku-5-5", model: nil, reasoning: .modelDefault,
                                       webSearch: useWebSearch ? WebSearchUse(maxUses: 8) : nil)
        )
    }

    private func body(_ model: AIModelInfo?, _ reasoning: AIReasoning, base: Int = 4096,
                      webSearch: WebSearchUse? = nil, schema: [String: Any]? = nil, tool: String? = nil) -> [String: Any] {
        AnthropicClient.requestBody(
            system: "sys", user: "hi",
            options: CompletionOptions(modelID: model?.id ?? "claude-haiku-5-5", model: model, reasoning: reasoning,
                                       baseMaxTokens: base, webSearch: webSearch, jsonSchema: schema),
            webSearchTool: tool
        )
    }

    private func ns(_ value: Any?) -> NSObject? { value as? NSObject }

    // MARK: - Request body

    @Test func adaptiveModelDefault() {
        let b = body(haiku55, .modelDefault)
        #expect(ns(b["thinking"]) == ns(["type": "adaptive"]))
        #expect(b["output_config"] == nil)
        #expect(b["max_tokens"] as? Int == 4096 + 16000)
        #expect(b["model"] as? String == "claude-haiku-5-5")
    }

    @Test func adaptiveLevel() {
        let b = body(haiku55, .level("high"))
        #expect(ns(b["thinking"]) == ns(["type": "adaptive"]))
        #expect((b["output_config"] as? [String: Any])?["effort"] as? String == "high")
    }

    @Test func enabledOnlyOff() {
        let b = body(haiku45, .off)
        #expect(b["thinking"] == nil && b["output_config"] == nil)
        #expect(b["max_tokens"] as? Int == 4096)
    }

    @Test func enabledOnlyMedium() {
        let b = body(haiku45, .level("medium"))
        #expect(ns(b["thinking"]) == ns(["type": "enabled", "budget_tokens": 8192]))
        #expect(b["output_config"] == nil)
        #expect(b["max_tokens"] as? Int == 4096 + 8192)
    }

    @Test func enabledOnlyLowAndHighBudgets() {
        #expect((body(haiku45, .level("low"))["thinking"] as? [String: Any])?["budget_tokens"] as? Int == 2048)
        #expect((body(haiku45, .level("high"))["thinking"] as? [String: Any])?["budget_tokens"] as? Int == 16384)
    }

    @Test func requestForUnknownModelOmitsThinking() {
        for reasoning in [AIReasoning.off, .modelDefault, .level("high")] {
            let b = body(nil, reasoning)
            #expect(b["thinking"] == nil && b["output_config"] == nil)
            #expect(b["max_tokens"] as? Int == 4096)
            #expect(b["model"] as? String == "claude-haiku-5-5")
        }
    }

    @Test func neverSendsDisabledThinking() {
        let reasonings: [AIReasoning] = [.off, .modelDefault] + ["low", "medium", "high", "xhigh", "max"].map(AIReasoning.level)
        for model in [haiku45, haiku55, sonnet55] {
            for reasoning in reasonings {
                let thinking = body(model, reasoning)["thinking"] as? [String: Any]
                #expect(thinking?["type"] as? String != "disabled")
            }
        }
    }

    @Test func maxTokensCappedAtModelLimit() {
        var small = haiku55; small.maxTokens = 20000
        #expect(body(small, .modelDefault, base: 16384)["max_tokens"] as? Int == 20000)
    }

    @Test func jsonSchemaGoesInOutputConfigFormat() {
        let schema: [String: Any] = ["type": "object", "properties": ["html": ["type": "string"]]]
        let config = body(haiku55, .level("low"), schema: schema)["output_config"] as? [String: Any]
        #expect(ns(config?["format"]) == ns(["type": "json_schema", "schema": schema]))
        #expect(config?["effort"] as? String == "low")
        let unknown = body(nil, .off, schema: schema)["output_config"] as? [String: Any]
        #expect(ns(unknown?["format"]) == ns(["type": "json_schema", "schema": schema]))
    }

    @Test func webSearchToolIsDirect() {
        let b = body(haiku55, .modelDefault, webSearch: WebSearchUse(maxUses: 8), tool: "web_search_20260318")
        #expect(ns(b["tools"]) == ns([["type": "web_search_20260318", "name": "web_search", "max_uses": 8, "allowed_callers": ["direct"]]]))
        #expect(body(haiku55, .modelDefault)["tools"] == nil)
    }

    @Test func systemAndUserMessage() {
        let b = body(haiku55, .modelDefault)
        let system = (b["system"] as? [[String: Any]])?.first
        #expect(system?["text"] as? String == "sys")
        #expect(ns(system?["cache_control"]) == ns(["type": "ephemeral"]))
        #expect(ns(b["messages"]) == ns([["role": "user", "content": "hi"]]))
    }

    @Test func optionsFromSettingsUseResolvedModelAndNormalizedReasoning() {
        var s = AISettings(); s.models = [haiku45, haiku55]; s.model = "claude-haiku-4-5"; s.reasoning = .modelDefault
        let o = CompletionOptions(settings: s, baseMaxTokens: 100)
        #expect(o.modelID == "claude-haiku-4-5" && o.model == haiku45 && o.reasoning == .off && o.baseMaxTokens == 100)
    }

    @Test func refusalThrowsRefused() async {
        AnthropicMockURLProtocol.requestHandler = makeHandler(body: Data(#"{"content":[{"type":"text","text":"partial"}],"stop_reason":"refusal"}"#.utf8))
        await #expect(throws: AnthropicError.refused) { _ = try await completeDefault() }
        #expect(AnthropicError.refused.errorDescription == "Claude declined this request.")
    }

    @Test func textIsJoinedFromTextBlocksOnly() async throws {
        let json = #"{"content":[{"type":"thinking","thinking":"hmm","signature":"x"},{"type":"text","text":"a"},{"type":"text","text":"b"}],"stop_reason":"end_turn"}"#
        AnthropicMockURLProtocol.requestHandler = makeHandler(body: Data(json.utf8))
        #expect(try await completeDefault().text == "ab")
    }

    @Test func sharedSessionTimeoutIs600() {
        #expect(AnthropicClient.sharedSession.configuration.timeoutIntervalForRequest == 600)
    }

    // MARK: - Request headers

    @Test func requestHasApiKeyHeader() async throws {
        var captured: URLRequest?
        AnthropicMockURLProtocol.requestHandler = { req in
            captured = req
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try self.successBody(textBlocks: ["hi"])
            )
        }
        _ = try await completeDefault()
        #expect(captured?.value(forHTTPHeaderField: "x-api-key") == "test-key")
    }

    @Test func requestHasVersionHeader() async throws {
        var captured: URLRequest?
        AnthropicMockURLProtocol.requestHandler = { req in
            captured = req
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try self.successBody(textBlocks: ["hi"])
            )
        }
        _ = try await completeDefault()
        #expect(captured?.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    }

    @Test func requestHasContentTypeHeader() async throws {
        var captured: URLRequest?
        AnthropicMockURLProtocol.requestHandler = { req in
            captured = req
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try self.successBody(textBlocks: ["hi"])
            )
        }
        _ = try await completeDefault()
        #expect(captured?.value(forHTTPHeaderField: "content-type") == "application/json")
    }

    // MARK: - Beta headers

    @Test func noBetaHeaderSent() async throws {
        // Prompt caching and web search are both GA — no anthropic-beta header needed.
        var captured: URLRequest?
        AnthropicMockURLProtocol.requestHandler = { req in
            captured = req
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try self.successBody(textBlocks: ["hi"])
            )
        }
        _ = try await completeDefault(useWebSearch: true)
        #expect(captured?.value(forHTTPHeaderField: "anthropic-beta") == nil)
    }

    // MARK: - Tools array

    @Test func toolsAbsentWhenWebSearchOff() async throws {
        var captured: URLRequest?
        AnthropicMockURLProtocol.requestHandler = { req in
            captured = req
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try self.successBody(textBlocks: ["hi"])
            )
        }
        _ = try await completeDefault(useWebSearch: false)
        let body = try JSONSerialization.jsonObject(with: captured!.httpBody!) as! [String: Any]
        #expect(body["tools"] == nil)
    }

    @Test func toolsPresentWhenWebSearchOn() async throws {
        var captured: URLRequest?
        AnthropicMockURLProtocol.requestHandler = { req in
            captured = req
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try self.successBody(textBlocks: ["hi"])
            )
        }
        _ = try await completeDefault(useWebSearch: true)
        let body = try JSONSerialization.jsonObject(with: captured!.httpBody!) as! [String: Any]
        let tools = body["tools"] as? [[String: Any]]
        #expect(tools?.first?["name"] as? String == "web_search")
    }

    // MARK: - Cache control on system block

    @Test func systemBlockHasCacheControlEphemeral() async throws {
        var captured: URLRequest?
        AnthropicMockURLProtocol.requestHandler = { req in
            captured = req
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try self.successBody(textBlocks: ["hi"])
            )
        }
        _ = try await completeDefault()
        let body = try JSONSerialization.jsonObject(with: captured!.httpBody!) as! [String: Any]
        let system = (body["system"] as? [[String: Any]])?.first
        let cacheControl = system?["cache_control"] as? [String: Any]
        #expect(cacheControl?["type"] as? String == "ephemeral")
    }

    // MARK: - Response text joining

    @Test func singleTextBlockReturnsText() async throws {
        AnthropicMockURLProtocol.requestHandler = makeHandler(body: try successBody(textBlocks: ["Hello world"]))
        let result = try await completeDefault()
        #expect(result.text == "Hello world")
    }

    @Test func multipleTextBlocksAreJoinedInOrder() async throws {
        // Web search fragments reply into many small text blocks — all must be joined in order.
        let json = """
        {"content":[
            {"type":"server_tool_use","id":"x","name":"web_search","input":{}},
            {"type":"web_search_tool_result","tool_use_id":"x","content":[]},
            {"type":"text","text":"TITLE: My Post"},
            {"type":"text","text":"\\n\\nCONTENT:\\n"},
            {"type":"text","text":"<p>Body</p>"}
        ],"stop_reason":"end_turn"}
        """.data(using: .utf8)!
        AnthropicMockURLProtocol.requestHandler = makeHandler(body: json)
        let result = try await completeDefault()
        #expect(result.text == "TITLE: My Post\n\nCONTENT:\n<p>Body</p>")
    }

    @Test func nonTextBlocksExcludedFromJoin() async throws {
        let json = """
        {"content":[
            {"type":"server_tool_use","id":"x","name":"web_search","input":{}},
            {"type":"text","text":"only this"}
        ],"stop_reason":"end_turn"}
        """.data(using: .utf8)!
        AnthropicMockURLProtocol.requestHandler = makeHandler(body: json)
        let result = try await completeDefault()
        #expect(result.text == "only this")
    }

    @Test func allNonTextBlocksThrowsNoTextContent() async throws {
        let json = """
        {"content":[
            {"type":"server_tool_use","id":"x","name":"web_search","input":{}}
        ],"stop_reason":"end_turn"}
        """.data(using: .utf8)!
        AnthropicMockURLProtocol.requestHandler = makeHandler(body: json)
        await #expect(throws: AnthropicError.noTextContent) {
            _ = try await completeDefault()
        }
    }

    // MARK: - Truncation flag

    @Test func truncatedTrueWhenStopReasonIsMaxTokens() async throws {
        let json = #"{"content":[{"type":"text","text":"x"}],"stop_reason":"max_tokens"}"#
            .data(using: .utf8)!
        AnthropicMockURLProtocol.requestHandler = makeHandler(body: json)
        let result = try await completeDefault()
        #expect(result.truncated == true)
    }

    @Test func cutOffStructuredReplyThrowsCutOffWithTheTool() async throws {
        let json = #"{"content":[{"type":"text","text":"{\"html\": \"<p>par"}],"stop_reason":"max_tokens"}"#
        AnthropicMockURLProtocol.requestHandler = makeHandler(body: Data(json.utf8))
        await #expect(throws: AnthropicError.cutOff(webSearchTool: "web_search_20260318")) {
            _ = try await client.complete(userMessage: "u", systemPrompt: "s", options: searchOptions(schema: ["type": "object"]))
        }
    }

    @Test func thinkingThatUsesTheWholeBudgetThrowsCutOff() async throws {
        let json = #"{"content":[{"type":"thinking","thinking":"hmm","signature":"x"}],"stop_reason":"max_tokens"}"#
        AnthropicMockURLProtocol.requestHandler = makeHandler(body: Data(json.utf8))
        await #expect(throws: AnthropicError.cutOff(webSearchTool: nil)) { _ = try await completeDefault() }
    }

    @Test func truncatedFalseWhenStopReasonIsEndTurn() async throws {
        AnthropicMockURLProtocol.requestHandler = makeHandler(body: try successBody(textBlocks: ["x"]))
        let result = try await completeDefault()
        #expect(result.truncated == false)
    }

    @Test func missingStopReasonFieldDoesNotThrowAndIsNotTruncated() async throws {
        // stop_reason is Optional so a response that omits the field entirely still decodes.
        let json = #"{"content":[{"type":"text","text":"x"}]}"#.data(using: .utf8)!
        AnthropicMockURLProtocol.requestHandler = makeHandler(body: json)
        let result = try await completeDefault()
        #expect(result.text == "x")
        #expect(result.truncated == false)
    }

    // MARK: - Error cases

    @Test func nonOkStatusThrowsHttpError() async throws {
        let body = "Bad request".data(using: .utf8)!
        AnthropicMockURLProtocol.requestHandler = makeHandler(status: 400, body: body)
        await #expect(throws: AnthropicError.self) {
            _ = try await completeDefault()
        }
    }

    @Test func httpErrorPreservesBodyString() async throws {
        let body = #"{"error":{"message":"invalid key"}}"#.data(using: .utf8)!
        AnthropicMockURLProtocol.requestHandler = makeHandler(status: 401, body: body)
        do {
            _ = try await completeDefault()
            Issue.record("Expected throw")
        } catch let err as AnthropicError {
            if case .httpError(let code, let msg) = err {
                #expect(code == 401)
                #expect(msg.contains("invalid key"))
            } else {
                Issue.record("Wrong error case: \(err)")
            }
        }
    }

    @Test func malformedJsonThrows() async throws {
        let body = "not json at all".data(using: .utf8)!
        AnthropicMockURLProtocol.requestHandler = makeHandler(body: body)
        await #expect(throws: (any Error).self) {
            _ = try await completeDefault()
        }
    }

    @Test func networkFailureThrows() async throws {
        AnthropicMockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        await #expect(throws: (any Error).self) {
            _ = try await completeDefault()
        }
    }

    @Test func networkFailureWrapsAsAnthropicNetworkError() async throws {
        AnthropicMockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        do {
            _ = try await completeDefault()
            Issue.record("Expected throw")
        } catch let err as AnthropicError {
            if case .networkError = err { /* pass */ }
            else { Issue.record("Wrong error case: \(err)") }
        }
    }

    private struct FakeError: Error, LocalizedError {
        let description: String
        var errorDescription: String? { description }
    }

    @Test func networkErrorPassesThroughUnrecognizedMessage() {
        let err = AnthropicError.networkError(FakeError(description: "Something else went wrong."))
        #expect(err.errorDescription == "Something else went wrong.")
    }

    // MARK: - verifyKey

    @Test func verifyKeyRequestsModelsWithKeyAndVersion() async throws {
        var captured: URLRequest?
        AnthropicMockURLProtocol.requestHandler = { req in
            captured = req
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"data":[]}"#.utf8))
        }
        try await client.verifyKey()
        #expect(captured?.httpMethod == "GET")
        #expect(captured?.url?.absoluteString == "https://api.anthropic.com/v1/models?limit=1")
        #expect(captured?.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(captured?.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    }

    @Test func verifyKeySucceedsOn200() async throws {
        AnthropicMockURLProtocol.requestHandler = makeHandler(body: Data(#"{"data":[]}"#.utf8))
        try await client.verifyKey()
    }

    @Test func verifyKeyThrowsInvalidKeyOn401() async {
        AnthropicMockURLProtocol.requestHandler = makeHandler(status: 401, body: Data(#"{"type":"error"}"#.utf8))
        await #expect(throws: AnthropicError.invalidKey) { try await client.verifyKey() }
    }

    @Test func verifyKeyThrowsHTTPErrorOn500() async {
        AnthropicMockURLProtocol.requestHandler = makeHandler(status: 500, body: Data("boom".utf8))
        await #expect(throws: AnthropicError.httpError(500, "boom")) { try await client.verifyKey() }
    }

    @Test func verifyKeyWrapsTransportFailureAsNetworkError() async {
        AnthropicMockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            try await client.verifyKey()
            Issue.record("Expected throw")
        } catch let err as AnthropicError {
            if case .networkError = err {} else { Issue.record("Wrong error case: \(err)") }
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    // MARK: - listModels

    private static func modelJSON(id: String, name: String, created: String, line: String, maxTokens: Int,
                                  adaptive: Bool, enabled: Bool, efforts: [String], webSearch: Bool) -> String {
        let effort = ["low", "medium", "high", "xhigh", "max"]
            .map { #""\#($0)":{"supported":\#(efforts.contains($0))}"# }.joined(separator: ",")
        return #"""
        {"type":"model","id":"\#(id)","display_name":"\#(name)","created_at":"\#(created)","line":"\#(line)",
         "max_input_tokens":1000000,"max_tokens":\#(maxTokens),
         "capabilities":{"effort":{"supported":\#(!efforts.isEmpty),\#(effort)},
           "server_tools":{"supported":true,"web_search":{"supported":\#(webSearch)}},
           "thinking":{"supported":true,"types":{"enabled":{"supported":\#(enabled)},"adaptive":{"supported":\#(adaptive)},"disabled":{"supported":true}}}},
         "lifecycle":"active"}
        """#
    }

    private static let haiku45JSON = modelJSON(id: "claude-haiku-4-5-20251001", name: "Claude Haiku 4.5", created: "2025-10-15T00:00:00Z",
                                               line: "haiku", maxTokens: 64000, adaptive: false, enabled: true, efforts: [], webSearch: true)
    private static let haiku55JSON = modelJSON(id: "claude-haiku-5-5", name: "Claude Haiku 5.5", created: "2026-10-07T18:00:00Z",
                                               line: "haiku", maxTokens: 128000, adaptive: true, enabled: false,
                                               efforts: ["low", "medium", "high", "xhigh", "max"], webSearch: true)
    private static let sonnet55JSON = modelJSON(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5", created: "2026-09-28T00:00:00Z",
                                                line: "sonnet", maxTokens: 128000, adaptive: true, enabled: false,
                                                efforts: ["low", "medium", "high"], webSearch: false)

    private static func page(_ models: [String], hasMore: Bool = false, lastID: String? = nil) -> Data {
        Data(#"{"data":[\#(models.joined(separator: ","))],"has_more":\#(hasMore),"last_id":\#(lastID.map { "\"\($0)\"" } ?? "null")}"#.utf8)
    }

    @Test func listModelsDecodesCapabilities() async throws {
        var captured: URLRequest?
        AnthropicMockURLProtocol.requestHandler = { req in
            captured = req
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Self.page([Self.haiku55JSON, Self.haiku45JSON, Self.sonnet55JSON]))
        }
        let models = try await client.listModels()
        #expect(captured?.url?.absoluteString == "https://api.anthropic.com/v1/models?limit=100")
        #expect(captured?.value(forHTTPHeaderField: "x-api-key") == "test-key")
        let h55 = try #require(models.first { $0.id == "claude-haiku-5-5" })
        #expect(h55.displayName == "Claude Haiku 5.5" && h55.maxTokens == 128000 && h55.line == "haiku")
        #expect(h55.supportsAdaptiveThinking && !h55.supportsEnabledThinking && h55.supportsWebSearch)
        #expect(h55.effortLevels == ["low", "medium", "high", "xhigh", "max"])
        #expect(h55.createdAt == ISO8601DateFormatter().date(from: "2026-10-07T18:00:00Z"))
        let h45 = try #require(models.first { $0.id == "claude-haiku-4-5-20251001" })
        #expect(!h45.supportsAdaptiveThinking && h45.supportsEnabledThinking && h45.effortLevels.isEmpty && h45.maxTokens == 64000)
        let s55 = try #require(models.first { $0.id == "claude-sonnet-5-5" })
        #expect(!s55.supportsWebSearch && s55.effortLevels == ["low", "medium", "high"])
    }

    @Test func listModelsSortsNewestFirst() async throws {
        AnthropicMockURLProtocol.requestHandler = makeHandler(body: Self.page([Self.haiku45JSON, Self.haiku55JSON, Self.sonnet55JSON]))
        let ids = try await client.listModels().map(\.id)
        #expect(ids == ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-haiku-4-5-20251001"])
    }

    @Test func listModelsFollowsPaging() async throws {
        var urls: [String] = []
        AnthropicMockURLProtocol.requestHandler = { req in
            urls.append(req.url!.absoluteString)
            let body = urls.count == 1
                ? Self.page([Self.haiku55JSON, Self.sonnet55JSON], hasMore: true, lastID: "claude-sonnet-5-5")
                : Self.page([Self.haiku45JSON])
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let models = try await client.listModels()
        #expect(models.count == 3)
        #expect(urls == ["https://api.anthropic.com/v1/models?limit=100",
                         "https://api.anthropic.com/v1/models?limit=100&after_id=claude-sonnet-5-5"])
    }

    @Test func listModelsInvalidKeyThrowsInvalidKey() async {
        AnthropicMockURLProtocol.requestHandler = makeHandler(status: 401, body: Data(#"{"type":"error"}"#.utf8))
        await #expect(throws: AnthropicError.invalidKey) { _ = try await client.listModels() }
    }

    // MARK: - Web search versions

    /// The 400 the API returned on 2026-10-07 for a tool type it doesn't know.
    private static func unknownToolBody(_ tool: String) -> Data {
        Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"tools.0: Input tag '\#(tool)' found using 'type' does not match any of the expected tags: 'bash_20250124', 'web_search_20250305', 'web_search_20260209'"},"request_id":"req_x"}"#.utf8)
    }

    private func searchOptions(knownTool: String? = nil, schema: [String: Any]? = nil) -> CompletionOptions {
        CompletionOptions(modelID: "claude-haiku-5-5", model: haiku55, reasoning: .modelDefault,
                          webSearch: WebSearchUse(maxUses: 8, knownTool: knownTool), jsonSchema: schema)
    }

    private static func sentTool(_ req: URLRequest) -> String? {
        let body = try? JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        return (body?["tools"] as? [[String: Any]])?.first?["type"] as? String
    }

    private static func ok(_ req: URLRequest, _ data: Data) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
    }

    @Test func triesNewestVersionFirst() async throws {
        var tools: [String?] = []
        AnthropicMockURLProtocol.requestHandler = { req in
            tools.append(Self.sentTool(req))
            return Self.ok(req, try self.successBody(textBlocks: ["hi"]))
        }
        let result = try await client.complete(userMessage: "u", systemPrompt: "s", options: searchOptions())
        #expect(tools == ["web_search_20260318"])
        #expect(result.webSearchTool == "web_search_20260318")
        #expect(AnthropicClient.webSearchVersions == ["web_search_20260318", "web_search_20260209", "web_search_20250305"])
    }

    @Test func matchingRejectionRetriesNextVersion() async throws {
        var tools: [String?] = []
        AnthropicMockURLProtocol.requestHandler = { req in
            let tool = Self.sentTool(req)
            tools.append(tool)
            if tool == "web_search_20250305" { return Self.ok(req, try self.successBody(textBlocks: ["hi"])) }
            return (HTTPURLResponse(url: req.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!, Self.unknownToolBody(tool!))
        }
        let result = try await client.complete(userMessage: "u", systemPrompt: "s", options: searchOptions())
        #expect(tools == ["web_search_20260318", "web_search_20260209", "web_search_20250305"])
        #expect(result.webSearchTool == "web_search_20250305")
    }

    @Test func unrelated400IsNotRetried() async {
        var count = 0
        AnthropicMockURLProtocol.requestHandler = { req in
            count += 1
            return (HTTPURLResponse(url: req.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"max_tokens: too large"}}"#.utf8))
        }
        await #expect(throws: AnthropicError.self) {
            _ = try await client.complete(userMessage: "u", systemPrompt: "s", options: searchOptions())
        }
        #expect(count == 1)
    }

    @Test func knownVersionIsUsedDirectly() async throws {
        var tools: [String?] = []
        AnthropicMockURLProtocol.requestHandler = { req in
            tools.append(Self.sentTool(req))
            return Self.ok(req, try self.successBody(textBlocks: ["hi"]))
        }
        let result = try await client.complete(userMessage: "u", systemPrompt: "s", options: searchOptions(knownTool: "web_search_20260209"))
        #expect(tools == ["web_search_20260209"])
        #expect(result.webSearchTool == "web_search_20260209")
    }

    @Test func noToolWithoutWebSearch() async throws {
        AnthropicMockURLProtocol.requestHandler = makeHandler(body: try successBody(textBlocks: ["hi"]))
        #expect(try await completeDefault().webSearchTool == nil)
    }

    // MARK: - pause_turn

    private static let pausedBody = Data(#"{"content":[{"type":"text","text":"Searching. "},{"type":"server_tool_use","id":"srv_1","name":"web_search","input":{"query":"q"}}],"stop_reason":"pause_turn"}"#.utf8)

    @Test func pauseTurnContinuesAndJoinsText() async throws {
        var bodies: [[String: Any]] = []
        AnthropicMockURLProtocol.requestHandler = { req in
            bodies.append(try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any])
            return Self.ok(req, bodies.count == 1 ? Self.pausedBody : try self.successBody(textBlocks: ["Done."]))
        }
        let result = try await client.complete(userMessage: "u", systemPrompt: "s", options: searchOptions())
        #expect(result.text == "Searching. Done.")
        #expect(bodies.count == 2)
        let messages = bodies[1]["messages"] as! [[String: Any]]
        #expect(messages.count == 2)
        #expect(messages[1]["role"] as? String == "assistant")
        let content = messages[1]["content"] as! [[String: Any]]
        #expect(content.map { $0["type"] as? String } == ["text", "server_tool_use"])
        #expect((content[1]["input"] as? [String: Any])?["query"] as? String == "q")
    }

    @Test func pauseTurnStopsAfterThreeContinuations() async throws {
        var count = 0
        AnthropicMockURLProtocol.requestHandler = { req in
            count += 1
            return Self.ok(req, Self.pausedBody)
        }
        let result = try await client.complete(userMessage: "u", systemPrompt: "s", options: searchOptions())
        #expect(count == 4)
        #expect(result.text == "Searching. Searching. Searching. Searching. ")
    }

    @Test func structuredOutputAcrossPauseTurnParsesLastText() async throws {
        var count = 0
        AnthropicMockURLProtocol.requestHandler = { req in
            count += 1
            return Self.ok(req, count == 1 ? Self.pausedBody : Data(#"{"content":[{"type":"text","text":"{\"html\":\"<p>x</p>\"}"}],"stop_reason":"end_turn"}"#.utf8))
        }
        let result = try await client.complete(userMessage: "u", systemPrompt: "s", options: searchOptions(schema: ["type": "object"]))
        #expect(result.text == #"{"html":"<p>x</p>"}"#)
    }

    @Test func schemaPropertiesAreSentInRequiredOrder() async throws {
        var bodyText = ""
        AnthropicMockURLProtocol.requestHandler = { req in
            bodyText = String(data: req.httpBody!, encoding: .utf8)!
            return Self.ok(req, try self.successBody(textBlocks: ["{}"]))
        }
        let options = CompletionOptions(modelID: "m", model: nil, reasoning: .off, jsonSchema: EvaluationPrompts.factCheckSchema)
        _ = try await client.complete(userMessage: "u", systemPrompt: "s", options: options)
        let claims = try #require(bodyText.range(of: #""claims""#))
        let checks = try #require(bodyText.range(of: #""fact_checks""#))
        #expect(claims.lowerBound < checks.lowerBound)
        let keys = ["original", "explanation", "source_quote", "source_url", "replacement"]
            .map { bodyText.range(of: "\"\($0)\":{")!.lowerBound }
        #expect(keys == keys.sorted())
        let parsed = try JSONSerialization.jsonObject(with: Data(bodyText.utf8)) as! [String: Any]
        #expect(parsed["model"] as? String == "m")
        #expect(ns((parsed["output_config"] as? [String: Any])?["format"]) == ns(["type": "json_schema", "schema": EvaluationPrompts.factCheckSchema]))
    }

    @Test func invalidKeyMessage() {
        #expect(AnthropicError.invalidKey.errorDescription == "Anthropic didn't accept this key.")
    }
}
