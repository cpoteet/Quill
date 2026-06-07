import Foundation

public struct WordPressClient: Sendable {
    private let credentials: Credentials
    private let session: URLSession

    // Shared ephemeral session — reuses the connection pool across all client instances.
    // Ephemeral config keeps URLSession away from the system keychain credential store.
    private static let sharedSession: URLSession = URLSession(configuration: .ephemeral)

    public init(credentials: Credentials, session: URLSession? = nil) {
        self.credentials = credentials
        self.session = session ?? Self.sharedSession
    }

    // MARK: - Posts

    public func fetchPosts(page: Int = 1, perPage: Int = 100) async throws -> [WPPost] {
        let url = try endpoint(
            "posts",
            query: [
                "per_page": "\(perPage)", "page": "\(page)", "context": "edit",
                "status": "publish,draft,private,future,pending",
            ])
        return try await get(url)
    }

    public func fetchPages(page: Int = 1, perPage: Int = 100) async throws -> [WPPost] {
        let url = try endpoint(
            "pages",
            query: [
                "per_page": "\(perPage)", "page": "\(page)", "context": "edit",
                "status": "publish,draft,private,future,pending",
            ])
        return try await get(url)
    }

    /// Fetches every post across all pages, following the `X-WP-TotalPages` header.
    public func fetchAllPosts(perPage: Int = 100) async throws -> [WPPost] {
        try await fetchAllPaginated(resource: "posts", perPage: perPage)
    }

    /// Fetches every page across all pages, following the `X-WP-TotalPages` header.
    public func fetchAllPages(perPage: Int = 100) async throws -> [WPPost] {
        try await fetchAllPaginated(resource: "pages", perPage: perPage)
    }

