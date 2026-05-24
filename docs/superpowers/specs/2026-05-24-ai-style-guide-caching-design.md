# AI Style Guide Caching

**Date:** 2026-05-24
**Status:** Approved

## Problem

When the user selects writing style sample posts, every AI call (generate post, selection operations) resolves those posts from the in-memory list, strips HTML, and sends the full raw content as the system prompt. This is expensive: multiple posts worth of content on every single call, even though the style data never changes between calls.

## Solution

Generate a compact style guide once — when the user saves their sample post selection — and store it alongside the settings. Every AI call uses this pre-computed summary instead of raw post content. Combined with the existing prompt caching already wired into `AnthropicClient`, the marginal cost of style context drops to nearly nothing for repeated calls within a 5-minute window.

## Data Model

`AISettings` gains one new optional field:

```swift
public var styleGuide: String?
```

Existing `ai_settings.json` files decode cleanly — the field is absent and defaults to `nil`. `samplePostIDs` is retained so the user can see which posts are selected and regenerate the guide if needed.

## Style Guide Generation

A new `AIPromptBuilder.styleGuideGenerationPrompt(sampleContents:)` method produces the user-turn message for a one-shot Claude call. It asks Claude to analyze the sample posts and return a ≤150 word style description covering:

- Voice and tone (formal/casual, warm/dry, etc.)
- Sentence rhythm and typical length
- Vocabulary level and word choice patterns
- Use of humor, personality, or rhetorical devices
- Any distinctive structural habits

The response is plain text — no preamble, no labels. This is what gets stored as `styleGuide`.

## Settings Save Flow

`PreferencesView.saveAll()` becomes `async` and runs inside a `Task`. The sequence:

1. Validate and save WordPress credentials. If the site URL has changed from the stored credentials, clear `samplePostIDs` and `styleGuide` from AI settings and reset the local state (`aiSamplePostIDs = []`). This prevents stale post IDs and a stale style guide from a previous site carrying over.
2. Save AI settings with current `samplePostIDs` and existing `styleGuide` (immediate persistence)
3. Call `onSaveAISettings` so `AppState` reflects the new API key / web search toggle right away
4. If API key is non-empty and sample post IDs are non-empty:
   - Compare current `aiSamplePostIDs` against the IDs stored on disk before this save. If they are identical and a `styleGuide` already exists, skip regeneration — the style guide is still valid.
   - Otherwise: set `isAnalyzing = true`, show "Analyzing writing style…" status label, strip HTML from each selected post's `content.rendered`, and call `AnthropicClient.complete` with the style guide generation prompt (no web search — this is a one-shot call)
   - On success: update `styleGuide` in settings, save again, call `onSaveAISettings` again
   - On failure: show error; existing style guide (if any) is preserved
   - Set `isAnalyzing = false`
5. If sample post IDs are empty: clear `styleGuide`, save, call `onSaveAISettings`
6. Show "Saved." on success

The button is disabled while `isAnalyzing` is true.

## System Prompt

`AIPromptBuilder.systemPrompt()` signature changes:

```swift
// Before
public static func systemPrompt(samplePostContents: [String]) -> String

// After
public static func systemPrompt(styleGuide: String?) -> String
```

When `styleGuide` is non-nil and non-empty, the system prompt appends:

```
Write in this author's style:

<style guide text>
```

The base instructions (output format, no code fences, clean HTML) are unchanged.

## Call Sites

Both call sites drop their resolve-and-strip blocks entirely:

**`PostEditorView.executeAIOperation()`** — removes the `sampleContents` computation, calls `AIPromptBuilder.systemPrompt(styleGuide: settings.styleGuide)`.

**`GeneratePostSheet`** — removes the `sampleContents` computation and the `samplePosts: [WPPost]` parameter, calls `AIPromptBuilder.systemPrompt(styleGuide: aiSettings.styleGuide)`.

## Prompt Caching

`AnthropicClient` already marks the system block with `cache_control: ephemeral`. The style guide travels in that block, so it is automatically cached for 5 minutes. No changes needed to `AnthropicClient`.

## Error Handling

- If style guide generation fails, the save still succeeds (credentials and AI key were already written). The error is shown inline; any previously stored style guide is left intact.
- If no sample posts are selected, `styleGuide` is set to `nil` and AI calls proceed without style context.
- If a stored post ID no longer exists in `appState.posts` at generation time, it is silently skipped (same behavior as before).

## Files Changed

- `Sources/QuillKit/AI/AISettings.swift` — add `styleGuide: String?`
- `Sources/QuillKit/AI/AIPromptBuilder.swift` — new `styleGuideGenerationPrompt`, updated `systemPrompt`
- `Sources/QuillKit/Views/Settings/PreferencesView.swift` — async save, analysis indicator, style guide generation call
- `Sources/QuillKit/Views/Editor/PostEditorView.swift` — remove resolve-and-strip, use `settings.styleGuide`
- `Sources/QuillKit/Views/AI/GeneratePostSheet.swift` — remove `samplePosts` param, remove resolve-and-strip, use `aiSettings.styleGuide`
