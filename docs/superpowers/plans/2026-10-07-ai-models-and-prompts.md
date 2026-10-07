# AI Model Selection and Prompts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the author choose the Claude model and reasoning level (defaulting to the newest Haiku), and replace every AI prompt with the versions tested on 2026-10-07: a two-request Evaluate with one-click Apply and fact checks, HTML-preserving selection commands plus Fix Spelling & Grammar and Rephrase, a cited Generate Post, and the structured style guide.

**Architecture:** `AnthropicClient.complete` takes a `CompletionOptions` value and builds its body through one pure function, so every request shape is unit-tested without a network call. Prompt text lives in `AIPromptBuilder` (style guide, Generate) and two new files, `EvaluationPrompts.swift` and `SelectionPrompts.swift`; every new prompt returns JSON through `output_config.format`. The editor sends selections as reduced HTML with `L`/`F` stubs and restores attributes itself; Evaluate's Apply is a new `window.applyEvaluationFinding`.

**Tech Stack:** Swift 6.3.1 / SwiftUI (macOS 27), Swift Testing, URLSession + `AnthropicMockURLProtocol`; Tiptap in `editor.html`, node `--test` + jsdom in `Scripts/`.

**Spec:** `docs/superpowers/specs/2026-10-02-ai-model-selection-design.md` and `docs/superpowers/specs/2026-10-07-ai-prompts-design.md`. Mockup: `docs/superpowers/specs/2026-10-07-evaluate-panel-mockups.html`, option B (tabs) chosen 2026-10-07. Prompt text is copied verbatim from the prompts spec; this plan names where it goes, not what it says.

## Open decisions (ask before the task that needs them)

- **Generate fills the Excerpt field** (Task 12): yes or no. The prompt asks for an excerpt either way; the answer decides whether `onResult` writes it.

## Global Constraints

- Work on `main`. **No commits unless the user asks**; at the end of each task, build, run and summarize what changed. Before any commit the user requests: `codex review --uncommitted -c model="gpt-6.1-sol" -c model_reasoning_effort="high"`, verify each finding, then commit.
- After every code change: `pkill -f "^$PWD/Quill.app/Contents/MacOS/Quill"; sleep 2 && ./build.sh 2>&1 && open Quill.app`.
- Default model: newest Models API entry with `line == "haiku"` by `created_at`; before any fetch, or if none, `claude-haiku-5-5`.
- Never send `thinking: {"type": "disabled"}`. Adaptive models: no "Off". Enabled-only budgets: Low 2,048 / Medium 8,192 / High 16,384.
- `max_tokens`: base + budget (enabled) or base + 16,000 (adaptive), capped at the model's `max_tokens`. Bases: 4,096 everywhere; Generate 4,096, then 16,384 for "Get Full Version".
- `sharedSession` request timeout: 600 seconds.
- Web search versions, newest first: `["web_search_20260318", "web_search_20260209", "web_search_20250305"]`; always the newest the model accepts; always `allowed_callers: ["direct"]`; `max_uses` 8 for Evaluate's fact-check, 10 for Generate. Never declare a `code_execution` tool.
- Prompts, schemas and categories: verbatim from `2026-10-07-ai-prompts-design.md`. Today's date goes in as `yyyy-MM-dd`.
- Model-picker copy: "Enter an API key to load models.", "Your saved model is no longer available. Switched to <display name>.", Reasoning caption "Higher levels think longer before answering. Responses take more time and cost more.", Web Search caption "This model can't search the web." Refusal: "Claude declined this request."
- UI rules from `docs/gotchas.md`: `SectionLabel` headings, no fixed widths inside `.inspector`, `InlineError` / `PaneError` for errors, no red text.
- A top-level `const` in a Resources JS file is not reachable as `window.x`; cross-file helpers are `function` declarations.

## Review Focus

1. **The author edits after Evaluate:** a finding's `original` no longer appears, or appears twice. Apply must refuse rather than replace the wrong occurrence (Task 8 tests both).
2. **Settings saved before this change, offline:** no model list, no capabilities. Every feature must still send a valid request to `claude-haiku-5-5` (Task 3 test `requestForUnknownModelOmitsThinking`).
3. **The model mangles a stub:** drops `F1`, duplicates `L1`, or invents `L9`. The result must insert without losing text or throwing (Task 10 tests).
4. **Only one Evaluate half fails** (refusal, rate limit, no search): the other half still shows, and the failed half shows an inline error (Task 9 test).
5. **The author switches posts while Evaluate or a rewrite is in flight:** results must not land on the new post. Reuse the existing `appState.selectedItem` / `loadedItem` guard (Tasks 9 and 11). `PostEditorView` has no unit-test seam, so this is a manual check in each task's run step: start the command, switch posts, confirm nothing lands.

