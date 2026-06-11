# Five Writing Features — Design

**Date:** 2026-06-11
**Status:** Approved
**Scope:** One spec, one phased implementation plan. Phases ordered smallest to largest; each phase ships independently.

1. Post stats (word count, characters, reading time)
2. Private + Pending Review statuses
3. Find & replace
4. Embeds
5. Footnotes

---

## Phase 1 — Post stats

**What:** A **Stats** section at the bottom of `PostSettingsPanel` showing `1,245 words · 6,832 characters · 6 min read`, updating live as the user types. Shown for both posts and pages.

**How:**

- A pure counting function `countStats(text)` in `editor-transforms.js` returns `{ words, characters }`. Words = whitespace-separated tokens of the ProseMirror doc's `textContent` (includes captions and code blocks); characters = full string length. Covered by Node tests (unicode, emoji, empty doc, whitespace-only).
- `editor.html` calls it on every `update` event and posts `{ words, characters }` to a new WKWebView message handler `statsChanged` (registered in `EditorView.makeNSView`, handled in `EditorCoordinator`, surfaced via a callback closure like the existing handlers).
- `PostEditorView` holds the stats as `@State` and passes them into `PostSettingsPanel`.
- Reading time is computed in Swift: `max(1, Int(ceil(Double(words) / 238.0)))` minutes, hidden when words == 0. Unit-tested.
- **Code view:** stats freeze at the last visual-mode value while code view is active (no parsing of raw HTML in the textarea).

---

## Phase 2 — Private + Pending Review statuses

**What:** The status picker in `PostSettingsPanel` becomes a dropdown (`MenuPickerStyle`) with five states: **Draft, Pending Review, Published, Scheduled, Private**. Applies to posts and pages.

This also fixes an existing bug: the sidebar already fetches `pending` and `private` items (`WordPressClient` status filter), but opening one leaves the current 3-segment control with no valid selection.

**Details:**

- `PostSettings.status` gains `"pending"` and `"private"` as valid values. No `WPPost`/`PostPayload` model changes — `status` is already a free string.
- Primary action button label per status (in `PostEditorView`):
  - `draft` → existing behavior
  - `pending` → "Submit for Review"
  - `publish` → "Publish" / "Update" (existing)
  - `future` → "Schedule" (existing)
  - `private` → "Publish Privately"
- Toast messages match ("Submitted for review", "Published privately").
- **Private and Scheduled are mutually exclusive** (WordPress cannot schedule a private post): selecting Private clears `publishDate`; the Schedule toggle is hidden/disabled while status is `private`.
- `PostListRow.statusColor` and subtitle gain distinct treatments for `pending` and `private`.
- Swift tests: status → button label mapping, private-clears-schedule rule.

---

## Phase 3 — Find & replace

**What:** ⌘F opens a compact find/replace bar inside the editor web view. Esc or ✕ closes it. Disabled in code view.

**UI (in-webview HTML, styled to match the toolbar, light/dark aware):**

- Find field, replace field, match counter ("3 of 14"), previous/next buttons, **Replace**, **Replace All**, match-case toggle (Aa), close button.
- ⌘F intercepted by a JS keydown listener; if text is selected when opened, it pre-fills the find field. Enter = next match, Shift+Enter = previous.

**Engine:**

