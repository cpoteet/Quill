# Manual test run, 2026-10-31

Scope: a targeted pass on the changes since 2.5.0 (block drag and Move Block, click seating, Enter in containers, View Post autosave, rejected-request reasons and term reuse, undo history on load, media inspector and filters, menu enabling, About window), then two fixes (Issues 1 and 2) and a broader sampled pass over §7 (see "Broader pass" below). Not the whole of §7. Local Studio site at `localhost:8881`, build at `dba6c32`.

## Progress

| Section | Status | Notes |
|---|---|---|
| Automated | Done | `./test.sh` passed (all suites); `--check-fixtures` 28/28 and no script handler ran |
| 7.3 Moving blocks, Move Block Up/Down, autoscroll, typing hides marker | Done | Section drag (⌘) blocked, see Harness 1 |
| 7.3 Clicking outside a line | Partial | Lists only; see results |
| 7.23 Enter in containers | Done | Columns, Buttons, tab panel, list |
| 7.8 View Post autosave | Done | |
| 7.7 Term reuse, 400 reason | Done | |
| 7.26 Media inspector and filters | Done | |
| 7.27 Menu enabling, About | Done | |
| 7.11 AI, 7.13 dark mode/narrow window, 7.1 onboarding | Not run | Dark mode and Authorize page need a person; AI untouched by these changes |

## Resume here

Nothing in flight. Fixes for Issues 1 and 2 are in the working tree, uncommitted. Not covered: dark mode drag checks, narrow window marker, section drag with ⌘, click seating in Columns, table, Pullquote, Group, Preformatted, Details and accordion titles, text drag and Finder image drop after the drag change.

## Issues

| # | Sev | Area | What happens, repro steps, and root cause |
|---|---|---|---|
| 1 | Low–Moderate | Editor, click | A click in the blank gutter either side of the text column puts the caret nowhere, and typed text is dropped. Repro: open a post, click about 80 px left of a paragraph, type. Cause (confirmed in the app): `.ProseMirror` is centred with `max-width: 38.5em`; the strip beside it is `#editor` / `#editor-wrap`, not editable, so WebKit blurs the editor. **Fixed** in `editor.html` (a `mousedown` listener on `#editor-wrap`); verified in the app, left gutter seats at line start, right gutter at line end, lower gutter on the last line. Tests: `a press in the page gutter` in `test-editor-keyboard.js`. A Codex review then found three flaws in the first version, each confirmed by reading the code and fixed: the caret went to a wrapped list or quote item's start (x is now clamped into the text block on the clicked line; verified in the app), Shift-click collapsed the selection (now keeps the anchor; verified), and a block anchored `editor` was mistaken for the container (now matched by element). |
| 2 | Low | Editor, keyboard | ⌃⌘F opened the find bar. Cause: the `document` `keydown` handler tested `metaKey` without rejecting `ctrlKey`. **Fixed** with `!e.ctrlKey`; verified in the app (no find bar). macOS 27's View menu lists Enter Full Screen as 🌐F, so ⌃⌘F is no longer a full-screen shortcut here and now does nothing. Tests: `find shortcut` in `test-editor-keyboard.js`. |

## Observations

| # | Type | Area | Note |
|---|---|---|---|
| 1 | Harness | Section drag | `left_click_drag` with the `cmd` modifier moved only the H2, not its section. The ⌘ flag reaches the page through a `flagsChanged` monitor that the tool's synthetic modifier does not drive (same limit as the Cmd+click gotcha). Needs a person. |
| 2 | Plan fix | Keyboard | See Issue 2. The View menu shows Enter Full Screen as 🌐F on macOS 27. |
| 3 | Harness | Keyboard | End does not move the caret to the end of a line (macOS scrolls instead); use ⌘→ in tests. An earlier Buttons check split a button for that reason. |
| 4 | Quirk | Click | Moved to Issue 1 and fixed. |
| 5 | Platform | Typing | macOS capitalised "edited" to "Edited" after a period during computer-use typing. |
| 6 | Positive | Drag | The amber line follows the pointer, a drop over a list or quote lands in the nearest gap between top-level blocks, a drop in the left margin works, and one ⌘Z undoes it. |
| 7 | Positive | Undo | Undo and Redo are disabled right after a post loads. |
| 8 | Quirk | Gallery | `gallery-block.html` is normalised on save (`<img/>`, comment moved inside the figure). The capture is hand-formatted and not core-shaped, so this is the reconstruction path, not a regression. |
| 9 | Harness | Dialogs | ⌘↩ and Return did not confirm the Revert alert; clicking its button did. The window looked inactive (grey traffic lights) while the sheet was up, so the keys may not have reached it. Not re-checked. |
| 10 | Platform | Typing | macOS capitalised words I typed after a full stop (`more`, `ok`) and curled straight quotes. |

## Results detail

