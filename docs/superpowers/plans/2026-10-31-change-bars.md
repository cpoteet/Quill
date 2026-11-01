# Change Bars — Implementation Plan

> **For agentic workers:** Ask Chris which execution method to use before starting: superpowers:executing-plans (one session does every task) or superpowers:subagent-driven-development (a fresh subagent per task). Do not pick one yourself. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A thin grey bar in the editor's right margin beside each top-level block that differs from the saved version, and a dot where a block was deleted.

**Architecture:** Swift sends the saved body (`cleanContent`, `cleanFootnotes`) to the editor as a baseline. `editor.html` turns it into the document the live editor would hold after loading it. A pure function in a new `change-bars.js` matches the baseline's top-level nodes against the current document. An overlay, also in `change-bars.js`, draws the marks outside the contenteditable, following the grip's rule: hidden on a keypress, shown again when the mouse moves.

**Tech Stack:** Tiptap 2.x / ProseMirror in WKWebView, classic scripts in `Sources/QuillKit/Resources/`, SwiftUI (`EditorView`, `EditorCoordinator`, `PostEditorView`), `node --test` + jsdom.

**Spec:** `docs/superpowers/specs/2026-10-31-change-bars-design.md`. Read it in full before Task 1. Mockup: `docs/superpowers/specs/2026-10-31-change-bars-mockups.html` (look only, not code to copy).

## Start here (for a fresh session)

**Project rules** (`~/.claude/CLAUDE.md`, repo `CLAUDE.md`):

- Work on `main`. **Do not commit** unless Chris asks. Each task ends with a check-in, not a commit. When he asks to commit: run `codex review --uncommitted -c model="gpt-6.1-sol" -c model_reasoning_effort="high"`, show the findings, check each against the code, fix the ones that hold, say which you rejected and why, then commit.
- Build after every code change with exactly `pkill -f "^$PWD/Quill.app/Contents/MacOS/Quill"; sleep 2 && ./build.sh 2>&1 && open Quill.app`. If the build fails, report the error instead of opening.
- `./test.sh` runs everything; one suite: `node --test Scripts/<file>.js`. `node` and `jsdom` live in `Scripts/`.
- Real WebKit: `./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"` before sign-off.
- Computer-use testing on a new local draft only, discarded afterwards. Read "Running the manual pass with an agent" in `docs/testing-plan.md` first.
- Comments: default none, one line max, never narrate the change.

**Facts verified on 2026-10-31:**

