# Quill Code Review — 2026-06-10

Full-codebase review covering security, memory, performance, correctness, and architecture.
Scope: all Swift sources, `editor.html`, `editor-transforms.js`, build script, and packaging.

**Overall verdict:** well-built app. Security fundamentals are mostly right — HTTPS enforced
with a localhost-only exception matching the ATS config, 0600/0700 file permissions, ephemeral
URLSessions, JSON-encoding for every Swift→JS injection, a locked-down navigation policy, and
careful context-menu hygiene. Nothing below is an emergency; the top three or four are worth
fixing soon.

---

## Status

| # | Finding | Severity | Effort | Status |
|---|---------|----------|--------|--------|
| 1 | [H1](#h1-new-nspanel-created-on-every-swiftui-render) — NSPanel created on every render | High | Small | ✅ Fixed |
| 2 | [S1](#s1-nsspellchecker-used-off-the-main-thread) — NSSpellChecker off main thread | High (crash-class) | Small | ✅ Fixed |
| 3 | [H2](#h2-media-grids-download-full-resolution-images-for-thumbnails) — Full-res thumbnails | High | Small | ✅ Fixed |
| 4 | [H3](#h3-startup-fetches-full-raw-html-of-every-post-and-page) — Full content fetched at launch | High | Medium | ✅ Fixed |
| 5 | [C1](#c1-code-view-corrupts-text-containing---or-quoted-attributes) — Code view entity corruption | Medium (data corruption) | Small | ✅ Fixed |
| 6 | [C2](#c2-taxonomy-cache-cleared-on-every-launch) — Taxonomy cache TTL defeated | Medium | Small | ✅ Fixed |
| 7 | [H4](#h4-whole-file-buffering-for-media-uploads-main-thread-reads-for-drops) — Upload buffering / main-thread reads | Medium | Medium | ⬜ Todo |
| 8 | [S2](#s2-clicked-links-open-via-nsworkspace-with-any-scheme) — Unrestricted link schemes | Low–Medium | Small | ⬜ Todo |
| 9 | [C3](#c3-prosemirror-positions-vs-utf-16-lengths-in-spell-context) — Spell-fix range mismatch | Low (silent corruption) | Small | ⬜ Todo |
| 10 | [Smaller items](#smaller-optimizations-and-cleanups) — opportunistically | Low | Small each | ✅ Fixed |
| 11 | [Architecture](#architecture-observations) — when next touching those files | — | Larger | ⬜ Todo |

---

## High impact

### H1. New `NSPanel` created on every SwiftUI render

**File:** `Sources/QuillKit/Views/Editor/PostEditorView.swift:34`

✅ **Fixed 2026-06-10** — Changed `private var resultPanel` to `@State private var resultPanel`.
`@State` ensures SwiftUI creates the panel once per view identity and reuses it across re-renders.

`private var resultPanel: AIResultPanel = AIResultPanel()` is a plain stored property on a view
*struct*. SwiftUI recreates `PostEditorView` every time `ContentView`'s body re-evaluates —
which happens on every `@Published` change in `AppState`, including each keystroke in the
sidebar search field. Each recreation constructs a real window-server-backed `NSPanel`.

Besides the churn, if the panel is showing when the struct is recreated, the visible panel is
orphaned — the new struct's `resultPanel` is a different instance, so nothing in Swift can
dismiss the one on screen (only its own buttons/Escape can).

### H2. Media grids download full-resolution images for thumbnails

**Files:** `Sources/QuillKit/Views/Media/MediaSidebarSection.swift`,
`Sources/QuillKit/Views/Media/MediaPickerView.swift`

✅ **Fixed 2026-06-10** — Added `thumbnailURL` computed property to `WPMedia` that prefers
`media_details.sizes["thumbnail"].source_url`, falling back to `sourceURL` when absent or empty.
Both grid cells updated to use `media.thumbnailURL`.

Both grids were using `AsyncImage(url: URL(string: media.sourceURL))` — the original upload, often
2–8 MB each, rendered at 80–90 pt. A 30-item page can pull 100+ MB over the network and decode
it all into memory.

### H3. Startup fetches full raw HTML of every post and page

**File:** `Sources/QuillKit/API/WordPressClient.swift` (`fetchAllPaginated`)

✅ **Fixed 2026-06-10** — Four coordinated changes:
1. `fetchAllPaginated` now sends `_fields=id,type,title,status,date,date_gmt,modified,slug,link,featured_media,categories,tags,parent,comment_status`
2. `WPPost.content`/`excerpt` changed to `decodeIfPresent` (empty default when absent from filtered response)
3. `PostEditorView.loadItem()` now calls `applyRemotePost(loadedPost)` after the individual fetch so the full content is applied to the editor
4. `PreferencesView` now fetches sample post content on-demand for style guide generation rather than reading from the list cache; takes `credentials: Credentials?` parameter
5. Three new tests added: `missingContentAndExcerptDefaultToEmpty` (WPPostDecodingTests), `fetchAllPostsRequestIncludesFieldsFilter` and `fetchPostRequestOmitsFieldsFilter` (WordPressClientTests)

**Note:** The fix revealed that `loadedPost` content was previously always discarded — the editor
was reading from the list cache, not the freshly fetched post. The fix also corrects this:
the editor now always shows the freshly fetched server content when a post is opened.

**Tradeoff:** There is now a brief "Start writing..." flash when clicking a post while the
individual fetch completes. Previously content appeared instantly from the full list cache.

`fetchAllPosts`/`fetchAllPages` were using `context=edit` with no `_fields` filter, so every post's
complete raw+rendered content (and excerpt, twice) came down at launch and lived forever in
`appState.posts`. The editor *re-fetches the full post anyway* when one is opened, so the list
payload was ~95% dead weight.

### H4. Whole-file buffering for media uploads; main-thread reads for drops

**Files:** `Sources/QuillKit/Views/Editor/PostEditorView.swift:649`,
`Sources/QuillKit/API/WordPressClient.swift:144`,
`Sources/QuillKit/Views/Media/MediaSidebarSection.swift:291`

- `handleDroppedImages` calls `Data(contentsOf:)` inside a main-actor task — a large drop
  freezes the UI. (The sidebar upload path got this right with `Task.detached`.)
- `uploadMedia` sets `request.httpBody = data`, so the entire file sits in memory. The open
  panel allows `UTType.movie`, meaning a multi-GB screen recording is fully buffered.
- Related bug: `mimeType(for:)` in `MediaSidebarSection.swift:291` has no movie mappings, so
  the movies the panel permits upload as `application/octet-stream`.

**Fix:** use `URLSession.upload(for:fromFile:)` for uploads; move drop-path file reads off the
main actor; add `mov`/`mp4`/`m4v` MIME mappings (or stop allowing movies in the panel).

---

## Security

Posture is good; these are hardening items, not holes.

### S1. `NSSpellChecker` used off the main thread

**File:** `Sources/QuillKit/Views/Editor/EditorCoordinator.swift`

✅ **Fixed 2026-06-10** — Replaced the `DispatchQueue.global` + iterative `checkSpelling` loop
with `NSSpellChecker.requestChecking(of:...)`. The async API handles threading internally and
delivers results on the main thread, eliminating both dispatch queue hops. The rewrite is also
simpler — `requestChecking` finds all misspellings in one shot, removing the manual `while` loop
and offset tracking.

### S2. Clicked links open via `NSWorkspace` with any scheme

**File:** `Sources/QuillKit/Views/Editor/EditorCoordinator.swift:230`

Pasted or server-loaded content can contain links with arbitrary schemes; a user click hands
them straight to `NSWorkspace.shared.open`.

**Fix:** restrict to `http`/`https`/`mailto`. Also: the policy allows *all* `file://`
navigations — a link-activated `file://` URL navigates the webview away from the editor (it
breaks rather than leaks, but cancelling anything that isn't the bundled `editor.html` is
cleaner).

### S3. Credentials/API key on disk in plain JSON — accepted risk, one note

The chmod-600 JSON store is a documented deliberate decision and is reasonable for a
non-sandboxed personal app. Residual risk worth a line in the docs: both secrets are readable
by *any process running as the user* (unlike keychain ACLs), and they transit Time
Machine/cloud backups in plaintext.

### S4. Raw API error bodies surface to users and stderr

**Files:** `Sources/QuillKit/API/APIError.swift:24`,
`Sources/QuillKit/AI/AnthropicClient.swift:69`

`AnthropicError.httpError` puts the full response body into the alert text — server bodies can
be huge/HTML. `friendlyHTTPMessage` logs to stderr from inside `errorDescription`, a side
effect in a computed property that fires every time the message is rendered.

---

## Correctness bugs

### C1. Code view corrupts text containing `<`, `&`, or quoted attributes

**File:** `Sources/QuillKit/Resources/editor-transforms.js` (`formatHTML.serialize`)

✅ **Fixed 2026-06-10** — Added `escapeText` and `escapeAttr` helpers. Text nodes now escape
`&→&amp;`, `<→&lt;`, `>→&gt;`; attribute values escape `&→&amp;` and `"→&quot;`. Five new
JS tests added in `formatHTML — entity escaping` suite (57 JS tests total).

`formatHTML` was serializing text nodes via raw `node.textContent` (entities decoded, never
re-escaped) and attributes via `a.value` without escaping `"`. A paragraph containing `5 < 10`
round-tripped through code view as a malformed tag and swallowed following content.

### C2. Taxonomy cache cleared on every launch

**File:** `Sources/QuillKit/Views/Sidebar/SidebarView.swift`

✅ **Fixed 2026-06-10** — `clearAll()` is now gated on a `UserDefaults` site-URL comparison.
The cache is only cleared when the WordPress site URL changes; normal launches serve from the
24-hour SQLite cache. Site switches still get a fresh fetch and update the stored URL.

`loadAllSections` (triggered by `.task(id: credentials)`) was calling `taxonomyCache.clearAll()`
unconditionally before `loadTaxonomiesIfNeeded`, so `isCategoryStale()` was always true and the
24-hour SQLite cache never served a hit. Simply removing `clearAll()` was not safe — the cache
has no site URL key, so it would serve stale data from a previous site on a site switch.

### C3. ProseMirror positions vs UTF-16 lengths in spell context

**File:** `Sources/QuillKit/Resources/editor.html:1561` (`spellContextAtPoint`)

`to: from + word.length` uses JS string length (UTF-16 units), but ProseMirror positions count
characters. A word adjacent to emoji/astral text will replace the wrong range when a spelling
suggestion is applied. Low frequency, but silent corruption when it hits.

---

## Smaller optimizations and cleanups

✅ **All fixed 2026-06-10:**
- `selectionchange` message no longer includes the `text` field (Swift only read `rect`).
- `applySpellErrors` builds one alternation regex for all words instead of one per word per node.
- `parseWPDate` fallback formatter is now a cached static (`utcNoSuffixFormatter`).
- Dead `index` parameter removed end-to-end: the `insertImageAtIndex` message is now
  `insertImage` (no payload), `imageInsertIndex: Int?` became `showImagePicker: Bool`,
  the `"index"` key is gone from the `.insertMediaURL` userInfo, and the JS global is
  `window.insertImage(url, …)`.
- Stale `anthropic-beta` headers removed (prompt caching and web search are both GA);
  the two beta-header tests replaced with one asserting no beta header is sent.
- `codesign --deep` dropped from `build.sh` (signs the bundle directly).
- `EditorView` now implements `dismantleNSView`, calling `removeAllScriptMessageHandlers()`.
- Stale "Walks the AppKit view hierarchy…" doc comment replaced with an accurate one.
- `KeychainStore` renamed to `CredentialsStore` (source file, tests, `testing-plan.md`,
  and `CLAUDE.md` all updated; historical specs/plans left as-is).

Original findings:

- **`selectionchange` ships the full selected text to Swift on every selection change**
  (`editor.html:1772`) — Swift only reads `rect`; drop the `text` field from the message.
- **`applySpellErrors` is O(words × text nodes)** with a fresh `RegExp` per word per node
  (`editor.html:1519`). Build one alternation regex once; only matters on long posts with many
  errors.
- **`parseWPDate` builds a `DateFormatter` per call** (`PostEditorView.swift:802`) — make it a
  cached static like the ISO formatter.
- **Dead `index` parameter through the image-insert chain** — `insertImageAtIndex` →
  `imageInsertIndex` → `info["index"]` → `insertImageAt(_index, …)` ignores it and inserts at
  the cursor. Remove the plumbing.
- **Stale beta headers** (`AnthropicClient.swift:116`) — `prompt-caching-2024-07-31` is long GA;
  web search likewise no longer needs its beta flag. Harmless but removable.
- **`codesign --deep` is deprecated** (`build.sh`) — harmless for a single-binary bundle today;
  sign the bundle directly.
- **No `dismantleNSView` in `EditorView`** — script message handlers aren't removed. No retain
  cycle exists (coordinator holds the webview weakly), so this is hygiene:
  `removeAllScriptMessageHandlers()` on teardown is cheap insurance.
- **Stale doc comment** at `PostEditorView.swift:796` — "Walks the AppKit view hierarchy…" sits
  above `parseWPDate`, describing a function that no longer exists.
- **Naming nit:** `KeychainStore` stores nothing in the keychain. `CredentialsStore` would stop
  the next reader from assuming keychain ACLs apply.

---

## Architecture observations

No urgent action; consider when next touching these files.

- **Layering is clean.** `QuillKit` models/clients/stores are UI-free and well tested; views
  are thin over `AppState`. The single-WKWebView-across-posts design is the right call.
- **`PostEditorView` (812 lines) carries too many roles:** view layout, autosave orchestration,
  conflict resolution, publish flow, drag-drop upload, and the AI pipeline. Extracting an
  `@MainActor` view-model (the save/autosave/conflict state machine especially) would make the
  trickiest logic in the app unit-testable — currently the one significant component the
  215 Swift tests can't reach.
- **`AppState` mixes selection state, list caches, media state, and AI settings.** Works at
  this size, but it's why every keystroke in search re-renders the editor pane (and re-creates
  the NSPanel in H1). Splitting media state out would shrink the invalidation blast radius.
