import Foundation
import Testing
@testable import QuillKit

// MARK: - Fixtures

private func makePost(id: Int = 1, title: String = "Post Title", status: String = "publish", type: String = "post") throws -> WPPost {
    let json = """
    {"id":\(id),"type":"\(type)",
     "title":{"rendered":"\(title)"},"content":{"rendered":"<p>x</p>"},
     "excerpt":{"rendered":""},
     "status":"\(status)","date":"2024-01-01T00:00:00",
     "modified":"2024-01-01T00:00:00","slug":"slug","link":"https://example.com"}
    """
    return try JSONDecoder().decode(WPPost.self, from: Data(json.utf8))
}

private func makeDraft(id: Int64 = 1, title: String = "Draft Title", type: String = "post") -> LocalDraft {
    LocalDraft(id: id, title: title, content: "", excerpt: "", type: type,
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
