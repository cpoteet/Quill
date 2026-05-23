# AI Writing Feature — Design Spec

**Date:** 2026-05-23
**Status:** Approved

## Overview

An AI writing assistant integrated into Quill, powered by Claude (Haiku model). Provides two interaction modes: generating a new post from a prompt, and performing operations on selected text (Make Longer, Make Shorter, Convert to Table, Convert to List). All AI UI is gated behind an Anthropic API key in Settings — if no key is configured, no AI chrome appears anywhere in the app.

---

## 1. Settings & API Key Gating

A new **"AI Writing"** section appears in `PreferencesView`, below the WordPress credentials section.

### Fields

- **Anthropic API Key** — `SecureField`, same visual style as the existing Application Password field. Saved to `~/Library/Application Support/Quill/ai_settings.json` (chmod 600), using the same file-based storage pattern as `credentials.json`.
- **Writing Style Samples** — a "Choose Sample Posts…" button that opens a sheet listing the user's WordPress posts as a checklist. User selects 2–5 posts. Stored as an array of post IDs in `ai_settings.json`. A caption beneath the button reads e.g. "3 posts selected" or "No samples selected."
- **Web Search** — a `Toggle`: "Allow Claude to search the web when generating content." Stored as a bool in `ai_settings.json`. On by default when an API key is first saved.

### Gating rule

`AppState` exposes a computed `var aiEnabled: Bool` that returns `true` only when a non-empty API key is present in `ai_settings.json`. All AI UI (toolbar button, floating selection pill) checks this flag before rendering. No key = no visible AI chrome.

### Data model

```swift
struct AISettings: Codable {
    var apiKey: String
    var samplePostIDs: [Int]
    var webSearchEnabled: Bool
}
```

Stored and loaded by a new `AISettingsStore` struct, mirroring the `KeychainStore` pattern.

---

## 2. Generate New Post Flow

### Entry point

A **✦ button** at the right end of the editor toolbar, separated from adjacent controls by a `Divider()`. Rendered only when `appState.aiEnabled`. Positioned after the existing settings sidebar button.

### Pre-flight check

If the current editor has non-empty title or body content, an alert fires before opening the sheet:
> "This will replace your current content. Continue?"
> Buttons: **Continue** / **Cancel**

If the editor is empty, the sheet opens immediately with no alert.

### Generate sheet

A modal sheet, ~480pt wide, containing:

- **Prompt text area** — multiline `TextEditor` with placeholder "Describe the post you want to write…", auto-grows up to ~5 lines
- **Status line** — appears only during generation; shows "Searching the web…" or "Writing…" based on current Claude tool activity
- **Buttons** — "Generate" (`.borderedProminent`) and "Cancel" (`.plain`). During generation the text area and Generate button are disabled; a `ProgressView` spinner replaces the button label.

### On success

Sheet dismisses. Editor title field and body are filled with Claude's generated title and HTML content respectively. Post is immediately marked dirty (unsaved amber dot appears).

### On failure

Sheet stays open. An inline error message appears below the prompt field. User may retry or cancel.

---

## 3. Floating Selection Toolbar (Selection Pill)

### Trigger

When the user makes a text selection in the editor of ≥ 10 characters, JavaScript detects the selection, measures its bounding rect (`getBoundingClientRect()`), and sends it to Swift via a new `selectionChanged` message handler. Swift positions and shows the pill. When the selection is cleared, Swift hides the pill.

### Appearance

A pill-shaped `NSPanel` (non-activating, `NSNonactivatingPanelMask`):
- Background: `Color.wpPanelBg` with a thin border and subtle drop shadow
- Four buttons in a horizontal row: **Make Longer · Make Shorter · Convert to Table · Convert to List**
- Positioned 8pt above the top edge of the selection rect, horizontally centered on it
- Fades in at 0.15s opacity animation; fades out immediately on selection clear

### Guardrails

- Minimum selection length: 10 characters (shorter selections do not show the pill)
- Pill is hidden immediately when the editor loses focus

---

## 4. Inline Preview & Accept/Discard

### On operation trigger

Tapping any pill button:
1. Dismisses the pill
2. Preserves the original selected text in memory
3. Replaces the selection in the editor with a loading indicator (pulsing placeholder)
4. Fires the Claude API request

### On success

The placeholder is replaced with Claude's result, rendered with a **soft green-tinted background highlight** (diff "added" style, subtle). The original text remains held in memory.

A floating **accept/discard bar** (`NSPanel`, non-activating) appears anchored ~8pt below the highlighted region:
- **✓ Accept** (`Return`) — confirms replacement, removes highlight, clears held original
- **✗ Discard** (`Escape`) — restores original text, removes highlight

Clicking anywhere else in the editor is treated as **Discard** (original text restored, highlight removed).

### On failure

Original text is restored automatically. A toast notification appears: *"Claude couldn't complete that — please try again."* Uses the existing `toastMessage` system in `PostEditorView`.

---

## 5. Voice & Style

### Mechanism

No explicit "analyze" step. When sample post IDs are configured, their full content is fetched fresh from WordPress at request time and included in Claude's system prompt:

> "Here are examples of this author's writing style: [post 1 content] / [post 2 content] / … Match their voice, tone, sentence rhythm, and personality in your response."

Claude derives vocabulary, formality, and style from the samples without any user-authored description.

### Behavior details

- Sample content is fetched fresh each request — no local caching of post body text
- If a sample post ID no longer exists on WordPress, it is silently skipped (no error)
- If no samples are selected, Claude operates without style guidance — no warning, no friction
- Web search availability is passed as a tool flag: when `webSearchEnabled` is true, Claude may make search calls mid-generation; when false, it generates from its own knowledge only

---

## 6. Claude API Details

- **Model:** `claude-haiku-4-5` (cost-efficient; fast enough for inline operations)
- **Client:** New `AnthropicClient` struct using `URLSessionConfiguration.ephemeral`, mirroring `WordPressClient` patterns. API key read from `AISettings` at call time.
- **Tools:** Web search tool conditionally included based on `AISettings.webSearchEnabled`
- **Streaming:** Not used in v1 — responses are returned complete. Status line ("Writing…") conveys activity without requiring streaming infrastructure.
- **Prompt caching:** System prompt (style samples) uses Anthropic prompt caching (`cache_control: ephemeral`) to reduce cost on repeated requests within a session.

---

## 7. Out of Scope (v1)

- Streaming token-by-token output
- Per-operation tone controls (e.g. "make it more formal")
- AI-generated image suggestions
- Conversation / follow-up instructions after a result
- Usage tracking or cost display
