import Foundation
import SQLite

public struct LocalDraft: Identifiable, Sendable {
    public let id: Int64
    public var title: String
    public var content: String
    public var excerpt: String
    public var createdAt: Date
    public var updatedAt: Date
}

public final class DraftStore: @unchecked Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    @discardableResult
    public func create(title: String, content: String, excerpt: String) throws -> Int64 {
        let now = Date().timeIntervalSince1970
        return try db.db.run(db.drafts.insert(
            db.draftTitle <- title,
            db.draftContent <- content,
            db.draftExcerpt <- excerpt,
            db.draftCreatedAt <- now,
            db.draftUpdatedAt <- now
        ))
    }

    public func fetchAll() throws -> [LocalDraft] {
        try db.db.prepare(db.drafts.order(db.draftUpdatedAt.desc)).map { row in
            LocalDraft(
                id: row[db.draftID],
                title: row[db.draftTitle],
                content: row[db.draftContent],
                excerpt: row[db.draftExcerpt],
                createdAt: Date(timeIntervalSince1970: row[db.draftCreatedAt]),
                updatedAt: Date(timeIntervalSince1970: row[db.draftUpdatedAt])
            )
        }
    }

    public func update(id: Int64, title: String, content: String, excerpt: String) throws {
        let row = db.drafts.filter(db.draftID == id)
        try db.db.run(row.update(
            db.draftTitle <- title,
            db.draftContent <- content,
            db.draftExcerpt <- excerpt,
            db.draftUpdatedAt <- Date().timeIntervalSince1970
        ))
    }

    public func delete(id: Int64) throws {
        try db.db.run(db.drafts.filter(db.draftID == id).delete())
    }
}
