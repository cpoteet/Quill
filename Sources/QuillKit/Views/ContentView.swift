import SwiftUI

public struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var onboarding = OnboardingModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    public init() {}

    public var body: some View {
        ZStack {
            if onboarding.showsPanel {
                OnboardingView(model: onboarding)
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView(columnVisibility: $columnVisibility)
                        .navigationSplitViewColumnWidth(min: 260, ideal: 310, max: 400)
                } detail: {
                    detailContent
                        .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.wpContentSurface.ignoresSafeArea())
                }
            }
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            onboarding.appState = appState
            loadCredentialsAtLaunch()
        }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onOpenURL { url in Task { await onboarding.handleCallback(url) } }
    }

    private func loadCredentialsAtLaunch() {
        let creds = try? CredentialsStore.load()
        appState.credentials = creds
        guard creds == nil else { return }
        appState.isLoadingList = false
        appState.hasLoadedList = true
        appState.isLoadingMedia = false
        appState.hasLoadedMedia = true
    }

    @ViewBuilder
    private var detailContent: some View {
        if appState.selectedSection == .media {
            MediaLibraryView()
        } else if let item = appState.selectedItem {
            PostEditorView(item: item)
        } else if !appState.hasLoadedList || appState.isLoadingList {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Quill")
        } else {
            EmptyEditorPlaceholder(section: appState.selectedSection,
                                   sectionIsEmpty: appState.sectionIsEmpty,
                                   loadFailed: appState.sectionIsEmpty && appState.sectionListError != nil)
                .navigationTitle("Quill")
        }
    }
}

struct EmptyEditorPlaceholder: View {
    let section: SidebarSection
    var sectionIsEmpty: Bool = false
    var loadFailed: Bool = false

    private var noun: String {
        switch section {
        case .posts: return "post"
        case .pages: return "page"
        case .localDrafts: return "draft"
        case .media: return "image"
        }
    }

    private var message: String {
        if loadFailed {
            return section == .media ? "Couldn't load media" : "Couldn't load \(noun)s"
        }
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
