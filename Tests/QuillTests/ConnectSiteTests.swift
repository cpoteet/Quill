import Foundation
import Testing
@testable import QuillKit

@Suite(.serialized) struct ConnectSiteTests {
    let session: URLSession
    let credentials = Credentials(siteURL: URL(string: "https://example.com")!, username: "chris", appPassword: "abcd efgh")

    init() {
        ConnectSiteMockURLProtocol.requestHandler = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ConnectSiteMockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    private func serve(status: Int, body: String) {
        ConnectSiteMockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
    }

    @Test func savesCredentialsAfterASuccessfulCheck() async throws {
        var requestedPath: String?
        ConnectSiteMockURLProtocol.requestHandler = { request in
            requestedPath = request.url?.path()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("[]".utf8))
        }
        var saved: [Credentials] = []
        try await ConnectSite.verifyAndSave(credentials, session: session) { saved.append($0) }
        #expect(requestedPath == "/wp-json/wp/v2/posts")
        #expect(saved == [credentials])
    }

    @Test func savesNothingWhenTheCheckFails() async {
        serve(status: 401, body: #"{"code":"rest_not_logged_in","message":"Sorry, you are not allowed to do that."}"#)
        var saved: [Credentials] = []
        await #expect(throws: (any Error).self) {
            try await ConnectSite.verifyAndSave(credentials, session: session) { saved.append($0) }
        }
        #expect(saved.isEmpty)
    }
}
