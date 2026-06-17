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
}
