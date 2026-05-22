import Foundation
import SQLite

public struct AutosaveSnapshot: Sendable {
    public let postID: Int
    public var title: String
    public var content: String
    public var savedAt: Date
    public var serverModified: String
}

public final class AutosaveStore: @unchecked Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    public func save(postID: Int, title: String, content: String, serverModified: String) throws {
        try db.db.run(db.autosaves.insert(or: .replace,
            db.autosavePostID <- postID,
            db.autosaveTitle <- title,
            db.autosaveContent <- content,
            db.autosaveSavedAt <- Date().timeIntervalSince1970,
            db.autosaveServerModified <- serverModified
        ))
    }

    public func load(postID: Int) throws -> AutosaveSnapshot? {
        let query = db.autosaves.filter(db.autosavePostID == postID)
        guard let row = try db.db.pluck(query) else { return nil }
        return AutosaveSnapshot(
            postID: row[db.autosavePostID],
            title: row[db.autosaveTitle],
            content: row[db.autosaveContent],
            savedAt: Date(timeIntervalSince1970: row[db.autosaveSavedAt]),
            serverModified: row[db.autosaveServerModified]
        )
    }

    public func delete(postID: Int) throws {
        try db.db.run(db.autosaves.filter(db.autosavePostID == postID).delete())
    }
}
