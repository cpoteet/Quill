# Manual test run, 2026-11-12

Run in two sessions: 2026-11-12, and 2026-11-13 (nested-list keys in WebKit, the caption focus loss, §7.15, §7.16, and this log's corrections).

Scope: Task 5 Step 3 of the Tiptap 3 migration (`docs/superpowers/plans/2026-11-11-tiptap-v3-migration.md`). Build at `89eb013` (branch `tiptap-v3-migration`), no source changes during the pass. Quill connected to the local Studio site (`localhost:8881`). Full-screen computer use, REST, SQLite and `Scripts/wp-validator.js`.

Every key result in WebKit was judged against v2, not by intuition: an ad-hoc jsdom probe loads `editor.html` from `09ba7a8` (v2) and from the working tree (v3) and runs the same cases on both. 195 key cases (13 contexts × Enter, Backspace, Delete, Tab, Shift-Tab × start, middle, end) and 44 block-shortcut cases gave identical results on v2 and v3; the WebKit results matched v2 in every case driven by hand. One case behaves differently in WebKit than in jsdom (Backspace at the start of an image caption, Issue 8); for that one, Quill was built with v2's `editor.html` and bundle and the same keys were pressed: v2 in WebKit does the same as v3 in WebKit. The probes are kept in `.superpowers/sdd/2026-11-11-tiptap-v3-migration/probes/` (git-ignored; copy into `Scripts/` to run, since jsdom lives there).

## Progress

| Area | Status | Notes |
|---|---|---|
| Migration extras (plan Task 5 Step 3 list) | Done | All pass, or match v2; section ⌘-drag blocked (harness). Nested-item keys driven in WebKit on 2026-11-13 |
| Fixture round-trip (every `Scripts/fixtures/*.html`) | Done | Byte-identical, or identical to v2's save |
| 7.3 content and round-trip | Sampled | Formats, quote/cite, Unicode, style menu, ⌃⌘F, undo after load, ⌘←/⌘→ beside cards, move up/down, grip drag |
| 7.4 images | Sampled | Picker insert, size, align, Rounded, Link to Full, Reset twice, handles, paste upload; Finder drop blocked (harness) |
| 7.5 links | Sampled | Link button, autolink, paste over selection, ⌘-click |
| 7.6 code view | Sampled | Covered: toolbar disabled, formatted HTML, edit then save, no drift over two cycles, escaping. Not covered: ⌘S inside code view, switching posts from code view, panels dismissing, block comments shown before a visual edit, reopen checks, dark mode |
| 7.7 save / publish | Sampled | Local save, remote save, publish via Status + ⌘⇧P |
| 7.9 autosave / revert | Sampled | Unsaved changes restored, Revert, clean post not stashed |
| 7.11 AI | Sampled | Undo/redo of an accepted Rephrase only |
| 7.14 context menu | Sampled | Right-click in a cell selection |
| 7.18 find & replace | Sampled | Covered: highlights, counter, Next, Replace, Replace All, case-sensitive, close. Not covered: Previous and wrap-around, find bar hidden in code view |
| 7.19 embeds | Sampled | Covered: YouTube pasted, Vimeo via the Embed button, both saved with provider classes. Not covered: X, SoundCloud, TikTok and another-site URLs via the button, an unrecognised URL pasted, reopen, live-site render, no resize handles on a card |
| 7.20 footnotes | Sampled | Issue 1, Question 7 |
| 7.22 block-risk banner | Sampled | Covered: forced banner, save refused (SQLite untouched), acknowledge, save, repair clears it. Not covered: preserved block raises none, switching or closing while up, autosave suspended, reopening a post saved with a loss, untouched post, per-post state, crash checks |
| 7.23 containers | Sampled | Issues 2–4. Covered: all nine menu entries, caret placement, Esc out of each, Custom HTML sheet, button Enter rules, ⌘⇧⌫ on Details, Accordion from a tab title, no chrome saved. Not covered: Gutenberg validation, nested delete, Enter-twice exits, Columns, empty-title hints, header clicks, the inserts-from-titles matrix beyond one case, Custom HTML in a column or quote, Edit…, script handlers, CSS/JS tabs |
| 7.24 settings | Sampled | Covered: all 28 settings fixtures round-trip byte-identical, both command checks. Not covered: the per-control toggles in the UI, accordion icons, new tab, default tab, collapse caret, Details caret, turning a setting off, Gutenberg |
| 7.25 tables | Sampled | Size grid, header row, Tab, new row |
| 7.28 paste | Sampled | Paste as Markdown; full real-WebKit differential was Task 5 Step 2 |
| 7.29 change bars | Sampled | Bars, clear on save, restored stash |
| 7.15 spell check | Done | Observation 15 (plan wording fixed) |
| 7.16 stats | Done | All four checks |
| 7.1, 7.2, 7.8, 7.10, 7.12, 7.13, 7.17, 7.21, 7.26, 7.27 | Skipped | No code path through `editor.html` or the bundle; the migration diff touches no Swift (ledger ruling) |

## Resume here

Nothing in flight; the pass is finished. Quill is not running; `credentials.json` and `ai_settings.json` are restored byte-for-byte. Left on the site for Chris to decide: QA posts 1026 "QA v3 keys", 1029 "QA v3 blocks", 1030 "QA v3 classic" (drafts), 1028 "QA v3 settings" (published), and media 1034 (`pasted-image-1.png`).

Needs a person: section ⌘-drag (§7.3), Finder drops onto the editor (§7.4), dark mode and every light/dark check.

## Issues

None is a migration failure, and none was fixed during this pass. All were fixed later on the branch, in `dc9d71e` (cpoteet/Quill#24). Issues 1–6 reproduce on v2 in the jsdom probe (same document, same key). Issue 7 is a code read of code the migration did not touch. Issues 8 and 9 reproduce on a Quill build with v2's `editor.html` and bundle, in WebKit.

All of these, plus two more found outside the pass (the quote-with-cite join pinned in `Scripts/test-editor-keyboard.js`, and `---` in a footnote), are filed as one tracking issue: https://github.com/cpoteet/Quill/issues/24

| # | Sev | Area | What happens, repro steps, and root cause if read |
|---|---|---|---|
| 1 | Moderate | Footnotes, shortcuts | ⌘⌥0–⌘⌥6 in a footnote entry empty the entry's text. Repro: insert a footnote, type "FootText words", caret mid-text, ⌘⌥2 → "1." with no text. ⌘Z restores it. ⌘⇧7/8, ⌘⇧B and ⌘⌥C do nothing there, as §7.20 expects. WebKit 1×, jsdom v2 and v3 for all seven heading shortcuts. Read, not confirmed: the toolbar disables the heading button in a footnote (`editor.html:6076`) but the Heading keyboard shortcuts are not guarded, and `setNode('heading')` on a `footnoteItem` inside `footnotesList` (content `footnoteItem+`) ends with an empty item. |
| 2 | Moderate | Buttons, image | Forward-Delete at the end of a button that is followed by an image deletes the whole image block and appends its caption to the button label ("ButtonOne labelCapText words"). Backspace at the start of that image's caption does the reverse: the image goes and the caption joins the button. One keystroke removes an image; ⌘Z restores it. Repro: post 1026, caret at the end of "ButtonOne label", fn-Delete. WebKit 1× each, jsdom v2 and v3. 2026-11-13: the forward-Delete half re-verified in WebKit on v3 from a fresh load (⌘Z restored it); the Backspace half did not reproduce in WebKit in five tries: Issue 8 happened instead. |
| 3 | Low–Moderate | Buttons, tabs | Backspace at the start of the only button in a Buttons block that follows a Tabs block removes the Buttons block and appends the label to the *last* tab panel's paragraph, which was hidden; the Tabs block switches to that tab. The link is lost. Repro: post 1026, caret at the start of "ButtonOne label", Backspace → "TabTwo bodyButtonOne label". WebKit 1×, jsdom v2 and v3. |
| 4 | Low–Moderate | Tabs | Enter in a tab title adds a tab title with no panel (three titles, two panels); the new tab shows the next tab's body. Forward-Delete at the end of a title merges it with the next title (one title, two panels). Repro: post 1026, caret at the end of "TabOne title", Enter. WebKit 1× each, jsdom v2 and v3. Not checked: what such a block saves, or whether Gutenberg accepts it. |
| 5 | Question | Quote | Enter in an empty last paragraph inside a quote removes that paragraph and puts the caret at the start of the next block; with a code block or heading next, the next keystrokes go into that block. A new paragraph is only created when nothing follows the quote. §7.3 says "the empty paragraph exits the blockquote (lift out)". jsdom v2 and v3: same for a following paragraph, heading and code block. |
| 6 | Low | Cite | After Backspace removes an empty cite, the caret goes to the start of the next block, not to the end of the quote. WebKit 1×, jsdom v2 and v3. |
| 7 | Question | Footnotes | §7.20 says clicking a footnote's number in the list jumps to its marker. Only the ↩ has a handler (`editor.html:3632`); the number is the `li` marker, and a click seats the caret at the start of the note. Code the migration did not touch. |
| 8 | Low–Moderate | Image caption | In WebKit, Backspace at the start of an image caption that follows a button does nothing to the document and takes the caret away: the caret disappears and the next typed character goes nowhere (Undo stays greyed). A click back in the text recovers. jsdom (v2 and v3) instead merges the caption into the button (Issue 2), which is also what WebKit did once on 2026-11-12, so the WebKit outcome varies. Repro: post 1026, click at the end of "CapText words", ⌘←, wait a second, Backspace, type "Q". Reproduced on v3 2× after earlier edits and undos (with and without a Tab in the caption first) and 2× from a fresh load of the post; on a v2 build 2×, one from a fresh load. Arriving at the caption start by → from the end of "ButtonOne label" gives the same result (v3 1×, v2 build 1×, both fresh loads). In a fast batch with no waits (click caption, Tab, click caption, ⌘←, Backspace, "Q") the result was "CapText wordQ" — the last letter deleted instead — 1× on v3 and 1× on v2; the second click lands after the settings row has appeared and pushed the caption down 16px. Read, not confirmed: `joinBackward` asks `view.endOfTextblock("backward")`, which measures the DOM in WebKit but sees jsdom's zero-size rects as "at the start"; with the image frame (`contenteditable=false`) before the caption inside the same node view (`editor.html:1854`), WebKit may answer no and leave Backspace to the browser. |
| 9 | Low | Settings row | After ⌘Z with the caret in an image caption, the settings row shows the **button** controls (+Button, −Button, Link, Outline, New tab) while the caret and the next typed character are in the caption. The row corrects itself on the next click. Seen after the Issue 8 fast batch (2× on v3, also after undoing a K typed later; 1× on a v2 build) and, with no undo involved, after → from the end of "ButtonOne label" into the caption (v3 1×, v2 build 1×, fresh loads). In that second case the next Backspace is Issue 8, so the two are likely one cause: WebKit draws the caret in the caption while the editor's selection is still at the button. jsdom (v2 and v3): after the same undo the selection is in the caption and `isActive('buttonsBlock')` is false, so the stale row comes from the selection WebKit reports after the undo, not from history. The row is drawn by `_updateRow2` (`editor.html:6097`) from `editor.isActive('buttonsBlock')`. Not checked: what −Button does in that state, or where exactly the editor's selection is. |
| 10 | Low | Tables, context menu | With several table cells selected (a cell selection, drawn amber), the right-click menu shows **Cut and Copy greyed out**; Paste and the AI items are enabled. ⌘C copies all the cells (HTML and text, checked with pbpaste). Repro: a 3×2 table with text, drag from the first body cell to the last cell, right-click inside. Same on a v2 build, on 89eb013 and on the fixed build (2026-11-13, same draft, same drag). Read, not confirmed: ProseMirror draws a cell selection with decorations and collapses the DOM selection, so WebKit's menu sees nothing to copy. |

## Observations

| # | Type | Area | Note |
|---|---|---|---|
| 1 | Quirk | Lists | Backspace at the start of the first item of a list that follows a paragraph selects the paragraph above (node selection) and leaves the list alone. Same on v2. |
| 2 | Plan fix | Images | §7.4 said dragging any handle keeps the aspect ratio. Only corners do (`editor.html:2011`); an edge handle stretches one axis by design, and Shift frees a corner. Corner drag 800×600 → 417×313 passed. Plan wording fixed. |
| 3 | Plan fix | Block-risk banner | §7.22's past-tense stage is set only on the save-to-WordPress path (`PostEditorView.swift:1214`). "Save Locally" leaves the acknowledged wording, which is right, since a local draft has no WordPress revisions. Plan wording fixed. |
| 4 | Plan fix | Code view | §7.6 expected `"quoted"` to show as `&quot;` in code view. Text-node quotes are not escaped, which is correct HTML; `&lt;` and `&amp;` show as expected. v2 and v3 both save a plain `"` and decode `&quot;` in text to `"` (probe). Plan wording fixed. |
| 5 | Quirk | Dirty state | A post seeded with the older accordion-heading markup stays dirty after every edit is undone, because the first edit re-serialises the accordion as current core writes it (`has-icon`, toggle icon). Expected; the fixtures README says the same of `accordion-block.html`. |
| 6 | Plan fix | Publish | ⌘⇧P on a draft whose Status is Draft saves it as a draft; it published once Status was set to Published. That is §7.17's rule (the button follows the Status picker); §7.7 read as if ⌘⇧P publishes a draft outright. Plan wording fixed to point at §7.17. |
| 7 | Harness | Keys | The computer-use key named `Delete` is Backspace; forward delete is `forward_delete`. A first batch that used `Delete` was re-run. |
| 8 | Harness | Section drag | `left_click_drag` with `cmd` moved only the H2, not its section, as in the 2026-10-31 run. Needs a person. |
| 9 | Harness | Finder drop | With Finder in front, the Claude desktop app's window (hidden from screenshots) sat over Quill's editor, so the drop went to Claude, not Quill. The upload-and-insert path was checked by pasting a PNG instead. |
| 10 | Harness | Clicks and typing | Two double-clicks within the double-click interval counted as a triple-click (whole line selected). A macOS autocorrect bubble ("C2") took a click. Smart quotes turned one typed `"` curly in code view despite substitutions being off. |
| 11 | Positive | Differential | 195 key cases and 44 shortcut cases identical on v2 and v3 in jsdom; every WebKit case driven by hand matched v2 (Issue 8's case against a v2 build in WebKit, since jsdom differs there). |
| 12 | Positive | Round-trip | All 28 `settings-*` fixtures in one post saved byte-identical apart from the typed character; the accordion/tabs/gallery/unsupported/group/inline-formats post and post-17780 saved byte-identical to what v2 writes for the same document. |
| 13 | Harness | jsdom | jsdom cannot stand in for WebKit at a caption's start (Issue 8): the key probes' "= v2" holds for the editor's commands, not for what WebKit does with a key ProseMirror passes on. The cases driven in WebKit by hand are the ones listed under Results detail; the rest of the 195 rest on jsdom. |
| 14 | Positive | Nested lists | All seven nested-item cases driven in WebKit on 2026-11-13 equal the v2 probe values: NestOne Enter at start, middle and end, Backspace at start, Tab (no change, focus kept), Shift-Tab; NestTwo Backspace at start, Tab, Shift-Tab. One ⌘Z restored each. |
| 15 | Plan fix | Spell check | §7.15 said the highlights clear when you start editing. The plugin (`editor.html:4152`) drops only the highlights an edit overlaps: typing elsewhere keeps them, editing "Thiss" cleared only that word. Which words are flagged is up to NSSpellChecker: for "Thiss sentense has sevral erors in it" it returns only "Thiss" and "sevral" (checked with a Swift script), and Quill underlined exactly those. Plan wording fixed. |

## Results detail

Migration extras (plan Task 5 Step 3):
- Enter/Backspace/Delete/Tab at start, middle and end of a list item, nested item, footnote entry, accordion heading, tab title, button, image caption, table cell, quote and cite: PASS against v2 (WebKit by hand, v2 by probe). Pre-existing behaviour logged as Issues 2–6, 8 and 9. Nested items: Observation 14. Image caption Backspace at start: Issue 8, matched against a v2 build in WebKit.
- Undo/redo across a ⌃⌘↑ block move, an HTML paste and an accepted AI Rephrase: PASS (screenshots).
- Undo immediately after opening a post does nothing: PASS (Undo greyed, ⌘Z twice, no change).
- Image resize by handle: PASS for corners; edge behaviour is Observation 2. Grip drag of a paragraph: PASS (amber drop line, lands in the gap, one ⌘Z). ⌘-drag of a section: BLOCKED (Observation 8).
- ⌘-click a link opens the browser: PASS (Safari came forward). ⌘-click a footnote marker: PASS (caret moves to its note; nothing opens).
- Open a published post and leave without editing: PASS on QA figures and on the block-heavy QA v3 settings (no edited dot, no autosave row).
- Block shortcuts ⌘⌥0, ⌘⌥1–6, ⌘⇧7, ⌘⇧8, ⌘⇧B, ⌘⌥C in body text: PASS (= v2). In a footnote: Issue 1.
- `1. ` and `- ` at a paragraph start fire the input rules; Backspace straight after reverts each to its text: PASS.
- Right-click inside a four-cell selection keeps it: PASS. Copy from that menu copies all four cells: PASS on 2026-11-12 (pbpaste), but on 2026-11-13 Copy was greyed out for a dragged cell selection on all three builds (Issue 10). The 2026-11-12 selection was probably a text range across cells rather than a cell selection; not re-created.
- A typed URL followed by a space autolinks; a URL pasted over a selected word links it: PASS (REST content).

Fixture round-trip: PASS. Posts 1028 (28 settings fixtures), 1029, 1030 seeded by REST, "X" typed, saved, diffed (REST); v2's save of the same document computed by probe. Validator: only the complaints already in the fixtures (`settings-image-custom-link` border style; classic `<div>` in post-17780).

Other §7 checks (all PASS unless noted; SQLite or REST plus validator unless noted):
- 7.3: bold, italic, strike, inline code, link, H1 from the style menu, bullet and numbered lists, quote with cite, code block (triple Enter exits), 2×2 table with header row, curly quotes, emoji, CJK and Arabic. Saved classes and `<thead>` present; validator `[]`. Style menu reopens on the first click after a choice. ⌃⌘F does not open Find. ⌘←/⌘→ beside a gallery and a Custom HTML card stay in the paragraph. Blockquote: Enter at the end of a quote paragraph stays inside; Enter in the cite exits; Backspace in an empty cite removes only the cite (caret: Issue 6); toggle off removes the quote. Enter in an empty quote paragraph: Issue 5.
- 7.4: picker insert, typing straight after goes below the image, Medium (300×225), align centre, Rounded keeps the selection, Link to Full Image, Reset twice (800×600 both times), no `<p></p>` saved after the image, PNG paste uploads (media 1034) with the caret below. Finder drop: BLOCKED (Observation 9).
- 7.5: link popover with typed URL. Search results, offline, mailto and javascript: links not run.
- 7.6: code view formatted, toolbar disabled; an edit made there saves; two enter/exit cycles leave the bytes unchanged; `&lt;` and `&amp;`.
- 7.7: local save toast "Saved locally"; remote ⌘S keeps draft; publish via Status = Published + ⌘⇧P (toast, badge, sidebar, Update and Share buttons); published content byte-identical. Observation 6.
- 7.9: two edits, switch away and back → "Unsaved changes restored" with bars on exactly those two blocks; Revert dialog → server copy, Revert button gone, a later save byte-identical; saved posts leave no stash.
- 7.18: highlights, "1 of 3", Next, case-sensitive "1 of 2", Replace, Replace All, close.
- 7.19: YouTube URL pasted alone → "YouTube embed"; Vimeo via Embed → "Vimeo embed"; both save with provider classes.
- 7.20: numbering follows document order, deleting a marker removes its note, ↩ jumps to the marker, body in `local_drafts.footnotes`, one `wp:footnotes`, `<sup … -link>`, no list or ↩ saved, rich paste into a note keeps only inline text and bold.
- 7.22: forced banner names the Heading block; ⌘S refused with SQLite untouched; acknowledge → save; repair in code view clears it.
- 7.23: all nine menu entries; caret placement for each; Esc leaves each; Custom HTML sheet with ⌘↩; button Enter rules; ⌘⇧⌫ deletes Details with the caret in the next block; Accordion inserted from a tab title lands after the Tabs and one ⌘Z removes it; no chrome in the saved markup.
- 7.24: both command checks clean (no missing preview class, no `NO CLASS`).
- 7.25: size grid inserts 2×2 with a header row; Tab moves through cells; Tab in the last cell adds a row.
- 7.28: Paste as Markdown converts heading, list, bold, code, link and quote.
- 7.29: bar beside an edited paragraph only; Save Locally clears it.
- 7.15 (local draft "QA v3 spell stats"): ABC underlines the words NSSpellChecker returns; editing a flagged word clears its underline (Observation 15); no crash; code view shows no spell-check markup.
- 7.16 (same draft): "8 words · 40 characters · 1 min read" for a 40-character sentence; typing three words → 11 / 56; two words typed in code view leave 11 / 56; back to visual → 13 / 68; 400 words pasted → "400 words · 1,999 characters · 2 min read".

## After the final review (2026-11-13, fixed build)

The final branch review found three Tiptap 3 regressions, fixed with tests (ledger; issue #24, bugs 12–14). Checked in WebKit on a build with the fixes, on a new local draft "QA v3 final fixes":
- `--check-fixtures`: 28/28 passed, no script handler ran.
- Table from the size grid (2×2 with a header row): PASS. Tab moves through the cells; Tab in the last cell adds a row. Cell keys match v2: Enter at the end and in the middle stays in the cell (new paragraph / split), Backspace at the start and Delete at the end leave the table alone. Dragging across four cells draws the cell selection; right-click keeps it (Issue 10 for Copy). The change bar beside the table sits in the right margin as designed.
- A classic `<table>` with `<colgroup><col width="100"><col width="250">` draws at normal widths and saves as `wp:table` with no `colwidth` (SQLite).
- `3. ` typed below `<ol type="a">` with two items adds item c (saved as a third `wp:list-item` in the same list).
- Validator on the saved draft: `[]` once the hand-written list comment carries `"type":"a"`; the input without it fails the same way, so that complaint is the test input's.

## Test plan edits made

`docs/testing-plan.md` (committed in `98766cd`), one line each: §7.4 corner versus edge handles (Observation 2); §7.6 quotes in code view (Observation 4); §7.7 ⌘⇧P follows the Status picker (Observation 6); §7.15 which highlights clear (Observation 15); §7.22 past-tense stage only on Save to WordPress (Observation 3).

## Final state

Re-checked at the end of the 2026-11-13 session:

- Quill (dev build) is not running (`pgrep`), and was not relaunched after the restore. `Quill.app` is the v3 build of `89eb013`: on 2026-11-13 it was built twice with v2's `editor.html` and `tiptap-bundle.js` (copied from `09ba7a8`) to compare Issues 8 and 9 in WebKit, and both times those two files were restored from HEAD (`git diff --quiet HEAD -- Sources`) and rebuilt.
- `credentials.json` and `ai_settings.json` restored byte-for-byte from the plan workspace's `orig/` copies: `cmp` clean, sha256 `96fc53c8…f612e` and `8d77c726…3649` match the recorded values, mode 600. `credentials.json` points at `http://localhost:8881`.
- `local_drafts`: 0 rows (the "QA v3 spell stats" draft from §7.15/§7.16 deleted). `autosaves`: the 5 rows that were there before the pass (rowids 6, 8, 13, 14, 15); none newer.
- Clipboard emptied.
- Site: post 1026 is byte-identical to its state at the start of the 2026-11-13 session (REST). QA posts 1026, 1029, 1030 (draft), 1028 (published) and media 1034 remain, pending Chris. No mu-plugin, second site or test user. The pass created no application passwords; the newest one on the account ("quill", 2026-11-13 00:17 UTC) dates from before the settings copies were taken and is the one Quill uses.
- Outside Quill, from 2026-11-12: both Finder drop attempts landed on the Claude desktop app's window, so `photo.jpg` may have been attached there (Observation 9); ⌘-click on a link opened example.com in Safari; one real Anthropic call was made (Rephrase, §7.11).
- Repo (uncommitted at the time; committed in `98766cd`): this log; five one-line wording fixes in `docs/testing-plan.md`; and, after the pass, three fixes from the final branch review (`editor.html`, three new tests, docs). The results above 2026-11-13's "After the final review" section ran on 89eb013, with Tiptap 3's `div.tableWrapper`; the tables were re-checked on the fixed build (below). `Quill.app` is the fixed build (working tree; bundle unchanged from 89eb013). On 2026-11-13 it was also built once more with v2's two editor files and once at 89eb013 for the Issue 10 comparison, and each time the working tree was put back (`editor.html` compared byte for byte with the tested fix; bundle == HEAD).
- `local_drafts` emptied again (the "QA v3 final fixes" draft); `autosaves` still the original 5 rows; settings files restored again after the last launch (cmp and sha256 OK); clipboard emptied; Quill not running. The probe scripts live in the git-ignored plan workspace (`.superpowers/sdd/2026-11-11-tiptap-v3-migration/probes/`), which is deleted when the plan finishes — whether to keep one under `Scripts/` is Chris's call.
