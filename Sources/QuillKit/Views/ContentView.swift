import SwiftUI

public struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var onboarding = OnboardingModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var launchSidebarWidth = Self.clampedSidebarWidth(UserDefaults.standard.double(forKey: sidebarWidthKey))

    private static let sidebarWidthKey = "sidebarWidth"
    private static let sidebarWidthRange: ClosedRange<Double> = 260...400

    private static func clampedSidebarWidth(_ width: Double) -> Double {
        min(max(width, sidebarWidthRange.lowerBound), sidebarWidthRange.upperBound)
    }

    public init() {}

    public var body: some View {
        ZStack {
            if onboarding.showsPanel {
                OnboardingView(model: onboarding)
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView(columnVisibility: $columnVisibility)
                        .onGeometryChange(for: Double.self) { $0.size.width } action: { width in
                            guard columnVisibility != .detailOnly else { return }
                            UserDefaults.standard.set(Self.clampedSidebarWidth(width), forKey: Self.sidebarWidthKey)
                        }
                        .navigationSplitViewColumnWidth(
                            min: Self.sidebarWidthRange.lowerBound,
                            ideal: launchSidebarWidth,
                            max: Self.sidebarWidthRange.upperBound
                        )
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
        .task(id: appState.aiSettings?.apiKey) { await appState.loadAIModelsIfNeeded() }
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
