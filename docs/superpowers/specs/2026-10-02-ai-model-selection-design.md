# Choosing the AI model and reasoning level

_Design, 2026-10-02._

## Problem

Every AI feature in Quill (style-guide generation, Generate Post, Evaluate, selection rewrites) calls `AnthropicClient.complete`, which defaults to `claude-haiku-4-5` and sends no thinking or effort settings. None of the four call sites pass a model. The web search tool is pinned to `web_search_20250305`, the basic version, even though newer models support `web_search_20260209`, which filters search results before they reach the model.

## Goals

1. The author picks any model their API key can use, and a reasoning level, in Settings → AI Writing. All four AI features use that choice.
2. Quill does not keep a list of models. The list and what each model supports come from the Models API (`GET /v1/models`), so a newly released model appears without an app update.
3. Web search uses the newest tool version the selected model accepts, without a table of which model takes which version.
4. With the defaults (Claude Haiku 4.5, reasoning Off), every request Quill sends is the same as today's, apart from the web search tool version.

Non-goals: streaming responses, a different model per feature, showing prices, and the server-side refusal fallback (see Out of scope).

## Settings

### Layout

Two pop-up menus are added to the AI Writing section, directly after the API key:

```
AI Writing
  Anthropic API Key   [••••••••••••]
  Model               [Claude Haiku 4.5        ▾]
  Reasoning           [Off                     ▾]
                      Higher levels think longer before answering.
                      Responses take more time and cost more.
  Writing Style       Choose Posts   3 posts selected
  Web Search          [✓]
```

- **Model** lists every model returned by the Models API, newest first (by `created_at`), labelled with `display_name`. With no API key it is disabled, with the caption "Enter an API key to load models." No models are hidden; retired models drop out of the API's list on their own.
- **Reasoning** lists only the options the selected model supports (below). Its caption is the same for every model.
- Both are standard macOS pop-up `Picker`s, matching the system `.roundedBorder` style of the other inputs.

### Reasoning options

The options come from the selected model's `capabilities` in the Models API response:

| Model capability | Options shown | Default |
|---|---|---|
| `thinking.types.adaptive.supported` | "Model default", then each effort level whose `effort.<level>.supported` is true (Low, Medium, High, Extra High, Max) | Model default |
| `thinking.types.enabled.supported` only (Claude Haiku 4.5) | Off, Low, Medium, High | Off |
| Neither | Off (menu disabled) | Off |

There is no Off for adaptive models because some of them (Claude Opus 5.5, Claude Sonnet 5.5) reject a request that turns thinking off. "Model default" exists because the Models API does not report each model's default effort (Claude Opus 5.5 defaults to Medium, Claude Sonnet 5.5 to High).

For enabled-only models, Low/Medium/High are Quill's labels for a fixed thinking budget, not API levels. The pane does not explain the difference: for the author, both mean "more thinking, slower, costs more."

| Label | `budget_tokens` |
|---|---|
| Low | 2,048 |
| Medium | 8,192 |
| High | 16,384 |

When the author switches models and the saved reasoning option does not exist for the new model, reasoning resets to that model's default.

### Loading the model list

- Fetched when Settings opens with a saved API key, and when the author finishes editing the key field (on submit or focus loss), not on every keystroke.
- The fetched list, including each model's `capabilities` and `max_tokens`, is saved in `AISettings`, so Settings and every AI call work offline from the last fetch.
- If the fetch fails, Settings keeps the saved list and shows the error as a caption under Model.
- If the saved model is not in a successful fetch, Settings switches to Claude Haiku 4.5 and shows "Your saved model is no longer available. Switched to Claude Haiku 4.5." If Haiku 4.5 is not in the list either, it switches to the first model in the list.

## Data model

`AISettings` (`Sources/QuillKit/AI/AISettings.swift`) gains:

- `model: String`, default `"claude-haiku-4-5"`
- `reasoning: AIReasoning`, default `.off`; cases `.off`, `.modelDefault`, `.level(String)` where the string is the API effort name (`low`, `medium`, `high`, `xhigh`, `max`)
- `models: [AIModelInfo]`, default empty: the last fetched list; each has `id`, `displayName`, `createdAt`, `maxTokens`, `supportsAdaptiveThinking`, `supportsEnabledThinking`, `effortLevels: [String]`
- `webSearchToolByModel: [String: String]`, default empty: the web search tool type that last worked for each model ID (see Web search)

All new fields decode with defaults when absent, so an existing `ai_settings.json` loads unchanged.

## Building the request

