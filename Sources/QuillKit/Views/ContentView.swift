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
                        .navigationSplitViewColumnWidth(min: 260, ideal: 260, max: 400)
                } detail: {
                    detailContent
                        .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.wpContentSurface.ignoresSafeArea())
                        .background(SplitItemSizePin().frame(width: 0, height: 0))
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
        .task(id: appState.aiSettings?.apiKey) { await appState.loadAIModelsIfNeeded() }
        .task(id: appState.credentials?.siteKey) { await appState.refreshSiteProfile() }
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
        } else if appState.sectionIsEmpty && appState.sectionListError != nil {
            EmptyEditorPlaceholder(section: appState.selectedSection)
                .navigationTitle("Quill")
        } else {
            MastheadView(section: appState.selectedSection)
                .navigationTitle("Quill")
        }
    }
}

struct EmptyEditorPlaceholder: View {
    let section: SidebarSection

    private var message: String {
        switch section {
        case .posts: return "Couldn't load posts"
        case .pages: return "Couldn't load pages"
        case .localDrafts: return "Couldn't load drafts"
        case .media: return "Couldn't load media"
        }
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
