# Drag Blocks to Reorder Them — Implementation Plan

> **For agentic workers:** Ask Chris which execution method to use before starting: superpowers:executing-plans (one session does every task) or superpowers:subagent-driven-development (a fresh subagent per task). Do not pick one yourself. The recommendation from the planning session is **executing-plans**: the tasks chain through shared interfaces, Tasks 3 and 4 both build `block-grip.js`, and each depends on `editor.html` facts listed under "Start here" that a fresh subagent per task would have to rediscover, the likeliest cold-start failure being a subagent that edits the tiptap bundle to import `TextSelection` or `closeHistory`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every top-level block in the editor gets a type-marker grip in the left margin that drags the block (or, with ⇧ on a heading, its whole section) to a gap between top-level blocks, plus Move Block Up / Move Block Down commands.

**Architecture:** Pure move logic (`block-move.js`) works on ProseMirror documents by top-level child index and builds one transaction per move. A grip overlay (`block-grip.js`) lives outside the contenteditable, tracks hover, draws the marker, and starts drags by setting `view.dragging` with an empty pasteboard. A `BlockMove` Tiptap extension in `editor.html` owns `handleDrop` / drag-over for grip drags only; every other drag keeps ProseMirror's default path. Swift adds two Edit-menu commands that call `window.moveBlock(direction)`.

**Tech Stack:** Tiptap 2.x / ProseMirror inside WKWebView, plain classic scripts in `Sources/QuillKit/Resources/`, SwiftUI menu commands, `node --test` + jsdom suites.

**Spec:** `docs/superpowers/specs/2026-10-31-drag-to-reorder-blocks-design.md` — read it in full before Task 0. Issue: `cpoteet/Quill#23` (holds the WebKit pasteboard research).

---

## Start here (for a fresh session)

The design was settled in a separate session with Chris. Everything decided there is in the spec; this section lists what a cold start would otherwise get wrong.

**Branch:** `drag-to-reorder-blocks`. Work on this branch. If the spec, this plan or the mockup file below is missing from your checkout, they were left uncommitted in the main checkout at `/Users/Chris/Documents/Claude/WP Mac App`; stop and ask Chris rather than recreating them.

**Project rules that bind this work** (from `~/.claude/CLAUDE.md` and the repo `CLAUDE.md`):

- **Do not commit** unless Chris explicitly asks. Each task ends with a check-in, not a commit. When he asks to commit, first run `codex review --uncommitted -c model="gpt-6.1-sol" -c model_reasoning_effort="high"`, show the findings, verify each against the code, fix the ones that hold, say which you rejected and why, then commit.
- **Build after every code change** with exactly: `pkill -f "^$PWD/Quill.app/Contents/MacOS/Quill"; sleep 2 && ./build.sh 2>&1 && open Quill.app`. If the build fails, report the error instead of opening.
- **Tests:** `./test.sh` runs everything. A single suite: `node --test Scripts/<file>.js`. `node` and `jsdom` live in `Scripts/`, not the repo root.
- **Real WebKit:** `./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"` must pass before sign-off.
- **Computer-use testing** goes on a new local draft (click "+ New Post"), never a published post. Discard it when done. Read "Running the manual pass with an agent" in `docs/testing-plan.md` first.
- **Comments:** default to none; one line max; never narrate the change.
- **Check in with Chris** at the end of each task with a short summary of what changed.

**Facts established in the design session** (verified against the code on 2026-10-31):