---

### Task 1: AI settings model and default-model rules

**Files:**
- Modify: `Sources/QuillKit/AI/AISettings.swift`
- Test: `Tests/QuillTests/AISettingsTests.swift` (new)

**Interfaces:**
- Produces:
  - `public struct AIModelInfo: Codable, Equatable { id: String; displayName: String; createdAt: Date; maxTokens: Int; line: String?; supportsAdaptiveThinking: Bool; supportsEnabledThinking: Bool; effortLevels: [String]; supportsWebSearch: Bool }`
  - `public enum AIReasoning: Codable, Equatable { case off, modelDefault, level(String) }`
  - New `AISettings` fields: `model: String?` (nil = default), `reasoning: AIReasoning = .modelDefault`, `models: [AIModelInfo] = []`, `webSearchToolByModel: [String: String] = [:]`, all decoding when absent.
  - `AISettings.fallbackModelID = "claude-haiku-5-5"`
  - `func resolvedModelID() -> String`, `func resolvedModel() -> AIModelInfo?`
  - `static func reasoningOptions(for: AIModelInfo?) -> [AIReasoning]`, `func normalizedReasoning() -> AIReasoning` (resets to the model's default when the saved option isn't offered)

- [ ] **Step 1: Write the failing tests**

```swift
@Test func decodesSettingsWrittenBeforeModelSelection() throws {
    let old = #"{"apiKey":"k","samplePostIDs":[1],"webSearchEnabled":true,"styleGuide":"g"}"#
    let s = try JSONDecoder().decode(AISettings.self, from: Data(old.utf8))
    #expect(s.model == nil && s.reasoning == .modelDefault && s.models.isEmpty && s.webSearchToolByModel.isEmpty)
}
@Test func defaultModelIsNewestHaiku() {
    var s = AISettings(); s.models = [haiku45, haiku55, sonnet55]
    #expect(s.resolvedModelID() == "claude-haiku-5-5")
}
@Test func defaultModelFallsBackWithoutAList() { #expect(AISettings().resolvedModelID() == "claude-haiku-5-5") }
@Test func pinnedModelWins() { var s = AISettings(); s.models = [haiku55, sonnet55]; s.model = "claude-sonnet-5-5"; #expect(s.resolvedModelID() == "claude-sonnet-5-5") }
@Test func adaptiveOptionsHaveNoOff() {
    #expect(AISettings.reasoningOptions(for: haiku55) == [.modelDefault, .level("low"), .level("medium"), .level("high"), .level("xhigh"), .level("max")])
}
@Test func enabledOnlyOptions() { #expect(AISettings.reasoningOptions(for: haiku45) == [.off, .level("low"), .level("medium"), .level("high")]) }
@Test func unknownModelOnlyOff() { #expect(AISettings.reasoningOptions(for: nil) == [.off]) }
@Test func switchingToEnabledOnlyResetsModelDefaultToOff() {
    var s = AISettings(); s.models = [haiku45]; s.model = "claude-haiku-4-5"; s.reasoning = .modelDefault
    #expect(s.normalizedReasoning() == .off)
}
```

Fixtures `haiku45`, `haiku55`, `sonnet55` mirror the Models API values recorded on 2026-10-07 (Haiku 4.5: enabled only, no effort, 64,000 max, created 2025-10-15; Haiku 5.5: adaptive, all five levels, 128,000, created 2026-10-07; both `line: "haiku"`, both web search).

- [ ] **Step 2:** `swift test --filter AISettingsTests`. Expected: FAIL (types not defined).
- [ ] **Step 3:** Implement the types and functions above in `AISettings.swift`. Custom `init(from:)` with `decodeIfPresent` for every new field.
- [ ] **Step 4:** `swift test --filter AISettingsTests`. Expected: PASS.
- [ ] **Step 5:** Build and run (Global Constraints); summarize to the user.

### Task 2: Models API list

**Files:**
- Modify: `Sources/QuillKit/AI/AnthropicClient.swift`
- Test: `Tests/QuillTests/AnthropicClientTests.swift`

