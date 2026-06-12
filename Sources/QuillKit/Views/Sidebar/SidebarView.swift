import SwiftUI

public struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var services: AppServices
    @State private var itemPendingDelete: PostItem? = nil
    @State private var deleteError: String? = nil

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            sectionTabs
            SoftHorizontalDivider()

            if appState.selectedSection != .media {
                SearchField(text: $appState.searchText)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                if appState.isLoadingList {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.65)
                        Text("Loading…")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
                }

                if let error = appState.listError {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(.top, 1)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button("Open Blog Settings") {
                            appState.isShowingPreferences = true
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08))
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.filteredItems) { item in
                            let rowSelected = appState.selectedItem == item
                            Button {
                                appState.selectedItem = item
                            } label: {
                                HStack(spacing: 0) {
                                    Rectangle()
                                        .fill(rowSelected ? Color.wpAmber : Color.clear)
                                        .frame(width: 2.5)
                                    PostListRow(item: item, isSelected: rowSelected)
                                        .padding(.leading, 9.5)
                                        .padding(.trailing, 12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .background(rowSelected ? Color.wpAmber.opacity(0.12) : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
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
                }
                .overlay(alignment: .trailing) { PanelInteriorFade(from: .trailing) }

                SoftHorizontalDivider()
                HStack {
                    Button {
                        Task { await loadCurrentSection() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(Color.primary.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Refresh (⌘R)")
                    .padding(.leading, 10)
                    .padding(.vertical, 8)

                    Spacer()

                    if appState.selectedSection != .localDrafts {
                        Button {
                            createNewDraft()
                        } label: {
                            Label(newButtonTitle, systemImage: "plus")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.wpAmber)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.wpAmber.opacity(0.10),
                                            in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("n", modifiers: .command)
                        .help("\(newButtonTitle) (⌘N)")
                        .padding(.trailing, 10)
                        .padding(.vertical, 8)
                    }
                }
            } else {
                MediaSidebarSection()
            }
        }
        .frame(minWidth: 220)
        .background(WarmSidebarBackground().ignoresSafeArea())
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
            await loadAllSections()
        }
    }

    private var sectionTabs: some View {
        HStack(spacing: 4) {
            ForEach(SidebarSection.allCases, id: \.self) { section in
                let selected = appState.selectedSection == section
                Button {
                    if appState.selectedSection != section { appState.selectedItem = nil }
                    appState.selectedSection = section
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: section.icon)
                            .font(.system(size: 14, weight: .medium))
                            .frame(height: 18)
                        Text(section.shortTitle)
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.wpAmber.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(Color.wpAmber.opacity(0.30), lineWidth: 0.5)
                                )
                        }
                    }
                    .foregroundStyle(selected ? Color.wpAmber : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private var newButtonTitle: String {
        switch appState.selectedSection {
        case .posts: return "New Post"
        case .pages: return "New Page"
        case .localDrafts: return "New Draft"
        case .media: return "New Media"
        }
    }

    private func createNewDraft() {
        let type = appState.selectedSection == .pages ? "page" : "post"
        appState.createNewDraft(type: type, draftStore: services.draftStore)
    }

    private func loadAllSections() async {
        guard let creds = appState.credentials else { return }
        appState.isLoadingList = true
        appState.listError = nil
        defer { appState.isLoadingList = false }

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
        } catch is CancellationError {
            // normal view lifecycle cancellation — not an error
        } catch {
            appState.listError = error.localizedDescription
        }
    }

    private func loadCurrentSection() async {
        guard let creds = appState.credentials else { return }
        appState.isLoadingList = true
        appState.listError = nil
        defer { appState.isLoadingList = false }

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
                break
            }
            await loadTaxonomiesIfNeeded(client: client)
        } catch is CancellationError {
            // normal view lifecycle cancellation — not an error
        } catch {
            appState.listError = error.localizedDescription
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

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            TextField("Search", text: $text)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
