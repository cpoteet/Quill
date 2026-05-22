import SwiftUI

public struct PostListRow: View {
    let item: PostItem

    public init(item: PostItem) {
        self.item = item
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(.body)
                .lineLimit(2)
            HStack(spacing: 6) {
                StatusBadge(status: item.statusBadge)
                if case .remote(let post) = item {
                    Text(formattedDate(post.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func formattedDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate]
        guard let date = formatter.date(from: iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    var color: Color {
        switch status {
        case "publish": return .green
        case "draft":   return .orange
        case "future":  return .blue
        case "local":   return .purple
        default:        return .secondary
        }
    }
}