- A ProseMirror plugin using the already-bundled `Plugin`/`PluginKey`/`Decoration`/`DecorationSet` exports (same machinery as spell check — kept as a separate plugin so the two decoration sets don't interact).
- Pure match-scanning logic (`findMatches(text, query, caseSensitive)` returning offsets) lives in `editor-transforms.js` for Node tests; the plugin maps offsets to doc positions per textblock. Matches do not span block boundaries. Case-insensitive by default.
- Matches render as inline decorations (`find-match`; active match `find-match-active`, scrolled into view).
- **Replace** dispatches `tr.insertText(replacement, from, to)` on the active match and advances. **Replace All** applies matches in reverse document order in one transaction so positions don't shift. Replacements participate in normal undo history.

---

## Phase 4 — Embeds

**What:** Explicit insert only — a toolbar button (next to the image "Add" button) opens a small in-webview popover with a URL field and Insert button. Pasted URLs remain plain links. In the editor, an embed renders as a **static placeholder card** (provider name/icon, URL, "renders on your published site" hint) — no third-party network requests. The card is selectable and deletable like any block.

**Model:** New atomic Tiptap node `EmbedBlock` with attrs `{ url, provider, caption }`.

**Gutenberg round-trip** (the saved HTML, emitted by `renderHTML`/`toWordPressHTML` and parsed back by `parseHTML` on `figure.wp-block-embed`):

```html
<figure class="wp-block-embed is-type-video is-provider-youtube wp-block-embed-youtube
               wp-embed-aspect-16-9 wp-has-aspect-ratio">
  <div class="wp-block-embed__wrapper">
URL
</div></figure>
```

- The newlines around the URL inside the wrapper div are part of the Gutenberg format and must be emitted.
- A provider table maps hostname → `{ slug, type, aspectClasses }` for: YouTube (`youtube.com`, `youtu.be`), Vimeo, X/Twitter (`twitter.com`, `x.com`), Spotify, SoundCloud, TikTok, Instagram. Video providers (YouTube, Vimeo) get `is-type-video` plus `wp-embed-aspect-16-9 wp-has-aspect-ratio`; others get `is-type-rich`.
- Unknown hosts emit a plain `<figure class="wp-block-embed"><div class="wp-block-embed__wrapper">URL</div></figure>` — WordPress resolves it via oEmbed at render time.
- An existing `<figcaption>` on a loaded embed is preserved in the `caption` attr and re-emitted verbatim. Caption *editing* is out of scope for v1.
- JS tests: provider detection table, insert → expected classes, Gutenberg HTML → node → identical HTML round-trip, caption preservation.

---

## Phase 5 — Footnotes

**What:** "Insert Footnote" (toolbar button + right-click context menu item) inserts an auto-numbered superscript marker at the cursor and adds an entry to a footnotes list pinned at the end of the document, where the user types the footnote text. Clicking a marker scrolls to its entry.

**Storage decision (approved):** Self-contained HTML, *not* Gutenberg meta parity. Gutenberg's native Footnotes block keeps text in post meta (`meta.footnotes`) plus a dynamic `<!-- wp:footnotes /-->` comment that Tiptap would strip on load. Instead Quill writes everything into the content:

- Marker: `<sup data-fn="UUID" class="fn"><a href="#UUID">N</a></sup>`
- List at document end: `<ol class="wp-block-footnotes"><li id="UUID">footnote text</li>…</ol>`

This renders correctly on any theme with working jump links. Trade-off (accepted): opening the post later in Gutenberg shows the list as an ordinary List block, not the managed Footnotes block; content still displays correctly. Meta-based parity can be a later phase.

**Model:**

- `FootnoteMarker`: inline atom node, attrs `{ id }`; displayed number is computed, never stored as the source of truth (the `N` in saved HTML is regenerated on save).
- `FootnotesList`: block node parsing/serializing `ol.wp-block-footnotes`, with list items (`li[id]`) holding inline content. Pinned to document end.

**Consistency plugin** (ProseMirror `appendTransaction`):

- Markers renumber in document order after any change.
- List entries reorder to match marker order.
- Deleting a marker deletes its orphaned list entry; deleting the last marker removes the list.
- Inserting a footnote when no list exists creates the list at the document end.

**Interaction:** Insert places the marker, creates the entry, and moves the cursor into the new entry for immediate typing. Clicking a marker scrolls its entry into view and focuses it.

**Tests:** JS round-trip (markers + list → HTML → parse → identical), renumbering on insert/delete/reorder, orphan cleanup, list-creation-on-first-insert.

---

## Cross-cutting

- **Phase ordering:** stats → statuses → find & replace → embeds → footnotes. Each phase ends with `./test.sh` green and a manual round-trip check against the live WordPress site (per the CLAUDE.md Gutenberg verification flow).
- **Testability rule:** pure logic (counting, match scanning, provider detection, footnote HTML transforms) goes in `editor-transforms.js` so `Scripts/test-editor.js` covers it; Swift-side logic (reading time, button labels, status rules) gets unit tests in the existing suites.
- **Docs:** CLAUDE.md's Gutenberg output table gains rows for embeds and footnotes; new gotchas get entries as discovered.
