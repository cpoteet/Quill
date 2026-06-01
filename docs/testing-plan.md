# Quill — In-Depth Testing Plan

_Last updated: 2026-05-31 (third pass — items 1 & 2 implemented)_

> **Changes since first draft (what this revision accounts for):**
> - **Storage refactored** — new generic `JSONFileStore<T>` + `AppSupportDirectory`
>   with a `.override` test seam. `KeychainStore` and `AISettingsStore` are now thin
>   wrappers over it. This collapses the old per-store credential/settings tests into
>   one generic suite and makes file-store tests trivial to isolate (see §3.5).
> - **AI selection UX changed** — the floating "selection pill" was removed
>   (`SelectionPillPanel` is gone); selection operations are now **right-click context
>   menu** items in `DroppableWebView` (`Make Longer/Shorter`, `To Table`, `To List`).
>   §7.10 / §7.13 updated accordingly.
> - **New blockquote `<cite>` attribution node** — a Tiptap `Cite` node, auto-inserted
>   on blockquote toggle, with Enter/Backspace behavior and **empty-cite stripping** in
>   `toWordPressHTML`. New JS + manual cases added (§6.1, §7.3).
> - **AI-accept now runs the Gutenberg transform** — accepted AI results are serialized
>   through `toWordPressHTML`, not inserted raw (§7.10).
> - **H4–H6 heading levels, File-menu commands, two-column media detail** — minor; folded
>   into existing checklists.
> - **Test suite itself is unchanged** — still the original 5 suites; items 1–6 of the
>   implementation order remain unbuilt. `AnthropicClient.session` is still a
>   `private static let` (not yet injectable), so §4.2/§5 refactor still applies.
>
> **Items 1 & 2 implemented (2026-05-31):** 5 new test files added, suite grows from
> 24 → 80 tests (all passing). See §10 for updated status.
> - `WPPostDecodingTests.swift` (9 tests) — §1.1
> - `WPMediaDecodingTests.swift` (7 tests) — §1.2
> - `PostPayloadTests.swift` (11 tests) — §1.3
> - `CredentialsTests.swift` (4 tests) — §1.5
> - `AIPromptBuilderTests.swift` (21 tests) — §4.1
> - `KeychainStoreTests.swift` updated: `struct` → `final class`, added `deinit` cleanup

This plan covers the entire Quill macOS app: the Swift business logic, the
SQLite storage layer, the WordPress and Anthropic network clients, the
Tiptap/JavaScript editor bridge, and the SwiftUI/AppKit UI. It is organized so
that the cheapest, most deterministic tests (pure-Swift unit tests) come first,
then the harder-to-automate layers (JS editor, UI), then manual/functional
checklists, and finally a regression matrix tied to the documented "known
gotchas" — the bugs most likely to silently reappear.

Each section lists **what to test**, **the concrete cases (including edge
cases)**, and **how** (automated vs. manual).

---

## 0. Test infrastructure & how to run

- **Framework:** `swift-testing` (already a dependency in `Package.swift`). Test
  target is `QuillTests` at `Tests/QuillTests/`.
- **Run all tests:** `swift test`
- **Run one suite:** `swift test --filter WordPressClientTests`
- **Existing helpers worth reusing:**
  - `MockURLProtocol` (in `WordPressClientTests.swift`) — install via
    `URLSessionConfiguration.ephemeral` + `protocolClasses`. **Extract this into
    its own file** (e.g. `Tests/QuillTests/Support/MockURLProtocol.swift`) so
    every networking suite can share it instead of redefining it.
  - `AppDatabase.inMemory()` — gives each storage suite an isolated in-memory DB.
- **Suite serialization:** Network and keychain suites that mutate shared global
  state (`MockURLProtocol.requestHandler`, the on-disk credentials file) must
  keep `@Suite(.serialized)`. Storage suites using `inMemory()` can run in
  parallel.

### Current coverage snapshot (baseline)

| Module | File | Status |
|---|---|---|
| `WordPressClient` | `WordPressClientTests.swift` | Partial — fetch/trash/searchLinks only |
| `DraftStore` | `DraftStoreTests.swift` | Good — CRUD covered |
| `AutosaveStore` | `AutosaveStoreTests.swift` | Partial — no delete test |
| `TaxonomyCache` | `TaxonomyCacheTests.swift` | Partial — categories only, no tags |
| `KeychainStore` | `KeychainStoreTests.swift` | Good — now wraps `JSONFileStore`; uses `AppSupportDirectory.override` |
| `JSONFileStore<T>` (new) | — | **None** — generic store under everything below |
| `AppSupportDirectory` (new) | — | **None** — dir resolver + `.override` test seam |
| `AISettingsStore` | — | **None** — now wraps `JSONFileStore` |
| `WPPost`/`WPMedia` decoding | `WPPostDecodingTests.swift`, `WPMediaDecodingTests.swift` | ✅ Done — 16 tests |
| `PostPayload` encoding | `PostPayloadTests.swift` | ✅ Done — 11 tests |
| `AIPromptBuilder` | `AIPromptBuilderTests.swift` | ✅ Done — 21 tests |
| `AnthropicClient` | — | **None** — requires injectable session refactor first |
| `Credentials.basicAuthHeader` | `CredentialsTests.swift` | ✅ Done — 4 tests |
| `AppState` computed props | — | **None** |
| `editor.html` JS transforms | — | **None** |
| UI flows | — | **None (manual only)** |

The biggest gaps with the highest bug risk are: **model decoding**,
**`PostPayload` encoding**, **`AIPromptBuilder.parseGenerateResponse`**, and the
**`toWordPressHTML` JS transform**. Prioritize those.

---

## 1. Model decoding & encoding (pure unit tests — highest ROI)

These are pure `Codable` functions with hand-written `init(from:)` containing
defaulting logic that has already caused production bugs (see gotchas about
float dimensions and missing taxonomy fields). They are trivial to test and
catch real regressions.

### 1.1 `WPPost` decoding (`Sources/QuillKit/API/Models/WPPost.swift`)

Add `WPPostTests`:

- **Full post** decodes all fields correctly.
- **Pages omit `categories`/`tags`** → both default to `[]` (the documented
  Pages-endpoint gotcha). Feed JSON with those keys absent and assert no throw.
