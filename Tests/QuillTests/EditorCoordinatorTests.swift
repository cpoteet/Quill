import Foundation
import Testing
@testable import QuillKit

@Suite struct EditorCoordinatorTests {

    // MARK: - isAllowedExternalURL (S2)

    @Test func httpURLIsAllowed() {
        let url = URL(string: "http://example.com/post")!
        #expect(EditorCoordinator.isAllowedExternalURL(url))
    }

    @Test func httpsURLIsAllowed() {
        let url = URL(string: "https://example.com/post")!
        #expect(EditorCoordinator.isAllowedExternalURL(url))
    }

    @Test func mailtoURLIsAllowed() {
        let url = URL(string: "mailto:user@example.com")!
        #expect(EditorCoordinator.isAllowedExternalURL(url))
    }

    @Test func fileURLIsNotAllowed() {
        let url = URL(string: "file:///etc/passwd")!
        #expect(!EditorCoordinator.isAllowedExternalURL(url))
    }

    @Test func javascriptURLIsNotAllowed() {
        let url = URL(string: "javascript:alert(1)")!
        #expect(!EditorCoordinator.isAllowedExternalURL(url))
    }

    @Test func ftpURLIsNotAllowed() {
        let url = URL(string: "ftp://example.com/file")!
        #expect(!EditorCoordinator.isAllowedExternalURL(url))
    }

    @Test func schemeCheckIsCaseInsensitive() {
        let url = URL(string: "HTTPS://example.com/post")!
        #expect(EditorCoordinator.isAllowedExternalURL(url))
    }

    // MARK: - mediaSizesDict(for:)

    private func decodeMedia(_ json: String) throws -> WPMedia {
        try JSONDecoder().decode(WPMedia.self, from: json.data(using: .utf8)!)
    }

    @Test func mediaSizesDictAddsFullFallbackWhenSizesOmitsIt() throws {
        // WordPress commonly omits "full" from media_details.sizes even though it lists others.
        let json = """
        {"id":1,"source_url":"https://example.com/full.jpg",
         "media_details":{"width":2000,"height":1000,
           "sizes":{"medium":{"source_url":"https://example.com/medium.jpg","width":300,"height":150}}}}
        """
        let media = try decodeMedia(json)
        let dict = try #require(EditorCoordinator.mediaSizesDict(for: media))
        let full = try #require(dict["full"])
        #expect(full["url"] as? String == "https://example.com/full.jpg")
        #expect(full["width"] as? Int == 2000)
        #expect(full["height"] as? Int == 1000)
        // The pre-existing "medium" entry is left untouched.
        let medium = try #require(dict["medium"])
        #expect(medium["url"] as? String == "https://example.com/medium.jpg")
    }

    @Test func mediaSizesDictPreservesExistingFullEntry() throws {
        let json = """
        {"id":1,"source_url":"https://example.com/full.jpg",
         "media_details":{"sizes":{"full":{"source_url":"https://example.com/actual-full.jpg","width":4000,"height":2000}}}}
        """
        let media = try decodeMedia(json)
        let dict = try #require(EditorCoordinator.mediaSizesDict(for: media))
        // Does not overwrite a "full" entry the server already provided.
        #expect(dict["full"]?["url"] as? String == "https://example.com/actual-full.jpg")
    }

    @Test func mediaSizesDictFallsBackToSourceURLWhenNoSizesAtAll() throws {
        let json = """
        {"id":1,"source_url":"https://example.com/only.jpg"}
        """
        let media = try decodeMedia(json)
        let dict = try #require(EditorCoordinator.mediaSizesDict(for: media))
        #expect(dict.count == 1)
        #expect(dict["full"]?["url"] as? String == "https://example.com/only.jpg")
    }

    @Test func mediaSizesDictReturnsNilWhenSourceURLIsEmpty() throws {
        let json = """
        {"id":1}
        """
        let media = try decodeMedia(json)
        #expect(EditorCoordinator.mediaSizesDict(for: media) == nil)
    }
}

