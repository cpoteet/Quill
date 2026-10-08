import Foundation

public struct EvaluationReview: Decodable, Equatable, Sendable {
    public let strengths: String
    public let priorities: [String]
}

public struct ReviewFinding: Decodable, Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case correction, suggestion }

    public let id = UUID()
    public var kind: Kind = .correction
    public let category: String
    public let original: String
    public let replacement: String
    public let explanation: String

    enum CodingKeys: String, CodingKey { case category, original, replacement, explanation }
}

public struct ReviewResult: Equatable, Sendable {
    public let review: EvaluationReview
    public let corrections: [ReviewFinding]
    public let suggestions: [ReviewFinding]
}

public struct FactCheck: Decodable, Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let original: String
    public let explanation: String
    public let sourceQuote: String
    public let sourceURL: String
    public let replacement: String

    enum CodingKeys: String, CodingKey {
        case original, explanation, replacement
        case sourceQuote = "source_quote"
        case sourceURL = "source_url"
    }
}

public struct FactCheckResult: Equatable, Sendable {
    public let claimsChecked: Int
    public let checks: [FactCheck]
}

/// Evaluate's two requests: the review (corrections, suggestions, overall judgment) and the web-search fact-check.
public enum EvaluationPrompts {

    // MARK: - The post as Claude sees it

    private static let markerSentence = ###"It is shown as plain text: "## " marks a heading, "- " a list item, "| … |" a table row, "[Caption]" an image caption and "[Footnote]" a footnote."###

    private static let blockTags: Set<String> = ["p", "h1", "h2", "h3", "h4", "h5", "h6", "li", "ul", "ol", "dl", "dt", "dd",
                                                 "blockquote", "div", "figure", "figcaption", "table", "section", "details",
                                                 "summary", "hr", "header", "footer", "aside", "article", "nav", "main", "address"]
    private static let blockBreak = "\u{1E}"
    private static let rowBreak = "\u{1F}"

