import Foundation

public enum AIWritingOperation {
    case makeLonger
    case makeShorter
    case convertToTable
    case convertToList
}

public struct AIPromptBuilder {

    /// System prompt, optionally incorporating style sample posts.
    /// Pass stripped plain-text content of sample posts.
    public static func systemPrompt(samplePostContents: [String]) -> String {
        var parts: [String] = []
        parts.append(
            "You are a writing assistant embedded in a WordPress editor. " +
            "Always follow the output format specified in the user message exactly. " +
            "Do not wrap output in markdown code fences. " +
            "Produce clean, minimal HTML for any HTML content."
        )
        if !samplePostContents.isEmpty {
            parts.append(
                "The author's writing style is shown in these sample posts. " +
                "Match their voice, tone, sentence rhythm, vocabulary, and personality:\n\n" +
                samplePostContents.enumerated().map { i, c in
                    "--- Sample \(i + 1) ---\n\(c)"
                }.joined(separator: "\n\n")
            )
        }
        return parts.joined(separator: "\n\n")
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
        let html = String(cleaned[contentMarker.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty, !html.isEmpty else { return nil }
        return (title, html)
    }

    /// User-turn prompt for a selection operation.
    public static func operationPrompt(selectedHTML: String, operation: AIWritingOperation) -> String {
        let instruction: String
        switch operation {
        case .makeLonger:
            instruction = "Expand and elaborate on this content, adding more detail, examples, and explanation while preserving the author's voice. Return only the expanded version as HTML — no preamble, no explanation."
        case .makeShorter:
            instruction = "Condense this content to its essential points, removing redundancy while preserving meaning and the author's voice. Return only the shortened version as HTML — no preamble, no explanation."
        case .convertToTable:
            instruction = "Convert this content into an HTML table. Use <table>, <thead>, <tbody>, <tr>, <th>, and <td> tags. Identify logical columns from the content. Return only the table HTML — no preamble, no explanation."
        case .convertToList:
            instruction = "Convert this content into an HTML unordered list using <ul> and <li> tags. Each distinct point or item becomes a list item. Return only the list HTML — no preamble, no explanation."
        }
        return "\(instruction)\n\nContent to transform:\n\(selectedHTML)"
    }
}
