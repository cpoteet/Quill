import Foundation

public struct WPMedia: Identifiable, Codable, Sendable {
    public let id: Int
    public var title: RenderedString
    public var sourceURL: String
    public var mediaType: String  // "image", "file", etc.
    public var mimeType: String
    public var mediaDetails: MediaDetails?

    enum CodingKeys: String, CodingKey {
        case id, title
        case sourceURL = "source_url"
        case mediaType = "media_type"
        case mimeType = "mime_type"
        case mediaDetails = "media_details"
    }
}

public struct MediaDetails: Codable, Sendable {
    public var width: Int?
    public var height: Int?
    public var sizes: [String: MediaSize]?
}

public struct MediaSize: Codable, Sendable {
    public var sourceURL: String
    public var width: Int
    public var height: Int

    enum CodingKeys: String, CodingKey {
        case sourceURL = "source_url"
        case width, height
    }
}
