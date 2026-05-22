import Foundation
import Testing
@testable import WPWriterKit

@Suite struct DraftStoreTests {
    var db: AppDatabase
    var store: DraftStore

    init() throws {
        db = try AppDatabase.inMemory()
        store = DraftStore(db: db)
    }

    @Test func createAndFetch() throws {
        let id = try store.create(title: "Test", content: "<p>Hello</p>", excerpt: "")
        let drafts = try store.fetchAll()
        #expect(drafts.count == 1)
        #expect(drafts[0].id == id)
        #expect(drafts[0].title == "Test")
    }

    @Test func update() throws {
        let id = try store.create(title: "Original", content: "", excerpt: "")
        try store.update(id: id, title: "Updated", content: "<p>New</p>", excerpt: "Excerpt")
        let drafts = try store.fetchAll()
        #expect(drafts[0].title == "Updated")
        #expect(drafts[0].content == "<p>New</p>")
    }

    @Test func delete() throws {
        let id = try store.create(title: "ToDelete", content: "", excerpt: "")
        try store.delete(id: id)
        let drafts = try store.fetchAll()
        #expect(drafts.isEmpty)
    }
}