- **Missing `type`** → defaults to `"post"`.
- **Missing `featured_media`** → defaults to `0`.
- **Missing `date_gmt`** → defaults to `""`.
- **Missing `parent`** → defaults to `0`; **missing `comment_status`** →
  defaults to `"open"`.
- **`content.raw` present vs. absent** → `content.raw` is the field
  `PostEditorView` prefers; verify both `rendered` and optional `raw` decode.
- **Edge:** `featured_media` as `0` vs. a real ID; `status` values `publish`,
  `draft`, `future`, `private`, `pending`, `trash`.
- **Edge:** required fields genuinely missing (`id`, `status`, `date`,
  `modified`, `slug`, `link`) → assert it **throws** (these are not optional).
- **Round-trip:** encode a decoded `WPPost` and confirm `CodingKeys` map back
  (`date_gmt`, `featured_media`, `comment_status`).

### 1.2 `WPMedia` / `MediaDetails` / `MediaSize` (`WPMedia.swift`)

This is the documented float-dimensions gotcha. Add `WPMediaTests`:

- **Integer dimensions** (`"width": 2560`) decode to `Int`.
- **Float dimensions** (`"width": 2560.0`) decode to `Int` via the
  try-Int-then-Double path. **This is the regression guard** — assert it does
  not throw and truncates correctly.
- **Missing `media_details`** → `nil`, no throw.
- **Missing `title`** → defaults to empty `RenderedString`.
- **`sizes` map** with named sizes (`thumbnail`, `medium`, `large`, `full`)
  decodes into `[String: MediaSize]`.
- **`sizes` with float width/height** → `MediaSize` truncates to `Int`.
- **Malformed `sizes`** (e.g. `sizes` is `[]` instead of object) → `try?`
  swallows it to `nil`; verify the whole `WPMedia` still decodes.
- **Edge:** `media_type` `"file"` vs `"image"`; non-image mime types.

### 1.3 `PostPayload` encoding (`WPPost.swift`)

This drives every create/update. Encoding bugs corrupt published content
silently. Add `PostPayloadTests` decoding the emitted JSON back into a
dictionary:

- **`date_gmt` key** is emitted (never `date`) when `dateGmt` is set — the
  scheduling gotcha. Assert the JSON key is literally `date_gmt`.
- **`featured_media` key name** correct.
- **`comment_status` key name** correct.
- **`slug` omitted when nil** (so the server value is preserved) — pass `nil`
  and assert the key is **absent** from the JSON.
- **`parent` for pages vs. nil for posts** — encode with `parent: nil` and
  assert absent; with `parent: 5` and assert present.
- **`dateGmt: nil`** → `date_gmt` key absent.
- **`featuredMedia: nil`** → `featured_media` key absent.
- **Empty `categories`/`tags`** arrays still encode as `[]`.

### 1.4 `LinkSearchResult` / `LinkResultType`

- ID construction `"\(type.rawValue)-\(id)"` matches what
  `searchLinks` produces (already asserted indirectly; add a direct unit test of
  the model if it has its own init logic).

### 1.5 `Credentials.basicAuthHeader` (`Auth/Credentials.swift`)

- **Known vector:** `user:pass` → `"Basic dXNlcjpwYXNz"`. Assert exact base64.
- **Edge:** app password containing spaces (WordPress app passwords are
  space-grouped, e.g. `xxxx yyyy zzzz`) — spaces are part of the secret and must
  be base64-encoded verbatim, not stripped.
- **Edge:** Unicode/non-ASCII in username → encoded via UTF-8 bytes
  (`Data(raw.utf8)`), assert correct.
- **Edge:** empty username or empty password → still produces a header (don't
  crash); document expected behavior.

> Note: `Credentials` persistence now goes through `KeychainStore` →
> `JSONFileStore<Credentials>`. Persistence behavior is tested generically in §3.5;
> the existing `KeychainStoreTests` should be updated to set
> `AppSupportDirectory.override` to a temp dir in its `init` (instead of relying on
> the real Application Support path) so it never touches real user credentials.

---

## 2. Networking — `WordPressClient` (mock-backed unit tests)

Extend `WordPressClientTests` using the shared `MockURLProtocol`. The existing
tests cover `fetchPosts`, `trashPost/Page`, and `searchLinks`. Fill the gaps and
add edge cases.

### 2.1 URL & request construction (capture the request, assert on it)

- **`fetchPosts` query**: `per_page`, `page`, `context=edit`, and
  `status=publish,draft,private,future,pending` are all present.
- **`fetchPages`** hits `/wp-json/wp/v2/pages` (not `/posts`).
- **`createPost`** → `POST /posts`, body is JSON, `Content-Type: application/json`.
- **`updatePost`** → `PUT /posts/{id}`.
- **`createPage`/`updatePage`** → `/pages` endpoints + correct method.
- **Authorization header** present on every request (`Basic …`) — assert from a
  captured request.
- **`uploadMedia`** sets `Content-Type` to the passed mime type and
  `Content-Disposition` with both `filename="…"` and `filename*=UTF-8''…`.
  - **Edge:** filename with spaces/unicode (`café photo.jpg`) → percent-encoded
    in the `filename*` part, raw in `filename`.
  - **Edge:** filename that fails percent-encoding → falls back to raw filename
    (the `?? filename` path).
