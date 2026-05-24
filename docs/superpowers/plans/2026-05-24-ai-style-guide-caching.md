# AI Style Guide Caching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate a compact writing-style summary once when the user saves sample post selections, store it in `ai_settings.json`, and use it on every AI call instead of re-resolving and re-sending raw post content.

**Architecture:** `AISettings` gains a `styleGuide: String?` field. `PreferencesView.saveAll()` calls Claude once to produce the guide whenever the sample post selection changes; it skips regeneration if IDs are unchanged and a guide already exists, and clears the guide when the WordPress site URL changes. Both AI call sites (`PostEditorView`, `GeneratePostSheet`) use the stored guide directly.

**Tech Stack:** Swift 6, SwiftUI, `AnthropicClient` (already in `Sources/QuillKit/AI/AnthropicClient.swift`), `AISettingsStore` (file-based JSON at `~/Library/Application Support/Quill/ai_settings.json`).

---

### Task 1: Add `styleGuide` field to `AISettings`

**Files:**
- Modify: `Sources/QuillKit/AI/AISettings.swift`

- [ ] **Step 1: Add the field and update the initializer**

Replace the entire file content with:

```swift
import Foundation

public struct AISettings: Codable {
    public var apiKey: String
    public var samplePostIDs: [Int]
    public var webSearchEnabled: Bool
    public var styleGuide: String?

    public init(apiKey: String = "", samplePostIDs: [Int] = [], webSearchEnabled: Bool = true, styleGuide: String? = nil) {
        self.apiKey = apiKey
        self.samplePostIDs = samplePostIDs
        self.webSearchEnabled = webSearchEnabled
        self.styleGuide = styleGuide
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

`styleGuide` is `Codable` with a default of `nil`, so existing `ai_settings.json` files without the field decode cleanly.

- [ ] **Step 2: Build to verify**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add Sources/QuillKit/AI/AISettings.swift && git commit -m "feat(ai): add styleGuide field to AISettings"
```

---

### Task 2: Update `AIPromptBuilder` and both AI call sites

This task changes the `systemPrompt` signature, which breaks two call sites. All three files must be updated together so the build stays clean.

**Files:**
- Modify: `Sources/QuillKit/AI/AIPromptBuilder.swift`
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift` (lines 620–631)
- Modify: `Sources/QuillKit/Views/AI/GeneratePostSheet.swift`

- [ ] **Step 1: Update `AIPromptBuilder`**

Replace the `systemPrompt` method and add `styleGuideGenerationPrompt`. The `operationPrompt`, `generatePostPrompt`, and `parseGenerateResponse` methods are unchanged.

In `Sources/QuillKit/AI/AIPromptBuilder.swift`, replace:

```swift
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
```

with:

```swift
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
```

- [ ] **Step 2: Update `PostEditorView` — remove resolve-and-strip, use stored style guide**

In `Sources/QuillKit/Views/Editor/PostEditorView.swift`, replace lines 620–631:

```swift
        // 2. Build style sample contents from loaded posts
        let sampleContents: [String] = settings.samplePostIDs.compactMap { id in
            guard let post = appState.posts.first(where: { $0.id == id }) else { return nil }
            let stripped = post.content.rendered
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return stripped.isEmpty ? nil : stripped
        }

        // 3. Call Claude (selection operations never use web search — faster + cheaper)
        let client = AnthropicClient(apiKey: settings.apiKey)
        let system = AIPromptBuilder.systemPrompt(samplePostContents: sampleContents)
```

with:

```swift
        // 2. Call Claude (selection operations never use web search — faster + cheaper)
        let client = AnthropicClient(apiKey: settings.apiKey)
        let system = AIPromptBuilder.systemPrompt(styleGuide: settings.styleGuide)
```

- [ ] **Step 3: Update `GeneratePostSheet` — remove `samplePosts` param and resolve-and-strip**

Replace the entire `Sources/QuillKit/Views/AI/GeneratePostSheet.swift` with:

```swift
import SwiftUI

