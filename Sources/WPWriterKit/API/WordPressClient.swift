import Foundation

public struct WordPressClient: Sendable {
    private let credentials: Credentials
    private let session: URLSession

    public init(credentials: Credentials, session: URLSession? = nil) {
        self.credentials = credentials
        if let session {
            self.session = session
        } else {
            // Use ephemeral configuration so URLSession never reads from or
            // writes to the system keychain credential store.
            let config = URLSessionConfiguration.ephemeral
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Posts

    public func fetchPosts(page: Int = 1, perPage: Int = 100) async throws -> [WPPost] {
        let url = try endpoint("posts", query: ["per_page": "\(perPage)", "page": "\(page)", "context": "edit", "status": "publish,draft,private,future,pending"])
        return try await get(url)
    }

    public func fetchPages(page: Int = 1, perPage: Int = 100) async throws -> [WPPost] {
        let url = try endpoint("pages", query: ["per_page": "\(perPage)", "page": "\(page)", "context": "edit", "status": "publish,draft,private,future,pending"])
        return try await get(url)
    }

    public func fetchPost(id: Int) async throws -> WPPost {
        let url = try endpoint("posts/\(id)", query: ["context": "edit"])
        return try await get(url)
    }

    public func fetchPage(id: Int) async throws -> WPPost {
        let url = try endpoint("pages/\(id)", query: ["context": "edit"])
        return try await get(url)
    }

    public func createPost(_ payload: PostPayload) async throws -> WPPost {
        let url = try endpoint("posts")
        return try await post(url, body: payload)
    }

    public func updatePost(id: Int, payload: PostPayload) async throws -> WPPost {
        let url = try endpoint("posts/\(id)")
        return try await put(url, body: payload)
    }

    public func createPage(_ payload: PostPayload) async throws -> WPPost {
        let url = try endpoint("pages")
        return try await post(url, body: payload)
    }

    public func updatePage(id: Int, payload: PostPayload) async throws -> WPPost {
        let url = try endpoint("pages/\(id)")
        return try await put(url, body: payload)
    }

    public func trashPost(id: Int) async throws {
        let url = try endpoint("posts/\(id)", query: ["force": "false"])
        let request = authorizedRequest(url: url, method: "DELETE")
        try await performVoid(request)
    }

    public func trashPage(id: Int) async throws {
        let url = try endpoint("pages/\(id)", query: ["force": "false"])
        let request = authorizedRequest(url: url, method: "DELETE")
        try await performVoid(request)
    }

    // MARK: - Media

    public func fetchMedia(page: Int = 1, perPage: Int = 50) async throws -> [WPMedia] {
        let url = try endpoint("media", query: ["per_page": "\(perPage)", "page": "\(page)"])
        return try await get(url)
    }

    public func uploadMedia(data: Data, filename: String, mimeType: String) async throws -> WPMedia {
        let url = try endpoint("media")
        var request = authorizedRequest(url: url, method: "POST")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
        request.setValue(
            "attachment; filename=\"\(filename)\"; filename*=UTF-8''\(encoded)",
            forHTTPHeaderField: "Content-Disposition"
        )
        request.httpBody = data
        return try await perform(request)
    }

    // MARK: - Taxonomies

    public func fetchCategories() async throws -> [WPCategory] {
        let url = try endpoint("categories", query: ["per_page": "100"])
        return try await get(url)
    }

    public func fetchTags() async throws -> [WPTag] {
        let url = try endpoint("tags", query: ["per_page": "100"])
        return try await get(url)
    }

    public func createTag(name: String) async throws -> WPTag {
        let url = try endpoint("tags")
        return try await post(url, body: TaxonomyPayload(name: name))
    }

    public func createCategory(name: String) async throws -> WPCategory {
        let url = try endpoint("categories")
        return try await post(url, body: TaxonomyPayload(name: name))
    }

    // MARK: - Autosave (for Preview)

    public func createAutosave(postID: Int, payload: PostPayload) async throws -> AutosaveResponse {
        let url = try endpoint("posts/\(postID)/autosaves")
        return try await post(url, body: payload)
    }

    public func createPageAutosave(postID: Int, payload: PostPayload) async throws -> AutosaveResponse {
        let url = try endpoint("pages/\(postID)/autosaves")
        return try await post(url, body: payload)
    }

    // MARK: - Helpers

    private func endpoint(_ path: String, query: [String: String] = [:]) throws -> URL {
        guard var components = URLComponents(
            url: credentials.siteURL.appendingPathComponent("/wp-json/wp/v2/\(path)"),
            resolvingAgainstBaseURL: false
        ) else { throw APIError.invalidURL }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }

    private func authorizedRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
        return request
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        let request = authorizedRequest(url: url, method: "GET")
        return try await perform(request)
    }

    private func post<T: Decodable, B: Encodable>(_ url: URL, body: B) async throws -> T {
        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private func put<T: Decodable, B: Encodable>(_ url: URL, body: B) async throws -> T {
        var request = authorizedRequest(url: url, method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private struct TaxonomyPayload: Encodable {
        let name: String
    }

    private func performVoid(_ request: URLRequest) async throws {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(statusCode: http.statusCode, body: body)
        }
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(statusCode: http.statusCode, body: body)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}
