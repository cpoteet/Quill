# Post Evaluation — Design Spec

**Date:** 2026-06-16
**Status:** Approved for implementation

## Overview

A writing quality evaluation feature for Quill. The user triggers an evaluation from the toolbar; Claude analyzes the full content and returns a prose critique plus a list of specific findings. Each finding quotes the exact phrase from the content and is clickable — clicking it jumps to and selects that phrase in the editor.

## Scope

**Writing quality checks only** — no SEO, no publishing readiness checklist:
- Grammar (sentence structure, agreement, punctuation)
- Clarity (clear ideas, easy-to-follow sentences)
- Readability (reading level, sentence/paragraph length)
- Wordiness (redundancy, filler phrases, passive voice)
- Tone / Voice (consistency of voice and tonal register)

## Trigger

A new **Evaluate button** in the editor toolbar utility group — the same group as the `</>` code view toggle, which sits to the left of the Add Image button. The button shows a checkmark-document icon. Clicking it:
- Opens the evaluation panel in the right panel slot (replacing Post Settings)
- Immediately triggers a new evaluation run
- If the panel is already open, re-runs the evaluation and replaces the previous result

## Panel

The evaluation panel occupies the right panel slot, replacing `PostSettingsPanel`. Closing it (X button in the panel header) dismisses the panel and restores `PostSettingsPanel`.

### Loading state

Spinner centered in the panel, below a "Post Evaluation" header. Message: **"Evaluating content…"** (not "post" — content applies to both posts and pages).

### Results state

**Header:** "Post Evaluation" on the left, "✕ Close" on the right.

**Prose summary:** 2–4 sentence conversational critique at the top, separated from findings by a horizontal rule. Reads like editorial feedback.

**Findings section:** Labeled "N findings — click to jump" (or "No specific issues found" when findings list is empty). Each finding is a tappable card showing:
- Category label in small caps (e.g. WORDINESS, PASSIVE VOICE, CLARITY)
- Quoted phrase in italics — the exact text from the content used for jump navigation
- Suggestion below the quote (optional — omitted if Claude has no specific rewrite)

**Re-evaluate link:** At the bottom of the panel. Reruns immediately, no confirmation.

### Error state

Error message with a Retry button. Shown when the API call fails.

### Short content state

When content is under ~100 words, skip the API call entirely and show: "Add more content before evaluating." No spinner, no findings.

## Claude interaction

### Prompt structure (`AIPromptBuilder`)

New `evaluatePostPrompt(title:html:)` function. Strips HTML to plain text before sending (reduces tokens). Sends both title and body — title quality is part of writing quality.

Instructs Claude to respond in this exact format:

```
SUMMARY:
<2–4 sentence prose critique covering overall writing quality>

FINDINGS:
QUOTE: "exact phrase from the content" | ISSUE: short label | SUGGESTION: rewrite (optional)
QUOTE: "exact phrase from the content" | ISSUE: short label | SUGGESTION: rewrite (optional)
```

The prompt names the five evaluation categories and asks Claude to quote exact phrases — not paraphrases — from the content so the click-to-jump feature can locate them reliably. If there are no issues worth flagging, the FINDINGS block is empty.

### Response parsing (`AIPromptBuilder`)

New `parseEvaluationResponse(_:) -> EvaluationResult?` function. Splits on `SUMMARY:` and `FINDINGS:` markers (case-insensitive, same pattern as `parseGenerateResponse`). Parses each `QUOTE: … | ISSUE: … | SUGGESTION: …` line into an `EvaluationFinding`.

## Click-to-jump

New JS function `window.findAndSelectText(text)` in `editor.html`. Uses the existing `findMatches(text)` from `editor-transforms.js` to locate the first match in the document. If found, dispatches a ProseMirror transaction to set the text selection to that range and scrolls it into view. No-op if the phrase is not found (e.g. the user edited the content after evaluating).

Called from `PostEditorView` when a finding card is tapped, via `webView.evaluateJavaScript`.

## State (`PostEditorView`)

Four new `@State` vars:
- `showEvaluationPanel: Bool` — toggles the right panel between Settings and Evaluation
- `isEvaluating: Bool` — drives the loading spinner
- `evaluationResult: EvaluationResult?` — nil until a run completes; replaced on re-evaluate
- `evaluationError: String?` — non-nil on API failure

## Data types

```swift
struct EvaluationFinding {
    let quote: String        // exact phrase — used for click-to-jump
    let issue: String        // short category label
    let suggestion: String?  // optional rewrite
}

struct EvaluationResult {
    let summary: String
    let findings: [EvaluationFinding]
}
```

## Edge cases

| Situation | Behavior |
|---|---|
| Content < 100 words | Skip API call; show "Add more content before evaluating" |
| No findings returned | Show summary only; label reads "No specific issues found" |
| Quoted phrase not found in editor | Click-to-jump is a no-op; finding card still shows |
| User edits content while panel is open | Panel stays with stale results; Re-evaluate to refresh |
| API error | Show error state with Retry button |
| Code view active when Evaluate clicked | `window.getContent()` already handles this correctly |

## Files changed

- `Sources/QuillKit/AI/AIPromptBuilder.swift` — add `evaluatePostPrompt`, `parseEvaluationResponse`, `EvaluationFinding`, `EvaluationResult`
- `Sources/QuillKit/Views/AI/EvaluationPanel.swift` — new SwiftUI view (loading / results / error states)
- `Sources/QuillKit/Views/Editor/PostEditorView.swift` — evaluation state vars, `executeEvaluation()` async func, toolbar button, right-panel toggle
- `Sources/QuillKit/Resources/editor.html` — add `window.findAndSelectText(text)`
- `Tests/QuillTests/AIPromptBuilderTests.swift` — tests for new prompt and parser
