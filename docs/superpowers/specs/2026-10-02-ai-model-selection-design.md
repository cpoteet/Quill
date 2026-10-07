# Choosing the AI model and reasoning level

_Design, 2026-10-02._

## Problem

Every AI feature in Quill (style-guide generation, Generate Post, Evaluate, selection rewrites) calls `AnthropicClient.complete`, which defaults to `claude-haiku-4-5` and sends no thinking or effort settings. None of the four call sites pass a model. The web search tool is pinned to `web_search_20250305`, the basic version, even though newer models support `web_search_20260209` and `web_search_20260318`.

## Goals

1. The author picks any model their API key can use, and a reasoning level, in Settings → AI Writing. All four AI features use that choice.
2. Quill does not keep a list of models. The list and what each model supports come from the Models API (`GET /v1/models`), so a newly released model appears without an app update.
3. Web search uses the newest tool version the selected model accepts, without a table of which model takes which version.
4. The default is the newest Haiku the API lists (Claude Haiku 5.5 as of 2026-10-07) at the model's default reasoning level, and it follows new Haiku releases without an app update (see Default model).
5. The style guide describes the author's writing more accurately, and the author can regenerate it at any time, for example after switching models (see Style-guide generation).

Non-goals: streaming responses, a different model per feature, showing prices, and the server-side refusal fallback (see Out of scope).

## Settings

### Layout

Two pop-up menus are added to the AI Writing section, directly after the API key:

```
AI Writing
  Anthropic API Key   [••••••••••••]
  Model               [Claude Haiku 5.5        ▾]
  Reasoning           [Model default           ▾]
                      Higher levels think longer before answering.
                      Responses take more time and cost more.
  Writing Style       Choose Posts   3 posts selected
                      Regenerate
  Web Search          [✓]
```

- **Model** lists every model returned by the Models API, newest first (by `created_at`), labelled with `display_name`. With no API key it is disabled, with the caption "Enter an API key to load models." No models are hidden; retired models drop out of the API's list on their own.
- **Reasoning** lists only the options the selected model supports (below). Its caption is the same for every model.
- Both are standard macOS pop-up `Picker`s, matching the system `.roundedBorder` style of the other inputs.
- **Regenerate** rebuilds the style guide from the selected posts with the current model. Today the guide is rebuilt only when the selected post IDs or the site change, so there is no way to refresh it after switching models or after the prompt below ships. The button is disabled with no API key or no samples, and shows the existing analyzing state while it runs. Changing the model does not regenerate the guide on its own.

### Reasoning options

The options come from the selected model's `capabilities` in the Models API response:

| Model capability | Options shown | Default |
|---|---|---|
| `thinking.types.adaptive.supported` | "Model default", then each effort level whose `effort.<level>.supported` is true (Low, Medium, High, Extra High, Max) | Model default |
| `thinking.types.enabled.supported` only (Claude Haiku 4.5) | Off, Low, Medium, High | Off |
| Neither | Off (menu disabled) | Off |

There is no Off for adaptive models. Some of them (Claude Opus 5.5, Claude Sonnet 5.5) reject a request that turns thinking off, and on Claude Haiku 5.5, which accepts it, Anthropic's prompting guide reports reasoning-like text leaking into the reply with thinking off. Low is the cheap option instead. "Model default" exists because the Models API does not report each model's default effort (Claude Opus 5.5 defaults to Medium, Claude Sonnet 5.5 to High).

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
- If the saved model is not in a successful fetch, Settings switches back to the default model and shows "Your saved model is no longer available. Switched to <display name>."

### Default model

Quill does not pin a default model ID. The default is the newest model (by `created_at`) whose Models API `line` is `"haiku"`, so the next Haiku becomes the default when it ships. Before the first successful fetch, and if no listed model has that line, the default is `claude-haiku-5-5`. An author who has never picked a model follows the default; picking one in the menu pins it.

