import Foundation

public enum AIWritingOperation: Sendable {
    case makeLonger
    case makeShorter
    case fixSpelling
    case rephrase
    case convertToTable
    case convertToList
}

public struct AIPromptBuilder {

    /// User-turn prompt that builds the style guide from sample posts. `Scripts/style-guide-probe.py` must match it.
    public static func styleGuideGenerationPrompt(samples: [(title: String, html: String)]) -> String {
        let reduced = samples.enumerated().map { i, sample in
            let body = reduceSample(html: sample.html)
            return sampleHeader(index: i + 1, title: decodeEntities(sample.title, keepMarkupEntities: false),
                                words: wordCount(ofReduced: body)) + "\n" + body
        }
        return styleGuideInstructions + "\n\n" + reduced.joined(separator: "\n\n")
    }

    private static let styleGuideInstructions = """
    Analyze these blog post samples and write a style guide that another writer can follow to write new posts in this author's style. The guide will be used both to write new posts and to judge whether a draft sounds like this author.

    Each sample is one post's title, word count and body. The HTML has been reduced to its structure: headings, paragraphs, lists, tables, block quotes, links, emphasis and footnotes. Images appear as [image], followed by their caption if they have one.

    Rules:
    - Write each point as an instruction to the writer ("Open with…", "Use…"), not as a description of the author.
    - Describe how the author writes, not what they write about. Leave out topics, products, hobbies and projects from the samples unless they show a habit that would carry over to any subject.
    - State a pattern only if it appears in at least two samples. Leave out generic writing advice.
    - Describe habits as tendencies ("often", "now and then"), not as rules to apply every time.
    - You may illustrate a habit with a word or short phrase in quotation marks, copied exactly from the samples. Never quote a whole sentence, and don't name products or technologies.

    Use exactly these labels, in this order, with nothing added to them. Under each label, write a short paragraph or a few bullets:

    Voice and tone:
    Sentence rhythm:
    Vocabulary:
    Humor and personality:
    Openings and closings:
    Structure and length:
    Formatting:
    Avoid:

    Formatting covers headings, lists, tables, footnotes, links, images and captions. Avoid covers things a generic writer would do that this author doesn't, and only where the samples make it clear.

    Aim for about 500 words. Start your response with "Voice and tone:" and end it after the Avoid section.
    """

    public static func sampleHeader(index: Int, title: String, words: Int) -> String {
        "--- Sample \(index): \(title) (\(words.formatted(.number.locale(Locale(identifier: "en_US")))) words) ---"
    }

    private static func wordCount(ofReduced body: String) -> Int {
        let text = body.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
        return text.split(whereSeparator: \.isWhitespace).count
    }

