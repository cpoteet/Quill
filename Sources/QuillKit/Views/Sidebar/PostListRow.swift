import SwiftUI

public struct PostListRow: View {
    let item: PostItem

    public init(item: PostItem) {
        self.item = item
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.title)
                .font(.body.weight(.medium))
                .lineLimit(2)
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var statusColor: Color { Color.statusColor(item.statusBadge) }

    private var subtitle: String {
        switch item {
        case .remote(let post):
            if post.type == "page" {
                switch post.status {
                case "publish": return "Published"
                case "draft":   return "Draft"
                case "private": return "Private"
                case "pending": return "Pending"
                case "future":  return "Scheduled"
                default:        return post.status.capitalized
                }
            }
            let date = formattedDate(post.date)
            switch post.status {
            case "publish": return date + " · Published"
            case "draft":   return date + " · Draft"
            case "future":  return date + " · Scheduled"
            case "pending": return date + " · Pending"
            case "private": return date + " · Private"
            default:        return date + " · " + post.status.capitalized
            }
        case .local(let draft): return "\(draft.type.capitalized) Draft"
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

    private func formattedDate(_ iso: String) -> String {
        for df in Self.dateFormatters {
            if let date = df.date(from: iso) {
                return date.formatted(date: .abbreviated, time: .omitted)
            }
        }
        return String(iso.prefix(10))
    }
}