struct GeneratePostSheet: View {
    let aiSettings: AISettings
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

            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text("Describe the post you want to write…")
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $prompt)
                    .font(.body)
                    .frame(minHeight: 80, maxHeight: 160)
                    .scrollContentBackground(.hidden)
                    .disabled(isGenerating)
            }
            .padding(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
            )

            if isGenerating {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.75)
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

    @MainActor
    private func generate() async {
        isGenerating = true
        errorText = nil
        statusText = aiSettings.webSearchEnabled ? "Searching the web…" : "Writing…"

        do {
            let client = AnthropicClient(apiKey: aiSettings.apiKey)
            let system = AIPromptBuilder.systemPrompt(styleGuide: aiSettings.styleGuide)
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

- [ ] **Step 4: Update the `GeneratePostSheet` call site in `PostEditorView`**

In `Sources/QuillKit/Views/Editor/PostEditorView.swift`, replace:

```swift
                GeneratePostSheet(
                    aiSettings: settings,
                    samplePosts: appState.posts
                ) { generatedTitle, generatedHTML in
```

with:

```swift
                GeneratePostSheet(
                    aiSettings: settings
                ) { generatedTitle, generatedHTML in
```

- [ ] **Step 5: Build to verify**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add Sources/QuillKit/AI/AIPromptBuilder.swift Sources/QuillKit/Views/Editor/PostEditorView.swift Sources/QuillKit/Views/AI/GeneratePostSheet.swift && git commit -m "feat(ai): use stored style guide instead of resolving posts at call time"
```

---

### Task 3: Async save with style guide generation in `PreferencesView`

**Files:**
- Modify: `Sources/QuillKit/Views/Settings/PreferencesView.swift`

- [ ] **Step 1: Add `isAnalyzing` state**

In `Sources/QuillKit/Views/Settings/PreferencesView.swift`, after `@State private var isSamplePickerOpen: Bool = false`, add:

```swift
    @State private var isAnalyzing: Bool = false
```

- [ ] **Step 2: Update the status/button HStack to show analysis state and wire async Task**

Replace the bottom HStack:

```swift
            HStack {
                if let error = saveError {
                    Text(error).foregroundStyle(.red).font(.caption)
                } else if saveSuccess {
                    Text("Saved.").foregroundStyle(.green).font(.caption)
                }
                Spacer()
                Button("Save") { saveAll() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
            }
```

with:

```swift
            HStack {
                if let error = saveError {
                    Text(error).foregroundStyle(.red).font(.caption)
                } else if isAnalyzing {
                    Text("Analyzing writing style…").foregroundStyle(.secondary).font(.caption)
                } else if saveSuccess {
                    Text("Saved.").foregroundStyle(.green).font(.caption)
                }
                Spacer()
                Button("Save") { Task { await saveAll() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || isAnalyzing)
            }
```

- [ ] **Step 3: Replace `saveAll()` with the async version**

Replace the entire `saveAll()` function:

```swift
    private func saveAll() async {
        saveError = nil
        saveSuccess = false

        // Detect site URL change before saving — stale sample IDs and style guide
        // from a previous site must be cleared when the user switches WordPress sites.
        let previousCreds = try? KeychainStore.load()
        let siteURLChanged = previousCreds != nil && previousCreds?.siteURL.absoluteString != siteURL
        if siteURLChanged {
            aiSamplePostIDs = []
        }

        // Save WordPress credentials if any field is filled
        if !siteURL.isEmpty || !username.isEmpty || !appPassword.isEmpty {
            guard let url = URL(string: siteURL), url.scheme != nil else {
                saveError = "Invalid URL. Include https://"
                return
            }
            isSaving = true
            let creds = Credentials(siteURL: url, username: username, appPassword: appPassword)
            do {
                try KeychainStore.save(creds)
                onSave(creds)
            } catch {
                saveError = error.localizedDescription
                isSaving = false
                return
            }
            isSaving = false
        }

        guard !aiAPIKey.isEmpty else {
            saveSuccess = true
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            saveSuccess = false
            return
        }

        // Determine whether the style guide needs regeneration:
        // - Empty sample IDs  → clear guide, no regen
        // - IDs unchanged (and site unchanged) + existing guide → keep guide, skip regen
        // - IDs changed OR site changed OR no existing guide → regen
        let previousSettings = try? AISettingsStore.load()
        let idsUnchanged = Set(aiSamplePostIDs) == Set(previousSettings?.samplePostIDs ?? [])

        let existingGuide: String?
        if aiSamplePostIDs.isEmpty {
            existingGuide = nil
        } else if idsUnchanged && !siteURLChanged {
            existingGuide = previousSettings?.styleGuide
        } else {
            existingGuide = nil
        }

        let shouldRegen = !aiSamplePostIDs.isEmpty && existingGuide == nil

        // Persist immediately with whatever guide is valid right now
        var current = AISettings(
            apiKey: aiAPIKey,
            samplePostIDs: aiSamplePostIDs,
            webSearchEnabled: aiWebSearchEnabled,
            styleGuide: existingGuide
        )
        try? AISettingsStore.save(current)
        onSaveAISettings?(current)

        // Optionally regenerate the style guide
        if shouldRegen {
            let sampleContents: [String] = aiSamplePostIDs.compactMap { id in
                guard let post = posts.first(where: { $0.id == id }) else { return nil }
                let stripped = post.content.rendered
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return stripped.isEmpty ? nil : stripped
            }

            if !sampleContents.isEmpty {
                isAnalyzing = true
                do {
                    let client = AnthropicClient(apiKey: aiAPIKey)
                    let prompt = AIPromptBuilder.styleGuideGenerationPrompt(sampleContents: sampleContents)
                    let guide = try await client.complete(
                        userMessage: prompt,
                        systemPrompt: "Return only the requested style guide with no preamble.",
                        useWebSearch: false
                    )
                    current.styleGuide = guide
                    try? AISettingsStore.save(current)
                    onSaveAISettings?(current)
                } catch {
                    saveError = "Style analysis failed: \(error.localizedDescription)"
                    isAnalyzing = false
                    return
                }
                isAnalyzing = false
            }
        }

        saveSuccess = true
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        saveSuccess = false
    }
```

- [ ] **Step 4: Build to verify**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add Sources/QuillKit/Views/Settings/PreferencesView.swift && git commit -m "feat(ai): generate and cache writing style guide on settings save"
```