Haiku 5.5 was chosen on 2026-10-07 from the style-guide probe (see Findings): it is far more accurate than Claude Haiku 4.5 at about a seventh of the cost per run, and close to Claude Sonnet 5.5.

## Data model

`AISettings` (`Sources/QuillKit/AI/AISettings.swift`) gains:

- `model: String?`, default `nil`, meaning the default model (see Default model)
- `reasoning: AIReasoning`, default `.modelDefault`; cases `.off`, `.modelDefault`, `.level(String)` where the string is the API effort name (`low`, `medium`, `high`, `xhigh`, `max`)
- `models: [AIModelInfo]`, default empty: the last fetched list; each has `id`, `displayName`, `createdAt`, `maxTokens`, `line`, `supportsAdaptiveThinking`, `supportsEnabledThinking`, `effortLevels: [String]`, `supportsWebSearch`
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

The Models API reports whether a model accepts web search at all (`capabilities.server_tools.web_search.supported`), but not which version (checked 2026-10-07). When it is false, the Web Search checkbox is disabled with the caption "This model can't search the web," and requests omit the tool. For a model that supports it, the version still cannot be looked up. Some hard-coding cannot be avoided: Quill has to know the type string of each version, and a future version may change the response format. What can be avoided is a model-to-version table.

- `AnthropicClient` holds one ordered list of known versions, newest first: `["web_search_20260318", "web_search_20260209", "web_search_20250305"]`. Quill always sends the newest version the model accepts.
- For a model with no entry in `webSearchToolByModel`, the first web search request tries the newest version. If the API answers 400 and the error message names the tool type, the client retries once with the next version, and so on down the list.
- The version that succeeds is saved in `webSearchToolByModel[modelID]`, so later requests skip the failed attempts. A rejected request costs no tokens.
- Adding a future version means adding one string to the front of the list.

During implementation, check the exact 400 error text the API returns for an unsupported tool version, and match on it narrowly so other 400s are not retried.

### How Claude calls search

From `web_search_20260209` on, the tool defaults to dynamic filtering: Claude calls search from Python it writes and filters the results before reading them. Each feature chooses, through the tool's `allowed_callers` field, which every version accepts:

- **Evaluate's fact-check sends `allowed_callers: ["direct"]`.** It makes a few targeted lookups, and on 2026-10-07 Claude Haiku 5.5's search code crashed in 7 of 8 runs, costing twice as much for fewer fact checks (see `2026-10-07-ai-prompts-design.md`).
- **Generate Post also sends `allowed_callers: ["direct"]`.** Tested on 2026-10-07: dynamic filtering's code crashed two or three times per post, linked fewer sources, cost about twice as much and once took over two minutes.

Dynamic filtering runs in code execution that the API provisions itself. Quill must not also declare a `code_execution` tool.

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

## Style-guide generation

The style guide uses the selected model and reasoning level like every other feature; it has no model of its own. The prompt and sample format below were tested on 2026-10-03 with `Scripts/style-guide-probe.py` (see Findings).

### Samples

`PreferencesView.saveAll` currently replaces every tag with a space. Claude never sees headings, lists, captions or post titles, and entities such as `&#8217;` are left in the text. Each sample becomes:

```
--- Sample 1: Building a WordPress Editor for the Mac (1,093 words) ---
<p>I've used a lot of WordPress editors…</p>
<h2>Why native</h2>
<ul><li>…</li></ul>
[image]
<figcaption>The editor in dark mode</figcaption>
```

- The title is `title.rendered` with entities decoded.
- The word count is the number of words in the reduced body with its tags removed, written with a thousands separator.
- `h1`–`h6`, `p`, `ul`, `ol`, `li`, `blockquote`, `a`, `em`, `strong`, `i`, `b`, `sup`, `figcaption`, `table`, `tr`, `th` and `td` are kept with every attribute removed, link URLs included. Each `<img>` becomes `[image]` on its own line. Every other tag is removed and its text kept. `<br>` and removed block tags (`div`, `figure`, `pre` and the like) become a line break, so the words on either side are not joined. Elements left empty are dropped, and each block element starts a new line.
- Entities are decoded with the table `stripHTML` already uses, moved into a helper both functions share, except `&lt;`, `&gt;` and `&amp;`, which stay encoded. A post that writes about `<em>` as text must not gain a real `<em>` tag. The word count strips tags first, then decodes those three.

