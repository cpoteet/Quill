import Foundation
import Testing
@testable import QuillKit

@Suite struct WPPostDecodingTests {

    private func decode(_ json: String) throws -> WPPost {
        try JSONDecoder().decode(WPPost.self, from: json.data(using: .utf8)!)
    }

    private let fullJSON = """
    {"id":1,"type":"post",
     "title":{"rendered":"Hello","raw":"Hello"},
     "content":{"rendered":"<p>Body</p>","raw":"<p>Body</p>"},
     "excerpt":{"rendered":"Excerpt","raw":"Excerpt"},
     "status":"publish","date":"2024-01-01T00:00:00",
     "date_gmt":"2024-01-01T00:00:00","modified":"2024-01-02T00:00:00",
     "slug":"hello","link":"https://example.com/hello",
     "featured_media":42,"categories":[1,2],"tags":[3],
     "parent":0,"comment_status":"open"}
    """

    @Test func fullPostDecodesAllFields() throws {
        let post = try decode(fullJSON)
        #expect(post.id == 1)
        #expect(post.type == "post")
        #expect(post.title.rendered == "Hello")
        #expect(post.title.raw == "Hello")
        #expect(post.content.raw == "<p>Body</p>")
        #expect(post.excerpt.raw == "Excerpt")
        #expect(post.excerpt.rendered == "Excerpt")
        #expect(post.status == "publish")
        #expect(post.dateGmt == "2024-01-01T00:00:00")
        #expect(post.modified == "2024-01-02T00:00:00")
        #expect(post.slug == "hello")
        #expect(post.link == "https://example.com/hello")
        #expect(post.featuredMedia == 42)
        #expect(post.categories == [1, 2])
        #expect(post.tags == [3])
        #expect(post.commentStatus == "open")
    }

    // Pages endpoint omits categories and tags — must default to []
    @Test func pageOmittingCategoriesAndTagsDefaultsToEmpty() throws {
        let json = """
        {"id":2,"type":"page",
         "title":{"rendered":"About"},"content":{"rendered":"<p>x</p>"},
         "excerpt":{"rendered":""},
         "status":"publish","date":"2024-01-01T00:00:00",
         "modified":"2024-01-01T00:00:00","slug":"about","link":"https://example.com/about"}
        """
        let post = try decode(json)
        #expect(post.categories == [])
        #expect(post.tags == [])
        #expect(post.type == "page")
    }

    @Test func missingTypeDefaultsToPost() throws {
        let json = """
        {"id":3,"title":{"rendered":"T"},"content":{"rendered":"C"},
         "excerpt":{"rendered":""},"status":"draft",
         "date":"2024-01-01T00:00:00","modified":"2024-01-01T00:00:00",
         "slug":"t","link":"https://example.com/t"}
        """
        let post = try decode(json)
        #expect(post.type == "post")
    }

    @Test func missingFeaturedMediaDefaultsToZero() throws {
        let json = """
        {"id":4,"title":{"rendered":"T"},"content":{"rendered":"C"},
         "excerpt":{"rendered":""},"status":"draft",
         "date":"2024-01-01T00:00:00","modified":"2024-01-01T00:00:00",
         "slug":"t","link":"https://example.com/t"}
        """
        let post = try decode(json)
        #expect(post.featuredMedia == 0)
    }

    @Test func missingDateGmtDefaultsToEmptyString() throws {
        let json = """
        {"id":5,"title":{"rendered":"T"},"content":{"rendered":"C"},
         "excerpt":{"rendered":""},"status":"draft",
         "date":"2024-01-01T00:00:00","modified":"2024-01-01T00:00:00",
         "slug":"t","link":"https://example.com/t"}
        """
        let post = try decode(json)
        #expect(post.dateGmt == "")
    }

    @Test func missingParentDefaultsToZero() throws {
        let json = """
        {"id":6,"title":{"rendered":"T"},"content":{"rendered":"C"},
         "excerpt":{"rendered":""},"status":"draft",
         "date":"2024-01-01T00:00:00","modified":"2024-01-01T00:00:00",
         "slug":"t","link":"https://example.com/t"}
        """
        let post = try decode(json)
        #expect(post.parent == 0)
    }

    @Test func missingCommentStatusDefaultsToOpen() throws {
        let json = """
        {"id":7,"title":{"rendered":"T"},"content":{"rendered":"C"},
         "excerpt":{"rendered":""},"status":"draft",
         "date":"2024-01-01T00:00:00","modified":"2024-01-01T00:00:00",
         "slug":"t","link":"https://example.com/t"}
        """
        let post = try decode(json)
        #expect(post.commentStatus == "open")
    }

    @Test func contentRawPreferredOverRendered() throws {
        let json = """
        {"id":8,"title":{"rendered":"T"},
         "content":{"rendered":"<p>rendered</p>","raw":"<p>raw</p>"},
         "excerpt":{"rendered":""},"status":"publish",
         "date":"2024-01-01T00:00:00","modified":"2024-01-01T00:00:00",
         "slug":"t","link":"https://example.com/t"}
        """
        let post = try decode(json)
        #expect(post.content.raw == "<p>raw</p>")
        #expect(post.content.rendered == "<p>rendered</p>")
        #expect(post.content.editorHTML == "<p>raw</p>")
    }

