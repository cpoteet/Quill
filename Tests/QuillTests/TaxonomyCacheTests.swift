import Foundation
import Testing
@testable import QuillKit

@Suite struct TaxonomyCacheTests {
    var db: AppDatabase
    var cache: TaxonomyCache

    init() throws {
        db = try AppDatabase.inMemory()
        cache = TaxonomyCache(db: db)
    }

    @Test func saveAndLoadCategories() throws {
        let cats = [
            WPCategory(id: 1, name: "Tech", slug: "tech", count: 5, parent: 0),
            WPCategory(id: 2, name: "News", slug: "news", count: 3, parent: 0),
        ]
        try cache.saveCategories(cats)
        let loaded = try cache.loadCategories()
        #expect(loaded.count == 2)
        #expect(loaded[0].name == "Tech")
    }

    @Test func staleAfterTTL() throws {
        let staleDate = Date().addingTimeInterval(-25 * 3600)
        let cats = [WPCategory(id: 1, name: "Old", slug: "old", count: 0, parent: 0)]
        try cache.saveCategories(cats, fetchedAt: staleDate)
        #expect(try cache.isCategoryStale())
    }

    @Test func freshWithinTTL() throws {
        let cats = [WPCategory(id: 1, name: "Fresh", slug: "fresh", count: 0, parent: 0)]
        try cache.saveCategories(cats)
        #expect(try !cache.isCategoryStale())
    }
}