**Interfaces:**
- Consumes: `AIModelInfo` (Task 1)
- Produces: `public func listModels() async throws -> [AIModelInfo]` (sorted newest first by `createdAt`; follows `has_more`/`last_id` paging; `limit=100`)

- [ ] **Step 1: Write the failing tests** `listModelsDecodesCapabilities` (a response holding the two recorded model objects maps `capabilities.thinking.types.adaptive.supported`, `.enabled.supported`, each `effort.<level>.supported`, `max_tokens`, `line`, `capabilities.server_tools.web_search.supported`), `listModelsSortsNewestFirst`, `listModelsFollowsPaging` (two pages, three models), `listModelsInvalidKeyThrowsInvalidKey` (401).
- [ ] **Step 2:** `swift test --filter AnthropicClientTests`. Expected: the four new tests FAIL.
- [ ] **Step 3:** Implement `listModels()`; `verifyKey()` stays as is.
- [ ] **Step 4:** Tests PASS.
- [ ] **Step 5:** Build and run; summarize.

### Task 3: Request builder, reasoning, refusal and timeout

**Files:**
- Modify: `Sources/QuillKit/AI/AnthropicClient.swift`
- Test: `Tests/QuillTests/AnthropicClientTests.swift`

**Interfaces:**
- Consumes: `AIModelInfo`, `AIReasoning`, `AISettings.resolvedModel()` (Task 1)
- Produces:
  - `public struct CompletionOptions { modelID: String; model: AIModelInfo?; reasoning: AIReasoning; baseMaxTokens: Int = 4096; webSearch: WebSearchUse? = nil; jsonSchema: [String: Any]? = nil }` with `public struct WebSearchUse { maxUses: Int }`
  - `public init(settings: AISettings, baseMaxTokens: Int = 4096, webSearch: WebSearchUse? = nil, jsonSchema: [String: Any]? = nil)` convenience on `CompletionOptions`
  - `static func requestBody(system: String, user: String, options: CompletionOptions, webSearchTool: String?) -> [String: Any]` (pure)
  - `public func complete(userMessage: String, systemPrompt: String, options: CompletionOptions) async throws -> Result`; `Result` gains `webSearchTool: String?` (the version that worked; nil if none sent)
  - `AnthropicError.refused` with description "Claude declined this request."

The old `complete(userMessage:systemPrompt:useWebSearch:maxTokens:model:)` is removed; call sites move in Tasks 6, 9, 11 and 12, so until then they pass `CompletionOptions(settings:)` with today's arguments.

- [ ] **Step 1: Write the failing tests**, one per row of the spec's request table and `max_tokens` rules, on `requestBody` directly:
  - `adaptiveModelDefault` → `thinking == ["type": "adaptive"]`, no `output_config.effort`, `max_tokens == 4096 + 16000`
  - `adaptiveLevel` → `output_config.effort == "high"`
  - `enabledOnlyOff` → no `thinking`, `max_tokens == 4096`
  - `enabledOnlyMedium` → `thinking == ["type": "enabled", "budget_tokens": 8192]`, `max_tokens == 4096 + 8192`
  - `requestForUnknownModelOmitsThinking` (model `nil`, any reasoning) → no `thinking`, no `output_config`, `max_tokens == 4096`
  - `neverSendsDisabledThinking`: every combination of the three fixture models × every `AIReasoning` case; `thinking["type"] != "disabled"`
  - `maxTokensCappedAtModelLimit` (base 16,384 + 16,000 on a 20,000-limit model → 20,000)
  - `jsonSchemaGoesInOutputConfigFormat` (`output_config.format == ["type": "json_schema", "schema": …]`, alongside `effort` when both apply)
  - `webSearchToolIsDirect` (`tools == [["type": t, "name": "web_search", "max_uses": 8, "allowed_callers": ["direct"]]]`)
  - `refusalThrowsRefused` (mock response `stop_reason: "refusal"`)
  - `textIsJoinedFromTextBlocksOnly` (response with a `thinking` block first, then two text blocks)
  - `sharedSessionTimeoutIs600`
- [ ] **Step 2:** `swift test --filter AnthropicClientTests`. Expected: new tests FAIL.
- [ ] **Step 3:** Implement. Encode the body with `JSONSerialization` (the schema is free-form); keep `cache_control` on the system block.
- [ ] **Step 4:** All `AnthropicClientTests` PASS, including the existing header and error tests (update their call sites to `options:`).
- [ ] **Step 5:** Move the four existing call sites to `CompletionOptions(settings:)` with their current arguments so the app builds; build and run; summarize.

