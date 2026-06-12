# Code Review — 2026-06-11 Feature Commits

**Scope:** all 25 commits from 2026-06-11 (`aa544fb^..c35f85f`) — five writing features (post statuses, live stats, find & replace, embed blocks, footnotes) plus the footnote back-arrow follow-up.

**Method:** 7 independent finder angles (line-by-line scan, removed-behavior audit, cross-file tracing, reuse, simplification, efficiency, altitude), ~38 candidates deduplicated to 16, each verified individually against the working tree.

**Verdict:** the work is solid and architecturally consistent — one real correctness bug in the embed wrapping, one minor find-and-replace glitch, and a handful of smaller observations. Several scary-looking candidates (footnote backref round-trip duplication, find-bar/code-view state desync, stale publish dates leaking into private-post payloads) were verified and **refuted** — those paths are properly guarded.

---

## Findings, ranked

### 1. Bug — identical embeds get double-wrapped in block comments

**File:** `Sources/QuillKit/Resources/editor-transforms.js:159`

`result.replace(figHTML, ...)` with a string argument replaces only the *first* occurrence. If a post contains two embeds with the same URL (same `outerHTML`), the second loop iteration matches the already-wrapped first figure — producing nested `<!-- wp:embed -->` comments around figure 1 and leaving figure 2 unwrapped. WordPress will choke on the malformed block comment structure.

