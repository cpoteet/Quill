import Foundation

public struct WPPost: Identifiable, Codable, Hashable, Sendable {
    public let id: Int
    public var type: String             // "post" or "page"
    public var title: RenderedString
    public var content: RenderedString
    public var excerpt: RenderedString
    public var status: String            // "publish", "draft", "future", "trash"
    public var date: String              // ISO8601, server local time
    public var dateGmt: String           // ISO8601, UTC — used for schedule round-trip
    public var modified: String          // ISO8601 — used for conflict detection
    public var slug: String
    public var link: String
    public var featuredMedia: Int        // media ID, 0 if none
    public var categories: [Int]
    public var tags: [Int]

    enum CodingKeys: String, CodingKey {
        case id, type, title, content, excerpt, status, date, modified, slug, link
        case dateGmt = "date_gmt"
        case featuredMedia = "featured_media"
        case categories, tags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(Int.self,            forKey: .id)
        type          = try c.decodeIfPresent(String.self, forKey: .type)          ?? "post"
        title         = try c.decode(RenderedString.self, forKey: .title)
        content       = try c.decode(RenderedString.self, forKey: .content)
        excerpt       = try c.decode(RenderedString.self, forKey: .excerpt)
        status        = try c.decode(String.self,         forKey: .status)
        date          = try c.decode(String.self,         forKey: .date)
        dateGmt       = try c.decodeIfPresent(String.self, forKey: .dateGmt) ?? ""
        modified      = try c.decode(String.self,         forKey: .modified)
        slug          = try c.decode(String.self,         forKey: .slug)
        link          = try c.decode(String.self,         forKey: .link)
        featuredMedia = try c.decodeIfPresent(Int.self,   forKey: .featuredMedia) ?? 0
        categories    = try c.decodeIfPresent([Int].self, forKey: .categories)    ?? []
        tags          = try c.decodeIfPresent([Int].self, forKey: .tags)          ?? []
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
