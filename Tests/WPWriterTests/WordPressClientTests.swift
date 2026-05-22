import Foundation
import Testing
@testable import WPWriterKit

@Suite(.serialized) struct WordPressClientTests {
    var client: WordPressClient

    init() {
        MockURLProtocol.requestHandler = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let credentials = Credentials(
            siteURL: URL(string: "https://example.com")!,
            username: "user",
            appPassword: "pass"
        )
        client = WordPressClient(credentials: credentials, session: session)
    }

    @Test func fetchPostsDecodesList() async throws {
        let json = """
        [{"id":1,"title":{"rendered":"Hello","raw":"Hello"},
          "content":{"rendered":"<p>World</p>","raw":"<p>World</p>"},
          "excerpt":{"rendered":"","raw":""},
          "status":"publish","date":"2024-01-01T00:00:00",
          "modified":"2024-01-01T00:00:00","slug":"hello","link":"https://example.com/hello",
          "featured_media":0,"categories":[],"tags":[]}]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, json)
        }

        let posts = try await client.fetchPosts()
        #expect(posts.count == 1)
        #expect(posts[0].id == 1)
        #expect(posts[0].title.rendered == "Hello")
    }

    @Test func fetchPostsThrowsOnHTTPError() async throws {
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        await #expect(throws: APIError.self) {
            try await client.fetchPosts()
        }
    }
}

// MARK: - Mock URLProtocol
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
