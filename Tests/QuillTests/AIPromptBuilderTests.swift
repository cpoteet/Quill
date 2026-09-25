import Foundation
import Testing
@testable import QuillKit

@Suite struct AIPromptBuilderTests {

    // MARK: - parseGenerateResponse

    @Test func happyPathParsesCorrectly() {
        let input = "TITLE: My Post\n\nCONTENT:\n<p>Hello</p>"
        let result = AIPromptBuilder.parseGenerateResponse(input)
        #expect(result?.title == "My Post")
        #expect(result?.html == "<p>Hello</p>")
    }

    @Test func markdownFencesStripped() {
        let input = "```html\nTITLE: Fenced\n\nCONTENT:\n<p>Body</p>\n```"
        let result = AIPromptBuilder.parseGenerateResponse(input)
        #expect(result?.title == "Fenced")
        #expect(result?.html.contains("<p>Body</p>") == true)
    }

    @Test func webSearchPreambleGluedDirectlyToTitle() {
        // When web search is on, Claude emits a preamble block joined without a newline
        let input = "I'll search for information about this.TITLE: Real Title\n\nCONTENT:\n<p>Body</p>"
        let result = AIPromptBuilder.parseGenerateResponse(input)
        #expect(result?.title == "Real Title")
        #expect(result?.html.contains("<p>Body</p>") == true)
    }

    @Test func caseInsensitiveMarkers() {
        let input = "title: Lowercase\n\ncontent:\n<p>x</p>"
        let result = AIPromptBuilder.parseGenerateResponse(input)
        #expect(result?.title == "Lowercase")
        #expect(result?.html.contains("<p>x</p>") == true)
    }

    @Test func missingTitleMarkerReturnsNil() {
        let input = "CONTENT:\n<p>No title marker</p>"
        #expect(AIPromptBuilder.parseGenerateResponse(input) == nil)
    }

    @Test func missingContentMarkerReturnsNil() {
        let input = "TITLE: A Title with no content marker"
        #expect(AIPromptBuilder.parseGenerateResponse(input) == nil)
    }

    @Test func emptyTitleReturnsNil() {
        let input = "TITLE:\n\nCONTENT:\n<p>Body</p>"
        #expect(AIPromptBuilder.parseGenerateResponse(input) == nil)
    }

    @Test func emptyContentReturnsNil() {
        let input = "TITLE: A Title\n\nCONTENT:\n"
        #expect(AIPromptBuilder.parseGenerateResponse(input) == nil)
    }

    @Test func titleIsTrimmed() {
        let input = "TITLE:   Padded Title   \n\nCONTENT:\n<p>x</p>"
        let result = AIPromptBuilder.parseGenerateResponse(input)
        #expect(result?.title == "Padded Title")
    }

    @Test func contentIsTrimmerd() {
        let input = "TITLE: T\n\nCONTENT:\n\n\n<p>x</p>\n\n"
        let result = AIPromptBuilder.parseGenerateResponse(input)
        #expect(result?.html == "<p>x</p>")
    }

    @Test func contentMarkerScopedAfterTitleMarker() {
        // A stray CONTENT: before TITLE: should not fool the parser
        let input = "CONTENT: junk TITLE: Real\n\nCONTENT:\n<p>body</p>"
        let result = AIPromptBuilder.parseGenerateResponse(input)
        #expect(result?.title == "Real")
        #expect(result?.html.contains("<p>body</p>") == true)
    }

    @Test func tableInlineStylesStripped() {
        let input = """
        TITLE: T

        CONTENT:
        <table style="border-collapse:collapse; width:100%;"><thead><tr style="background-color:#f2f2f2;"><th style="padding:10px; text-align:left;">Year</th></tr></thead><tbody><tr style='border:1px solid #ddd;'><td style="padding:10px;" class="num">2030</td></tr></tbody></table>
        """
        let html = AIPromptBuilder.parseGenerateResponse(input)?.html
        #expect(html == #"<table class="has-fixed-layout"><thead><tr><th>Year</th></tr></thead><tbody><tr><td class="num">2030</td></tr></tbody></table>"#)
    }

