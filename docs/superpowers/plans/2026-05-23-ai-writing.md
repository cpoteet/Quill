# AI Writing Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate Claude Haiku into Quill as an AI writing assistant with two modes — generating a full post from a prompt, and running operations (Make Longer, Make Shorter, Convert to Table, Convert to List) on selected text with inline accept/discard preview.

**Architecture:** A new `AI/` layer contains `AISettings` (file-backed config), `AnthropicClient` (URLSession-based API client), and `AIPromptBuilder` (prompt construction with style samples). The editor gains a JS selection bridge that reports selections to Swift, which shows a floating non-activating `NSPanel` pill. Results appear inline in the editor via a Tiptap custom mark with a second `NSPanel` accept/discard bar.

**Tech Stack:** Swift 6, SwiftUI, AppKit (NSPanel), WKWebView JS bridge, Anthropic Messages API (claude-haiku-4-5), Tiptap 2.x custom mark extension.

---

## File Structure

**New files:**
- `Sources/QuillKit/AI/AISettings.swift` — `AISettings` Codable struct + `AISettingsStore` (load/save/delete)
- `Sources/QuillKit/AI/AnthropicClient.swift` — API client, all Codable request/response types
- `Sources/QuillKit/AI/AIPromptBuilder.swift` — system prompt + per-operation prompt construction
- `Sources/QuillKit/Views/AI/SamplePostPickerSheet.swift` — checklist sheet for selecting style-sample posts
- `Sources/QuillKit/Views/AI/GeneratePostSheet.swift` — generate-from-prompt modal sheet
- `Sources/QuillKit/Views/AI/SelectionPillPanel.swift` — non-activating NSPanel with four operation buttons
- `Sources/QuillKit/Views/AI/AIResultPanel.swift` — non-activating NSPanel with Accept / Discard

**Modified files:**
- `Sources/QuillKit/App/AppState.swift` — add `aiSettings: AISettings?`, `aiEnabled: Bool`
- `Sources/QuillKit/Views/Settings/PreferencesView.swift` — add AI Writing settings section
- `Sources/QuillKit/Views/Editor/EditorView.swift` — register `selectionChanged` message handler; add `onSelectionChanged` + `onAIOperation` callbacks
- `Sources/QuillKit/Views/Editor/EditorCoordinator.swift` — handle `selectionChanged` message; add `onSelectionChanged` closure
- `Sources/QuillKit/Resources/editor.html` — selection detection JS; AI bridge globals (`beginAIOperation`, `showAIResult`, `acceptAIResult`, `discardAIResult`); `AIResult` custom Tiptap mark; highlight CSS
- `Sources/QuillKit/Views/Editor/PostEditorView.swift` — ✦ toolbar button; AI state properties; generate + operation execution logic

---

## Task 1: AISettings model and store

**Files:**
- Create: `Sources/QuillKit/AI/AISettings.swift`

- [ ] **Step 1: Create the file**

```swift
import Foundation

public struct AISettings: Codable {
    public var apiKey: String
    public var samplePostIDs: [Int]
    public var webSearchEnabled: Bool

    public init(apiKey: String = "", samplePostIDs: [Int] = [], webSearchEnabled: Bool = true) {
        self.apiKey = apiKey
        self.samplePostIDs = samplePostIDs
        self.webSearchEnabled = webSearchEnabled
    }
}

public struct AISettingsStore {
    private static var fileURL: URL {
        get throws {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dir = base.appendingPathComponent("Quill", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("ai_settings.json")
        }
    }

    public static func save(_ settings: AISettings) throws {
        let url = try fileURL
        let data = try JSONEncoder().encode(settings)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }

    public static func load() throws -> AISettings? {
        let url = try fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AISettings.self, from: data)
    }

    public static func delete() throws {
        let url = try fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
./build.sh
```
Expected: exits 0, produces `Quill.app`.

- [ ] **Step 3: Commit**

```bash
git add Sources/QuillKit/AI/AISettings.swift
git commit -m "feat(ai): add AISettings model and AISettingsStore"
```

---

## Task 2: AnthropicClient

**Files:**
- Create: `Sources/QuillKit/AI/AnthropicClient.swift`

- [ ] **Step 1: Create the file with all request/response types and the client**

