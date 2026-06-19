import Foundation

public enum LinkResultType: String, Sendable {
    case post, page, category, tag, media

    public var badge: String {
        switch self {
        case .post:     return "Post"
        case .page:     return "Page"
        case .category: return "Category"
        case .tag:      return "Tag"
        case .media:    return "Media"
        }
    }
}

public struct LinkSearchResult: Identifiable, Sendable {
    public let id: String   // e.g. "post-42", "category-7" — avoids collisions across types
    public let title: String
    public let url: String
    public let type: LinkResultType
}
