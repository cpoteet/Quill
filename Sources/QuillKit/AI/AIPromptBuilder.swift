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
            "Respond with valid HTML only — no markdown, no code fences, no explanation text. " +
            "Produce clean, minimal HTML suitable for a WordPress post body."
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
        <post body as HTML paragraphs>
        """
    }

    /// Parse Claude's generate-post response into (title, htmlContent).
    /// Returns nil if the format is not recognised.
    public static func parseGenerateResponse(_ text: String) -> (title: String, html: String)? {
        let lines = text.components(separatedBy: "\n")
        guard let titleLine = lines.first(where: { $0.hasPrefix("TITLE:") }) else { return nil }
        let title = String(titleLine.dropFirst("TITLE:".count)).trimmingCharacters(in: .whitespaces)
        guard let contentIdx = lines.firstIndex(where: { $0.hasPrefix("CONTENT:") }) else { return nil }
        let html = lines[(contentIdx + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
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
