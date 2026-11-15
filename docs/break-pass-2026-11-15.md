# Quill break-it pass — 2026-11-15 (post-Tiptap-upgrade, HEAD 167da0c)
Rules: live site siolon.com — drafts only, never publish. Local draft 416 is Chris's: don't touch.
REST drafts created (trash at end): 18535 18537 18538 18545

## Findings

### F1 — One unclosed inline tag in a block leaks into every later block and is saved that way (MEDIUM-HIGH, data mutation)
Repro (REST draft 18535): content = paragraph "Type here." + `<p>A sentence with an <a href="https://example.com">unclosed link…</p>` + heading + paragraph + list, all correctly delimited. Open in Quill → heading, paragraph and list item all render as links. Type one char, File → Save Draft. GET ?context=edit diff: `<a href="https://example.com">` now wraps the heading text, the next paragraph and the list item.
Same with code view: a delimited `<p><b>leaky bold</p>` bolds every following block (paragraph, heading, all list levels, quote, table header) — draft 418 bytes show `<strong>` in each.
Cause: the whole post is parsed as one HTML string (`_parseSavedHTML` / code-view parse), so the HTML parser's formatting-element reconstruction carries the open `<a>`/`<b>` across block boundaries. Verified with wp-validator on the same bytes: Gutenberg flags only that paragraph as invalid and resaves every other block byte-identically. Not a regression: v2.6.0 (Tiptap 2) also loads with one whole-document setContent.
Expected: the damage stays inside the block that has the bad markup.
Also reached by: ordinary HTML paste (`<p>Before <b>unclosed…</p><h3>…` → h3 and every later pasted block saved with `<strong>`), and Paste as Markdown with inline raw HTML (`<div>raw <b>html</div> after` → every later block, lists included, saved bold; draft 423).

### F2 — (seen once) Pasting multi-line text into the Title stores newlines in the title (LOW-MEDIUM)
Click title, paste 1500 paragraphs → title becomes a 394,223-char string with embedded \n (sqlite draft 419: instr(title, char(10)) = 258). Gutenberg keeps titles single-line (it moves extra paragraphs into the content). Would be sent to WordPress as is.

### F3 — Block-risk banner survives an undo that removes the risky block, and then holds back every later edit (MEDIUM, narrow trigger)
Code view: type a malformed run that includes an unknown block → banner "Saving this post would delete content: Acme Widget". ⌘Z back to the original → banner remains (only setContent/code-view parse re-posts blocksAtRisk). ⌘S still saved because content == cleanContent (observed). From the code, not observed: the alarm stays `.unacknowledged`, so once the user types again `alarmBlocksSaving` is true and `flushToDB` (post switch, quit) and the 30-second autosave both return early (PostEditorView.swift ~951 and performAutosave). Edits made after the undo are not kept unless the user clicks "Save anyway" about a block that no longer exists. Wording also says "published post" on a local draft. (Full control timed out before I could repro the loss on screen.)

### F4 — (seen once) Paste as Markdown into an empty paragraph leaves that empty paragraph above the pasted blocks (LOW)
Return, then ⇧⌘V → saved `<!-- wp:paragraph --><p></p><!-- /wp:paragraph -->` ahead of the H1 (draft 423).

### F5 — Multi-block paste into a table cell nests headings/lists/paragraphs/tables/details inside `<td>` (LOW)
Draft 418: cell holds `<h2 class="wp-block-heading">…<ul class="wp-block-list">…`. Gutenberg's cells are inline RichText and its paste flattens to inline. A table nested in a list item cell even had its row hoisted into the outer table (draft 421). wp-validator passes it, so it isn't an invalid-block error.

### F7 — One keystroke deletes a preserved block (MEDIUM, undoable)
Draft 426: Backspace at the start of a paragraph that follows an unknown block (acme/widget) deletes the whole block; forward Delete at the end of a paragraph before one does the same; Backspace after a separator deletes it. Forward Delete in an *empty* paragraph instead selects the block (amber outline), and typing one letter then replaces the block with a paragraph. ⌘Z restores each. Gutenberg selects a block it can't merge into instead of deleting it. ProseMirror's joinBackward/joinForward delete an atom outright; pre-existing.

