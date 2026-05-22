import Foundation

public struct WPPost: Identifiable, Codable, Hashable, Sendable {
    public let id: Int
    public var title: RenderedString
    public var content: RenderedString
    public var excerpt: RenderedString
    public var status: String            // "publish", "draft", "future", "trash"
    public var date: String              // ISO8601, server local time
    public var modified: String          // ISO8601 — used for conflict detection
    public var slug: String
    public var link: String
    public var featuredMedia: Int        // media ID, 0 if none
    public var categories: [Int]
    public var tags: [Int]

    enum CodingKeys: String, CodingKey {
        case id, title, content, excerpt, status, date, modified, slug, link
        case featuredMedia = "featured_media"
        case categories, tags
    }
}

public struct RenderedString: Codable, Hashable, Sendable {
    public var rendered: String
    public var raw: String?

    public init(raw: String) {
        self.rendered = raw
        self.raw = raw
    }
}

public struct PostPayload: Encodable, Sendable {
    public var title: String
    public var content: String
    public var excerpt: String
    public var status: String
    public var date: String?
    public var featuredMedia: Int?
    public var categories: [Int]
    public var tags: [Int]

    enum CodingKeys: String, CodingKey {
        case title, content, excerpt, status, date
        case featuredMedia = "featured_media"
        case categories, tags
    }

    public init(
        title: String,
        content: String,
        excerpt: String = "",
        status: String,
        date: String? = nil,
        featuredMedia: Int? = nil,
        categories: [Int] = [],
        tags: [Int] = []
    ) {
        self.title = title
        self.content = content
        self.excerpt = excerpt
        self.status = status
        self.date = date
        self.featuredMedia = featuredMedia
        self.categories = categories
        self.tags = tags
    }
}