`AnthropicClient.complete` takes the selected `AIModelInfo` (or `nil` when no list has been fetched yet) and the `AIReasoning` value instead of a bare model string. The request body is built by one pure function so it can be tested without a network call.

| Selected model | Reasoning | `thinking` | `output_config` |
|---|---|---|---|
| Adaptive | Model default | `{"type": "adaptive"}` | omitted |
| Adaptive | a level | `{"type": "adaptive"}` | `{"effort": "<level>"}` |
| Enabled only | Off | omitted | omitted |
| Enabled only | Low/Medium/High | `{"type": "enabled", "budget_tokens": N}` | omitted |
| Unknown (`nil`) or neither | any | omitted | omitted |

The client never sends `{"type": "disabled"}`.

### `max_tokens`

Thinking tokens count against `max_tokens`, so each call site's base value is raised when thinking is on:

- Enabled-only model with a budget: base + `budget_tokens`.
- Adaptive model: base + 16,000.
- The result is capped at the model's `max_tokens` from the Models API.

Base values stay as they are: 4,096 for Evaluate, rewrites and style-guide generation; 4,096 for Generate, rising to 16,384 when the author picks "Get Full Version" in the truncation alert.

### Timeout

`AnthropicClient.sharedSession` sets `timeoutIntervalForRequest` to 600 seconds. Requests do not stream, so no bytes arrive until the whole response is ready. The 60-second default would fail a long Opus generation with web search.

## Web search

The Models API has no web search capability field (checked against the Models API reference, 2026-10-02), so the version a model accepts cannot be looked up. Some hard-coding cannot be avoided: Quill has to know the type string of each version, and a future version may change the response format. What can be avoided is a model-to-version table.

- `AnthropicClient` holds one ordered list of known versions, newest first: `["web_search_20260209", "web_search_20250305"]`.
- For a model with no entry in `webSearchToolByModel`, the first web search request tries the newest version. If the API answers 400 and the error message names the tool type, the client retries once with the next version, and so on down the list.
- The version that succeeds is saved in `webSearchToolByModel[modelID]`, so later requests skip the failed attempts. A rejected request costs no tokens.
- Adding a future version means adding one string to the front of the list.

During implementation, check the exact 400 error text the API returns for an unsupported tool version, and match on it narrowly so other 400s are not retried.

`web_search_20260209` filters results using code execution internally. Quill must not also declare a `code_execution` tool.

### `pause_turn`

Long server-tool turns can end with `stop_reason: "pause_turn"`. The client then sends the request again with the returned assistant content appended as an assistant message, up to three times, and joins the text from every response. This requires keeping each response's content blocks as raw JSON, not only the decoded text.

## Error handling

- **Refusal.** When `stop_reason` is `"refusal"`, `complete` throws a new `AnthropicError.refused`, with the description "Claude declined this request." It does not return partial text.
- **Truncation.** Unchanged: `Result.truncated` is true when `stop_reason` is `"max_tokens"`.
- **Account-specific rejections** (for example, a model that requires data retention the account does not allow) arrive as ordinary 400s and use the existing `httpError` message.

## Call sites

All four read the model and reasoning from `AISettings`:

- `PreferencesView.saveAll` (style guide)
- `GeneratePostSheet.generate`
- `PostEditorView` Evaluate
- `PostEditorView` selection rewrites

## Tests

In `Tests/QuillTests/AnthropicClientTests.swift`:

- Request body for each row of the request table, including that `{"type": "disabled"}` is never sent.
- `max_tokens` for an enabled-only budget, an adaptive model, and the cap at the model's limit.
- Web search: newest version tried first; a matching 400 retries with the next version and records it; an unrelated 400 is not retried; a recorded version is used directly.
- `pause_turn`: content from each continuation is joined; stops after three continuations.
- `stop_reason: "refusal"` throws `.refused`.
- `AISettings` decodes a settings file written before this change.
- Model list decoding from a Models API response, sorted newest first.

Update the Swift test count in `CLAUDE.md` and `docs/testing-plan.md`.

## Documentation

- `Sources/QuillKit/AI/CLAUDE.md`: a gotcha for the request table (never send disabled thinking; Haiku's levels are budgets) and one for the web search version fallback.
- `site/docs.html`: describe the Model and Reasoning settings.

## Out of scope

- **Server-side refusal fallback** (`fallbacks: "default"`). It only applies to some models, and the Models API does not report which, so sending it with an arbitrary model risks a 400. Revisit if refusals turn out to be common.
- **Streaming.** The longer timeout covers the immediate risk.
- **Per-feature models**, for example a fast model for rewrites and a stronger one for Generate.
- **Prices in Settings.** The Models API does not report them.