### F8 — Paste over a selection that ends at the start of the next block swallows that block (MEDIUM)
Shift-click selection from inside "BBB" to the line after "CCC" (head at the start of the following code block), paste rich HTML (h2, p, ul): the code block, which was not visibly selected, was joined into the last pasted list item as `<br>`-separated text, and Tiptap's paste rules then turned its literal `**not bold**` into real bold. A plain triple-click on CCC is fine. ⌘Z restores.

### F6 — Cosmetic (LOW, each seen once)
- Details block inside a narrow container (column → tabs): the "CLOSED ON THE SITE" label draws over the summary text.
- Find: after Replace All the counter stays at "1 of 20000" until focus moves (the replace itself was correct: 20,000 escaped replacements).
- Return in an accordion heading does nothing, so text typed next lands in the heading.

### Notes (not bugs)
- F1 is not a Tiptap-upgrade regression: setContent has always parsed the whole post as one string.
- 10-level list nesting, Shift-Tab out, grip drag, Move Block: valid output; adjacent lists stay separate blocks.
- Columns→accordion→tabs→details nesting validates clean. Inserting Columns with the caret in a table cell places it after the table.
- Undo/redo across a code-view edit works.
- Unsaved remote edit survives switching posts (restore toast).
- Markdown footnotes `[^1]` and task-list checkboxes are pasted as literal text / plain bullets.
- `javascript:` link URL is silently refused (no message). Quotes in a URL are escaped correctly.
- Conflict dialog (server edited under Quill) → Keep Local saved local text, status stayed draft. Double ⇧⌘P and double-click Save to WordPress each created exactly one post.
- Hostile paste (img onerror, svg onbegin, javascript: href, iframe) ran nothing; dropped cleanly.
- 1500-paragraph paste (394 KB): instant, no typing lag, 1501 blocks saved.
- Undo×60/redo×60 round trip: byte-identical. Block move ×12 up/×14 down past unsupported block, table, footnotes: same content. Footnote delete+undo restores body.
- kill -9 3 s after typing loses the edit: by design (30 s autosave). ⌘Q and ⌘N immediately after typing both flushed correctly.
- Delimiter probe caveat: macOS smart dashes turned typed `-->`/`<!--` into `—>`/`<!—` in the title and paragraph, so only the code block got real delimiters (escaped correctly). User text inside block-comment JSON (tab label, embed URL, code language) was not probed. The hostile title was only saved locally.
- After Replace All the computer-use tool reported "no app holds keyboard focus" until I clicked the sidebar; Quill was idle (0% CPU). Unverified whether that was app state or tool.
- `\`\`\`code ` takes "code" as the language (Tiptap behaviour) → `language-code` class.
- A paragraph's leading space is trimmed on save.

