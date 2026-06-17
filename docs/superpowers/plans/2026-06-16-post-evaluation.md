# Post Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a toolbar button that sends the full post/page content to Claude and displays a conversational writing critique in the right panel, with clickable findings that jump to the relevant phrase in the editor.

**Architecture:** Four new data types and two new functions go into `AIPromptBuilder.swift`. A new `EvaluationPanel.swift` SwiftUI view handles the four panel states. `PostEditorView.swift` gains four state vars, a toolbar button, the right-panel toggle, and an `executeEvaluation()` async function. `editor.html` gains `window.findAndSelectText(query)` which uses the existing `findMatches` utility.

**Tech Stack:** Swift 6, SwiftUI, WKWebView, AnthropicClient (existing), `findMatches` in `editor-transforms.js` (existing)

---

## Task 1: Data types + prompt builder — tests first

**Files:**
- Modify: `Tests/QuillTests/AIPromptBuilderTests.swift`
- Modify: `Sources/QuillKit/AI/AIPromptBuilder.swift`

- [ ] **Step 1: Write failing tests for `parseEvaluationResponse` and `evaluatePostPrompt`**

Add this new `@Suite` block at the bottom of `Tests/QuillTests/AIPromptBuilderTests.swift`, before the final `}`:

```swift
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
}

// MARK: - evaluatePostPrompt

@Suite struct EvaluatePostPromptTests {

    @Test func promptIncludesTitle() {
        let prompt = AIPromptBuilder.evaluatePostPrompt(title: "My Article", html: "<p>Body.</p>")
        #expect(prompt.contains("My Article"))
    }

    @Test func promptStripsHTMLTags() {
        let prompt = AIPromptBuilder.evaluatePostPrompt(title: "T", html: "<p>Hello <strong>world</strong></p>")
        #expect(!prompt.contains("<p>"))
        #expect(!prompt.contains("<strong>"))
        #expect(prompt.contains("Hello world"))
    }

    @Test func promptDecodesHTMLEntities() {
        let prompt = AIPromptBuilder.evaluatePostPrompt(title: "T", html: "<p>a &amp; b &lt;c&gt;</p>")
        #expect(prompt.contains("a & b <c>"))
    }

    @Test func promptNamesAllFiveCategories() {
        let prompt = AIPromptBuilder.evaluatePostPrompt(title: "T", html: "<p>x</p>")
        #expect(prompt.lowercased().contains("grammar"))
        #expect(prompt.lowercased().contains("clarity"))
        #expect(prompt.lowercased().contains("readability"))
        #expect(prompt.lowercased().contains("wordiness"))
        #expect(prompt.lowercased().contains("tone"))
    }

    @Test func promptIncludesSummaryAndFindingsFormatInstructions() {
        let prompt = AIPromptBuilder.evaluatePostPrompt(title: "T", html: "<p>x</p>")
        #expect(prompt.contains("SUMMARY:"))
        #expect(prompt.contains("FINDINGS:"))
        #expect(prompt.contains("QUOTE:"))
        #expect(prompt.contains("ISSUE:"))
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
swift test --filter EvaluationParserTests
swift test --filter EvaluatePostPromptTests
```

Expected: compile errors — `parseEvaluationResponse`, `evaluatePostPrompt`, `EvaluationFinding`, `EvaluationResult` do not exist yet.

- [ ] **Step 3: Add data types and implementation to `AIPromptBuilder.swift`**

Add the following at the top of `Sources/QuillKit/AI/AIPromptBuilder.swift`, after the `AIWritingOperation` enum:

```swift
public struct EvaluationFinding {
    public let quote: String
    public let issue: String
    public let suggestion: String?
}

public struct EvaluationResult {
    public let summary: String
    public let findings: [EvaluationFinding]
}
```

Then add these functions inside `public struct AIPromptBuilder`, after the existing `operationPrompt` function:

