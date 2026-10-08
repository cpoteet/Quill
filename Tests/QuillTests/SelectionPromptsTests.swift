import Foundation
import Testing
@testable import QuillKit

@Suite struct SelectionPromptsTests {

    private func selection(_ html: String = "Some <em>text</em>", plain: String = "Some text", context: String? = nil) -> AISelection {
        AISelection(html: html, plainText: plain, before: "Before text.", after: "After text.", title: "A Post", context: context)
    }

    private func words(_ count: Int) -> String {
        Array(repeating: "word", count: count).joined(separator: " ")
    }

    @Test func targetsMatchToday() {
        func t(_ w: Int, _ op: AIWritingOperation) -> [Int] { let r = SelectionPrompts.targets(words: w, operation: op); return [r.target, r.ceiling] }
        #expect(t(5, .makeLonger) == [20, 25])
        #expect(t(39, .makeLonger) == [156, 195])
        #expect(t(40, .makeLonger) == [80, 100])
        #expect(t(150, .makeLonger) == [300, 375])
        #expect(t(151, .makeLonger) == [227, 302])
        #expect(t(10, .makeShorter) == [7, 8])
        #expect(t(39, .makeShorter) == [27, 31])
        #expect(t(40, .makeShorter) == [20, 24])
        #expect(t(150, .makeShorter) == [75, 90])
        #expect(t(151, .makeShorter) == [60, 76])
        #expect(t(1, .makeShorter) == [1, 1])
    }

    @Test func userPromptWrapsSelectionAndContext() {
        let prompt = SelectionPrompts.user(selection(), operation: .rephrase)
        #expect(prompt.hasPrefix("<post_title>A Post</post_title>\n\n<before>\nBefore text.\n</before>\n\n<selection>\nSome <em>text</em>\n</selection>\n\n<after>\nAfter text.\n</after>\n\n"))
        #expect(prompt.hasSuffix(#"Don't add links, footnotes or formatting, and don't repeat what the text before or after already says. Put the rewritten selection in "html"."#))
        #expect(prompt.contains("Keep each <a id=\"…\">…</a>, <sup id=\"…\"></sup>, <em>, <strong> and <code> with the words it belongs to"))
    }

    @Test func instructionPerOperation() {
        let longer = SelectionPrompts.user(selection(plain: words(5)), operation: .makeLonger)
        #expect(longer.contains("Expand the selection from 5 words to about 20 words, and never more than 25. Keep the author's sentences, and add new ones that explain the reasoning, spell out a consequence or give a general example of what the selection already says. Don't add facts, figures, names, dates or quotes that the selection and the text around it don't support, and don't describe anything the author did, saw or felt beyond what the text says. Keep the same number of paragraphs."))
        let shorter = SelectionPrompts.user(selection(plain: words(100)), operation: .makeShorter)
        #expect(shorter.contains("Shorten the selection from 100 words to about 50 words, and never more than 60. Cut the least important sentences and tighten the rest, keeping the author's own words where you can. Keep the meaning and the same number of paragraphs."))
        let fix = SelectionPrompts.user(selection(plain: words(12)), operation: .fixSpelling)
        #expect(fix.contains("Fix the spelling, grammar and punctuation errors in the selection, and nothing else. Keep every other word, the word order and the author's style, even where you would write it differently. If there is nothing to fix, return the selection unchanged."))
        #expect(!fix.contains("words to about"))
        let rephrase = SelectionPrompts.user(selection(plain: words(12)), operation: .rephrase)
        #expect(rephrase.contains("Rephrase the selection so it reads more clearly and smoothly, with the same meaning and about the same length (12 words). Keep the author's voice, and keep their wording wherever it already reads well."))
        #expect(!rephrase.contains("never more than"))
    }

    @Test func convertInstructionsNameTheirTags() {
        #expect(SelectionPrompts.user(selection(), operation: .convertToTable).contains("<table>, <thead>, <tbody>, <tr>, <th> and <td>"))
        #expect(SelectionPrompts.user(selection(), operation: .convertToList).contains("<ul> and <li>"))
    }

    @Test func listAndTableKeepContainerInstruction() {
        for context in ["bulletList", "orderedList", "table"] {
            for operation in [AIWritingOperation.makeLonger, .makeShorter, .fixSpelling, .rephrase] {
                let prompt = SelectionPrompts.user(selection(plain: words(20), context: context), operation: operation)
                #expect(!prompt.contains("words to about"), "\(context) \(operation)")
                let tag = context == "orderedList" ? "<ol>" : context == "bulletList" ? "<ul>" : "<table>"
                #expect(prompt.contains("return the whole \(context == "table" ? "table" : "list") as HTML"), "\(context) \(operation)")
                #expect(prompt.contains(tag), "\(context) \(operation)")
            }
        }
        let longerList = SelectionPrompts.user(selection(plain: words(20), context: "bulletList"), operation: .makeLonger)
        #expect(longerList.contains("Expand each list item"))
        #expect(longerList.contains("Don't add facts, figures, names, dates or quotes"))
        #expect(longerList.contains("don't describe anything the author did, saw or felt"))
        let shorterTable = SelectionPrompts.user(selection(plain: words(20), context: "table"), operation: .makeShorter)
        #expect(shorterTable.contains("Condense each table cell"))
    }

    @Test func convertingInsideAListOrTableUsesTheGeneralConvertInstruction() {
        for context in ["bulletList", "orderedList", "table"] {
            let table = SelectionPrompts.user(selection(context: context), operation: .convertToTable)
            #expect(table.contains("Convert the selection into an HTML table"), "\(context)")
            let list = SelectionPrompts.user(selection(context: context), operation: .convertToList)
            #expect(list.contains("Convert the selection into an HTML unordered list"), "\(context)")
            #expect(!table.contains("Keep the same") && !list.contains("Keep the same"), "\(context)")
        }
    }

    @Test func systemPromptHasGuideOrNot() {
        let with = SelectionPrompts.system(styleGuide: "Terse.")
        #expect(with.hasPrefix("You edit part of a blog post for its author in Quill, a WordPress editor. You rewrite only the selected text; the text around it is there so your rewrite fits in its place.\n\nMatch the author's voice. The selected text is the best example of it; the style guide below describes it more broadly. Quoted words and phrases in the guide are examples of the author's habits, not phrases to reuse."))
        #expect(with.hasSuffix("<style_guide>\nTerse.\n</style_guide>"))
        let without = SelectionPrompts.system(styleGuide: nil)
        #expect(without.hasSuffix("Match the author's voice. The selected text is the best example of it."))
        #expect(!without.contains("style_guide"))
    }

    @Test func parseReadsHTMLField() throws {
        #expect(try SelectionPrompts.parse(#"{"html":"Some <em>text</em>"}"#) == "Some <em>text</em>")
        #expect(throws: (any Error).self) { _ = try SelectionPrompts.parse("Some text") }
        let props = SelectionPrompts.schema["properties"] as! [String: Any]
        #expect(props.keys.sorted() == ["html"])
        #expect(SelectionPrompts.schema["required"] as? [String] == ["html"])
    }
}