    @Test func nonTableInlineStylesLeftAlone() {
        let input = #"<p style="color:red">x</p><span style="font-weight:bold">y</span>"#
        #expect(AIPromptBuilder.normalizeAITables(input) == input)
    }

    @Test func tableWithOwnClassKeepsIt() {
        let input = #"<table class="custom"><tr><td>x</td></tr></table>"#
        #expect(AIPromptBuilder.normalizeAITables(input) == input)
    }

    @Test func generatePromptForbidsInlineStyles() {
        let prompt = AIPromptBuilder.generatePostPrompt(userPrompt: "x")
        #expect(prompt.contains("<table>"))
        #expect(prompt.contains("style attributes"))
    }

    // cleanOperationResult is the right-click rewrite path. It used to be inline in
    // PostEditorView with no test; the fixtures exercise it as a whole, these pin
    // each step.
    @Test func cleanOperationResultStripsFencesAndTrims() {
        let raw = "```html\n<p>Rewritten.</p>\n```\n"
        #expect(AIPromptBuilder.cleanOperationResult(raw) == "<p>Rewritten.</p>")
    }

    @Test func cleanOperationResultStripsABareFence() {
        #expect(AIPromptBuilder.cleanOperationResult("```\n<p>x</p>\n```") == "<p>x</p>")
    }

    @Test func cleanOperationResultLeavesUnfencedHTMLAlone() {
        #expect(AIPromptBuilder.cleanOperationResult("<p>x</p>") == "<p>x</p>")
    }