- Automated: `./test.sh` PASS (output tail only: JS click seat 21/21, "All test suites passed"); `--check-fixtures` PASS 28/28.
- Moving blocks: PASS (screenshot). Marker shows, tooltip not captured; dim source, card, amber line seen. Drop over a list, quote, and the left margin each landed at a top-level gap. Saved content has the new order and `problems(html)` returns `[]` (REST + validator).
- Section drag (⌘): BLOCKED (Observation 1). ⇧ not tried.
- Move Block Down with ⌃⌘↓: PASS, caret stayed in the paragraph. Edit menu items are disabled on Media (screenshot).
- Autoscroll with 60 paragraphs: PASS, last paragraph dropped at the top.
- Typing hides marker: PASS; it returns on mouse move. Code view not checked.
- Other drags unchanged: SKIP.
- Clicking outside a line: PARTIAL. Click right of a paragraph line and right of a list item land at the line end; a click between two list items lands on a neighbour line (the exact midpoint is ambiguous). Gutter click: Observation 4. Columns, table, quote, pre, group, pullquote not covered.
- Enter in containers: PASS. Columns: Enter keeps the line in the column and the separator runs full height; Enter twice after the right column's text exits to a paragraph below. Buttons: Enter on a filled button makes a new one; Enter on the empty new button between two others leaves two Buttons blocks with an empty paragraph between them (screenshot; Gutenberg validity not checked for this edit). Tab panel: Enter twice exits to a paragraph below. List: Enter twice on a new empty item exits the list.
- View Post on a published post: PASS. Tooltip "View Post"; `GET /posts/999/autosaves` returned `[]` after an edit and the click; the post was unchanged on the server.
- Term reuse: PASS. A tag and a category created over REST after Quill's cache loaded were typed in the panel and saved; the post got tag 35 and category 36, and no duplicate term exists (REST).
- Rejected request (injected 400 on PUT): PASS. Banner reads "WordPress didn't accept the request: QA injected failure" with no Settings button.
- Link search with all requests failing (injected 500): PASS. The picker shows "Couldn't search: Something went wrong on your WordPress server. Try again in a moment."
- Media: filter selection draws amber (PASS). Caption edit saved (REST). Esc on Title reverted and left `modified` unchanged (REST). Changing the filter cleared the selection and the inspector showed "No Selection" (PASS). Insert from the picker prefilled the caption with its link, alt text came across, the caret went below the image, and SQLite holds the expected figure (PASS).
- About window: PASS, centred horizontally on the screen.

## Broader pass

Sampled, on the rebuilt app with the fixes.

- Fixture round trip in the real app: `settings-*` fixtures plus `unsupported-blocks.html` seeded as one post, one character typed, ⌘S → byte-identical apart from blank lines Quill inserts between the hand-written fixture's adjacent blocks; `problems(html)` reports the same single problem before and after (PASS, REST + validator). `gallery-block.html`, a hand-formatted capture with an `ids` key and indented figures, comes back normalised (`<img/>`, comment placement); it is outside `--check-fixtures`, and `settings-gallery.html` is byte-identical (Observation 8).
- Local draft: ⌘S "Saved locally"; Save to WordPress with Status Draft "Saved to WordPress", row moved to Posts and selected; ⌘S "Draft saved" (PASS).
- Conflict (REST edit, then save): Cancel keeps edits; Use Server reloads the server text and a following ⌘S shows no second conflict (PASS). Keep Local not run.
- Publish with the Status picker on Published and ⌘⇧P: published (REST `publish`), Share button appears (PASS). Scheduling: Scheduled status with the year stepped to 2027, ⌘⇧P → `future` with `date_gmt` 23:50 matching the UI's 7:50 PM EDT; unscheduling by choosing Published → published now (PASS).
- Stash: edit, Media, back → "Unsaved changes restored"; Revert dialog (clicked) reloads the server text (PASS). Move to Trash: Cancel leaves it; confirm → `trash`, editor closes (PASS).
- Footnote: marker plus note; block toolbar buttons disabled in the note; saved content ends `<!-- wp:footnotes /-->` with the body in `meta.footnotes`; validator clean (PASS).
- Table grid (hover reads 3×2, inserts 3×2), YouTube embed card "YouTube embed" (PASS). Find: counts all matches including the footnote list, Aa case toggle, Replace All (PASS). Code view: entities escaped, toolbar disabled, ⌘S in code view saves the textarea (PASS).
- Pasted PNG from the clipboard uploads, inserts a figure with the caret below, and the saved markup is valid (PASS). Media delete from the grid: "Delete Permanently?" dialog, item gone from the server (PASS).
- AI: Evaluate on a published post returned a verdict, fixes, ideas and facts (PASS). Selection Make Longer returned a result with Accept and Discard; Discard restored the text (PASS). Rephrase on a three-word selection showed Accept and Discard with the text unchanged (weak pass: possibly the model returned the same words).
- Preview of a draft followed by ⌘S: no conflict dialog (PASS). Settings opens with credentials and AI fields (PASS). Help menu: User Guide, Changelog.
- Not covered: Finder drag uploads, HEIC conversion, onboarding and Authorize page, offline wording, second-site switching, dark mode, spell-check suggestions, link popover search against live results, Pages, PDF/Word paste, Stats panel (not found in the Post Settings panel in a windowed Quill), the 500+ media grid, Keep Local, and large uploads.

## Test plan edits made

- Keyboard suite count 137 → 143 with a table for the six new tests; JS totals 2,076. Two manual checks added in §7.3 (gutter click, ⌃⌘F). §7.10 and §7.17 wording: the context menu item is Move to Trash; the publish button label follows the Status picker (Draft reads Save Draft).

## Final state

- Quill quit; `credentials.json` and `ai_settings.json` restored byte-for-byte (sha256 `237c1fb2…` and `8cc24160…`, `cmp` clean), pointing at localhost:8881. The build in `Quill.app` includes the two fixes.
- `local_drafts` empty; my autosave rows deleted (the one remaining row, for siolon.com post 105, is older and belongs to the user).
- Site: all `MTP` test posts (including the trashed one), the test tags and category, and the pasted image deleted; media 947's caption and alt text cleared back to empty. Fault injector and `qa-fault.json` removed. A throw-away PNG `mtp-paste.png` remains in `~/Documents/Claude/QuillTestFiles/`.
- Clipboard cleared. Safari was opened by View Post and Preview and left running.
- Uncommitted: `editor.html` (the two fixes), `test-editor-keyboard.js`, `docs/editor-gotchas.md`, `docs/testing-plan.md`, `Sources/QuillKit/Resources/CLAUDE.md`, and this log.
