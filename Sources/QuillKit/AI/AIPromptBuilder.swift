import Foundation

public enum AIWritingOperation {
    case makeLonger
    case makeShorter
    case convertToTable
    case convertToList
}

public struct EvaluationFinding {
    public let quote: String
    public let anchor: String?   // 3–4 verbatim words for navigation; nil falls back to quote
    public let issue: String
    public let suggestion: String?
}

public struct EvaluationResult {
    public let summary: String
    public let findings: [EvaluationFinding]
}

public struct AIPromptBuilder {

    /// System prompt, optionally incorporating a pre-computed writing style guide.
    public static func systemPrompt(styleGuide: String?) -> String {
        var parts: [String] = [
            "You are a writing assistant embedded in a WordPress editor. " +
            "Always follow the output format specified in the user message exactly. " +
            "Do not wrap output in markdown code fences. " +
            "Produce clean, minimal HTML for any HTML content."
        ]
        if let guide = styleGuide, !guide.isEmpty {
            parts.append("Write in this author's style:\n\n\(guide)")
        }
        return parts.joined(separator: "\n\n")
    }

    /// User-turn prompt that asks Claude to produce a compact writing style guide
    /// from plain-text sample post contents. Used once when the user saves their
    /// sample post selection in Settings.
    public static func styleGuideGenerationPrompt(sampleContents: [String]) -> String {
        let samples = sampleContents.enumerated().map { i, c in
            "--- Sample \(i + 1) ---\n\(c)"
        }.joined(separator: "\n\n")
        return """
        Analyze these blog post samples and write a concise style guide (150 words max) \
        capturing this author's writing style. Cover: voice and tone, sentence rhythm, \
        vocabulary level, use of humor or personality, and any distinctive patterns. \
        Return only the style guide — no preamble, no labels.

        \(samples)
        """
    }

    /// User-turn prompt for generating a brand-new post.
    /// Returns a prompt that asks Claude to produce TITLE and CONTENT sections.
    public static func generatePostPrompt(userPrompt: String) -> String {
        """
        Write a blog post based on this description: \(userPrompt)

        Format your response exactly as:
        TITLE: <the post title, plain text, no HTML>

        CONTENT:
        <well-structured HTML using <h2> for major sections, <h3> for sub-sections, <p> for paragraphs, and <ul>/<li> for lists where appropriate. No markdown, no code fences, just clean HTML.>
        """
    }