    // The rewrite path must normalize tables too, or "To Table" produces exactly
    // the inline-styled markup the generate path was fixed to stop producing.
    @Test func cleanOperationResultNormalizesTables() {
        let raw = "```html\n" + #"<table style="width:100%"><tr style="x"><td style="y">1</td></tr></table>"# + "\n```"
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

    @Test func citeTagWrapperStrippedButTextKept() {
        // Web search citations wrap sentences in <cite index="..."> — the wrapper must be
        // removed but the sentence itself must survive in the generated post.
        let input = "TITLE: T\n\nCONTENT:\n<p>Water boils at 100C<cite index=\"1\">according to NIST</cite>.</p>"
        let result = AIPromptBuilder.parseGenerateResponse(input)
        #expect(result?.html.contains("<cite") == false)
        #expect(result?.html.contains("according to NIST") == true)
    }

    @Test func citeTagWithNestedInlineTagStillStripped() {
        // A citation wrapping a nested inline tag (e.g. a link) must still be stripped —
        // a `[^<]*` capture group would fail to match here and leave the wrapper in place.
        let input = "TITLE: T\n\nCONTENT:\n<p>See <cite index=\"1\">the <a href=\"https://nist.gov\">NIST</a> page</cite> for details.</p>"
        let result = AIPromptBuilder.parseGenerateResponse(input)
        #expect(result?.html.contains("<cite") == false)
        #expect(result?.html.contains("<a href=\"https://nist.gov\">NIST</a>") == true)
    }

    @Test func emptyCiteTagRemovedEntirely() {
        let input = "TITLE: T\n\nCONTENT:\n<p>Some fact<cite index=\"2\"></cite>.</p>"
        let result = AIPromptBuilder.parseGenerateResponse(input)
        #expect(result?.html.contains("<cite") == false)
        #expect(result?.html == "<p>Some fact.</p>")
    }

    // MARK: - systemPrompt

    @Test func systemPromptWithoutStyleGuide() {
        let prompt = AIPromptBuilder.systemPrompt(styleGuide: nil)
        #expect(prompt.contains("WordPress editor"))
        #expect(!prompt.contains("author's style"))
    }

    @Test func systemPromptWithEmptyStyleGuideExcludesStyleBlock() {
        let prompt = AIPromptBuilder.systemPrompt(styleGuide: "")
        #expect(!prompt.contains("author's style"))
    }

    @Test func systemPromptWithStyleGuideIncludesIt() {
        let prompt = AIPromptBuilder.systemPrompt(styleGuide: "Terse and direct.")
        #expect(prompt.contains("Terse and direct."))
        #expect(prompt.contains("author's style"))
    }

    // MARK: - generatePostPrompt

    @Test func generatePostPromptNamesHTMLElements() {
        // Vague prompts caused Claude to omit headings — the prompt must name elements
        let prompt = AIPromptBuilder.generatePostPrompt(userPrompt: "test")
        #expect(prompt.contains("<h2>"))
        #expect(prompt.contains("<h3>"))
        #expect(prompt.contains("<p>"))
        #expect(prompt.contains("<ul>"))
        #expect(prompt.contains("<li>"))
    }

    @Test func generatePostPromptIncludesUserPrompt() {
        let prompt = AIPromptBuilder.generatePostPrompt(userPrompt: "a post about Swift")
        #expect(prompt.contains("a post about Swift"))
    }

    // MARK: - operationPrompt

    @Test func operationPromptIncludesSelectedHTML() {
        let html = "<p>Some text</p>"
        let prompt = AIPromptBuilder.operationPrompt(selectedHTML: html, operation: .makeLonger)
        #expect(prompt.contains(html))
    }

    @Test func makeLongerInstructionPresent() {
        let prompt = AIPromptBuilder.operationPrompt(selectedHTML: "x", operation: .makeLonger)
        #expect(prompt.lowercased().contains("expand") || prompt.lowercased().contains("longer"))
    }

    @Test func makeLongerStatesWordTargetFromSelection() {
        let prompt = AIPromptBuilder.operationPrompt(selectedHTML: "one two three four five", operation: .makeLonger)
        #expect(prompt.contains("from 5 words to about 20 words"))
        #expect(prompt.contains("never more than 25"))
        #expect(prompt.contains("same number of paragraphs"))
    }

    @Test func makeLongerScalesDownForLongerSelections() {
        let paragraph = AIPromptBuilder.operationPrompt(selectedHTML: words(100), operation: .makeLonger)
        #expect(paragraph.contains("to about 200 words, and never more than 250"))
        let long = AIPromptBuilder.operationPrompt(selectedHTML: words(200), operation: .makeLonger)
        #expect(long.contains("to about 300 words, and never more than 400"))
    }

    @Test func makeShorterScalesUpForLongerSelections() {
        let sentence = AIPromptBuilder.operationPrompt(selectedHTML: words(10), operation: .makeShorter)
        #expect(sentence.contains("from 10 words to about 7 words, and never more than 8"))
        let paragraph = AIPromptBuilder.operationPrompt(selectedHTML: words(100), operation: .makeShorter)
        #expect(paragraph.contains("to about 50 words, and never more than 60"))
        let long = AIPromptBuilder.operationPrompt(selectedHTML: words(200), operation: .makeShorter)
        #expect(long.contains("to about 80 words, and never more than 100"))
        #expect(long.contains("same number of paragraphs"))
    }

    @Test func lengthTiersSwitchAtFortyAndAfterOneHundredFiftyWords() {
        #expect(AIPromptBuilder.operationPrompt(selectedHTML: words(39), operation: .makeLonger)
            .contains("from 39 words to about 156 words, and never more than 195"))
        #expect(AIPromptBuilder.operationPrompt(selectedHTML: words(40), operation: .makeLonger)
            .contains("from 40 words to about 80 words, and never more than 100"))
        #expect(AIPromptBuilder.operationPrompt(selectedHTML: words(150), operation: .makeLonger)
            .contains("from 150 words to about 300 words, and never more than 375"))
        #expect(AIPromptBuilder.operationPrompt(selectedHTML: words(151), operation: .makeLonger)
            .contains("from 151 words to about 227 words, and never more than 302"))
        #expect(AIPromptBuilder.operationPrompt(selectedHTML: words(39), operation: .makeShorter)
            .contains("from 39 words to about 27 words, and never more than 31"))
        #expect(AIPromptBuilder.operationPrompt(selectedHTML: words(40), operation: .makeShorter)
            .contains("from 40 words to about 20 words, and never more than 24"))
        #expect(AIPromptBuilder.operationPrompt(selectedHTML: words(150), operation: .makeShorter)
            .contains("from 150 words to about 75 words, and never more than 90"))
        #expect(AIPromptBuilder.operationPrompt(selectedHTML: words(151), operation: .makeShorter)
            .contains("from 151 words to about 60 words, and never more than 76"))
    }

    @Test func makeShorterNeverTargetsZeroWords() {
        let prompt = AIPromptBuilder.operationPrompt(selectedHTML: "Extraordinarily", operation: .makeShorter)
        #expect(prompt.contains("to about 1 words, and never more than 1"))
    }

    @Test func wordTargetCountsWordsAcrossParagraphBreaks() {
        let prompt = AIPromptBuilder.operationPrompt(selectedHTML: "One two\nthree\n\nfour", operation: .makeLonger)
        #expect(prompt.contains("from 4 words to about 16 words"))
    }

    @Test func listAndTableContextsGetNoWordTarget() {
        for context in ["bulletList", "orderedList", "table"] {
            for operation in [AIWritingOperation.makeLonger, .makeShorter] {
                let prompt = AIPromptBuilder.operationPrompt(selectedHTML: words(20), operation: operation, context: context)
                #expect(!prompt.contains("words to about"), "\(context) \(operation)")
            }
        }
    }

    private func words(_ count: Int) -> String {
        Array(repeating: "word", count: count).joined(separator: " ")
    }

    @Test func makeShorterInstructionPresent() {
        let prompt = AIPromptBuilder.operationPrompt(selectedHTML: "x", operation: .makeShorter)
        #expect(prompt.lowercased().contains("condense") || prompt.lowercased().contains("shorter"))
    }

    @Test func convertToTableMentionsTableTags() {
        let prompt = AIPromptBuilder.operationPrompt(selectedHTML: "x", operation: .convertToTable)
        #expect(prompt.contains("<table>"))
    }

    @Test func convertToListMentionsListTags() {
        let prompt = AIPromptBuilder.operationPrompt(selectedHTML: "x", operation: .convertToList)
        #expect(prompt.contains("<ul>") && prompt.contains("<li>"))
    }

    @Test func makeLongerWithBulletListContextUsesUlTag() {
        let prompt = AIPromptBuilder.operationPrompt(selectedHTML: "items", operation: .makeLonger, context: "bulletList")
        #expect(prompt.lowercased().contains("list item"))
        #expect(prompt.contains("<ul>"))
    }

    @Test func makeLongerWithOrderedListContextUsesOlTag() {
        let prompt = AIPromptBuilder.operationPrompt(selectedHTML: "items", operation: .makeLonger, context: "orderedList")
        #expect(prompt.lowercased().contains("list item"))
        #expect(prompt.contains("<ol>"))
        #expect(!prompt.contains("<ul>"))
    }

    @Test func makeShorterWithOrderedListContextUsesOlTag() {
        let prompt = AIPromptBuilder.operationPrompt(selectedHTML: "items", operation: .makeShorter, context: "orderedList")
        #expect(prompt.lowercased().contains("list item"))
        #expect(prompt.contains("<ol>"))
    }

    @Test func makeShorterWithBulletListContextUsesUlTag() {
        let prompt = AIPromptBuilder.operationPrompt(selectedHTML: "items", operation: .makeShorter, context: "bulletList")
        #expect(prompt.lowercased().contains("list item"))
        #expect(prompt.contains("<ul>"))
    }

    @Test func makeLongerWithTableContextUsesTableInstruction() {
        let prompt = AIPromptBuilder.operationPrompt(selectedHTML: "cells", operation: .makeLonger, context: "table")
        #expect(prompt.lowercased().contains("table cell") || prompt.lowercased().contains("table structure"))
    }

    @Test func makeShorterWithTableContextUsesTableInstruction() {
        let prompt = AIPromptBuilder.operationPrompt(selectedHTML: "cells", operation: .makeShorter, context: "table")
        #expect(prompt.lowercased().contains("table cell") || prompt.lowercased().contains("table structure"))
    }

    @Test func operationPromptWithNilContextUsesDefaultInstruction() {
        let prompt = AIPromptBuilder.operationPrompt(selectedHTML: "text", operation: .makeLonger, context: nil)
        #expect(prompt.lowercased().contains("expand this content"))
    }

    // MARK: - styleGuideGenerationPrompt

    @Test func styleGuidePromptNumbersSamples() {
        let prompt = AIPromptBuilder.styleGuideGenerationPrompt(
            sampleContents: ["First post", "Second post"])
        #expect(prompt.contains("Sample 1"))
        #expect(prompt.contains("Sample 2"))
        #expect(prompt.contains("First post"))
        #expect(prompt.contains("Second post"))
    }

    @Test func styleGuidePromptWithEmptySamples() {
        let prompt = AIPromptBuilder.styleGuideGenerationPrompt(sampleContents: [])
        // Should not crash; prompt still formed
        #expect(prompt.contains("style guide"))
    }

    @Test func styleGuidePromptWordLimit() {
        let prompt = AIPromptBuilder.styleGuideGenerationPrompt(sampleContents: ["x"])
        #expect(prompt.contains("150 words"))
    }
}

