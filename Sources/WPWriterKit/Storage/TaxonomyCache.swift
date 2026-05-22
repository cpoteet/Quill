import Foundation
import SQLite

public final class TaxonomyCache: @unchecked Sendable {
    private let db: AppDatabase
    private let ttl: TimeInterval = 24 * 3600   // 24 hours

    public init(db: AppDatabase) {
        self.db = db
    }

    public func saveCategories(_ categories: [WPCategory], fetchedAt: Date = .init()) throws {
        try db.db.run(db.taxonomyCache.filter(db.taxType == "category").delete())
        for cat in categories {
            try db.db.run(db.taxonomyCache.insert(or: .replace,
                db.taxType <- "category",
                db.taxID <- cat.id,
                db.taxName <- cat.name,
                db.taxSlug <- cat.slug,
                db.taxFetchedAt <- fetchedAt.timeIntervalSince1970
            ))
        }
    }

    public func loadCategories() throws -> [WPCategory] {
        try db.db.prepare(db.taxonomyCache.filter(db.taxType == "category").order(db.taxID)).map { row in
            WPCategory(id: row[db.taxID], name: row[db.taxName], slug: row[db.taxSlug], count: 0, parent: 0)
        }
    }

    public func isCategoryStale() throws -> Bool {
        guard let row = try db.db.pluck(db.taxonomyCache.filter(db.taxType == "category")) else { return true }
        return Date().timeIntervalSince1970 - row[db.taxFetchedAt] > ttl
    }

    public func saveTags(_ tags: [WPTag], fetchedAt: Date = .init()) throws {
        try db.db.run(db.taxonomyCache.filter(db.taxType == "tag").delete())
        for tag in tags {
            try db.db.run(db.taxonomyCache.insert(or: .replace,
                db.taxType <- "tag",
                db.taxID <- tag.id,
                db.taxName <- tag.name,
                db.taxSlug <- tag.slug,
                db.taxFetchedAt <- fetchedAt.timeIntervalSince1970
            ))
        }
    }

    public func loadTags() throws -> [WPTag] {
        try db.db.prepare(db.taxonomyCache.filter(db.taxType == "tag").order(db.taxID)).map { row in
            WPTag(id: row[db.taxID], name: row[db.taxName], slug: row[db.taxSlug], count: 0)
        }
    }

    public func isTagStale() throws -> Bool {
        guard let row = try db.db.pluck(db.taxonomyCache.filter(db.taxType == "tag")) else { return true }
        return Date().timeIntervalSince1970 - row[db.taxFetchedAt] > ttl
    }
}
