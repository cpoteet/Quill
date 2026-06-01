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
