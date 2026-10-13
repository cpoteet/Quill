import Foundation

/// A synced pattern (`wp_block`), read with `context=edit` for its raw title and content.
public struct WPSyncedPattern: Decodable, Sendable {
    public let id: Int
    public let status: String
    public let title: String
    public let content: String

    init(id: Int, status: String, title: String, content: String) {
        self.id = id
        self.status = status
        self.title = title
        self.content = content
    }

    private struct Raw: Decodable { let raw: String? }
    private enum CodingKeys: String, CodingKey { case id, status, title, content }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        title = (try c.decodeIfPresent(Raw.self, forKey: .title)?.raw ?? "").decodingHTMLEntities()
        content = try c.decodeIfPresent(Raw.self, forKey: .content)?.raw ?? ""
    }
}

public enum SyncedPatternResult: Sendable {
    case loaded(WPSyncedPattern)
    case notFound
    case failed
}