// MARK: - EvaluationResult / parseEvaluationResponse

@Suite struct EvaluationParserTests {

    @Test func happyPathTwoFindings() {
        let input = """
        SUMMARY:
        Clear writing overall. A few passive constructions drag it down.

        FINDINGS:
        QUOTE: "was completed by the team" | ISSUE: Passive Voice | SUGGESTION: the team completed
        QUOTE: "in order to achieve" | ISSUE: Wordiness
        """
        let result = AIPromptBuilder.parseEvaluationResponse(input)
        #expect(result?.summary == "Clear writing overall. A few passive constructions drag it down.")
        #expect(result?.findings.count == 2)
        #expect(result?.findings[0].quote == "was completed by the team")
        #expect(result?.findings[0].issue == "Passive Voice")
        #expect(result?.findings[0].suggestion == "the team completed")
        #expect(result?.findings[1].quote == "in order to achieve")
        #expect(result?.findings[1].issue == "Wordiness")
        #expect(result?.findings[1].suggestion == nil)
    }

    @Test func emptyFindingsReturnsResultWithNoFindings() {
        let input = """
        SUMMARY:
        Well-written post with no significant issues.

        FINDINGS:
        """
        let result = AIPromptBuilder.parseEvaluationResponse(input)
        #expect(result != nil)
        #expect(result?.summary == "Well-written post with no significant issues.")
        #expect(result?.findings.isEmpty == true)
    }