```swift
import Foundation

// MARK: - Request types

private struct AnthropicRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: [SystemBlock]
    let messages: [AnthropicMessage]
    let tools: [AnthropicTool]?

    enum CodingKeys: String, CodingKey {
        case model, system, messages, tools
        case maxTokens = "max_tokens"
    }
}

private struct SystemBlock: Encodable {
    let type: String = "text"
    let text: String
    let cacheControl: CacheControl

    enum CodingKeys: String, CodingKey {
        case type, text
        case cacheControl = "cache_control"
    }
}

private struct CacheControl: Encodable {
    let type: String = "ephemeral"
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: String
}

private struct AnthropicTool: Encodable {
    let type: String
    let name: String
}

// MARK: - Response types

private struct AnthropicResponse: Decodable {
    let content: [ContentBlock]
    let stopReason: String

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}

private struct ContentBlock: Decodable {
    let type: String
    let text: String?
}

// MARK: - Errors

public enum AnthropicError: LocalizedError {
    case httpError(Int, String)
    case noTextContent
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .httpError(let code, let msg): return "API error \(code): \(msg)"
        case .noTextContent: return "Claude returned no text content."
        case .invalidResponse: return "Unexpected response from API."
        }
    }
}

// MARK: - Client

public struct AnthropicClient {
    public let apiKey: String

    private static let session: URLSession = {
        URLSession(configuration: .ephemeral)
    }()

    /// Sends a single-turn request and returns the text response.
    /// - Parameters:
    ///   - userMessage: The user turn content.
    ///   - systemPrompt: System instructions (cached with ephemeral cache_control).
    ///   - useWebSearch: Whether to include the web_search tool.
    public func complete(
        userMessage: String,
        systemPrompt: String,
        useWebSearch: Bool
    ) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        // Beta headers
        var betas: [String] = ["prompt-caching-2024-07-31"]
        if useWebSearch { betas.append("web-search-2025-03-05") }
        request.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")

        let tools: [AnthropicTool]? = useWebSearch
            ? [AnthropicTool(type: "web_search_20250305", name: "web_search")]
            : nil

        let body = AnthropicRequest(
            model: "claude-haiku-4-5",
            maxTokens: 4096,
            system: [SystemBlock(text: systemPrompt, cacheControl: CacheControl())],
            messages: [AnthropicMessage(role: "user", content: userMessage)],
            tools: tools
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, urlResponse) = try await Self.session.data(for: request)

        guard let http = urlResponse as? HTTPURLResponse else { throw AnthropicError.invalidResponse }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
            throw AnthropicError.httpError(http.statusCode, msg)
        }

        let response = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let text = response.content.first(where: { $0.type == "text" })?.text else {
            throw AnthropicError.noTextContent
        }
        return text
    }
}
```

- [ ] **Step 2: Verify build**

```bash
./build.sh
```
Expected: exits 0.

- [ ] **Step 3: Commit**

```bash
git add Sources/QuillKit/AI/AnthropicClient.swift
git commit -m "feat(ai): add AnthropicClient with prompt-caching and web-search support"
```

---

## Task 3: AIPromptBuilder

**Files:**
- Create: `Sources/QuillKit/AI/AIPromptBuilder.swift`

- [ ] **Step 1: Define the operation enum and prompt builder**

```swift
import Foundation

public enum AIWritingOperation {
    case makeLonger
    case makeShorter
    case convertToTable
    case convertToList
}

public struct AIPromptBuilder {

    /// System prompt, optionally incorporating style sample posts.
    /// Pass stripped plain-text or HTML content of sample posts.
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
            instruction = "Expand and elaborate on this content, adding more detail, examples, and explanation while preserving the author's voice. Return the expanded version as HTML."
        case .makeShorter:
            instruction = "Condense this content to its essential points, removing redundancy while preserving meaning and the author's voice. Return the shortened version as HTML."
        case .convertToTable:
            instruction = "Convert this content into an HTML table. Use <table>, <thead>, <tbody>, <tr>, <th>, and <td> tags. Identify logical columns from the content."
        case .convertToList:
            instruction = "Convert this content into an HTML unordered list using <ul> and <li> tags. Each distinct point or item becomes a list item."
        }
        return "\(instruction)\n\nContent to transform:\n\(selectedHTML)"
    }
}
```

- [ ] **Step 2: Verify build**

```bash
./build.sh
```
Expected: exits 0.

- [ ] **Step 3: Commit**

```bash
git add Sources/QuillKit/AI/AIPromptBuilder.swift
git commit -m "feat(ai): add AIPromptBuilder with generate and operation prompts"
```

---

## Task 4: AppState updates

**Files:**
- Modify: `Sources/QuillKit/App/AppState.swift`

- [ ] **Step 1: Read the current file**

Read `Sources/QuillKit/App/AppState.swift` to confirm current property list before editing.

- [ ] **Step 2: Add AI properties**

After the `mediaError` line (currently the last `@Published` property), add:

```swift
    @Published public var aiSettings: AISettings?

    public var aiEnabled: Bool {
        guard let settings = aiSettings, !settings.apiKey.isEmpty else { return false }
        return true
    }
```

- [ ] **Step 3: Load AI settings on init**

Replace the existing `public init() {}` with:

```swift
    public init() {
        aiSettings = try? AISettingsStore.load()
    }
```

- [ ] **Step 4: Verify build**