- `editor.html` loads classic scripts in this order (lines ~1612–1617): `tiptap-bundle.js`, `marked-bundle.js`, `editor-transforms.js`, `block-parser.js`, `block-descriptors.js`, `block-settings.js`, then the inline script. `build.sh` rsyncs the whole Resources directory, so a new `.js` file there ships with no build change.
- **Gotcha:** a top-level `const` in a Resources JS file is not reachable as `window.x`; only `function` declarations are. Write both new files as `function` declarations only.
- **The bundle exports `Plugin` and `PluginKey`, but not `TextSelection`, `NodeSelection` or `closeHistory`.** Do not edit `Scripts/tiptap-bundle/entry.js` (the "new JS dependencies" gotcha). Set selections with `editor.commands.setTextSelection(pos)` / `setNodeSelection(pos)` after dispatching.
- **History grouping:** Tiptap's history merges a change into the previous undo step when it comes within 500 ms and is adjacent to the previous change. A move made straight after typing in the same block would merge into the typing. prosemirror-history's close key in this bundle is `new PluginKey("closeHistory")`, whose meta key string is `"closeHistory$"`; `tr.setMeta('closeHistory$', true)` starts a new undo step. It is needed on both sides of a move: on the move itself (so it does not join earlier typing) and on the selection change after it (so later typing does not join the move). Tasks 1 and 2 have tests for each side, so a bundle change that renames the key fails loudly.
- **Footnotes need no new code:** `FootnoteSync` (`editor.html` ~3563) reorders the footnotes list to marker order in an `appendTransaction` after every doc change, and `getFootnotes()` builds the meta from that list. When the footnotes list exists, it is always the last top-level child.
- **Trailing paragraph:** `TrailingParagraph` (~4090) appends an empty paragraph after a last block in `TRAILING_PARAGRAPH_AFTER` (`table`, `galleryBlock`, `embedBlock`, `gutenbergPassthrough`, `horizontalRule`), before the footnotes list if there is one, and `toWordPressHTML` strips it on save. This is why saved-HTML tests compare against a freshly loaded post in the target order, not against hand-written HTML. It also means a move must remove the generated paragraph when it moves the block that paragraph followed; otherwise the paragraph no longer follows a listed shape and is saved (Codex reproduced this: `<p>A</p><hr>` with the hr moved up saved `<hr><p>A</p><p></p>`).
- **Guards that exist already:** `codeViewActive` (a `let` in the inline script, ~6200; tests toggle code view by dispatching `click` on `#btn-code-view`), `_aiOperation()` (~6849, truthy while an AI rewrite is pending; `window.beginAIOperation()` starts one from a selection of 10+ characters), `_overlayOpen()` (~3691).
- **⌥ is ProseMirror's drag-copy modifier on macOS** (`dragCopyModifier` is `altKey` on Mac), which is why sections use ⇧.
- **Blocks already draggable by grabbing them:** `EmbedBlock` (~2275), `GalleryBlock` (~2382), `GutenbergPassthrough` (~3352), `InlineImage` (~4244) set `draggable: true`. Leave them exactly as they are. Embeds, galleries and passthrough cards also get a grip; inline images do not (they are inline).
- **Scroll container:** `#editor-wrap` (`overflow-y: auto; padding: 32px 24px`), and `body` is `overflow: hidden`. `.ProseMirror` is `max-width: 38.5em; margin: 0 auto`.
- **Tooltip style to reuse:** `#toolbar-tooltip` (~433–466).
- **Dark mode** is `body.dark` (`window.setDarkMode`), not a media query alone.
- **Swift wiring pattern:** `QuillApp.swift` `CommandGroup(after: .pasteboard)` holds Paste as Markdown and Find…, each setting an `@Published` trigger on `AppState` (~127); `PostEditorView.swift` (~414) observes it with `.onChange`, resets it, and calls `editorWebView?.evaluateJavaScript("openFindBar()")`.
- **Test suite pattern:** copy the `before()` block from `Scripts/test-editor-bridge.js` (jsdom with `runScripts: 'dangerously'`, `resources: 'usable'`, the `crypto` / `matchMedia` / `requestAnimationFrame` / `ResizeObserver` stubs, a `win.webkit.messageHandlers.contentChanged` stub collecting messages, and the poll for `win._tiptapEditor`). jsdom has no layout (every rect is zero) and no `DataTransfer` / `DragEvent`.
- **The mockup** Chris approved is `docs/superpowers/specs/2026-10-31-drag-to-reorder-blocks-mockups.html` (open it in a browser and pick "Type marker"; the companion-server script it references is absent, which is harmless). It shows the look only. Its drag is faked with `mousedown`/`mousemove` and `preventDefault()`; carry none of that code over, because the real grip must start a native drag (see Task 4).
- **`#editor-wrap` is not positioned** (no `position: relative`); it holds `#editor` and `#code-editor`. ProseMirror's Dropcursor places its element against `view.dom.offsetParent`, so making `#editor-wrap` positioned changes where Dropcursor measures from. Prefer a positioned overlay container of the grip's own inside `#editor-wrap`, sized to its scroll content; if you position `#editor-wrap` instead, check Dropcursor still lines up on a text drag.

## Global Constraints