- **`deleteMedia`** → `DELETE /media/{id}?force=true` (permanent — contrast with
  trash's `force=false`).
- **`createAutosave`/`createPageAutosave`** → `POST /posts/{id}/autosaves` and
  `/pages/{id}/autosaves`.
- **`fetchCategories`/`fetchTags`** → `per_page=100`.
- **`createCategory`/`createTag`** → `POST` with `{"name": …}` body.

### 2.2 Response handling & error mapping (`perform` / `performVoid`)

- **2xx with valid JSON** → decodes (covered for posts; add for media, taxonomy).
- **Any status ≥ 300** → throws `APIError.httpError(statusCode:body:)` with the
  **body string preserved**. Test 400, 401, 403, 404, 500.
  - **Edge:** non-UTF8 body bytes → `body` becomes `""` (the `?? ""` path), no
    crash.
- **Valid 2xx but malformed/garbage JSON** → throws `APIError.decodingError`
  (not `httpError`). This distinction matters for user-facing messages.
- **Network failure** (have `MockURLProtocol` throw a `URLError`) →
  `APIError.networkError`.
- **Cancellation:** a `CancellationError` or `URLError(.cancelled)` is re-thrown
  as `CancellationError`, **not** wrapped in `APIError.networkError`. This is
  explicit code in both `perform` and `performVoid` — test both paths. (Matters
  because autosave/load tasks get cancelled on fast navigation.)
- **`performVoid` on 204/empty body** → succeeds without trying to decode.

### 2.3 `searchLinks` (partially covered — extend)

- **All three sub-requests succeed** → merged & ordered posts, terms, media
  (covered).
- **One sub-request fails** → ignored, others still returned (covered for the
  media/term failure; also test the **posts** request failing while terms
  succeed).
- **All three fail** → returns `[]` (not a throw). The `try?` swallows each.
- **subtype routing:** `subtype == "page"` → `.page`, else `.post`;
  `subtype == "tag"` → `.tag`, else `.category`. Test a `subtype` value that's
  neither to confirm the else-branch.
- **Edge:** empty query string still issues requests (no client-side guard).
- **Edge:** media item with empty `source_url` still produces a result.

### 2.4 Concurrency

- `searchLinks` issues the three `async let` fetches concurrently — verify with
  a handler that records request order/timing isn't relied upon (the merge order
  is deterministic regardless of completion order). A test that delays the posts
  response but still expects posts first in the result proves ordering is by
  construction, not by arrival.

---

## 3. Storage layer (SQLite — in-memory unit tests)

### 3.1 `DraftStore` (well covered — add edge cases)

- **Empty title/content** create & fetch (new drafts start blank).
- **`update` on a non-existent id** → no-op, no throw (SQLite update matches 0
  rows). Confirm behavior is intentional.
- **`delete` on a non-existent id** → no throw.
- **`fetchAll` ordering** is by `updated_at DESC` — create A, create B, update
  A, assert A now sorts first.
- **Very large content** (multi-MB HTML) round-trips intact.
- **Unicode / emoji / curly quotes** in title and content round-trip byte-exact
  (ties to the curly-quotes gotcha).
- **`type` defaulting**: a row inserted before the `type` column existed (or via
  raw SQL without `type`) reads back as `"post"` (the `defaultValue` + ALTER
  migration). Simulate by inserting via raw SQL.

### 3.2 `AutosaveStore`

- `saveAndLoad`, `loadReturnsNilForUnknownPost`, `saveOverwritesExisting` —
  covered.
- **Add `delete`** test (used by `save(force:)` after a successful publish to
  clear the stash, and the gotcha around spurious restore toasts depends on it).
- **`insert(or: .replace)`** keyed on `post_id` primary key — saving twice for
  the same post keeps exactly one row; saving for two different posts keeps two.
- **`serverModified` preserved** exactly (it's the conflict-detection baseline).
- **Edge:** `savedAt` is set to "now" on each save — verify a later save has a
  newer timestamp.

### 3.3 `TaxonomyCache` (extend beyond categories)

- **Tags**: add `saveAndLoadTags`, `isTagStale`, fresh-within-TTL for tags
  (mirror the category tests — currently only categories are tested).
- **TTL boundary:** exactly 24h (the documented TTL) — test just under and just
  over. Current stale test uses 25h; add a 23h59m "fresh" and 24h01m "stale"
  pair to pin the boundary.
- **Replace semantics:** saving a new category set replaces the old (the
  composite PK is `(type, wp_id)`) — save `[1,2]`, then save `[2,3]`, assert what
  remains (does it merge or replace? document & test the actual behavior — this
  is a likely surprise).
- **Categories and tags don't collide:** a category with `wp_id == 1` and a tag
  with `wp_id == 1` coexist because the PK includes `type`.
- **Empty save** (`saveCategories([])`) → `loadCategories()` returns `[]`, and
  staleness still computed from `fetchedAt`.

### 3.4 `AppDatabase` migration

- **`inMemory()` and re-`migrate()`** is idempotent (`ifNotExists`) — constructing
  twice on the same path doesn't throw.
- **ALTER TABLE add `type`** is wrapped in `try?` — simulate an old DB (create
  `local_drafts` without `type`), open via `AppDatabase`, confirm the column is
  added and existing rows default to `"post"`.

### 3.5 `JSONFileStore<T>` & `AppSupportDirectory` (new — **untested, easy & high value**)

These now back **all** file persistence (credentials, AI settings). One generic
suite covers the security-critical write path that previously lived in each store.
**Set `AppSupportDirectory.override` to a unique temp dir in the suite `init` and
clean it up after** — this is the whole reason `.override` exists, and it makes
these tests hermetic.

`JSONFileStore` (parameterize over a simple `Codable` fixture type):
- **Round-trip:** `save(value)` then `load()` returns an equal value.
- **`load()` when file absent** → `nil` (not a throw) — the `fileExists` guard.
- **`delete()`** removes the file; **`delete()` when absent** → no throw.
- **Overwrite:** saving twice leaves one file with the latest value (atomic write).
- **chmod 600:** after `save`, the file's posix permissions are exactly `0o600`
  (owner read/write only). **This is the security regression guard.**
- **Atomic write:** `options: [.atomic]` — a corrupt/partial file is never left
  behind. (Hard to force a mid-write crash in a unit test; at minimum assert that
  overwriting a larger file with a smaller value yields valid JSON, no trailing
  garbage.)
- **Decode failure:** write malformed JSON to the path, then `load()` → throws
  (surfaces a decoding error rather than returning a half-object).
- **Distinct filenames don't collide:** two stores with different filenames are
  independent.

`AppSupportDirectory`:
- **`directory()` creates the dir** and returns it; calling twice is idempotent.
- **Directory permissions `0o700`** — assert posix perms on the created dir
  (closes the world-readable window the doc-comment describes).
- **Pre-existing loose dir is tightened** — pre-create the override dir with
  `0o755`, call `directory()`, assert it's re-set to `0o700` (the `setAttributes`
  fallback path). _Note: this tightening only runs on the real path, not the
  `override` branch — test the real branch carefully or document the gap._
- **`fileURL(name)`** joins correctly.
- **`override` isolation:** with `override` set, no file is ever created under the
  real `~/Library/Application Support/Quill`.

### 3.6 Thin store wrappers (`KeychainStore`, `AISettingsStore`)

