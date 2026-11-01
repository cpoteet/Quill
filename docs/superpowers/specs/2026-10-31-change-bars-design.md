# Change bars

Mockup: `2026-10-31-change-bars-mockups.html` next to this spec. Where the mockup and this spec differ, the spec wins.

## Why

The unsaved-changes dot in the close button says that a post has changed, not where. Before Revert or Save, the only way to find out what changed is to reread the post. Technical manuals and legal drafts solve this with a change bar: a rule in the margin beside each revised passage. Quill draws one beside each top-level block that differs from the last saved version.

## Goals

- A thin grey bar in the right margin beside every top-level block that differs from the saved version, including new blocks.
- A small dot in the right margin at each gap where a block was deleted.
- The bars show which blocks differ from the saved version, the one the unsaved-changes dot and Revert use.
- Undoing a change back to the saved text removes its bar.

## Non-goals

- Marks inside a block. A one-word edit puts a bar beside the whole paragraph; a change inside a Group, Columns, list or quote puts a bar beside the whole container.
- Showing the old text, or reverting one block. Hovering a bar shows a tooltip, nothing more.
- The title, Post Settings and the featured image. They sit outside the editor, and the title is one line the author can see.
- Bars in code view.
- Telling a new block apart from an edited one. Both get the same bar.

## Anti-goals

- A bar appearing or moving beside the line the author is typing. Quill is for writing; this is the rule the grip follows too.
- A bar on a post that has no unsaved changes. A false bar teaches the author to ignore them.
- Any change to saved HTML, the word count or the selection. The bars are drawn outside the contenteditable.

## Decisions

On 2026-10-31 Chris accepted my recommendation from the mockup: right margin, grey, hidden while typing.

### Look

- **Position:** right margin, 8px right of the `.ProseMirror` column's right edge. The left margin belongs to the grip, and a bar there sits against a quote's left border and reads as part of it. The right margin is clear at every window width: `#editor-wrap` keeps 24px of right padding, including below 700px, where only the left padding shrinks.
- **Bar:** 2px wide, 1px corner radius, the full height of the block's box. Grey: `rgba(0,0,0,0.17)` light, `rgba(255,255,255,0.2)` dark. Not amber: amber already means caret, selection, drop line and links, and an amber bar would read as "selected" or as a warning.
- **Deleted block:** a 6px grey dot in the same column, centred vertically in the gap where the block was. Several blocks deleted from one gap make one dot.
- **Tooltip:** after a short hover delay, in Quill's existing tooltip style: "Changed since the last save" on a bar, "Removed since the last save" on a dot. The hover area is 12px wide, centred on the mark.
- **The marks never take the pointer** (`pointer-events: none`). The page-gutter press handler in `editor.html` acts only when the press lands on `#editor-wrap` itself (`e.target !== wrap` returns early), so a mark that took the pointer would swallow every click beside a changed block. The tooltip is driven from a `mousemove` listener on `#editor-wrap` that hit-tests the marks' positions, the way the grip's row hover works.
- The marks are `aria-hidden`. The unsaved-changes dot and the window's edited state remain the accessible signal.

### When they show

- Hidden on any keypress in the editor, and shown again on the next mouse movement, the same rule as the grip (`block-grip.js`). *(My call: the mockup's one-second timer was a stand-in. With the grip's rule, nothing reappears while the author pauses mid-sentence with the mouse still.)*
- Fade out in about 0.12s and in over about 0.35s.
- Never while code view is active, while an overlay is open (`_overlayOpen()`), or while a grip drag is in progress. They redraw when the drag ends: a moved block gets a bar at its new place and leaves a dot at its old one.
- Never while Swift reports the body as clean (`bodyIsDirty` false), whatever the comparison finds. This guards the anti-goal above if the baseline parse ever differs from the loaded document.

### What they compare against

The baseline is the post's saved body as Swift holds it: `cleanContent` and `cleanFootnotes` in `PostEditorView`. That is what `isDirty` and Revert use. The two can still disagree in one direction: after an edit is undone, the editor no longer saves from the raw original HTML, so the dot can stay on with no bars showing. That is acceptable; a bar on an unchanged block is not. Comparing against the document as the editor first loaded it would be wrong in one case that matters:

- **Restored unsaved changes.** When a remote post loads with an autosave stash, the editor shows the stash's content but `cleanContent` stays the server's. The bars must show the restored changes, so the author sees what the "Unsaved changes restored" toast refers to.

Swift sends the baseline to the editor whenever `cleanContent` or `cleanFootnotes` changes: on load, after a save, on Revert, after `reloadIfClean`, and after Save Locally. New bridge function `window.setChangeBaseline(html, footnotesJSON)`, plus `window.setBodyDirty(bool)` for the clean gate above.

### How blocks are compared