```bash
./build.sh
```
Expected: exits 0.

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/App/AppState.swift
git commit -m "feat(ai): add aiSettings and aiEnabled to AppState"
```

---

## Task 5: SamplePostPickerSheet

**Files:**
- Create: `Sources/QuillKit/Views/AI/SamplePostPickerSheet.swift`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

/// Sheet that lets the user pick 2–5 WordPress posts as writing-style samples.
struct SamplePostPickerSheet: View {
    let posts: [WPPost]
    @Binding var selectedIDs: [Int]
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Choose Style Samples")
                    .font(.headline)
                Spacer()
                Button("Done") { onDone() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedIDs.isEmpty)
            }
            .padding()

            Divider()

            Text("Select 2–5 posts that represent your writing style. Claude will match your voice when generating content.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)

            if posts.isEmpty {
                Spacer()
                Text("No posts available.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(posts) { post in
                            let isSelected = selectedIDs.contains(post.id)
                            let atLimit = selectedIDs.count >= 5 && !isSelected
                            Button {
                                if isSelected {
                                    selectedIDs.removeAll { $0 == post.id }
                                } else if !atLimit {
                                    selectedIDs.append(post.id)
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                    Text(post.title.rendered.isEmpty ? "Untitled" : post.title.rendered)
                                        .foregroundStyle(atLimit && !isSelected ? .secondary : .primary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(atLimit)
                            Divider().padding(.leading)
                        }
                    }
                }
            }

            if selectedIDs.count >= 5 {
                Text("Maximum 5 samples selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: 440, height: 480)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
./build.sh
```
Expected: exits 0.

- [ ] **Step 3: Commit**

```bash
git add Sources/QuillKit/Views/AI/SamplePostPickerSheet.swift
git commit -m "feat(ai): add SamplePostPickerSheet for style sample selection"
```

---

## Task 6: AI Writing section in PreferencesView

**Files:**
- Modify: `Sources/QuillKit/Views/Settings/PreferencesView.swift`

- [ ] **Step 1: Read the current file**

Read `Sources/QuillKit/Views/Settings/PreferencesView.swift` to confirm its structure before editing.

- [ ] **Step 2: Add AI state properties**

After the existing `@State private var saveSuccess: Bool = false` line, add:

```swift
    // AI Writing settings
    @State private var aiAPIKey: String = ""
    @State private var aiSamplePostIDs: [Int] = []
    @State private var aiWebSearchEnabled: Bool = true
    @State private var isSamplePickerOpen: Bool = false
    @State private var aiSaveSuccess: Bool = false
    @EnvironmentObject private var appState: AppState
```

- [ ] **Step 3: Add AI section to body**

In the `body` VStack, after the closing `}` of the existing `HStack` that contains the Save button, add:

```swift
            Divider()

            settingSection(title: "AI Writing") {
                formRow(label: "Anthropic API Key") {
                    SecureField("sk-ant-…", text: $aiAPIKey)
                        .textFieldStyle(.plain)
                        .inputFieldStyle()
                }
                Divider().padding(.leading, 12)
                formRow(label: "Writing Style") {
                    HStack {
                        Button("Choose Sample Posts…") { isSamplePickerOpen = true }
                            .buttonStyle(.bordered)
                            .disabled(appState.posts.isEmpty)
                        Text(aiSamplePostIDs.isEmpty
                             ? "No samples selected"
                             : "\(aiSamplePostIDs.count) post\(aiSamplePostIDs.count == 1 ? "" : "s") selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider().padding(.leading, 12)
                formRow(label: "Web Search") {
                    Toggle("Allow Claude to search the web", isOn: $aiWebSearchEnabled)
                        .toggleStyle(.switch)
                }
            }
            .sheet(isPresented: $isSamplePickerOpen) {
                SamplePostPickerSheet(
                    posts: appState.posts,
                    selectedIDs: $aiSamplePostIDs,
                    onDone: { isSamplePickerOpen = false }
                )
            }

            HStack {
                if aiSaveSuccess {
                    Text("AI settings saved.").foregroundStyle(.green).font(.caption)
                }
                Spacer()
                Button("Save AI Settings") { saveAISettings() }
                    .buttonStyle(.borderedProminent)
                    .disabled(aiAPIKey.isEmpty)
            }
```

- [ ] **Step 4: Add loadExistingAI() and saveAISettings() methods**

After the existing `save()` method, add:

```swift
    private func loadExistingAI() {
        guard let settings = try? AISettingsStore.load() else { return }
        aiAPIKey = settings.apiKey
        aiSamplePostIDs = settings.samplePostIDs
        aiWebSearchEnabled = settings.webSearchEnabled
    }

    private func saveAISettings() {
        let settings = AISettings(
            apiKey: aiAPIKey,
            samplePostIDs: aiSamplePostIDs,
            webSearchEnabled: aiWebSearchEnabled
        )
        try? AISettingsStore.save(settings)
        appState.aiSettings = settings
        aiSaveSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { aiSaveSuccess = false }
    }
```

- [ ] **Step 5: Call loadExistingAI in onAppear**

The existing `.onAppear(perform: loadExisting)` needs to also call `loadExistingAI()`. Replace it with:

```swift
        .onAppear {
            loadExisting()
            loadExistingAI()
        }
```

- [ ] **Step 6: Verify build**

```bash
./build.sh
```
Expected: exits 0.

- [ ] **Step 7: Commit**

```bash
git add Sources/QuillKit/Views/Settings/PreferencesView.swift Sources/QuillKit/Views/AI/SamplePostPickerSheet.swift
git commit -m "feat(ai): add AI Writing section to PreferencesView"
```

---

## Task 7: editor.html — selection detection and AI JS bridge

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`

- [ ] **Step 1: Add AI highlight CSS**

In the `<style>` block, just before the closing `</style>` tag (before the `#drop-overlay` section works, but end of the style block is cleanest), add:

