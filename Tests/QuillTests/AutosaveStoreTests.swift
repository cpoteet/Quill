import Foundation
import Testing
@testable import QuillKit

@Suite struct AutosaveStoreTests {
    var db: AppDatabase
    var store: AutosaveStore

    init() throws {
        db = try AppDatabase.inMemory()
        store = AutosaveStore(db: db)
    }

    @Test func saveAndLoad() throws {
        try store.save(postID: 42, title: "Post", content: "<p>Hi</p>", serverModified: "2024-01-01T00:00:00")
        let snap = try store.load(postID: 42)
        #expect(snap != nil)
        #expect(snap?.title == "Post")
        #expect(snap?.serverModified == "2024-01-01T00:00:00")
    }

    @Test func loadReturnsNilForUnknownPost() throws {
        let snap = try store.load(postID: 999)
        #expect(snap == nil)
    }

    @Test func saveOverwritesExisting() throws {
        try store.save(postID: 1, title: "Old", content: "old", serverModified: "2024-01-01T00:00:00")
        try store.save(postID: 1, title: "New", content: "new", serverModified: "2024-01-02T00:00:00")
        let snap = try store.load(postID: 1)
        #expect(snap?.title == "New")
    }

    @Test func deleteRemovesAutosave() throws {
        try store.save(postID: 10, title: "T", content: "C", serverModified: "2024-01-01")
        try store.delete(postID: 10)
        #expect(try store.load(postID: 10) == nil)
    }

    @Test func deleteOnMissingPostIDDoesNotThrow() throws {
        try store.delete(postID: 999)
    }

    @Test func oneSavePerPostID() throws {
        try store.save(postID: 5, title: "A", content: "a", serverModified: "2024-01-01")
        try store.save(postID: 5, title: "B", content: "b", serverModified: "2024-01-02")
        let snap = try store.load(postID: 5)
        #expect(snap?.title == "B")
    }

    @Test func serverModifiedPreservedExactly() throws {
        let modified = "2025-12-31T23:59:59"
        try store.save(postID: 1, title: "", content: "", serverModified: modified)
        let snap = try store.load(postID: 1)
        #expect(snap?.serverModified == modified)
    }

    @Test func laterSaveHasNewerSavedAt() throws {
        try store.save(postID: 1, title: "V1", content: "", serverModified: "2024-01-01")
        let first = try store.load(postID: 1)!
        Thread.sleep(forTimeInterval: 0.01)
        try store.save(postID: 1, title: "V2", content: "", serverModified: "2024-01-02")
        let second = try store.load(postID: 1)!
        #expect(second.savedAt > first.savedAt)
    }

    @Test func footnotesSurviveTheStash() throws {
        try store.save(postID: 42, title: "P", content: "<p>Hi</p>",
                       footnotes: #"[{"id":"fn-a","content":"Note"}]"#, serverModified: "m")
        #expect(try store.load(postID: 42)?.footnotes == #"[{"id":"fn-a","content":"Note"}]"#)
    }

    @Test func omittedFootnotesDefaultToEmpty() throws {
        try store.save(postID: 43, title: "P", content: "<p>Hi</p>", serverModified: "m")
        #expect(try store.load(postID: 43)?.footnotes == "")
    }
}
