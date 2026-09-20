import SwiftUI

struct MediaSidebarSection: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        List(selection: $appState.mediaFilter) {
            ForEach(MediaFilter.allCases) { filter in
                Label(filter.title, systemImage: filter.icon)
                    .tag(filter)
            }
            if let error = appState.mediaError {
                errorRow(error)
            }
        }
        .listStyle(.sidebar)
    }

    private func errorRow(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Blog Settings") { openSettings() }
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}
