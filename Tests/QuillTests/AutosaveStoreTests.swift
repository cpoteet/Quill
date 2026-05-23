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
}