```css
    /* ── AI writing ─────────────────────────────────── */
    .ai-loading {
      background: rgba(120, 120, 128, 0.15);
      border-radius: 3px;
      animation: ai-pulse 1.1s ease-in-out infinite;
    }
    @keyframes ai-pulse {
      0%, 100% { opacity: 0.35; }
      50% { opacity: 0.85; }
    }
    .ai-result {
      background: rgba(34, 197, 94, 0.18);
      border-radius: 2px;
    }
    body.dark .ai-result { background: rgba(34, 197, 94, 0.22); }
```

- [ ] **Step 2: Add AIResult custom Tiptap mark**

In the `<script type="module">` block, after the existing imports (after the `Placeholder` import line), add:

```javascript
    import { Mark } from 'https://esm.sh/@tiptap/core@2'

    const AIResult = Mark.create({
      name: 'aiResult',
      inclusive: false,
      addAttributes() {
        return {
          class: {
            default: 'ai-result',
            parseHTML: el => el.getAttribute('class'),
            renderHTML: attrs => ({ class: attrs.class }),
          },
        }
      },
      parseHTML() {
        return [
          { tag: 'span[class="ai-result"]' },
          { tag: 'span[class="ai-loading"]' },
        ]
      },
      renderHTML({ HTMLAttributes }) {
        return ['span', HTMLAttributes, 0]
      },
    })
```

- [ ] **Step 3: Add AIResult to the editor extensions list**

Find the `extensions: [` array in the Editor constructor. Add `AIResult,` after the `Placeholder` extension entry. The extensions array should end up including it alongside StarterKit, Underline, etc.

- [ ] **Step 4: Add selection change listener**

In the editor's `onCreate` callback (or after the `editor` is initialised — look for where `window.setContent` etc. are defined), add a `selectionchange` listener:

```javascript
    document.addEventListener('selectionchange', () => {
      if (!editor) return
      const sel = window.getSelection()
      if (!sel || sel.isCollapsed || sel.toString().length < 10) {
        window.webkit?.messageHandlers?.selectionChanged?.postMessage(null)
        return
      }
      const range = sel.getRangeAt(0)
      const rect  = range.getBoundingClientRect()
      window.webkit?.messageHandlers?.selectionChanged?.postMessage({
        text: sel.toString(),
        rect: { x: rect.left, y: rect.top, width: rect.width, height: rect.height },
      })
    })
```

- [ ] **Step 5: Add AI bridge globals**

After the existing `window.removeLink` line, add:

```javascript
    // ── AI writing bridge ────────────────────────────
    let _aiOriginalHTML = null
    let _aiFrom = null
    let _aiTo   = null

    window.beginAIOperation = () => {
      const { from, to } = editor.state.selection
      if (from === to) return false
      _aiFrom = from
      _aiTo   = to
      _aiOriginalHTML = editor.getHTML()
      // Replace selected range with animated loading placeholder
      editor.chain().focus()
        .insertContentAt({ from, to }, '<span class="ai-loading">  Rewriting…  </span>')
        .run()
      return true
    }

    window.showAIResult = (html) => {
      // Restore original, then replace the same range with highlighted result
      editor.commands.setContent(_aiOriginalHTML)
      editor.chain().focus()
        .insertContentAt({ from: _aiFrom, to: _aiTo },
          '<span class="ai-result">' + html + '</span>')
        .run()
    }

    window.acceptAIResult = () => {
      // Unwrap the .ai-result span via DOMParser, then setContent
      const parser = new DOMParser()
      const dom = parser.parseFromString(editor.getHTML(), 'text/html')
      dom.querySelectorAll('.ai-result').forEach(el => el.replaceWith(...el.childNodes))
      editor.commands.setContent(dom.body.innerHTML)
      _aiOriginalHTML = null
    }

    window.discardAIResult = () => {
      if (_aiOriginalHTML !== null) {
        editor.commands.setContent(_aiOriginalHTML)
        _aiOriginalHTML = null
      }
    }
```

- [ ] **Step 6: Verify build**

```bash
./build.sh
```
Expected: exits 0.

- [ ] **Step 7: Smoke test selection in running app**