The reduction is a pure function in `AIPromptBuilder`, so it is tested without a network call. `styleGuideGenerationPrompt` takes the reduced samples with their titles and word counts.

### Prompt

The system prompt stays "Return only the requested style guide with no preamble." The user message is this text followed by the samples:

```text
Analyze these blog post samples and write a style guide that another writer can follow to write new posts in this author's style. The guide will be used both to write new posts and to judge whether a draft sounds like this author.

Each sample is one post's title, word count and body. The HTML has been reduced to its structure: headings, paragraphs, lists, tables, block quotes, links, emphasis and footnotes. Images appear as [image], followed by their caption if they have one.

Rules:
- Write each point as an instruction to the writer ("Open with…", "Use…"), not as a description of the author.
- Describe how the author writes, not what they write about. Leave out topics, products, hobbies and projects from the samples unless they show a habit that would carry over to any subject.
- State a pattern only if it appears in at least two samples. Leave out generic writing advice.
- Describe habits as tendencies ("often", "now and then"), not as rules to apply every time.
- You may illustrate a habit with a word or short phrase in quotation marks, copied exactly from the samples. Never quote a whole sentence, and don't name products or technologies.

Use exactly these labels, in this order, with nothing added to them. Under each label, write a short paragraph or a few bullets:

Voice and tone:
Sentence rhythm:
Vocabulary:
Humor and personality:
Openings and closings:
Structure and length:
Formatting:
Avoid:

Formatting covers headings, lists, tables, footnotes, links, images and captions. Avoid covers things a generic writer would do that this author doesn't, and only where the samples make it clear.

Aim for about 500 words. Start your response with "Voice and tone:" and end it after the Avoid section.
```

The base `max_tokens` of 4,096 holds a 500–600-word guide (about 1,400 output tokens).

### Using the guide

`systemPrompt(styleGuide:)` introduces the guide with this text instead of "Write in this author's style:":

> Write in this author's style, following the guide below. Quoted words and phrases are examples of the author's habits, not phrases to reuse; use them sparingly.

The guide names real words from the author's posts, and the models did not reliably limit them to words used in several posts, so this line is what keeps a single post's phrase from turning into a tic in generated text. `evaluatePostPrompt` is unchanged; there, the quotes help the evaluator recognise the author's voice as intentional.

### Findings

Four prompt versions were run once each against the five sample posts. Outputs vary between runs, so these are strong signals, not measurements.

- **Fixing the input helped more than any wording.** Titles and real word counts ended invented length claims ("1,500 to 4,000+ words" for posts of 1,093–2,557). Structural markup is what made the Formatting and Openings sections possible.
- **The models follow instructions about what to do:** the fixed labels, the first line, writing instructions instead of descriptions, describing tendencies, copying quotes exactly (made-up quotes fell from 4 to 0).
- **They don't reliably follow instructions that need counting or holding back:** word limits (overshot by 10–80%), "at least two samples" (26 of 42 quotes came from a single post), "never quote a whole sentence", "don't name products". Rewording one of these brought back a different failure, so the remaining risk is handled where the guide is used (Using the guide), not in more prompt wording.
- **Claude Sonnet 5.5 was much more accurate than Claude Haiku 4.5.** Haiku claimed frequent sentence fragments (5 in 382 sentences), a favourite verb that never appears, and italics used for one word only. Haiku 4.5 is a year older than Sonnet 5.5, so rerun the probe when a newer Haiku ships before drawing conclusions about the default.
- **Rerun on 2026-10-07 with Claude Haiku 5.5** (five posts on varied topics, two runs per setting):

  | Model | Words | Cost per run | Result |
  |---|---|---|---|
  | Claude Haiku 4.5 | 436–492 | $0.012 | Accurate but generic ("Avoid abrupt endings"); overstates habits (footnotes "liberally", in 2 of 5 posts). |
  | Claude Haiku 5.5, low | 479–500 | $0.002 | Specific, mostly accurate habits: semicolon-stacked sentences, "However / Plus / Also" openers, wry parentheticals, footnotes as an end list. |
  | Claude Haiku 5.5, medium (default) | 456–485 | $0.002 | Same as low. One run claimed "no call to action" for a post that ends on a download link. |
  | Claude Haiku 5.5, high | 448–467 | $0.004 | About 6× the thinking tokens of low with no visible gain. |
  | Claude Sonnet 5.5 | 644–660 | $0.036 | Most perceptive (a neutral voice for explainer posts, cranky remarks kept in footnotes); overshoots the length by 30%. |

  Haiku 5.5 was the only model to keep to the ~500-word target. Quotes per guide rose from 7–12 on Haiku 4.5 to 22–40, still about half from a single post, which makes the line in Using the guide more important. The table rows were a run of bare lines, because the reduction dropped table tags; tables are now kept.