    @Test func missingSummaryMarkerReturnsNil() {
        let input = "FINDINGS:\nQUOTE: \"text\" | ISSUE: Clarity"
        #expect(AIPromptBuilder.parseEvaluationResponse(input) == nil)
    }

    @Test func missingFindingsMarkerReturnsNil() {
        let input = "SUMMARY:\nGood post."
        #expect(AIPromptBuilder.parseEvaluationResponse(input) == nil)
    }

    @Test func emptySummaryReturnsNil() {
        let input = "SUMMARY:\n\nFINDINGS:\n"
        #expect(AIPromptBuilder.parseEvaluationResponse(input) == nil)
    }

    @Test func caseInsensitiveMarkers() {
        let input = "summary:\nGood draft.\n\nfindings:\n"
        let result = AIPromptBuilder.parseEvaluationResponse(input)
        #expect(result?.summary == "Good draft.")
        #expect(result?.findings.isEmpty == true)
    }

    @Test func findingWithoutSuggestionHasNilSuggestion() {
        let input = """
        SUMMARY:
        Decent draft.

        FINDINGS:
        QUOTE: "some phrase" | ISSUE: Clarity
        """
        let result = AIPromptBuilder.parseEvaluationResponse(input)
        #expect(result?.findings.first?.suggestion == nil)
    }

