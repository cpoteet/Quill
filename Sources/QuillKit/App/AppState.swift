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

public enum PostItem: Identifiable, Hashable {
    case remote(WPPost)
    case local(LocalDraft)

    public var id: String {
        switch self {
        case .remote(let p): return "remote-\(p.id)"
        case .local(let d): return "local-\(d.id)"
        }
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
    @Published public var credentials: Credentials?

    @Published public var posts: [WPPost] = []
    @Published public var pages: [WPPost] = []
    @Published public var localDrafts: [LocalDraft] = []
    @Published public var categories: [WPCategory] = []
    @Published public var tags: [WPTag] = []

    @Published public var isLoadingList: Bool = true
    @Published public var hasLoadedList: Bool = false
    @Published public var listError: String?
    // Set only after a successful loadAllSections() — lets SidebarView skip
    // refetching everything when it remounts (sidebar hide/show) with unchanged credentials.
    @Published public var lastLoadedCredentials: Credentials?
    @Published public var hasCheckedForUpdate: Bool = false

    @Published public var mediaItems: [WPMedia] = []
    @Published public var selectedMedia: WPMedia?
    @Published public var isLoadingMedia: Bool = true
    @Published public var hasLoadedMedia: Bool = false
    @Published public var mediaError: String?

    @Published public var aiSettings: AISettings?
    @Published public var triggerMediaUpload: Bool = false
    @Published public var mediaFilter: MediaFilter = .all
    @Published public var mediaSearchText: String = ""
    @Published public var mediaRefreshToken: Int = 0
    @Published public var isMediaInspectorOpen: Bool = false
    @Published public var triggerShowMediaDetails: Bool = false
    @Published public var triggerFindBar: Bool = false
    @Published public var triggerPasteMarkdown: Bool = false
    @Published public var updateAvailable: UpdateInfo?

    public var aiEnabled: Bool {
        guard let settings = aiSettings, !settings.apiKey.isEmpty else { return false }
        return true
    }

    public init() {
        aiSettings = try? AISettingsStore.load()
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

    public var filteredItems: [PostItem] {
        let items: [PostItem]
        switch selectedSection {
        case .posts: items = posts.map { .remote($0) }
        case .pages: items = pages.map { .remote($0) }
        case .localDrafts: items = localDrafts.map { .local($0) }
        case .media: return []
        }
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
}