- **A top-level `const` in a Resources JS file is not on `window`;** only `function` declarations are. Write `change-bars.js` as `function` declarations.
- **The bundle exports no `DOMParser`, `DOMSerializer`, `Fragment` or `EditorState`.** Do not edit `Scripts/tiptap-bundle/entry.js`. Reach them through the live editor: `editor.schema.cached.domParser` and `editor.schema.cached.domSerializer` (ProseMirror caches each the first time it is built; `setContent` and `getHTML` build them), `doc.content.constructor` (`Fragment`) and `editor.state.constructor` (`EditorState`, with its static `create`).
- **Tiptap's `elementFromString`** (minified as `xr` in `tiptap-bundle.js`) wraps the HTML in `<body>`, parses it with `DOMParser`, then removes whitespace-only text nodes matching `/^(\n\s\s|\n)$/` (`Hc`). The baseline must do the same, or galleries' `sourceHTML` differs (found by the Codex review, 2026-10-31).
- **How `window.setContent` (~6622) prepares content:** `_wrapIncoming(inlineFootnotes(html, storedFootnotes))`, where `_wrapIncoming` (~6575) is a `const` arrow inside the inline script calling `wrapUnsupportedBlocks(html, parseBlocks)`. Tiptap then parses with `parseOptions: { preserveWhitespace: false }` (~6960) from a body made by `new DOMParser().parseFromString('<body>' + html + '</body>', 'text/html')`, which is inert.
- **Plugins that change a freshly loaded doc:** `FootnoteSync` (~3641, runs only when `transactions.some(tr => tr.docChanged)`) and `TrailingParagraph` (~4234), both through `appendTransaction`. `window.setSyncedPattern` (~2752) re-renders node views and dispatches nothing.
- **The grip's hide rule** (`block-grip.js` ~409, ~478): `mousemove` on `#editor-wrap` with no buttons shows it. A capture-phase `keydown` on `document` hides it unless the key is `Meta`, `Shift`, `Alt`, `Control` or `CapsLock`. `view.dom` `mousedown` and `#editor-wrap` `scroll` also hide it.
- **Gutter clicks:** the `mousedown` handler on `#editor-wrap` (~6321) returns early unless `e.target` is the wrap itself or the editor element. Anything in the margin that takes the pointer breaks it.
- **Grip drag state:** `activeGripDrag()` in `block-grip.js` is truthy during a grip drag; `endGripDrag` clears it.
- **Guards:** `codeViewActive` (~6436), `_overlayOpen()` (~3769).
- **Grip tooltip:** `#block-grip-tooltip` with `showTip`/`hideTip` in `block-grip.js` (~300–320). Its CSS is in `editor.html` beside the grip's.
- **Swift push path:** `EditorView.updateNSView` calls `coordinator.setContent(html, footnotes:)`. `EditorCoordinator.setContent` (~493) dedupes with `EditorPushState`, queues while not ready (`pendingHTML`), and calls `setContent(...)` in JS. `evaluateJavaScript` calls run in the order they are made.
- **Swift baseline state:** `PostEditorView` holds `cleanContent`, `cleanFootnotes` and the private `bodyIsDirty`. They are set on load (~885), in `applyRemotePost` (~912; Revert and `reloadIfClean` both go through it), after Save Locally (~1018) and after a remote save (~1158). On stash restore (~855) `cleanContent` stays the server's content while `htmlContent` takes the stash. That is the behaviour the spec relies on, so it needs no change.
- **Test suite setup:** copy the `before()` block from `Scripts/test-editor-block-move.js` (jsdom, stubs, `win._tiptapEditor` poll). jsdom has no layout, so test the comparison and the gating, not pixel positions.

## Global Constraints

- Bar: 2px wide, 1px radius, full block height, 8px right of `.ProseMirror`'s right edge. Grey `rgba(0,0,0,0.17)` light, `rgba(255,255,255,0.2)` dark (`body.dark`).
- Deletion dot: 6px, same grey, same column, centred in the gap. One dot per gap.
- Tooltip copy: "Changed since the last save" (bar), "Removed since the last save" (dot). Hover area 12px wide.
- Marks have `pointer-events: none` and `aria-hidden="true"`, and live outside the contenteditable.
- Fade out about 0.12s, in about 0.35s.
- No marks when `codeViewActive`, `_overlayOpen()`, `activeGripDrag()`, or Swift reports the body clean.
- No new JS dependency; no change to `Scripts/tiptap-bundle/`.

## Review Focus