**Fix:** avoid string surgery entirely. While still in the DOM, insert `doc.createComment(' wp:embed ' + JSON.stringify(attrs) + ' ')` before each figure and a closing comment after (plus `\n` text nodes), then serialize once with `div.innerHTML`. This also fixes the O(n×m) full-string rescan per embed (finding 5's cousin) and makes the transform idempotent by construction.

### 2. Minor bug — Replace scrolls using stale match positions

**File:** `Sources/QuillKit/Resources/editor.html:2137-2138`

`_replaceActive()` dispatches the replacement transaction, then immediately calls `_scrollToActiveMatch()` while `_findMatchPositions` still holds pre-replacement offsets. When the replacement text differs in length, the scroll targets a shifted position. The editor's async `update` handler re-collects matches afterward, so the state self-heals, but the scroll itself can land wrong.

**Fix:** re-collect matches before scrolling, or map the stored positions through `tr.mapping`.

### 3. Behavior — word/character counts include footnote text and embed URLs

**File:** `Sources/QuillKit/Resources/editor.html:1975`

`countStats(editor.getText())` counts everything in the doc: footnote list items (`content: 'inline*'`) and the raw URL text inside embed cards. The stats therefore overstate the body the reader actually sees. Probably acceptable for a writing aid, but for parity with Gutenberg's counter, count from a filtered text source (skip `footnotesList` and `embedBlock` nodes in a `doc.descendants` walk).

### 4. UX — switching status away from "future" silently discards the scheduled date

**File:** `Sources/QuillKit/Views/Settings/PostSettingsPanel.swift:33-39`

`statusDidChange()` nils `publishDate` for every non-future status, and the tests codify this — so it may be intentional. But the flow "future (date picked) → private → oops, back to future" loses the chosen date and resets to now+1h. Stashing the last-chosen date in a private property and restoring it on return to "future" would make the picker forgiving without changing payload semantics (which are correct — verified that `dateGmt` is only ever sent from `publishDate`, so no stale date leaks for private posts).

### 5. Efficiency — find rescans and FootnoteSync walks are per-keystroke full-document passes

**Files:** `Sources/QuillKit/Resources/editor.html:2152` (find input), `editor.html` FootnoteSync `appendTransaction`

The find input's `input` listener and the editor-update hook both run `_collectFindMatches()` (full `doc.descendants` + regex) with no debounce, and `FootnoteSync.appendTransaction` walks the whole doc on every `docChanged` transaction (the `docChanged` early-exit guard is present, which is good). For blog-post-sized documents this is fine; for very long docs, the levers are a ~150 ms debounce on the find input and a cheap "does the doc contain any footnote marker" pre-check in FootnoteSync.

### 6. Cleanup — status strings deserve a `PostStatus` enum

**Files:** `PostEditorView.swift:676` (`publishButtonTitle`, `toastMessage`), `PostSettingsPanel.swift` (picker tags, `statusDidChange`), `PostListRow.swift:31` (`statusColor`, subtitle)

Raw `"draft"/"pending"/"publish"/"future"/"private"` strings are switched on in five places across three files. A `PostStatus` enum with `buttonTitle`, `toastMessage`, `badgeColor`, and `label` computed properties would give exhaustiveness checking the next time a status is added. Not urgent — the helpers are at least unit-tested now.

### 7. Design note — embed provider is re-detected on every save, not stored

**File:** `Sources/QuillKit/Resources/editor-transforms.js` (`detectEmbedProvider`, `embedClassFor`)

`detectEmbedProvider` runs in both `renderHTML` (via `embedClassFor`) and `toWordPressHTML`, so changing the provider host list silently re-classifies existing embeds on their next save. Storing the provider in node attrs at insert time would pin it. Arguably re-detection is the desired behavior (it fixes past misclassifications), so this is a conscious-choice item, not a defect.

### 8. Doc inaccuracy in CLAUDE.md

The footnote back-arrow gotcha says the `.footnote-backref` class "is stripped from the `<li>` innerHTML in `FootnoteItem.renderHTML()`" — verification shows the stripping actually happens in `FootnoteItem.parseHTML`'s `getAttrs` (`editor.html:1420`), plus the idempotency guard at `editor-transforms.js:134`. Worth a one-line correction so the gotcha doesn't mislead a future session.

---

## Holistic architecture assessment

The five features fit the established architecture well — this was the strongest part of the review:

- **Layering is respected.** Every pure transform (`countStats`, `findMatches`, `detectEmbedProvider`, `embedClassFor`, footnote renumbering/backrefs) landed in `editor-transforms.js` where it's testable via Node/jsdom, and all five got tests. Interactive/stateful code (find bar, NodeViews, FootnoteSync) stayed in `editor.html`. Swift-side helpers (`PostStats`, status functions) are static/pure and unit-tested.
- **The stats bridge follows the existing pattern** — a registered message handler in `EditorView.makeNSView`, a coordinator callback, a closure wired in `PostEditorView` — exactly the same shape as `requestMediaSizes`, debounced 500 ms on the JS side. The `@State stats` does re-render the settings panel every tick while typing, but on macOS with this panel size it's negligible.
- **Footnotes are well-engineered.** The three-part coordination (CSS counters for live display, `FootnoteSync` for ordering/orphan cleanup, `toWordPressHTML` for canonical saved numbers + backrefs) verified as consistent — display and saved numbers can't diverge, and the backref save/load round-trip is clean, including through code view, thanks to the parse-side strip and the save-side duplicate guard.
- **EmbedBlock's dual render path** (NodeView card vs. `renderHTML` figure) is idiomatic Tiptap — NodeView is editor presentation, `renderHTML` is serialization — so the "keep in sync" finder flag is not a real problem.
- **One genuine altitude gap: find & replace is invisible to macOS.** It lives entirely in JS behind a webview Cmd+F. There's no Edit → Find menu item, so it's undiscoverable and un-Mac-like; if the webview doesn't have key focus the shortcut does nothing. A small `CommandGroup` in `QuillApp.commands` that calls `window.openFindBar?.()` through the coordinator (same pattern as New Post/New Media) would integrate it properly.

**If only two things get fixed:** the embed double-wrap (finding 1 — a real data-corruption path in saved HTML) and the Edit → Find menu integration.

---

## Verified non-issues (refuted candidates)

For the record, these were investigated and disproven:

- `_replaceActive()` with zero matches — guarded by `if (!m) return` (`editor.html:2134-2135`).
- Find bar stuck after code-view toggle — `_enterCodeView()` calls `_closeFindBar()` which keeps `_findOpen` and DOM in sync; `_openFindBar()`'s `codeViewActive` guard only blocks opening *while in* code view.
- Stale `publishDate` sent for private posts — payload uses `settings.publishDate.map { ... }` and the date is already nil'd by `statusDidChange()`.
- Footnote backref duplication on save/load cycles — parse-side strip + `li.querySelector('.footnote-backref')` guard make the round-trip idempotent (covered by a JS test).
- Reading-time logic duplicated between JS and Swift — no duplication; JS computes raw words/chars, Swift alone applies the 238 wpm formula. Clean split.
- Editor footnote numbering diverging from saved numbers — CSS counters (document order) + FootnoteSync reordering + save-time renumbering are coordinated; they can't diverge.
