import Foundation
import Testing
@testable import QuillKit

// MARK: - Shared fixtures

private let minimalPostJSON = """
{"id":1,"title":{"rendered":"Hello","raw":"Hello"},\
"content":{"rendered":"<p>World</p>","raw":"<p>World</p>"},\
"excerpt":{"rendered":"","raw":""},\
"status":"publish","date":"2024-01-01T00:00:00",\
"modified":"2024-01-01T00:00:00","slug":"hello","link":"https://example.com/hello",\
"featured_media":0,"categories":[],"tags":[]}
"""

private let minimalMediaJSON = """
{"id":5,"title":{"rendered":"photo.jpg"},\
"source_url":"https://example.com/photo.jpg",\
"media_type":"image","mime_type":"image/jpeg",\
"link":"https://example.com/?attachment_id=5","date":"2024-01-01T00:00:00"}
"""

private let minimalCategoryJSON = """
{"id":1,"name":"Tech","slug":"tech","count":5,"parent":0}
"""

private let minimalTagJSON = """
{"id":1,"name":"swift","slug":"swift","count":3}
"""

private let minimalAutosaveJSON = """
{"parent":1}
"""

private let minimalPayload = PostPayload(title: "T", content: "C", status: "draft")

// MARK: - Suite

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

    // MARK: - Existing tests

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

    @Test func trashPostSendsDeleteRequest() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }
        try await client.trashPost(id: 42)
        #expect(capturedRequest?.httpMethod == "DELETE")
        #expect(capturedRequest?.url?.path.contains("posts/42") == true)
        #expect(capturedRequest?.url?.query?.contains("force=false") == true)
    }

    @Test func trashPostThrowsOnHTTPError() async throws {
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 403, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }
        await #expect(throws: APIError.self) {
            try await client.trashPost(id: 42)
        }
    }

    @Test func trashPageSendsDeleteRequest() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }
        try await client.trashPage(id: 7)
        #expect(capturedRequest?.httpMethod == "DELETE")
        #expect(capturedRequest?.url?.path.contains("pages/7") == true)
        #expect(capturedRequest?.url?.query?.contains("force=false") == true)
    }

    @Test func searchLinksReturnsMergedResults() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let path = request.url?.path ?? ""
            let query = request.url?.query ?? ""

            if path.contains("/search") && query.contains("type=post") {
                let json = """
                [{"id":1,"title":"Hello Post","url":"https://example.com/hello","type":"post","subtype":"post"},
                 {"id":2,"title":"About Page","url":"https://example.com/about","type":"post","subtype":"page"}]
                """.data(using: .utf8)!
                return (response, json)
            } else if path.contains("/search") && query.contains("type=term") {
                let json = """
                [{"id":3,"title":"Tech","url":"https://example.com/category/tech","type":"term","subtype":"category"},
                 {"id":4,"title":"swift","url":"https://example.com/tag/swift","type":"term","subtype":"tag"}]
                """.data(using: .utf8)!
                return (response, json)
            } else if path.contains("/media") {
                let json = """
                [{"id":5,"title":{"rendered":"photo.jpg"},"source_url":"https://example.com/wp-content/uploads/photo.jpg",
                  "media_type":"image","mime_type":"image/jpeg","link":"https://example.com/?attachment_id=5","date":"2024-01-01T00:00:00"}]
                """.data(using: .utf8)!
                return (response, json)
            }
            return (response, "[]".data(using: .utf8)!)
        }

        let results = try await client.searchLinks(query: "hello")
        #expect(results.count == 5)
        #expect(results[0].type == .post)
        #expect(results[0].title == "Hello Post")
        #expect(results[0].id == "post-1")
        #expect(results[1].type == .page)
        #expect(results[2].type == .category)
        #expect(results[3].type == .tag)
        #expect(results[4].type == .media)
        #expect(results[4].url == "https://example.com/wp-content/uploads/photo.jpg")
    }

    @Test func searchLinksIgnoresSubrequestFailures() async throws {
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            let query = request.url?.query ?? ""
            if path.contains("/search") && query.contains("type=post") {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
                )!
                let json = """
                [{"id":1,"title":"Hello","url":"https://example.com/hello","type":"post","subtype":"post"}]
                """.data(using: .utf8)!
                return (response, json)
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let results = try await client.searchLinks(query: "hello")
        #expect(results.count == 1)
        #expect(results[0].type == .post)
    }

    @Test func searchQueryPlusCharacterIsPercentEscaped() async throws {
        // URLComponents leaves a literal "+" unescaped in query values (valid per RFC 3986),
        // but WordPress/PHP decodes "+" as a space — it must be escaped to "%2B" so the
        // search term round-trips literally instead of becoming "C  C" server-side.
        var capturedQuery: String?
        MockURLProtocol.requestHandler = { request in
            if capturedQuery == nil { capturedQuery = request.url?.query }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    "[]".data(using: .utf8)!)
        }
        _ = try await client.searchLinks(query: "C++")
        #expect(capturedQuery?.contains("C%2B%2B") == true)
        #expect(capturedQuery?.contains("+") == false)
    }

    // MARK: - §2.1 URL & request construction

    @Test func fetchPostsIncludesRequiredQueryParams() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    "[]".data(using: .utf8)!)
        }
        _ = try await client.fetchPosts()
        let query = capturedRequest?.url?.query ?? ""
        #expect(query.contains("per_page="))
        #expect(query.contains("page="))
        #expect(query.contains("context=edit"))
        #expect(query.contains("publish"))
        #expect(query.contains("draft"))
    }

    @Test func createPostUsesPostMethodWithJsonContentType() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    minimalPostJSON.data(using: .utf8)!)
        }
        _ = try await client.createPost(minimalPayload)
        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.url?.path.hasSuffix("/posts") == true)
        #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func updatePostUsesPutMethodOnPostsId() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    minimalPostJSON.data(using: .utf8)!)
        }
        _ = try await client.updatePost(id: 99, payload: minimalPayload)
        #expect(capturedRequest?.httpMethod == "PUT")
        #expect(capturedRequest?.url?.path.contains("posts/99") == true)
        #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func createPageUsesPostMethodOnPagesEndpoint() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    minimalPostJSON.data(using: .utf8)!)
        }
        _ = try await client.createPage(minimalPayload)
        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.url?.path.hasSuffix("/pages") == true)
    }

    @Test func updatePageUsesPutMethodOnPagesId() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    minimalPostJSON.data(using: .utf8)!)
        }
        _ = try await client.updatePage(id: 55, payload: minimalPayload)
        #expect(capturedRequest?.httpMethod == "PUT")
        #expect(capturedRequest?.url?.path.contains("pages/55") == true)
    }

    @Test func authorizationHeaderIncludedInRequests() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    "[]".data(using: .utf8)!)
        }
        _ = try await client.fetchPosts()
        let auth = capturedRequest?.value(forHTTPHeaderField: "Authorization") ?? ""
        #expect(auth.hasPrefix("Basic "))
        #expect(auth.count > "Basic ".count)
    }

    @Test func requestsAcceptJSONSoWordPressHidesPHPWarnings() async throws {
        var capturedRequests: [URLRequest] = []
        MockURLProtocol.requestHandler = { request in
            capturedRequests.append(request)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    minimalMediaJSON.data(using: .utf8)!)
        }
        _ = try await client.fetchMediaItem(id: 1)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try Data([0x89, 0x50]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        _ = try await client.uploadMedia(fileURL: tmp, filename: "photo.png", mimeType: "image/png")
        #expect(capturedRequests.count == 2)
        for request in capturedRequests {
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        }
    }

    @Test func uploadMediaSetsContentTypeFromMimeType() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    minimalMediaJSON.data(using: .utf8)!)
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try Data([0x89, 0x50]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        _ = try await client.uploadMedia(fileURL: tmp, filename: "photo.png", mimeType: "image/png")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "image/png")
    }

    @Test func uploadMediaSetsContentDispositionWithFilename() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    minimalMediaJSON.data(using: .utf8)!)
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try Data([0xFF, 0xD8]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        _ = try await client.uploadMedia(fileURL: tmp, filename: "photo.jpg", mimeType: "image/jpeg")
        let disposition = capturedRequest?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        #expect(disposition.contains("filename=\"photo.jpg\""))
        #expect(disposition.contains("filename*=UTF-8''"))
    }

    @Test func uploadMediaSpacesInFilenameArePercentEncoded() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    minimalMediaJSON.data(using: .utf8)!)
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try Data([0xFF, 0xD8]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        _ = try await client.uploadMedia(fileURL: tmp, filename: "my photo.jpg", mimeType: "image/jpeg")
        let disposition = capturedRequest?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        #expect(disposition.contains("filename=\"my photo.jpg\""))
        #expect(disposition.contains("my%20photo.jpg"))
    }

    @Test func deleteMediaSendsDeleteWithForceTrueQuery() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data())
        }
        try await client.deleteMedia(id: 77)
        #expect(capturedRequest?.httpMethod == "DELETE")
        #expect(capturedRequest?.url?.path.contains("media/77") == true)
        #expect(capturedRequest?.url?.query?.contains("force=true") == true)
    }

    @Test func fetchMediaItemHitsCorrectEndpointWithEditContext() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    minimalMediaJSON.data(using: .utf8)!)
        }
        let media = try await client.fetchMediaItem(id: 42)
        #expect(capturedRequest?.url?.path.contains("media/42") == true)
        #expect(capturedRequest?.url?.query?.contains("context=edit") == true)
        #expect(capturedRequest?.httpMethod == "GET")
        #expect(media.id == 5)
    }

    @Test func updateMediaAltTextSendsPostToMediaEndpoint() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    minimalMediaJSON.data(using: .utf8)!)
        }
        _ = try await client.updateMediaAltText(id: 42, altText: "A sunset photo")
        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.url?.path.contains("media/42") == true)
    }

    @Test func updateMediaAltTextBodyContainsAltText() async throws {
        var bodyData: Data?
        MockURLProtocol.requestHandler = { request in
            var body = Data()
            if let stream = request.httpBodyStream {
                stream.open()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let n = stream.read(&buffer, maxLength: buffer.count)
                    if n > 0 { body.append(contentsOf: buffer[..<n]) }
                }
                stream.close()
            }
            bodyData = body
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    minimalMediaJSON.data(using: .utf8)!)
        }
        _ = try await client.updateMediaAltText(id: 42, altText: "Sunset over a lake")
        let bodyStr = String(data: bodyData ?? Data(), encoding: .utf8) ?? ""
        #expect(bodyStr.contains("alt_text"))
        #expect(bodyStr.contains("Sunset over a lake"))
    }

    @Test func updateMediaAltTextReturnsDecodedMedia() async throws {
        let mediaJSON = """
        {"id":42,"title":{"rendered":"photo.jpg"},\
        "source_url":"https://example.com/photo.jpg",\
        "media_type":"image","mime_type":"image/jpeg",\
        "link":"https://example.com/?attachment_id=42","date":"2024-01-01T00:00:00",\
        "alt_text":"Updated alt text"}
        """
        MockURLProtocol.requestHandler = { request in
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    mediaJSON.data(using: .utf8)!)
        }
        let updated = try await client.updateMediaAltText(id: 42, altText: "Updated alt text")
        #expect(updated.id == 42)
        #expect(updated.altText == "Updated alt text")
    }

    @Test func createAutosaveSendsToPostAutosavesEndpoint() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    minimalAutosaveJSON.data(using: .utf8)!)
        }
        _ = try await client.createAutosave(postID: 10, payload: minimalPayload)
        let path = capturedRequest?.url?.path ?? ""
        #expect(path.contains("posts/10/autosaves"))
        #expect(capturedRequest?.httpMethod == "POST")
    }

    @Test func createPageAutosaveSendsToPageAutosavesEndpoint() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    minimalAutosaveJSON.data(using: .utf8)!)
        }
        _ = try await client.createPageAutosave(postID: 20, payload: minimalPayload)
        let path = capturedRequest?.url?.path ?? ""
        #expect(path.contains("pages/20/autosaves"))
        #expect(capturedRequest?.httpMethod == "POST")
    }

    @Test func fetchAllCategoriesHitsCategoriesEndpointWithPerPage100() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                    headerFields: ["X-WP-TotalPages": "1"])!,
                    "[]".data(using: .utf8)!)
        }
        _ = try await client.fetchAllCategories()
        #expect(capturedRequest?.url?.query?.contains("per_page=100") == true)
        #expect(capturedRequest?.url?.path.contains("/categories") == true)
    }

    @Test func fetchAllCategoriesPaginatesAcrossMultiplePages() async throws {
        var requestedPages: [String] = []
        MockURLProtocol.requestHandler = { request in
            let pageParam = request.url?.query?
                .components(separatedBy: "&")
                .first(where: { $0.hasPrefix("page=") })?
                .replacingOccurrences(of: "page=", with: "") ?? "1"
            requestedPages.append(pageParam)
            let json = pageParam == "1"
                ? "[{\"id\":1,\"name\":\"Tech\",\"slug\":\"tech\",\"count\":5,\"parent\":0}]"
                : "[{\"id\":2,\"name\":\"News\",\"slug\":\"news\",\"count\":2,\"parent\":0}]"
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                    headerFields: ["X-WP-TotalPages": "2"])!,
                    json.data(using: .utf8)!)
        }
        let categories = try await client.fetchAllCategories()
        #expect(requestedPages == ["1", "2"])
        #expect(categories.count == 2)
        #expect(categories[0].id == 1)
        #expect(categories[1].id == 2)
    }

    @Test func fetchAllTagsHitsTagsEndpointWithPerPage100() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                    headerFields: ["X-WP-TotalPages": "1"])!,
                    "[]".data(using: .utf8)!)
        }
        _ = try await client.fetchAllTags()
        #expect(capturedRequest?.url?.query?.contains("per_page=100") == true)
        #expect(capturedRequest?.url?.path.contains("/tags") == true)
    }

    @Test func fetchAllTagsPaginatesAcrossMultiplePages() async throws {
        var requestedPages: [String] = []
        MockURLProtocol.requestHandler = { request in
            let pageParam = request.url?.query?
                .components(separatedBy: "&")
                .first(where: { $0.hasPrefix("page=") })?
                .replacingOccurrences(of: "page=", with: "") ?? "1"
            requestedPages.append(pageParam)
            let json = pageParam == "1"
                ? "[{\"id\":3,\"name\":\"swift\",\"slug\":\"swift\",\"count\":10}]"
                : "[{\"id\":4,\"name\":\"ios\",\"slug\":\"ios\",\"count\":7}]"
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                    headerFields: ["X-WP-TotalPages": "2"])!,
                    json.data(using: .utf8)!)
        }
        let tags = try await client.fetchAllTags()
        #expect(requestedPages == ["1", "2"])
        #expect(tags.count == 2)
        #expect(tags[0].id == 3)
        #expect(tags[1].id == 4)
    }

    @Test func createCategoryUsesPostMethodOnCategoriesEndpoint() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    minimalCategoryJSON.data(using: .utf8)!)
        }
        _ = try await client.createCategory(name: "Tech")
        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.url?.path.contains("/categories") == true)
        #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func createTagUsesPostMethodOnTagsEndpoint() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    minimalTagJSON.data(using: .utf8)!)
        }
        _ = try await client.createTag(name: "swift")
        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.url?.path.contains("/tags") == true)
        #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    // MARK: - §2.2 Response handling & error mapping

    @Test func httpErrorPreservesStatusCode() async throws {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
             "Not Found".data(using: .utf8)!)
        }
        do {
            _ = try await client.fetchPosts()
            Issue.record("Expected APIError.httpError to be thrown")
        } catch let error as APIError {
            guard case .httpError(let code, _) = error else {
                Issue.record("Expected httpError, got \(error)")
                return
            }
            #expect(code == 404)
        } catch {
            Issue.record("Expected APIError, got \(error)")
        }
    }

    @Test func httpErrorPreservesBodyString() async throws {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
             "Bad Request".data(using: .utf8)!)
        }
        do {
            _ = try await client.fetchPosts()
            Issue.record("Expected APIError.httpError to be thrown")
        } catch let error as APIError {
            guard case .httpError(let code, let body) = error else {
                Issue.record("Expected httpError, got \(error)")
                return
            }
            #expect(code == 400)
            #expect(body == "Bad Request")
        } catch {
            Issue.record("Expected APIError, got \(error)")
        }
    }

    @Test func nonUtf8ResponseBodyBecomesEmptyString() async throws {
        MockURLProtocol.requestHandler = { request in
            // 0xFF 0xFE is not valid UTF-8
            (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
             Data([0xFF, 0xFE]))
        }
        do {
            _ = try await client.fetchPosts()
            Issue.record("Expected APIError.httpError to be thrown")
        } catch let error as APIError {
            guard case .httpError(_, let body) = error else {
                Issue.record("Expected httpError, got \(error)")
                return
            }
            #expect(body == "")
        } catch {
            Issue.record("Expected APIError, got \(error)")
        }
    }

    @Test func successWithMalformedJsonThrowsDecodingError() async throws {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             "{not valid json!!!".data(using: .utf8)!)
        }
        do {
            _ = try await client.fetchPosts()
            Issue.record("Expected APIError.decodingError to be thrown")
        } catch let error as APIError {
            if case .httpError = error {
                Issue.record("Expected decodingError, not httpError — malformed JSON on 200 should decode, not fail HTTP check")
            } else if case .decodingError = error {
                // Pass
            } else {
                Issue.record("Expected decodingError, got \(error)")
            }
        } catch {
            Issue.record("Expected APIError, got \(error)")
        }
    }

    @Test func networkFailureThrowsNetworkError() async throws {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.timedOut)
        }
        do {
            _ = try await client.fetchPosts()
            Issue.record("Expected APIError.networkError to be thrown")
        } catch let error as APIError {
            if case .networkError = error { /* pass */ }
            else { Issue.record("Expected networkError, got \(error)") }
        } catch {
            Issue.record("Expected APIError.networkError, got \(error)")
        }
    }

    @Test func urlErrorCancelledRethrowsAsCancellationError() async throws {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.cancelled)
        }
        do {
            _ = try await client.fetchPosts()
            Issue.record("Expected CancellationError to be thrown")
        } catch is CancellationError {
            // Pass — URLError(.cancelled) must be rethrown as CancellationError, not wrapped in APIError
        } catch let error as APIError {
            Issue.record("URLError(.cancelled) must not be wrapped in APIError; got \(error)")
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }

    // MARK: - §2.3 searchLinks extensions

    @Test func searchLinksAllSubrequestsFailReturnsEmptyArray() async throws {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!,
             Data())
        }
        let results = try await client.searchLinks(query: "test")
        #expect(results.isEmpty)
    }

    @Test func searchLinksPageSubtypeMapsToPageType() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let path = request.url?.path ?? ""
            let query = request.url?.query ?? ""
            if path.contains("/search") && query.contains("type=post") {
                let json = """
                [{"id":2,"title":"About","url":"https://example.com/about","type":"post","subtype":"page"}]
                """.data(using: .utf8)!
                return (response, json)
            }
            return (response, "[]".data(using: .utf8)!)
        }
        let results = try await client.searchLinks(query: "about")
        #expect(results.count == 1)
        #expect(results[0].type == .page)
    }

    @Test func searchLinksTagSubtypeMapsToTagType() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let path = request.url?.path ?? ""
            let query = request.url?.query ?? ""
            if path.contains("/search") && query.contains("type=term") {
                let json = """
                [{"id":4,"title":"swift","url":"https://example.com/tag/swift","type":"term","subtype":"tag"}]
                """.data(using: .utf8)!
                return (response, json)
            }
            return (response, "[]".data(using: .utf8)!)
        }
        let results = try await client.searchLinks(query: "swift")
        #expect(results.count == 1)
        #expect(results[0].type == .tag)
    }

    @Test func searchLinksUnknownTermSubtypeFallsToCategory() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let path = request.url?.path ?? ""
            let query = request.url?.query ?? ""
            if path.contains("/search") && query.contains("type=term") {
                // "post_tag" is not "tag", so it falls through to .category
                let json = """
                [{"id":9,"title":"misc","url":"https://example.com/misc","type":"term","subtype":"unknown_type"}]
                """.data(using: .utf8)!
                return (response, json)
            }
            return (response, "[]".data(using: .utf8)!)
        }
        let results = try await client.searchLinks(query: "misc")
        #expect(results.count == 1)
        #expect(results[0].type == .category)
    }

    // MARK: - Filename sanitization

    @Test func sanitizeFilenamePassesThroughNormal() {
        #expect(WordPressClient.sanitizeFilename("photo.jpg") == "photo.jpg")
    }

    @Test func sanitizeFilenameReplacesQuotesAndBackslashes() {
        #expect(WordPressClient.sanitizeFilename("weird \"name\".jpg") == "weird -name-.jpg")
        #expect(WordPressClient.sanitizeFilename("back\\slash.jpg") == "back-slash.jpg")
    }

    @Test func sanitizeFilenameReplacesControlChars() {
        #expect(WordPressClient.sanitizeFilename("bad\nname.jpg") == "bad-name.jpg")
        #expect(WordPressClient.sanitizeFilename("file\u{0001}name.jpg") == "file-name.jpg")
    }

    @Test func sanitizeFilenamePreservesUnicode() {
        #expect(WordPressClient.sanitizeFilename("café.jpg") == "café.jpg")
    }

    @Test func sanitizeFilenameNormalizesUnicodeSpaces() {
        #expect(WordPressClient.sanitizeFilename("ai-writing 9.06.39\u{202F}PM.png") == "ai-writing 9.06.39 PM.png")
        #expect(WordPressClient.sanitizeFilename("file\u{00A0}name.jpg") == "file name.jpg")
    }

    @Test func sanitizeFilenameHandlesEmptyStem() {
        #expect(WordPressClient.sanitizeFilename("   .png") == "upload.png")
    }

    @Test func uploadMediaSanitizesFilenameInContentDisposition() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    minimalMediaJSON.data(using: .utf8)!)
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try Data([0xFF, 0xD8]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        _ = try await client.uploadMedia(fileURL: tmp, filename: "weird \"name\".jpg", mimeType: "image/jpeg")
        let disposition = capturedRequest?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        #expect(disposition.contains("filename=\"weird -name-.jpg\""))
    }

    @Test func uploadMediaStreamsFromFileNotHttpBody() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    minimalMediaJSON.data(using: .utf8)!)
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let media = try await client.uploadMedia(fileURL: tmp, filename: "test.png", mimeType: "image/png")
        #expect(capturedRequest?.httpBody == nil)
        #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "image/png")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Disposition")?.contains("filename=\"test.png\"") == true)
        #expect(media.id == 5)
    }

    @Test func searchLinksPostsFailWhileTermsSucceed() async throws {
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            let query = request.url?.query ?? ""
            if path.contains("/search") && query.contains("type=post") {
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                        Data())
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if path.contains("/search") && query.contains("type=term") {
                let json = """
                [{"id":3,"title":"Tech","url":"https://example.com/category/tech","type":"term","subtype":"category"}]
                """.data(using: .utf8)!
                return (response, json)
            }
            return (response, "[]".data(using: .utf8)!)
        }
        let results = try await client.searchLinks(query: "tech")
        #expect(results.count == 1)
        #expect(results[0].type == .category)
    }

    // fetchAllPosts must include _fields so the list payload omits content/excerpt.
    // If _fields is removed, list fetches become 10–100× larger and the decoded posts
    // will have content that was never meant to be cached (regression from H3 fix).
    @Test func fetchAllPostsRequestIncludesFieldsFilter() async throws {
        var capturedQuery: String?
        let fieldFilteredJSON = """
        [{"id":1,"type":"post","title":{"rendered":"Hello"},"status":"publish",
          "date":"2024-01-01T00:00:00","modified":"2024-01-01T00:00:00",
          "slug":"hello","link":"https://example.com/hello"}]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            capturedQuery = request.url?.query
            let headers = ["X-WP-TotalPages": "1"]
            let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                           httpVersion: nil, headerFields: headers)!
            return (response, fieldFilteredJSON)
        }

        _ = try await client.fetchAllPosts()
        #expect(capturedQuery?.contains("_fields=") == true)
    }

    // fetchPost must NOT include _fields — it must return full content for the editor.
    // If _fields is accidentally added here, post content will be empty when opening a post.
    @Test func fetchPostRequestOmitsFieldsFilter() async throws {
        var capturedQuery: String?
        MockURLProtocol.requestHandler = { request in
            capturedQuery = request.url?.query
            let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                           httpVersion: nil, headerFields: nil)!
            return (response, minimalPostJSON.data(using: .utf8)!)
        }

        _ = try await client.fetchPost(id: 1)
        #expect(capturedQuery?.contains("_fields=") != true)
    }

    // MARK: - Media filters

    @Test func fetchMediaOmitsFilterParamsByDefault() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!,
                    "[]".data(using: .utf8)!)
        }
        _ = try await client.fetchMedia()
        let query = capturedRequest?.url?.query ?? ""
        #expect(query.contains("context=edit"))
        #expect(query.contains("media_type=") == false)
        #expect(query.contains("search=") == false)
    }

    @Test func fetchMediaSendsMediaTypeAndSearch() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!,
                    "[]".data(using: .utf8)!)
        }
        _ = try await client.fetchMedia(mediaType: "image", search: "sunset")
        let query = capturedRequest?.url?.query ?? ""
        #expect(query.contains("media_type=image"))
        #expect(query.contains("search=sunset"))
    }

    @Test func fetchMediaTreatsEmptyFilterStringsAsAbsent() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!,
                    "[]".data(using: .utf8)!)
        }
        _ = try await client.fetchMedia(mediaType: "", search: "")
        let query = capturedRequest?.url?.query ?? ""
        #expect(query.contains("media_type=") == false)
        #expect(query.contains("search=") == false)
    }

    // GallerySheet loops until a page holds an image; a dropped `page` never terminates.
    @Test func fetchMediaSendsTheRequestedPageAndPageSize() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!,
                    "[]".data(using: .utf8)!)
        }
        func value(_ name: String) -> String? {
            guard let url = capturedRequest?.url else { return nil }
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == name }?.value
        }

        _ = try await client.fetchMedia(page: 1, perPage: 30)
        #expect(value("page") == "1")
        #expect(value("per_page") == "30")

        _ = try await client.fetchMedia(page: 4, perPage: 30, mediaType: "image")
        #expect(value("page") == "4")
        #expect(value("per_page") == "30")
        #expect(value("media_type") == "image")
    }

    // MediaLibraryView pages by offset because it mutates its own window.
    @Test func fetchMediaOmitsOffsetUnlessAsked() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!,
                    "[]".data(using: .utf8)!)
        }
        func value(_ name: String) -> String? {
            guard let url = capturedRequest?.url else { return nil }
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == name }?.value
        }

        _ = try await client.fetchMedia(perPage: 30)
        #expect(value("offset") == nil)

        _ = try await client.fetchMedia(perPage: 30, offset: 29)
        #expect(value("offset") == "29")
        #expect(value("per_page") == "30")
    }
}