### Task 4: Web search versions and `pause_turn`

**Files:**
- Modify: `Sources/QuillKit/AI/AnthropicClient.swift`
- Test: `Tests/QuillTests/AnthropicClientTests.swift`

**Interfaces:**
- Consumes: `CompletionOptions`, `Result.webSearchTool` (Task 3)
- Produces: `public static let webSearchVersions = ["web_search_20260318", "web_search_20260209", "web_search_20250305"]`; `complete` takes `knownWebSearchTool: String?` inside `WebSearchUse` (`WebSearchUse(maxUses:knownTool:)`) and reports the version that worked in `Result.webSearchTool`. Callers save it into `AISettings.webSearchToolByModel[modelID]`.

- [ ] **Step 1: Find the real error text.** Send one request with a nonexistent version (`web_search_20990101`) to `claude-haiku-5-5` using the probe credentials, record the exact 400 message in the test fixture, and match on the narrowest stable part of it.
- [ ] **Step 2: Write the failing tests** `triesNewestVersionFirst`, `matchingRejectionRetriesNextVersion` (records the version used), `unrelated400IsNotRetried`, `knownVersionIsUsedDirectly` (one request), `pauseTurnContinuesAndJoinsText` (resends with the assistant content appended, joins text from both), `pauseTurnStopsAfterThreeContinuations`, `structuredOutputAcrossPauseTurnParsesLastText` (the JSON text arrives in the final response).
- [ ] **Step 3:** `swift test --filter AnthropicClientTests`. Expected: new tests FAIL.
- [ ] **Step 4:** Implement. Keep each response's `content` as raw JSON for the continuation.
- [ ] **Step 5:** Tests PASS; build and run; summarize.

### Task 5: Settings: model and reasoning pickers, Regenerate

**Files:**
- Modify: `Sources/QuillKit/Views/Settings/PreferencesView.swift`
- Test: `Tests/QuillTests/AISettingsTests.swift`

