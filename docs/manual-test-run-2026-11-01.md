# Manual test run, 2026-11-01

Scope: an exploratory pass over the whole editor on one new local draft: inline formats, the style menu, lists, every toolbar button, every Additional blocks entry and its second toolbar row, images (library insert, size, align, Rounded, Link to Full Image, handle resize, caption), galleries, footnotes, embeds, find and replace, code view, paste, block moves, click seating and caret keyboard behaviour. Build at `94917b9`, no source changes. Not the whole of §7.

Quill was connected to `https://www.siolon.com`, not the local Studio site, so nothing was uploaded, no alt text was edited, Evaluate and Generate were not run, and nothing was published. Library images were inserted by reference only.

## Progress

| Area | Status | Notes |
|---|---|---|
| Inline formats, link, New tab | Done | Saved HTML checked and valid |
| Style menu, lists, blockquote, code block, table | Done | Issue 1 |
| Additional blocks (Separator, Pullquote, Preformatted, Custom HTML, Details, Buttons, Columns, Accordion, Tabs) | Done | Issues 4, 5 |
| Images and gallery | Done | Issue 2; uploads, alt text, drop and paste skipped (production site) |
| Moving blocks, Move Block Up/Down | Done | Section drag with ⌘ not retried (Harness 1 of the 2026-10-31 run) |
| Click and caret behaviour | Done | Issue 3 |
| Footnote, Embed, Find and replace, Code view, Spell check, Paste, Paste as Markdown | Done | |
| Evaluate, Generate | Skipped | Real API key; Generate opened its "Replace Content?" alert and was cancelled |
| Dark mode, VoiceOver, inline images in text, image upload, drop and paste | Not run | Need a person, or write to the site |

## Resume here

Nothing in flight. The test draft is deleted. A draft that was already in Local Drafts (Untitled, id 381) was not touched.

## Issues

| # | Sev | Area | What happens, repro steps, and root cause if read |
|---|---|---|---|
| 1 | Low | Toolbar, style menu | After choosing an item from the Paragraph/Heading menu, the next click on the style button does nothing; the second click opens the menu. Repro: click the button, choose Heading 2, wait 2 s, click the button → no menu; click again → it opens. 4 of 4 attempts, with or without a click in the editor in between. The Additional blocks menu does not do it. Not a read: `setHeadingLevel` and the button's click handler in `editor.html` (about line 5740) close and toggle correctly, so the cause is not found. |
| 2 | Low | Image, Rounded | Clicking Rounded on a selected image toggles the class but deselects the image: the handles and the size popover close and the caret moves to the start of the caption. The alignment buttons keep the selection. 2 of 2. Chaining another control needs a second click on the image. |
| 3 | Low | Accordion, caret | Expanding a collapsed accordion by clicking its header row leaves two caret bars in the empty or short panel (the real one at the text, a second about 65 px to its right); typing clears the extra one. 2 of 2. Collapsing and expanding via −Item or Esc does not show it. |
| 4 | Low | Tabs, row 2 | With the caret in a tab's title the second row shows +Tab, −Tab and ✕ but not Default; it returns with the caret in the panel body. Clicking a tab label puts the caret in the title, so Default is hidden right after choosing a tab. 2 of 2. |
| 5 | Question | Details, insert | A new Details block puts the caret in the body, not the empty title (the Accordion puts it in its heading). Typing right after Insert fills the body and leaves the title hint showing. 1 of 1. §7.23 asks only for "somewhere sensible". |