```swift
/// Prompt for evaluating the writing quality of a full post or page.
/// Strips HTML to plain text before sending to reduce token usage.
public static func evaluatePostPrompt(title: String, html: String) -> String {
    let body = stripHTML(html)
    return """
    You are a writing quality evaluator. Analyze the following blog post for: \
    grammar, clarity, readability, wordiness, and tone/voice consistency.

    Title: \(title)

    Content:
    \(body)

    Respond in this exact format:

    SUMMARY:
    <2–4 sentence prose critique of the overall writing quality>

    FINDINGS:
    QUOTE: "exact phrase from the title or content" | ISSUE: short label | SUGGESTION: rewrite (optional)

    Rules:
    - Quote exact phrases verbatim from the title or content — not paraphrases. \
      The quotes must match the text character-for-character.
    - ISSUE label should be one of: Grammar, Clarity, Readability, Wordiness, Passive Voice, Tone
    - SUGGESTION is optional — omit the pipe and SUGGESTION field if you have no specific rewrite
    - List only meaningful issues, not subjective stylistic preferences
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

        let suggestion = parts
            .first(where: { $0.uppercased().hasPrefix("SUGGESTION:") })
            .map { $0.replacingOccurrences(of: "SUGGESTION:", with: "", options: .caseInsensitive)
                      .trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }

        findings.append(EvaluationFinding(quote: quote, issue: issue, suggestion: suggestion))
    }

    return EvaluationResult(summary: summary, findings: findings)
}

private static func stripHTML(_ html: String) -> String {
    var text = html.replacingOccurrences(
        of: #"</(p|h[1-6]|li|blockquote|pre|div)>"#,
        with: "\n",
        options: .regularExpression
    )
    text = text.replacingOccurrences(of: #"<[^>]+(>|$)"#, with: " ", options: .regularExpression)
    text = text
        .replacingOccurrences(of: "&amp;",  with: "&")
        .replacingOccurrences(of: "&lt;",   with: "<")
        .replacingOccurrences(of: "&gt;",   with: ">")
        .replacingOccurrences(of: "&nbsp;", with: " ")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;",  with: "'")
    return text.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
swift test --filter EvaluationParserTests
swift test --filter EvaluatePostPromptTests
```

Expected: all tests PASS.

- [ ] **Step 5: Run the full Swift test suite to confirm no regressions**

```bash
swift test
```

Expected: 233+ tests, all passing.

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/AI/AIPromptBuilder.swift Tests/QuillTests/AIPromptBuilderTests.swift
git commit -m "feat: add EvaluationFinding, EvaluationResult, evaluatePostPrompt, parseEvaluationResponse"
```

---

## Task 2: JS `window.findAndSelectText` in editor.html

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` (insert after line ~2646, after `window.discardAIResult`)

- [ ] **Step 1: Add `window.findAndSelectText` to editor.html**

Find this block in `editor.html` (it ends around line 2646):

```javascript
    window.discardAIResult = () => {
      if (_aiOriginalHTML !== null) {
        editor.commands.setContent(_aiOriginalHTML)
        _aiOriginalHTML = null
        _aiFrom         = null
        _aiTo           = null
        _aiResultTo     = null
      }
      _aiInProgress = false
    }
```

Insert the following immediately after that closing `}`:

```javascript

    window.findAndSelectText = function(query) {
      if (!editor || !query) return
      const positions = []
      let text = ''
      editor.state.doc.descendants(function(node, pos) {
        if (!node.isText) return
        for (let i = 0; i < node.text.length; i++) {
          positions.push(pos + i)
          text += node.text[i]
        }
      })
      const matches = findMatches(text, query, false)
      if (!matches.length) return
      const m = matches[0]
      if (m.start >= positions.length || m.end - 1 >= positions.length) return
      const from = positions[m.start]
      const to = positions[m.end - 1] + 1
      editor.chain().setTextSelection({ from, to }).scrollIntoView().run()
    }
```