- **The samples limit what the guide can learn.** When most samples share a topic, the guide treats it as style ("stress that human expertise matters when using AI"). Picking samples on varied topics improves the guide more than prompt changes.

`Scripts/style-guide-probe.py <model-id> [effort]` reruns the test with the author's saved samples, API key and site credentials from Quill's Application Support folder. It prints the guide, then its word count, token usage and how many quotes appear in two or more samples, one, or none. Its prompt and sample reduction must match `AIPromptBuilder`.

## Tests

In `Tests/QuillTests/AnthropicClientTests.swift`:

- Request body for each row of the request table, including that `{"type": "disabled"}` is never sent.
- `max_tokens` for an enabled-only budget, an adaptive model, and the cap at the model's limit.
- Web search: newest version tried first; a matching 400 retries with the next version and records it; an unrelated 400 is not retried; a recorded version is used directly.
- `pause_turn`: content from each continuation is joined; stops after three continuations.
- `stop_reason: "refusal"` throws `.refused`.
- `AISettings` decodes a settings file written before this change.
- Model list decoding from a Models API response, sorted newest first.

In `Tests/QuillTests/AIPromptBuilderTests.swift`:

- Sample reduction: kept tags lose their attributes, `<img>` becomes `[image]`, other tags are removed with their text kept, `<br>` and removed block tags keep words apart, empty elements are dropped, entities are decoded, and `&lt;em&gt;` in prose stays encoded rather than becoming a tag.
- The sample header carries the title and a formatted word count.
- `styleGuideGenerationPrompt` contains the eight labels in order and numbers the samples.
- `systemPrompt(styleGuide:)` includes the line about quoted words; the existing tests for a nil or empty guide still pass.

Update the Swift test count in `CLAUDE.md` and `docs/testing-plan.md`.

## Documentation

- `Sources/QuillKit/AI/CLAUDE.md`: a gotcha for the request table (never send disabled thinking; Haiku's levels are budgets) and one for the web search version fallback. Update the style-guide gotcha: about 500 words instead of 150, built with the selected model, and `Scripts/style-guide-probe.py` must be kept in step with the prompt and sample reduction.
- `site/docs.html`: describe the Model and Reasoning settings and the Regenerate button, and suggest picking sample posts on varied topics.
- `docs/testing-plan.md`: list `Scripts/style-guide-probe.py` as a manual check that costs a few cents per run.

## Out of scope

- **Server-side refusal fallback** (`fallbacks: "default"`). It only applies to some models, and the Models API does not report which, so sending it with an arbitrary model risks a 400. Revisit if refusals turn out to be common.
- **Streaming.** The longer timeout covers the immediate risk.
- **Per-feature models**, for example a fast model for rewrites and a stronger one for Generate.
- **Prices in Settings.** The Models API does not report them.