@Suite("setContent push decision")
struct EditorPushDecisionTests {
    @Test("identical content and footnotes is skipped")
    func skipsIdentical() {
        var state = EditorPushState()
        #expect(state.shouldPush(html: "<p>A</p>", footnotes: "[]"))
        state.record(html: "<p>A</p>", footnotes: "[]")
        #expect(!state.shouldPush(html: "<p>A</p>", footnotes: "[]"))
    }

    @Test("a footnote-only difference still pushes")
    func pushesOnFootnoteChange() {
        var state = EditorPushState()
        state.record(html: "<p>A</p>", footnotes: "[]")
        #expect(state.shouldPush(html: "<p>A</p>", footnotes: #"[{"content":"note"}]"#))
    }

    @Test("nil and empty footnotes are the same absence")
    func nilMatchesEmpty() {
        var state = EditorPushState()
        state.record(html: "<p>A</p>", footnotes: nil)
        #expect(!state.shouldPush(html: "<p>A</p>", footnotes: ""))
    }

    @Test("a content difference pushes whatever the footnotes say")
    func pushesOnContentChange() {
        var state = EditorPushState()
        state.record(html: "<p>A</p>", footnotes: "[]")
        #expect(state.shouldPush(html: "<p>B</p>", footnotes: "[]"))
    }

    // contentChanged only knows the HTML. If it reset the footnotes half, the very
    // next updateNSView would re-push identical content and wipe the user's caret.
    @Test("recording the HTML alone leaves the recorded footnotes intact")
    func recordHTMLKeepsFootnotes() {
        var state = EditorPushState()
        state.record(html: "<p>A</p>", footnotes: #"[{"id":"fn-a"}]"#)
        state.recordHTML("<p>A edited</p>")
        #expect(!state.shouldPush(html: "<p>A edited</p>", footnotes: #"[{"id":"fn-a"}]"#))
        #expect(state.shouldPush(html: "<p>A edited</p>", footnotes: "[]"))
    }

    // The mirror image: footnotesChanged only knows the notes.
    @Test("recording the footnotes alone leaves the recorded HTML intact")
    func recordFootnotesKeepsHTML() {
        var state = EditorPushState()
        state.record(html: "<p>A</p>", footnotes: "[]")
        state.recordFootnotes(#"[{"id":"fn-a"}]"#)
        #expect(!state.shouldPush(html: "<p>A</p>", footnotes: #"[{"id":"fn-a"}]"#))
        #expect(state.shouldPush(html: "<p>B</p>", footnotes: #"[{"id":"fn-a"}]"#))
    }

    // Two posts sharing a body and differing only in their notes: the whole reason
    // the dedupe key is a pair. Switching A → B → A must push all three times.
    @Test("switching between two posts with the same body still pushes each time")
    func pushesForEachPostSharingABody() {
        let body = "<p>Shared</p>"
        var state = EditorPushState()
        #expect(state.shouldPush(html: body, footnotes: #"[{"id":"a"}]"#))
        state.record(html: body, footnotes: #"[{"id":"a"}]"#)
        #expect(state.shouldPush(html: body, footnotes: #"[{"id":"b"}]"#))
        state.record(html: body, footnotes: #"[{"id":"b"}]"#)
        #expect(state.shouldPush(html: body, footnotes: #"[{"id":"a"}]"#))
    }

    // A fresh state matches an editor that has not loaded anything, so an empty
    // post is legitimately skipped — but only the first time.
    @Test("an empty post is skipped on a fresh state and pushed after any load")
    func emptyPostAfterARealOne() {
        var state = EditorPushState()
        #expect(!state.shouldPush(html: "", footnotes: ""))
        state.record(html: "<p>A</p>", footnotes: "[]")
        #expect(state.shouldPush(html: "", footnotes: ""))
    }

    // MARK: - Spell checking

    @MainActor @Test func misspelledWordsReturnsOnMainActorWithoutTrapping() async {
        let words = await withCheckedContinuation { continuation in
            EditorCoordinator.misspelledWords(in: "This sentance has a speling mistake.") {
                continuation.resume(returning: $0)
            }
        }
        #expect(words.contains("speling"))
        #expect(words.contains("sentance"))
    }
}