    private func fetchAllPaginated(resource: String, perPage: Int) async throws -> [WPPost] {
        var all: [WPPost] = []
        var page = 1
        var totalPages = 1
        repeat {
            let url = try endpoint(
                resource,
                query: [
                    "per_page": "\(perPage)", "page": "\(page)", "context": "edit",
                    "status": "publish,draft,private,future,pending",
                ])
            let request = authorizedRequest(url: url, method: "GET")
            let (data, http) = try await send(request)
            let batch: [WPPost]
            do {
                batch = try JSONDecoder().decode([WPPost].self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
            all.append(contentsOf: batch)
            if let header = http?.value(forHTTPHeaderField: "X-WP-TotalPages"),
               let parsed = Int(header) {
                totalPages = parsed
            }
            page += 1
        } while page <= totalPages
        return all
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
        let url = try endpoint(
            "media",
            query: ["per_page": "\(perPage)", "page": "\(page)", "context": "edit"]
        )
        return try await get(url)
    }

    public func fetchMediaItem(id: Int) async throws -> WPMedia {
        let url = try endpoint("media/\(id)", query: ["context": "edit"])
        return try await get(url)
    }

    public func uploadMedia(data: Data, filename: String, mimeType: String) async throws -> WPMedia {
        let url = try endpoint("media")
        var request = authorizedRequest(url: url, method: "POST")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        let fallback = WordPressClient.contentDispositionFilenameFallback(filename)
        let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fallback
        request.setValue(
            "attachment; filename=\"\(fallback)\"; filename*=UTF-8''\(encoded)",
            forHTTPHeaderField: "Content-Disposition"
        )
        request.httpBody = data
        return try await perform(request)
    }

    static func contentDispositionFilenameFallback(_ filename: String) -> String {
        filename
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .filter { $0.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value != 127 } }
    }

    public func deleteMedia(id: Int) async throws {
        let url = try endpoint("media/\(id)", query: ["force": "true"])
        let request = authorizedRequest(url: url, method: "DELETE")
        try await performVoid(request)
    }

    public func updateMediaAltText(id: Int, altText: String) async throws -> WPMedia {
        // WordPress accepts POST for partial media updates (only alt_text changes)
        let url = try endpoint("media/\(id)")
        return try await post(url, body: MediaAltPayload(altText: altText))
    }

    // MARK: - Taxonomies

    public func fetchAllCategories() async throws -> [WPCategory] {
        try await fetchAllPaginatedTaxonomy(resource: "categories")
    }

    public func fetchAllTags() async throws -> [WPTag] {
        try await fetchAllPaginatedTaxonomy(resource: "tags")
    }

    private func fetchAllPaginatedTaxonomy<T: Decodable>(resource: String) async throws -> [T] {
        var all: [T] = []
        var page = 1
        var totalPages = 1
        repeat {
            let url = try endpoint(resource, query: ["per_page": "100", "page": "\(page)"])
            let request = authorizedRequest(url: url, method: "GET")
            let (data, http) = try await send(request)
            let batch: [T]
            do { batch = try JSONDecoder().decode([T].self, from: data) }
            catch { throw APIError.decodingError(error) }
            all.append(contentsOf: batch)
            if let header = http?.value(forHTTPHeaderField: "X-WP-TotalPages"),
               let parsed = Int(header) { totalPages = parsed }
            page += 1
        } while page <= totalPages
        return all
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

    // MARK: - Search

    private struct WPSearchItem: Decodable {
        let id: Int
        let title: String   // plain string in /wp/v2/search (not a rendered object)
        let url: String
        let type: String    // "post" or "term"
        let subtype: String // "post", "page", "category", "tag"
    }

    public func searchLinks(query: String) async throws -> [LinkSearchResult] {
        let postsURL = try endpoint("search", query: [
            "search": query, "type": "post", "subtype": "post,page", "per_page": "5",
        ])
        let termsURL = try endpoint("search", query: [
            "search": query, "type": "term", "subtype": "category,tag", "per_page": "5",
        ])
        let mediaURL = try endpoint("media", query: [
            "search": query, "per_page": "3",
        ])

        async let postFetch: [WPSearchItem] = get(postsURL)
        async let termFetch: [WPSearchItem] = get(termsURL)
        async let mediaFetch: [WPMedia] = get(mediaURL)

        let posts  = (try? await postFetch)  ?? []
        let terms  = (try? await termFetch)  ?? []
        let medias = (try? await mediaFetch) ?? []

        var results: [LinkSearchResult] = []

        for item in posts {
            let type: LinkResultType = item.subtype == "page" ? .page : .post
            results.append(LinkSearchResult(
                id: "\(type.rawValue)-\(item.id)",
                wpId: item.id, title: item.title, url: item.url, type: type
            ))
        }
        for item in terms {
            let type: LinkResultType = item.subtype == "tag" ? .tag : .category
            results.append(LinkSearchResult(
                id: "\(type.rawValue)-\(item.id)",
                wpId: item.id, title: item.title, url: item.url, type: type
            ))
        }
        for item in medias {
            results.append(LinkSearchResult(
                id: "media-\(item.id)",
                wpId: item.id, title: item.title.rendered, url: item.sourceURL, type: .media
            ))
        }

        return results
    }

    // MARK: - Helpers

    private func endpoint(_ path: String, query: [String: String] = [:]) throws -> URL {
        guard
            var components = URLComponents(
                url: credentials.siteURL.appendingPathComponent("/wp-json/wp/v2/\(path)"),
                resolvingAgainstBaseURL: false
            )
        else { throw APIError.invalidURL }
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

    private struct MediaAltPayload: Encodable {
        let altText: String
        enum CodingKeys: String, CodingKey { case altText = "alt_text" }
    }

    /// Sends a request, mapping cancellation and HTTP errors. Returns the body data and
    /// the HTTP response (so callers can read pagination headers like `X-WP-TotalPages`).
    private func send(_ request: URLRequest) async throws -> (data: Data, http: HTTPURLResponse?) {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.networkError(error)
        }
        let http = response as? HTTPURLResponse
        if let http, http.statusCode >= 300 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(statusCode: http.statusCode, body: body)
        }
        return (data, http)
    }

    private func performVoid(_ request: URLRequest) async throws {
        _ = try await send(request)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, _) = try await send(request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}
