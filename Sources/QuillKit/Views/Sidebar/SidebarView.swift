import AppKit
import SwiftUI

public struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var services: AppServices
    @Environment(\.openSettings) private var openSettings
    @State private var itemPendingDelete: PostItem? = nil
    @State private var deleteError: String? = nil

    public init() {}

    private var sectionSelection: Binding<SidebarSection> {
        Binding(
            get: { appState.selectedSection },
            set: { section in
                guard section != appState.selectedSection else { return }
                appState.selectedItem = nil
                appState.selectedMedia = nil
                appState.searchText = ""
                appState.selectedSection = section
            }
        )
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
        appState.selectedSection == .media ? "Search Media" : "Search"
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                SidebarSectionPicker(selection: sectionSelection)

                SidebarSearchField(text: searchBinding, prompt: searchPrompt)
                    .frame(height: 24)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)

            if appState.selectedSection != .media {
                postList
            } else {
                MediaSidebarSection()
            }
        }
        .navigationSplitViewColumnWidth(min: 260, ideal: 310, max: 400)
        .onChange(of: appState.selectedItem) { _, _ in releaseSearchFocus() }
        .onChange(of: appState.selectedSection) { _, _ in releaseSearchFocus() }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    Task { await loadCurrentSection() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh (\u{2318}R)")
                .accessibilityLabel("Refresh")

                Button {
                    appState.createNewDraft(type: "post", draftStore: services.draftStore)
                } label: {
                    Image(systemName: "note.text.badge.plus")
                }
                .help("New Post (\u{2318}N)")
                .accessibilityLabel("New Post")

                Button {
                    appState.createNewDraft(type: "page", draftStore: services.draftStore)
                } label: {
                    Image(systemName: "book.badge.plus")
                }
                .help("New Page (\u{21E7}\u{2318}N)")
                .accessibilityLabel("New Page")

                Button {
                    appState.selectedSection = .media
                    appState.triggerMediaUpload = true
                } label: {
                    Image(systemName: "photo.badge.plus")
                }
                .help("New Media (\u{2325}\u{2318}N)")
                .accessibilityLabel("New Media")
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
        List(selection: $appState.selectedItem) {
            if let error = appState.listError {
                listErrorRow(error)
            }
            ForEach(appState.filteredItems) { item in
                PostListRow(item: item)
                    .tag(item)
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
            if let update = appState.updateAvailable {
                updateRow(update)
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if appState.filteredItems.isEmpty && appState.hasLoadedList && !appState.isLoadingList {
                SidebarEmptyState(section: appState.selectedSection,
                                  isSearching: !appState.searchText.isEmpty)
            } else if !appState.hasLoadedList || appState.isLoadingList {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func listErrorRow(_ error: String) -> some View {
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
        appState.categories = []
        appState.tags = []
        do {
            async let posts = client.fetchAllPosts()
            async let pages = client.fetchAllPages()
            appState.posts = try await posts
            appState.pages = try await pages
            appState.localDrafts = (try? services.draftStore.fetchAll()) ?? []
            await loadTaxonomiesIfNeeded(client: client)
            appState.hasLoadedList = true
            appState.isLoadingList = false
            appState.lastLoadedCredentials = creds
        } catch is CancellationError {
            appState.isLoadingList = false
        } catch {
            appState.listError = error.localizedDescription
            appState.hasLoadedList = true
            appState.isLoadingList = false
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
            appState.listError = error.localizedDescription
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
            if appState.selectedItem == item {
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

struct SidebarEmptyState: View {
    let section: SidebarSection
    let isSearching: Bool

    private var icon: String {
        switch section {
        case .posts: return "doc.text"
        case .pages: return "doc.plaintext"
        case .localDrafts: return "pencil"
        case .media: return "photo"
        }
    }

    private var message: String {
        switch section {
        case .posts: return "No posts yet"
        case .pages: return "No pages yet"
        case .localDrafts: return "No drafts yet"
        case .media: return "No media yet"
        }
    }

    private var hint: String {
        switch section {
        case .posts: return "Create one with the new-post button in the toolbar"
        case .pages: return "Create one with the new-page button in the toolbar"
        case .localDrafts: return "Use File \u{2192} New Post/Page to start writing"
        case .media: return "Create one with the new-media button in the toolbar"
        }
    }

    var body: some View {
        if isSearching {
            ContentUnavailableView.search
        } else {
            ContentUnavailableView(message, systemImage: icon, description: Text(hint))
        }
    }
}
