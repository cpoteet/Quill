import SwiftUI

public struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            if appState.isSidebarVisible {
                SidebarView()
                    .frame(width: 240)
                    .transition(.move(edge: .leading))
                SoftPanelBoundary()
                    .transition(.move(edge: .leading))
            }
            Group {
                if appState.selectedSection == .media {
                    if let media = appState.selectedMedia {
                        MediaDetailView(media: media) { [media] altText in
                            guard let creds = appState.credentials else { return }
                            guard let idx = appState.mediaItems.firstIndex(where: { $0.id == media.id }) else { return }
                            do {
                                let updated = try await WordPressClient(credentials: creds)
                                    .updateMediaAltText(id: media.id, altText: altText)
                                appState.mediaItems[idx] = updated
                                if appState.selectedMedia?.id == updated.id {
                                    appState.selectedMedia = updated
                                }
                            } catch {
                                // Save failed silently — field retains the edited value
                            }
                        }
                        .id(media.id)
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
                } else if !appState.hasLoadedList || appState.isLoadingList {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.wpPanelBg)
                } else {
                    EmptyEditorPlaceholder(section: appState.selectedSection,
                                          sectionIsEmpty: appState.sectionIsEmpty)
                }
            }
            .frame(minWidth: 500, maxWidth: .infinity)
        }
        .animation(.easeInOut(duration: 0.2), value: appState.isSidebarVisible)
        .frame(minWidth: 900, minHeight: 600)
        .background(Color.wpPanelBg)
    }
}

struct EmptyEditorPlaceholder: View {
    let section: SidebarSection
    var sectionIsEmpty: Bool = false

    private var noun: String {
        switch section {
        case .posts: return "post"
        case .pages: return "page"
        case .localDrafts: return "draft"
        default: return "post"
        }
    }

    private var icon: String {
        switch section {
        case .posts: return "doc.text"
        case .pages: return "doc.plaintext"
        case .localDrafts: return "pencil"
        case .media: return "photo"
        }
    }

    private var message: String {
        if sectionIsEmpty {
            return "No \(noun)s yet"
        }
        return "Select a \(noun) to edit"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Color.wpAmber.opacity(0.5))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
