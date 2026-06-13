import SwiftUI

public struct PostListRow: View {
    let item: PostItem
    var isSelected: Bool

    public init(item: PostItem, isSelected: Bool = false) {
        self.item = item
        self.isSelected = isSelected
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .foregroundStyle(isSelected ? Color.wpAmber : Color.primary)
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(subtitle)
                    .font(.system(size: 11))
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
            case "pending": return date + " · Pending"
            case "private": return date + " · Private"
            default: return date
            }
        case .local(let draft): return "\(draft.type.capitalized) Draft"
        }
    }

    private func formattedDate(_ iso: String) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ssZZZZZ"] {
            df.dateFormat = fmt
            if let date = df.date(from: iso) {
                return date.formatted(date: .abbreviated, time: .omitted)
            }
        }
        return String(iso.prefix(10))
    }
}