Open `Quill.app`, open a post, select 15+ characters of text. Open Console.app, filter for `selectionChanged`. Confirm JS sends the message (you won't see the pill yet, but the message should appear or at least not crash).

- [ ] **Step 8: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html
git commit -m "feat(ai): add selection detection and AI JS bridge to editor.html"
```

---

## Task 8: EditorCoordinator and EditorView — selection wiring

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/EditorCoordinator.swift`
- Modify: `Sources/QuillKit/Views/Editor/EditorView.swift`

- [ ] **Step 1: Add selectionChanged callback to EditorCoordinator**

In `EditorCoordinator`, after `var onSearchLinks`:

```swift
    var onSelectionChanged: ((CGRect?) -> Void)?
```

- [ ] **Step 2: Handle selectionChanged message in EditorCoordinator**

In `userContentController(_:didReceive:)`, add a new `case` before `default:`:

```swift
        case "selectionChanged":
            DispatchQueue.main.async {
                if let body = message.body as? [String: Any],
                   let rectMap = body["rect"] as? [String: Any],
                   let x = rectMap["x"] as? Double,
                   let y = rectMap["y"] as? Double,
                   let w = rectMap["width"] as? Double,
                   let h = rectMap["height"] as? Double {
                    self.onSelectionChanged?(CGRect(x: x, y: y, width: w, height: h))
                } else {
                    self.onSelectionChanged?(nil)
                }
            }
```

- [ ] **Step 3: Register selectionChanged handler in EditorView.makeNSView**

In `EditorView.makeNSView(context:)`, after the existing `config.userContentController.add` lines, add:

```swift
        config.userContentController.add(context.coordinator, name: "selectionChanged")
```

- [ ] **Step 4: Add onSelectionChanged parameter to EditorView**

In `EditorView`:

Add the property after `onRequestMediaSizes`:
```swift
    var onSelectionChanged: ((CGRect?) -> Void)?
```

Add the parameter to `init`:
```swift
        onSelectionChanged: ((CGRect?) -> Void)? = nil,
```

And store it:
```swift
        self.onSelectionChanged = onSelectionChanged
```

Wire it in `makeNSView` after `context.coordinator.onRequestMediaSizes = onRequestMediaSizes`:
```swift
        context.coordinator.onSelectionChanged = onSelectionChanged
```

And in `updateNSView` after the existing coordinator updates:
```swift
        context.coordinator.onSelectionChanged = onSelectionChanged
```

- [ ] **Step 5: Verify build**

```bash
./build.sh
```
Expected: exits 0.

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/Views/Editor/EditorCoordinator.swift Sources/QuillKit/Views/Editor/EditorView.swift
git commit -m "feat(ai): wire selectionChanged message handler through EditorCoordinator and EditorView"
```

---

## Task 9: SelectionPillPanel

**Files:**
- Create: `Sources/QuillKit/Views/AI/SelectionPillPanel.swift`

- [ ] **Step 1: Create the file**

```swift
import AppKit
import SwiftUI

/// Non-activating floating pill that appears above a text selection with four AI operation buttons.
final class SelectionPillPanel: NSPanel {

    private var onOperation: ((AIWritingOperation) -> Void)?
    private var hostingController: NSHostingController<SelectionPillView>?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 36),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .floating
        animationBehavior = .none
    }

    func show(
        selectionRect jsRect: CGRect,
        in webView: NSView,
        onOperation: @escaping (AIWritingOperation) -> Void
    ) {
        self.onOperation = onOperation

        let view = SelectionPillView { [weak self] op in
            self?.orderOut(nil)
            onOperation(op)
        }
        let hc = NSHostingController(rootView: view)
        hc.sizingOptions = .preferredContentSize
        contentViewController = hc
        hostingController = hc

        // Size the panel to the hosting content
        let size = hc.view.fittingSize
        setContentSize(size)

        position(jsRect: jsRect, in: webView)

        alphaValue = 0
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 1
        }
    }

    func hide() {
        orderOut(nil)
    }

    private func position(jsRect: CGRect, in webView: NSView) {
        guard let window = webView.window else { return }

        // WKWebView is flipped: jsRect.y is distance from top-left of the webView.
        // Convert to AppKit coordinates (origin bottom-left).
        let flippedY = webView.bounds.height - jsRect.origin.y  // top edge of selection in AppKit coords
        let selectionInWebView = NSRect(
            x: jsRect.origin.x,
            y: flippedY - jsRect.height,          // bottom edge
            width: jsRect.width,
            height: jsRect.height
        )
        let selectionInWindow = webView.convert(selectionInWebView, to: nil)
        let selectionOnScreen = window.convertToScreen(selectionInWindow)

        let panelSize = frame.size
        let x = selectionOnScreen.midX - panelSize.width / 2
        let y = selectionOnScreen.maxY + 8   // 8pt above selection top edge
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - SwiftUI pill content

private struct SelectionPillView: View {
    let onOperation: (AIWritingOperation) -> Void

    var body: some View {
        HStack(spacing: 2) {
            pillButton("Make Longer",       op: .makeLonger)
            separator
            pillButton("Make Shorter",      op: .makeShorter)
            separator
            pillButton("Convert to Table",  op: .convertToTable)
            separator
            pillButton("Convert to List",   op: .convertToList)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                )
        )
        .padding(6) // room for shadow
    }

    private var separator: some View {
        Divider().frame(height: 16)
    }

    private func pillButton(_ label: String, op: AIWritingOperation) -> some View {
        Button(label) { onOperation(op) }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
    }
}
```

- [ ] **Step 2: Verify build**

```bash
./build.sh
```
Expected: exits 0.

- [ ] **Step 3: Commit**

```bash
git add Sources/QuillKit/Views/AI/SelectionPillPanel.swift
git commit -m "feat(ai): add SelectionPillPanel floating NSPanel"
```

---

## Task 10: AIResultPanel

**Files:**
- Create: `Sources/QuillKit/Views/AI/AIResultPanel.swift`

- [ ] **Step 1: Create the file**

```swift
import AppKit
import SwiftUI

/// Non-activating floating bar that appears below an AI result with Accept / Discard buttons.
final class AIResultPanel: NSPanel {

