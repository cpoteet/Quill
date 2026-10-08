import Foundation
import Testing
@testable import QuillKit

@Suite struct AIPromptBuilderTests {

    // MARK: - Generate Post

    private static let today = ISO8601DateFormatter().date(from: "2026-10-07T12:00:00Z")!

    private func generated(_ html: String, title: String = "T", excerpt: String = "E") throws -> (title: String, excerpt: String, html: String) {
        let json = try JSONSerialization.data(withJSONObject: ["title": title, "excerpt": excerpt, "html": html])
        return try AIPromptBuilder.parseGenerated(String(data: json, encoding: .utf8)!)
    }

    @Test func generateSystemHasDateAndNoInventionRule() {
        let system = AIPromptBuilder.generateSystem(styleGuide: "Terse.", today: Self.today, webSearch: true)
        #expect(system.hasPrefix("You write blog post drafts for an author in Quill, a WordPress editor. Today's date is 2026-10-07."))
        #expect(system.contains("The author edits the draft and publishes it under their own name, so everything in it must be true of them, and you don't know their life. Don't write about what the author does, did, uses, tried, noticed or plans, and don't mention their work, clients or history, unless the description tells you about it. Give opinions as judgments about the subject (\"Templates should…\", \"The better choice is…\"), not as reports of the author's own habits or experience."))
        #expect(system.contains("Its quoted words and phrases show the author's habits; don't copy them, because a copied phrase reads as a tic."))
        #expect(system.contains("Your training data ends well before today's date."))
        #expect(system.hasSuffix("<style_guide>\nTerse.\n</style_guide>"))
    }

