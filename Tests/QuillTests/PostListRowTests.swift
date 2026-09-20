import Foundation
import Testing
@testable import QuillKit

private func makeRemote(status: String, type: String = "post") throws -> PostItem {
    let json = """
    {"id":1,"type":"\(type)",
     "title":{"rendered":"T"},"content":{"rendered":""},"excerpt":{"rendered":""},
     "status":"\(status)","date":"2026-03-04T09:00:00",
     "modified":"2026-03-04T09:00:00","slug":"s","link":"https://example.com"}
    """
    return .remote(try JSONDecoder().decode(WPPost.self, from: Data(json.utf8)))
}

private func makeLocal(type: String) -> PostItem {
    .local(LocalDraft(id: 1, title: "T", content: "", excerpt: "", type: type,
                      footnotes: "", createdAt: Date(), updatedAt: Date()))
}

@Suite struct PostListRowSubtitleTests {

    @Test func remotePostsPairTheDateWithTheStatus() throws {
        #expect(try PostListRow.subtitle(for: makeRemote(status: "publish"), dateText: "Mar 4, 2026") == "Mar 4, 2026 \u{00B7} Published")
        #expect(try PostListRow.subtitle(for: makeRemote(status: "draft"), dateText: "Mar 4, 2026") == "Mar 4, 2026 \u{00B7} Draft")
        #expect(try PostListRow.subtitle(for: makeRemote(status: "future"), dateText: "Mar 4, 2026") == "Mar 4, 2026 \u{00B7} Scheduled")
    }

    @Test func pagesShowTheStatusWithoutADate() throws {
        #expect(try PostListRow.subtitle(for: makeRemote(status: "publish", type: "page"), dateText: "Mar 4, 2026") == "Published")
        #expect(try PostListRow.subtitle(for: makeRemote(status: "pending", type: "page"), dateText: "Mar 4, 2026") == "Pending")
    }

    @Test func localDraftsNameTheirType() {
        #expect(PostListRow.subtitle(for: makeLocal(type: "post"), dateText: "") == "Post Draft")
        #expect(PostListRow.subtitle(for: makeLocal(type: "page"), dateText: "") == "Page Draft")
    }

    @Test func anUnknownStatusIsCapitalisedRatherThanDropped() throws {
        #expect(PostListRow.statusLabel("archived") == "Archived")
        #expect(try PostListRow.subtitle(for: makeRemote(status: "archived"), dateText: "Mar 4, 2026") == "Mar 4, 2026 \u{00B7} Archived")
    }

    @Test func theTwoStatusesWordPressNamesDifferentlyAreTranslated() {
        #expect(PostListRow.statusLabel("publish") == "Published")
        #expect(PostListRow.statusLabel("future") == "Scheduled")
    }

    @Test func anUnparseableDateFallsBackToItsFirstTenCharacters() {
        #expect(PostListRow.formattedDate("not-a-date-at-all") == "not-a-date")
    }

    @Test func anISODateIsFormattedRatherThanTruncated() {
        let out = PostListRow.formattedDate("2026-03-04T09:00:00")
        #expect(out != "2026-03-04")
        #expect(out.contains("2026"))
    }
}
