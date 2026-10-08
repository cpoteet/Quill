import Foundation
import Testing
@testable import QuillKit

@Suite struct EvaluationPromptsTests {

    private static let noon = ISO8601DateFormatter().date(from: "2023-11-13T12:00:00Z")!
    private static let today = ISO8601DateFormatter().date(from: "2026-10-07T12:00:00Z")!

    // MARK: - postText

    @Test func postTextMarksStructure() {
        let html = "<h2>A</h2><p>b</p><ul><li>c</li></ul><figure><img><figcaption>d</figcaption></figure><table><tr><td>e</td><td>f</td></tr></table>"
        #expect(EvaluationPrompts.postText(html: html) == "## A\n\nb\n\n- c\n\n[Caption] d\n\n| e | f |")
    }

    @Test func postTextHeadingLevelsAndTableRows() {
        let html = "<h3>Sub</h3><table><thead><tr><th>Year</th><th>Posts</th></tr></thead><tbody><tr><td>2006</td><td></td></tr></tbody></table><p>After</p>"
        #expect(EvaluationPrompts.postText(html: html) == "### Sub\n\n| Year | Posts |\n| 2006 | |\n\nAfter")
    }

    @Test func postTextMarksFootnotes() {
        let html = ##"<p>Body<sup data-fn="x" class="fn" id="x-link"><a href="#x">1</a></sup>.</p><ol class="wp-block-footnotes"><li id="x">A <em>note</em>. <a href="#x-link" class="footnote-backref">↩︎</a></li></ol>"##
        #expect(EvaluationPrompts.postText(html: html) == "Body.\n\n[Footnote] A note.")
    }

    @Test func postTextLeavesOutCodeAndEmbeds() {
        let html = #"<p>a</p><pre class="wp-block-code"><code>let x</code></pre><figure class="wp-block-embed is-type-video"><div class="wp-block-embed__wrapper">https://youtu.be/x</div></figure><p>b</p>"#
        #expect(EvaluationPrompts.postText(html: html) == "a\n\nb")
    }

    @Test func postTextKeepsNonBreakingSpacesAsTheEditorDoes() {
        let html = "<p>This is one.&nbsp; This\n   are&nbsp;wrong.</p>"
        #expect(EvaluationPrompts.postText(html: html) == "This is one.  This are wrong.")
    }

    @Test func postTextLeavesOutScriptsAndStyles() {
        let html = #"<p>a</p><!-- wp:html --><style>.x { color: red }</style><script>let y = 1</script><!-- /wp:html --><p>b</p>"#
        #expect(EvaluationPrompts.postText(html: html) == "a\n\nb")
    }

    @Test func postTextJoinsInlineElementsWithoutPhantomSpaces() {
        let html = ##"<p><a href="#">DSPM</a>, <a href="#">Content</a> (<a href="#">ref</a>) word<em>s</em> it&#8217;s &amp; more</p>"##
        #expect(EvaluationPrompts.postText(html: html) == "DSPM, Content (ref) words it\u{2019}s & more")
    }

    @Test func postTextKeepsTheAuthorsOwnSpaceBeforePunctuation() {
        #expect(EvaluationPrompts.postText(html: "<p>one , two</p>") == "one , two")
    }

    @Test func appendingFootnotesBuildsTheList() {
        let html = EvaluationPrompts.appendingFootnotes(to: "<p>a</p>", meta: #"[{"id":"x","content":"The <em>note</em>."}]"#)
        #expect(EvaluationPrompts.postText(html: html) == "a\n\n[Footnote] The note.")
        #expect(EvaluationPrompts.appendingFootnotes(to: "<p>a</p>", meta: "[]") == "<p>a</p>")
        #expect(EvaluationPrompts.appendingFootnotes(to: "<p>a</p>", meta: "") == "<p>a</p>")
    }

    @Test func postTextMatchesEditorText() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Scripts/fixtures/evaluate")
        let html = try String(contentsOf: dir.appendingPathComponent("post.html"), encoding: .utf8)
        let meta = try String(contentsOf: dir.appendingPathComponent("post.footnotes.json"), encoding: .utf8)
        let editorText = try String(contentsOf: dir.appendingPathComponent("post.editor-text.txt"), encoding: .utf8)
        let text = EvaluationPrompts.postText(html: EvaluationPrompts.appendingFootnotes(to: html, meta: meta))
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 12)
        for line in lines {
            let unmarked = line.replacingOccurrences(of: #"^(#{1,6} |- |\[Caption\] |\[Footnote\] )"#, with: "", options: .regularExpression)
            let pieces = unmarked.hasPrefix("| ")
                ? unmarked.dropFirst(2).dropLast(2).components(separatedBy: " | ")
                : [unmarked]
            for piece in pieces where !piece.isEmpty {
                #expect(editorText.contains(piece), "not in the editor's text: \(piece)")
            }
        }
    }

    // MARK: - Prompts

    @Test func reviewSystemHasDateAndGuide() {
        let system = EvaluationPrompts.reviewSystem(styleGuide: "Terse.", today: Self.today)
        #expect(system.hasPrefix("You are an experienced editor reviewing a blog post for its author in Quill, a WordPress editor. Today's date is 2026-10-07. Write to the author as \"you\"."))
        #expect(system.contains("never suggest adding tables, footnotes, lists, asides or any other feature because the guide mentions it."))
        #expect(system.hasSuffix("<style_guide>\nTerse.\n</style_guide>"))
    }

