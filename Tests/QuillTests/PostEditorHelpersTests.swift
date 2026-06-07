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
}
