import Foundation
import Testing
@testable import QuillKit

@Suite struct DraftStoreTests {
    var db: AppDatabase
    var store: DraftStore

    init() throws {
        db = try AppDatabase.inMemory()
        store = DraftStore(db: db)
    }

    @Test func createAndFetch() throws {
        let id = try store.create(title: "Test", content: "<p>Hello</p>", excerpt: "", type: "post")
        let drafts = try store.fetchAll()
        #expect(drafts.count == 1)
        #expect(drafts[0].id == id)
        #expect(drafts[0].title == "Test")
        #expect(drafts[0].type == "post")
    }

    @Test func createPageDraft() throws {
        let id = try store.create(title: "About", content: "", excerpt: "", type: "page")
        let drafts = try store.fetchAll()
        #expect(drafts[0].id == id)
        #expect(drafts[0].type == "page")
    }

    @Test func fetchAllPreservesType() throws {
        _ = try store.create(title: "Post Draft", content: "", excerpt: "", type: "post")
        _ = try store.create(title: "Page Draft", content: "", excerpt: "", type: "page")
        let drafts = try store.fetchAll()
        #expect(drafts.count == 2)
        let types = Set(drafts.map(\.type))
        #expect(types == ["post", "page"])
    }

    @Test func update() throws {
        let id = try store.create(title: "Original", content: "", excerpt: "", type: "post")
        try store.update(id: id, title: "Updated", content: "<p>New</p>", excerpt: "Excerpt")
        let drafts = try store.fetchAll()
        #expect(drafts[0].title == "Updated")
        #expect(drafts[0].content == "<p>New</p>")
    }

    @Test func delete() throws {
        let id = try store.create(title: "ToDelete", content: "", excerpt: "", type: "post")
        try store.delete(id: id)
        let drafts = try store.fetchAll()
        #expect(drafts.isEmpty)
    }

    @Test func loadByIdReturnsNilForUnknownId() throws {
        let draft = try store.load(id: 999)
        #expect(draft == nil)
    }

    @Test func loadByIdReturnsCorrectDraft() throws {
        let id = try store.create(title: "Hello", content: "<p>World</p>", excerpt: "Ex", type: "post")
        let draft = try store.load(id: id)
        #expect(draft != nil)
        #expect(draft?.id == id)
        #expect(draft?.title == "Hello")
        #expect(draft?.content == "<p>World</p>")
        #expect(draft?.excerpt == "Ex")
        #expect(draft?.type == "post")
    }

    @Test func loadByIdReflectsUpdates() throws {
        let id = try store.create(title: "Old", content: "old", excerpt: "", type: "post")
        try store.update(id: id, title: "New", content: "new", excerpt: "updated")
        let draft = try store.load(id: id)
        #expect(draft?.title == "New")
        #expect(draft?.content == "new")
        #expect(draft?.excerpt == "updated")
    }

    @Test func emptyTitleAndContentRoundTrip() throws {
        let id = try store.create(title: "", content: "", excerpt: "", type: "post")
        let draft = try store.load(id: id)
        #expect(draft?.title == "")
        #expect(draft?.content == "")
    }

    @Test func updateNonExistentIdDoesNotThrow() throws {
        try store.update(id: 9999, title: "X", content: "y", excerpt: "")
    }

    @Test func deleteNonExistentIdDoesNotThrow() throws {
        try store.delete(id: 9999)
    }

    @Test func fetchAllOrderedByUpdatedAtDesc() throws {
        let idA = try store.create(title: "A", content: "", excerpt: "", type: "post")
        Thread.sleep(forTimeInterval: 0.01)
        _ = try store.create(title: "B", content: "", excerpt: "", type: "post")
        Thread.sleep(forTimeInterval: 0.01)
        try store.update(id: idA, title: "A Updated", content: "", excerpt: "")
        let drafts = try store.fetchAll()
        #expect(drafts[0].title == "A Updated")
    }

    @Test func unicodeAndEmojiRoundTrip() throws {
        let title = "H\u{00E9}llo W\u{00F6}rld \u{1F30D} \u{201C}curly\u{201D}"
        let content = "<p>\u{00CB}moji \u{1F389} and \u{00AB}quotes\u{00BB}</p>"
        let id = try store.create(title: title, content: content, excerpt: "", type: "post")
        let draft = try store.load(id: id)
        #expect(draft?.title == title)
        #expect(draft?.content == content)
    }

    @Test func footnotesSurviveCreateAndLoad() throws {
        let id = try store.create(title: "T", content: "<p>x</p>", excerpt: "",
                                  footnotes: #"[{"id":"fn-a","content":"Note"}]"#)
        #expect(try store.load(id: id)?.footnotes == #"[{"id":"fn-a","content":"Note"}]"#)
    }

    @Test func updateReplacesFootnotes() throws {
        let id = try store.create(title: "T", content: "<p>x</p>", excerpt: "",
                                  footnotes: #"[{"id":"fn-a","content":"Note"}]"#)
        try store.update(id: id, title: "T", content: "<p>x</p>", excerpt: "", footnotes: "[]")
        #expect(try store.load(id: id)?.footnotes == "[]")
    }

    @Test func draftCreatedWithoutFootnotesReadsBackEmpty() throws {
        let id = try store.create(title: "T", content: "<p>x</p>", excerpt: "")
        #expect(try store.load(id: id)?.footnotes == "")
    }

    // fetchAll builds LocalDraft separately from load(id:), so the column has to
    // be read in both places — this is the one the sidebar and the editor use.
    @Test func fetchAllCarriesFootnotes() throws {
        _ = try store.create(title: "A", content: "", excerpt: "", footnotes: #"[{"id":"fn-a","content":"Note"}]"#)
        _ = try store.create(title: "B", content: "", excerpt: "")
        let byTitle = Dictionary(uniqueKeysWithValues: try store.fetchAll().map { ($0.title, $0.footnotes) })
        #expect(byTitle["A"] == #"[{"id":"fn-a","content":"Note"}]"#)
        #expect(byTitle["B"] == "")
    }

    // `footnotes` defaults to "" on update, so a call site that forgets the
    // argument erases the bodies instead of leaving them alone. Every PostEditorView
    // save path passes it; this pins the cost of a new one that does not.
    @Test func updateWithoutFootnotesErasesThem() throws {
        let id = try store.create(title: "T", content: "", excerpt: "", footnotes: #"[{"id":"fn-a","content":"Note"}]"#)
        try store.update(id: id, title: "T", content: "", excerpt: "")
        #expect(try store.load(id: id)?.footnotes == "")
    }

    // The full local-draft round trip: written on save, read back on reopen,
    // and unchanged by an edit that only touches the body.
    @Test func footnotesSurviveAnEditThatOnlyChangesTheContent() throws {
        let notes = #"[{"id":"fn-a","content":"The <em>note</em> body."}]"#
        let id = try store.create(title: "T", content: "<p>one</p>", excerpt: "", footnotes: notes)
        let reopened = try #require(try store.load(id: id))
        try store.update(id: id, title: reopened.title, content: "<p>one two</p>",
                         excerpt: reopened.excerpt, footnotes: reopened.footnotes)
        let after = try #require(try store.load(id: id))
        #expect(after.content == "<p>one two</p>")
        #expect(after.footnotes == notes)
    }
}