    @Test func reviewSystemOmitsGuideParagraphWithoutGuide() {
        for guide in [nil, ""] as [String?] {
            let system = EvaluationPrompts.reviewSystem(styleGuide: guide, today: Self.today)
            #expect(system == "You are an experienced editor reviewing a blog post for its author in Quill, a WordPress editor. Today's date is 2026-10-07. Write to the author as \"you\".")
        }
    }

    @Test func reviewPromptHasDateAndPublishLine() {
        let published = EvaluationPrompts.review(title: "T", html: "<p>Body</p>", publishedOn: Self.noon)
        #expect(published.contains("<post>\nTitle: T\nPublished: 2023-11-13\n\nBody\n</post>"))
        let draft = EvaluationPrompts.review(title: "T", html: "<p>Body</p>", publishedOn: nil)
        #expect(draft.contains("Title: T\nStatus: draft, not yet published\n\nBody"))
        #expect(draft.hasPrefix("Review this post and report what would make it better. It is shown as plain text: \"## \" marks a heading"))
        #expect(draft.contains("Someone else is checking facts, so don't judge whether claims are true."))
        #expect(draft.hasSuffix("If the fix is to delete the text, \"replacement\" is an empty string."))
    }

    @Test func factCheckPromptsCarryDateAndSearchLimit() {
        let system = EvaluationPrompts.factCheckSystem(today: Self.today)
        #expect(system.contains("Today's date is 2026-10-07."))
        #expect(system.hasSuffix("so search for those before you judge them, even when you feel sure."))
        let user = EvaluationPrompts.factCheck(title: "T", html: "<p>Body</p>", publishedOn: nil)
        #expect(user.hasPrefix("Fact-check this post. It is shown as plain text:"))
        #expect(user.contains("Search at most 8 times."))
        #expect(user.contains("\"wrong\", \"outdated\", \"needs qualifier\" or \"not checked\""))
        #expect(user.contains("For each one, \"original\" is the exact text it applies to, copied character for character from the post (without the markers)"))
        #expect(user.hasSuffix("or an empty string if the author should decide how to fix it."))
    }

    @Test func reviewSchemaListsTheCategories() throws {
        let props = EvaluationPrompts.reviewSchema["properties"] as! [String: Any]
        func categories(_ key: String) -> [String] {
            let items = (props[key] as! [String: Any])["items"] as! [String: Any]
            return ((items["properties"] as! [String: Any])["category"] as! [String: Any])["enum"] as! [String]
        }
        #expect(categories("corrections") == ["Spelling", "Grammar", "Punctuation", "Word choice", "Consistency"])
        #expect(categories("suggestions") == ["Clarity", "Concision", "Flow", "Repetition", "Voice", "Structure"])
        #expect(EvaluationPrompts.reviewSchema["additionalProperties"] as? Bool == false)
        _ = try JSONSerialization.data(withJSONObject: EvaluationPrompts.reviewSchema)
        _ = try JSONSerialization.data(withJSONObject: EvaluationPrompts.factCheckSchema)
    }

    // MARK: - Parsing

    @Test func parseReviewDropsNoOpItems() throws {
        let json = #"""
        {"review":{"strengths":"Warm.","priorities":["Retitle.","Cut the intro."]},
         "corrections":[{"category":"Spelling","original":"feel off","replacement":"fell off","explanation":"Past tense."},
                        {"category":"Grammar","original":"same","replacement":"same","explanation":"No-op."}],
         "suggestions":[{"category":"Concision","original":"a b c","replacement":"","explanation":"Cut."}]}
        """#
        let result = try EvaluationPrompts.parseReview(json)
        #expect(result.review.strengths == "Warm." && result.review.priorities == ["Retitle.", "Cut the intro."])
        #expect(result.corrections.map(\.original) == ["feel off"])
        #expect(result.corrections.first?.kind == .correction)
        #expect(result.suggestions.map(\.replacement) == [""])
        #expect(result.suggestions.first?.kind == .suggestion)
        #expect(result.corrections[0].id != result.suggestions[0].id)
    }

    @Test func parseFactCheckCountsClaims() throws {
        let json = #"""
        {"claims":[{"claim":"a","verdict":"confirmed"},{"claim":"b","verdict":"outdated"},{"claim":"c","verdict":"not checked"}],
         "fact_checks":[{"original":"Viva Topics","explanation":"Retired.","source_quote":"Viva Topics is retired.","source_url":"https://learn.microsoft.com/x","replacement":""}]}
        """#
        let result = try EvaluationPrompts.parseFactCheck(json)
        #expect(result.claimsChecked == 3)
        #expect(result.checks.count == 1)
        #expect(result.checks[0].sourceQuote == "Viva Topics is retired." && result.checks[0].sourceURL == "https://learn.microsoft.com/x")
    }

    @Test func parseReviewRejectsMalformedJSON() {
        #expect(throws: (any Error).self) { _ = try EvaluationPrompts.parseReview("not json") }
    }
}