1. Build the baseline as the document the live editor would hold after loading the clean HTML, not just a parse of it. Parse it the way `window.setContent` does: `_wrapIncoming(inlineFootnotes(html, footnotes))`, then Tiptap's document creation, including the step where Tiptap's `elementFromString` drops whitespace-only text nodes before ProseMirror parses. Then run it through the editor's own plugins, so the `appendTransaction` plugins (`FootnoteSync`'s reorder, the trailing-paragraph plugin) do to the baseline what they did to the loaded document. One way: an `EditorState` with the editor's schema and plugins, with the content applied through `applyTransaction`. A bare parse skips those plugins, and every difference they make becomes a false bar once the author edits anything. Post markup is never parsed into an element of the live page (`docs/gotchas.md`); use `inertDocument()` wherever a DOM is needed. Synced patterns need nothing extra: `window.setSyncedPattern` re-renders node views and dispatches no transaction.
2. Give each top-level node a key: its saved Gutenberg HTML, serialized on its own (the node alone, through the editor's DOM serializer and `toWordPressHTML`). Match the baseline's keys to the current document's with a longest-common-subsequence. Posts have tens to a few hundred top-level blocks, so the quadratic cost is fine. Cache each key by node identity, since unchanged nodes keep their identity across transactions. Recompute at most once per animation frame, and not at all while the marks are hidden.

   Not `node.eq`. Saving does not reload the editor, so after a save the baseline is the saved HTML parsed afresh, while the editor still holds the document it had before. A probe on 2026-10-31 (in the Codex review of this spec) appended a paragraph to each of the 36 fixtures, saved, reparsed the output and compared nodes. Images, galleries and accordions in 3 fixtures came back with different attributes (`rawAttrs`, `blockAttrs`), which would put false bars on them after every save. Serializing, reparsing and serializing again gave identical output for all 36, so keys built from saved HTML agree where the nodes do not. Serializing each node on its own also means a footnote renumbered by an edit elsewhere does not mark its paragraph.
3. Between two matched nodes:
   - every unmatched current node gets a bar;
   - if there are no unmatched current nodes but there are unmatched baseline nodes, the gap gets a dot.

   So an edited paragraph gets a bar and no dot, and a deleted one gets a dot.
4. The footnotes list is a top-level node and is compared like any other, so editing a note puts a bar beside the list.
5. The empty paragraph Quill keeps after a final table, separator or card is ignored on both sides, because the save transform drops it.

### Placement

- An overlay layer outside the contenteditable, like `#block-grip-layer`, so the marks never reach `getHTML()`.
- Positions come from each block's `view.nodeDOM(pos).getBoundingClientRect()`, relative to `#editor-wrap`'s scroll content, so they scroll with the text without being redrawn.
- Redraw on document change (throttled as above), on window resize, and when a block's height changes without a transaction: images loading, embeds resizing. A `ResizeObserver` on `.ProseMirror` covers the last case.

## Testing

### JS suite (new `Scripts/test-editor-change-bars.js`, added to `test.sh`)

The comparison is a plain function that takes two ProseMirror documents and returns the changed top-level indices and the deletion gaps, so it can be tested without layout.

- **Check first, before the rest of the build:** the baseline reproduces the loaded document. For every post in `Scripts/fixtures`, the baseline built from its HTML and the document `setContent` loads have the same keys. Then, without reloading the editor, edit one block, take the save output, build a baseline from it, and check that every key except the edited block's matches the document still in the editor. That is the state after every save. Add two fixtures for this check if none exist: stored footnotes out of marker order (so `FootnoteSync` reorders them on load), and a synced pattern. If any fixture fails, the bars would show on unchanged blocks; fix the parse or bring the failure back to Chris before going on.
- Editing a paragraph: one bar, no dot.
- Inserting a block at the top: one bar on the new block, none on the blocks below it.
- Deleting a block: a dot in that gap and no bars. Deleting two adjacent blocks: one dot.
- Moving a block with the grip: a bar at the new place and a dot at the old.
- Editing, then undoing back to the original: no marks.
- A change inside a Group or Columns: one bar on the container.
- Editing a footnote's text: a bar on the footnotes list.
- The trailing empty paragraph is never marked.
- No marks while `setBodyDirty(false)` is in effect, in code view, or with an overlay open.
- The marks never appear in `getContent()` output.

### Swift

- `PostEditorView` sends the baseline on load, save, Save Locally, Revert and `reloadIfClean`.
- A remote post restored from an autosave stash gets the server content as its baseline, not the stash's.

Update the counts in `docs/testing-plan.md`.

### Real WebKit (`docs/testing-plan.md` §7, manual)

- Bars appear in the right margin, clear of the text, at the narrowest window with the sidebar and inspector open. Nothing renders past the column's right edge into the bars: a wide table, a long code line and a wide or full-width image all stay inside the column or scroll within it.
- A click on a bar, or in the margin beside a changed block, still puts the caret on that line.
- Typing hides them; moving the mouse brings them back.
- A post reopened with restored unsaved changes shows bars on exactly the restored blocks.
- Save clears them; Revert clears them; a published post that has just loaded has none.
- Bars follow their blocks while an image above them finishes loading.
- Light and dark.

## Docs to update

- `site/docs.html`: a short paragraph under Saving and Publishing.
- `docs/testing-plan.md`: the new suite, its count, the §7 steps.
- `Sources/QuillKit/Resources/CLAUDE.md`: a gotcha entry for "compare against Swift's baseline, not the loaded document", pointing at the stash-restore test.

## Gate result

Run on 2026-10-31 before the bridge and overlay were built. The baseline built from each fixture's HTML gives the same block keys as the loaded document for all 41 post fixtures (36 in `Scripts/fixtures`, 5 in `script-sinks/`). The after-save check passes for all of them, including the accordion, gallery and post-17780 fixtures whose nodes reparse with different attributes. The two extra fixtures the testing section asks for became cases inside the test instead: footnotes out of marker order need post meta, which a `.html` fixture cannot carry, and `unsupported-blocks.html` already holds a synced pattern. Removing the whitespace-node strip or the plugins from `_buildChangeBaseline` turns the gate red, so the tests can catch a wrong parse. `--check-fixtures` runs the same check in WebKit, and its 28 fixtures pass.

## Left to the builder

- Where the comparison function lives (a new `change-bars.js` beside `block-grip.js` is the expected route) and what it is named.
- How the hide-on-keypress state is shared with the grip, so the two cannot drift apart.
