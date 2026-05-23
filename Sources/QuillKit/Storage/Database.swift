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
            })
        // Migration for existing databases: silently ignored if column already exists
        try? db.run("ALTER TABLE local_drafts ADD COLUMN type TEXT NOT NULL DEFAULT 'post'")

        try db.run(
            autosaves.create(ifNotExists: true) { t in
                t.column(autosavePostID, primaryKey: true)
                t.column(autosaveTitle)
                t.column(autosaveContent)
                t.column(autosaveSavedAt)
                t.column(autosaveServerModified)
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

    public static func production() throws -> AppDatabase {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quill", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try AppDatabase(path: dir.appendingPathComponent("drafts.db").path)
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(path: ":memory:")
    }
}