1. **Typing straight after a save in a post with images, galleries or accordions:** no bars on untouched blocks. Their nodes reparse with different attributes, which is why the keys are saved HTML. (Task 1's "after a save" test.)
2. **A brand-new empty local draft:** the first paragraph typed gets a bar. (Task 4's `firstEmptyBaselineIsSent`.)
3. **Reopening a post with restored unsaved changes:** bars on exactly the restored blocks. (Task 2 test: `setContent(stash)` then `setChangeBaseline(server)`.)
4. **Clicking in the right margin beside a changed block:** the caret lands on that line. (Task 3 test: the mark element's computed `pointer-events` is `none`; manual step in Task 5.)
5. **Saving while still typing:** the bars recompute against the new baseline with no flash of stale bars. (Task 2 test: two `setChangeBaseline` calls in a row leave only the second's result.)

---

## File structure

| File | Status | Responsibility |
|---|---|---|
| `Sources/QuillKit/Resources/change-bars.js` | Create | `changedBlocks` (pure), `installChangeBars` (overlay, tooltip, show/hide). |
| `Sources/QuillKit/Resources/block-grip.js` | Modify | Export `isGripHidingKey(event)` so both overlays hide on the same keys. |
| `Sources/QuillKit/Resources/editor.html` | Modify | `<script>` tag; CSS; `_buildChangeBaseline`; `window.setChangeBaseline`; `window.setBodyDirty`; install call. |
| `Scripts/test-editor-change-bars.js` | Create | jsdom suite. |
| `Scripts/fixtures/` | Modify | Add footnotes-out-of-order and synced-pattern fixtures if absent. |
| `test.sh` | Modify | Register the suite. |
| `Sources/QuillKit/Views/Editor/EditorCoordinator.swift` | Modify | `setChangeBaseline`, `setBodyDirty`, deduped and queued until ready. |
| `Sources/QuillKit/Views/Editor/EditorView.swift` | Modify | `baselineHTML`, `baselineFootnotes`, `bodyDirty` parameters. |
| `Sources/QuillKit/Views/Editor/PostEditorView.swift` | Modify | Pass `cleanContent`, `cleanFootnotes`, `bodyIsDirty`. |
| `Tests/QuillTests/EditorCoordinatorTests.swift` | Modify | JS-string and dedupe tests. |
| Docs | Modify | Task 5. |

CSS goes in `editor.html`'s existing `<style>` block, beside the grip's, because every editor style lives there. Tell Chris this when you check in after Task 3, since his global rule asks for a stated reason.

---

### Task 1: Baseline document and the comparison (the gate)

The spec says to check this first. If the equality tests fail on any fixture, stop and bring the failure to Chris before Task 2.

**Files:**
- Create: `Sources/QuillKit/Resources/change-bars.js`
- Create: `Scripts/test-editor-change-bars.js`
- Modify: `Sources/QuillKit/Resources/editor.html` (add `<script src="./change-bars.js"></script>` after `block-grip.js`; add `_buildChangeBaseline` in the inline script near `window.setContent`)
- Modify: `test.sh` (add `run "JS change bar tests"  node --test Scripts/test-editor-change-bars.js` after the block move line)
- Modify: `Scripts/fixtures/` (only if no existing fixture has footnotes stored out of marker order, or a `wp:block` synced pattern)

**Interfaces:**
- Produces:
  - `_buildChangeBaseline(html: string, footnotesJSON: string) -> Node` (inline script, exposed for tests as `window._buildChangeBaseline`). Prepares the HTML exactly as `setContent` does. Then it parses the way Tiptap's `elementFromString` does: `new DOMParser().parseFromString('<body>' + html + '</body>', 'text/html').body`, then recursively remove text nodes matching `/^(\n\s\s|\n)$/` (Tiptap's `removeWhitespaces`, minified as `Hc` in the bundle), then `editor.schema.cached.domParser.parse(body, { preserveWhitespace: false })`. Then it builds `editor.state.constructor.create({ schema: editor.schema, plugins: editor.state.plugins })`, applies a transaction that replaces the whole doc with the parsed content through `state.applyTransaction(tr)` (so `appendTransaction` plugins run), and returns the resulting `state.doc`. Throws if `editor.schema.cached.domParser` is missing.
  - `_blockKey(node: Node) -> string` (inline script, passed to `changedBlocks`). The node's saved Gutenberg HTML, serialized on its own: `editor.schema.cached.domSerializer.serializeFragment(doc.content.constructor.from(node), { document: inertDocument() })`, put in an `inertDocument()` container, its `innerHTML` run through `toWordPressHTML` and `extractFootnotes(...).content`. For `footnotesList`, `JSON.stringify(node.toJSON())`. Cache in a `WeakMap` keyed by node. Throws if `editor.schema.cached.domSerializer` is missing.
  - `changedBlocks(baseline: Node, current: Node, trailingAfter: Set<string>, keyOf: (Node) => string) -> { changed: number[], removedGaps: number[] }` in `change-bars.js`. Indexes are top-level child indexes of `current`; gap `i` is before child `i`. On both sides, ignore an empty `paragraph` that `generatedTrailingIndex(doc, trailingAfter)` (from `block-move.js`) reports. `editor.html` passes `TRAILING_PARAGRAPH_AFTER` and `_blockKey`. Algorithm: an LCS over top-level nodes comparing `keyOf(node)`, not `node.eq`. The spec explains why: after a save, images, galleries and accordions reparse with different attributes but identical saved HTML. Between consecutive matches, unmatched current nodes go to `changed`; if the current run is empty and the baseline run is not, the gap goes to `removedGaps`.

- [ ] **Step 1: Write the failing tests**

```js
describe('baseline equals the loaded document', () => {
  // For every .html file in Scripts/fixtures (recursively, skipping README and the paste/ai/evaluate subfolders
  // whose files are not posts): setContent(html, footnotes); assert changedBlocks(_buildChangeBaseline(html, footnotes), doc)
  // returns { changed: [], removedGaps: [] }.
  test('every post fixture')
  test('after a save, only the edited block is marked')  // per fixture, no reload: append '<p>Z</p>' at the end; out = getContent(); baseline = _buildChangeBaseline(out, getFootnotes()); edit the first paragraph (or append again); changedBlocks marks only that block. Without reloading is the point: the editor keeps the pre-save doc.
  test('accordion, gallery and post-17780 pass the save test') // the three fixtures whose nodes reparse with different attrs
  test('footnotes stored out of marker order')                          // FootnoteSync reorders on load; still no marks
  test('a synced pattern')
})

describe('changedBlocks', () => {
  test('editing a paragraph: one bar, no dot')                    // <p>A</p><p>B</p><p>C</p>, edit B → { changed: [1], removedGaps: [] }
  test('inserting at the top marks only the new block')           // → changed [0]
  test('deleting a block leaves a dot and no bars')               // delete B → { changed: [], removedGaps: [1] }
  test('deleting two adjacent blocks leaves one dot')
  test('a moved block: a bar at the new place, a dot at the old')
  test('undo back to the original: no marks')
  test('a change inside a Group marks the Group')
  test('editing a footnote marks the footnotes list')
  test('the generated trailing paragraph is never marked')        // <p>A</p><hr>, edit A → changed [0] only
})
```

- [ ] **Step 2: Run** `node --test Scripts/test-editor-change-bars.js`. Expected: FAIL, `_buildChangeBaseline` / `changedBlocks` not defined.
- [ ] **Step 3: Implement** `_buildChangeBaseline` and `changedBlocks` as specified above. Add the two fixtures if they are missing, each with a README line as the other fixtures have.
- [ ] **Step 4: Run** the suite, then `./test.sh`. Expected: all PASS. If a "baseline equals" test fails, find which attribute differs (log both nodes' `toJSON()`), and stop and report to Chris if the cause is in parsing rather than in this code.
- [ ] **Step 5: Check in with Chris** with the result of the gate.

---

### Task 2: Bridge functions and gating

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`
- Modify: `Scripts/test-editor-change-bars.js`

**Interfaces:**
- Consumes: `_buildChangeBaseline`, `changedBlocks` (Task 1).
- Produces:
  - `window.setChangeBaseline(html: string, footnotesJSON: string)`. Stores the baseline doc and recomputes.
  - `window.setBodyDirty(dirty: boolean)`.
  - `window._changeMarks() -> { changed: number[], removedGaps: number[] }`: the marks that would show right now, gating included. For tests, and for Task 3's overlay to read.
  - Gating inside `_changeMarks`: empty when there is no baseline, when `setBodyDirty(false)` is in effect, when `codeViewActive`, `_overlayOpen()`, or `activeGripDrag()`.

- [ ] **Step 1: Write the failing tests**

```js
describe('bridge', () => {
  test('restored unsaved changes are marked')        // setContent('<p>A</p><p>B2</p>'); setChangeBaseline('<p>A</p><p>B</p>', '[]'); setBodyDirty(true) → changed [1]
  test('no marks while the body is clean')           // same, then setBodyDirty(false) → empty
  test('no marks before any baseline arrives')
  test('a second baseline replaces the first')       // two calls in a row; result reflects only the second
  test('no marks in code view')                      // click #btn-code-view
  test('no marks with an overlay open')              // open the find bar (window.openFindBar())
  test('marks never appear in getContent()')
})
```

- [ ] **Step 2: Run** the suite. Expected: the new tests FAIL.
- [ ] **Step 3: Implement** the two `window` functions and `_changeMarks`. Recompute lazily: store a dirty flag on every `transaction` with `docChanged`, and compute in `_changeMarks()`, at most once per animation frame when the overlay asks.
- [ ] **Step 4: Run** the suite and `./test.sh`. Expected: PASS.
- [ ] **Step 5: Check in with Chris.**

---

### Task 3: The overlay

**Files:**
- Modify: `Sources/QuillKit/Resources/change-bars.js`
- Modify: `Sources/QuillKit/Resources/block-grip.js`
- Modify: `Sources/QuillKit/Resources/editor.html` (CSS; `installChangeBars` call after `installBlockGrip`)
- Modify: `Scripts/test-editor-change-bars.js`

**Interfaces:**
- Consumes: `window._changeMarks()` (Task 2).
- Produces:
  - `isGripHidingKey(event) -> boolean` in `block-grip.js`: true unless `event.key` is `Meta`, `Shift`, `Alt`, `Control` or `CapsLock`. The grip's own `keydown` handler switches to it, so the two cannot drift.
  - `installChangeBars(editor, hooks: { marks: () => { changed, removedGaps } }) -> { redraw(), hide() }`. Creates `#change-bar-layer` (positioned like `#block-grip-layer`, inserted into `#editor-wrap`) holding one `.change-bar` per changed block and one `.change-bar-removed` per gap, and `#change-bar-tooltip`. Placement as in the spec: `view.nodeDOM(topLevelPos(doc, i)).getBoundingClientRect()`, x = column right + 8px. Dots sit at the midpoint between the rects either side of the gap, using `gapYs(view)` from `block-grip.js` for the y. Shows on `mousemove` over `#editor-wrap` with `e.buttons === 0`. Hides on capture-phase `keydown` where `isGripHidingKey(e)`. Redraws on doc change (one per frame), window `resize`, and a `ResizeObserver` on `view.dom`. The tooltip shows after 600ms (the grip's delay) when the pointer is within 6px horizontally of a mark's x and inside its vertical extent, found by hit-testing in the same `mousemove` handler.
  - CSS: `#change-bar-layer` and children `pointer-events: none`; `#change-bar-tooltip` joins `#block-grip-tooltip`'s rule (`#block-grip-tooltip, #change-bar-tooltip { … }`). Colours and fades from Global Constraints. `.faded` class for hidden.

- [ ] **Step 1: Write the failing tests** (jsdom gives zero rects; test structure and state, not geometry)

```js
describe('overlay', () => {
  test('one .change-bar per changed block and one .change-bar-removed per gap')
  test('the layer is outside the contenteditable and aria-hidden')
  test('marks have pointer-events: none')                     // getComputedStyle on a .change-bar
  test('a keypress fades the layer; a mousemove with no buttons shows it')
  test('a modifier key alone does not fade it')               // dispatch keydown key: 'Shift'
  test('isGripHidingKey matches the grip: the grip also hides on "a" and not on "Meta"')
})
```

- [ ] **Step 2: Run** the suite. Expected: the new tests FAIL.
- [ ] **Step 3: Implement** `isGripHidingKey`, switch the grip's handler to it, then `installChangeBars` and the CSS.
- [ ] **Step 4: Run** the suite and `./test.sh`. Expected: PASS, including the existing block move suite.
- [ ] **Step 5: Check in with Chris.** Say why the CSS is inline.

---

### Task 4: Swift sends the baseline

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/EditorCoordinator.swift`
- Modify: `Sources/QuillKit/Views/Editor/EditorView.swift`
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift`
- Test: `Tests/QuillTests/EditorCoordinatorTests.swift`

**Interfaces:**
- Consumes: `window.setChangeBaseline`, `window.setBodyDirty` (Task 2).
- Produces:
  - `EditorCoordinator.setChangeBaseline(_ html: String, footnotes: String)`: deduped against the last baseline actually sent, held as pending while not ready, and sent after any pending content on ready, so the JS always has the content before its baseline. Don't reuse `EditorPushState` as it is: a fresh one treats `("", "")` as already sent (`emptyPostAfterARealOne`), so a new empty local draft would never get a baseline. Track the last sent pair as an optional (`nil` = nothing sent yet), in a small `BaselinePushState` or as an optional on the coordinator.
  - `EditorCoordinator.setBodyDirty(_ dirty: Bool)`: deduped on the last value sent; pending while not ready.
  - `nonisolated static func changeBaselineJS(html: String, footnotes: String) -> String?`: JSON-encodes both arguments the way `setContent` does and returns `"window.setChangeBaseline?.(<html>, <fn>)"`.
  - `EditorView` gains `baselineHTML: String`, `baselineFootnotes: String`, `bodyDirty: Bool`; `updateNSView` calls `setContent` first, then `setChangeBaseline`, then `setBodyDirty`.
  - `PostEditorView` passes `cleanContent`, `cleanFootnotes` and `bodyIsDirty`.

The spec asks for a Swift test that a stash-restored post gets the server content as its baseline. `PostEditorView` already keeps `cleanContent` as the server's on restore, and as a View it has no unit seam, so Task 2's "restored unsaved changes are marked" JS test and Task 5's manual step cover it instead. Tell Chris about this deviation at check-in.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func changeBaselineJSEscapesQuotesAndNewlines()   // html "<p>\"a\"\n</p>" → output contains "\\\"a\\\"\\n" and starts with "window.setChangeBaseline?.("
@Test func changeBaselineJSPassesFootnotesThrough()    // footnotes "[{\"id\":\"x\"}]" round-trips through JSONDecoder
@Test func firstEmptyBaselineIsSent()                  // fresh state: shouldPush("", "") == true; after record("", ""): false; after record("<p>A</p>", "[]"): ("", "") true again
```

- [ ] **Step 2: Run** `swift test --filter EditorCoordinatorTests`. Expected: FAIL, `changeBaselineJS` not found.
- [ ] **Step 3: Implement** as specified.
- [ ] **Step 4: Run** `swift test --filter EditorCoordinatorTests`, then `./test.sh`, then the build command. Expected: PASS, and Quill opens.
- [ ] **Step 5: Manual smoke test** on a new local draft: type in a paragraph, move the mouse, and see a bar. Save Locally, and the bar goes. Discard the draft.
- [ ] **Step 6: Check in with Chris.**

---

### Task 5: Real WebKit pass and docs

**Files:**
- Modify: `docs/testing-plan.md`, `site/docs.html`, `Sources/QuillKit/Resources/CLAUDE.md`, the spec

- [ ] **Step 1: Run** `./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"`. Expected: pass.
- [ ] **Step 2: Run the spec's §7 steps** on a new local draft and on a published post opened read-only (load it and look; do not edit it): bars at the narrowest window with the sidebar and inspector open; nothing renders past the column into the bars (wide table, long code line, wide image); typing hides them and moving the mouse brings them back; a click on a bar puts the caret on that line; Save and Revert clear them; a freshly loaded post has none; bars follow blocks while an image above them loads; light and dark. For restored unsaved changes, which only remote posts have: send a new local draft to WordPress as a draft (status Draft, then the publish button), edit two of its paragraphs, switch to another post without saving, switch back, and check the bars sit on exactly those two paragraphs. Delete that draft on WordPress when done.
- [ ] **Step 3: Update docs.**
  - `docs/testing-plan.md`: the suite, its count, the §7 steps.
  - `site/docs.html`: a short paragraph under Saving and Publishing.
  - `Sources/QuillKit/Resources/CLAUDE.md`: a gotcha entry, "compare against Swift's baseline, not the loaded document", pointing at the restored-changes test.
  - The spec: record the Task 1 gate result.
- [ ] **Step 4: Run** `./test.sh`. Expected: all suites pass.
- [ ] **Step 5: Check in with Chris** with a summary, and ask whether to commit.