    /// Plain text whose characters match the editor's, with markers for headings, list items, table rows, captions and footnotes.
    public static func postText(html: String) -> String {
        var source = html
        for pattern in [#"(?s)<pre[^>]*>.*?</pre>"#,
                        #"(?si)<(script|style)\b[^>]*>.*?</\1\s*>"#,
                        #"(?s)<figure[^>]*wp-block-embed[^>]*>.*?</figure>"#,
                        #"(?s)<sup[^>]*data-fn[^>]*>.*?</sup>"#,
                        #"(?s)<a[^>]*footnote-backref[^>]*>.*?</a>"#,
                        ##"(?s)<a[^>]*href="#[^"]*-link"[^>]*>.*?</a>"##] {
            source = source.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        let tag = try! NSRegularExpression(pattern: #"<!--[\s\S]*?-->|<(/?)([A-Za-z][A-Za-z0-9]*)\b([^>]*)>"#)
        let ns = source as NSString
        var out = ""
        var cursor = 0
        var listStack: [Bool] = []
        for match in tag.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            cursor = match.range.location + match.range.length
            guard match.range(at: 2).location != NSNotFound else { continue }
            let name = ns.substring(with: match.range(at: 2)).lowercased()
            let closing = match.range(at: 1).length > 0
            let attributes = ns.substring(with: match.range(at: 3))
            switch (name, closing) {
            case ("ol", false), ("ul", false):
                listStack.append(attributes.contains("wp-block-footnotes"))
                out += blockBreak
            case ("ol", true), ("ul", true):
                _ = listStack.popLast()
                out += blockBreak
            case ("li", false):
                out += blockBreak + (listStack.last == true ? "[Footnote] " : "- ")
            case ("figcaption", false):
                out += blockBreak + "[Caption] "
            case ("tr", false):
                out += rowBreak + "| "
            case ("tr", true):
                out += rowBreak
            case ("td", true), ("th", true):
                out += " | "
            case ("br", _):
                out += " "
            default:
                if name.count == 2, name.first == "h", let level = Int(name.dropFirst()), (1...6).contains(level) {
                    out += blockBreak + (closing ? "" : String(repeating: "#", count: level) + " ")
                } else if blockTags.contains(name) {
                    out += blockBreak
                }
            }
        }
        out += ns.substring(from: cursor)
        out = AIPromptBuilder.decodeEntities(out, keepMarkupEntities: false)
        return out.components(separatedBy: blockBreak)
            .map { block in
                block.components(separatedBy: rowBreak)
                    // ProseMirror collapses source whitespace but keeps each non-breaking space as a character.
                    .map { $0.replacingOccurrences(of: #"[ \t\n\r\f]+"#, with: " ", options: .regularExpression)
                        .trimmingCharacters(in: CharacterSet(charactersIn: " "))
                        .replacingOccurrences(of: "\u{00A0}", with: " ") }
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0 != "|" }
                    .joined(separator: "\n")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// The post's footnote bodies, from the `footnotes` meta, appended as the list WordPress renders.
    public static func appendingFootnotes(to html: String, meta: String) -> String {
        struct Footnote: Decodable { let content: String }
        guard let notes = try? JSONDecoder().decode([Footnote].self, from: Data(meta.utf8)), !notes.isEmpty else { return html }
        return html + #"<ol class="wp-block-footnotes">"# + notes.map { "<li>\($0.content)</li>" }.joined() + "</ol>"
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func postBlock(title: String, html: String, publishedOn: Date?) -> String {
        let status = publishedOn.map { "Published: \(day($0))" } ?? "Status: draft, not yet published"
        return "<post>\nTitle: \(title)\n\(status)\n\n\(postText(html: html))\n</post>"
    }

    // MARK: - Review request

    public static func reviewSystem(styleGuide: String?, today: Date) -> String {
        var system = #"You are an experienced editor reviewing a blog post for its author in Quill, a WordPress editor. Today's date is \#(day(today)). Write to the author as "you"."#
        if let guide = styleGuide, !guide.isEmpty {
            system += """


            The author's style guide is below. Writing that follows it is intentional: don't correct the author's voice, word choices or habits toward a generic style. Use the guide to recognise the author's voice, not as a checklist: never suggest adding tables, footnotes, lists, asides or any other feature because the guide mentions it.

            <style_guide>
            \(guide)
            </style_guide>
            """
        }
        return system
    }

    public static func review(title: String, html: String, publishedOn: Date?) -> String {
        """
        Review this post and report what would make it better. \(markerSentence)

        \(postBlock(title: title, html: html, publishedOn: publishedOn))

        Report three kinds of feedback. Someone else is checking facts, so don't judge whether claims are true.

        Corrections are errors any copy editor would fix whatever the author's style: spelling, grammar, punctuation, a wrong or missing word, and inconsistent names, capitalization or terms. Report every one you find, in captions, footnotes and tables too. A spelling or style the author uses consistently is not an error, even where a style manual would differ. A judgment call is a suggestion, not a correction.

        Suggestions are changes worth the author's time: a sentence that is hard to follow, wording that could lose words without losing meaning, an awkward transition, a repeated word or idea, or a passage that drifts from the style guide. Rewrite only the words that need it and keep the author's wording elsewhere. Skip changes that are a matter of taste. A short list of strong suggestions is better than a long one.

        The review is your overall judgment: what works, then the two or three changes that would improve the post most, looking at the title, the opening, the order of sections, the headings and the ending.

        For every correction and suggestion, "original" is the exact text it applies to, copied character for character from the post (without the markers), as short as it can be while still being unique in the post. "replacement" is the text to put in its place. If the fix is to delete the text, "replacement" is an empty string.
        """
    }

    private static func findingSchema(_ categories: [String]) -> [String: Any] {
        [
            "type": "array",
            "items": [
                "type": "object",
                "properties": [
                    "category": ["type": "string", "enum": categories],
                    "original": ["type": "string"],
                    "replacement": ["type": "string"],
                    "explanation": ["type": "string"],
                ],
                "required": ["category", "original", "replacement", "explanation"],
                "additionalProperties": false,
            ] as [String: Any],
        ]
    }

    nonisolated(unsafe) public static let reviewSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "review": [
                "type": "object",
                "properties": [
                    "strengths": ["type": "string"],
                    "priorities": ["type": "array", "items": ["type": "string"]],
                ],
                "required": ["strengths", "priorities"],
                "additionalProperties": false,
            ] as [String: Any],
            "corrections": findingSchema(["Spelling", "Grammar", "Punctuation", "Word choice", "Consistency"]),
            "suggestions": findingSchema(["Clarity", "Concision", "Flow", "Repetition", "Voice", "Structure"]),
        ],
        "required": ["review", "corrections", "suggestions"],
        "additionalProperties": false,
    ]

    public static func parseReview(_ json: String) throws -> ReviewResult {
        struct Payload: Decodable {
            let review: EvaluationReview
            let corrections: [ReviewFinding]
            let suggestions: [ReviewFinding]
        }
        let payload = try JSONDecoder().decode(Payload.self, from: Data(json.utf8))
        func kept(_ findings: [ReviewFinding], as kind: ReviewFinding.Kind) -> [ReviewFinding] {
            findings.filter { $0.replacement != $0.original }.map { var f = $0; f.kind = kind; return f }
        }
        return ReviewResult(review: payload.review,
                            corrections: kept(payload.corrections, as: .correction),
                            suggestions: kept(payload.suggestions, as: .suggestion))
    }

    // MARK: - Fact-check request

    public static func factCheckSystem(today: Date) -> String {
        #"You fact-check blog posts for their author in Quill, a WordPress editor. Today's date is \#(day(today)). Write to the author as "you". Your training data ends well before today's date. Product names, versions, release status, dates, prices, people's roles, rules and anything "latest" may have changed since then, so search for those before you judge them, even when you feel sure."#
    }

    public static func factCheck(title: String, html: String, publishedOn: Date?) -> String {
        """
        Fact-check this post. \(markerSentence)

        \(postBlock(title: title, html: html, publishedOn: publishedOn))

        Check claims a reader could verify against a public source, not the author's own experiences, plans or opinions. A published post is judged against its publish date: a claim that was true then is not an error, but if it has since changed, say so. Prefer the vendor's own documentation and announcements to blogs and forums. Search at most 8 times.

        First list every checkable claim in "claims", each with its verdict: "confirmed", "wrong", "outdated", "needs qualifier" or "not checked". Search for every claim about something that can change before giving it a verdict; use "not checked" only when you ran out of searches. Group related claims into one search where you can.

        Then, in "fact_checks", report each claim whose verdict is wrong, outdated or needs qualifier. For each one, "original" is the exact text it applies to, copied character for character from the post (without the markers), as short as it can be while still being unique in the post. "explanation" says in one or two sentences what is wrong and what is true instead. "source_quote" is the sentence from the source that shows it, copied exactly, and "source_url" is that source. "replacement" is corrected wording for "original", or an empty string if the author should decide how to fix it.
        """
    }

    nonisolated(unsafe) public static let factCheckSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "claims": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "claim": ["type": "string"],
                        "verdict": ["type": "string", "enum": ["confirmed", "wrong", "outdated", "needs qualifier", "not checked"]],
                    ],
                    "required": ["claim", "verdict"],
                    "additionalProperties": false,
                ] as [String: Any],
            ] as [String: Any],
            "fact_checks": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "original": ["type": "string"],
                        "explanation": ["type": "string"],
                        "source_quote": ["type": "string"],
                        "source_url": ["type": "string"],
                        "replacement": ["type": "string"],
                    ],
                    "required": ["original", "explanation", "source_quote", "source_url", "replacement"],
                    "additionalProperties": false,
                ] as [String: Any],
            ] as [String: Any],
        ],
        "required": ["claims", "fact_checks"],
        "additionalProperties": false,
    ]

    public static func parseFactCheck(_ json: String) throws -> FactCheckResult {
        struct Claim: Decodable { let claim: String }
        struct Payload: Decodable {
            let claims: [Claim]
            let factChecks: [FactCheck]
            enum CodingKeys: String, CodingKey { case claims, factChecks = "fact_checks" }
        }
        let payload = try JSONDecoder().decode(Payload.self, from: Data(json.utf8))
        return FactCheckResult(claimsChecked: payload.claims.count, checks: payload.factChecks)
    }
}
