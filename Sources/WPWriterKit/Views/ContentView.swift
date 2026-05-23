import SwiftUI

public struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 240)
            Divider()
            Group {
                if appState.selectedSection == .media {
                    if let media = appState.selectedMedia {
                        MediaDetailView(media: media)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "photo")
                                .font(.system(size: 38, weight: .light))
                                .foregroundStyle(Color.wpAmber.opacity(0.5))
                            Text("Select an image to preview")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.wpPanelBg)
                    }
                } else if let item = appState.selectedItem {
                    PostEditorView(item: item)
                } else {
                    EmptyEditorPlaceholder()
                }
            }
            .frame(minWidth: 500, maxWidth: .infinity)
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

struct EmptyEditorPlaceholder: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Color.wpAmber.opacity(0.5))
            Text("Select a post to edit")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
