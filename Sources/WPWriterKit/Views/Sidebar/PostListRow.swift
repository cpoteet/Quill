import SwiftUI

public struct PostListRow: View {
    let item: PostItem

    public init(item: PostItem) {
        self.item = item
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .foregroundStyle(.primary)
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private var statusColor: Color {
        switch item.statusBadge {
        case "publish": return .green
        case "draft":   return Color.wpAmber
        case "future":  return .blue
        case "local":   return .purple
        default:        return Color(.tertiaryLabelColor)
        }
    }

    private var subtitle: String {
        if case .remote(let post) = item {
            return formattedDate(post.date)
        }
        return "local draft"
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
