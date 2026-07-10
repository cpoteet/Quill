import Foundation

public struct WPMedia: Identifiable, Codable, Sendable {
    public let id: Int
    public var title: RenderedString
    public var sourceURL: String
    public var mediaType: String  // "image", "file", etc.
    public var mimeType: String
    public var link: String       // WordPress attachment page URL
    public var date: String       // ISO8601, server local time
    public var altText: String
    public var mediaDetails: MediaDetails?

    public var thumbnailURL: String {
        if let url = mediaDetails?.sizes?["thumbnail"]?.sourceURL, !url.isEmpty {
            return url
        }
        return sourceURL
    }

    /// Resolves a WordPress size slug (e.g. "thumbnail", "medium", "large") to its URL,
    /// falling back to the full-resolution `sourceURL` when the slug is "full", unrecognized,
    /// or the matched size entry has no (or a blank) `source_url`.
    public func sizedURL(for sizeSlug: String) -> String {
        guard sizeSlug != "full", let url = mediaDetails?.sizes?[sizeSlug]?.sourceURL, !url.isEmpty else {
            return sourceURL
        }
        return url
    }

    enum CodingKeys: String, CodingKey {
        case id, title
        case sourceURL = "source_url"
        case mediaType = "media_type"
        case mimeType = "mime_type"
        case link, date
        case altText = "alt_text"
        case mediaDetails = "media_details"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(RenderedString.self, forKey: .title) ?? RenderedString(raw: "")
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType) ?? ""
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType) ?? ""
        link = try c.decodeIfPresent(String.self, forKey: .link) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        altText = try c.decodeIfPresent(String.self, forKey: .altText) ?? ""
        mediaDetails = try c.decodeIfPresent(MediaDetails.self, forKey: .mediaDetails)
    }
}

public struct MediaDetails: Codable, Sendable {
    public var width: Int?
    public var height: Int?
    public var sizes: [String: MediaSize]?

    enum CodingKeys: String, CodingKey { case width, height, sizes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // WordPress returns dimensions as floats on some installations (e.g. 2560.0).
        // Try Int first, fall back to Double→Int truncation.
        width = (try? c.decodeIfPresent(Int.self, forKey: .width))
            ?? (try? c.decodeIfPresent(Double.self, forKey: .width)).map(Int.init)
        height = (try? c.decodeIfPresent(Int.self, forKey: .height))
            ?? (try? c.decodeIfPresent(Double.self, forKey: .height)).map(Int.init)
        sizes = try? c.decodeIfPresent([String: MediaSize].self, forKey: .sizes)
    }
}

public struct MediaSize: Codable, Sendable {
    public var sourceURL: String
    public var width: Int
    public var height: Int

    enum CodingKeys: String, CodingKey {
        case sourceURL = "source_url"
        case width, height
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
        width = ((try? c.decodeIfPresent(Int.self, forKey: .width))
            ?? (try? c.decodeIfPresent(Double.self, forKey: .width)).map(Int.init)) ?? 0
        height = ((try? c.decodeIfPresent(Int.self, forKey: .height))
            ?? (try? c.decodeIfPresent(Double.self, forKey: .height)).map(Int.init)) ?? 0
    }
}