Now that both are one-liners over `JSONFileStore`, a light smoke test each is
enough (the heavy lifting is §3.5):
- `KeychainStore.save/load/delete` round-trips a `Credentials` (existing tests —
  just add the `AppSupportDirectory.override` setup).
- `AISettingsStore.save/load` round-trips an `AISettings` including `apiKey`,
  `styleGuide`, `samplePostIDs`, and site URL; missing file → `nil`.

---

## 4. AI layer

### 4.1 `AIPromptBuilder` (pure functions — **untested, high value**)

`parseGenerateResponse` has subtle string-parsing logic that has already been
patched twice (web-search preamble, fences). Add `AIPromptBuilderTests`:

**`parseGenerateResponse`:**
- **Happy path:** `"TITLE: My Post\n\nCONTENT:\n<p>Hi</p>"` → `("My Post",
  "<p>Hi</p>")`.
- **Markdown fences stripped:** input wrapped in ` ```html … ``` ` → fences
  removed, title/content extracted.
- **Web-search preamble:** preamble text glued directly before `TITLE:` with no
  newline (`"I'll search for…TITLE: X\n\nCONTENT:\n<p>…</p>"`) → still parses
  because it searches for `TITLE:` anywhere (the documented gotcha).
- **Case-insensitive markers:** `title:` / `content:` lowercase → still parsed.
- **Missing `TITLE:`** → returns `nil`.
- **Missing `CONTENT:`** → returns `nil`.
- **`CONTENT:` appears before `TITLE:`** → the content search is scoped to
  *after* the title marker; a stray `CONTENT:` earlier shouldn't fool it. Test
  `"CONTENT: junk TITLE: Real\n\nCONTENT:\n<p>body</p>"`.
- **Empty title** (`"TITLE:\n\nCONTENT:\n<p>x</p>"`) → returns `nil` (guard).
- **Empty content** (`"TITLE: X\n\nCONTENT:\n"`) → returns `nil` (guard).
- **Title with leading/trailing whitespace** → trimmed.
- **Content with surrounding blank lines** → trimmed via
  `whitespacesAndNewlines`.
- **`TITLE:` with no following newline** (title runs to EOF, no CONTENT) →
  returns `nil` (no content marker).