    private var onAccept: (() -> Void)?
    private var onDiscard: (() -> Void)?
    private var eventMonitor: Any?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 36),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .floating
        animationBehavior = .none
    }

    func show(
        belowRect jsRect: CGRect,
        in webView: NSView,
        onAccept: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.onAccept = onAccept
        self.onDiscard = onDiscard

        let view = AIResultBarView(
            onAccept: { [weak self] in self?.finish(accepted: true) },
            onDiscard: { [weak self] in self?.finish(accepted: false) }
        )
        let hc = NSHostingController(rootView: view)
        hc.sizingOptions = .preferredContentSize
        contentViewController = hc

        let size = hc.view.fittingSize
        setContentSize(size)
        position(jsRect: jsRect, in: webView)
        orderFront(nil)

        // Monitor keyboard (Return = accept, Escape = discard) and click-away (discard)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 36 { // Return
                    self.finish(accepted: true)
                    return nil
                } else if event.keyCode == 53 { // Escape
                    self.finish(accepted: false)
                    return nil
                }
            } else if event.type == .leftMouseDown {
                // Click outside this panel → discard
                if event.window !== self {
                    self.finish(accepted: false)
                }
            }
            return event
        }
    }

    func dismiss() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        orderOut(nil)
    }

    private func finish(accepted: Bool) {
        dismiss()
        if accepted { onAccept?() } else { onDiscard?() }
    }

    private func position(jsRect: CGRect, in webView: NSView) {
        guard let window = webView.window else { return }

        // jsRect is the bounding rect of the highlighted result region (AI highlight).
        // Position the bar 8pt below the bottom edge of the rect.
        let flippedY = webView.bounds.height - jsRect.origin.y
        let rectInWebView = NSRect(
            x: jsRect.origin.x,
            y: flippedY - jsRect.height,
            width: jsRect.width,
            height: jsRect.height
        )
        let rectInWindow = webView.convert(rectInWebView, to: nil)
        let rectOnScreen = window.convertToScreen(rectInWindow)

        let panelSize = frame.size
        let x = rectOnScreen.midX - panelSize.width / 2
        let y = rectOnScreen.minY - panelSize.height - 8  // 8pt below result bottom edge
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - SwiftUI bar content

private struct AIResultBarView: View {
    let onAccept: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                onAccept()
            } label: {
                Label("Accept", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut(.return, modifiers: [])

            Button {
                onDiscard()
            } label: {
                Label("Discard", systemImage: "xmark")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                )
        )
        .padding(6)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
./build.sh
```
Expected: exits 0.

- [ ] **Step 3: Commit**

```bash
git add Sources/QuillKit/Views/AI/AIResultPanel.swift
git commit -m "feat(ai): add AIResultPanel floating NSPanel with accept/discard"
```

---

## Task 11: GeneratePostSheet and toolbar button

**Files:**
- Create: `Sources/QuillKit/Views/AI/GeneratePostSheet.swift`
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift`

- [ ] **Step 1: Create GeneratePostSheet**

```swift
import SwiftUI

struct GeneratePostSheet: View {
    let aiSettings: AISettings
    let samplePosts: [WPPost]            // fetched fresh for style context
    var onResult: (String, String) -> Void   // (title, html)
    var onCancel: () -> Void

    @State private var prompt: String = ""
    @State private var isGenerating: Bool = false
    @State private var statusText: String = ""
    @State private var errorText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Generate Post with Claude")
                .font(.headline)

            TextEditor(text: $prompt)
                .font(.body)
                .frame(minHeight: 80, maxHeight: 160)
                .overlay(
                    Group {
                        if prompt.isEmpty {
                            Text("Describe the post you want to write…")
                                .foregroundStyle(.secondary)
                                .padding(5)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                )
                .disabled(isGenerating)

            if isGenerating {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text(statusText.isEmpty ? "Writing…" : statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = errorText {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(isGenerating)
                Button("Generate") {
                    Task { await generate() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || isGenerating)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func generate() async {
        isGenerating = true
        errorText = nil
        statusText = aiSettings.webSearchEnabled ? "Searching the web…" : "Writing…"

        do {
            // Fetch sample post contents fresh from WordPress
            var sampleContents: [String] = []
            if !aiSettings.samplePostIDs.isEmpty {
                // Use the already-loaded posts that match the IDs; strip HTML tags for cleaner style input
                for id in aiSettings.samplePostIDs {
                    if let post = samplePosts.first(where: { $0.id == id }) {
                        let stripped = post.content.rendered
                            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !stripped.isEmpty { sampleContents.append(stripped) }
                    }
                }
            }

            statusText = "Writing…"
            let client = AnthropicClient(apiKey: aiSettings.apiKey)
            let system = AIPromptBuilder.systemPrompt(samplePostContents: sampleContents)
            let userMsg = AIPromptBuilder.generatePostPrompt(userPrompt: prompt)
            let response = try await client.complete(
                userMessage: userMsg,
                systemPrompt: system,
                useWebSearch: aiSettings.webSearchEnabled
            )

            guard let parsed = AIPromptBuilder.parseGenerateResponse(response) else {
                errorText = "Claude returned an unexpected format. Please try again."
                isGenerating = false
                return
            }

            isGenerating = false
            onResult(parsed.title, parsed.html)
        } catch {
            errorText = error.localizedDescription
            isGenerating = false
        }
    }
}
```

- [ ] **Step 2: Add AI state properties to PostEditorView**

Read `Sources/QuillKit/Views/Editor/PostEditorView.swift`. After `@State private var cleanContent: String = ""`, add:

```swift
    // AI state
    @State private var isAISheetOpen: Bool = false
    @State private var showAIReplaceAlert: Bool = false
    @State private var selectionPill: SelectionPillPanel? = nil
    @State private var resultPanel: AIResultPanel? = nil
    @State private var currentSelectionRect: CGRect? = nil
```

- [ ] **Step 3: Add ✦ toolbar button**

In the `toolbar` computed property, after the existing settings sidebar button (`Image(systemName: "sidebar.right")`), add:

```swift
            if appState.aiEnabled {
                Divider().frame(height: 20)
                Button {
                    if (title.isEmpty && htmlContent.isEmpty) {
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

- [ ] **Step 4: Add sheet and alert modifiers to PostEditorView body**

After the existing `.toast(message: $toastMessage)` modifier, add:

```swift
        .alert("Replace Content?", isPresented: $showAIReplaceAlert) {
            Button("Continue") { isAISheetOpen = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace your current title and content. Continue?")
        }
        .sheet(isPresented: $isAISheetOpen) {
            if let settings = appState.aiSettings {
                GeneratePostSheet(
                    aiSettings: settings,
                    samplePosts: appState.posts
                ) { generatedTitle, generatedHTML in
                    title = generatedTitle
                    htmlContent = generatedHTML
                    isAISheetOpen = false
                    scheduleAutosave()
                } onCancel: {
                    isAISheetOpen = false
                }
            }
        }
```

- [ ] **Step 5: Wire onSelectionChanged into EditorView**

In `PostEditorView.body`, find the `EditorView(...)` call. Add the `onSelectionChanged` parameter:

```swift
                    onSelectionChanged: { rect in
                        currentSelectionRect = rect
                        handleSelectionChange(rect: rect)
                    }
```

- [ ] **Step 6: Add handleSelectionChange method**

Add this method to `PostEditorView`:

```swift
    private func handleSelectionChange(rect: CGRect?) {
        guard appState.aiEnabled else { return }
        if let rect = rect {
            guard let webView = findWebView() else { return }
            if selectionPill == nil { selectionPill = SelectionPillPanel() }
            selectionPill?.show(selectionRect: rect, in: webView) { [self] operation in
                Task { await executeAIOperation(operation) }
            }
        } else {
            selectionPill?.hide()
        }
    }

    /// Walks the view hierarchy to find the WKWebView inside EditorView.
    private func findWebView() -> NSView? {
        // EditorView is embedded in PostEditorView; walk NSApplication windows
        for window in NSApplication.shared.windows {
            if let wv = findWKWebView(in: window.contentView) { return wv }
        }
        return nil
    }

    private func findWKWebView(in view: NSView?) -> NSView? {
        guard let view = view else { return nil }
        if NSStringFromClass(type(of: view)).contains("WKWebView") { return view }
        for sub in view.subviews {
            if let found = findWKWebView(in: sub) { return found }
        }
        return nil
    }
```

- [ ] **Step 7: Verify build**

```bash
./build.sh
```
Expected: exits 0.

- [ ] **Step 8: Smoke test generate flow**

1. Open `Quill.app`
2. Open Settings, enter an Anthropic API key, save
3. Open a post — ✦ button should appear in toolbar
4. Click ✦, enter a prompt, click Generate
5. Confirm title and content fill in on success

- [ ] **Step 9: Commit**

```bash
git add Sources/QuillKit/Views/AI/GeneratePostSheet.swift Sources/QuillKit/Views/Editor/PostEditorView.swift
git commit -m "feat(ai): add generate-post sheet and toolbar entry point"
```

---

## Task 12: Selection operation execution

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift`

- [ ] **Step 1: Add executeAIOperation method**

Add this method to `PostEditorView`. It orchestrates the full selection → loading → result → accept/discard flow:

```swift
    private func executeAIOperation(_ operation: AIWritingOperation) async {
        guard let settings = appState.aiSettings else { return }
        guard let webView = findWebView() else { return }

        // 1. Tell JS to capture selection and show loading placeholder; get back the selected HTML
        var selectedHTML = ""
        await withCheckedContinuation { continuation in
            (webView as? WKWebView)?.evaluateJavaScript("beginAIOperation()") { result, _ in
                if let success = result as? Bool, success {
                    // Also grab the selected text for the prompt via getSelection
                    (webView as? WKWebView)?.evaluateJavaScript("editor.getHTML()") { html, _ in
                        // We pass the whole doc HTML; prompt builder will use selectedHTML
                        // Actually we stored it in JS — get it from _aiOriginalHTML extraction
                        continuation.resume()
                    }
                } else {
                    continuation.resume()
                }
            }
        }

        // Retrieve selectedHTML (the portion between _aiFrom and _aiTo) from JS
        await withCheckedContinuation { continuation in
            (webView as? WKWebView)?.evaluateJavaScript(
                "_aiOriginalHTML ? editor.state.doc.textBetween(_aiFrom, _aiTo, ' ') : ''"
            ) { result, _ in
                selectedHTML = (result as? String) ?? ""
                continuation.resume()
            }
        }

        guard !selectedHTML.isEmpty else { return }

        // 2. Fetch style samples
        var sampleContents: [String] = []
        for id in settings.samplePostIDs {
            if let post = appState.posts.first(where: { $0.id == id }) {
                let stripped = post.content.rendered
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !stripped.isEmpty { sampleContents.append(stripped) }
            }
        }

        // 3. Call Claude
        let client = AnthropicClient(apiKey: settings.apiKey)
        let system = AIPromptBuilder.systemPrompt(samplePostContents: sampleContents)
        let userMsg = AIPromptBuilder.operationPrompt(selectedHTML: selectedHTML, operation: operation)

        do {
            let resultHTML = try await client.complete(
                userMessage: userMsg,
                systemPrompt: system,
                useWebSearch: false   // operations don't use web search
            )

            // 4. Show result in editor with highlight
            let encoded = try JSONEncoder().encode(resultHTML)
            let jsonStr = String(data: encoded, encoding: .utf8) ?? "\"\""
            (webView as? WKWebView)?.evaluateJavaScript("showAIResult(\(jsonStr))", completionHandler: nil)

            // 5. Show accept/discard panel below the (now-highlighted) result region
            //    Re-use the last known selection rect as approximation
            guard let rect = currentSelectionRect else { return }
            if resultPanel == nil { resultPanel = AIResultPanel() }
            resultPanel?.show(
                belowRect: rect,
                in: webView,
                onAccept: {
                    (webView as? WKWebView)?.evaluateJavaScript("acceptAIResult()", completionHandler: nil)
                    resultPanel = nil
                    // Mark dirty
                    (webView as? WKWebView)?.evaluateJavaScript(
                        "window.webkit?.messageHandlers?.contentChanged?.postMessage(editor.getHTML())",
                        completionHandler: nil
                    )
                },
                onDiscard: {
                    (webView as? WKWebView)?.evaluateJavaScript("discardAIResult()", completionHandler: nil)
                    resultPanel = nil
                }
            )
        } catch {
            // Restore original and show toast
            (webView as? WKWebView)?.evaluateJavaScript("discardAIResult()", completionHandler: nil)
            toastMessage = "Claude couldn't complete that — please try again."
        }
    }
```

- [ ] **Step 2: Verify build**

```bash
./build.sh
```
Expected: exits 0.

- [ ] **Step 3: End-to-end smoke test**

1. Open `Quill.app`, open a post with body text
2. Select 20+ characters of text → confirm pill appears above selection
3. Click "Make Shorter" → pill disappears, loading placeholder appears in editor
4. Wait for result → green-highlighted result appears, accept/discard bar appears below
5. Press Return → highlight clears, result is kept, unsaved dot appears
6. Repeat, this time press Escape (or click away) → original text is restored
7. Try with a network failure (airplane mode) → toast "Claude couldn't complete that" appears, original text is restored

- [ ] **Step 4: Commit**

```bash
git add Sources/QuillKit/Views/Editor/PostEditorView.swift
git commit -m "feat(ai): wire selection operation execution with inline preview and accept/discard"
```

---

## Self-Review

**Spec coverage check:**
- ✅ §1 Settings & Gating — Tasks 1, 4, 6 (AISettings, AppState.aiEnabled, PreferencesView AI section)
- ✅ §2 Generate New Post — Tasks 11 (GeneratePostSheet, toolbar button, pre-flight alert, success/failure)
- ✅ §3 Floating Selection Pill — Tasks 7, 8, 9 (JS bridge, EditorCoordinator, SelectionPillPanel)
- ✅ §4 Inline Preview & Accept/Discard — Tasks 7, 10, 12 (JS bridge functions, AIResultPanel, operation execution)
- ✅ §5 Voice & Style — Tasks 3, 11, 12 (AIPromptBuilder system prompt with samples, used in both generate and operation flows)
- ✅ §6 Claude API Details — Tasks 2, 3 (AnthropicClient: Haiku model, ephemeral session, prompt caching, web search tool, no streaming)

**Placeholder scan:** No TBDs. All code blocks are complete.

**Type consistency:**
- `AIWritingOperation` defined in Task 3, used in Tasks 9, 12 ✅
- `AISettings` defined in Task 1, used in Tasks 4, 6, 11, 12 ✅
- `AISettingsStore` defined in Task 1, used in Tasks 4, 6 ✅
- `AnthropicClient.complete(userMessage:systemPrompt:useWebSearch:)` signature defined in Task 2, called identically in Tasks 11 and 12 ✅
- `AIPromptBuilder.systemPrompt(samplePostContents:)` defined in Task 3, called in Tasks 11, 12 ✅
- `SelectionPillPanel.show(selectionRect:in:onOperation:)` defined in Task 9, called in Task 11 ✅
- `AIResultPanel.show(belowRect:in:onAccept:onDiscard:)` defined in Task 10, called in Task 12 ✅
- `beginAIOperation`, `showAIResult`, `acceptAIResult`, `discardAIResult` JS globals defined in Task 7, called in Task 12 ✅