    /// Parse Claude's generate-post response into (title, htmlContent).
    /// Returns nil if the format is not recognised.
    public static func parseGenerateResponse(_ text: String) -> (title: String, html: String)? {
        // Strip any markdown code fences Claude might add despite instructions
        var cleaned = text
        if let fenceRange = cleaned.range(of: "```html", options: .caseInsensitive) {
            cleaned.removeSubrange(fenceRange)
        }
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")

        // When web search is on, Claude emits a preamble text block that gets joined
        // directly to the TITLE: line without a newline. Search for "TITLE:" anywhere.
        guard let titleMarker = cleaned.range(of: "TITLE:", options: .caseInsensitive) else {
            return nil
        }
        // Everything from the marker onward; grab the title up to the first newline
        let afterTitle = cleaned[titleMarker.upperBound...]
        let titleEnd = afterTitle.firstIndex(of: "\n") ?? afterTitle.endIndex
        let title = afterTitle[..<titleEnd].trimmingCharacters(in: .whitespaces)

        // Find CONTENT: after the title marker
        guard let contentMarker = cleaned.range(of: "CONTENT:", options: .caseInsensitive,
                                                range: titleMarker.upperBound..<cleaned.endIndex) else {
            return nil
        }
        var html = String(cleaned[contentMarker.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip <cite index="...">...</cite> tags injected by Anthropic web search citations
        html = html.replacingOccurrences(
            of: #"<cite\s+index="[^"]*">[^<]*</cite>"#,
            with: "",
            options: .regularExpression
        )

        guard !title.isEmpty, !html.isEmpty else { return nil }
        return (title, html)
    }

    /// User-turn prompt for a selection operation.
    public static func operationPrompt(selectedHTML: String, operation: AIWritingOperation) -> String {
        let instruction: String
        switch operation {
        case .makeLonger:
            instruction = "Expand this content to roughly 2–3 times its current length by adding detail, examples, or explanation where it feels natural. Preserve the author's voice. Do not pad with filler. Return only the expanded version as HTML — no preamble, no explanation."
        case .makeShorter:
            instruction = "Condense this content to its essential points, removing redundancy while preserving meaning and the author's voice. Return only the shortened version as HTML — no preamble, no explanation."
        case .convertToTable:
            instruction = "Convert this content into an HTML table. Use <table>, <thead>, <tbody>, <tr>, <th>, and <td> tags. Identify logical columns from the content. Return only the table HTML — no preamble, no explanation."
        case .convertToList:
            instruction = "Convert this content into an HTML unordered list using <ul> and <li> tags. Each distinct point or item becomes a list item. Return only the list HTML — no preamble, no explanation."
        }
        return "\(instruction)\n\nContent to transform:\n\(selectedHTML)"
    }

    /// Prompt for evaluating the writing quality of a full post or page.
    /// Strips HTML to plain text before sending to reduce token usage.
    public static func evaluatePostPrompt(title: String, html: String, styleGuide: String?) -> String {
        let body = stripHTML(html)
        let styleContext: String
        if let guide = styleGuide, !guide.isEmpty {
            styleContext = """

        Author's established writing style:
        \(guide)

        Treat elements consistent with this style as intentional — do not flag them as issues.
        """
        } else {
            styleContext = ""
        }
        return """
        You are a writing quality evaluator. Analyze the following blog post for \
        grammar, clarity, readability, wordiness, and tone/voice consistency.\(styleContext)

        Title: \(title)

        Content:
        \(body)

        Respond in this exact format:

        SUMMARY:
        <2–4 sentence prose critique of the overall writing quality>

        FINDINGS:
        QUOTE: "display phrase (≤15 words, can be approximate)" | ANCHOR: "3–4 verbatim words" | ISSUE: short label | SUGGESTION: rewrite (optional)

        Rules:
        - QUOTE is shown to the user in the panel — it can be approximate or paraphrased, ≤15 words
        - ANCHOR is 3–4 consecutive words copied verbatim, character-for-character from the \
          Content above — no punctuation changes, no added or removed characters. \
          It is used to locate the text in the editor and must match exactly.
        - ISSUE label should be one of: Grammar, Clarity, Readability, Wordiness, Passive Voice, Tone
        - SUGGESTION is optional — omit the pipe and SUGGESTION field if you have no specific rewrite
        - Flag issues that would meaningfully improve the writing — skip minor stylistic preferences
        - For Wordiness: only flag phrases that are genuinely excessive and could be cut or \
          shortened without losing meaning; do not flag every slightly-long sentence
        - Prioritise the most impactful findings; aim for the 5–12 most significant issues
        - If there are no issues worth flagging, leave FINDINGS empty
        """
    }

    /// Parses Claude's evaluation response into an EvaluationResult.
    /// Returns nil if the SUMMARY: or FINDINGS: markers are missing or the summary is empty.
    public static func parseEvaluationResponse(_ text: String) -> EvaluationResult? {
        guard let summaryRange = text.range(of: "SUMMARY:", options: .caseInsensitive) else {
            return nil
        }
        guard let findingsRange = text.range(
            of: "FINDINGS:",
            options: .caseInsensitive,
            range: summaryRange.upperBound..<text.endIndex
        ) else {
            return nil
        }

        let summary = String(text[summaryRange.upperBound..<findingsRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return nil }

        let findingsText = String(text[findingsRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var findings: [EvaluationFinding] = []
        for line in findingsText.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.uppercased().hasPrefix("QUOTE:") else { continue }

            let parts = trimmed.components(separatedBy: " | ")
            guard parts.count >= 2 else { continue }

            // Strip "QUOTE:" prefix, then remove surrounding quotes if present
            let quotePart = parts[0]
                .replacingOccurrences(of: "QUOTE:", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
            let quote: String
            if quotePart.hasPrefix("\""), quotePart.hasSuffix("\""), quotePart.count > 1 {
                quote = String(quotePart.dropFirst().dropLast())
            } else {
                quote = quotePart
            }
            guard !quote.isEmpty else { continue }

            guard let issuePart = parts.first(where: { $0.uppercased().hasPrefix("ISSUE:") }) else { continue }
            let issue = issuePart
                .replacingOccurrences(of: "ISSUE:", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
            guard !issue.isEmpty else { continue }

            let anchor = parts
                .first(where: { $0.uppercased().hasPrefix("ANCHOR:") })
                .map { part -> String in
                    var s = part
                        .replacingOccurrences(of: "ANCHOR:", with: "", options: .caseInsensitive)
                        .trimmingCharacters(in: .whitespaces)
                    if s.hasPrefix("\""), s.hasSuffix("\""), s.count > 1 {
                        s = String(s.dropFirst().dropLast())
                    }
                    return s
                }
                .flatMap { $0.isEmpty ? nil : $0 }

            let suggestion = parts
                .first(where: { $0.uppercased().hasPrefix("SUGGESTION:") })
                .map { $0.replacingOccurrences(of: "SUGGESTION:", with: "", options: .caseInsensitive)
                          .trimmingCharacters(in: .whitespaces) }
                .flatMap { $0.isEmpty ? nil : $0 }

            findings.append(EvaluationFinding(quote: quote, anchor: anchor, issue: issue, suggestion: suggestion))
        }

        return EvaluationResult(summary: summary, findings: findings)
    }

    private static func stripHTML(_ html: String) -> String {
        // Strip non-prose blocks entirely before tag removal so they don't produce
        // nonsensical evaluation findings.
        // (?s) enables DOTALL so . matches newlines inside multi-line blocks
        var text = html.replacingOccurrences(
            of: #"(?s)<figcaption[^>]*>.*?</figcaption>"#,
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?s)<pre[^>]*>.*?</pre>"#,
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?s)<figure[^>]*wp-block-embed[^>]*>.*?</figure>"#,
            with: " ",
            options: .regularExpression
        )
        // Footnote markers are inline atoms in the editor (no text), so strip them
        // entirely — leaving the number causes Claude to flag it as stray text.
        text = text.replacingOccurrences(
            of: #"<sup[^>]*data-fn[^>]*>.*?</sup>"#,
            with: "",
            options: .regularExpression
        )
        // Footnote backrefs (↩) are NodeView artifacts not in the ProseMirror doc —
        // strip so footnote list text matches the editor for anchor navigation.
        text = text.replacingOccurrences(
            of: #"<a[^>]*footnote-backref[^>]*>.*?</a>"#,
            with: "",
            options: .regularExpression
        )
        // Convert closing block tags to spaces (not newlines) so the plain-text output
        // matches how findAndSelectText concatenates ProseMirror text nodes — with no separator.
        text = text.replacingOccurrences(
            of: #"</(p|h[1-6]|li|blockquote|pre|div)>"#,
            with: " ",
            options: .regularExpression
        )
        // Remove remaining tags (replace with space to prevent smashing adjacent inline elements)
        text = text.replacingOccurrences(of: #"<[^>]+(>|$)"#, with: " ", options: .regularExpression)
        // Decode HTML entities — named + numeric forms common in WordPress content
        text = text
            .replacingOccurrences(of: "&amp;",   with: "&")
            .replacingOccurrences(of: "&lt;",    with: "<")
            .replacingOccurrences(of: "&gt;",    with: ">")
            .replacingOccurrences(of: "&nbsp;",  with: "\u{00A0}")
            .replacingOccurrences(of: "&#160;",  with: "\u{00A0}")
            .replacingOccurrences(of: "&quot;",  with: "\"")
            .replacingOccurrences(of: "&#34;",   with: "\"")
            .replacingOccurrences(of: "&#39;",   with: "'")
            .replacingOccurrences(of: "&apos;",  with: "'")
            .replacingOccurrences(of: "&#8216;", with: "\u{2018}")
            .replacingOccurrences(of: "&lsquo;", with: "\u{2018}")
            .replacingOccurrences(of: "&#8217;", with: "\u{2019}")
            .replacingOccurrences(of: "&rsquo;", with: "\u{2019}")
            .replacingOccurrences(of: "&#8220;", with: "\u{201C}")
            .replacingOccurrences(of: "&ldquo;", with: "\u{201C}")
            .replacingOccurrences(of: "&#8221;", with: "\u{201D}")
            .replacingOccurrences(of: "&rdquo;", with: "\u{201D}")
            .replacingOccurrences(of: "&#8211;", with: "\u{2013}")
            .replacingOccurrences(of: "&ndash;", with: "\u{2013}")
            .replacingOccurrences(of: "&#8212;", with: "\u{2014}")
            .replacingOccurrences(of: "&mdash;", with: "\u{2014}")
            .replacingOccurrences(of: "&#8230;", with: "\u{2026}")
            .replacingOccurrences(of: "&hellip;", with: "\u{2026}")
        // Collapse all whitespace (spaces, tabs, newlines) and strip blank segments
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