- **Multiple ` ``` ` occurrences** → all stripped.

**`systemPrompt(styleGuide:)`:**
- `nil` guide → base prompt only, no "Write in this author's style" block.
- **Empty-string guide** → treated same as nil (the `!guide.isEmpty` check).
- Non-empty guide → appended with the style-guide header.

**`generatePostPrompt`** / **`operationPrompt`** / **`styleGuideGenerationPrompt`:**
- Assert the prompt **names the HTML elements** (`<h2>`, `<h3>`, `<p>`,
  `<ul>`/`<li>`) — the documented gotcha that vague prompts cause Claude to omit
  headings. A test asserting `prompt.contains("<h2>")` guards that.
- `operationPrompt` includes the correct instruction per `AIWritingOperation`
  case and embeds the selected HTML after `"Content to transform:"`.
- `styleGuideGenerationPrompt` numbers samples `--- Sample 1 ---`, `--- Sample 2
  ---` and joins them; test with 0, 1, and N samples.

### 4.2 `AnthropicClient` (mock-backed)

`AnthropicClient.session` is **still** a `private static let` (confirmed this
revision) — to unit test it, refactor to allow injecting a `URLSession` (mirror
`WordPressClient`'s init, which already does this). With that:

- **Request shape:** `x-api-key`, `anthropic-version: 2023-06-01`,
  `content-type: application/json` headers set.
- **Beta header without web search:** `anthropic-beta:
  prompt-caching-2024-07-31` only.
- **Beta header with web search:** includes `web-search-2025-03-05` and the
  request body's `tools` array contains the `web_search_20250305` tool.
- **No web search** → `tools` is omitted/nil in body.
- **`cache_control: ephemeral`** present on the system block (caching gotcha).
- **Response joining (the documented multi-block gotcha):** a response with
  several `type: "text"` blocks plus `server_tool_use` and
  `web_search_tool_result` blocks → only the text blocks are joined, in order,
  into the full string. **Assert non-text blocks are excluded and order is
  preserved** (don't use first/last).
- **Empty text** (all blocks non-text, or empty) → throws
  `AnthropicError.noTextContent`.
- **Non-200** → throws `AnthropicError.httpError(code, body)` with body
  preserved.
- **Non-HTTP response** → `AnthropicError.invalidResponse`.
- **Malformed JSON** → decoding throws (verify it surfaces, not silently empty).

### 4.3 `AISettings` / `AISettingsStore`

- Persistence round-trip and **chmod 600** are now covered generically in §3.5
  (`AISettingsStore` is a thin `JSONFileStore<AISettings>` wrapper) — see §3.6 for
  the smoke test. Don't re-test the file mechanics here.
- `aiEnabled` logic (on `AppState`): nil settings → false; empty apiKey → false;
  non-empty → true. (Unit-testable on `AppState` directly.)
- **Style-guide regeneration rules** (documented in gotchas) — these live in
  `PreferencesView.saveAll()`; if extractable into a testable helper, test:
  (a) sample IDs changed → regenerate; (b) no guide yet → regenerate; (c) IDs
  unchanged + guide exists → reuse, no Claude call; (d) **site URL changed →
  clear `samplePostIDs` and set guide to nil**. If not extractable, cover under
  manual §7.

---

## 5. `AppState` & view-model logic (pure unit tests)

`AppState` has pure computed properties worth pinning:

- **`filteredItems`** for each section: `.posts` → maps `posts`; `.pages` →
  `pages`; `.localDrafts` → `localDrafts`; `.media` → `[]`.
- **Search filter:** case-insensitive `contains` on title; empty search returns
  all; no-match returns `[]`; partial match works; **whitespace-only search**
  (document whether it filters or not).
- **`PostItem.id`** uniqueness: a remote post id `5` → `"remote-5"`; a local
  draft id `5` → `"local-5"` — they must not collide (the sidebar selection
  depends on this).
- **`PostItem.title`** empty → `"Untitled"` for both remote and local.
- **`PostItem.statusBadge`**: remote → status string; local → `"local-{type}"`.
- **`SidebarSection.icon` / `.shortTitle`** mapping (cheap, guards typos).

---

## 6. JavaScript editor layer (`Resources/editor.html`)

This is the **least-covered, highest-complexity** area. The `toWordPressHTML`
transform and the `parseHTML` rules are the contract with WordPress; a
regression here corrupts every saved post. Two complementary approaches:

### 6.1 Headless JS unit tests (recommended — add a JS test harness)

`toWordPressHTML`, `extractAlignment`, and the parse rules are pure DOM
functions. Extract them (or the bundle) so they can run under **Node with
jsdom** or a headless browser, and add a `Scripts/test-editor.mjs` (or a small
`vitest`/`node:test` suite). Test cases for `toWordPressHTML`:

- **Headings** `<h1>`–`<h6>` → gain `class="wp-block-heading"`; existing classes
  preserved (idempotent — running twice doesn't double-add).
- **Lists:** `<ul>` (non-task) and `<ol>` → `wp-block-list`; **task lists
  (`ul[data-type="taskList"]`) are excluded** — assert no class added.
- **List-item `<p>` unwrap:** `<li><p>text</p></li>` → `<li>text</li>`; but
  **multi-paragraph `<li>`** (`<li><p>a</p><p>b</p></li>`) is left untouched
  (the "exactly one child" guard).
- **Task item div unwrap:** `<li data-type="taskItem"><div><p>x</p></div></li>`
  → inner `<p>` stripped to `<div>x</div>`.
- **Blockquote** → `wp-block-quote`; **code `<pre>`** → `wp-block-code`.
- **Blockquote `<cite>` (new feature):**
  - **Empty cite stripped:** `<blockquote><p>quote</p><cite></cite></blockquote>`
    and a whitespace-only cite (`<cite>   </cite>`) → the `<cite>` is **removed**
    from saved HTML (the `!el.textContent.trim()` rule). This is the regression
    guard for the auto-inserted empty cite on every new blockquote.
  - **Non-empty cite preserved:** `<cite>— Author</cite>` survives and stays the
    last child of the blockquote.
  - **Cite only stripped inside blockquote** — the selector is `blockquote cite`;
    a stray `<cite>` elsewhere (if it can occur) is out of scope. Confirm scope.
  - **Round-trip:** load `<blockquote class="wp-block-quote"><p>q</p><cite>A</cite>
    </blockquote>` → parses to a blockquote node with a trailing `cite` child →
    serializes back to the same structure (parse rule is `{ tag: 'cite' }`,
    schema `block+ cite?`).
- **Aligned images:** `<img class="alignleft">` → wrapped in
  `<figure class="wp-block-image alignleft">`, and the align class **removed
  from the img**. Test all three: left/right/center.
- **`data-media-id` → `wp-image-{id}` class** re-emitted on the img.
- **Image with both alignment and media-id** → figure wrapper + `wp-image-{id}`.
- **Image with no alignment, no media-id** → untouched (bare `<img>`).
- **Tables — header promotion:** a `<tbody>` whose first row is all `<th>` →
  that row moves into a new `<thead>`. **Edge:** first row mixed `<th>`/`<td>` →
  **not** promoted. **Edge:** table already has `<thead>` → skipped.
- **Tables — figure wrap:** `<table>` → wrapped in `<figure
  class="wp-block-table">`; a table **already** inside `wp-block-table` is not
  double-wrapped (idempotency guard).
- **Idempotency overall:** `toWordPressHTML(toWordPressHTML(x))` ==
  `toWordPressHTML(x)` for representative inputs — critical because it runs on
  every keystroke-debounce.
- **Empty document** (`<p></p>`) → stable output, no crash.
- **Unicode / curly quotes / emoji** in text nodes → preserved.

For `extractAlignment` / `parseHTML`:
- **`figure.wp-block-image alignleft`** on load → parsed back to an image node
  with `alignment: left` (the round-trip with the serializer above).
- A `figure.wp-block-image` with **no** alignment class → no alignment.
- An `<img>` with `class="wp-image-42"` → `mediaId: 42` extracted.
- An `<img>` with `width`/`height` attributes → parsed onto the node.

**Round-trip property test:** For each Gutenberg block type, assert
`parse(serialize(node)) == node` and `serialize(parse(html))` ==
canonical-`html`. This is the single most valuable JS test — it proves load →
edit → save doesn't drift.

### 6.2 In-app integration (WKWebView) — covered under manual §7.4

The Swift↔JS bridge (`beginAIOperation`, `showAIResult`, `setMediaSizes`,
`getContent`, message handlers) is hard to unit test without driving a live
WKWebView. Cover via the manual editor checklist, or — if automation is worth
it — an XCUITest target that loads `editor.html` and calls
`evaluateJavaScript`.

---

## 7. Functional / manual test checklists

These cover SwiftUI/AppKit behavior, WKWebView interaction, and end-to-end flows
that aren't economically unit-testable. Run against a **real WordPress test
site** (or a local `wp-env`/Docker WordPress) using an Application Password.
Build with `./build.sh` and `open Quill.app` before each pass.

> Recommendation: keep a disposable WordPress instance so destructive tests
> (delete, trash, publish) don't pollute a real site.

### 7.1 Authentication & onboarding

- [ ] First launch with no credentials → preferences/login prompt shown.
- [ ] Valid site URL + username + app password → connects, lists load.
- [ ] **Edge:** site URL without scheme (`example.com`) — does it normalize or
      fail clearly?
- [ ] **Edge:** site URL with trailing slash, with subdirectory install
      (`example.com/blog`), with non-standard port.
- [ ] **Edge:** wrong password → `401` surfaced as a readable error, not a
      silent failure.
- [ ] **Edge:** site that isn't WordPress / REST API disabled → clear error.
- [ ] App password with spaces pasted verbatim → auth succeeds (ties to §1.5).
- [ ] No keychain prompt appears during normal network use (ephemeral-session
      gotcha).
- [ ] Credentials persist across relaunch; changing the site URL updates the
      lists and (per gotcha) clears AI sample post IDs.

### 7.2 Sidebar, lists, navigation

- [ ] Posts / Pages / Local Drafts / Media sections each load and render.
- [ ] Selection highlight uses the custom (non-blue) style — confirms the
      `ScrollView+LazyVStack` (not `List`) gotcha holds.
- [ ] Search filters the current section case-insensitively; clearing restores.
- [ ] **Empty states:** empty Posts, empty Pages, empty Drafts, empty Media each
      show the right placeholder; editor empty state says "post"/"page"/"draft"
      per active section (TODO item).
- [ ] Switching to Media hides the post list/search/toolbar and shows the
      thumbnail grid (the `else` branch gotcha).
- [ ] Pagination in Posts and Media loads more on scroll; `hasMore` stops at the
      end.
- [ ] No `NavigationSplitView`/`HSplitView` chrome (no drag cursor on the
      divider) — visual confirm of the layout gotcha.

### 7.3 Editor — content & Gutenberg round-trip

- [ ] Load an existing remote post → content renders identically to WordPress.
- [ ] Type formatting: bold, italic, strike, inline code, links, headings (h1–
      h6), bullet/ordered/task lists, blockquote, code block, table.
- [ ] Save → fetch `content.raw` via REST (`?context=edit`) → matches the
      Gutenberg expected output table in `CLAUDE.md` (heading classes, list
      classes, figure-wrapped tables/images, thead promotion).
- [ ] **Round-trip stability:** load → save without editing → diff is empty (no
      drift). Then load again → still identical.
- [ ] Multi-paragraph list items survive the save unchanged (don't get
      collapsed).
- [ ] Task list checkboxes round-trip.
- [ ] **Blockquote attribution (`<cite>`):**
  - [ ] Toggling blockquote **on** auto-appends an empty cite line (subdued,
        right-aligned).
  - [ ] Typing in the cite line then saving → `<cite>` persists inside the
        blockquote and renders as a `<cite>` on WordPress.
  - [ ] Leaving the cite **blank** → the empty `<cite>` is **not** saved (no empty
        cite litters the published HTML).
  - [ ] **Enter** inside the cite exits the blockquote into a new paragraph after
        it (doesn't add a newline inside the cite).
  - [ ] **Backspace** in an empty cite deletes the cite node (doesn't delete the
        whole quote).
  - [ ] Toggling blockquote **off** removes the quote and its cite cleanly.
- [ ] Curly quotes / emoji / non-Latin scripts survive save→reload byte-exact.
- [ ] Very long post (10k+ words) — editor stays responsive; save succeeds.
- [ ] Paste from Word/Google Docs/Safari → reasonable HTML, no script injection.

### 7.4 Editor — images

- [ ] Insert image via media picker at caret → appears at correct position.
- [ ] **Hit-testing:** clicking a thumbnail in the picker grid selects the
      intended item (regression on the recent thumbnail-grid offset fix).
- [ ] Drag image file from Finder onto editor → uploads, inserts, toast shown.
- [ ] **Edge:** drag a non-image file → ignored (the `isFileURL`/mime guard).
- [ ] **Edge:** drag multiple images at once → all upload and insert.
- [ ] **Edge:** upload failure (offline) → error surfaced, editor not corrupted.
- [ ] Resize handles appear on select; drag resizes; aspect ratio respected.
- [ ] Named WordPress sizes (thumbnail/medium/large/full) offered when the image
      has a `mediaId` and the media item is loaded; hidden otherwise
      (`setMediaSizes(id, null)` path).
- [ ] Image alignment left/center/right → wraps text correctly and saves as
      `figure.wp-block-image alignXXX`.
- [ ] Image toolbar repositions on scroll and hides on deselect (the
      `_scrollHandler` cleanup + 80ms deselect delay gotchas).
- [ ] Clicking a toolbar input doesn't dismiss the toolbar (80ms delay).
- [ ] Mime detection: insert `.jpg/.png/.gif/.webp/.heic/.tiff` → correct
      content type sent.

### 7.5 Editor — links

- [ ] Link button opens the popover anchored to the **selection rect** (not the
      toolbar button) when text is selected; anchored to the button when nothing
      selected.
- [ ] Typing a query searches posts/pages/categories/tags/media; results render
      (the `ObservableObject` re-render gotcha).
- [ ] Popover **grows** as results appear without clipping (the
      `.preferredContentSize` sizing gotcha).
- [ ] Selecting a result inserts the link; manual URL entry works.
- [ ] **Edge:** no results → empty state, no crash.
- [ ] **Edge:** search while offline → handled gracefully.

### 7.6 Save / publish / draft / schedule

- [ ] **Local draft, Save Draft** → persists locally only, **no** network call
      (verify via proxy/network log); toast "Saved locally".
- [ ] **Local draft, Publish** → creates remote post, **local copy disappears
      immediately** from the Drafts list (TODO item), selection moves to the new
      remote item, section switches to Posts/Pages.
- [ ] Page draft publishes to `/pages`, post draft to `/posts`.
- [ ] **Remote post, ⌘S** → updates WordPress (status `draft` stays draft).
- [ ] **Remote post, ⌘⇧P / Publish** → publishes; button label reflects state
      (`Publish` / `Update` / `Publish Draft` / `Schedule`).
- [ ] **Scheduling:** set a future date → status `future`, post scheduled;
      verify on the server the scheduled time matches (UTC `date_gmt`, **not**
      site-local `date` — the scheduling gotcha). Test a timezone-offset site.
- [ ] Reopening a scheduled post shows the correct future date in the panel
      (the `parseWPDate` round-trip, incl. the no-timezone-suffix fallback).
- [ ] Inline new category/tag names → created on save, IDs attached, appear in
      `appState.categories/tags` and the panel (the deferred-creation gotcha).
- [ ] **Edge:** taxonomy creation fails → save aborts with an error, content not
      lost.
- [ ] Slug: blank slug on a new item stays blank (doesn't inherit previous
      item's slug — TODO item); editing slug then save sends it; blank slug on
      update **omits** `slug` so the server value is preserved.
- [ ] Featured image set/clear; `featured_media: 0` clears it.
- [ ] Comment status open/closed round-trips.
- [ ] Page parent picker excludes the page itself; saving sets `parent`.

### 7.7 Conflict detection

- [ ] Open a remote post in Quill. Edit it on the server (or via another client)
      so `modified` changes. Save in Quill → **Conflict Detected** alert.
  - [ ] "Keep Local" → force-saves, overwrites server.
  - [ ] "Use Server" → reloads server content, discards local edits.
  - [ ] "Cancel" → keeps editing, no data lost.
- [ ] **False-conflict guard:** open a post, immediately save without server
      changes → **no** conflict alert (the `loadItem` baseline-refresh from the
      live server value).
- [ ] **Preview-induced baseline refresh:** preview a *draft* post (which can
      bump `modified` via autosave), then save → **no** spurious conflict (the
      `openPreview` draft/pending refresh).

### 7.8 Autosave / unsaved-changes / navigation

- [ ] Edit a remote post, wait 30s → autosave stash written; navigate away and
      back → "Unsaved changes restored" toast and stashed content shown.
- [ ] **No spurious restore toast** when opening a server post that has no real
      local divergence (the recent autosave-restore-toast fix).
- [ ] Navigate away from a dirty local draft → flushed to SQLite; reopening shows
      the latest content.
- [ ] Navigate away from a dirty remote post → stashed; not pushed to WordPress.
- [ ] After a successful publish/update, the autosave stash for that post is
      **deleted** (so the next open doesn't falsely restore).
- [ ] Dirty indicator (amber dot) shows for local drafts when `isDirty`, hidden
      for remote.
- [ ] Rapid navigation between items → no autosave from item A lands on item B
      (the `expectedItemID` guard); no crash; cancelled load tasks don't throw.
- [ ] Quitting the app with unsaved local-draft edits → recovered on next launch.

### 7.9 Delete / trash

- [ ] Trash a remote post → confirmation alert, then `force=false` (recoverable
      — appears in WordPress Trash, not gone).
- [ ] Trash a page → `/pages/{id}` trashed.
- [ ] Delete a local draft → removed from list and SQLite.
- [ ] Delete media → confirmation alert (permanent, `force=true`); after confirm
      it's gone from the grid and server.
- [ ] **Edge:** delete failure (permissions/offline) → `deleteError` alert; item
      stays.
- [ ] Cancel on any delete confirmation → nothing happens.

### 7.10 AI features (require an Anthropic API key configured)

- [ ] With no API key: ✦ toolbar button is **hidden** and the AI items are
      **absent** from the editor right-click menu (`aiEnabled == false`).
- [ ] Add a key in Settings → feature enables **without relaunch**.
- [ ] **Generate post:** ✦ on an empty editor opens the sheet directly; on a
      non-empty editor shows the "Replace Content?" alert first.
- [ ] Generate produces a title + structured HTML **with headings** (not just
      `<p>` — the prompt-structure gotcha).
- [ ] Generate with web search on → response reassembled correctly across
      fragmented blocks (the joining gotcha); citations don't break the
      TITLE/CONTENT parse.
- [ ] **Selection ops (now right-click menu, not a pill):** select text →
      right-click → Make Longer / Make Shorter / To Table / To List each appear
      (only when `aiEnabled && hasTextSelection`) and each works.
  - [ ] `hasTextSelection` updates correctly: the AI items appear only when there
        is a non-empty selection; collapse the selection → items gone on next
        right-click.
  - [ ] The AI menu items survive the AutoFill/Services re-filter (their selector
        strings are in `WebViewMenuFilter.allowed`) — see §7.13.
- [ ] AI result inserts at **block boundaries** — no empty `<p>` fragments
      before/after, no blank paragraphs from inter-block whitespace (the two
      insertion gotchas). Verify the saved HTML has no stray empty paragraphs.
- [ ] Accept → content committed and `contentChanged` fires (Swift gets the
      HTML); Discard → original restored.
- [ ] **Accepted AI result is Gutenberg-transformed** (commit
      "apply Gutenberg HTML transformation when accepting AI result") — if the AI
      returns a table/list/heading, the **saved** HTML has `wp-block-*` classes
      and figure wrappers, not raw Tiptap output. Verify via `content.raw`.
- [ ] **Edge:** Claude error/timeout → original text restored, "couldn't
      complete" toast, editor not corrupted.
- [ ] **Edge:** empty selection → no-op (`beginAIOperation` returns empty).
- [ ] The AI result bar (`AIResultPanel`) stays above Quill but **not** above
      other apps when you switch away (the child-window gotcha); no rectangular
      shadow artifact (the `hasShadow=false` gotcha); buttons are visible in light
      mode (the `.plain` style gotcha). _(The old selection pill panel is gone — no
      pill to test.)_
- [ ] Style guide: select sample posts in Settings → guide generated once;
      re-saving with unchanged samples makes **no** Claude call; changing the
      site URL clears samples and guide.

### 7.11 Settings panel & preferences

- [ ] Post settings panel for **posts** shows categories, tags, slug, excerpt,
      discussion; for **pages** shows parent + slug + discussion only (no
      categories/tags/excerpt) — the `isPage` gotcha.
- [ ] Amber accent applied throughout settings (recent commit).
- [ ] Preferences opens from both the menu and (if present) the in-app sheet;
      `PreferencesView` works in the separate `Settings` scene **without
      EnvironmentObject** (the gotcha) — i.e. sample post picker is populated.

### 7.12 Window / appearance / chrome

- [ ] Light and dark mode: sidebar (`wpSidebarBg`), panels (`wpPanelBg`),
      title/breadcrumb bars render with correct tokens; **title/breadcrumb bars
      white in dark mode** (open TODO — verify current state).
- [ ] Enter/exit full screen → title bar color stable (TODO fixed — confirm).
- [ ] Title field + top border spacing correct (TODO fixed — confirm).
- [ ] App icon/logo present in dock and about.
- [ ] Editor "Loading editor…" overlay shows then fades on `editorReady`; never
      sticks if the bundle loads.

### 7.13 Context menus (AppKit specifics)

- [ ] Right-click in the **editor (WKWebView)** → Cut/Copy/Paste present and
      correctly enabled/disabled; **no AutoFill/Services leakage** (the
      `willOpenMenu` + `NSMenuDelegate` re-filter gotcha).
- [ ] Right-click in the **title field** → only Cut/Copy/Paste; no AutoFill (the
      `RestrictedTextView` gotcha).
- [ ] Right-click a misspelled word → spelling suggestions appear.

### 7.14 Spell check

- [ ] "ABC" toolbar button highlights misspellings via decorations; highlights
      clear on first edit.
- [ ] No `NSUndefinedKeyException` crash on macOS 26 (the
      `continuousSpellCheckingEnabled` KVC gotcha) — launch and run spell check
      on the current OS.

---

## 8. Non-functional & resilience

- **Offline / flaky network:** every network action (list load, save, publish,
  upload, search, AI) degrades gracefully with a user-visible error, never a
  hang or crash. Test by toggling network mid-operation.
- **Slow network:** saves show the saving state and disable buttons
  (`isSaving`); no double-submit on rapid clicks.
- **Large media library:** Media grid with 500+ items — scrolling stays smooth,
  pagination works, memory bounded (the `Color.clear` overlay layout gotcha
  keeps columns aligned).
- **Concurrency / cancellation:** rapidly switching items cancels in-flight
  load/autosave tasks without throwing or cross-contaminating state.
- **File permissions:** `credentials.json` and `ai_settings.json` are chmod 600.
- **Crash recovery:** force-quit mid-edit → local draft / autosave stash
  recovered on relaunch.
- **Performance:** `toWordPressHTML` runs on a 500ms debounce on every edit — on
  a large document it should not block typing (profile if sluggish).
- **Security:** pasted/loaded HTML with `<script>` or `onerror=` attributes is
  not executed in the WKWebView; AI-returned HTML is inserted as content, not
  evaluated.

---

## 9. Regression matrix — "known gotchas" guards

Each documented gotcha in `CLAUDE.md` is a bug that already happened. Pin the
ones that are automatable; manually verify the rest. (✅ = add automated test,
👁 = manual verify.)

| # | Gotcha | Guard |
|---|---|---|
| 1 | Pages omit `categories`/`tags` | ✅ §1.1 |
| 2 | `WPPost.type` routing posts vs pages | ✅ §2.1 / 👁 §7.6 |
| 3 | Scheduling uses `date_gmt` not `date` | ✅ §1.3 + 👁 §7.6 |
| 4 | Media dimensions as floats | ✅ §1.2 |
| 5 | `slug` omitted when empty | ✅ §1.3 + 👁 §7.6 |
| 6 | Trash `force=false` vs media `force=true` | ✅ §2.1 + 👁 §7.9 |
| 7 | Cancellation re-thrown, not wrapped | ✅ §2.2 |
| 8 | `searchLinks` ignores sub-failures | ✅ §2.3 |
| 9 | Web-search response joined across blocks | ✅ §4.2 |
| 10 | Web-search preamble before `TITLE:` | ✅ §4.1 |
| 11 | AI prompt must name HTML elements | ✅ §4.1 |
| 12 | `toWordPressHTML` transforms (all rows) | ✅ §6.1 + 👁 §7.3 |
| 12a | Empty blockquote `<cite>` stripped on save (new) | ✅ §6.1 + 👁 §7.3 |
| 13 | List `<p>` unwrap only single-child | ✅ §6.1 |
| 14 | Table thead promotion / figure wrap | ✅ §6.1 |
| 15 | Style-guide regeneration rules | ✅/👁 §4.3 |
| 16 | Curly quotes in Swift strings | ✅ §3.1 (round-trip) |
| 17 | Autosave restore toast not spurious | 👁 §7.8 |
| 18 | Conflict baseline refresh (no false positive) | 👁 §7.7 |
| 19 | Selection-anchored link popover + sizing | 👁 §7.5 |
| 20 | `AIResultPanel` child-window / shadow / button style (pill removed) | 👁 §7.10 |
| 21 | AI insert at block boundaries (no empty `<p>`) | 👁 §7.10 + ✅ §6.1 |
| 22 | Media grid `Color.clear` layout | 👁 §7.2 |
| 23 | Context-menu AutoFill leakage | 👁 §7.13 |
| 24 | macOS 26 spell-check KVC crash | 👁 §7.14 |
| 25 | Ephemeral session (no keychain prompts) | 👁 §7.1 |
| 26 | Sidebar not `List`; layout not `NavigationSplitView` | 👁 §7.2 |
| 27 | `JSONFileStore` writes chmod 600 + atomic (new) | ✅ §3.5 |
| 28 | `AppSupportDirectory` dir is 0o700 + `.override` isolation (new) | ✅ §3.5 |
| 29 | AI selection ops via right-click menu, gated on `hasTextSelection` (new) | 👁 §7.10/§7.13 |
| 30 | Accepted AI result is Gutenberg-transformed (new) | 👁 §7.10 |

---

## 10. Suggested implementation order

1. ~~**Model tests** (§1) — fastest, highest regression value, zero new infra.~~ ✅ **Done** — `WPPostDecodingTests` (9), `WPMediaDecodingTests` (7), `PostPayloadTests` (11), `CredentialsTests` (4). 80 tests total passing.
2. ~~**`AIPromptBuilder` tests** (§4.1) — pure, already-patched-twice logic.~~ ✅ **Done** — `AIPromptBuilderTests` (21). Covers all `parseGenerateResponse` edge cases, system prompt, generate/operation/style-guide prompts.
3. **`WordPressClient` gap-fill** (§2) — extract shared `MockURLProtocol` first.
4. **Storage gap-fill** (§3) — tags, autosave delete, migration, **and the new
   `JSONFileStore`/`AppSupportDirectory` suite (§3.5)**. The latter is now a quick
   win: `AppSupportDirectory.override` makes file-store tests hermetic with no
   mocking, and it guards the chmod-600/atomic-write security path that backs
   credentials and AI settings.
5. **`AnthropicClient` injectable session + tests** (§4.2) — small refactor
   (still needed — session is still `static`).
6. **JS editor harness** (§6.1) — biggest infra lift, biggest correctness payoff.
7. **Manual checklists** (§7) — run a full pass before each release; spot-check
   the regression matrix (§9) after any editor or save-path change.

### Concrete refactors that unlock testing
- Extract `MockURLProtocol` to a shared support file.
- Add an injectable `URLSession` to `AnthropicClient` (mirror `WordPressClient`).
- _Already in place:_ `AppSupportDirectory.override` is the test seam for all file
  stores — use it in `init`, no refactor needed. The `Cite` node and empty-cite
  stripping should be included in whatever module exposes `toWordPressHTML` to the
  JS harness (§6.1).
- Extract `toWordPressHTML`, `extractAlignment`, and the parse helpers into a
  module the bundle imports **and** a Node test can import (or test against the
  built `tiptap-bundle.js` via jsdom).
- If feasible, lift the style-guide regeneration decision out of
  `PreferencesView.saveAll()` into a pure function for §4.3.