    @Test func findingWithEmptySuggestionFieldHasNilSuggestion() {
        let input = """
        SUMMARY:
        Decent draft.

        FINDINGS:
        QUOTE: "some phrase" | ISSUE: Clarity | SUGGESTION:
        """
        let result = AIPromptBuilder.parseEvaluationResponse(input)
        #expect(result?.findings.first?.suggestion == nil)
    }

    @Test func nonQuoteLinesBetweenFindingsAreSkipped() {
        let input = """
        SUMMARY:
        Good post.

        FINDINGS:
        Here are the issues I found:
        QUOTE: "a phrase" | ISSUE: Grammar
        """
        let result = AIPromptBuilder.parseEvaluationResponse(input)
        #expect(result?.findings.count == 1)
        #expect(result?.findings.first?.quote == "a phrase")
    }

    @Test func findingsMarkerScopedAfterSummaryMarker() {
        // Stray FINDINGS: before SUMMARY: should not confuse the parser
        let input = "FINDINGS: junk SUMMARY:\nReal summary.\n\nFINDINGS:\n"
        let result = AIPromptBuilder.parseEvaluationResponse(input)
        #expect(result?.summary == "Real summary.")
    }

    @Test func anchorFieldIsParsedIntoFinding() {
        let input = """
        SUMMARY:
        A solid draft with a few issues.

        FINDINGS:
        QUOTE: "was completed by the team" | ANCHOR: "completed by the" | ISSUE: Passive Voice | SUGGESTION: the team completed
        """
        let result = AIPromptBuilder.parseEvaluationResponse(input)
        #expect(result?.findings.count == 1)
        #expect(result?.findings[0].anchor == "completed by the")
        #expect(result?.findings[0].quote == "was completed by the team")
        #expect(result?.findings[0].issue == "Passive Voice")
        #expect(result?.findings[0].suggestion == "the team completed")
    }

    @Test func anchorFieldIsNilWhenOmitted() {
        let input = """
        SUMMARY:
        Good draft.

        FINDINGS:
        QUOTE: "in order to achieve" | ISSUE: Wordiness
        """
        let result = AIPromptBuilder.parseEvaluationResponse(input)
        #expect(result?.findings.first?.anchor == nil)
    }

    @Test func anchorFieldStripsOuterQuotes() {
        let input = """
        SUMMARY:
        Fine post.

        FINDINGS:
        QUOTE: "some longer phrase here" | ANCHOR: "some phrase" | ISSUE: Clarity
        """
        let result = AIPromptBuilder.parseEvaluationResponse(input)
        // Surrounding quote marks are stripped; the literal text is preserved
        #expect(result?.findings.first?.anchor == "some phrase")
    }

    @Test func anchorFieldEmptyStringBecomesNil() {
        let input = """
        SUMMARY:
        Fine post.

        FINDINGS:
        QUOTE: "some phrase" | ANCHOR: "" | ISSUE: Clarity
        """
        let result = AIPromptBuilder.parseEvaluationResponse(input)
        #expect(result?.findings.first?.anchor == nil)
    }

    @Test func anchorFieldCaseInsensitivePrefix() {
        let input = """
        SUMMARY:
        Fine post.

        FINDINGS:
        QUOTE: "phrase" | anchor: "the phrase" | ISSUE: Clarity
        """
        let result = AIPromptBuilder.parseEvaluationResponse(input)
        #expect(result?.findings.first?.anchor == "the phrase")
    }
}

// MARK: - evaluatePostPrompt

@Suite struct EvaluatePostPromptTests {

    @Test func promptIncludesTitle() {
        let prompt = AIPromptBuilder.evaluatePostPrompt(title: "My Article", html: "<p>Body.</p>", styleGuide: nil)
        #expect(prompt.contains("My Article"))
    }

