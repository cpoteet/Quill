import SwiftUI

public struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var services: AppServices

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $appState.selectedSection) {
                ForEach(SidebarSection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if appState.selectedSection != .media {
                SearchField(text: $appState.searchText)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)

                List(appState.filteredItems, selection: $appState.selectedItem) { item in
                    PostListRow(item: item)
                        .tag(item)
                }
                .listStyle(.sidebar)

                Divider()
                HStack {
                    Spacer()
                    Button {
                        createNewDraft()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .buttonStyle(.plain)
                    .help("New Local Draft")
                    .padding(8)
                }
            } else {
                Text("Media")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 220)
        .task(id: appState.selectedSection) {
            await loadCurrentSection()
        }
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
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.quinary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
