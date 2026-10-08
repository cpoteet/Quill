import AppKit
import SwiftUI

struct SidebarToggleButton: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility

    private var isHidden: Bool { columnVisibility == .detailOnly }

    var body: some View {
        Button {
            withAnimation { columnVisibility = isHidden ? .all : .detailOnly }
        } label: {
            Image(systemName: "sidebar.left")
        }
        .help(isHidden ? "Show Sidebar" : "Hide Sidebar")
        .accessibilityLabel(isHidden ? "Show Sidebar" : "Hide Sidebar")
    }
}

public struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var services: AppServices
    @State private var itemPendingDelete: PostItem? = nil
    @State private var deleteError: String? = nil

    @Binding private var columnVisibility: NavigationSplitViewVisibility
    @State private var isFullyOnScreen = true

    public init(columnVisibility: Binding<NavigationSplitViewVisibility>) {
        _columnVisibility = columnVisibility
    }

    private var sectionSelection: Binding<SidebarSection> {
        Binding(
            get: { appState.selectedSection },
            set: { section in
                guard section != appState.selectedSection else { return }
                appState.selectedItem = nil
                appState.selectedMedia = nil
                appState.searchText = ""
                appState.mediaSearchText = ""
                appState.selectedSection = section
            }
        )
    }

    // A save replaces the cached post but not `selectedItem`, so rows match the selection by id.
    private var itemSelection: Binding<PostItem.ID?> {
        Binding(
            get: { appState.selectedItem?.id },
            set: { id in
                guard id != appState.selectedItem?.id else { return }
                appState.selectedItem = appState.filteredItems.first { $0.id == id }
            }
        )
    }

    /// The WKWebView keeps first responder across a row click, which leaves the selection drawn unemphasized.
    private func focusPostList() {
        guard appState.selectedSection != .media else { return }
        guard let window = NSApp.keyWindow,
              let root = window.contentView,
              let table = Self.firstTableView(in: root) else { return }
        window.makeFirstResponder(table)
    }

    // The sidebar's list is the first table in the window; the inspector has none. If one is
    // ever added there, scope this instead of widening it.
    private static func firstTableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for sub in view.subviews {
            if let found = firstTableView(in: sub) { return found }
        }
        return nil
    }

    private func releaseSearchFocus() {
        guard let window = NSApp.keyWindow else { return }
        guard window.firstResponder is NSText || window.firstResponder is NSSearchField else { return }
        window.makeFirstResponder(nil)
    }

    private var searchBinding: Binding<String> {
        appState.selectedSection == .media ? $appState.mediaSearchText : $appState.searchText
    }

    private var searchPrompt: String {
        "Search \(appState.selectedSection.shortTitle)"
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                SidebarSectionPicker(selection: sectionSelection)

                HStack(spacing: 6) {
                    SidebarSearchField(text: searchBinding, prompt: searchPrompt)
                        .frame(height: 24)
                    if appState.selectedSection == .posts || appState.selectedSection == .pages {
                        SidebarStatusFilterButton()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)

            if appState.selectedSection != .media {
                postList
            } else {
                MediaSidebarSection()
            }
        }
        .toolbar(removing: .sidebarToggle)
        .background(SplitItemCollapseFix(behavior: .sidebar).frame(width: 0, height: 0))
        // Adding toolbar items while the column is still sliding in overflows them into a » menu.
        .onGeometryChange(for: Bool.self) { $0.frame(in: .global).minX >= 0 } action: { isFullyOnScreen = $0 }
        .onChange(of: appState.selectedItem) { _, _ in
            releaseSearchFocus()
            focusPostList()
        }
        .onChange(of: appState.selectedSection) { _, _ in releaseSearchFocus() }
        .onChange(of: appState.triggerRefresh) { _, newValue in
            guard newValue else { return }
            appState.triggerRefresh = false
            Task { await refresh() }
        }
        .toolbar {
            ToolbarItem {
                SidebarToggleButton(columnVisibility: $columnVisibility)
            }

            if isFullyOnScreen && columnVisibility != .detailOnly {
                ToolbarSpacer(.flexible)

                ToolbarItem {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh (\u{2318}R)")
                    .accessibilityLabel("Refresh")
                }

                ToolbarItem {
                    Menu {
                        Button("New Post", systemImage: "note.text.badge.plus") {
                            appState.createNewDraft(type: "post", draftStore: services.draftStore)
                        }
                        Button("New Page", systemImage: "book.badge.plus") {
                            appState.createNewDraft(type: "page", draftStore: services.draftStore)
                        }
                        Button("Upload Media\u{2026}", systemImage: "photo.badge.plus") {
                            appState.selectedSection = .media
                            appState.triggerMediaUpload = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("New")
                    .accessibilityLabel("New")
                }
            }
        }
        .alert(
            "Confirm Delete",
            isPresented: Binding(
                get: { itemPendingDelete != nil },
                set: { if !$0 { itemPendingDelete = nil } }
            ),
            presenting: itemPendingDelete
        ) { item in
            Button("Cancel", role: .cancel) { itemPendingDelete = nil }
            Button(deleteActionLabel(for: item), role: .destructive) {
                let target = item
                itemPendingDelete = nil
                Task { await performDelete(target) }
            }
        } message: { item in
            Text(deleteMessage(for: item))
        }
        .alert(
            "Delete Failed",
            isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .task(id: appState.credentials) {
            guard appState.credentials != appState.lastLoadedCredentials else { return }
            await loadAllSections()
        }
        .task {
            guard !appState.hasCheckedForUpdate else { return }
            // Only latch hasCheckedForUpdate on success (whether or not an update was found),
            // mirroring lastLoadedCredentials above — a transient network failure should retry
            // on the next remount, not be silently skipped for the rest of the session. Using
            // `try?` here would collapse "checked, no update" and "check failed" into the same
            // nil result, so an explicit do/catch is needed to tell them apart.
            do {
                appState.updateAvailable = try await UpdateChecker.check()
                appState.hasCheckedForUpdate = true
            } catch {
                // Leave hasCheckedForUpdate false so a later remount retries.
            }
        }
    }

    private var postList: some View {
        List(selection: itemSelection) {
            if let update = appState.updateAvailable {
                updateRow(update)
            }
            if let error = appState.sectionListError {
                SidebarErrorRow(failure: error)
            }
            ForEach(appState.filteredItems) { item in
                PostListRow(item: item, isSelected: appState.selectedItem?.id == item.id)
                    .tag(item.id)
                    .contextMenu {
                        Button(role: .destructive) {
                            itemPendingDelete = item
                        } label: {
                            switch item {
                            case .remote: Label("Move to Trash", systemImage: "trash")
                            case .local: Label("Delete Draft", systemImage: "trash")
                            }
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if appState.filteredItems.isEmpty && appState.hasLoadedList && !appState.isLoadingList
                && appState.sectionListError == nil {
                SectionEmptyState(section: appState.selectedSection,
                                  statusFilter: appState.statusFilter,
                                  isSearching: !appState.searchText.isEmpty)
            } else if !appState.hasLoadedList || appState.isLoadingList {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func updateRow(_ update: UpdateInfo) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Button("Quill \(update.version) available") {
                NSWorkspace.shared.open(update.url)
            }
            .buttonStyle(.link)
            Spacer()
            Button {
                UpdateChecker.dismiss(update.version)
                appState.updateAvailable = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
            .accessibilityLabel("Dismiss update notice")
        }
        .font(.subheadline)
        .padding(.vertical, 2)
    }

    private func loadAllSections() async {
        guard let creds = appState.credentials else {
            appState.isLoadingList = false
            appState.hasLoadedList = true
            return
        }
        appState.isLoadingList = true
        appState.listError = nil

        let client = WordPressClient(credentials: creds)
        // Clear taxonomy cache only when the WordPress site URL changes.
        // Clearing unconditionally on every launch defeats the 24-hour TTL.
        let siteKey = "TaxonomyCacheLastSiteURL"
        let currentSite = creds.siteURL.absoluteString
        if UserDefaults.standard.string(forKey: siteKey) != currentSite {
            try? services.taxonomyCache.clearAll()
            UserDefaults.standard.set(currentSite, forKey: siteKey)
        }
        try? services.autosaveStore.adoptUnsited(site: creds.siteKey)
        appState.categories = []
        appState.tags = []
        appState.localDrafts = (try? services.draftStore.fetchAll()) ?? []
        do {
            async let posts = client.fetchAllPosts()
            async let pages = client.fetchAllPages()
            appState.posts = try await posts
            appState.pages = try await pages
            await loadTaxonomiesIfNeeded(client: client)
            appState.hasLoadedList = true
            appState.isLoadingList = false
            appState.lastLoadedCredentials = creds
        } catch is CancellationError {
            appState.isLoadingList = false
        } catch {
            appState.listError = LoadFailure(error)
            appState.hasLoadedList = true
            appState.isLoadingList = false
        }
    }

    private func refresh() async {
        if appState.credentials != appState.lastLoadedCredentials {
            if appState.selectedSection == .media { appState.mediaRefreshToken += 1 }
            await loadAllSections()
        } else {
            await loadCurrentSection()
        }
    }

    func loadCurrentSection() async {
        guard let creds = appState.credentials else { return }
        appState.isLoadingList = true
        appState.listError = nil

        let client = WordPressClient(credentials: creds)
        do {
            switch appState.selectedSection {
            case .posts:
                appState.posts = try await client.fetchAllPosts()
            case .pages:
                appState.pages = try await client.fetchAllPages()
            case .localDrafts:
                appState.localDrafts = (try? services.draftStore.fetchAll()) ?? []
            case .media:
                appState.mediaRefreshToken += 1
            }
            await loadTaxonomiesIfNeeded(client: client)
            appState.hasLoadedList = true
            appState.isLoadingList = false
        } catch is CancellationError {
            appState.isLoadingList = false
        } catch {
            appState.listError = LoadFailure(error)
            appState.hasLoadedList = true
            appState.isLoadingList = false
        }
    }

    private func deleteActionLabel(for item: PostItem) -> String {
        switch item {
        case .remote: return "Move to Trash"
        case .local: return "Delete"
        }
    }

    private func deleteMessage(for item: PostItem) -> String {
        switch item {
        case .remote: return "\"\(item.title)\" will be moved to the WordPress Trash."
        case .local: return "\"\(item.title)\" will be permanently deleted."
        }
    }

    private func performDelete(_ item: PostItem) async {
        do {
            switch item {
            case .remote(let post):
                guard let creds = appState.credentials else { return }
                let client = WordPressClient(credentials: creds)
                if post.type == "page" {
                    try await client.trashPage(id: post.id)
                    appState.pages.removeAll { $0.id == post.id }
                } else {
                    try await client.trashPost(id: post.id)
                    appState.posts.removeAll { $0.id == post.id }
                }
            case .local(let draft):
                try services.draftStore.delete(id: draft.id)
                appState.localDrafts.removeAll { $0.id == draft.id }
            }
            if appState.selectedItem?.id == item.id {
                appState.selectedItem = nil
            }
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private func loadTaxonomiesIfNeeded(client: WordPressClient) async {
        if (try? services.taxonomyCache.isCategoryStale()) != false {
            if let cats = try? await client.fetchAllCategories() {
                try? services.taxonomyCache.saveCategories(cats)
                appState.categories = cats
            }
        } else {
            appState.categories = (try? services.taxonomyCache.loadCategories()) ?? []
        }
        if (try? services.taxonomyCache.isTagStale()) != false {
            if let tags = try? await client.fetchAllTags() {
                try? services.taxonomyCache.saveTags(tags)
                appState.tags = tags
            }
        } else {
            appState.tags = (try? services.taxonomyCache.loadTags()) ?? []
        }
    }
}

struct SidebarErrorRow: View {
    let failure: LoadFailure
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings

    nonisolated private static let capHeight = NSFont.preferredFont(forTextStyle: .subheadline).capHeight
    // Measured gap between the large-scale symbol's frame top and the triangle's apex.
    nonisolated private static let triangleTopInset: CGFloat = 1.5

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .imageScale(.large)
                .alignmentGuide(.firstTextBaseline) { $0[.top] + Self.triangleTopInset + Self.capHeight }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(failure.message)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Button("Retry") { appState.triggerRefresh = true }
                    if failure.needsSettings {
                        Button("Open Blog Settings…") { openSettings() }
                    }
                }
                .controlSize(.small)
            }
        }
        .font(.subheadline)
        .padding(.vertical, 6)
    }
}

struct SectionEmptyState: View {
    let section: SidebarSection
    var mediaFilter: MediaFilter = .all
    var statusFilter: PostStatusFilter = .all
    let isSearching: Bool

    private var message: String {
        if section == .media, mediaFilter != .all {
            return "No \(mediaFilter.title.lowercased())"
        }
        if statusFilter != .all {
            return "No \(statusFilter.title(in: section).lowercased()) \(section.shortTitle.lowercased())"
        }
        switch section {
        case .posts: return "No posts yet"
        case .pages: return "No pages yet"
        case .localDrafts: return "No drafts yet"
        case .media: return "No media yet"
        }
    }

    private var hint: String {
        if section == .media, mediaFilter != .all {
            return "Choose All Media to see everything in your library"
        }
        if statusFilter != .all {
            return "Choose \(PostStatusFilter.all.title(in: section)) to see everything"
        }
        switch section {
        case .posts: return "Create one from the + menu in the toolbar"
        case .pages: return "Create one from the + menu in the toolbar"
        case .localDrafts: return "Use File \u{2192} New Post/Page to start writing"
        case .media: return "Create one from the + menu in the toolbar"
        }
    }

    var body: some View {
        if isSearching {
            ContentUnavailableView.search
        } else {
            ContentUnavailableView {
                Label {
                    Text(message)
                } icon: {
                    QuillMark.emptyStateIcon
                }
            } description: {
                Text(hint)
            }
        }
    }
}
