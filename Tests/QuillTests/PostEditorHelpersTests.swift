import Foundation
import Testing
@testable import QuillKit

@Suite struct PostEditorHelpersTests {

    // MARK: - previewURL (Issue 2)

    @Test func previewURLAppendsFreshQueryToCleanURL() {
        let url = PostEditorView.previewURL(from: "https://example.com/my-post/")
        #expect(url?.query == "preview=true")
    }

    @Test func previewURLAppendsPreviewAlongsideExistingQuery() {
        let url = PostEditorView.previewURL(from: "https://example.com/?p=123")
        #expect(url?.query?.contains("p=123") == true)
        #expect(url?.query?.contains("preview=true") == true)
        #expect(url?.absoluteString.contains("?p=123?") == false)
    }

    @Test func previewURLReplacesExistingPreviewFalseParam() {
        let url = PostEditorView.previewURL(from: "https://example.com/post/?preview=false")
        #expect(url?.query == "preview=true")
    }

    @Test func previewURLPreservesMultipleExistingParams() {
        let url = PostEditorView.previewURL(from: "https://example.com/?p=123&foo=bar")
        #expect(url?.query?.contains("foo=bar") == true)
        #expect(url?.query?.contains("preview=true") == true)
    }

    @Test func previewURLPreservesFragment() {
        let url = PostEditorView.previewURL(from: "https://example.com/my-post/#section")
        #expect(url?.fragment == "section")
        #expect(url?.query == "preview=true")
    }

    // MARK: - Status helpers

    @Test func publishButtonTitlePerStatus() {
        #expect(PostEditorView.publishButtonTitle(status: "draft", isPublishedRemote: false) == "Publish Draft")
        #expect(PostEditorView.publishButtonTitle(status: "future", isPublishedRemote: false) == "Schedule")
        #expect(PostEditorView.publishButtonTitle(status: "pending", isPublishedRemote: false) == "Submit for Review")
        #expect(PostEditorView.publishButtonTitle(status: "private", isPublishedRemote: false) == "Publish Privately")
        #expect(PostEditorView.publishButtonTitle(status: "publish", isPublishedRemote: false) == "Publish")
        #expect(PostEditorView.publishButtonTitle(status: "publish", isPublishedRemote: true) == "Update")
        #expect(PostEditorView.publishButtonTitle(status: "trash", isPublishedRemote: false) == "Publish")
    }

    @Test func toastMessagePerStatus() {
        #expect(PostEditorView.toastMessage(forStatus: "publish") == "Published")
        #expect(PostEditorView.toastMessage(forStatus: "future") == "Scheduled")
        #expect(PostEditorView.toastMessage(forStatus: "pending") == "Submitted for review")
        #expect(PostEditorView.toastMessage(forStatus: "private") == "Published privately")
        #expect(PostEditorView.toastMessage(forStatus: "draft") == "Draft saved")
    }

    @Test func statusChangeToFutureSetsDefaultDate() {
        var s = PostSettings()
        s.status = "future"
        s.statusDidChange()
        #expect(s.publishDate != nil)
    }

    @Test func statusChangeToPrivateClearsScheduledDate() {
        var s = PostSettings()
        s.status = "future"
        s.statusDidChange()
        s.status = "private"
        s.statusDidChange()
        #expect(s.publishDate == nil)
    }

    @Test func statusChangeToFuturePreservesExistingDate() {
        var s = PostSettings()
        let existing = Date().addingTimeInterval(7200)
        s.status = "future"
        s.publishDate = existing
        s.statusDidChange()
        #expect(s.publishDate == existing)
    }

    @Test func statusChangeToPendingClearsScheduledDate() {
        var s = PostSettings()
        s.status = "future"
        s.statusDidChange()
        s.status = "pending"
        s.statusDidChange()
        #expect(s.publishDate == nil)
    }

    // MARK: - PostStats reading time

    @Test func readingTimeZeroWordsIsZero() {
        #expect(PostStats(words: 0, characters: 0).readingMinutes == 0)
    }

    @Test func readingTimeShortTextIsOneMinute() {
        #expect(PostStats(words: 1, characters: 5).readingMinutes == 1)
        #expect(PostStats(words: 238, characters: 1000).readingMinutes == 1)
    }

    @Test func readingTimeRoundsUp() {
        #expect(PostStats(words: 239, characters: 1000).readingMinutes == 2)
        #expect(PostStats(words: 1000, characters: 5000).readingMinutes == 5)  // 1000/238 = 4.2 → 5
    }
}
