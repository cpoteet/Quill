import SwiftUI

public struct PostListRow: View {
    let item: PostItem
    let isSelected: Bool

    public init(item: PostItem, isSelected: Bool) {
        self.item = item
        self.isSelected = isSelected
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.title)
                .font(.body.weight(.medium))
                .lineLimit(2)
            HStack(spacing: 5) {
                statusDot
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    /// Amber selection swallows the warm status colours, so a selected dot gets a white ring.
    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 6, height: 6)
            .overlay {
                if isSelected {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 1)
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityHidden(true)
    }

    private var statusColor: Color { Color.statusColor(item.statusBadge) }

    private var subtitle: String {
        guard case .remote(let post) = item else { return Self.subtitle(for: item, dateText: "") }
        return Self.subtitle(for: item, dateText: Self.formattedDate(post.date))
    }

    nonisolated static func statusLabel(_ status: String) -> String {
        switch status {
        case "publish": return "Published"
        case "draft":   return "Draft"
        case "future":  return "Scheduled"
        case "pending": return "Pending"
        case "private": return "Private"
        default:        return status.capitalized
        }
    }

    nonisolated static func subtitle(for item: PostItem, dateText: String) -> String {
        switch item {
        case .remote(let post):
            if post.type == "page" { return statusLabel(post.status) }
            return dateText + " \u{00B7} " + statusLabel(post.status)
        case .local(let draft):
            return "\(draft.type.capitalized) Draft"
        }
    }

    private static let dateFormatters: [DateFormatter] = {
        ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ssZZZZZ"].map { fmt in
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = fmt
            return df
        }
    }()

    nonisolated static func formattedDate(_ iso: String) -> String {
        for df in dateFormatters {
            if let date = df.date(from: iso) {
                return date.formatted(date: .abbreviated, time: .omitted)
            }
        }
        return String(iso.prefix(10))
    }
}