    @Test func promptStripsHTMLTags() {
        let prompt = AIPromptBuilder.evaluatePostPrompt(title: "T", html: "<p>Hello <strong>world</strong></p>", styleGuide: nil)
        #expect(!prompt.contains("<p>"))
        #expect(!prompt.contains("<strong>"))
        #expect(prompt.contains("Hello world"))
    }

    @Test func promptDecodesHTMLEntities() {
        let prompt = AIPromptBuilder.evaluatePostPrompt(title: "T", html: "<p>a &amp; b &lt;c&gt;</p>", styleGuide: nil)
        #expect(prompt.contains("a & b <c>"))
    }

    @Test func promptDecodesSmartQuoteEntities() {
        let prompt = AIPromptBuilder.evaluatePostPrompt(
            title: "T",
            html: "<p>He said &ldquo;hello&rdquo; and it&rsquo;s fine.</p>",
            styleGuide: nil
        )
        #expect(prompt.contains("\u{201C}hello\u{201D}"))
        #expect(prompt.contains("it\u{2019}s"))
    }

    @Test func promptDecodesTypographicDashAndEllipsis() {
        let prompt = AIPromptBuilder.evaluatePostPrompt(
            title: "T",
            html: "<p>A&ndash;B &mdash; C&hellip;</p>",
            styleGuide: nil
        )
        #expect(prompt.contains("\u{2013}"))  // en dash
        #expect(prompt.contains("\u{2014}"))  // em dash
        #expect(prompt.contains("\u{2026}"))  // ellipsis
    }

    @Test func promptNamesAllFiveCategories() {
        let prompt = AIPromptBuilder.evaluatePostPrompt(title: "T", html: "<p>x</p>", styleGuide: nil)
        #expect(prompt.lowercased().contains("grammar"))
        #expect(prompt.lowercased().contains("clarity"))
        #expect(prompt.lowercased().contains("readability"))
        #expect(prompt.lowercased().contains("wordiness"))
        #expect(prompt.lowercased().contains("tone"))
    }

    @Test func promptIncludesSummaryAndFindingsFormatInstructions() {
        let prompt = AIPromptBuilder.evaluatePostPrompt(title: "T", html: "<p>x</p>", styleGuide: nil)
        #expect(prompt.contains("SUMMARY:"))
        #expect(prompt.contains("FINDINGS:"))
        #expect(prompt.contains("QUOTE:"))
        #expect(prompt.contains("ISSUE:"))
    }

    @Test func promptIncludesAnchorFormatSpec() {
        let prompt = AIPromptBuilder.evaluatePostPrompt(title: "T", html: "<p>x</p>", styleGuide: nil)
        #expect(prompt.contains("ANCHOR:"))
    }

    @Test func promptIncludesStyleGuideWhenProvided() {
        let guide = "Conversational tone, short sentences, avoids jargon."
        let prompt = AIPromptBuilder.evaluatePostPrompt(title: "T", html: "<p>x</p>", styleGuide: guide)
        #expect(prompt.contains(guide))
        #expect(prompt.contains("established writing style"))
        #expect(prompt.contains("Treat elements consistent with this style as intentional"))
    }

    @Test func promptOmitsStyleGuideBlockWhenNil() {
        let prompt = AIPromptBuilder.evaluatePostPrompt(title: "T", html: "<p>x</p>", styleGuide: nil)
        #expect(!prompt.contains("established writing style"))
        #expect(!prompt.contains("Treat elements consistent"))
    }

    @Test func promptOmitsStyleGuideBlockWhenEmpty() {
        let prompt = AIPromptBuilder.evaluatePostPrompt(title: "T", html: "<p>x</p>", styleGuide: "")
        #expect(!prompt.contains("established writing style"))
    }