Fixes, uncommitted in `editor.html` with tests: 2 (`_dispatchSetting` reselects an atom block after a setting change), 4 (`_panelOfTitle` resolves a tab's panel from its title), 5 (`insertDetails` seats the caret in the summary). Issue 3: collapsing from the header now moves a caret in the hidden panel up to the title; the second bar is gone in the app. Issue 1: the style menu now opens on mouse-down, as a native pop-up button does, with click kept for the keyboard; the first click after choosing a style opened it 2 of 2. All five were re-checked in the rebuilt app on a new draft, which was then deleted. Each fix has a test that fails without it, except issue 1, which jsdom cannot press. `./test.sh` passes 22/22.

## Observations

| # | Type | Area | Note |
|---|---|---|---|
| 1 | Improvement | Link | ⌘K does nothing. There is no shortcut for the link popover, in the menus or the editor. |
| 2 | Improvement | Image resize | Dragging a handle past the file's size keeps the smaller `src`: a Medium image (300 px file) dragged to 422 px saves `width:422px` with `-300x175.png`, so it is upscaled. The Thumb, Medium, Large and Full buttons swap the `src`. |
| 3 | Quirk | Table | Header off deletes the header row and its text (undo restores it); Footer on adds a row. This matches Gutenberg's "Header section" toggle. |
| 4 | Quirk | Columns | Tab inside a column does nothing (it neither moves to the next column nor inserts a tab). Tab in a code block or preformatted block inserts a tab. |
| 5 | Quirk | Click | Clicking below a final blockquote that has a cite seats in the cite; Return exits to a new paragraph. Clicking below a table with a trailing paragraph seats in that paragraph. |
| 6 | Quirk | Paste | Plain-text paste converts `**bold**` and bare URLs but leaves `- ` and `# ` literal. Paste as Markdown (⌘⇧V) converts headings, lists, quote, code, table, link, emphasis and strikethrough. |
| 7 | Quirk | Footnote | Return inside a footnote stores `<br>` in the footnote's `content`. |
| 8 | Quirk | Click, row 2 | A click made while a second toolbar row is showing lands on the shifted layout, one line higher than the same spot without the row. Not a bug: it follows the pointer, and cost two false alarms in this run. |
| 9 | Platform | Image | macOS draws its "Ask Siri" circle over a selected image; it appears in screenshots near the toolbar and is not Quill's. |
| 10 | Harness | Typing | macOS substituted `pre   spaced` with `pre. s paced`, capitalised `a2` to `A2`, and the pointer's hover and tooltip stuck on ABC through three `mouse_move` calls (a click cleared it). |
| 11 | Harness | Keys | A ⌃⌘↑ sent right after another Move Block key did nothing once; sent alone it worked. |
| 12 | Positive | Save | Every block saved by the pass validates: `problems(html)` returned `[]` on the full draft, including footnotes, the embed, Custom HTML, Accordion, Tabs, Details and the linked image. |
| 13 | Positive | Code view | Toggling code view on and off and saving left the saved HTML byte-identical apart from the text typed afterwards. |
| 14 | Positive | Moves | Dragging a block by its marker lands in the nearest gap and one ⌘Z undoes it. ⌃⌘↑/↓ move a block with the caret kept. The change bars appear beside moved and edited blocks. |
| 15 | Positive | Size | At 900 pt the toolbar keeps full-size buttons and scrolls sideways; every button is reachable. |

## Results detail

- Inline formats: PASS. Bold, italic, strikethrough, inline code and a link with New tab saved as `<strong>`, `<em>`, `<s>`, `<code>` and `<a target="_blank" rel="noopener">` (SQLite + validator).
- Style menu: PASS for H1–H6 and Paragraph; FAIL (issue 1) for reopening it after a choice.
- Lists: PASS. Nested bullet via Tab, ordered list, double Return exits.
- Blockquote: PASS. Cite, Plain, ✕ (Delete block), ⌘Z restores it.
- Code block: PASS. Three Returns exit and trim the blank lines.
- Table: PASS. Grid picker, Tab through cells, +Row, +Col, −Row, −Col, Header, Footer, Stripes; saved `thead`, `tfoot` and `is-style-stripes` validate.
- Additional blocks: PASS for insert, typing, exit and save of Separator, Pullquote (Return twice exits), Preformatted, Custom HTML (HTML and CSS tabs, Edit… reopens with content), Details, Buttons (+Button, Link, Outline), Columns (+Col), Accordion (+Item, −Item, Auto-close, Icon side, header click collapses), Tabs (+Tab, Default). Issues 3, 4, 5.
- Images: PASS for library insert with prefilled caption, Thumb 150×150, Medium 300×175, Large 1024×599, Full 1300×760, typed width 400 → height 234, Reset, left/centre/right, handle resize 422×246, caption edit, Link to Full Image, Backspace deletes and ⌘Z restores. FAIL (issue 2) for Rounded. SKIP: alt text, upload, drop and paste.
- Gallery: PASS. Three images selected, Insert Gallery, Edit… removes one and updates.
- Footnote and Embed: PASS. Marker and back-link work; a YouTube URL becomes an embed card.
- Find and replace: PASS (`1 of 2`, Replace, All).
- Spell check: PASS. Highlights, cleared on editing.
- Moving blocks: PASS by marker drag and by ⌃⌘↑/↓. A drag that ended near the viewport edge autoscrolled and landed one gap higher than aimed (not a repro).
- Click and caret: PASS. Right of a line seats at the line end, the left and right gutters seat at line start and end, Backspace at a block start merges, Return splits, ⌥⌫ merges at a block start, ⌘Z undoes a split, shift-arrow selection across paragraphs takes ⌘B and the link popover, Undo and Redo buttons work.
- Markdown input: PASS for `##`, `-`, `1.`, `>`, `**`, `_`, `` ` `` and `---`.
- Paste: PASS for plain text and Paste as Markdown (observation 6).
- Evaluate, Generate: SKIP (API key); Generate's alert cancelled, content intact.

## Test plan edits made

None.

## Final state

Quill (this build) was quit and relaunched by `build.sh` and is still running. `credentials.json` and `ai_settings.json` match the recorded sha256 (`0b04375d…`, `627b4c6b…`) and point at `https://www.siolon.com`. The test draft (id 382) is deleted; draft 381 is the one that was already there. The five `autosaves` rows are from earlier runs and were left. The local Studio site was offline at the start, was started for the pass and has been stopped. No repository changes other than this log. The clipboard was overwritten.
