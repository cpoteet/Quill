import Foundation

struct BlockRiskAlarm: Equatable {
    enum Stage: Equatable { case unacknowledged, acknowledged, saved }

    var names: [String]
    var stage: Stage

    var blocksSaving: Bool { stage == .unacknowledged }

    private var displayNames: [String] { names.map(Self.displayName(for:)) }
    private var isSingular: Bool { names.count == 1 }

    var title: String {
        switch stage {
        case .unacknowledged:
            return "Saving this post would delete content"
        case .acknowledged:
            return isSingular
                ? "Saving will delete a \(displayNames[0]) block"
                : "Saving will delete \(names.count) blocks"
        case .saved:
            return ""
        }
    }

    var body: String {
        switch stage {
        case .unacknowledged:
            let subject = isSingular
                ? "A \(displayNames[0]) block didn't survive loading into Quill"
                : "\(Self.list(displayNames)) blocks didn't survive loading into Quill"
            let object = isSingular ? "it" : "them"
            return "\(subject), so saving from here would remove \(object) from the published post. "
                + "This is a Quill limitation, not a problem with your post."
        case .acknowledged:
            return "You chose to save anyway. Quill won't ask again for this post."
        case .saved:
            let subject = isSingular ? "A \(displayNames[0]) block was" : "\(Self.list(displayNames)) blocks were"
            return "\(subject) removed from this post. You can restore \(isSingular ? "it" : "them") "
                + "from the post's revision history in WordPress."
        }
    }

    private static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }

    private static let known: [String: String] = [
        "block": "Synced Pattern",
        "nextpage": "Page Break",
        "more": "Read More",
        "html": "Custom HTML",
    ]

    static func displayName(for blockName: String) -> String {
        let bare = blockName.hasPrefix("core/") ? String(blockName.dropFirst(5)) : blockName
        if let known = known[bare] { return known }
        return bare
            .split(whereSeparator: { $0 == "-" || $0 == "/" })
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