    @Test func promptExcludesImageCaptionText() {
        let html = "<figure class=\"wp-block-image\"><img src=\"x.jpg\"><figcaption class=\"wp-element-caption\">This is a caption</figcaption></figure><p>Body text.</p>"
        let prompt = AIPromptBuilder.evaluatePostPrompt(title: "T", html: html, styleGuide: nil)
        #expect(!prompt.contains("This is a caption"))
        #expect(prompt.contains("Body text"))
    }

    @Test func promptExcludesCodeBlockContent() {
        let html = "<p>Intro.</p><pre class=\"wp-block-code\"><code>let x = 1\nfoo()</code></pre><p>After code.</p>"
        let prompt = AIPromptBuilder.evaluatePostPrompt(title: "T", html: html, styleGuide: nil)
        #expect(!prompt.contains("let x = 1"))
        #expect(!prompt.contains("foo()"))
        #expect(prompt.contains("Intro"))
        #expect(prompt.contains("After code"))
    }

    @Test func promptExcludesEmbedFigureContent() {
        let html = "<p>See below.</p><figure class=\"wp-block-embed is-type-video\"><div class=\"wp-block-embed__wrapper\">https://www.youtube.com/watch?v=abc</div></figure><p>More prose.</p>"
        let prompt = AIPromptBuilder.evaluatePostPrompt(title: "T", html: html, styleGuide: nil)
        #expect(!prompt.contains("youtube.com"))
        #expect(prompt.contains("See below"))
        #expect(prompt.contains("More prose"))
    }

    @Test func promptExcludesFootnoteMarkersAndBackrefs() {
        let html = "<p>Editorial is the opposite of that. It\u{2019}s a block theme built around<sup data-fn class=\"fn\"><a href=\"#fn-abc123\">3</a></sup> the idea of blocks.</p><ol class=\"wp-block-footnotes\"><li id=\"fn-abc123\">See reference<a class=\"footnote-backref\" href=\"#ref-fn-abc123\">\u{21A9}</a></li></ol>"
        let prompt = AIPromptBuilder.evaluatePostPrompt(title: "T", html: html, styleGuide: nil)
        // Footnote number should not appear as plain text between words
        #expect(!prompt.contains("around 3 the"))
        #expect(prompt.contains("around the"))
        // Backref arrow should be stripped from footnote list text
        #expect(!prompt.contains("\u{21A9}"))
        #expect(prompt.contains("See reference"))
    }

    @Test func promptDoesNotInjectSpaceBeforePunctuationAfterInlineTags() {
        // Inline tags (links) immediately followed by a comma must not leave a
        // phantom space before the comma — otherwise Claude flags a "spaces
        // around commas" issue that isn't in the source, and the anchor (with
        // the phantom space) fails to match the editor text on jump-to-finding.
        let html = "<p>experiences such as <a href=\"/dspm\">DSPM</a>, <a href=\"/ce\">Content Explorer</a>, <a href=\"/de\">Data Explorer</a>.</p>"
        let prompt = AIPromptBuilder.evaluatePostPrompt(title: "T", html: html, styleGuide: nil)
        #expect(prompt.contains("DSPM, Content Explorer, Data Explorer"))
        #expect(!prompt.contains("DSPM ,"))
        #expect(!prompt.contains("Explorer ,"))
        #expect(!prompt.contains("Explorer ."))
    }

    @Test func promptStripsSpaceBeforeClosingPunctuation() {
        // Closing punctuation that ends up preceded by a phantom space (from an
        // inline tag) should be tightened: comma, period, semicolon, colon,
        // bang, question mark, and closing paren/bracket.
        let html = "<p>See <a href=\"/x\">this</a>; also <a href=\"/y\">that</a> (<a href=\"/z\">ref</a>)!</p>"
        let prompt = AIPromptBuilder.evaluatePostPrompt(title: "T", html: html, styleGuide: nil)
        #expect(prompt.contains("this; also"))
        #expect(prompt.contains("(ref)!"))
        #expect(!prompt.contains("this ;"))
        #expect(!prompt.contains("ref )"))
        #expect(!prompt.contains(") !"))
    }
}
