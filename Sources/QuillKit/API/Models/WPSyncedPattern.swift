import Foundation

/// A synced pattern (`wp_block`), read with `context=edit` for its raw title.
public struct WPSyncedPattern: Decodable, Sendable {
    public let id: Int
    public let status: String
    public let title: String

    init(id: Int, status: String, title: String) {
        self.id = id
        self.status = status
        self.title = title
    }

    private struct Raw: Decodable { let raw: String? }
    private enum CodingKeys: String, CodingKey { case id, status, title }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        title = (try c.decodeIfPresent(Raw.self, forKey: .title)?.raw ?? "").decodingHTMLEntities()
    }
}

public enum SyncedPatternResult: Sendable {
    case loaded(WPSyncedPattern)
    case notFound
    case failed
}
