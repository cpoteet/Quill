import Combine
import Foundation

public enum SidebarSection: String, Hashable, CaseIterable {
    case posts = "Posts"
    case pages = "Pages"
    case localDrafts = "Local Drafts"
    case media = "Media"

    var icon: String {
        switch self {
        case .posts: return "doc.text"
        case .pages: return "doc.plaintext"
        case .localDrafts: return "pencil"
        case .media: return "photo"
        }
    }

    var shortTitle: String {
        switch self {
        case .posts: return "Posts"
        case .pages: return "Pages"
        case .localDrafts: return "Drafts"
        case .media: return "Media"
        }
    }
}

public enum PostStatusFilter: String, Hashable, CaseIterable {
    case all, publish, draft, future, pending, `private`

    func title(in section: SidebarSection) -> String {
        self == .all ? "All \(section.shortTitle)" : PostListRow.statusLabel(rawValue)
    }

    func matches(_ post: WPPost) -> Bool {
        self == .all || post.status == rawValue
    }
}

private extension WPPost {
    // `date` is the site's wall clock, which runs backwards when clocks go back.
    var publishSortKey: String { dateGmt.isEmpty ? date : dateGmt }
}

public enum PostItem: Identifiable, Hashable {
    case remote(WPPost)
    case local(LocalDraft)

    public var id: String {
        switch self {
        case .remote(let p): return "remote-\(p.id)"
        case .local(let d): return "local-\(d.id)"
        }
    }

    public var isRemote: Bool {
        if case .remote = self { return true }
        return false
    }

    public var title: String {
        switch self {
        case .remote(let p): return p.title.rendered.isEmpty ? "Untitled" : p.title.decodedTitle
        case .local(let d): return d.title.isEmpty ? "Untitled" : d.title
        }
    }

    public var statusBadge: String {
        switch self {
        case .remote(let p): return p.status
        case .local(let d): return "local-\(d.type)"
        }
    }
}

public final class AppState: ObservableObject {
    @Published public var selectedSection: SidebarSection = .posts
    @Published public var selectedItem: PostItem?
    @Published public var searchText: String = ""
    @Published private var postStatusFilter: PostStatusFilter = .all
    @Published private var pageStatusFilter: PostStatusFilter = .all
    @Published public var credentials: Credentials?
    /// Asked once per connection, the first time the Custom HTML sheet opens; nil until WordPress answers.
    @Published public var canPostUnfilteredHTML: Bool?

    @Published public var posts: [WPPost] = []
    @Published public var pages: [WPPost] = []
    @Published public var localDrafts: [LocalDraft] = []
    @Published private var categoriesStorage: [WPCategory] = []
    @Published private var tagsStorage: [WPTag] = []

    // Sorted on assignment so PostSettingsPanel never sorts per render — see docs/gotchas.md.
    public var categories: [WPCategory] {
        get { categoriesStorage }
        set { categoriesStorage = newValue.sortedByName() }
    }

    public var tags: [WPTag] {
        get { tagsStorage }
        set { tagsStorage = newValue.sortedByName() }
    }

    @Published public var isLoadingList: Bool = true
    @Published public var hasLoadedList: Bool = false
    @Published public var listError: LoadFailure?
    // Set only after a successful loadAllSections() — lets SidebarView skip
    // refetching everything when it remounts (sidebar hide/show) with unchanged credentials.
    @Published public var lastLoadedCredentials: Credentials?
    @Published public var hasCheckedForUpdate: Bool = false

    @Published public var mediaItems: [WPMedia] = []
    @Published public var selectedMedia: WPMedia?
    @Published public var isLoadingMedia: Bool = true
    @Published public var hasLoadedMedia: Bool = false
    @Published public var mediaError: LoadFailure?

    @Published public var aiSettings: AISettings?
    @Published public var triggerMediaUpload: Bool = false
    @Published public var mediaFilter: MediaFilter = .all
    @Published public var mediaSearchText: String = ""
    @Published public var mediaRefreshToken: Int = 0
    @Published public var isMediaInspectorOpen: Bool = false
    @Published public var triggerShowMediaDetails: Bool = false
    @Published public var triggerFindBar: Bool = false
    @Published public var triggerPasteMarkdown: Bool = false
    @Published public var triggerSave: Bool = false
    @Published public var triggerPublish: Bool = false
    @Published public var triggerPreview: Bool = false
    @Published public var triggerRevert: Bool = false
    @Published public var triggerRefresh: Bool = false

    // Mirrored from PostEditorView so the File menu can enable its items; the editor is
    // the only writer.
    @Published public var editorIsDirty: Bool = false
    @Published public var editorIsSaving: Bool = false
    @Published public var editorPublishTitle: String = "Publish"
    @Published public var updateAvailable: UpdateInfo?