**Interfaces:**
- Consumes: `listModels()` (Task 2), `AISettings` API (Task 1)
- Produces: `func applyingFetchedModels(_ models: [AIModelInfo]) -> (AISettings, notice: String?)` on `AISettings` (pure: stores the list, clears a pinned model missing from it and returns the "no longer available" notice with the default model's display name, normalizes reasoning). Task 6 adds the Regenerate action's body.

- [ ] **Step 1: Write the failing tests** `fetchKeepsPinnedModelThatStillExists`, `fetchDropsMissingPinnedModelWithNotice` (notice == "Your saved model is no longer available. Switched to Claude Haiku 5.5."), `fetchWithoutPinnedModelHasNoNotice`.
- [ ] **Step 2:** Run; expected FAIL. **Step 3:** Implement. **Step 4:** Run; expected PASS.
- [ ] **Step 5: UI.** In the AI Writing section, after the API key, as in the spec's layout: Model `Picker` (newest first, `displayName`, disabled with "Enter an API key to load models." when the key is empty; fetch error shown as a caption, saved list kept), Reasoning `Picker` from `reasoningOptions(for:)` (labels: Model default, Off, Low, Medium, High, Extra High, Max) with its caption, Regenerate button under Writing Style (disabled with no key or no samples; uses the existing analyzing state), Web Search toggle disabled with "This model can't search the web." when `supportsWebSearch` is false. Fetch on appear with a saved key and on key submit or focus loss.
- [ ] **Step 6:** Build and run. In Settings: models load newest first; Haiku 5.5 shows Model default…Max; switching to Haiku 4.5 shows Off, Low, Medium, High and resets to Off; clearing the key disables Model. Summarize.

### Task 6: Style guide input, prompt and Regenerate

**Files:**
- Modify: `Sources/QuillKit/AI/AIPromptBuilder.swift`, `Sources/QuillKit/Views/Settings/PreferencesView.swift`
- Test: `Tests/QuillTests/AIPromptBuilderTests.swift`

**Interfaces:**
- Produces: `static func reduceSample(html: String) -> String`, `static func sampleHeader(index: Int, title: String, words: Int) -> String` (`--- Sample 1: Title (1,093 words) ---`), `static func styleGuideGenerationPrompt(samples: [(title: String, html: String)]) -> String`, a shared `decodeEntities(_:keepMarkupEntities:)` used by `stripHTML` and the reduction.

- [ ] **Step 1: Write the failing tests** from the spec's Tests list: kept tags lose attributes (including `table`, `tr`, `th`, `td`), `<img>` → `[image]`, other tags removed with text kept, `<br>`/removed block tags keep words apart, empty elements dropped, entities decoded, `&lt;em&gt;` stays encoded; header has title and `1,093`; the prompt has the eight labels in order and numbers the samples; `systemPrompt(styleGuide:)` includes the quoted-words line; existing nil/empty-guide tests still pass.
- [ ] **Step 2:** Run; FAIL. **Step 3:** Implement; prompt text verbatim from the model-selection spec (with "tables" added, as in `Scripts/style-guide-probe.py`). **Step 4:** PASS.
- [ ] **Step 5:** `PreferencesView.saveAll` and Regenerate fetch each sample's `title.rendered` and `content.rendered`, call `styleGuideGenerationPrompt(samples:)` with `CompletionOptions(settings:)`.
- [ ] **Step 6:** Run `Scripts/style-guide-probe.py claude-haiku-5-5` and confirm its prompt and reduction still match `AIPromptBuilder` (diff the printed prompt against a Swift-built one for the same samples). Build, run, press Regenerate; the guide starts with "Voice and tone:". Summarize.

### Task 7: Evaluate prompts and result types

**Files:**
- Create: `Sources/QuillKit/AI/EvaluationPrompts.swift`
- Test: `Tests/QuillTests/EvaluationPromptsTests.swift` (new)

The old `evaluatePostPrompt`, `parseEvaluationResponse`, `EvaluationFinding` and `EvaluationResult` in `AIPromptBuilder.swift` stay until Task 9 moves their callers (`PostEditorView`, `EvaluationPanel`). Until then the new finding type is `ReviewFinding`, so the names don't collide.

**Interfaces:**
- Produces:
  - `public struct EvaluationReview: Decodable { strengths: String; priorities: [String] }`
  - IDs are a `UUID` assigned when parsed, not decoded from the JSON.
  - `public struct ReviewFinding: Decodable, Identifiable { kind: Kind (.correction, .suggestion); category: String; original: String; replacement: String; explanation: String }`
  - `public struct ReviewResult { review: EvaluationReview; corrections: [ReviewFinding]; suggestions: [ReviewFinding] }` (drops items whose `replacement == original`)
  - `public struct FactCheck: Decodable, Identifiable { original, explanation, sourceQuote, sourceURL, replacement: String }`, `public struct FactCheckResult { claimsChecked: Int; checks: [FactCheck] }`
  - `enum EvaluationPrompts { static func postText(html: String) -> String; static func reviewSystem(styleGuide: String?, today: Date) -> String; static func review(title: String, html: String, publishedOn: Date?) -> String; static func factCheckSystem(today: Date) -> String; static func factCheck(title: String, html: String, publishedOn: Date?) -> String; static let reviewSchema: [String: Any]; static let factCheckSchema: [String: Any]; static func parseReview(_ json: String) throws -> ReviewResult; static func parseFactCheck(_ json: String) throws -> FactCheckResult }`

- [ ] **Step 1: Write the failing tests**
  - `postTextMarksStructure`: `<h2>A</h2><p>b</p><ul><li>c</li></ul><figure><img><figcaption>d</figcaption></figure><table><tr><td>e</td><td>f</td></tr></table>` → `"## A\n\nb\n\n- c\n\n[Caption] d\n\n| e | f |"`; footnote list items get `[Footnote] `; `<pre>` and embeds are left out; footnote markers removed; `stripHTML`'s phantom-space fixes still apply.
  - `postTextMatchesEditorText`: for a fixture post, every line with its marker removed is a substring of the editor's text (so `original` can be found).
  - `reviewPromptHasDateAndPublishLine` (`Published: 2023-11-13` / `Status: draft, not yet published`)
  - `reviewSystemOmitsGuideParagraphWithoutGuide`
  - `parseReviewDropsNoOpItems`, `parseFactCheckCountsClaims`
- [ ] **Step 2:** Run; FAIL. **Step 3:** Implement with the prompt text and schemas verbatim from the prompts spec. **Step 4:** PASS.
- [ ] **Step 5:** `swift test` passes and the app builds unchanged. Summarize (no app-visible change yet).

### Task 8: Apply a finding in the editor

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`
- Test: `Scripts/test-editor-evaluate.js` (new; add to `test.sh`)

**Interfaces:**
- Produces: `window.applyEvaluationFinding(original, replacement) -> 'applied' | 'missing' | 'ambiguous'` (one transaction, so ⌘Z undoes it; matches through the same exact-then-normalized `findMatches` path as `findAndSelectText`, never the loose tier) and `window.findingStatus(originals: string[]) -> string[]` returning `'ok' | 'missing' | 'ambiguous'` for each without editing, for the panel's enabled/disabled Apply.

- [ ] **Step 1: Write the failing tests** (real `editor.html` in jsdom, like `test-ai-output-validity.js`):
  - `applies a correction inside a paragraph and keeps surrounding marks` (`<p>It <em>feel</em> off</p>`, `feel` → `fell`; emphasis kept)
  - `returns missing after the text was edited`
  - `returns ambiguous when the original appears twice and changes nothing`
  - `keeps a link on unchanged words` (`See the <a href="https://example.com">docs</a> today.`, `the docs` → `these docs`: "docs" is still linked)
  - `applies across a link boundary` (original spans plain text and link text; link kept on its words)
  - `empty replacement deletes the text`
  - `applies inside a caption and a table cell`
  - `one undo restores the original`
- [ ] **Step 2:** `node --test Scripts/test-editor-evaluate.js`. Expected: FAIL.
- [ ] **Step 3:** Implement. Don't replace the whole match: `tr.insertText` over a range gives it one set of marks and strips a link inside it. Diff `original` against `replacement` by word, and apply only the changed runs, last to first, each with `tr.insertText` at its own position so it takes the marks there. All runs go in one transaction.
- [ ] **Step 4:** PASS. Update the JS count in `CLAUDE.md` and `docs/testing-plan.md`.
- [ ] **Step 5:** Build and run; summarize.

### Task 9: Evaluate panel and two-request flow

**Files:**
- Modify: `Sources/QuillKit/Views/AI/EvaluationPanel.swift`, `Sources/QuillKit/Views/Editor/PostEditorView.swift` (evaluate function near line 1555; `onFindingSelected` at line 443), `Sources/QuillKit/Views/Editor/EditorCoordinator.swift` if a new JS call needs a bridge
- Test: `Tests/QuillTests/EvaluationStateTests.swift` (new)

**Interfaces:**
- Consumes: Tasks 3, 4, 7, 8
- Produces: `public struct EvaluationState { var review: Half<ReviewResult>; var facts: Half<FactCheckResult>; var applied: Set<ReviewFinding.ID>; var statuses: [ReviewFinding.ID: String] }` with `enum Half<T> { case loading, done(T), failed(String), unavailable }`; `facts` is `.unavailable` when Web Search is off or the model lacks it ("Turn on Web Search in Settings to check facts.").

- [ ] **Step 1: Write the failing tests** on `EvaluationState` reducers: `factsFailureKeepsReview`, `reviewFailureKeepsFacts`, `unavailableFactsWhenSearchOff`, `appliedFindingIsMarked`, `applyAllSkipsMissingAndAmbiguous`.
- [ ] **Step 2:** Run; FAIL. **Step 3:** Implement the reducers. **Step 4:** PASS.
- [ ] **Step 5:** `PostEditorView` sends the review and fact-check requests concurrently (`async let`) with `CompletionOptions` (fact-check: `WebSearchUse(maxUses: 8, knownTool: settings.webSearchToolByModel[modelID])`, saving the returned tool), `today: Date()`, `publishedOn` from the loaded post's status and `date`. Each half updates the panel as it lands. Before applying a result, check `appState.selectedItem` still matches the post that started it (Review Focus 5).
- [ ] **Step 6:** Panel per mockup option B: a segmented `Picker` under the header with Review, Fixes *n*, Ideas *n*, Facts *n* (Facts shows "Facts …" while its request runs; counts hidden at zero). It opens on Review, which starts with one line of counts ("7 fixes, 3 ideas, 3 facts to check"), then strengths and priorities. Fixes holds the corrections with Apply All; Ideas the suggestions; Facts the fact checks under "Check these", each with claim, explanation, `sourceQuote`, source host link (opens in the browser), "Use Wording" only with a replacement; Apply calls `applyEvaluationFinding` and marks the row; `findingStatus` after each Apply and on re-show disables rows with "Text has changed". Row click jumps via `findAndSelectText(original)`. The `.inspector` width rule and `SectionLabel` apply.
- [ ] **Step 6b:** Delete the old `evaluatePostPrompt`, `parseEvaluationResponse`, `EvaluationFinding`, `EvaluationResult` and their tests in `AIPromptBuilderTests.swift`, now that nothing calls them.
- [ ] **Step 7:** Build and run on a new local draft (paste the "Reflections on Twenty Years" text, which has known errors). Check: corrections appear before fact checks; Apply edits the draft and ⌘Z restores it; editing a flagged sentence disables its Apply; Web Search off shows the Facts notice. Summarize.

### Task 10: Selection HTML with stubs, and restoring them

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` (`beginAIOperation` line 6403, `showAIResult` line 6459)
- Test: `Scripts/test-ai-output-validity.js`

**Interfaces:**
- Produces: `beginAIOperation()` additionally returns `html` (selection via `DOMSerializer`, reduced: `<a id="L1">`, `<sup id="F1"></sup>`, bare `em`/`strong`/`code`/`s`, no other attributes; lists and tables reduce their container the same way), `before` and `after` (plain text: the rest of the selection's paragraph on each side plus one paragraph further out), `title` is not needed (Swift has it). The stub map lives on the pending operation. `showAIResult(html, cFrom, cTo)` restores stubs before its existing cleanup.

- [ ] **Step 1: Write the failing tests**
  - `selection html reduces links and footnotes to stubs` (link `href`/`target` and the marker's `data-fn` absent from `html`)
  - `before and after carry the rest of the paragraph for a mid-paragraph selection`
  - `showAIResult restores link attributes and the footnote marker by id`
  - `unknown stub id is unwrapped to its text` (`<a id="L9">x</a>` → `x`)
  - `duplicated stub keeps the first and unwraps the rest`
  - `dropped footnote stub leaves no marker and no text loss`
  - `inline result inside a paragraph does not split it` (result with no `<p>` replaces a mid-paragraph selection; paragraph count unchanged)
- [ ] **Step 2:** `node --test Scripts/test-ai-output-validity.js`. Expected: new tests FAIL.
- [ ] **Step 3:** Implement. The marker node is reinserted as the original ProseMirror node, not re-parsed HTML, so `FootnoteSync` keeps its entry.
- [ ] **Step 4:** PASS; existing AI-output tests still pass. Update test counts.
- [ ] **Step 5:** Build and run; summarize.

### Task 11: Selection prompts and the two new commands

**Files:**
- Create: `Sources/QuillKit/AI/SelectionPrompts.swift`
- Modify: `Sources/QuillKit/AI/AIPromptBuilder.swift` (`AIWritingOperation` gains `.fixSpelling`, `.rephrase`; `operationPrompt` removed), `Sources/QuillKit/Views/Editor/PostEditorView.swift` (`executeAIOperation`, line 1607), `Sources/QuillKit/Views/Editor/DroppableWebView.swift` (menu at line 156)
- Test: `Tests/QuillTests/SelectionPromptsTests.swift` (new)

**Interfaces:**
- Consumes: Task 3 (`CompletionOptions`), Task 10 (`html`, `before`, `after`)
- Produces: `struct AISelection { html, plainText, before, after, title: String; context: String? }`; `enum SelectionPrompts { static func system(styleGuide: String?) -> String; static func user(_ s: AISelection, operation: AIWritingOperation) -> String; static func targets(words: Int, operation: AIWritingOperation) -> (target: Int, ceiling: Int); static let schema: [String: Any]; static func parse(_ json: String) throws -> String }`

- [ ] **Step 1: Write the failing tests**: `targetsMatchToday` (the current factors: <40 words ×4/×5 longer, ×0.7/×0.8 shorter; ≤150 ×2/×2.5 and ×0.5/×0.6; above ×1.5/×2 and ×0.4/×0.5), `userPromptWrapsSelectionAndContext` (tags `<post_title>`, `<before>`, `<selection>`, `<after>` in that order), `instructionPerOperation` (each of the four commands carries its spec sentence; Fix and Rephrase carry no targets), `listAndTableKeepContainerInstruction` (list/table context keeps today's per-item wording, now about HTML), `parseReadsHTMLField`.
- [ ] **Step 2:** Run; FAIL. **Step 3:** Implement with the spec's text. **Step 4:** PASS.
- [ ] **Step 5:** `executeAIOperation` builds `AISelection` from the JS result and sends `CompletionOptions(settings:, jsonSchema: SelectionPrompts.schema)`; drop `cleanOperationResult`'s fence stripping (JSON can't carry one) but keep `normalizeAITables`. Guard the post switch as in Task 9. Menu order: Make Longer, Make Shorter, Rephrase, Fix Spelling & Grammar, separator, Convert to Table, Convert to List.
- [ ] **Step 6:** Lists and tables: extend `Scripts/` with a one-off probe (scratch, not committed) that runs Longer, Shorter and Fix on one bullet list and one table from a fixture; confirm container shape and stubs survive before shipping (the prompts spec requires this test).
- [ ] **Step 7:** Build and run on a new local draft: each command on a paragraph with a link and a footnote keeps both; a one-sentence selection stays inside its paragraph; Fix changes only errors. Summarize.

### Task 12: Generate Post

**Files:**
- Modify: `Sources/QuillKit/AI/AIPromptBuilder.swift` (`generatePostPrompt`, `parseGenerateResponse`), `Sources/QuillKit/Views/AI/GeneratePostSheet.swift`, `Sources/QuillKit/Views/Editor/PostEditorView.swift` (sheet at line 272)
- Test: `Tests/QuillTests/AIPromptBuilderTests.swift`

**Interfaces:**
- Produces: `static func generateSystem(styleGuide: String?, today: Date, webSearch: Bool) -> String`, `static func generatePrompt(description: String, webSearch: Bool) -> String`, `static let generateSchema`, `static func parseGenerated(_ json: String) throws -> (title: String, excerpt: String, html: String)`; `GeneratePostSheet.onResult: (String, String, String) -> Void` (title, html, excerpt).

- [ ] **Step 0:** Ask the user whether Generate fills the Excerpt (Open decisions).
- [ ] **Step 1: Write the failing tests**: `generateSystemHasDateAndNoInventionRule`, `withoutSearchOmitsSearchParagraphAndLinkSentence`, `parseGeneratedClosesSpaceBeforePunctuation` (`"honestly , they're"` → `"honestly, they're"`), `parseGeneratedStripsCiteTagsAndNormalizesTables` (keeps the current `<cite>` and table handling).
- [ ] **Step 2:** Run; FAIL. **Step 3:** Implement with the spec's text; remove the `TITLE:`/`CONTENT:` parser and its tests. **Step 4:** PASS.
- [ ] **Step 5:** The sheet sends `CompletionOptions(settings:, baseMaxTokens: 4096 or 16384, webSearch: WebSearchUse(maxUses: 10, knownTool:), jsonSchema:)`, saves the returned tool, and keeps the truncation alert (`Result.truncated`). With a truncated JSON response, parsing fails: treat truncation as "Get Full Version" without parsing.
- [ ] **Step 6:** Build and run: generate "How to choose between Claude Haiku 5.5 and Claude Sonnet 5.5 for the AI features in a writing app" and confirm inline source links, no first-person experiences, and (if approved) the excerpt filled. Summarize.

### Task 13: Documentation and release checks

**Files:**
- Modify: `Sources/QuillKit/AI/CLAUDE.md`, `Sources/QuillKit/Views/AI/CLAUDE.md`, `CLAUDE.md`, `docs/testing-plan.md`, `site/docs.html`

- [ ] **Step 1:** `Sources/QuillKit/AI/CLAUDE.md`: replace the ANCHOR/QUOTE gotcha with "findings carry an exact `original`; Apply refuses missing or ambiguous text"; replace the two web-search fragment/preamble gotchas with "JSON output; web search is always direct; never declare code execution"; add the request-table gotcha (never send disabled thinking; Haiku 4.5's levels are budgets); update the style-guide gotcha (about 500 words, built with the selected model, probe must match). Remove the "must specify HTML structure explicitly" entry only if the new Generate prompt keeps naming the elements (it does; keep it, reworded).
- [ ] **Step 2:** `site/docs.html`: Model and Reasoning, Regenerate (pick sample posts on varied topics), the new Evaluate panel (corrections, suggestions, fact checks, Apply), Rephrase and Fix Spelling & Grammar, Generate's sources.
- [ ] **Step 3:** `docs/testing-plan.md`: new suites and counts; `Scripts/style-guide-probe.py` as a manual check costing a few cents.
- [ ] **Step 4:** `./test.sh` passes; `./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"` passes. Correct the counts in `CLAUDE.md`.
- [ ] **Step 5:** Run the `claude-md-management:revise-claude-md` skill. Summarize the whole change for the user; they decide on the commit.
