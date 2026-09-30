import Foundation
import SQLite

public final class AppDatabase: @unchecked Sendable {
    let db: Connection

    // local_drafts columns
    let drafts = Table("local_drafts")
    let draftID = Expression<Int64>("id")
    let draftTitle = Expression<String>("title")
    let draftContent = Expression<String>("content")
    let draftExcerpt = Expression<String>("excerpt")
    let draftCreatedAt = Expression<Double>("created_at")
    let draftUpdatedAt = Expression<Double>("updated_at")
    let draftType = Expression<String>("type")

    // autosaves columns
    let autosaves = Table("autosaves")
    let autosaveSite = Expression<String>("site")
    let autosavePostID = Expression<Int>("post_id")
    let autosaveTitle = Expression<String>("title")
    let autosaveContent = Expression<String>("content")
    let autosaveSavedAt = Expression<Double>("saved_at")
    let autosaveServerModified = Expression<String>("server_modified")

    // taxonomy_cache columns
    let taxonomyCache = Table("taxonomy_cache")
    let taxType = Expression<String>("type")  // "category" or "tag"
    let taxID = Expression<Int>("wp_id")
    let taxName = Expression<String>("name")
    public let draftFootnotes = Expression<String>("footnotes")
    public let autosaveFootnotes = Expression<String>("footnotes")
    let taxSlug = Expression<String>("slug")
    let taxFetchedAt = Expression<Double>("fetched_at")

    public init(path: String) throws {
        db = try Connection(path)
        try migrate()
    }

    private func migrate() throws {
        try db.run(
            drafts.create(ifNotExists: true) { t in
                t.column(draftID, primaryKey: .autoincrement)
                t.column(draftTitle)
                t.column(draftContent)
                t.column(draftExcerpt)
                t.column(draftCreatedAt)
                t.column(draftUpdatedAt)
                t.column(draftType, defaultValue: "post")
                t.column(draftFootnotes, defaultValue: "")
            })
        // Migration for existing databases: silently ignored if column already exists
        try? db.run("ALTER TABLE local_drafts ADD COLUMN type TEXT NOT NULL DEFAULT 'post'")
        try? db.run("ALTER TABLE local_drafts ADD COLUMN footnotes TEXT NOT NULL DEFAULT ''")
        try? db.run("ALTER TABLE autosaves ADD COLUMN footnotes TEXT NOT NULL DEFAULT ''")
        try addSiteKeyToAutosaves()

        try db.run(
            autosaves.create(ifNotExists: true) { t in
                t.column(autosaveSite)
                t.column(autosavePostID)
                t.column(autosaveTitle)
                t.column(autosaveContent)
                t.column(autosaveSavedAt)
                t.column(autosaveServerModified)
                t.column(autosaveFootnotes, defaultValue: "")
                t.primaryKey(autosaveSite, autosavePostID)
            })

        try db.run(
            taxonomyCache.create(ifNotExists: true) { t in
                t.column(taxType)
                t.column(taxID)
                t.column(taxName)
                t.column(taxSlug)
                t.column(taxFetchedAt)
                t.primaryKey(taxType, taxID)
            })
    }

    // Rows from before the site key get site '' until AutosaveStore.adoptUnsited claims them.
    private func addSiteKeyToAutosaves() throws {
        let columns = try db.prepare("PRAGMA table_info(autosaves)").map { $0[1] as? String }
        guard !columns.isEmpty, !columns.contains("site") else { return }
        try db.transaction {
            try db.run("ALTER TABLE autosaves RENAME TO autosaves_unsited")
            try db.run("""
                CREATE TABLE autosaves (
                    site TEXT NOT NULL,
                    post_id INTEGER NOT NULL,
                    title TEXT NOT NULL,
                    content TEXT NOT NULL,
                    saved_at REAL NOT NULL,
                    server_modified TEXT NOT NULL,
                    footnotes TEXT NOT NULL DEFAULT '',
                    PRIMARY KEY (site, post_id)
                )
            """)
            try db.run("""
                INSERT INTO autosaves (site, post_id, title, content, saved_at, server_modified, footnotes)
                SELECT '', post_id, title, content, saved_at, server_modified, footnotes FROM autosaves_unsited
            """)
            try db.run("DROP TABLE autosaves_unsited")
        }
    }

    public static func production() throws -> AppDatabase {
        let dir = try AppSupportDirectory.directory()
        return try AppDatabase(path: dir.appendingPathComponent("drafts.db").path)
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(path: ":memory:")
    }
}
