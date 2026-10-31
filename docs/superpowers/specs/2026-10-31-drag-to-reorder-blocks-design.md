# Drag blocks to reorder them

Issue: [cpoteet/Quill#23](https://github.com/cpoteet/Quill/issues/23). The issue holds the WebKit research (pasteboard behaviour, bundle sizes, the 2.x extension's limits); this spec does not repeat it.

## Why

Today the only way to reorder a post is cut and paste. That is awkward for any block, and worst for images, galleries, tables and embeds, where selecting the whole block is fiddly and a paste can land in the wrong place.

## Goals

- Hovering a top-level block shows a grip in the left margin. Dragging the grip moves the block; a drop line shows where it will land.
- Holding ⇧ over a heading's grip selects the heading's whole section, and the drag moves the section.
- Move Up and Move Down commands move the current block without a mouse.
- One move is one undo step, and marks the post as edited.
- A moved block saves exactly as it did before the move, apart from its position.

## Non-goals

- Nested drags: moving a paragraph into or out of a column, Group, quote or list, or a list item within a list. Groups and Columns move as one unit with their contents.
- Multi-block selection drags.
- A block menu on the grip (Gutenberg's ⋮). A click selects the block, nothing more.
- Moving a section from the keyboard. *(My call: keep the shortcuts to one block in v1.)*
- Changing how the existing draggable nodes (embeds, galleries, passthrough cards, inline images) behave when dragged after selecting them. The new drop rules apply only to drags the grip starts, so this feature cannot change those drags. Chris accepted the inconsistency (grabbing an embed can still drop it inside a column; its grip cannot) in exchange for less machinery. Revisit when nested drags are built.

## Anti-goals

- The grip appearing while the author types. Quill is for writing; a grip flickering next to every paragraph would be a regression in feel even if it worked.
- A drop that lands a block inside a container when the author meant to put it between blocks.
- Any change to a block's saved HTML caused by moving it.
- A new JS dependency or a change to the editor's lockfile.

## Decisions

### Approach: Quill's own handle (option B in the issue)

No `@tiptap/extension-drag-handle`, no tippy, no collaboration stubs. On `dragstart` from the grip, set `view.dragging = { slice, move: true }` and clear `dataTransfer`. A grip drop is handled entirely in Quill's `handleDrop`, which returns `true`, so ProseMirror's default drop (including its own delete of the source when `move` is set) never runs for it. That handler builds the whole move as one transaction:

1. Delete the source range (block or section).
2. Map the target gap through that delete.
3. Insert the slice at the mapped gap.
4. Dispatch nothing when the drop lands in place or inside the moved section.

ProseMirror's default drop path runs only for drags the grip did not start. This uses ProseMirror's API rather than Tiptap's extension API, so the Tiptap 3 migration should not need to touch it.

The empty pasteboard is load-bearing:

- It keeps the drag out of `DroppableWebView`'s image path (`hasImageFiles` is false).
- The slice never goes through HTML serialization and parsing. That keeps unsupported blocks byte-exact, and it keeps carried attributes from being replayed onto the live page (the script-sink gotcha in `docs/gotchas.md`).

A test must fail if the grip's `dragstart` ever puts `text/html` on the pasteboard.

### What can be dragged

- Every top-level block in the document, including Groups, Columns, synced pattern cards, unsupported-block cards, galleries, embeds and tables.
- Blocks that can already be dragged by grabbing them (embeds, galleries, unsupported-block cards) get a marker as well. Their existing drag stays as it is; the marker is a second way to move them, not a replacement.
- **Not** the footnotes list (`footnotesList`) or anything inside it.
- No grip at all while code view is active (`codeViewActive`), while an AI operation is pending (`_aiOperation()`), or while an overlay is open (`_overlayOpen()`). Move Up and Move Down do nothing in the same states.

The AI rule matters because a move deletes and re-inserts the block: a pending rewrite range inside it collapses when the block is deleted, and Accept or Discard then acts on the wrong text.

### Where a drop can land

A grip drag only drops into a gap between two top-level blocks, or before the first or after the last. The drop line shows only in those gaps. Wherever the pointer is, including over a column, a quote, a list or a table cell, the drop goes to the nearest top-level gap.

- Nothing can be dropped after the footnotes list; the last gap is the one before it.
- Dropping a block (or section) back where it started, or inside the section being moved, does nothing and adds no undo step.

The same snapping function decides the drop (in `handleDrop`) and the drop line (in drag-over handling). Both return `false` / do nothing for any drag the grip did not start, so text drags, drags from other apps and Finder image drops are unchanged.

### Section drag (⇧)

- Holding ⇧ while the pointer is over a heading's grip highlights the section before the drag starts, so the author sees what will move. Releasing ⇧ before pressing removes the highlight.
- A section is a top-level heading plus every following top-level block up to, but not including, the next top-level heading of the same or a higher level, or the footnotes list, or the end of the document.
- A heading inside a Group, Columns or any other container does not start a section, and its grip is the container's grip.
- ⇧ on any other block's grip moves just that block.
- ⇧ is used because ⌥ during a drag is ProseMirror's "copy instead of move" modifier on macOS (`dragCopyModifier` is `altKey` on Mac), and ⌥-drag would duplicate the section.

### The grip: a type marker

Chris chose this from four mockups (dots, iOS-style lines, a bar the height of the block, a type marker), kept in `2026-10-31-drag-to-reorder-blocks-mockups.html` next to this spec. The grip shows what kind of block it is, set in the editor's own sans (never monospace), so it gives information as well as a drag handle.

Markers:

| Block | Marker |
|---|---|
| Paragraph | ¶ |
| Heading | h1 to h6, in small caps (`font-variant-caps: all-small-caps`) |
| Bulleted list | • |
| Numbered list | 1. |
| Quote | “ |
| Pullquote | ” (a larger closing quote, to tell it from Quote) |
| Code | {} |
| Preformatted | pre, in small caps |
| Separator | — |
| Image, gallery, embed, table, Columns, Group, Buttons, Details, Accordion, Tabs | A line glyph drawn in SVG to match the text markers' weight: a frame with a horizon (image), two overlapping frames (gallery), a frame with a play triangle (embed), a 3×3 grid (table), two side-by-side columns (Columns), a bracketed box (Group), a rounded rect (Buttons), a chevron (Details, Accordion), a tabbed folder (Tabs) |
| Synced pattern card | Two arrows in a loop |
| Unsupported-block card, Custom HTML | Angle brackets `< >` drawn as a glyph, not set in a code font |

*(My call: the exact glyph for each block. SF Symbols cannot be used, because the editor is a web page and the SF Symbols licence does not allow embedding them, so the glyphs are Quill's own.)*

Look and behaviour:

- About 13px glyphs in a 26 × 22 hit box, grey (`#b4b4b4` light, `#636363` dark), as in the mockup.
- On hover: darker glyph (`#5f5f5f` / `#c4c4c4`), a faint rounded background, and a `grab` cursor.
- With ⇧ over a heading's marker: the marker turns accent and the section gets an accent tint (accent at about 8% opacity) behind it.
- After a short hover delay, a tooltip in Quill's existing tooltip style names the block and the action: "Paragraph · Drag to move", and on a top-level heading, "Heading 2 · Drag to move, ⇧ for the section". *(My call: a type marker is not a conventional drag handle, and the tooltip is how a first-time user finds out it moves.)*
- While dragging, the card that follows the pointer shows the marker and the block's first line, cut off at about 280px, plus "+ N more" for a section.

Placement and the rest:

- It lives in an overlay element outside the contenteditable, so it can never reach `getHTML()`, the word count or the selection.
- It hides on any keypress in the editor and comes back on the next mouse movement.
- The hover area is the whole row, margin included, so moving the pointer left toward the grip does not hide it.
- Vertical position: aligned with the first line of text for text blocks, and with the top edge for media and cards. For left- or right-aligned (floated) images, it uses the column's left edge, not the image's box.
- Clicking the grip makes that block current, so Move Up/Down act on it: a text block (paragraph, heading, list) gets the caret at its start; any other block gets a node selection, as clicking it would. *(My call: a node-selected paragraph would be replaced by the next keypress, and the grip hides on keypress, so the author might not see it happen. ⇧⌘⌫ still covers only the types in `DELETABLE_BLOCKS`; this feature does not widen it.)*
- The grip is not in the tab order. Keyboard and VoiceOver users use the menu commands.

### Margin space

`#editor-wrap` has 24px of horizontal padding and the `.ProseMirror` column is centred at 38.5em. In a wide window the grip sits in the space left of the column. When the window is narrow enough that the gap is under the grip's width, the grip must still not cover text: either the column gains a left gutter at that width, or the grip moves inside the padding. Builder's choice, checked at the narrowest window Quill allows with the sidebar and inspector open.

### Drop line and drag preview

- The drop line is a horizontal line in the accent colour (`var(--accent)`), spanning the column width, in the gap the snapping function picks. StarterKit's Dropcursor places its line from the raw pointer position, which over a column or quote is inside the container, so it cannot simply be restyled: hide it during grip drags and draw Quill's own line. Other drags keep today's Dropcursor.
- The drag preview must not cover most of the window when a large Group or Columns block is dragged. Use `setDragImage` with the small card described under the grip, not a snapshot of the block.

### Move Up and Move Down

- Edit menu, after Find…, as "Move Block Up" and "Move Block Down", wired the same way as Paste as Markdown (`appState` trigger → `PostEditorView` → a `window.*` function in `editor.html`).
- Proposed shortcuts: ⌃⌘↑ and ⌃⌘↓. ⇧⌘↑ and ⌥⇧↑ are taken by text selection on macOS. Before shipping, confirm ⌃⌘↑/↓ is not a macOS system shortcut and not already handled by WebKit in a contenteditable; if it is, bring an alternative back to Chris.
- They move the top-level block that holds the caret (or the selected block) past its neighbour, skipping over a whole Group or Columns block as one unit. They do nothing at the top, at the bottom, or next to the footnotes list. The caret stays in the moved block.

## Footnotes

`FootnoteSync` in `editor.html` reorders the footnotes list to follow marker order after every document change, and `getFootnotes()` builds the meta from that list. Moving a paragraph with a footnote reference therefore reorders the notes with no new code; the tests below confirm it.

## Undo

A drop and a Move command are each one transaction. `FootnoteSync`'s appended transaction belongs to the same history event. One ⌘Z must put the block, and the notes order, back.

## Known cosmetic effect

ProseMirror redraws a moved node view from scratch. An embed's preview reloads, and per-view state that is not in the document resets. Nothing saved changes. This is accepted, not fixed.

## Testing

The move logic (find a top-level block's range, find a section's range, resolve the nearest top-level gap, apply the move) should be plain functions that take a ProseMirror state, so the Node suites can test them without a drag. The DOM wiring (hover tracking, grip position, drag events) stays thin.

### JS suites (new `Scripts/test-editor-block-move.js`, added to `test.sh`)

- Moving each modeled block keeps its saved HTML identical apart from position. Cover unsupported-block passthrough (byte-exact), synced pattern cards, Groups, Columns, galleries, embeds, tables and footnote references.
- Moving a paragraph with a footnote reference reorders `getFootnotes()` to match.
- Section ranges: H2 stops at the next H2 or H1, not at an H3; stops before the footnotes list; a heading inside a Group does not start one.
- Gap resolution: a drop position inside a column, quote, list or table cell resolves to a top-level gap; no gap after the footnotes list; dropping in place or inside the moved section is a no-op.
- One undo restores the document after a move, including the notes order.
- A move marks the post as edited (the content-change message reaches Swift).
- No grip and no move in code view, during a pending AI operation, or with an overlay open.
- The grip's `dragstart` leaves `dataTransfer` empty. jsdom has no `DataTransfer` or `DragEvent`, so the dragstart logic is a function that takes the event, and the test passes a stub whose `setData` / `clearData` are spies.

Update the counts in `docs/testing-plan.md`.

### Real WebKit

The `--check-fixtures` harness does not drive drags, so these go in `docs/testing-plan.md` §7 as manual steps:

- A grip drag moves a block; a ⇧ grip drag on a heading moves its section.
- A long post autoscrolls while dragging toward the top or bottom. `#editor-wrap` is the scroll container (`body` is `overflow: hidden`), and native drag autoscroll is not guaranteed inside it. **Check this first, before the rest of the build**: if it does not scroll, the drag needs its own autoscroll while the pointer is near the container's top or bottom edge.
- The §7 Finder image drops still upload.
- Dragging selected text within the post still works and still shows the normal drop cursor.
- The grip does not cover text at the narrowest window width.

## Docs to update

- `site/docs.html`: the grip, ⇧ for sections, and the two shortcuts in the Keyboard Shortcuts list under Editing.
- `docs/testing-plan.md`: the new suite and its count, the §7 steps above.
- `Sources/QuillKit/Resources/CLAUDE.md`: a gotcha entry for the empty-pasteboard rule, pointing at its test.
- `docs/platform-workarounds.md`: only if autoscroll or the drag preview needs a WebKit workaround.

## Still open

- **⌃⌘↑/↓** pending the clash check above.

## Left to the builder

- Where the move functions live and what they are named.
- How hover tracking finds the top-level block under the pointer (`posAtCoords` with a `requestAnimationFrame` throttle is the expected route).
- The narrow-window gutter approach, within the rules above.
