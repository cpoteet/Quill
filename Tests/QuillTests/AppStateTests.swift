import AppKit
import Foundation
import Testing
@testable import QuillKit

// MARK: - Fixtures

private func makePost(id: Int = 1, title: String = "Post Title", status: String = "publish", type: String = "post",
                      date: String = "2024-01-01T00:00:00", dateGmt: String? = nil) throws -> WPPost {
    let gmtField = dateGmt.map { #""date_gmt":"\#($0)","# } ?? ""
    let json = """
    {"id":\(id),"type":"\(type)",
     "title":{"rendered":"\(title)"},"content":{"rendered":"<p>x</p>"},
     "excerpt":{"rendered":""},
     "status":"\(status)","date":"\(date)",\(gmtField)
     "modified":"2024-01-01T00:00:00","slug":"slug","link":"https://example.com"}
    """
    return try JSONDecoder().decode(WPPost.self, from: Data(json.utf8))
}

private func makeDraft(id: Int64 = 1, title: String = "Draft Title", type: String = "post") -> LocalDraft {
    LocalDraft(id: id, title: title, content: "", excerpt: "", type: type, footnotes: "",
               createdAt: Date(), updatedAt: Date())
}

// MARK: - PostItem

@Suite struct PostItemTests {

    @Test func remotePostIdFormatsAsRemoteDashId() throws {
        let post = try makePost(id: 5)
        #expect(PostItem.remote(post).id == "remote-5")
    }

    @Test func localDraftIdFormatsAsLocalDashId() {
        #expect(PostItem.local(makeDraft(id: 5)).id == "local-5")
    }

    @Test func remoteAndLocalWithSameNumericIdDoNotCollide() throws {
        let post = try makePost(id: 5)
        #expect(PostItem.remote(post).id != PostItem.local(makeDraft(id: 5)).id)
    }

    @Test func remotePostTitleUsesRenderedTitle() throws {
        #expect(try PostItem.remote(makePost(title: "My Post")).title == "My Post")
    }

    @Test func remotePostWithEmptyTitleReturnsUntitled() throws {
        #expect(try PostItem.remote(makePost(title: "")).title == "Untitled")
    }

    @Test func localDraftTitleUsesDraftTitle() {
        #expect(PostItem.local(makeDraft(title: "My Draft")).title == "My Draft")
    }

    @Test func localDraftWithEmptyTitleReturnsUntitled() {
        #expect(PostItem.local(makeDraft(title: "")).title == "Untitled")
    }

    @Test func remoteStatusBadgeIsPostStatus() throws {
        #expect(try PostItem.remote(makePost(status: "draft")).statusBadge == "draft")
    }

    @Test func localPostStatusBadgeIsLocalPost() {
        #expect(PostItem.local(makeDraft(type: "post")).statusBadge == "local-post")
    }

    @Test func localPageStatusBadgeIsLocalPage() {
        #expect(PostItem.local(makeDraft(type: "page")).statusBadge == "local-page")
    }

    // The File menu enables Revert and Preview off this flag alone.
    @Test func onlyARemoteItemReportsItselfAsRemote() throws {
        #expect(try PostItem.remote(makePost()).isRemote)
        #expect(PostItem.local(makeDraft()).isRemote == false)
    }
}

// MARK: - SidebarSection

@Suite struct SidebarSectionTests {

    @Test func postsIcon() { #expect(SidebarSection.posts.icon == "doc.text") }
    @Test func pagesIcon() { #expect(SidebarSection.pages.icon == "doc.plaintext") }
    @Test func localDraftsIcon() { #expect(SidebarSection.localDrafts.icon == "pencil") }
    @Test func mediaIcon() { #expect(SidebarSection.media.icon == "photo") }

    @Test func postsShortTitle() { #expect(SidebarSection.posts.shortTitle == "Posts") }
    @Test func pagesShortTitle() { #expect(SidebarSection.pages.shortTitle == "Pages") }
    @Test func localDraftsShortTitle() { #expect(SidebarSection.localDrafts.shortTitle == "Drafts") }
    @Test func mediaShortTitle() { #expect(SidebarSection.media.shortTitle == "Media") }
}

// MARK: - AppState.filteredItems

@Suite struct AppStateLoadingTests {

    @Test func initialListStateWaitsForFirstLoad() {
        let state = AppState()
        #expect(state.isLoadingList)
        #expect(!state.hasLoadedList)
    }

    @Test func initialMediaStateWaitsForFirstLoad() {
        let state = AppState()
        #expect(state.isLoadingMedia)
        #expect(!state.hasLoadedMedia)
    }
}

// A menu command whose trigger only the editor resets must be disabled while no editor is mounted.
@Suite struct AppStateEditorMountedTests {

    @Test func noEditorWithoutASelection() {
        let state = AppState()
        #expect(!state.editorIsMounted)
    }

    @Test func editorWithASelectedDraft() {
        let state = AppState()
        state.selectedItem = .local(makeDraft())
        #expect(state.editorIsMounted)
    }

    @Test func noEditorInMediaEvenWithASelection() {
        let state = AppState()
        state.selectedItem = .local(makeDraft())
        state.selectedSection = .media
        #expect(!state.editorIsMounted)
    }
}

@Suite struct AppStateFilteredItemsTests {

    @Test func postsSectionMapsRemotePosts() throws {
        let state = AppState()
        state.posts = [try makePost(id: 1)]
        state.selectedSection = .posts
        let items = state.filteredItems
        #expect(items.count == 1)
        #expect(items[0].id == "remote-1")
    }

    @Test func pagesSectionMapsRemotePages() throws {
        let state = AppState()
        state.pages = [try makePost(id: 2, type: "page")]
        state.selectedSection = .pages
        let items = state.filteredItems
        #expect(items.count == 1)
        #expect(items[0].id == "remote-2")
    }

    @Test func localDraftsSectionMapsLocalDrafts() {
        let state = AppState()
        state.localDrafts = [makeDraft(id: 3)]
        state.selectedSection = .localDrafts
        let items = state.filteredItems
        #expect(items.count == 1)
        #expect(items[0].id == "local-3")
    }

    @Test func mediaSectionReturnsEmpty() {
        let state = AppState()
        state.selectedSection = .media
        #expect(state.filteredItems.isEmpty)
    }

    @Test func emptySearchReturnsAllItems() throws {
        let state = AppState()
        state.posts = [try makePost(id: 1, title: "A"), try makePost(id: 2, title: "B")]
        state.selectedSection = .posts
        state.searchText = ""
        #expect(state.filteredItems.count == 2)
    }

    @Test func searchFiltersCaseInsensitively() throws {
        let state = AppState()
        state.posts = [try makePost(id: 1, title: "Hello World"), try makePost(id: 2, title: "Goodbye")]
        state.selectedSection = .posts
        state.searchText = "hello"
        let items = state.filteredItems
        #expect(items.count == 1)
        #expect(items[0].id == "remote-1")
    }

    @Test func searchReturnsEmptyForNoMatch() throws {
        let state = AppState()
        state.posts = [try makePost(id: 1, title: "Hello")]
        state.selectedSection = .posts
        state.searchText = "zzz"
        #expect(state.filteredItems.isEmpty)
    }

    @Test func partialTitleMatchReturnsItem() throws {
        let state = AppState()
        state.posts = [try makePost(id: 1, title: "Hello World")]
        state.selectedSection = .posts
        state.searchText = "World"
        #expect(state.filteredItems.count == 1)
    }

    // Whitespace-only is non-empty so filtering applies, but no normal title
    // contains 3 consecutive spaces — result is empty.
    @Test func whitespaceOnlySearchFiltersOutAllNormalTitles() throws {
        let state = AppState()
        state.posts = [try makePost(id: 1, title: "Hello"), try makePost(id: 2, title: "World")]
        state.selectedSection = .posts
        state.searchText = "   "
        #expect(state.filteredItems.isEmpty)
    }

    @Test func searchOnlyAppliesToActiveSection() throws {
        let state = AppState()
        state.posts = [try makePost(id: 1, title: "Alpha")]
        state.pages = [try makePost(id: 2, title: "Beta", type: "page")]
        state.selectedSection = .posts
        state.searchText = "Alpha"
        // Only posts are searched; pages section is not active
        #expect(state.filteredItems.count == 1)
        #expect(state.filteredItems[0].id == "remote-1")
    }

    @MainActor @Test func newDraftClearsTheSearchSoItIsListed() async throws {
        let state = AppState()
        state.posts = [try makePost(id: 1, title: "QA post")]
        state.searchText = "QA"
        state.createNewDraft(type: "post", draftStore: DraftStore(db: try AppDatabase.inMemory()))
        for _ in 0..<100 where state.selectedItem == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(state.selectedSection == .localDrafts)
        #expect(state.filteredItems.map(\.id) == [state.selectedItem?.id])
    }

    @MainActor @Test func switchingSectionClosesTheInspectorNowAndSwitchesAfterwards() async throws {
        final class Seen { var section: SidebarSection? }
        let state = AppState()
        state.selectedSection = .media
        state.isMediaInspectorOpen = true
        let token = state.inspectorCloseToken
        let seen = Seen()
        state.switchSection(to: .posts) { seen.section = state.selectedSection }
        #expect(state.isMediaInspectorOpen == false)
        #expect(state.inspectorCloseToken == token + 1)
        #expect(state.selectedSection == .media)
        for _ in 0..<100 where seen.section == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(state.selectedSection == .posts)
        #expect(seen.section == .posts)
    }

    @MainActor @Test func switchingSectionWithoutAFollowUpStillSwitches() async throws {
        let state = AppState()
        state.switchSection(to: .pages)
        for _ in 0..<100 where state.selectedSection != .pages { try await Task.sleep(for: .milliseconds(10)) }
        #expect(state.selectedSection == .pages)
    }

    @MainActor @Test func switchingToTheCurrentSectionRunsTheFollowUpAndLeavesTheInspectorOpen() {
        let state = AppState()
        state.selectedSection = .media
        state.isMediaInspectorOpen = true
        let token = state.inspectorCloseToken
        var ran = false
        state.switchSection(to: .media) { ran = true }
        #expect(ran)
        #expect(state.isMediaInspectorOpen)
        #expect(state.inspectorCloseToken == token)
    }

    @MainActor @Test func newDraftStartsWithAnEmptyTitle() async throws {
        let state = AppState()
        let store = DraftStore(db: try AppDatabase.inMemory())
        state.createNewDraft(type: "post", draftStore: store)
        #expect(try store.fetchAll().map(\.title) == [""])
    }
}

// MARK: - AppState status filter

@Suite struct AppStateStatusFilterTests {

    private func postsState() throws -> AppState {
        let state = AppState()
        state.posts = [
            try makePost(id: 1, title: "Alpha", status: "publish"),
            try makePost(id: 2, title: "Beta", status: "draft"),
            try makePost(id: 3, title: "Alpha draft", status: "draft"),
            try makePost(id: 4, title: "Gamma", status: "future"),
        ]
        state.selectedSection = .posts
        return state
    }

    @Test func filterDefaultsToAll() throws {
        let state = try postsState()
        #expect(state.statusFilter == .all)
        #expect(state.filteredItems.count == 4)
    }

    @Test func draftFilterShowsOnlyDrafts() throws {
        let state = try postsState()
        state.statusFilter = .draft
        #expect(state.filteredItems.map(\.id) == ["remote-2", "remote-3"])
    }

    @Test func filterCombinesWithSearch() throws {
        let state = try postsState()
        state.statusFilter = .draft
        state.searchText = "alpha"
        #expect(state.filteredItems.map(\.id) == ["remote-3"])
    }

    @Test func postsAndPagesKeepSeparateFilters() throws {
        let state = try postsState()
        state.pages = [try makePost(id: 9, status: "draft", type: "page")]
        state.statusFilter = .draft
        state.selectedSection = .pages
        #expect(state.statusFilter == .all)
        state.selectedSection = .posts
        #expect(state.statusFilter == .draft)
    }

    @Test func localDraftsAndMediaIgnoreTheFilter() throws {
        let state = AppState()
        state.localDrafts = [makeDraft(id: 1)]
        state.selectedSection = .localDrafts
        state.statusFilter = .draft
        #expect(state.statusFilter == .all)
        #expect(state.filteredItems.count == 1)
    }

    @Test func pendingAndPrivateAreOfferedOnlyWhenPresent() throws {
        let state = try postsState()
        #expect(state.availableStatusFilters == [.all, .publish, .draft, .future])
        state.posts.append(try makePost(id: 5, status: "private"))
        #expect(state.availableStatusFilters == [.all, .publish, .draft, .future, .private])
    }

    @Test func filterFallsBackToAllWhenItsStatusIsGone() throws {
        let state = try postsState()
        state.posts.append(try makePost(id: 5, status: "pending"))
        state.statusFilter = .pending
        #expect(state.filteredItems.map(\.id) == ["remote-5"])
        state.posts.removeLast()
        #expect(state.statusFilter == .all)
        #expect(state.filteredItems.count == 4)
        state.posts.append(try makePost(id: 6, status: "pending"))
        #expect(state.statusFilter == .pending)
        #expect(state.filteredItems.map(\.id) == ["remote-6"])
    }

    @Test func publishedDraftAndScheduledAreOfferedEvenWhenEmpty() {
        let state = AppState()
        state.selectedSection = .posts
        #expect(state.availableStatusFilters == [.all, .publish, .draft, .future])
    }

    @Test func pagesFilterTheirOwnList() throws {
        let state = try postsState()
        state.pages = [
            try makePost(id: 7, status: "publish", type: "page"),
            try makePost(id: 8, status: "draft", type: "page"),
        ]
        state.selectedSection = .pages
        state.statusFilter = .draft
        #expect(state.filteredItems.map(\.id) == ["remote-8"])
        #expect(state.statusCount(.all) == 2)
    }

    @Test func mediaIgnoresTheFilter() {
        let state = AppState()
        state.selectedSection = .media
        state.statusFilter = .draft
        #expect(state.statusFilter == .all)
        #expect(state.statusCount(.all) == 0)
    }

    @Test func listErrorIsHiddenOnlyForLocalDrafts() {
        let state = AppState()
        state.listError = LoadFailure(APIError.httpError(statusCode: 401, body: ""))
        for section in [SidebarSection.posts, .pages, .media] {
            state.selectedSection = section
            #expect(state.sectionListError == state.listError)
        }
        state.selectedSection = .localDrafts
        #expect(state.sectionListError == nil)
    }

    @Test func countsCoverTheWholeSectionAndIgnoreSearch() throws {
        let state = try postsState()
        state.searchText = "zzz"
        #expect(state.statusCount(.all) == 4)
        #expect(state.statusCount(.draft) == 2)
        #expect(state.statusCount(.future) == 1)
        #expect(state.statusCount(.pending) == 0)
    }

    @Test func scheduledListsSoonestFirst() throws {
        let state = AppState()
        state.posts = [
            try makePost(id: 1, status: "future", date: "2026-12-01T09:00:00"),
            try makePost(id: 2, status: "future", date: "2026-10-10T09:00:00"),
            try makePost(id: 3, status: "future", date: "2026-11-01T09:00:00"),
        ]
        state.selectedSection = .posts
        state.statusFilter = .future
        #expect(state.filteredItems.map(\.id) == ["remote-2", "remote-3", "remote-1"])
    }

    // When clocks go back, local times can run backwards while UTC runs forwards.
    @Test func scheduledSortsByUTCWhenLocalTimesOverlap() throws {
        let state = AppState()
        state.posts = [
            try makePost(id: 1, status: "future", date: "2026-11-01T01:15:00", dateGmt: "2026-11-01T06:15:00"),
            try makePost(id: 2, status: "future", date: "2026-11-01T01:45:00", dateGmt: "2026-11-01T05:45:00"),
        ]
        state.selectedSection = .posts
        state.statusFilter = .future
        #expect(state.filteredItems.map(\.id) == ["remote-2", "remote-1"])
    }

    @Test func otherFiltersKeepServerOrder() throws {
        let state = AppState()
        state.posts = [
            try makePost(id: 1, status: "draft", date: "2026-01-01T00:00:00"),
            try makePost(id: 2, status: "draft", date: "2026-02-01T00:00:00"),
        ]
        state.selectedSection = .posts
        state.statusFilter = .draft
        #expect(state.filteredItems.map(\.id) == ["remote-1", "remote-2"])
    }

    @Test func titlesMatchTheRowStatusWords() {
        #expect(PostStatusFilter.all.title(in: .posts) == "All Posts")
        #expect(PostStatusFilter.all.title(in: .pages) == "All Pages")
        #expect(PostStatusFilter.publish.title(in: .posts) == "Published")
        #expect(PostStatusFilter.draft.title(in: .posts) == "Draft")
        #expect(PostStatusFilter.future.title(in: .posts) == "Scheduled")
        #expect(PostStatusFilter.pending.title(in: .pages) == "Pending")
        #expect(PostStatusFilter.private.title(in: .pages) == "Private")
    }
}

// MARK: - AppState.sectionIsEmpty

@Suite struct SectionIsEmptyTests {

    @Test func postsEmptyWhenNoPosts() {
        let state = AppState()
        state.selectedSection = .posts
        #expect(state.sectionIsEmpty)
    }

    @Test func postsNotEmptyWhenPostsExist() throws {
        let state = AppState()
        state.posts = [try makePost(id: 1)]
        state.selectedSection = .posts
        #expect(!state.sectionIsEmpty)
    }

    @Test func pagesEmptyWhenNoPages() {
        let state = AppState()
        state.selectedSection = .pages
        #expect(state.sectionIsEmpty)
    }

    @Test func localDraftsEmptyWhenNoDrafts() {
        let state = AppState()
        state.selectedSection = .localDrafts
        #expect(state.sectionIsEmpty)
    }

    @Test func mediaEmptyWhenNoMedia() {
        let state = AppState()
        state.selectedSection = .media
        #expect(state.sectionIsEmpty)
    }
}

// MARK: - Taxonomy ordering

private func makeCategory(_ id: Int, _ name: String) -> WPCategory {
    WPCategory(id: id, name: name, slug: name.lowercased(), count: 0, parent: 0)
}

private func makeTag(_ id: Int, _ name: String) -> WPTag {
    WPTag(id: id, name: name, slug: name.lowercased(), count: 0)
}

@Suite struct TaxonomyOrderingTests {

    @Test func assigningCategoriesSortsThem() {
        let state = AppState()
        state.categories = [makeCategory(1, "Zebra"), makeCategory(2, "apple"), makeCategory(3, "Mango")]
        #expect(state.categories.map(\.name) == ["apple", "Mango", "Zebra"])
    }

    @Test func assigningTagsSortsThem() {
        let state = AppState()
        state.tags = [makeTag(1, "swift"), makeTag(2, "AppKit"), makeTag(3, "webkit")]
        #expect(state.tags.map(\.name) == ["AppKit", "swift", "webkit"])
    }

    @Test func appendingToCategoriesKeepsThemSorted() {
        let state = AppState()
        state.categories = [makeCategory(1, "Beta"), makeCategory(2, "Delta")]
        state.categories.append(makeCategory(3, "Alpha"))
        #expect(state.categories.map(\.name) == ["Alpha", "Beta", "Delta"])
    }

    @Test func sortedByNameIgnoresCase() {
        let sorted = [makeTag(1, "banana"), makeTag(2, "Apple"), makeTag(3, "cherry")].sortedByName()
        #expect(sorted.map(\.name) == ["Apple", "banana", "cherry"])
    }

    @Test func sortedByNameUsesLocaleAwareComparison() {
        let sorted = [makeCategory(1, "Zurich"), makeCategory(2, "\u{00E4}pfel"), makeCategory(3, "Apple")].sortedByName()
        #expect(sorted.map(\.name).first != "Zurich")
        #expect(sorted.map(\.name).last == "Zurich")
    }
}

// MARK: - Switching sites

private func makeMedia(id: Int, alt: String = "") throws -> WPMedia {
    let json = """
    {"id":\(id),"title":{"rendered":"p\(id)"},"source_url":"https://example.com/p\(id).jpg",\
    "media_type":"image","mime_type":"image/jpeg","link":"https://example.com/p\(id)","alt_text":"\(alt)"}
    """
    return try JSONDecoder().decode(WPMedia.self, from: Data(json.utf8))
}

@MainActor @Suite struct SiteSwitchTests {
    private let siteA = Credentials(siteURL: URL(string: "https://a.test")!, username: "u", appPassword: "p")
    private let siteB = Credentials(siteURL: URL(string: "https://b.test")!, username: "u", appPassword: "p")

    @Test func anotherSiteFlushesTheOpenPostThenClearsTheOldSitesState() async throws {
        let state = AppState()
        state.credentials = siteA
        let open = PostItem.remote(try makePost(id: 7))
        state.selectedItem = open
        state.posts = [try makePost(id: 7)]
        state.pages = [try makePost(id: 8, type: "page")]
        state.mediaItems = [try makeMedia(id: 3)]
        state.selectedMedia = try makeMedia(id: 3)
        var seenWhenFlushed: (Credentials?, PostItem?)
        state.persistOpenPost = (UUID(), { seenWhenFlushed = (state.credentials, state.selectedItem) })

        await state.connect(siteB)

        #expect(seenWhenFlushed.0 == siteA)
        #expect(seenWhenFlushed.1 == open)
        #expect(state.credentials == siteB)
        #expect(state.selectedItem == nil)
        #expect(state.posts.isEmpty && state.pages.isEmpty)
        #expect(state.mediaItems.isEmpty && state.selectedMedia == nil)
    }

    @Test func theFirstSiteConnectsWithoutFlushingAnything() async throws {
        let state = AppState()
        let draft = PostItem.local(makeDraft(id: 4))
        state.selectedItem = draft
        var flushed = false
        state.persistOpenPost = (UUID(), { flushed = true })

        await state.connect(siteA)

        #expect(!flushed)
        #expect(state.selectedItem == draft)
        #expect(state.credentials == siteA)
    }

    @Test func theSameSiteWithNewCredentialsKeepsTheOpenPost() async throws {
        let state = AppState()
        state.credentials = siteA
        let item = PostItem.remote(try makePost(id: 7))
        state.selectedItem = item
        var flushed = false
        state.persistOpenPost = (UUID(), { flushed = true })
        let newPassword = Credentials(siteURL: URL(string: "https://a.test/")!, username: "u", appPassword: "new")

        await state.connect(newPassword)

        #expect(!flushed)
        #expect(state.selectedItem == item)
        #expect(state.credentials == newPassword)
    }

    @Test func connectingForgetsWhetherTheAccountCanPostUnfilteredHTML() async {
        let state = AppState()
        state.credentials = siteA
        state.canPostUnfilteredHTML = true
        let otherUser = Credentials(siteURL: URL(string: "https://a.test/")!, username: "author", appPassword: "p")

        await state.connect(otherUser)

        #expect(state.canPostUnfilteredHTML == nil)
    }
}

// MARK: - Site name

@MainActor @Suite struct SiteProfileRefreshTests {
    private let siteA = Credentials(siteURL: URL(string: "https://a.test")!, username: "u", appPassword: "p")
    private let siteB = Credentials(siteURL: URL(string: "https://b.test")!, username: "u", appPassword: "p")
    private let iconA = URL(string: "https://cdn.test/a.png")!
    private let iconB = URL(string: "https://cdn.test/b.png")!

    private func state(on site: Credentials) -> AppState {
        let state = AppState()
        state.credentials = site
        return state
    }

    @Test func refreshShowsStoredNameThenFetched() async throws {
        let store = try makeSiteProfileStore()
        try store.setProfile(SiteProfile(name: "Old"), for: siteA.siteKey)
        let state = state(on: siteA)
        var seenDuringFetch: String?
        await state.refreshSiteProfile(store: store, fetch: { _ in
            seenDuringFetch = state.siteName
            return SiteProfile(name: "New")
        }, loadIcon: { _ in nil })
        #expect(seenDuringFetch == "Old")
        #expect(state.siteName == "New")
        #expect(store.profile(for: siteA.siteKey)?.name == "New")
    }

    @Test func refreshDropsAResultForAnotherSite() async throws {
        let store = try makeSiteProfileStore()
        let state = state(on: siteA)
        await state.refreshSiteProfile(store: store, fetch: { _ in
            state.credentials = siteB
            return SiteProfile(name: "A's name", iconURL: iconA)
        }, loadIcon: { _ in tinyPNG() })
        #expect(state.siteName == nil)
        #expect(state.siteIcon == nil)
    }

    @Test func aFailedRefreshKeepsTheStoredProfile() async throws {
        let store = try makeSiteProfileStore()
        try store.setProfile(SiteProfile(name: "Old", iconURL: iconA, iconData: tinyPNG()), for: siteA.siteKey)
        let state = state(on: siteA)
        await state.refreshSiteProfile(store: store, fetch: { _ in throw URLError(.notConnectedToInternet) },
                                       loadIcon: { _ in nil })
        #expect(state.siteName == "Old")
        #expect(state.siteIcon != nil)
    }

    @Test func aSiteWhoseNameWasClearedFallsBack() async throws {
        let store = try makeSiteProfileStore()
        try store.setProfile(SiteProfile(name: "Old"), for: siteA.siteKey)
        let state = state(on: siteA)
        await state.refreshSiteProfile(store: store, fetch: { _ in SiteProfile() }, loadIcon: { _ in nil })
        #expect(state.siteName == nil)
        #expect(store.profile(for: siteA.siteKey)?.name == nil)
    }

    @Test func aNewIconIsDownloadedShownAndStored() async throws {
        let store = try makeSiteProfileStore()
        let state = state(on: siteA)
        var loaded: [URL] = []
        await state.refreshSiteProfile(store: store, fetch: { _ in SiteProfile(name: "A", iconURL: iconA) },
                                       loadIcon: { loaded.append($0); return tinyPNG() })
        #expect(loaded == [iconA])
        #expect(state.siteIcon != nil)
        #expect(store.profile(for: siteA.siteKey)?.iconData == tinyPNG())
    }

    @Test func anUnchangedIconIsNotDownloadedAgain() async throws {
        let store = try makeSiteProfileStore()
        try store.setProfile(SiteProfile(name: "A", iconURL: iconA, iconData: tinyPNG()), for: siteA.siteKey)
        let state = state(on: siteA)
        var loads = 0
        await state.refreshSiteProfile(store: store, fetch: { _ in SiteProfile(name: "A", iconURL: iconA) },
                                       loadIcon: { _ in loads += 1; return tinyPNG() })
        #expect(loads == 0)
        #expect(state.siteIcon != nil)
    }

    @Test func aSiteThatDropsItsIconClearsIt() async throws {
        let store = try makeSiteProfileStore()
        try store.setProfile(SiteProfile(name: "A", iconURL: iconA, iconData: tinyPNG()), for: siteA.siteKey)
        let state = state(on: siteA)
        await state.refreshSiteProfile(store: store, fetch: { _ in SiteProfile(name: "A") }, loadIcon: { _ in nil })
        #expect(state.siteIcon == nil)
        #expect(store.profile(for: siteA.siteKey)?.iconData == nil)
    }

    @Test func aFailedDownloadKeepsTheOldIconAndTriesAgainNextTime() async throws {
        let store = try makeSiteProfileStore()
        try store.setProfile(SiteProfile(name: "A", iconURL: iconA, iconData: tinyPNG()), for: siteA.siteKey)
        let state = state(on: siteA)
        await state.refreshSiteProfile(store: store, fetch: { _ in SiteProfile(name: "A", iconURL: iconB) },
                                       loadIcon: { _ in nil })
        #expect(state.siteIcon != nil)
        var loaded: [URL] = []
        await state.refreshSiteProfile(store: store, fetch: { _ in SiteProfile(name: "A", iconURL: iconB) },
                                       loadIcon: { loaded.append($0); return tinyPNG() })
        #expect(loaded == [iconB])
        #expect(store.profile(for: siteA.siteKey)?.iconURL == iconB)
    }

    @Test func bytesThatAreNotAnImageCountAsAFailedDownload() async throws {
        let store = try makeSiteProfileStore()
        try store.setProfile(SiteProfile(name: "A", iconURL: iconA, iconData: tinyPNG()), for: siteA.siteKey)
        let state = state(on: siteA)
        await state.refreshSiteProfile(store: store, fetch: { _ in SiteProfile(name: "A", iconURL: iconB) },
                                       loadIcon: { _ in Data("<html>Not found</html>".utf8) })
        #expect(state.siteIcon != nil)
        #expect(store.profile(for: siteA.siteKey)?.iconURL == iconA)
        #expect(store.profile(for: siteA.siteKey)?.iconData == tinyPNG())
    }

    @Test func anotherAccountOnTheSameSiteForgetsTheUserID() async {
        let state = state(on: siteA)
        state.currentUserID = 3
        await state.connect(Credentials(siteURL: URL(string: "https://a.test/")!, username: "author", appPassword: "p"))
        #expect(state.currentUserID == nil)
    }

    @Test func connectingToAnotherSiteForgetsTheProfileAndUser() async {
        let state = state(on: siteA)
        state.siteName = "A"
        state.siteIcon = NSImage(data: tinyPNG())
        state.currentUserID = 3
        await state.connect(siteB)
        #expect(state.siteName == nil)
        #expect(state.siteIcon == nil)
        #expect(state.currentUserID == nil)
    }
}

// MARK: - Opening from the masthead

@MainActor @Suite struct OpenFromMastheadTests {
    private func waitForSelection(_ state: AppState) async throws {
        for _ in 0..<100 where state.selectedItem == nil { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func openingALocalDraftFromPostsSwitchesToDrafts() async throws {
        let state = AppState()
        let draft = makeDraft(id: 4)
        state.localDrafts = [draft]
        state.openFromMasthead(.local(draft), in: .localDrafts)
        try await waitForSelection(state)
        #expect(state.selectedSection == .localDrafts)
        #expect(state.selectedItem == .local(draft))
    }

    @Test func openingAStashedPageFromPostsSwitchesToPages() async throws {
        let state = AppState()
        let page = try makePost(id: 8, type: "page")
        state.pages = [page]
        state.openFromMasthead(.remote(page), in: .pages)
        try await waitForSelection(state)
        #expect(state.selectedSection == .pages)
        #expect(state.selectedItem == .remote(page))
    }

    @Test func openingClearsAFilterThatWouldHideTheItem() async throws {
        let state = AppState()
        let draft = try makePost(id: 1, status: "draft")
        state.posts = [draft, try makePost(id: 2, status: "publish")]
        state.statusFilter = .publish
        state.openFromMasthead(.remote(draft), in: .posts)
        #expect(state.statusFilter == .all)
        #expect(state.filteredItems.contains { $0.id == "remote-1" })
    }

    @Test func openingKeepsAFilterThatShowsTheItem() async throws {
        let state = AppState()
        let draft = try makePost(id: 1, status: "draft")
        state.posts = [draft, try makePost(id: 2, status: "publish")]
        state.statusFilter = .draft
        state.openFromMasthead(.remote(draft), in: .posts)
        #expect(state.statusFilter == .draft)
        #expect(state.selectedItem == .remote(draft))
    }

    @Test func openingClearsASearchThatWouldHideTheItem() async throws {
        let state = AppState()
        let draft = try makePost(id: 1, title: "Packing")
        state.posts = [draft]
        state.searchText = "Coast"
        state.openFromMasthead(.remote(draft), in: .posts)
        #expect(state.searchText == "")
    }

    @Test func openingKeepsASearchThatShowsTheItem() async throws {
        let state = AppState()
        let draft = try makePost(id: 1, title: "Packing")
        state.posts = [draft]
        state.searchText = "Pack"
        state.openFromMasthead(.remote(draft), in: .posts)
        #expect(state.searchText == "Pack")
    }
}

// MARK: - Missed schedules

@MainActor private final class Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { continuation != nil }
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func open() { continuation?.resume(); continuation = nil }
}

@MainActor @Suite struct MissedScheduleTests {
    private let siteA = Credentials(siteURL: URL(string: "https://a.test")!, username: "u", appPassword: "p")
    private let siteB = Credentials(siteURL: URL(string: "https://b.test")!, username: "u", appPassword: "p")
    private let now = PostSettings.parseWPDate("2026-10-31T12:00:00")!
    private let passed = "2026-10-31T11:00:00"

    private func state(with posts: [WPPost]) -> AppState {
        let state = AppState()
        state.credentials = siteA
        state.posts = posts
        return state
    }

    @Test func aStillFutureFetchConfirmsTheMiss() async throws {
        let post = try makePost(id: 1, status: "future", dateGmt: passed)
        let state = state(with: [post])
        await state.confirmMissedSchedules(now: now, fetch: { _, _ in post })
        #expect(state.confirmedMissed == [MissedKey(id: 1, dateGmt: passed)])
    }

    @Test func aPublishedFetchUpdatesTheListAndDoesNotConfirm() async throws {
        let state = state(with: [try makePost(id: 1, status: "future", dateGmt: passed)])
        let published = try makePost(id: 1, status: "publish", dateGmt: passed)
        await state.confirmMissedSchedules(now: now, fetch: { _, _ in published })
        #expect(state.confirmedMissed.isEmpty)
        #expect(state.posts[0].status == "publish")
    }

    @Test func aPublishedPageUpdatesThePagesList() async throws {
        let state = state(with: [])
        state.pages = [try makePost(id: 2, status: "future", type: "page", dateGmt: passed)]
        let published = try makePost(id: 2, status: "publish", type: "page", dateGmt: passed)
        await state.confirmMissedSchedules(now: now, fetch: { _, _ in published })
        #expect(state.pages[0].status == "publish")
    }

    @Test func aFailedFetchConfirmsNothing() async throws {
        let state = state(with: [try makePost(id: 1, status: "future", dateGmt: passed)])
        await state.confirmMissedSchedules(now: now, fetch: { _, _ in throw URLError(.notConnectedToInternet) })
        #expect(state.confirmedMissed.isEmpty)
        #expect(state.posts[0].status == "future")
    }

    @Test func eachPostIsFetchedOnce() async throws {
        let post = try makePost(id: 1, status: "future", dateGmt: passed)
        let state = state(with: [post])
        var fetches = 0
        await state.confirmMissedSchedules(now: now, fetch: { _, _ in fetches += 1; return post })
        await state.confirmMissedSchedules(now: now, fetch: { _, _ in fetches += 1; return post })
        #expect(fetches == 1)
    }

    @Test func aFailedFetchIsRetriedOnTheNextCall() async throws {
        let post = try makePost(id: 1, status: "future", dateGmt: passed)
        let state = state(with: [post])
        var fetches = 0
        await state.confirmMissedSchedules(now: now, fetch: { _, _ in fetches += 1; throw URLError(.timedOut) })
        await state.confirmMissedSchedules(now: now, fetch: { _, _ in fetches += 1; return post })
        #expect(fetches == 2)
        #expect(state.confirmedMissed == [MissedKey(id: 1, dateGmt: passed)])
    }

    @Test func aRescheduledPostIsCheckedAgain() async throws {
        let first = try makePost(id: 1, status: "future", dateGmt: passed)
        let state = state(with: [first])
        await state.confirmMissedSchedules(now: now, fetch: { _, _ in first })
        let moved = try makePost(id: 1, status: "future", dateGmt: "2026-10-31T11:30:00")
        state.posts = [moved]
        var fetches = 0
        await state.confirmMissedSchedules(now: now, fetch: { _, _ in fetches += 1; return moved })
        #expect(fetches == 1)
        #expect(state.confirmedMissed.contains(MissedKey(id: 1, dateGmt: "2026-10-31T11:30:00")))
        let rows = Masthead.scheduled(for: .posts, posts: state.posts, pages: [], confirmedMissed: [MissedKey(id: 1, dateGmt: passed)], now: now)
        #expect(rows.isEmpty)
    }

    @Test func aPostCrossingTheGraceIsPickedUpOnALaterCall() async throws {
        let post = try makePost(id: 1, status: "future", dateGmt: "2026-10-31T11:57:00")
        let state = state(with: [post])
        var fetches = 0
        await state.confirmMissedSchedules(now: now, fetch: { _, _ in fetches += 1; return post })
        #expect(fetches == 0)
        await state.confirmMissedSchedules(now: now.addingTimeInterval(360), fetch: { _, _ in fetches += 1; return post })
        #expect(fetches == 1)
    }

    @Test func aResultAfterASiteSwitchIsDropped() async throws {
        let post = try makePost(id: 1, status: "future", dateGmt: passed)
        let state = state(with: [post])
        await state.confirmMissedSchedules(now: now, fetch: { _, _ in
            await state.connect(siteB)
            return try makePost(id: 1, status: "publish", dateGmt: passed)
        })
        #expect(state.confirmedMissed.isEmpty)
        #expect(state.posts.isEmpty)
    }

    @Test func aCheckFinishesWhenTheTaskThatStartedItIsReplaced() async throws {
        let post = try makePost(id: 1, status: "future", dateGmt: passed)
        let state = state(with: [post])
        let gate = Gate()
        let replaced = Task { @MainActor in
            await state.confirmMissedSchedules(now: now, fetch: { _, _ in
                await gate.wait()
                try Task.checkCancellation()
                return post
            })
        }
        while !gate.isWaiting { await Task.yield() }
        replaced.cancel()
        await state.confirmMissedSchedules(now: now, fetch: { _, _ in post })
        gate.open()
        await replaced.value
        #expect(state.confirmedMissed == [MissedKey(id: 1, dateGmt: passed)])
    }

    @Test func aLateResponseDoesNotOverwriteANewerListEntry() async throws {
        let state = state(with: [try makePost(id: 1, title: "Old", status: "future", dateGmt: passed)])
        let refreshed = try makePost(id: 1, title: "Renamed", status: "draft", dateGmt: passed)
        await state.confirmMissedSchedules(now: now, fetch: { _, _ in
            state.posts = [refreshed]
            return try makePost(id: 1, title: "Old", status: "publish", dateGmt: passed)
        })
        #expect(state.posts[0].title.rendered == "Renamed")
        #expect(state.posts[0].status == "draft")
    }

    @Test func connectingToAnotherSiteForgetsConfirmations() async throws {
        let post = try makePost(id: 1, status: "future", dateGmt: passed)
        let state = state(with: [post])
        await state.confirmMissedSchedules(now: now, fetch: { _, _ in post })
        await state.connect(siteB)
        #expect(state.confirmedMissed.isEmpty)
    }
}

// MARK: - Updating a media item after a save

@Suite struct MediaUpdateTests {
    private let site = Credentials(siteURL: URL(string: "https://a.test")!, username: "u", appPassword: "p")
    private func media(id: Int, alt: String = "") throws -> WPMedia { try makeMedia(id: id, alt: alt) }

    @Test func theItemIsFoundByIDWhereverItNowSits() throws {
        let state = AppState()
        state.credentials = site
        state.mediaItems = [try media(id: 1), try media(id: 2), try media(id: 3)]
        state.selectedMedia = try media(id: 2)
        state.mediaItems.remove(at: 0)

        state.updateMedia(id: 2, fromSite: site.siteKey) { $0.altText = "New" }

        #expect(state.mediaItems.map(\.id) == [2, 3])
        #expect(state.mediaItems[0].altText == "New")
        #expect(state.selectedMedia?.altText == "New")
    }

    @Test func anItemNoLongerListedIsNotAddedBack() throws {
        let state = AppState()
        state.credentials = site
        state.mediaItems = [try media(id: 1)]
        state.selectedMedia = try media(id: 1)

        state.updateMedia(id: 2, fromSite: site.siteKey) { $0.altText = "New" }

        #expect(state.mediaItems.map(\.id) == [1])
        #expect(state.selectedMedia?.id == 1)
    }

    @Test func aSaveThatReturnsAfterASiteSwitchLeavesTheNewSiteAlone() throws {
        let state = AppState()
        state.credentials = Credentials(siteURL: URL(string: "https://b.test")!, username: "u", appPassword: "p")
        state.mediaItems = [try media(id: 2, alt: "B's image")]
        state.selectedMedia = try media(id: 2, alt: "B's image")

        state.updateMedia(id: 2, fromSite: site.siteKey) { $0.altText = "A's alt" }

        #expect(state.mediaItems[0].altText == "B's image")
        #expect(state.selectedMedia?.altText == "B's image")
    }

    @Test func aLateTitleSaveKeepsANewerAltText() throws {
        let state = AppState()
        state.credentials = site
        state.mediaItems = [try media(id: 2, alt: "Old")]
        state.selectedMedia = try media(id: 2, alt: "Old")
        let titleResponse = try media(id: 2, alt: "Old")

        state.updateMedia(id: 2, fromSite: site.siteKey) { $0.altText = "New" }
        state.updateMedia(id: 2, fromSite: site.siteKey) { $0.title = RenderedString(raw: "Renamed") }

        #expect(titleResponse.altText == "Old")
        #expect(state.mediaItems[0].altText == "New")
        #expect(state.mediaItems[0].title.raw == "Renamed")
        #expect(state.selectedMedia?.altText == "New")
        #expect(state.selectedMedia?.title.raw == "Renamed")
    }
}


// MARK: - AI model list

@MainActor @Suite struct AIModelLoadingTests {

    @Test func fillsAnEmptyModelListAndSavesIt() async {
        let state = AppState()
        state.aiSettings = AISettings(apiKey: "k")
        var saved: AISettings?
        await state.loadAIModelsIfNeeded(fetch: { _ in [haiku55, sonnet55] }, save: { saved = $0 })
        #expect(state.aiSettings?.models == [haiku55, sonnet55])
        #expect(saved?.models == [haiku55, sonnet55])
    }

    @Test func aFetchDropsAPinnedModelThatIsGoneAndFitsTheReasoningToTheNewDefault() async {
        let state = AppState()
        var settings = AISettings(apiKey: "k")
        settings.model = "claude-opus-3"
        settings.reasoning = .level("xhigh")
        state.aiSettings = settings
        var saved: AISettings?
        await state.loadAIModelsIfNeeded(fetch: { _ in [haiku45] }, save: { saved = $0 })
        #expect(state.aiSettings?.model == nil)
        #expect(state.aiSettings?.resolvedModelID() == "claude-haiku-4-5")
        #expect(state.aiSettings?.reasoning == .off)
        #expect(saved?.model == nil && saved?.reasoning == .off)
    }

    @Test func leavesAnExistingListAlone() async {
        let state = AppState()
        var settings = AISettings(apiKey: "k")
        settings.models = [haiku45]
        state.aiSettings = settings
        var fetched = false
        await state.loadAIModelsIfNeeded(fetch: { _ in fetched = true; return [haiku55] }, save: { _ in })
        #expect(!fetched)
        #expect(state.aiSettings?.models == [haiku45])
    }

    @Test func doesNothingWithoutAKey() async {
        let state = AppState()
        state.aiSettings = AISettings(apiKey: "")
        var fetched = false
        await state.loadAIModelsIfNeeded(fetch: { _ in fetched = true; return [haiku55] }, save: { _ in })
        #expect(!fetched)
    }

    @Test func dropsTheListWhenTheKeyChangedDuringTheFetch() async {
        let state = AppState()
        state.aiSettings = AISettings(apiKey: "old")
        var saved = false
        await state.loadAIModelsIfNeeded(fetch: { _ in
            state.aiSettings = AISettings(apiKey: "new")
            return [haiku55]
        }, save: { _ in saved = true })
        #expect(state.aiSettings?.models == [])
        #expect(!saved)
    }

    @Test func aFailedFetchChangesNothing() async {
        let state = AppState()
        state.aiSettings = AISettings(apiKey: "k")
        await state.loadAIModelsIfNeeded(fetch: { _ in throw URLError(.notConnectedToInternet) }, save: { _ in })
        #expect(state.aiSettings?.models == [])
    }
}