    private static let sampleKeptTags: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6", "p", "ul", "ol", "li", "blockquote",
                                                      "a", "em", "strong", "i", "b", "sup", "figcaption", "table", "tr", "th", "td"]
    private static let sampleBlockTags: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6", "p", "ul", "ol", "li", "blockquote",
                                                       "figcaption", "table", "tr"]
    private static let sampleBreakTags: Set<String> = ["br", "hr", "div", "figure", "section", "pre", "details", "summary", "dt", "dd"]

    /// Reduces a sample post to its structure: kept tags lose every attribute, images become [image], other tags go.
    public static func reduceSample(html: String) -> String {
        let tag = try! NSRegularExpression(pattern: #"<!--[\s\S]*?-->|<(/?)([A-Za-z][A-Za-z0-9]*)\b[^>]*>"#)
        let ns = html as NSString
        var out = ""
        var cursor = 0
        func appendText(_ range: NSRange) {
            guard range.length > 0 else { return }
            let text = decodeEntities(ns.substring(with: range), keepMarkupEntities: true)
            out += text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        }
        for match in tag.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            appendText(NSRange(location: cursor, length: match.range.location - cursor))
            cursor = match.range.location + match.range.length
            guard match.range(at: 2).location != NSNotFound else { continue }
            let name = ns.substring(with: match.range(at: 2)).lowercased()
            let closing = match.range(at: 1).length > 0
            let selfClosing = ns.substring(with: match.range).hasSuffix("/>")
            if !closing && name == "img" {
                out += "\n[image] "
            } else if sampleKeptTags.contains(name) {
                if !closing { out += (sampleBlockTags.contains(name) ? "\n" : "") + "<\(name)>" }
                if closing || selfClosing { out += "</\(name)>" }
            } else if sampleBreakTags.contains(name) {
                out += selfClosing ? "\n\n" : "\n"
            }
        }
        appendText(NSRange(location: cursor, length: ns.length - cursor))
        while true {
            let emptied = out.replacingOccurrences(of: #"<(\w+)>\s*</\1>"#, with: "", options: .regularExpression)
            if emptied == out { break }
            out = emptied
        }
        return out.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "nbsp": "\u{00A0}", "quot": "\"", "apos": "'",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
        "ndash": "\u{2013}", "mdash": "\u{2014}", "hellip": "\u{2026}",
    ]

    /// Decodes WordPress's common named entities and every numeric one. With `keepMarkupEntities`, `<`, `>` and `&` stay encoded.
    static func decodeEntities(_ text: String, keepMarkupEntities: Bool) -> String {
        let entity = try! NSRegularExpression(pattern: #"&(#[0-9]+|#[xX][0-9a-fA-F]+|[A-Za-z]+);"#)
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for match in entity.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            cursor = match.range.location + match.range.length
            let body = ns.substring(with: match.range(at: 1))
            var decoded: String?
            if body.hasPrefix("#") {
                let digits = body.dropFirst()
                let value = digits.first == "x" || digits.first == "X"
                    ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                decoded = value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                decoded = namedEntities[body]
            }
            if let char = decoded, keepMarkupEntities, let kept = ["<": "&lt;", ">": "&gt;", "&": "&amp;"][char] {
                decoded = kept
            }
            out += decoded ?? ns.substring(with: match.range)
        }
        out += ns.substring(from: cursor)
        return out
    }

    // MARK: - Generate Post

    public static func generateSystem(styleGuide: String?, today: Date, webSearch: Bool) -> String {
        var parts = [
            "You write blog post drafts for an author in Quill, a WordPress editor. Today's date is \(EvaluationPrompts.day(today)).",
            "The author edits the draft and publishes it under their own name, so everything in it must be true of them, and you don't know their life. Don't write about what the author does, did, uses, tried, noticed or plans, and don't mention their work, clients or history, unless the description tells you about it. Give opinions as judgments about the subject (\"Templates should…\", \"The better choice is…\"), not as reports of the author's own habits or experience.",
        ]
        let guide = styleGuide.flatMap { $0.isEmpty ? nil : $0 }
        if guide != nil {
            parts.append("Write in the author's voice, following the style guide below. Its quoted words and phrases show the author's habits; don't copy them, because a copied phrase reads as a tic.")
        }
        if webSearch {
            parts.append("Your training data ends well before today's date. Records, office holders, prices, versions, rules and anything \"latest\" may have changed since then, so search for those before you write about them, even when you feel sure. Facts that can't change need no search.")
        }
        if let guide {
            parts.append("<style_guide>\n\(guide)\n</style_guide>")
        }
        return parts.joined(separator: "\n\n")
    }

    public static func generatePrompt(description: String, webSearch: Bool) -> String {
        let linking = webSearch
            ? #" Link each fact you took from a search to its source, with <a href="…"> on the words it supports, the way the author links inline."#
            : ""
        return """
        Write a blog post from this description:

        <description>
        \(description)
        </description>

        Follow the style guide's length and structure unless the description asks for something else. Use only the HTML the post needs: <h2> for sections (<h3> under one only when a section needs it), <p>, <ul> or <ol> with <li>, <blockquote>, <em>, <strong>, and <table> with <thead>, <tbody>, <tr>, <th> and <td> for tabular data. No other tags, no attributes except href, no styles and no Markdown.\(linking)

        Put the title, as plain text, in "title"; one or two sentences for the post's excerpt in "excerpt"; and the body in "html".
        """
    }

    nonisolated(unsafe) public static let generateSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "title": ["type": "string"],
            "excerpt": ["type": "string"],
            "html": ["type": "string"],
        ],
        "required": ["title", "excerpt", "html"],
        "additionalProperties": false,
    ]

    public struct EmptyGeneratedPost: Error {}

    /// Reads Generate's JSON reply. Throws when it doesn't parse (a truncated reply never does) or holds no post.
    public static func parseGenerated(_ json: String) throws -> (title: String, excerpt: String, html: String) {
        struct Payload: Decodable { let title, excerpt, html: String }
        let payload = try JSONDecoder().decode(Payload.self, from: Data(json.utf8))
        // Citation spans leave a space before the punctuation that follows them ("honestly , they're").
        var html = payload.html.replacingOccurrences(
            of: #"</cite> +(?=[;:!?](?:\s|<|$))"#, with: "</cite>", options: .regularExpression)
        // Keep the words inside a search citation even if Claude wraps whole sentences, nested tags included.
        html = html.replacingOccurrences(
            of: #"<cite\s+index="[^"]*">(.*?)</cite>"#, with: "$1", options: .regularExpression)
        // French spaces before ; : ! ? but no language spaces before a comma or full stop.
        html = html.replacingOccurrences(of: #" +(?=[,.](?:\s|<|$))"#, with: "", options: .regularExpression)
        html = normalizeAITables(html).trimmingCharacters(in: .whitespacesAndNewlines)
        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !html.isEmpty else { throw EmptyGeneratedPost() }
        return (title, payload.excerpt.trimmingCharacters(in: .whitespacesAndNewlines), html)
    }

    /// Cleans a selection operation's reply before it reaches the editor.
    public static func cleanOperationResult(_ html: String) -> String {
        normalizeAITables(html).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips Claude's inline table styles and gives new tables core's default fixed layout, as the toolbar does.
    public static func normalizeAITables(_ html: String) -> String {
        html.replacingOccurrences(
            of: #"(<(?:table|thead|tbody|tfoot|tr|th|td|caption)(?![-\w])[^>]*?)\s+style\s*=\s*(?:"[^"]*"|'[^']*')"#,
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        ).replacingOccurrences(
            of: #"<table(?![-\w])(?![^>]*\bclass\s*=)"#,
            with: #"<table class="has-fixed-layout""#,
            options: [.regularExpression, .caseInsensitive]
        )
    }
}
