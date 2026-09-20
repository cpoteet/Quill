import SwiftUI

public struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            detailContent
                .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.wpContentSurface.ignoresSafeArea())
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .frame(minWidth: 900, minHeight: 600)
        .onAppear(perform: loadCredentialsAtLaunch)
    }

    private func loadCredentialsAtLaunch() {
        let creds = try? CredentialsStore.load()
        appState.credentials = creds
        guard creds == nil else { return }
        appState.isLoadingList = false
        appState.hasLoadedList = true
        appState.isLoadingMedia = false
        appState.hasLoadedMedia = true
        openSettings()
    }

    @ViewBuilder
    private var detailContent: some View {
        if appState.selectedSection == .media {
            MediaLibraryView()
                .navigationTitle(appState.selectedMedia?.title.decodedTitle ?? "Media")
                .toolbar {
                    ToolbarSpacer(.flexible)
                    ToolbarItem {
                        Button {
                            withAnimation { appState.isMediaInspectorOpen.toggle() }
                        } label: {
                            Image(systemName: "sidebar.right")
                        }
                        .help("Media Info")
                        .accessibilityLabel("Media Info")
                    }
                }
                .inspector(isPresented: $appState.isMediaInspectorOpen) {
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
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
                    } else {
                        Text("No Selection")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
                    }
                }
        } else if let item = appState.selectedItem {
            PostEditorView(item: item)
        } else if !appState.hasLoadedList || appState.isLoadingList {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Quill")
        } else {
            EmptyEditorPlaceholder(section: appState.selectedSection,
                                   sectionIsEmpty: appState.sectionIsEmpty)
                .navigationTitle("Quill")
        }
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
        case .media: return "image"
        }
    }

    private var message: String {
        if sectionIsEmpty {
            return "No \(noun)s yet"
        }
        return "Select a \(noun) to edit"
    }

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(message)
            } icon: {
                QuillMark.emptyStateIcon
            }
        }
    }
}