- [ ] **Step 2: Build and smoke-test manually**

```bash
./build.sh && open Quill.app
```

In the app: open a post with body text, open the browser console in the WebView (or use a temporary test via Swift), and verify `window.findAndSelectText` is defined and selects text when called with a known phrase. You can test via the app's existing JS evaluation by temporarily calling it from another action.

- [ ] **Step 3: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html
git commit -m "feat: add window.findAndSelectText for evaluation click-to-jump"
```

---

## Task 3: EvaluationPanel SwiftUI view

**Files:**
- Create: `Sources/QuillKit/Views/AI/EvaluationPanel.swift`

- [ ] **Step 1: Create `EvaluationPanel.swift`**

```swift
import SwiftUI

public enum EvaluationPanelState {
    case shortContent
    case loading
    case result(EvaluationResult)
    case error(String)
}

public struct EvaluationPanel: View {
    let state: EvaluationPanelState
    let onClose: () -> Void
    let onReEvaluate: () -> Void
    let onFindingSelected: (String) -> Void

    public var body: some View {
        VStack(spacing: 0) {
            header
            SoftHorizontalDivider()
            content
        }
        .frame(width: 260)
        .background(WarmSidebarBackground())
        .overlay(alignment: .leading) { PanelInteriorFade(from: .leading) }
    }

