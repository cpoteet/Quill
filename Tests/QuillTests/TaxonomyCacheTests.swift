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

    // MARK: - Tags

    @Test func saveAndLoadTags() throws {
        let tags = [
            WPTag(id: 1, name: "Swift", slug: "swift", count: 10),
            WPTag(id: 2, name: "iOS", slug: "ios", count: 5),
        ]
        try cache.saveTags(tags)
        let loaded = try cache.loadTags()
        #expect(loaded.count == 2)
        #expect(loaded[0].name == "Swift")
    }

    @Test func staleTagsAfterTTL() throws {
        let staleDate = Date().addingTimeInterval(-25 * 3600)
        try cache.saveTags([WPTag(id: 1, name: "Old", slug: "old", count: 0)], fetchedAt: staleDate)
        #expect(try cache.isTagStale())
    }

    @Test func freshTagsWithinTTL() throws {
        try cache.saveTags([WPTag(id: 1, name: "Fresh", slug: "fresh", count: 0)])
        #expect(try !cache.isTagStale())
    }

    // MARK: - TTL boundary

    @Test func staleJustAfterTTLBoundary() throws {
        let date = Date().addingTimeInterval(-(24 * 3600 + 60))  // 24h01m ago
        try cache.saveCategories([WPCategory(id: 1, name: "C", slug: "c", count: 0, parent: 0)], fetchedAt: date)
        #expect(try cache.isCategoryStale())
    }

    @Test func freshJustBeforeTTLBoundary() throws {
        let date = Date().addingTimeInterval(-(24 * 3600 - 60))  // 23h59m ago
        try cache.saveCategories([WPCategory(id: 1, name: "C", slug: "c", count: 0, parent: 0)], fetchedAt: date)
        #expect(try !cache.isCategoryStale())
    }

    // MARK: - Replace semantics

    @Test func saveCategoriesReplacesAll() throws {
        try cache.saveCategories([
            WPCategory(id: 1, name: "A", slug: "a", count: 0, parent: 0),
            WPCategory(id: 2, name: "B", slug: "b", count: 0, parent: 0),
        ])
        try cache.saveCategories([
            WPCategory(id: 2, name: "B2", slug: "b2", count: 0, parent: 0),
            WPCategory(id: 3, name: "C", slug: "c", count: 0, parent: 0),
        ])
        let loaded = try cache.loadCategories()
        #expect(loaded.count == 2)
        #expect(Set(loaded.map(\.id)) == [2, 3])
    }

    // MARK: - Non-collision between types

    @Test func categoryAndTagWithSameIDCoexist() throws {
        try cache.saveCategories([WPCategory(id: 1, name: "CatOne", slug: "catone", count: 0, parent: 0)])
        try cache.saveTags([WPTag(id: 1, name: "TagOne", slug: "tagone", count: 0)])
        let cats = try cache.loadCategories()
        let tags = try cache.loadTags()
        #expect(cats.count == 1)
        #expect(tags.count == 1)
        #expect(cats[0].name == "CatOne")
        #expect(tags[0].name == "TagOne")
    }

    // MARK: - Empty save

    @Test func saveEmptyCategoriesYieldsEmptyLoad() throws {
        try cache.saveCategories([WPCategory(id: 1, name: "Old", slug: "old", count: 0, parent: 0)])
        try cache.saveCategories([])
        #expect(try cache.loadCategories().isEmpty)
    }

    @Test func isStaleWhenNoDataExists() throws {
        #expect(try cache.isCategoryStale())
        #expect(try cache.isTagStale())
    }
}
