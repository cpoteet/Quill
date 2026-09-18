import Foundation
import Testing
@testable import QuillKit

@Suite struct PostPayloadTests {

    private func encodeToDict(_ payload: PostPayload) throws -> [String: Any] {
        let data = try JSONEncoder().encode(payload)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @Test func schedulingUsesDateGmtKeyNotDate() throws {
        let payload = PostPayload(title: "T", content: "C", status: "future",
                                  dateGmt: "2026-06-01T14:00:00Z")
        let dict = try encodeToDict(payload)
        // Must use date_gmt, never date — the documented scheduling gotcha
        #expect(dict["date_gmt"] as? String == "2026-06-01T14:00:00Z")
        #expect(dict["date"] == nil)
    }

    @Test func nilDateGmtOmitsKeyFromJSON() throws {
        let payload = PostPayload(title: "T", content: "C", status: "draft")
        let dict = try encodeToDict(payload)
        #expect(dict["date_gmt"] == nil)
    }

    @Test func nilSlugOmitsKeyFromJSON() throws {
        let payload = PostPayload(title: "T", content: "C", status: "draft", slug: nil)
        let dict = try encodeToDict(payload)
        // Omitting slug preserves the server value on update
        #expect(dict["slug"] == nil)
    }

    @Test func nonEmptySlugIncludedInJSON() throws {
        let payload = PostPayload(title: "T", content: "C", status: "draft", slug: "my-post")
        let dict = try encodeToDict(payload)
        #expect(dict["slug"] as? String == "my-post")
    }

    @Test func nilFeaturedMediaOmitsKey() throws {
        let payload = PostPayload(title: "T", content: "C", status: "draft", featuredMedia: nil)
        let dict = try encodeToDict(payload)
        #expect(dict["featured_media"] == nil)
    }

    @Test func featuredMediaIncludedWhenSet() throws {
        let payload = PostPayload(title: "T", content: "C", status: "draft", featuredMedia: 99)
        let dict = try encodeToDict(payload)
        #expect(dict["featured_media"] as? Int == 99)
    }

    @Test func nilParentOmitsKey() throws {
        let payload = PostPayload(title: "T", content: "C", status: "draft", parent: nil)
        let dict = try encodeToDict(payload)
        #expect(dict["parent"] == nil)
    }

    @Test func parentIncludedForPages() throws {
        let payload = PostPayload(title: "T", content: "C", status: "publish", parent: 5)
        let dict = try encodeToDict(payload)
        #expect(dict["parent"] as? Int == 5)
    }

    @Test func emptyCategoriesAndTagsEncodeAsEmptyArrays() throws {
        let payload = PostPayload(title: "T", content: "C", status: "draft")
        let dict = try encodeToDict(payload)
        #expect((dict["categories"] as? [Int]) == [])
        #expect((dict["tags"] as? [Int]) == [])
    }

    @Test func categoriesAndTagsPopulated() throws {
        let payload = PostPayload(title: "T", content: "C", status: "draft",
                                  categories: [1, 2], tags: [3])
        let dict = try encodeToDict(payload)
        #expect(dict["categories"] as? [Int] == [1, 2])
        #expect(dict["tags"] as? [Int] == [3])
    }

    @Test func codingKeyNamesAreCorrect() throws {
        let payload = PostPayload(title: "T", content: "C", status: "draft",
                                  featuredMedia: 1, commentStatus: "closed")
        let dict = try encodeToDict(payload)
        // These snake_case keys are the documented CodingKeys — wrong names break the API
        #expect(dict["featured_media"] != nil)
        #expect(dict["comment_status"] as? String == "closed")
        #expect(dict["featuredMedia"] == nil)   // camelCase must not appear
        #expect(dict["commentStatus"] == nil)
    }

    // core/footnotes is a dynamic block: the bodies travel in post meta, never
    // in content. See docs/footnotes-meta.md.
    @Test func footnotesAreSentUnderMeta() throws {
        let payload = PostPayload(title: "T", content: "C", status: "draft",
                                  footnotes: #"[{"id":"fn-a","content":"Note"}]"#)
        let dict = try encodeToDict(payload)
        let meta = dict["meta"] as? [String: Any]
        #expect(meta?["footnotes"] as? String == #"[{"id":"fn-a","content":"Note"}]"#)
    }

    @Test func nilFootnotesOmitsMetaEntirely() throws {
        let payload = PostPayload(title: "T", content: "C", status: "draft")
        let dict = try encodeToDict(payload)
        #expect(dict["meta"] == nil)
    }

    @Test func emptyFootnotesStillSendsMetaSoDeletingTheLastOneClearsIt() throws {
        let payload = PostPayload(title: "T", content: "C", status: "draft", footnotes: "[]")
        let dict = try encodeToDict(payload)
        #expect((dict["meta"] as? [String: Any])?["footnotes"] as? String == "[]")
    }

    @Test func everyOtherFieldStillEncodesAlongsideMeta() throws {
        let payload = PostPayload(title: "T", content: "C", excerpt: "E", status: "future",
                                  dateGmt: "2026-06-01T14:00:00Z", featuredMedia: 7,
                                  categories: [1], tags: [2], slug: "s",
                                  commentStatus: "closed", parent: 3, footnotes: "[]")
        let dict = try encodeToDict(payload)
        #expect(dict["title"] as? String == "T")
        #expect(dict["content"] as? String == "C")
        #expect(dict["excerpt"] as? String == "E")
        #expect(dict["status"] as? String == "future")
        #expect(dict["date_gmt"] as? String == "2026-06-01T14:00:00Z")
        #expect(dict["featured_media"] as? Int == 7)
        #expect(dict["categories"] as? [Int] == [1])
        #expect(dict["tags"] as? [Int] == [2])
        #expect(dict["slug"] as? String == "s")
        #expect(dict["comment_status"] as? String == "closed")
        #expect(dict["parent"] as? Int == 3)
    }
}
