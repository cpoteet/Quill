import Foundation
import Testing
@testable import QuillKit

@Suite struct AutosaveStoreTests {
    var db: AppDatabase
    var store: AutosaveStore
    let site = "https://a.test"

    init() throws {
        db = try AppDatabase.inMemory()
        store = AutosaveStore(db: db)
    }

    @Test func saveAndLoad() throws {
        try store.save(site: site, postID: 42, title: "Post", content: "<p>Hi</p>", serverModified: "2024-01-01T00:00:00")
        let snap = try store.load(site: site, postID: 42)
        #expect(snap != nil)
        #expect(snap?.title == "Post")
        #expect(snap?.serverModified == "2024-01-01T00:00:00")
    }

    @Test func loadReturnsNilForUnknownPost() throws {
        let snap = try store.load(site: site, postID: 999)
        #expect(snap == nil)
    }

    @Test func saveOverwritesExisting() throws {
        try store.save(site: site, postID: 1, title: "Old", content: "old", serverModified: "2024-01-01T00:00:00")
        try store.save(site: site, postID: 1, title: "New", content: "new", serverModified: "2024-01-02T00:00:00")
        let snap = try store.load(site: site, postID: 1)
        #expect(snap?.title == "New")
    }

    @Test func deleteRemovesAutosave() throws {
        try store.save(site: site, postID: 10, title: "T", content: "C", serverModified: "2024-01-01")
        try store.delete(site: site, postID: 10)
        #expect(try store.load(site: site, postID: 10) == nil)
    }

    @Test func deleteOnMissingPostIDDoesNotThrow() throws {
        try store.delete(site: site, postID: 999)
    }

    @Test func oneSavePerPostID() throws {
        try store.save(site: site, postID: 5, title: "A", content: "a", serverModified: "2024-01-01")
        try store.save(site: site, postID: 5, title: "B", content: "b", serverModified: "2024-01-02")
        let snap = try store.load(site: site, postID: 5)
        #expect(snap?.title == "B")
    }

    @Test func serverModifiedPreservedExactly() throws {
        let modified = "2025-12-31T23:59:59"
        try store.save(site: site, postID: 1, title: "", content: "", serverModified: modified)
        let snap = try store.load(site: site, postID: 1)
        #expect(snap?.serverModified == modified)
    }

    @Test func laterSaveHasNewerSavedAt() throws {
        try store.save(site: site, postID: 1, title: "V1", content: "", serverModified: "2024-01-01")
        let first = try store.load(site: site, postID: 1)!
        Thread.sleep(forTimeInterval: 0.01)
        try store.save(site: site, postID: 1, title: "V2", content: "", serverModified: "2024-01-02")
        let second = try store.load(site: site, postID: 1)!
        #expect(second.savedAt > first.savedAt)
    }

    @Test func footnotesSurviveTheStash() throws {
        try store.save(site: site, postID: 42, title: "P", content: "<p>Hi</p>",
                       footnotes: #"[{"id":"fn-a","content":"Note"}]"#, serverModified: "m")
        #expect(try store.load(site: site, postID: 42)?.footnotes == #"[{"id":"fn-a","content":"Note"}]"#)
    }

    @Test func omittedFootnotesDefaultToEmpty() throws {
        try store.save(site: site, postID: 43, title: "P", content: "<p>Hi</p>", serverModified: "m")
        #expect(try store.load(site: site, postID: 43)?.footnotes == "")
    }

    // save() is insert-or-replace and `footnotes` defaults to "", so a re-save
    // that omits the argument replaces the whole row and drops the bodies.
    @Test func resavingWithoutFootnotesErasesThem() throws {
        try store.save(site: site, postID: 44, title: "P", content: "c",
                       footnotes: #"[{"id":"fn-a","content":"Note"}]"#, serverModified: "m")
        try store.save(site: site, postID: 44, title: "P", content: "c2", serverModified: "m")
        #expect(try store.load(site: site, postID: 44)?.footnotes == "")
    }

    // The restore path: an autosave stashed on post switch must come back with
    // the same three halves the editor needs to rebuild the post.
    @Test func replacingAnAutosaveKeepsTitleContentAndFootnotesInStep() throws {
        try store.save(site: site, postID: 45, title: "V1", content: "<p>one</p>",
                       footnotes: #"[{"id":"fn-a","content":"One"}]"#, serverModified: "m1")
        try store.save(site: site, postID: 45, title: "V2", content: "<p>two</p>",
                       footnotes: #"[{"id":"fn-a","content":"One"},{"id":"fn-b","content":"Two"}]"#,
                       serverModified: "m2")
        let snap = try #require(try store.load(site: site, postID: 45))
        #expect(snap.title == "V2")
        #expect(snap.content == "<p>two</p>")
        #expect(snap.footnotes == #"[{"id":"fn-a","content":"One"},{"id":"fn-b","content":"Two"}]"#)
        #expect(snap.serverModified == "m2")
    }

    @Test func deletingTheLastFootnoteStoresAnEmptyArrayNotAnEmptyString() throws {
        try store.save(site: site, postID: 46, title: "P", content: "c",
                       footnotes: #"[{"id":"fn-a","content":"Note"}]"#, serverModified: "m")
        try store.save(site: site, postID: 46, title: "P", content: "c", footnotes: "[]", serverModified: "m")
        #expect(try store.load(site: site, postID: 46)?.footnotes == "[]")
    }

    @Test func samePostIDOnTwoSitesIsTwoStashes() throws {
        try store.save(site: "https://a.test", postID: 7, title: "A", content: "", serverModified: "m")
        try store.save(site: "https://b.test", postID: 7, title: "B", content: "", serverModified: "m")
        #expect(try store.load(site: "https://a.test", postID: 7)?.title == "A")
        #expect(try store.load(site: "https://b.test", postID: 7)?.title == "B")
        try store.delete(site: "https://a.test", postID: 7)
        #expect(try store.load(site: "https://a.test", postID: 7) == nil)
        #expect(try store.load(site: "https://b.test", postID: 7)?.title == "B")
    }

    @Test func unsitedStashesBelongToTheFirstSiteThatAdoptsThem() throws {
        try db.db.run("INSERT INTO autosaves (site, post_id, title, content, saved_at, server_modified) VALUES ('', 3, 'Legacy', '', 0, 'm')")
        #expect(try store.load(site: "https://a.test", postID: 3) == nil)
        try store.adoptUnsited(site: "https://a.test")
        try store.adoptUnsited(site: "https://b.test")
        #expect(try store.load(site: "https://a.test", postID: 3)?.title == "Legacy")
        #expect(try store.load(site: "https://b.test", postID: 3) == nil)
    }

    @Test func adoptionKeepsTheSitedStashWhenBothExist() throws {
        try db.db.run("INSERT INTO autosaves (site, post_id, title, content, saved_at, server_modified) VALUES ('', 3, 'Legacy', '', 0, 'm')")
        try store.save(site: "https://a.test", postID: 3, title: "Newer", content: "", serverModified: "m")
        try store.adoptUnsited(site: "https://a.test")
        #expect(try store.load(site: "https://a.test", postID: 3)?.title == "Newer")
        #expect(try db.db.scalar("SELECT COUNT(*) FROM autosaves WHERE site = ''") as? Int64 == 0)
    }
}