    private var header: some View {
        HStack {
            Text("Post Evaluation")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button("Close") { onClose() }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(WarmPanelHeaderBackground())
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .shortContent: shortContentView
        case .loading:      loadingView
        case .result(let r): resultView(r)
        case .error(let msg): errorView(msg)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Evaluating content…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var shortContentView: some View {
        VStack(spacing: 8) {
            Text("Add more content before evaluating.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func resultView(_ result: EvaluationResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(result.summary)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .padding(16)

                SoftHorizontalDivider()

                let countLabel = result.findings.isEmpty
                    ? "No specific issues found"
                    : "\(result.findings.count) finding\(result.findings.count == 1 ? "" : "s") — click to jump"

                Text(countLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, result.findings.isEmpty ? 12 : 8)

                if !result.findings.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(Array(result.findings.enumerated()), id: \.offset) { _, finding in
                            EvaluationFindingCard(
                                finding: finding,
                                onTap: { onFindingSelected(finding.quote) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }

                SoftHorizontalDivider()
                Button("↺  Re-evaluate") { onReEvaluate() }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text("Evaluation failed.")
                .font(.system(size: 12, weight: .medium))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { onReEvaluate() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct EvaluationFindingCard: View {
    let finding: EvaluationFinding
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(finding.issue.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.wpAmber)
                    .tracking(0.5)
                Text("\"\(finding.quote)\"")
                    .font(.system(size: 11))
                    .italic()
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let suggestion = finding.suggestion {
                    Text("→ \(suggestion)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.wpAmber.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.wpAmber.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build to confirm it compiles**

```bash
swift build 2>&1 | grep -E "error:|warning:" | head -20
```

Expected: no errors. Fix any that appear before proceeding.

- [ ] **Step 3: Commit**

```bash
git add Sources/QuillKit/Views/AI/EvaluationPanel.swift
git commit -m "feat: add EvaluationPanel SwiftUI view with loading/result/error/shortContent states"
```

---

## Task 4: Wire up PostEditorView

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift`

- [ ] **Step 1: Add evaluation state vars**

In `PostEditorView`, find the `// AI state` comment block (around line 40):

```swift
    // AI state
    @State private var isAISheetOpen: Bool = false
    @State private var showAIReplaceAlert: Bool = false
    @State private var currentSelectionRect: CGRect? = nil
    @State private var hasTextSelection: Bool = false
    @State private var editorWebView: WKWebView? = nil
    @State private var resultPanel: AIResultPanel = AIResultPanel()
```

Replace it with:

```swift
    // AI state
    @State private var isAISheetOpen: Bool = false
    @State private var showAIReplaceAlert: Bool = false
    @State private var currentSelectionRect: CGRect? = nil
    @State private var hasTextSelection: Bool = false
    @State private var editorWebView: WKWebView? = nil
    @State private var resultPanel: AIResultPanel = AIResultPanel()

    // Evaluation state
    @State private var showEvaluationPanel: Bool = false
    @State private var isEvaluating: Bool = false
    @State private var evaluationResult: EvaluationResult? = nil
    @State private var evaluationError: String? = nil
```

- [ ] **Step 2: Add the Evaluate toolbar button**

Find this block in the `toolbar` computed property (around line 282):

```swift
            if appState.aiEnabled {
                Divider().frame(height: 20)
                Button {
                    let trimmed = htmlContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    let titleIsEmpty = title.isEmpty || title == "Untitled"
                    let contentIsEmpty = titleIsEmpty && (trimmed.isEmpty || trimmed == "<p></p>")
                    if contentIsEmpty {
                        isAISheetOpen = true
                    } else {
                        showAIReplaceAlert = true
                    }
                } label: {
                    Text("✦")
                        .font(.system(size: 13))
                }
                .help("Generate post with Claude")
            }
```

Replace it with:

```swift
            if appState.aiEnabled {
                Divider().frame(height: 20)
                Button {
                    let trimmed = htmlContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    let titleIsEmpty = title.isEmpty || title == "Untitled"
                    let contentIsEmpty = titleIsEmpty && (trimmed.isEmpty || trimmed == "<p></p>")
                    if contentIsEmpty {
                        isAISheetOpen = true
                    } else {
                        showAIReplaceAlert = true
                    }
                } label: {
                    Text("✦")
                        .font(.system(size: 13))
                }
                .help("Generate post with Claude")
                Button {
                    showEvaluationPanel = true
                    evaluationResult = nil
                    evaluationError = nil
                    Task { await executeEvaluation() }
                } label: {
                    Image(systemName: "doc.badge.checkmark")
                        .font(.system(size: 13))
                }
                .help("Evaluate writing quality")
            }
```

- [ ] **Step 4: Replace the right-panel toggle to support EvaluationPanel**

Find this block in `body` (around line 137):

```swift
            if isSettingsOpen {
                SoftPanelBoundary()
                    .transition(.move(edge: .trailing))
                PostSettingsPanel(
                    settings: $settings,
                    postType: postType,
                    isLocalDraft: !isRemote,
                    categories: appState.categories,
                    tags: appState.tags,
                    pages: availableParentPages,
                    stats: stats
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSettingsOpen)
```

Replace it with:

```swift
            if showEvaluationPanel {
                SoftPanelBoundary()
                    .transition(.move(edge: .trailing))
                EvaluationPanel(
                    state: evaluationPanelState,
                    onClose: {
                        showEvaluationPanel = false
                        evaluationResult = nil
                        evaluationError = nil
                    },
                    onReEvaluate: { Task { await executeEvaluation() } },
                    onFindingSelected: { quote in
                        guard let data = try? JSONEncoder().encode(quote),
                              let json = String(data: data, encoding: .utf8) else { return }
                        editorWebView?.evaluateJavaScript(
                            "window.findAndSelectText(\(json))", completionHandler: nil)
                    }
                )
                .transition(.move(edge: .trailing))
            } else if isSettingsOpen {
                SoftPanelBoundary()
                    .transition(.move(edge: .trailing))
                PostSettingsPanel(
                    settings: $settings,
                    postType: postType,
                    isLocalDraft: !isRemote,
                    categories: appState.categories,
                    tags: appState.tags,
                    pages: availableParentPages,
                    stats: stats
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSettingsOpen)
        .animation(.easeInOut(duration: 0.2), value: showEvaluationPanel)
```

- [ ] **Step 5: Reset evaluation state when switching items**

Find this line (around line 210):

```swift
        .onChange(of: item.id) { _ in contentLoaded = false }
```

Replace it with:

```swift
        .onChange(of: item.id) { _ in
            contentLoaded = false
            showEvaluationPanel = false
            evaluationResult = nil
            evaluationError = nil
        }
```

- [ ] **Step 6: Add `executeEvaluation()` and `evaluationPanelState` in a new MARK section**

Find the `// MARK: - AI selection handling` section (around line 785) and insert the following immediately before it:

```swift
    // MARK: - Evaluation

    private var evaluationPanelState: EvaluationPanelState {
        if stats.words < 100 { return .shortContent }
        if isEvaluating { return .loading }
        if let error = evaluationError { return .error(error) }
        if let result = evaluationResult { return .result(result) }
        return .loading
    }

    @MainActor
    private func executeEvaluation() async {
        guard let aiSettings = appState.aiSettings else { return }
        guard stats.words >= 100 else { return }

        isEvaluating = true
        evaluationResult = nil
        evaluationError = nil

        let prompt = AIPromptBuilder.evaluatePostPrompt(title: title, html: htmlContent)
        let system = AIPromptBuilder.systemPrompt(styleGuide: nil)
        let client = AnthropicClient(apiKey: aiSettings.apiKey)

        do {
            let responseText = try await client.complete(
                userMessage: prompt,
                systemPrompt: system,
                useWebSearch: false
            ).text
            if let result = AIPromptBuilder.parseEvaluationResponse(responseText) {
                evaluationResult = result
            } else {
                evaluationError = "Could not parse evaluation response."
            }
        } catch {
            evaluationError = error.localizedDescription
        }

        isEvaluating = false
    }

```

- [ ] **Step 7: Build to confirm it compiles**

```bash
swift build 2>&1 | grep -E "error:" | head -20
```

Expected: no errors.

- [ ] **Step 8: Run full test suite**

```bash
swift test
```

Expected: all tests passing.

- [ ] **Step 9: Commit**

```bash
git add Sources/QuillKit/Views/Editor/PostEditorView.swift
git commit -m "feat: wire evaluation panel into PostEditorView with toolbar button and right-panel toggle"
```

---

## Task 5: Full build and manual verification

- [ ] **Step 1: Build and open the app**

```bash
./build.sh && open Quill.app
```

- [ ] **Step 2: Verify short-content state**

Open a post with fewer than 100 words. Click the `doc.badge.checkmark` toolbar button (visible only when AI is enabled). The right panel should show "Add more content before evaluating." without hitting the API.

- [ ] **Step 3: Verify loading and results states**

Open a post with substantial content (>100 words). Click the Evaluate button. Confirm:
- The panel opens immediately showing the spinner and "Evaluating content…"
- After the Claude call completes, the spinner is replaced with a prose summary and finding cards
- The finding count label is correct ("N findings — click to jump")

- [ ] **Step 4: Verify click-to-jump**

Click a finding card. Confirm the editor scrolls to and selects the quoted phrase. If the phrase is not found (e.g., after editing), the click should be a no-op with no crash.

- [ ] **Step 5: Verify re-evaluate**

Click "↺  Re-evaluate" at the bottom of the panel. Confirm the spinner reappears and a new result loads.

- [ ] **Step 6: Verify close restores Post Settings**

If Post Settings was open before clicking Evaluate, close the evaluation panel and confirm Post Settings returns. If settings was not open, confirm the panel simply disappears.

- [ ] **Step 7: Verify switching posts resets the panel**

While the evaluation panel is open, switch to a different post in the sidebar. Confirm the panel closes.

- [ ] **Step 8: Verify pages work**

Open a page (not a post) and run the evaluation. The loading message should say "Evaluating content…" (not "post").

- [ ] **Step 9: Final commit if any fixes were needed**

```bash
git add -p
git commit -m "fix: post evaluation manual testing corrections"
```