- No new JS dependency and no change to `Scripts/tiptap-bundle/` or its lockfile.
- The grip and every visual affordance live outside the contenteditable and never reach `getHTML()`, `getContent()`, the word count or the selection.
- A grip `dragstart` leaves `dataTransfer` empty: it calls `clearData()` and never `setData`.
- Grip drops are handled entirely by Quill's `handleDrop` (returns `true`). Any drag the grip did not start is passed through untouched (`handleDrop` returns `false`, no drop line, Dropcursor as today).
- One move is one transaction and one undo step, and it marks the post as edited.
- Nothing can be dropped after the footnotes list; it has no grip.
- No grip and no moves while `codeViewActive`, while `_aiOperation()` is truthy, or while `_overlayOpen()`.
- Marker colours: glyph `#b4b4b4` light / `#636363` dark; hover glyph `#5f5f5f` / `#c4c4c4`; hit box 26 × 22 px; glyphs about 13 px; heading labels `font-variant-caps: all-small-caps`; never a monospace font.
- Drop line: 2 px, `var(--accent)`, column width. Section tint: accent at about 8% opacity.
- Menu titles: "Move Block Up", "Move Block Down" (Edit menu, after Find…). Shortcuts ⌃⌘↑ / ⌃⌘↓, subject to Task 0.
- Tooltip copy: "<Block name> · Drag to move"; on a top-level heading "Heading N · Drag to move, ⇧ for the section".

## Review Focus

1. **Moving a block straight after typing in it** — the move must be its own undo step; one ⌘Z undoes the move and leaves the typing. (Test in Task 1.)
2. **Moving the block that holds the caret, or a selected atom block** — after Move Up/Down the caret is at the same offset inside the moved block, or the atom stays node-selected; the editor keeps focus. (Test in Task 2.)
3. **A section whose heading is the last heading, with footnotes present** — the section ends before the footnotes list, never includes it, and the list stays last. (Test in Task 1.)
4. **Moving the last block when it is followed by the trailing empty paragraph** — the saved HTML matches a freshly loaded post in the new order; no stray empty paragraph is saved and none goes missing. (Test in Task 1.)
5. **A text drag or a Finder image drop while the grip is visible** — behaves exactly as today. (Test in Task 4 for `handleDrop` returning `false`; manual check in Task 6 for Finder.)

---

## File structure

