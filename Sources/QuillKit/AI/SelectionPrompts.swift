import Foundation

/// What the editor hands over for a right-click rewrite: the selection as reduced HTML and the text around it.
public struct AISelection {
    public var html: String
    public var plainText: String
    public var before: String
    public var after: String
    public var title: String
    /// `bulletList`, `orderedList` or `table` when the selection is inside one, and `html` is then the whole container.
    public var context: String?

    public init(html: String, plainText: String, before: String, after: String, title: String, context: String?) {
        self.html = html
        self.plainText = plainText
        self.before = before
        self.after = after
        self.title = title
        self.context = context
    }
}

/// The right-click rewrites: Make Longer, Make Shorter, Fix Spelling & Grammar, Rephrase, Convert to Table and Convert to List.
public enum SelectionPrompts {

    public static func system(styleGuide: String?) -> String {
        let intro = "You edit part of a blog post for its author in Quill, a WordPress editor. You rewrite only the selected text; the text around it is there so your rewrite fits in its place."
        guard let guide = styleGuide, !guide.isEmpty else {
            return intro + "\n\nMatch the author's voice. The selected text is the best example of it."
        }
        return """
        \(intro)

        Match the author's voice. The selected text is the best example of it; the style guide below describes it more broadly. Quoted words and phrases in the guide are examples of the author's habits, not phrases to reuse.

        <style_guide>
        \(guide)
        </style_guide>
        """
    }

    public static func user(_ selection: AISelection, operation: AIWritingOperation) -> String {
        """
        <post_title>\(selection.title)</post_title>

        <before>
        \(selection.before)
        </before>

        <selection>
        \(selection.html)
        </selection>

        <after>
        \(selection.after)
        </after>

        \(instruction(for: operation, selection: selection))

        The selection is HTML and may start or end mid-paragraph; your rewrite replaces it exactly, so it must fit between the text before and after. Keep each <a id="…">…</a>, <sup id="…"></sup>, <em>, <strong> and <code> with the words it belongs to, and drop one only when you remove all of its words. Don't add links, footnotes or formatting, and don't repeat what the text before or after already says. Put the rewritten selection in "html".
        """
    }

    public static func targets(words: Int, operation: AIWritingOperation) -> (target: Int, ceiling: Int) {
        let factors: (Double, Double)
        switch operation {
        case .makeLonger: factors = words < 40 ? (4, 5) : words <= 150 ? (2, 2.5) : (1.5, 2)
        case .makeShorter: factors = words < 40 ? (0.7, 0.8) : words <= 150 ? (0.5, 0.6) : (0.4, 0.5)
        default: factors = (1, 1)
        }
        func scaled(_ factor: Double) -> Int { max(1, Int((Double(words) * factor).rounded())) }
        return (scaled(factors.0), scaled(factors.1))
    }

    private static let noInvention = "Don't add facts, figures, names, dates or quotes that the selection and the text around it don't support, and don't describe anything the author did, saw or felt beyond what the text says."

    private static func instruction(for operation: AIWritingOperation, selection: AISelection) -> String {
        let w = selection.plainText.split(whereSeparator: \.isWhitespace).count
        let (t, m) = targets(words: w, operation: operation)
        switch selection.context {
        case "bulletList", "orderedList":
            let keep = "Keep the same items in the same order, and return the whole list as HTML (\(selection.context == "orderedList" ? "<ol>" : "<ul>") with <li> items)."
            switch operation {
            case .makeLonger:
                return "Expand each list item to about two to three times its length. Keep the author's words in each item, and add words that explain the reasoning, spell out a consequence or give a general example of what the item already says. \(noInvention) \(keep)"
            case .makeShorter:
                return "Condense each list item to its essential point, keeping the author's own words where you can and the meaning of each item. \(keep)"
            case .fixSpelling:
                return "Fix the spelling, grammar and punctuation errors in the list, and nothing else. Keep every other word, the word order and the author's style, even where you would write it differently. \(keep)"
            case .rephrase:
                return "Rephrase each list item so it reads more clearly and smoothly, with the same meaning and about the same length. Keep the author's voice, and keep their wording wherever it already reads well. \(keep)"
            case .convertToTable, .convertToList:
                break
            }
        case "table":
            let keep = "Keep the same rows and columns, and return the whole table as HTML (<table> with its rows and cells)."
            switch operation {
            case .makeLonger:
                return "Expand the content of each table cell by explaining what it already says. \(noInvention) \(keep)"
            case .makeShorter:
                return "Condense each table cell to its essential content, keeping its meaning. \(keep)"
            case .fixSpelling:
                return "Fix the spelling, grammar and punctuation errors in the table, and nothing else. Keep every other word and the author's style. \(keep)"
            case .rephrase:
                return "Rephrase each table cell so it reads more clearly, with the same meaning and about the same length. Keep the author's wording wherever it already reads well. \(keep)"
            case .convertToTable, .convertToList:
                break
            }
        default:
            break
        }
        switch operation {
        case .makeLonger:
            return "Expand the selection from \(w) words to about \(t) words, and never more than \(m). Keep the author's sentences, and add new ones that explain the reasoning, spell out a consequence or give a general example of what the selection already says. \(noInvention) Keep the same number of paragraphs."
        case .makeShorter:
            return "Shorten the selection from \(w) words to about \(t) words, and never more than \(m). Cut the least important sentences and tighten the rest, keeping the author's own words where you can. Keep the meaning and the same number of paragraphs."
        case .fixSpelling:
            return "Fix the spelling, grammar and punctuation errors in the selection, and nothing else. Keep every other word, the word order and the author's style, even where you would write it differently. If there is nothing to fix, return the selection unchanged."
        case .rephrase:
            return "Rephrase the selection so it reads more clearly and smoothly, with the same meaning and about the same length (\(w) words). Keep the author's voice, and keep their wording wherever it already reads well."
        case .convertToTable:
            return "Convert the selection into an HTML table, using <table>, <thead>, <tbody>, <tr>, <th> and <td>. Identify logical columns from the content, and keep the author's words."
        case .convertToList:
            return "Convert the selection into an HTML unordered list using <ul> and <li>. Each distinct point or item becomes a list item, in the author's words."
        }
    }

    nonisolated(unsafe) public static let schema: [String: Any] = [
        "type": "object",
        "properties": ["html": ["type": "string"]],
        "required": ["html"],
        "additionalProperties": false,
    ]

    public static func parse(_ json: String) throws -> String {
        struct Payload: Decodable { let html: String }
        return try JSONDecoder().decode(Payload.self, from: Data(json.utf8)).html
    }
}
