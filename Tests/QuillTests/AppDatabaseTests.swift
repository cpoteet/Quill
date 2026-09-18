import Foundation
import Testing
@testable import QuillKit

@Suite struct AppDatabaseTests {

    @Test func migrationIsIdempotent() throws {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-idempotent-\(UUID().uuidString).db")
            .path
        defer { try? FileManager.default.removeItem(atPath: tempPath) }
        _ = try AppDatabase(path: tempPath)
        // Second open: migrate() runs again; CREATE IF NOT EXISTS + try? must not throw
        let db2 = try AppDatabase(path: tempPath)
        let store = DraftStore(db: db2)
        #expect(try store.fetchAll().isEmpty)
    }

    @Test func typeColumnMigratedFromOldSchema() throws {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-migrate-\(UUID().uuidString).db")
            .path
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        // Build a "pre-type" database: open via AppDatabase (which creates tables),
        // then drop and recreate local_drafts without the type column to simulate an old install.
        let setupDB = try AppDatabase(path: tempPath)
        try setupDB.db.run("DROP TABLE IF EXISTS local_drafts")
        try setupDB.db.run("""
            CREATE TABLE local_drafts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                excerpt TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
        """)
        let now = Date().timeIntervalSince1970
        try setupDB.db.run(
            "INSERT INTO local_drafts (title, content, excerpt, created_at, updated_at) VALUES ('Old Post', '<p>Hi</p>', '', \(now), \(now))"
        )

        // Re-open: migrate() fires ALTER TABLE ADD COLUMN type with DEFAULT 'post'
        let db = try AppDatabase(path: tempPath)
        let store = DraftStore(db: db)
        let drafts = try store.fetchAll()
        #expect(drafts.count == 1)
        #expect(drafts[0].title == "Old Post")
        #expect(drafts[0].type == "post")
    }

    private func tempDBPath(_ label: String) -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-\(label)-\(UUID().uuidString).db")
            .path
    }

    // The footnotes column arrived after the app shipped, so an existing install
    // reaches it only through ALTER TABLE. DraftStore reads it as a non-optional
    // String, so a silently-skipped migration is a crash, not a blank field.
    @Test func footnotesColumnMigratedOntoAnExistingDraftsTable() throws {
        let path = tempDBPath("draft-footnotes")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let setup = try AppDatabase(path: path)
        try setup.db.run("DROP TABLE IF EXISTS local_drafts")
        try setup.db.run("""
            CREATE TABLE local_drafts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                excerpt TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                type TEXT NOT NULL DEFAULT 'post'
            )
        """)
        let now = Date().timeIntervalSince1970
        try setup.db.run(
            "INSERT INTO local_drafts (title, content, excerpt, created_at, updated_at) VALUES ('Old', '<p>Hi</p>', '', \(now), \(now))"
        )

        let store = DraftStore(db: try AppDatabase(path: path))
        let migrated = try #require(try store.fetchAll().first)
        #expect(migrated.title == "Old")
        #expect(migrated.content == "<p>Hi</p>")
        #expect(migrated.footnotes == "")

        // The migrated column is writable, not just readable.
        try store.update(id: migrated.id, title: "Old", content: "<p>Hi</p>", excerpt: "",
                         footnotes: #"[{"id":"fn-a","content":"Note"}]"#)
        #expect(try store.load(id: migrated.id)?.footnotes == #"[{"id":"fn-a","content":"Note"}]"#)
    }

    // migrate() ALTERs autosaves *before* it creates the table, so this path only
    // works because an existing install already has the table. Pinned so a
    // reordering of migrate() cannot quietly drop the column for upgraders.
    @Test func footnotesColumnMigratedOntoAnExistingAutosavesTable() throws {
        let path = tempDBPath("autosave-footnotes")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let setup = try AppDatabase(path: path)
        try setup.db.run("DROP TABLE IF EXISTS autosaves")
        try setup.db.run("""
            CREATE TABLE autosaves (
                post_id INTEGER PRIMARY KEY,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                saved_at REAL NOT NULL,
                server_modified TEXT NOT NULL
            )
        """)
        try setup.db.run(
            "INSERT INTO autosaves (post_id, title, content, saved_at, server_modified) VALUES (11, 'Stashed', '<p>Hi</p>', \(Date().timeIntervalSince1970), '2024-01-01')"
        )

        let store = AutosaveStore(db: try AppDatabase(path: path))
        let migrated = try #require(try store.load(postID: 11))
        #expect(migrated.title == "Stashed")
        #expect(migrated.serverModified == "2024-01-01")
        #expect(migrated.footnotes == "")

        try store.save(postID: 11, title: "Stashed", content: "<p>Hi</p>",
                       footnotes: "[]", serverModified: "2024-01-02")
        #expect(try store.load(postID: 11)?.footnotes == "[]")
    }

    // Both tables name their column "footnotes"; the two Expressions must stay
    // scoped to their own table rather than colliding.
    @Test func draftAndAutosaveFootnotesAreIndependent() throws {
        let db = try AppDatabase.inMemory()
        let drafts = DraftStore(db: db)
        let autosaves = AutosaveStore(db: db)
        let id = try drafts.create(title: "D", content: "", excerpt: "", footnotes: #"["draft"]"#)
        try autosaves.save(postID: 1, title: "A", content: "", footnotes: #"["autosave"]"#, serverModified: "m")
        #expect(try drafts.load(id: id)?.footnotes == #"["draft"]"#)
        #expect(try autosaves.load(postID: 1)?.footnotes == #"["autosave"]"#)
    }
}