    @Test func emptyContentRawFallsBackToRenderedForEditorHTML() throws {
        let json = """
        {"id":9,"title":{"rendered":"T"},
         "content":{"rendered":"<p>rendered body</p>","raw":""},
         "excerpt":{"rendered":""},"status":"publish",
         "date":"2024-01-01T00:00:00","modified":"2024-01-01T00:00:00",
         "slug":"t","link":"https://example.com/t"}
        """
        let post = try decode(json)
        #expect(post.content.raw == "")
        #expect(post.content.editorHTML == "<p>rendered body</p>")
    }

    @Test func whitespaceContentRawFallsBackToRenderedForEditorHTML() throws {
        let json = """
        {"id":10,"title":{"rendered":"T"},
         "content":{"rendered":"<p>rendered body</p>","raw":"\\n  "},
         "excerpt":{"rendered":""},"status":"publish",
         "date":"2024-01-01T00:00:00","modified":"2024-01-01T00:00:00",
         "slug":"t","link":"https://example.com/t"}
        """
        let post = try decode(json)
        #expect(post.content.editorHTML == "<p>rendered body</p>")
    }

    @Test func missingRequiredFieldThrows() throws {
        // Missing `id` — should throw, not silently default
        let json = """
        {"title":{"rendered":"T"},"content":{"rendered":"C"},
         "excerpt":{"rendered":""},"status":"draft",
         "date":"2024-01-01T00:00:00","modified":"2024-01-01T00:00:00",
         "slug":"t","link":"https://example.com/t"}
        """
        #expect(throws: (any Error).self) { try decode(json) }
    }

    @Test func futureStatusDecodes() throws {
        let post = try decode(fullJSON.replacingOccurrences(of: "\"publish\"", with: "\"future\""))
        #expect(post.status == "future")
    }

    // When fetched via the list endpoint with _fields (no content/excerpt in payload),
    // decoding must succeed with empty defaults rather than throwing.
    // MARK: – Classic content wpautop

    @Test func classicContentGetsWpautop() throws {
        let json = """
        {"id":20,"title":{"rendered":"T"},
         "content":{"rendered":"<p>rendered</p>","raw":"Hello world\\n\\nSecond paragraph"},
         "excerpt":{"rendered":""},"status":"publish",
         "date":"2024-01-01T00:00:00","modified":"2024-01-01T00:00:00",
         "slug":"t","link":"https://example.com/t"}
        """
        let post = try decode(json)
        #expect(post.content.editorHTML == "<p>Hello world</p>\n\n<p>Second paragraph</p>")
    }

    @Test func classicContentSingleNewlineBecomesBr() throws {
        let json = """
        {"id":21,"title":{"rendered":"T"},
         "content":{"rendered":"<p>r</p>","raw":"Line one\\nLine two"},
         "excerpt":{"rendered":""},"status":"publish",
         "date":"2024-01-01T00:00:00","modified":"2024-01-01T00:00:00",
         "slug":"t","link":"https://example.com/t"}
        """
        let post = try decode(json)
        #expect(post.content.editorHTML == "<p>Line one<br />\nLine two</p>")
    }

    @Test func classicContentWithInlineHTML() throws {
        let json = """
        {"id":22,"title":{"rendered":"T"},
         "content":{"rendered":"<p>r</p>","raw":"Check out <a href=\\"http://example.com\\">this link</a> today\\n\\n<strong>Bold</strong> text"},
         "excerpt":{"rendered":""},"status":"publish",
         "date":"2024-01-01T00:00:00","modified":"2024-01-01T00:00:00",
         "slug":"t","link":"https://example.com/t"}
        """
        let post = try decode(json)
        let html = post.content.editorHTML
        #expect(html.contains("<p>Check out <a href=\"http://example.com\">this link</a> today</p>"))
        #expect(html.contains("<p><strong>Bold</strong> text</p>"))
    }

    @Test func classicContentBlockElementNotWrapped() throws {
        let json = """
        {"id":23,"title":{"rendered":"T"},
         "content":{"rendered":"<p>r</p>","raw":"Intro text\\n\\n<blockquote>A quote</blockquote>\\n\\nEnd"},
         "excerpt":{"rendered":""},"status":"publish",
         "date":"2024-01-01T00:00:00","modified":"2024-01-01T00:00:00",
         "slug":"t","link":"https://example.com/t"}
        """
        let post = try decode(json)
        let html = post.content.editorHTML
        #expect(html.contains("<p>Intro text</p>"))
        #expect(html.contains("<blockquote>A quote</blockquote>"))
        #expect(!html.contains("<p><blockquote>"))
        #expect(html.contains("<p>End</p>"))
    }

