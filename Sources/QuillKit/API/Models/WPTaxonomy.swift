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

public protocol NamedTaxonomy {
    var name: String { get }
}

extension WPCategory: NamedTaxonomy {}
extension WPTag: NamedTaxonomy {}

extension Array where Element: NamedTaxonomy {
    public func sortedByName() -> [Element] {
        sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
