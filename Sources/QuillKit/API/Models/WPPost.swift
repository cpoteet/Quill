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
        content = try c.decodeIfPresent(RenderedString.self, forKey: .content) ?? RenderedString(raw: "")
        excerpt = try c.decodeIfPresent(RenderedString.self, forKey: .excerpt) ?? RenderedString(raw: "")
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

    public var editorHTML: String {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return rendered
        }
        if raw.contains("<!-- wp:") || raw.contains("<p>") || raw.contains("<p ")
            || raw.contains("wp-block-") {
            return raw
        }
        return Self.wpautop(raw)
    }

    static func wpautop(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")

        let containers = "ul|ol|table|blockquote|pre|div|figure|h[1-6]|hr|section|article"

        if let re = try? NSRegularExpression(
            pattern: "(<(?:\(containers))(?:\\s[^>]*)?>)", options: .caseInsensitive
        ) {
            s = re.stringByReplacingMatches(
                in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "\n\n$1")
        }
        if let re = try? NSRegularExpression(
            pattern: "(</(?:\(containers))>)", options: .caseInsensitive
        ) {
            s = re.stringByReplacingMatches(
                in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1\n\n")
        }
        if let re = try? NSRegularExpression(
            pattern: "(<hr\\b[^>]*/?>)", options: .caseInsensitive
        ) {
            s = re.stringByReplacingMatches(
                in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1\n\n")
        }

        while s.contains("\n\n\n") {
            s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        let blocks = s.components(separatedBy: "\n\n")

        let wrapped = blocks.compactMap { block -> String? in
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            if Self.containsBlockTag(trimmed) { return trimmed }

            let withBreaks = trimmed.replacingOccurrences(of: "\n", with: "<br />\n")
            return "<p>\(withBreaks)</p>"
        }

        return wrapped.joined(separator: "\n\n")
    }

    private static func containsBlockTag(_ text: String) -> Bool {
        let lower = text.lowercased()
        let tags = [
            "<ul", "<ol", "<li", "<table", "<thead", "<tbody", "<tfoot",
            "<tr", "<td", "<th", "<blockquote", "<pre", "<div", "<figure",
            "<h1", "<h2", "<h3", "<h4", "<h5", "<h6", "<hr", "<section",
        ]
        return tags.contains { lower.contains($0) }
    }

    public var excerptText: String {
        if let raw {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "" }
            return trimmed.replacingOccurrences(
                of: "<[^>]+>", with: "", options: .regularExpression
            ).decodingHTMLEntities().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    public var decodedTitle: String {
        rendered.decodingHTMLEntities()
    }

    public init(raw: String) {
        // Local drafts have no server-rendered HTML; treat raw as the display value.
        self.rendered = raw
        self.raw = raw
    }
}

extension String {
    func decodingHTMLEntities() -> String {
        guard contains("&") else { return self }
        var result = self
        let named: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", "\u{00A0}"),
            ("&mdash;", "\u{2014}"), ("&ndash;", "\u{2013}"),
            ("&hellip;", "\u{2026}"), ("&lsquo;", "\u{2018}"),
            ("&rsquo;", "\u{2019}"), ("&ldquo;", "\u{201C}"),
            ("&rdquo;", "\u{201D}"),
        ]
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: nsRange).reversed()
            for match in matches {
                if let range = Range(match.range(at: 1), in: result),
                   let code = UInt32(result[range]),
                   let scalar = Unicode.Scalar(code) {
                    let charRange = Range(match.range, in: result)!
                    result.replaceSubrange(charRange, with: String(Character(scalar)))
                }
            }
        }
        if let regex = try? NSRegularExpression(pattern: "&#x([0-9a-fA-F]+);") {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: nsRange).reversed()
            for match in matches {
                if let range = Range(match.range(at: 1), in: result),
                   let code = UInt32(result[range], radix: 16),
                   let scalar = Unicode.Scalar(code) {
                    let charRange = Range(match.range, in: result)!
                    result.replaceSubrange(charRange, with: String(Character(scalar)))
                }
            }
        }
        for (entity, char) in named {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        return result
    }
}

public struct AutosaveResponse: Decodable, Sendable {
    public let link: String?
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