    // Registered by the open editor; awaited before Quill quits and before the site changes.
    var persistOpenPost: (owner: UUID, run: @MainActor () async -> Void)?

    public var aiEnabled: Bool {
        guard let settings = aiSettings, !settings.apiKey.isEmpty else { return false }
        return true
    }

    public init() {
        aiSettings = try? AISettingsStore.load()
    }

    // Without a model list every AI call falls back to no thinking, so it's fetched as soon as there's a key.
    @MainActor public func loadAIModelsIfNeeded(
        fetch: (String) async throws -> [AIModelInfo] = { try await AnthropicClient(apiKey: $0).listModels() },
        save: (AISettings) throws -> Void = { try AISettingsStore.save($0) }
    ) async {
        guard let settings = aiSettings, !settings.apiKey.isEmpty, settings.models.isEmpty,
              let models = try? await fetch(settings.apiKey),
              let current = aiSettings, current.apiKey == settings.apiKey, current.models.isEmpty else { return }
        let next = current.applyingFetchedModels(models).0
        aiSettings = next
        try? save(next)
    }

    // The open post is saved while the old site is still current, so its stash is keyed to that site.
    @MainActor public func connect(_ newCredentials: Credentials) async {
        if let current = credentials, current.siteKey != newCredentials.siteKey {
            await persistOpenPost?.run()
            selectedItem = nil
            posts = []
            pages = []
            mediaItems = []
            selectedMedia = nil
        }
        credentials = newCredentials
        canPostUnfilteredHTML = nil
    }

    @MainActor public func loadUnfilteredHTMLCapability() async {
        guard canPostUnfilteredHTML == nil, let creds = credentials else { return }
        let allowed = try? await WordPressClient(credentials: creds).canPostUnfilteredHTML()
        guard credentials == creds else { return }
        canPostUnfilteredHTML = allowed
    }

    // Looked up by ID after the request, since the list can change while it runs.
    public func replaceMedia(_ updated: WPMedia, fromSite site: String) {
        guard credentials?.siteKey == site else { return }
        if let index = mediaItems.firstIndex(where: { $0.id == updated.id }) { mediaItems[index] = updated }
        if selectedMedia?.id == updated.id { selectedMedia = updated }
    }

    public func createNewDraft(type: String, draftStore: DraftStore) {
        guard let id = try? draftStore.create(title: "Untitled", content: "", excerpt: "", type: type) else { return }
        guard let updated = try? draftStore.fetchAll(),
              let newDraft = updated.first(where: { $0.id == id }) else { return }
        localDrafts = updated
        selectedSection = .localDrafts
        selectedItem = .local(newDraft)
    }

    public var sectionIsEmpty: Bool {
        switch selectedSection {
        case .posts: return posts.isEmpty
        case .pages: return pages.isEmpty
        case .localDrafts: return localDrafts.isEmpty
        case .media: return mediaItems.isEmpty
        }
    }

    // Local Drafts load from SQLite, so a failed network load says nothing about them.
    public var sectionListError: LoadFailure? {
        selectedSection == .localDrafts ? nil : listError
    }

    private var sectionPosts: [WPPost] {
        switch selectedSection {
        case .posts: return posts
        case .pages: return pages
        case .localDrafts, .media: return []
        }
    }

    public var availableStatusFilters: [PostStatusFilter] {
        PostStatusFilter.allCases.filter { filter in
            switch filter {
            case .pending, .private: return statusCount(filter) > 0
            default: return true
            }
        }
    }

    // Reads back as All once no post has the stored status, without forgetting the choice.
    public var statusFilter: PostStatusFilter {
        get {
            let stored: PostStatusFilter
            switch selectedSection {
            case .posts: stored = postStatusFilter
            case .pages: stored = pageStatusFilter
            case .localDrafts, .media: return .all
            }
            return availableStatusFilters.contains(stored) ? stored : .all
        }
        set {
            switch selectedSection {
            case .posts: postStatusFilter = newValue
            case .pages: pageStatusFilter = newValue
            case .localDrafts, .media: break
            }
        }
    }

    public func statusCount(_ filter: PostStatusFilter) -> Int {
        sectionPosts.count(where: filter.matches)
    }

    public var filteredItems: [PostItem] {
        let items: [PostItem]
        switch selectedSection {
        case .posts, .pages:
            let filter = statusFilter
            var matching = sectionPosts.filter(filter.matches)
            if filter == .future { matching.sort { $0.publishSortKey < $1.publishSortKey } }
            items = matching.map { .remote($0) }
        case .localDrafts: items = localDrafts.map { .local($0) }
        case .media: return []
        }
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
}

public struct LoadFailure: Equatable {
    public let message: String
    public let needsSettings: Bool

    public init(_ error: Error) {
        message = error.localizedDescription
        needsSettings = (error as? APIError)?.isFixedInSettings ?? false
    }
}