    @Test func withoutSearchOmitsSearchParagraphAndLinkSentence() {
        let system = AIPromptBuilder.generateSystem(styleGuide: "Terse.", today: Self.today, webSearch: false)
        #expect(!system.contains("Your training data ends"))
        #expect(system.contains("everything in it must be true of them"))
        let user = AIPromptBuilder.generatePrompt(description: "A post about Swift", webSearch: false)
        #expect(!user.contains("Link each fact"))
        #expect(user.contains("<description>\nA post about Swift\n</description>"))
        #expect(AIPromptBuilder.generatePrompt(description: "x", webSearch: true)
            .contains("Link each fact you took from a search to its source, with <a href=\"…\"> on the words it supports, the way the author links inline."))
    }

    @Test func generateSystemWithoutGuideOmitsTheVoiceParagraph() {
        let system = AIPromptBuilder.generateSystem(styleGuide: nil, today: Self.today, webSearch: true)
        #expect(!system.contains("style_guide") && !system.contains("following the style guide"))
        #expect(system.contains("Your training data ends"))
    }

    @Test func generatePromptNamesHTMLElementsAndJSONFields() {
        let prompt = AIPromptBuilder.generatePrompt(description: "x", webSearch: true)
        for tag in ["<h2>", "<h3>", "<p>", "<ul>", "<ol>", "<li>", "<blockquote>", "<table>", "<thead>", "<tbody>", "<tr>", "<th>", "<td>"] {
            #expect(prompt.contains(tag), "\(tag)")
        }
        #expect(prompt.contains("No other tags, no attributes except href, no styles and no Markdown."))
        #expect(prompt.hasSuffix(#"Put the title, as plain text, in "title"; one or two sentences for the post's excerpt in "excerpt"; and the body in "html"."#))
        let props = AIPromptBuilder.generateSchema["properties"] as! [String: Any]
        #expect(props.keys.sorted() == ["excerpt", "html", "title"])
        #expect(AIPromptBuilder.generateSchema["required"] as? [String] == ["title", "excerpt", "html"])
    }

    @Test func parseGeneratedReadsTheFields() throws {
        let result = try generated("<p>Body</p>\n", title: "  A Title ", excerpt: " Short. ")
        #expect(result.title == "A Title" && result.excerpt == "Short." && result.html == "<p>Body</p>")
    }

    @Test func parseGeneratedClosesSpaceBeforePunctuation() throws {
        #expect(try generated("<p>Honestly , they're fine . <a href=\"x\">Docs</a> ; more: yes ! Is it ?</p>").html
                == "<p>Honestly, they're fine. <a href=\"x\">Docs</a>; more: yes! Is it?</p>")
        #expect(try generated("<p>Use .NET and version 3 .5</p>").html == "<p>Use .NET and version 3 .5</p>")
    }

    @Test func parseGeneratedStripsCiteTagsAndNormalizesTables() throws {
        // Citations wrap sentences in <cite index="…">; the wrapper goes and the words stay, nested links included.
        #expect(try generated(#"<p>Water boils at 100C <cite index="1">according to NIST</cite>.</p>"#).html
                == "<p>Water boils at 100C according to NIST.</p>")
        #expect(try generated(#"<p>See <cite index="1">the <a href="https://nist.gov">NIST</a> page</cite>.</p>"#).html
                == #"<p>See the <a href="https://nist.gov">NIST</a> page.</p>"#)
        #expect(try generated(#"<p>Some fact<cite index="2"></cite>.</p>"#).html == "<p>Some fact.</p>")
        #expect(try generated(#"<table style="width:100%"><tr style="x"><td style="padding:1px" class="num">1</td></tr></table>"#).html
                == #"<table class="has-fixed-layout"><tr><td class="num">1</td></tr></table>"#)
    }

    @Test func parseGeneratedRejectsAnEmptyPostOrTruncatedJSON() {
        #expect(throws: (any Error).self) { _ = try self.generated("", title: "T") }
        #expect(throws: (any Error).self) { _ = try self.generated("<p>x</p>", title: " ") }
        #expect(throws: (any Error).self) { _ = try AIPromptBuilder.parseGenerated(#"{"title":"T","excerpt":"E","html":"<p>cut off"#) }
    }

    @Test func nonTableInlineStylesLeftAlone() {
        let input = #"<p style="color:red">x</p><span style="font-weight:bold">y</span>"#
        #expect(AIPromptBuilder.normalizeAITables(input) == input)
    }

    @Test func tableWithOwnClassKeepsIt() {
        let input = #"<table class="custom"><tr><td>x</td></tr></table>"#
        #expect(AIPromptBuilder.normalizeAITables(input) == input)
    }

    // cleanOperationResult is the right-click rewrite path. It used to be inline in
    // PostEditorView with no test; the fixtures exercise it as a whole, these pin
    // each step.
    @Test func cleanOperationResultTrims() {
        #expect(AIPromptBuilder.cleanOperationResult("\n<p>x</p>\n") == "<p>x</p>")
    }

    // The rewrite path must normalize tables too, or "To Table" produces exactly
    // the inline-styled markup the generate path was fixed to stop producing.
    @Test func cleanOperationResultNormalizesTables() {
        let raw = #"<table style="width:100%"><tr style="x"><td style="y">1</td></tr></table>"#
        #expect(AIPromptBuilder.cleanOperationResult(raw)
                == #"<table class="has-fixed-layout"><tr><td>1</td></tr></table>"#)
    }

    // Strip runs before the class check, so a table carrying both keeps its own
    // class and must not also collect has-fixed-layout.
    @Test func tableWithBothStyleAndClassKeepsOnlyTheClass() {
        #expect(AIPromptBuilder.normalizeAITables(#"<table class="custom" style="width:100%"><td>x</td></table>"#)
                == #"<table class="custom"><td>x</td></table>"#)
        #expect(AIPromptBuilder.normalizeAITables(#"<table style="width:100%" class="custom"><td>x</td></table>"#)
                == #"<table class="custom"><td>x</td></table>"#)
    }

    @Test func styleIsStrippedFromEveryTableTagIncludingCaptionAndFoot() {
        let input = #"<table style="a"><caption style="b">C</caption><tfoot style="c"><tr style="d"><td style="e">1</td></tr></tfoot></table>"#
        let out = AIPromptBuilder.normalizeAITables(input)
        #expect(!out.contains("style="))
        #expect(out == #"<table class="has-fixed-layout"><caption>C</caption><tfoot><tr><td>1</td></tr></tfoot></table>"#)
    }

    // Stripping must take the whole attribute and nothing else: the tag's other
    // attributes, and the cell text, stay put.
    @Test func strippingStyleLeavesTheOtherAttributesAndText() {
        #expect(AIPromptBuilder.normalizeAITables(#"<td colspan="2" style="p:1" scope="row">Cell &amp; more</td>"#)
                == #"<td colspan="2" scope="row">Cell &amp; more</td>"#)
    }

    @Test func singleQuotedStylesAreStrippedToo() {
        #expect(AIPromptBuilder.normalizeAITables("<tr style='border:1px'><td>x</td></tr>")
                == "<tr><td>x</td></tr>")
    }

    @Test func multipleTablesEachGetTheDefaultLayoutClass() {
        let out = AIPromptBuilder.normalizeAITables("<table><td>a</td></table><p>between</p><table><td>b</td></table>")
        #expect(out == #"<table class="has-fixed-layout"><td>a</td></table><p>between</p><table class="has-fixed-layout"><td>b</td></table>"#)
    }

    // MARK: - Style guide samples

    @Test func reduceSampleKeepsStructuralTagsWithoutAttributes() {
        let html = #"<h2 class="wp-block-heading" id="x">Why</h2><p class="a">See <a href="https://e.com" target="_blank">this</a> and <em>that</em>.</p><table class="t"><tr><th scope="col">H</th></tr><tr><td style="x">C</td></tr></table>"#
        #expect(AIPromptBuilder.reduceSample(html: html) == "<h2>Why</h2>\n<p>See <a>this</a> and <em>that</em>.</p>\n<table>\n<tr><th>H</th></tr>\n<tr><td>C</td></tr></table>")
    }

    @Test func reduceSampleTurnsImagesIntoMarkersAndKeepsCaptions() {
        let html = #"<figure class="wp-block-image"><img src="a.jpg" alt="x"/><figcaption class="c">The editor</figcaption></figure>"#
        #expect(AIPromptBuilder.reduceSample(html: html) == "[image]\n<figcaption>The editor</figcaption>")
    }

    @Test func reduceSampleRemovesOtherTagsButKeepsText() {
        #expect(AIPromptBuilder.reduceSample(html: #"<p>A <span class="x">b</span> <code>c</code></p>"#) == "<p>A b c</p>")
    }

    @Test func reduceSampleKeepsWordsApartAcrossBreaksAndRemovedBlocks() {
        #expect(AIPromptBuilder.reduceSample(html: "<div>one</div><div>two<br>three</div><pre>four</pre>") == "one\ntwo\nthree\nfour")
    }

    @Test func reduceSampleDropsEmptyElements() {
        #expect(AIPromptBuilder.reduceSample(html: "<p>a</p><p> </p><ul><li></li></ul>") == "<p>a</p>")
    }

    @Test func reduceSampleDecodesEntitiesButKeepsMarkupEncoded() {
        let html = "<p>It&#8217;s &ldquo;fine&rdquo; &#8212; write &lt;em&gt; &amp; &#038; go&hellip;&nbsp;now</p>"
        #expect(AIPromptBuilder.reduceSample(html: html) == "<p>It\u{2019}s \u{201C}fine\u{201D} \u{2014} write &lt;em&gt; &amp; &amp; go\u{2026} now</p>")
    }

    @Test func sampleHeaderHasTitleAndFormattedCount() {
        #expect(AIPromptBuilder.sampleHeader(index: 1, title: "Building a WordPress Editor", words: 1093) == "--- Sample 1: Building a WordPress Editor (1,093 words) ---")
    }

    @Test func styleGuidePromptHasTheEightLabelsInOrder() {
        let prompt = AIPromptBuilder.styleGuideGenerationPrompt(samples: [])
        let labels = ["Voice and tone:", "Sentence rhythm:", "Vocabulary:", "Humor and personality:",
                      "Openings and closings:", "Structure and length:", "Formatting:", "Avoid:"]
        let positions = labels.map { prompt.range(of: "\n\($0)\n")?.lowerBound }
        #expect(positions.allSatisfy { $0 != nil })
        #expect(positions.compactMap { $0 } == positions.compactMap { $0 }.sorted())
        #expect(prompt.contains("Aim for about 500 words."))
        #expect(prompt.contains("headings, paragraphs, lists, tables, block quotes"))
    }

    @Test func styleGuidePromptNumbersSamplesWithTitleAndCount() {
        let prompt = AIPromptBuilder.styleGuideGenerationPrompt(samples: [
            (title: "First &amp; best", html: "<p>One two &lt;em&gt;</p>"),
            (title: "Second", html: "<p>Three</p>"),
        ])
        #expect(prompt.hasSuffix("""
        --- Sample 1: First & best (3 words) ---
        <p>One two &lt;em&gt;</p>

        --- Sample 2: Second (1 words) ---
        <p>Three</p>
        """))
        #expect(prompt.contains("after the Avoid section.\n\n--- Sample 1"))
    }

}