## Second pass (2026-11-15 afternoon)
- Boundary keys beside unknown blocks/separator → F7. Enter between atoms fine.
- Input rules don't fire inside a code block or as a heading in a quoted list item. Rich paste into a code block lands as plain text.
- Mixed-selection paste → F8.
- Seeded remote draft 18545 (unsupported-blocks, tabs, accordion, buttons, embed, pullquote): edits inside tabs saved; every preserved block (html, shortcode, calendar, navigation, synced pattern #1234, nextpage, more, acme, embed, pullquote, buttons) came back intact; Quill also repaired the fixture's invalid accordion headings (validator clean).
- Revert to Saved (confirm dialog) and conflict → Use Server both work.
- Block-comment JSON: serializeAttributes escapes `--`, `<`, `>`, `&`, `"`, `\` exactly as WordPress does.

## Gates
- ./test.sh: 22/22 suites green. --check-fixtures: 28/28, no script handler ran.

## Not covered
- Image/media upload, paste or drag (would create live media on siolon.com); featured image; gallery.
- New categories/tags (would create live terms). Publishing, scheduling, editing published posts.
- Network faults (no fault injector on prod), AI/Evaluate, VoiceOver, dark mode, second site.
- Live media, new terms, publishing, network faults, AI: still out of bounds on the production site.
- Second pass covered: table-cell input rules (→ F9), an accordion panel edit, inserting Buttons, Pullquote and Custom HTML (validator clean apart from the case above), the hostile title through WordPress (round-trips exactly as typed, as a draft). Embeds were loaded and preserved but not inserted. Pasting a URL to make one would fetch nothing, but it was not tried.

## Cleanup state
- REST drafts 18535, 18537, 18538, 18545, 18549 moved to Trash (18549 was local draft 418, saved to WordPress to check the hostile title) (not force-deleted). Quill's Posts list shows them until refreshed; 18538 may keep an `autosaves` stash row.
- Local QA drafts left in drafts.db: 419, 420, 423, 424, 425, 426 (edited this pass), 427, 428 (418 moved to WordPress as 18549) (Chris's 416 verified byte-identical to the pre-pass backup).
- Repo: no tracked changes.

## Fixes (uncommitted)
| Finding | Fix | Proof |
|---|---|---|
| F1 unclosed tag leaks across blocks | `closeLeakingTags` (editor-transforms.js) in `_wrapIncoming`; modeled leaf blocks only | bridge tests, `settings-unclosed-tag.html`/`.saved` in both corpora, `--check-fixtures` 29/29 |
| F3 stale block-risk banner | `_riskStep` restores each side's alarm on undo/redo; wording "from the post" | preservation tests; in app: typing after undo reached SQLite on a switch |
| F7 one-key delete of textless blocks | `_selectTextlessBlock` in `_edgeBackspace`/`_edgeDelete`; `handleTextInput` over a selected preserved block | keyboard tests; in app |
| F8 paste swallows next block | `_trimSelectionOffNextBlock` before the paste | paste tests; real-WebKit harness |
| F5 blocks into a table cell | `_asCellLines` (reuses `flattenPastedCells`) for ⌘V/drop and Paste as Markdown | paste tests; real-WebKit harness; validator clean |
| F4 + Markdown leak | `_closeRawHTMLBlock` via marked `walkTokens`; empty landing line replaced | paste tests; in app |
| F2 title newlines | `TitleTextField.singleLine` via `shouldChangeTextIn` | Swift tests; in app (undo works) |
| F6 details label overlap | summary `padding-right` when the label shows | in app |
| F9 block Markdown rules in a table cell (found in the second pass) | `_noBlockRulesInLines` also stands down in a cell | keyboard tests; in app |

Regressions caught and fixed before hand-off: F7 first selected the block above a nested first list item or quote line (now only a line directly beside the block), and F5 flattened a pasted table or cell range instead of filling the grid (a table on its own is now left to ProseMirror). Both are pinned by tests.

Left as is, with reasons:
- A literal `<!-- /wp:html -->` typed inside a Custom HTML block is saved verbatim and closes the block early in WordPress's parser. Gutenberg also saves Custom HTML raw, so it is expected to behave the same there (not checked in Gutenberg).
- Ordinary ⌘V of HTML with an unclosed tag: WebKit's clipboard HTML comes from a live DOM and is always balanced; only synthetic clipboards can carry one, and the source page renders the same way.
- Inside the one bad block (or raw-HTML chunk) text after the unclosed tag stays bold/linked, as a browser renders it.
- Return in an accordion heading doing nothing: deliberate (testing-plan row 306).
- Find counter "1 of 20000" after Replace All: the code recounts; on 11 matches it reads "0 of 0" at once. The stale count was a repaint lag after a 20,000-step transaction.
- kill -9 losing up to 30 s: by design.

## Codex review (gpt-6.1-sol, high) — all four findings verified and fixed
- P1 `closeLeakingTags` threw when an unclosed comment swallowed its DOM probe, aborting `setContent` → the repair now appends closing tags (`leakingTagClosers`), no DOM probe. Reproduced first.
- P2 Paste as Markdown closed a raw table split across two tokens by a blank line → same closers-only repair. Reproduced first.
- P2 Undo/redo cleared a real alarm when the parse changed nothing visible (equal documents) → such a parse is not tracked; the alarm stays up. Confirmed from the code.
- P2 The repair descended into a preserved block nested in a container → the collector stops at any unmodeled block. Reproduced first.
None rejected.

## Also fixed after the pass
- Deleting a post trashed outside Quill (still listed) failed with HTTP 410 and left the row: `trashPost`/`trashPage` now treat WordPress's 410 `rest_already_trashed` as done.
