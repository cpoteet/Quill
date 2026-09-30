import Foundation
import SQLite

public struct AutosaveSnapshot: Sendable {
    public let postID: Int
    public var title: String
    public var content: String
    public var footnotes: String  // core/footnotes bodies as JSON
    public var savedAt: Date
    public var serverModified: String
}

public final class AutosaveStore: @unchecked Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    public func save(site: String, postID: Int, title: String, content: String, footnotes: String = "", serverModified: String) throws {
        try db.db.run(
            db.autosaves.insert(
                or: .replace,
                db.autosaveSite <- site,
                db.autosavePostID <- postID,
                db.autosaveTitle <- title,
                db.autosaveContent <- content,
                db.autosaveFootnotes <- footnotes,
                db.autosaveSavedAt <- Date().timeIntervalSince1970,
                db.autosaveServerModified <- serverModified
            ))
    }

    public func load(site: String, postID: Int) throws -> AutosaveSnapshot? {
        let query = db.autosaves.filter(db.autosaveSite == site && db.autosavePostID == postID)
        guard let row = try db.db.pluck(query) else { return nil }
        return AutosaveSnapshot(
            postID: row[db.autosavePostID],
            title: row[db.autosaveTitle],
            content: row[db.autosaveContent],
            footnotes: row[db.autosaveFootnotes],
            savedAt: Date(timeIntervalSince1970: row[db.autosaveSavedAt]),
            serverModified: row[db.autosaveServerModified]
        )
    }

    public func delete(site: String, postID: Int) throws {
        try db.db.run(db.autosaves.filter(db.autosaveSite == site && db.autosavePostID == postID).delete())
    }

    // A stash already written for the site is newer than an unsited one, so it wins.
    public func adoptUnsited(site: String) throws {
        try db.db.transaction {
            try db.db.run("UPDATE OR IGNORE autosaves SET site = ? WHERE site = ''", site)
            try db.db.run("DELETE FROM autosaves WHERE site = ''")
        }
    }
}
