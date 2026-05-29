import Foundation

public struct WPPost: Identifiable, Codable, Hashable, Sendable {
    public let id: Int
    public var type: String  // "post" or "page"
    public var title: RenderedString
    public var content: RenderedString
    public var excerpt: RenderedString
    public var status: String  // "publish", "draft", "future", "trash"
    public var date: String  // ISO8601, server local time
    public var dateGmt: String  // ISO8601, UTC — used for schedule round-trip
    public var modified: String  // ISO8601 — used for conflict detection
    public var slug: String
    public var link: String
    public var featuredMedia: Int  // media ID, 0 if none
    public var categories: [Int]
    public var tags: [Int]
    public var parent: Int          // page parent ID, 0 = top-level
    public var commentStatus: String  // "open" or "closed"

    enum CodingKeys: String, CodingKey {
        case id, type, title, content, excerpt, status, date, modified, slug, link, parent
        case dateGmt = "date_gmt"
        case featuredMedia = "featured_media"
        case categories, tags
        case commentStatus = "comment_status"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "post"
        title = try c.decode(RenderedString.self, forKey: .title)
        content = try c.decode(RenderedString.self, forKey: .content)
        excerpt = try c.decode(RenderedString.self, forKey: .excerpt)
        status = try c.decode(String.self, forKey: .status)
        date = try c.decode(String.self, forKey: .date)
        dateGmt = try c.decodeIfPresent(String.self, forKey: .dateGmt) ?? ""
        modified = try c.decode(String.self, forKey: .modified)
        slug = try c.decode(String.self, forKey: .slug)
        link = try c.decode(String.self, forKey: .link)
        featuredMedia = try c.decodeIfPresent(Int.self, forKey: .featuredMedia) ?? 0
        categories = try c.decodeIfPresent([Int].self, forKey: .categories) ?? []
        tags = try c.decodeIfPresent([Int].self, forKey: .tags) ?? []
        parent = try c.decodeIfPresent(Int.self, forKey: .parent) ?? 0
        commentStatus = try c.decodeIfPresent(String.self, forKey: .commentStatus) ?? "open"
    }
}

public struct RenderedString: Codable, Hashable, Sendable {
    public var rendered: String
    public var raw: String?

    public init(raw: String) {
        // Local drafts have no server-rendered HTML; treat raw as the display value.
        self.rendered = raw
        self.raw = raw
    }
}

public struct AutosaveResponse: Decodable, Sendable {
    public let link: String?
    public let parent: Int?
}

public struct PostPayload: Encodable, Sendable {
    public var title: String
    public var content: String
    public var excerpt: String
    public var status: String
    public var dateGmt: String?  // UTC — sent as date_gmt so WordPress treats it unambiguously as UTC
    public var featuredMedia: Int?
    public var categories: [Int]
    public var tags: [Int]
    public var slug: String?
    public var commentStatus: String?
    public var parent: Int?

    enum CodingKeys: String, CodingKey {
        case title, content, excerpt, status, slug, parent
        case dateGmt = "date_gmt"
        case featuredMedia = "featured_media"
        case categories, tags
        case commentStatus = "comment_status"
    }

    public init(
        title: String,
        content: String,
        excerpt: String = "",
        status: String,
        dateGmt: String? = nil,
        featuredMedia: Int? = nil,
        categories: [Int] = [],
        tags: [Int] = [],
        slug: String? = nil,
        commentStatus: String? = nil,
        parent: Int? = nil
    ) {
        self.title = title
        self.content = content
        self.excerpt = excerpt
        self.status = status
        self.dateGmt = dateGmt
        self.featuredMedia = featuredMedia
        self.categories = categories
        self.tags = tags
        self.slug = slug
        self.commentStatus = commentStatus
        self.parent = parent
    }
}
