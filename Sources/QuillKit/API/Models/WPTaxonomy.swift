import Foundation

public struct WPCategory: Identifiable, Codable, Sendable {
    public let id: Int
    public var name: String
    public var slug: String
    public var count: Int
    public var parent: Int
}

public struct WPTag: Identifiable, Codable, Sendable {
    public let id: Int
    public var name: String
    public var slug: String
    public var count: Int
}