    @Test func gutenbergContentUnchanged() throws {
        let raw = "<!-- wp:paragraph -->\\n<p>Hello</p>\\n<!-- /wp:paragraph -->"
        let json = """
        {"id":24,"title":{"rendered":"T"},
         "content":{"rendered":"<p>Hello</p>","raw":"\(raw)"},
         "excerpt":{"rendered":""},"status":"publish",
         "date":"2024-01-01T00:00:00","modified":"2024-01-01T00:00:00",
         "slug":"t","link":"https://example.com/t"}
        """
        let post = try decode(json)
        #expect(post.content.editorHTML == post.content.raw)
    }

    @Test func contentWithParagraphTagsUnchanged() throws {
        let json = """
        {"id":25,"title":{"rendered":"T"},
         "content":{"rendered":"<p>r</p>","raw":"<p>Already wrapped</p>"},
         "excerpt":{"rendered":""},"status":"publish",
         "date":"2024-01-01T00:00:00","modified":"2024-01-01T00:00:00",
         "slug":"t","link":"https://example.com/t"}
        """
        let post = try decode(json)
        #expect(post.content.editorHTML == "<p>Already wrapped</p>")
    }

    @Test func classicContentShortcodePreserved() throws {
        let json = """
        {"id":26,"title":{"rendered":"T"},
         "content":{"rendered":"<div class='gallery'>...</div>","raw":"Check this gallery:\\n\\n[gallery ids=\\"1,2,3\\"]\\n\\nNeat!"},
         "excerpt":{"rendered":""},"status":"publish",
         "date":"2024-01-01T00:00:00","modified":"2024-01-01T00:00:00",
         "slug":"t","link":"https://example.com/t"}
        """
        let post = try decode(json)
        let html = post.content.editorHTML
        #expect(html.contains("<p>[gallery ids=\"1,2,3\"]</p>"))
        #expect(html.contains("<p>Neat!</p>"))
    }

    @Test func classicContentListNotCorrupted() throws {
        let json = """
        {"id":28,"title":{"rendered":"T"},
         "content":{"rendered":"<p>r</p>","raw":"Intro text\\r\\n<ul>\\r\\n\\t<li>Item A</li>\\r\\n\\t<li>Item B</li>\\r\\n</ul>\\r\\nEnd text"},
         "excerpt":{"rendered":""},"status":"publish",
         "date":"2024-01-01T00:00:00","modified":"2024-01-01T00:00:00",
         "slug":"t","link":"https://example.com/t"}
        """
        let post = try decode(json)
        let html = post.content.editorHTML
        #expect(html.contains("<p>Intro text</p>"))
        #expect(html.contains("<p>End text</p>"))
        #expect(!html.contains("<br"))
        #expect(html.contains("<li>Item A</li>"))
        #expect(html.contains("<li>Item B</li>"))
    }

    @Test func classicContentListWithAttributes() throws {
        let json = """
        {"id":29,"title":{"rendered":"T"},
         "content":{"rendered":"<p>r</p>","raw":"Before\\n<ol start=\\"3\\">\\n<li>First</li>\\n<li>Second</li>\\n</ol>\\nAfter"},
         "excerpt":{"rendered":""},"status":"publish",
         "date":"2024-01-01T00:00:00","modified":"2024-01-01T00:00:00",
         "slug":"t","link":"https://example.com/t"}
        """
        let post = try decode(json)
        let html = post.content.editorHTML
        #expect(html.contains("<p>Before</p>"))
        #expect(html.contains("<p>After</p>"))
        #expect(html.contains("<ol start=\"3\">"))
        #expect(!html.contains("<br"))
    }

    @Test func classicExcerptGetsWpautop() throws {
        let json = """
        {"id":27,"title":{"rendered":"T"},
         "content":{"rendered":"<p>body</p>","raw":"<p>body</p>"},
         "excerpt":{"rendered":"<p>Nice excerpt</p>","raw":"Nice excerpt"},
         "status":"publish",
         "date":"2024-01-01T00:00:00","modified":"2024-01-01T00:00:00",
         "slug":"t","link":"https://example.com/t"}
        """
        let post = try decode(json)
        #expect(post.excerpt.editorHTML == "<p>Nice excerpt</p>")
    }

    // When fetched via the list endpoint with _fields (no content/excerpt in payload),
    // decoding must succeed with empty defaults rather than throwing.
    @Test func missingContentAndExcerptDefaultToEmpty() throws {
        let json = """
        {"id":11,"type":"post",
         "title":{"rendered":"List Post","raw":"List Post"},
         "status":"publish","date":"2024-01-01T00:00:00",
         "date_gmt":"2024-01-01T00:00:00","modified":"2024-01-02T00:00:00",
         "slug":"list-post","link":"https://example.com/list-post",
         "featured_media":0,"categories":[],"tags":[],"parent":0,"comment_status":"open"}
        """
        let post = try decode(json)
        #expect(post.id == 11)
        #expect(post.content.rendered == "")
        #expect(post.content.raw == "")
        #expect(post.content.editorHTML == "")
        #expect(post.excerpt.rendered == "")
    }
}
