import SwiftUI

public struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        HSplitView {
            SidebarView()
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
            Group {
                if appState.selectedSection == .media {
                    MediaPickerView(mode: .browser)
                } else if let item = appState.selectedItem {
                    PostEditorView(item: item)
                } else {
                    EmptyEditorPlaceholder()
                }
            }
            .frame(minWidth: 500)
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
