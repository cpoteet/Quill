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
}
