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
            useWebSearch: useWebSearch
        )
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

    @Test func truncatedFalseWhenStopReasonIsEndTurn() async throws {
        AnthropicMockURLProtocol.requestHandler = makeHandler(body: try successBody(textBlocks: ["x"]))
        let result = try await completeDefault()
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
}