| File | Status | Responsibility |
|---|---|---|
| `Sources/QuillKit/Resources/block-move.js` | Create | Pure functions on a ProseMirror doc/state: top-level indexes, sections, gaps, the move transaction, the marker for a node. No DOM. |
| `Sources/QuillKit/Resources/block-grip.js` | Create | The overlay: hover tracking, grip placement, marker rendering, tooltip, keypress hiding, click behaviour, drag start, drop line, section tint, drag card. Takes the editor and hooks; owns no document logic. |
| `Sources/QuillKit/Resources/editor.html` | Modify | `<script>` tags for both files; CSS for the grip, drop line, tint, card (in the existing `<style>` block, matching how the rest of the editor's CSS lives there); the `BlockMove` extension; `_blockMoveAllowed()`; `window.moveBlock`; Dropcursor class. |
| `Scripts/test-editor-block-move.js` | Create | The new jsdom suite. |
| `test.sh` | Modify | Register the suite. |
| `Sources/QuillKit/App/AppState.swift` | Modify | `triggerMoveBlockUp`, `triggerMoveBlockDown`. |
| `Sources/QuillKit/App/QuillApp.swift` | Modify | Two menu items. |
| `Sources/QuillKit/Views/Editor/PostEditorView.swift` | Modify | Two `.onChange` handlers. |
| `site/docs.html`, `docs/testing-plan.md`, `docs/editor-gotchas.md`, `Sources/QuillKit/Resources/CLAUDE.md`, the spec | Modify | Task 6. |

CSS stays inline in `editor.html` because every editor style already lives in that one `<style>` block and is loaded with the page; a separate stylesheet would be the only one. Say so to Chris when you check in after Task 3 (his global rule asks for a stated reason).

---

### Task 0: Preflight checks in real WebKit

Two facts decide parts of later tasks. Nothing is built here.

**Files:** the spec (record results).

- [ ] **Step 1: Build and open Quill** with the build command above. Create a new local draft, paste in about 60 paragraphs so the editor scrolls.
- [ ] **Step 2: Check native drag autoscroll.** Select a word near the bottom, drag it towards the top edge of the editor area and hold it there. Record whether `#editor-wrap` scrolls. ProseMirror text drags use the same native drag session a grip drag will, so this answers the spec's question without building the grip.
- [ ] **Step 3: Check ⌃⌘↑ / ⌃⌘↓.** In System Settings → Keyboard → Keyboard Shortcuts, confirm neither is assigned. In the draft, put the caret mid-paragraph and press each; record whether anything happens (it should not).
- [ ] **Step 4: Record both results** under "Still open" in the spec. If ⌃⌘↑/↓ is taken, stop and ask Chris for an alternative before Task 2. Discard the draft.
- [ ] **Step 5: Check in with Chris** with the two results.

---

### Task 1: Move logic and its tests

**Files:**
- Create: `Sources/QuillKit/Resources/block-move.js`
- Create: `Scripts/test-editor-block-move.js`
- Modify: `Sources/QuillKit/Resources/editor.html` (add `<script src="./block-move.js"></script>` after `block-settings.js`)
- Modify: `test.sh` (add `run "JS block move tests"  node --test Scripts/test-editor-block-move.js` after the container tests line)

**Interfaces:**
- Produces (all `function` declarations, global in the browser and in jsdom):
  - `movableCount(doc) -> number` — top-level child count, minus one when the last child is `footnotesList`. Gaps are numbered `0..movableCount(doc)`; gap `i` is before child `i`.
  - `topLevelIndexAt(doc, pos) -> number` — index of the top-level child containing `pos`, or `-1` if that child is the footnotes list.
  - `topLevelPos(doc, index) -> number` — document position where child `index` starts; `index === doc.childCount` gives `doc.content.size`.
  - `sectionEnd(doc, index) -> number` — exclusive end index. For a `heading` at `index`: the index of the next top-level `heading` with `level <=` its level, else `movableCount(doc)`. For anything else: `index + 1`.
  - `isNoOpMove(from, to, gap) -> boolean` — `gap >= from && gap <= to`.
  - `adjacentGap(doc, index, direction) -> number | null` — `direction` is `'up'` or `'down'`. Up: `index === 0 ? null : index - 1`. Down: `index + 1 >= movableCount(doc) ? null : index + 2`.
  - `generatedTrailingIndex(doc, trailingAfter: Set<string>) -> number` — the index of the empty paragraph `TrailingParagraph` generated, or `-1`: the last movable child, when it is an empty `paragraph` and the child before it has a type in `trailingAfter`.
  - `moveTopLevelBlocks(state, from, to, gap, trailingAfter: Set<string>) -> { tr, start } | null` — `editor.html` passes its `TRAILING_PARAGRAPH_AFTER`. Let `t = generatedTrailingIndex(doc, trailingAfter)`. Returns `null` when `isNoOpMove(from, to, gap)`, or when `t === to && gap === to + 1` (moving past only the generated paragraph). Otherwise one transaction: delete `topLevelPos(from)..topLevelPos(to)`, map `topLevelPos(gap)` through that step, insert the removed fragment there; then, if `t !== -1` and `t - 1` lies inside `from..to - 1` (the block it followed is being moved), delete that paragraph at its mapped position in the same transaction, because it would otherwise be saved as a real empty paragraph (`TrailingParagraph` re-adds one wherever the new last block needs it). Set `tr.setMeta('closeHistory$', true)` so the move does not merge into earlier typing. `start` is the position where the first moved block now begins.
  - `blockMarker(node) -> { kind: 'text' | 'glyph', value: string, label: string }` — the spec's marker table. `kind: 'text'` values: `¶`, `h1`…`h6`, `•`, `1.`, `“`, `”`, `{}`, `pre`, `—`. `kind: 'glyph'` values are glyph ids: `image`, `gallery`, `embed`, `table`, `columns`, `group`, `buttons`, `chevron`, `tabs`, `synced`, `html`. `label` is the tooltip's block name ("Paragraph", "Heading 2", "Bulleted list", "Numbered list", "Quote", "Pullquote", "Code", "Preformatted", "Separator", "Image", "Gallery", "Embed", "Table", "Columns", "Group", "Buttons", "Details", "Accordion", "Tabs", "Synced pattern", "Custom HTML", "Unsupported block"). Node names: `paragraph`, `heading`, `bulletList`, `orderedList`, `blockquote`, `pullquote`, `codeBlock`, `preformatted`, `horizontalRule`, `image`, `galleryBlock`, `embedBlock`, `table`, `columnsBlock`, `groupBlock`, `buttonsBlock`, `detailsBlock`, `accordionBlock`, `tabsBlock`, `gutenbergPassthrough`. For `gutenbergPassthrough`, read its attrs to tell a synced pattern (`wp:block` source), Custom HTML (`wp:html` source) and any other unsupported block apart — inspect the node's attrs in `editor.html` (~3352) and the synced pattern code (~2549) to find the field.

- [ ] **Step 1: Write the failing tests** in `Scripts/test-editor-block-move.js` (suite setup copied from `test-editor-bridge.js`):

```js
describe('top-level ranges', () => {
  test('movableCount excludes a trailing footnotes list')            // load a post with one footnote; assert movableCount === childCount - 1
  test('topLevelIndexAt returns -1 inside the footnotes list')
  test('sectionEnd: an H2 stops at the next H2 or H1, not at an H3') // H2 p H3 p H2 p → sectionEnd(0) === 4
  test('sectionEnd: the last H2 stops before the footnotes list')
  test('sectionEnd: a heading inside a Group does not start a section') // the Group's index gives index + 1
  test('sectionEnd: a non-heading is one block')
  test('isNoOpMove: gaps from..to inclusive are no-ops')
  test('adjacentGap: null at the top, null at the bottom, null next to the footnotes list')
})

describe('a move saves exactly what loading the post in that order saves', () => {
  // For each sample X: load `<p>A</p>` + X + `<p>B</p>`, move X to after B,
  // then assert win.getContent() === getContent() of a fresh load of `<p>A</p><p>B</p>` + X.
  // Samples: paragraph, H2, bulleted list, numbered list (start=3), quote, pullquote,
  // code, preformatted, separator, image with caption and alignment, gallery, embed,
  // table, columns, group, buttons, details, accordion, tabs, synced pattern card,
  // Custom HTML card, an unsupported block (byte-exact source with single-quoted attrs and <br/>).
  // Take the markup for each from the existing suites (test-editor-containers.js,
  // test-editor-gallery.js, test-editor-passthrough.js) rather than writing new fixtures.
})

describe('footnotes and undo', () => {
  test('moving a paragraph with a footnote reference reorders getFootnotes()') // two notes, move the second paragraph above the first, assert JSON order flips
  test('one undo restores the document and the notes order')
  test('a move straight after typing in the same block is its own undo step')  // insertContent 'x', move immediately, undo once → 'x' still there, order restored
  test('moving a final separator up does not leave a saved empty paragraph') // load <p>A</p><hr>, move the hr to gap 0, getContent() === fresh load of <hr><p>A</p>
  test('moving a final table down past only its generated paragraph is a no-op') // returns null
  test('generatedTrailingIndex finds the generated paragraph before a footnotes list')
  test('an author\'s empty paragraph after a plain paragraph is not treated as generated')
  test('the footnotes list stays the last child after any move')
  test('a no-op move returns null and adds no undo step')
})

describe('blockMarker', () => {
  test('maps every top-level node type to the spec marker')         // table-driven over the samples above
  test('headings use h1..h6 and a "Heading N" label')
  test('tells synced pattern, Custom HTML and unsupported cards apart')
})
```

Each `test(...)` above is a real test with the assertion its comment states.

- [ ] **Step 2: Run** `node --test Scripts/test-editor-block-move.js`. Expected: FAIL, `movableCount is not defined`.
- [ ] **Step 3: Implement** `block-move.js` with the interfaces above, and add the `<script>` tag and the `test.sh` line.
- [ ] **Step 4: Run** the suite. Expected: PASS. Then `./test.sh`. Expected: all suites pass.
- [ ] **Step 5: Build** with the build command (the app must still load). **Check in with Chris.**

---

### Task 2: Move Block Up / Move Block Down

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`
- Modify: `Sources/QuillKit/App/AppState.swift`, `Sources/QuillKit/App/QuillApp.swift`, `Sources/QuillKit/Views/Editor/PostEditorView.swift`
- Test: `Scripts/test-editor-block-move.js`

**Interfaces:**
- Consumes: `topLevelIndexAt`, `adjacentGap`, `moveTopLevelBlocks` (Task 1).
- Produces:
  - `_blockMoveAllowed() -> boolean` in `editor.html`: `!codeViewActive && !_aiOperation() && !_overlayOpen()`.
  - `_selectAfterMove(start: number, offset: number | null) -> void` in `editor.html` — sets the selection after a move: a text selection at `start + offset` when `offset` is a number, otherwise a node selection at `start` for an atom block or a text selection at the block's start for a text block. It runs as one chain that also sets `closeHistory$` (the same `chain().command(({ tr }) => { tr.setMeta(...); return true })` shape `acceptAIResult` uses), so typing straight after a move starts a new undo step: a step-less transaction carrying that meta resets prosemirror-history's grouping. Task 4's drop uses it too.
  - `window.moveBlock(direction: 'up' | 'down') -> boolean` — moves the top-level block holding the selection (or the node-selected top-level block) one place; returns `false` and does nothing when not allowed, at an end, or inside the footnotes list. Dispatches the move, then calls `_selectAfterMove` with the caret's old offset from the block's start (or `null` for a node selection); keeps focus.
  - `AppState.triggerMoveBlockUp: Bool`, `AppState.triggerMoveBlockDown: Bool`.

- [ ] **Step 1: Write the failing tests:**

```js
describe('moveBlock', () => {
  test('moves the caret block up one place and keeps the caret offset')
  test('moves a node-selected embed down and keeps it node-selected')
  test('moves a whole Group past its neighbour as one unit')
  test('does nothing at the top, at the bottom, or above the footnotes list')
  test('does nothing in code view')            // click #btn-code-view first
  test('does nothing while an AI operation is pending') // select 10+ chars, win.beginAIOperation()
  test('does nothing while the find bar is open')       // win.openFindBar()
  test('a move sends contentChanged to Swift')          // the stub collected a message after the move
  test('typing straight after a move is its own undo step') // move A below B, insertContent 'x' at once, undo once → 'x' gone, order still moved
})
```

- [ ] **Step 2: Run** the suite. Expected: FAIL, `win.moveBlock is not a function`.
- [ ] **Step 3: Implement** `_blockMoveAllowed` and `window.moveBlock` in `editor.html`.
- [ ] **Step 4: Run** the suite. Expected: PASS.
- [ ] **Step 5: Add the Swift side.** In `QuillApp.swift`, inside the existing `CommandGroup(after: .pasteboard)` after Find…, add "Move Block Up" (`.keyboardShortcut(.upArrow, modifiers: [.command, .control])`) and "Move Block Down" (`.downArrow`), each setting its `AppState` trigger. In `PostEditorView.swift`, next to the `triggerFindBar` handler, add two `.onChange` handlers that reset the trigger and call `editorWebView?.evaluateJavaScript("moveBlock('up')")` / `('down')`.
- [ ] **Step 6: Build, then check by hand** in a new local draft: ⌃⌘↑/↓ move a paragraph, a Group and an image; ⌘Z undoes each move in one step. Run `swift test` (via `./test.sh`). **Check in with Chris.**

---

### Task 3: The grip overlay (hover, marker, tooltip, click)

**Files:**
- Create: `Sources/QuillKit/Resources/block-grip.js`
- Modify: `Sources/QuillKit/Resources/editor.html` (script tag after `block-move.js`; CSS; call `installBlockGrip` once the editor exists, next to `window._tiptapEditor = editor` ~4582)
- Test: `Scripts/test-editor-block-move.js`

**Interfaces:**
- Consumes: `topLevelIndexAt`, `topLevelPos`, `sectionEnd`, `blockMarker` (Task 1); `_blockMoveAllowed` (Task 2).
- Produces:
  - `installBlockGrip(editor, hooks) -> { el: HTMLElement, hide(): void, showFor(index: number): void, click(): void, setShift(down: boolean): void }` (`showFor`, `click` and `setShift` are what the real event handlers call, exposed so the jsdom tests can drive them without coordinates) where `hooks = { allowed: () => boolean, onDragStart(event, range), onDragEnd() }` (the drag hooks are filled in by Task 4; Task 3 passes no-ops).
  - The grip element `#block-grip`, appended to `#editor-wrap` (not inside `.ProseMirror`), `aria-hidden="true"`, not focusable.
  - `blockGlyphSVG(id) -> string` in `block-grip.js` — the inline SVG for each glyph id from `blockMarker`, stroke `currentColor`, about 1.3 px stroke at 13 px.

Behaviour (all from the spec's "The grip: a type marker"):
- Hover tracking on `#editor-wrap` `mousemove`, throttled with `requestAnimationFrame`; the hovered block is the top-level child under the pointer's y, with the whole row, margin included, counting as the block. Use `view.posAtCoords` at the column's horizontal centre, then `topLevelIndexAt`.
- Vertical placement: centred on the first line (computed `line-height`) for text blocks; top edge for media and cards. Horizontal: the column's left edge minus the grip width minus 6 px. For floated images, use the column's edge, not the image box.
- If the gap to the left of the column is narrower than the grip, give `.ProseMirror` a left gutter at that width (a `@media`/container rule) rather than letting the grip cover text. Pick the breakpoint by measuring at Quill's narrowest window with the sidebar and inspector open.
- Hide on any `keydown` in the editor; show again on the next `mousemove`. Hide on scroll until the next `mousemove`. Hide when `hooks.allowed()` is false.
- Tooltip after about 600 ms of hovering the grip, in `#toolbar-tooltip`'s style, with the copy from Global Constraints.
- Click on the grip: text blocks (`paragraph`, `heading`, `bulletList`, `orderedList`) get `setTextSelection` at the block's start; any other block gets `setNodeSelection` at `topLevelPos`. Focus the editor.
- No grip for the footnotes list.

- [ ] **Step 1: Write the failing tests** (jsdom has no layout, so these test structure and state, not position):

```js
describe('grip overlay', () => {
  test('#block-grip exists outside .ProseMirror and is aria-hidden')
  test('getContent() never contains block-grip markup after hovering')     // showFor(0), then getContent(); jsdom has no elementFromPoint, so a synthetic mousemove would test nothing
  test('blockGlyphSVG returns an <svg> for every glyph id blockMarker can return')
  test('the grip hides on keydown')
  test('the grip stays hidden in code view, during an AI operation, and with the find bar open')
  test('clicking the grip on a paragraph puts the caret at its start')     // call the click handler directly with the paragraph's index
  test('clicking the grip on an embed node-selects it')
})
```

Drive these through `showFor(index)` and `click()` on the object `installBlockGrip` returns, not through synthesised coordinates jsdom cannot resolve.

- [ ] **Step 2: Run** the suite. Expected: FAIL.
- [ ] **Step 3: Implement** `block-grip.js`, its CSS in `editor.html` (light and `body.dark` colours from Global Constraints), and the `installBlockGrip` call.
- [ ] **Step 4: Run** the suite, then `./test.sh`. Expected: PASS.
- [ ] **Step 5: Build and look** in a new local draft, in light and dark: each block type shows its marker at the right height, the tooltip copy is right, typing hides the grip, and the grip never covers text at the narrowest window. Take screenshots for Chris. **Check in with Chris**, including the reason the CSS stayed inline. He has not seen the drawn glyphs yet; ask for his reaction to them.

---

### Task 4: Dragging, dropping, sections

**Files:**
- Modify: `Sources/QuillKit/Resources/block-grip.js`, `Sources/QuillKit/Resources/editor.html`
- Test: `Scripts/test-editor-block-move.js`

**Interfaces:**
- Consumes: `movableCount`, `sectionEnd`, `isNoOpMove`, `moveTopLevelBlocks`, `blockMarker` (Task 1); `installBlockGrip` (Task 3).
- Produces:
  - `gripDragStart(view, event, range) -> void` in `block-grip.js` — `range = { from, to }` (top-level indexes). Calls `event.dataTransfer.clearData()`, never `setData`; sets `view.dragging = { slice, move: true }` with the slice of that range; calls `event.dataTransfer.setDragImage(card, 12, 12)` with the drag card; marks the drag as a grip drag (module state that `handleDrop` reads).
  - `nearestGap(gapYs: number[], y: number) -> number` — index of the closest gap y. Pure.
  - `gapYs(view) -> number[]` — the y of gaps `0..movableCount`, each midway between neighbouring top-level DOM blocks (from `view.nodeDOM(topLevelPos(i))`), with gap 0 just above the first block and the last gap just below the last movable block.
  - `BlockMove` Tiptap extension in `editor.html` with one plugin whose props are:
    - `handleDrop(view, event)` — if the current drag is not a grip drag, return `false`. Otherwise compute the gap with `nearestGap(gapYs(view), event.clientY)`, dispatch `moveTopLevelBlocks` (nothing for a no-op), call `_selectAfterMove(start, null)`, clear the grip-drag state, return `true`.
    - `handleDOMEvents.dragover` / `dragleave` / `dragend` — for a grip drag only: draw or hide the drop line at the chosen gap (hidden for no-op gaps) and keep `body.block-dragging` set; return `false` so other handlers still run.
  - **Margin drops.** ProseMirror's `dragover`/`drop` handlers and the plugin props above are attached to `view.dom`, but the grip sits in the margin outside it, and a grip drag can be released over `#editor-wrap`'s padding. Nothing there calls `preventDefault()` on `dragover`, so such a drop would silently cancel. Add `dragover` (calling `preventDefault()`) and `drop` listeners on `#editor-wrap` that act only for grip drags and use the same `nearestGap` + `moveTopLevelBlocks` path as `handleDrop`; make sure a drop inside `view.dom` is handled once, not by both.
  - StarterKit's Dropcursor configured with `dropcursor: { class: 'quill-dropcursor' }` in the existing `StarterKit...configure({...})` (~4385), and CSS `body.block-dragging .quill-dropcursor { display: none }`.

Behaviour:
- The grip element is `draggable="true"` and starts a real native drag through `dragstart`; do not call `preventDefault()` on its `mousedown`. A native drag session is what makes the empty pasteboard and `view.dragging` work.
- `handleDrop` ignores its `slice` argument: by then ProseMirror has cleared `view.dragging` and run the paste transforms over the slice. Rebuild the move from the index range recorded at `dragstart`.
- The drag card must be laid out when `setDragImage` is called: position it off-screen, never `display: none`.
- ⇧ held while the pointer is on a heading's grip: `sectionEnd` gives the range; the marker turns accent and an accent tint covers the section (top of the heading to the bottom of the last block, column width plus 8 px each side). Releasing ⇧ removes both. ⇧ on any other grip changes nothing. The range is read at `mousedown` / `dragstart`, so letting go of ⇧ mid-drag does not change what moves.
- During a drag, the source blocks get `opacity: 0.32` through a class on their DOM nodes (a decoration is better if it is simple; never a document change).
- The drag card: the marker plus the first block's text (or its label for media), cut off at 280 px wide, plus "+ N more" for a section. Built off-screen in the overlay, not in the document.

- [ ] **Step 1: Write the failing tests:**

```js
describe('grip drag', () => {
  test('gripDragStart clears the pasteboard and never sets data')       // stub { clearData: spy, setData: spy, setDragImage: spy }
  test('gripDragStart sets view.dragging with move: true and the block slice')
  test('gripDragStart with a section range carries every block in the section')
  test('handleDrop returns false for a drag the grip did not start')      // call the plugin prop directly
  test('handleDrop for a grip drag moves the block and returns true')     // stub gapYs or pass a clientY that nearestGap maps to a known gap
  test('a grip drop on a no-op gap changes nothing and adds no undo step')
  test('nearestGap picks the closest gap, ties go to the earlier one')
})
```

- [ ] **Step 2: Run** the suite. Expected: FAIL.
- [ ] **Step 3: Implement** the drag start, gap logic, `BlockMove` extension, Dropcursor class, drop line, section tint and drag card.
- [ ] **Step 4: Run** the suite, then `./test.sh`. Expected: PASS.
- [ ] **Step 5: Build and check by hand** in a new local draft: drag a paragraph, an image, a Group and an embed by their grips; drop over a column, a quote, a list and a table and confirm the block lands in the nearest top-level gap; release a drag with the pointer in the left margin and confirm it still drops; ⇧-drag an H2 section; confirm the amber line, the card and the dimmed source; confirm a text drag still shows the ordinary drop cursor; grab an embed itself (not its grip) and drop it inside a column to confirm today's behaviour is unchanged. **Check in with Chris.**

---

### Task 5: Autoscroll (only if Task 0 found none)

Skip this task, and say so, if Task 0 recorded that `#editor-wrap` scrolls during a native drag.

**Files:** `Sources/QuillKit/Resources/block-grip.js`, `docs/platform-workarounds.md`

- [ ] **Step 1: Implement** scrolling during a grip drag: on `dragover`, when the pointer is within 48 px of `#editor-wrap`'s top or bottom edge, scroll by a speed proportional to the distance into that band (up to about 18 px per frame), driven by `requestAnimationFrame`, stopping on `dragend` / `drop` / leaving the band.
- [ ] **Step 2: Add an entry** to `docs/platform-workarounds.md` in its existing format: what WebKit does not do, the workaround, and the Task 0 check as the test for whether it is still needed.
- [ ] **Step 3: Build and check** in a 60-paragraph draft: drag the last paragraph's grip to the top. **Check in with Chris.**

---

### Task 6: Docs, counts and release checks

**Files:** `site/docs.html`, `docs/testing-plan.md`, `docs/editor-gotchas.md`, `Sources/QuillKit/Resources/CLAUDE.md`, the spec.

- [ ] **Step 1: `site/docs.html`:** in the editing section, describe the type marker, dragging, ⇧ for a section, and that a block lands between blocks (not inside a column). In the Keyboard Shortcuts list under "Editing", add `⌃⌘↑` Move the block up and `⌃⌘↓` Move the block down, in the existing `docs-keys__row` markup. Plain language, no mannered prose.
- [ ] **Step 2: `docs/testing-plan.md`:**
  - Add the suite to the numbered list under "Full suite" and a `## JS block move tests (N tests)` section listing every test by name, in the style of the neighbouring suites. Use the count `node --test` reports.
  - Add §7 manual steps (under 7.3 Editor) for: grip drag of a block; ⇧ section drag; a long post scrolling during a drag; the §7 Finder image drops still uploading; a text drag still working with the normal drop cursor; the grip not covering text at the narrowest window; dragging an embed by itself still working as before.
- [ ] **Step 3: Gotcha.** Add an entry to `docs/editor-gotchas.md`: "A grip drag must leave the pasteboard empty" — `DroppableWebView` takes over any drag whose pasteboard holds image file URLs, and an HTML pasteboard would send the slice through serialization and parsing, losing byte-exact passthrough source and replaying carried attributes onto the live page; the test that guards it is `gripDragStart clears the pasteboard and never sets data`. Index its title in `Sources/QuillKit/Resources/CLAUDE.md` the way the other `editor.html` gotchas are indexed.
- [ ] **Step 4: Spec.** Under "Still open", replace the ⌃⌘↑/↓ line with the Task 0 result.
- [ ] **Step 5: Verify.** Run `./test.sh` (all pass), the build command, then `./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"` (passes). Walk the new §7 steps in a new local draft and discard it.
- [ ] **Step 6: Check in with Chris** with a summary of the whole branch, the test counts, and anything that did not go to plan. Do not commit until he asks; then follow the Codex review rule above.
