import Foundation

/// A synced pattern (`wp_block`). Its controller exposes `title.raw` in view context.
public struct WPSyncedPattern: Decodable, Sendable {
    public let id: Int
    public let title: String
    public let hasPassword: Bool

    init(id: Int, title: String, hasPassword: Bool = false) {
        self.id = id
        self.title = title
        self.hasPassword = hasPassword
    }

    private struct Raw: Decodable { let raw: String? }
    private struct Content: Decodable { let protected: Bool? }
    private enum CodingKeys: String, CodingKey { case id, title, content }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = (try c.decodeIfPresent(Raw.self, forKey: .title)?.raw ?? "").decodingHTMLEntities()
        hasPassword = try c.decodeIfPresent(Content.self, forKey: .content)?.protected ?? false
    }
}

public enum SyncedPatternResult: Sendable {
    case loaded(WPSyncedPattern)
    case notFound
    case failed
}
