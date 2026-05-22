import SwiftUI

public struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var services: AppServices

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            sectionTabs
            Divider()

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
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08))
                }

                List(appState.filteredItems, selection: $appState.selectedItem) { item in
                    PostListRow(item: item)
                        .tag(item)
                }
                .listStyle(.sidebar)

                Divider()
                HStack {
                    Button {
                        Task { await loadCurrentSection() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Refresh (⌘R)")
                    .padding(10)

                    Spacer()

                    Button {
                        createNewDraft()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.wpAmber)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("n", modifiers: .command)
                    .help("New Local Draft (⌘N)")
                    .padding(10)
                }
            }
        }
        .frame(minWidth: 220)
        .task(id: appState.selectedSection) {
            await loadCurrentSection()
        }
    }

    private var sectionTabs: some View {
        HStack(spacing: 0) {
            ForEach(SidebarSection.allCases, id: \.self) { section in
                let selected = appState.selectedSection == section
                Button {
                    appState.selectedSection = section
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: section.icon)
                            .font(.system(size: 14, weight: selected ? .semibold : .regular))
                        Text(section.shortTitle)
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(selected ? Color.wpAmber : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2)
    }

    private func createNewDraft() {
        guard let id = try? services.draftStore.create(
            title: "Untitled",
            content: "",
            excerpt: ""
        ) else { return }
        if let updated = try? services.draftStore.fetchAll(),
           let newDraft = updated.first(where: { $0.id == id }) {
            appState.localDrafts = updated
            appState.selectedSection = .localDrafts
            appState.selectedItem = .local(newDraft)
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
                appState.posts = try await client.fetchPosts()
            case .pages:
                appState.pages = try await client.fetchPages()
            case .localDrafts:
                appState.localDrafts = (try? services.draftStore.fetchAll()) ?? []
            case .media:
                break
            }
            await loadTaxonomiesIfNeeded(client: client)
        } catch {
            appState.listError = error.localizedDescription
        }
    }

    private func loadTaxonomiesIfNeeded(client: WordPressClient) async {
        if (try? services.taxonomyCache.isCategoryStale()) != false {
            if let cats = try? await client.fetchCategories() {
                try? services.taxonomyCache.saveCategories(cats)
                appState.categories = cats
            }
        } else {
            appState.categories = (try? services.taxonomyCache.loadCategories()) ?? []
        }
        if (try? services.taxonomyCache.isTagStale()) != false {
            if let tags = try? await client.fetchTags() {
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
                Button { text = "" } label: {
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
