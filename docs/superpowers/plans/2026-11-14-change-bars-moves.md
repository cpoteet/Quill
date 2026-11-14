# Change Bars for Moved Blocks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A block move marks the moved block with a "Moved since the last save" bar and leaves no dot (cpoteet/Quill#28).

**Architecture:** `changedBlocks` gets a weighted LCS whose weights only break ties against blocks the author moved, then pairs leftover added and removed blocks by key as moves. `editor.html` records the moved blocks' keys at the two move sites and clears them with the baseline.

**Tech Stack:** Plain JS in `Sources/QuillKit/Resources/`, node:test + jsdom in `Scripts/`.

**Spec:** `docs/superpowers/specs/2026-11-14-change-bars-moves-design.md`

## Global Constraints

- Moved bars use the existing `.change-bar` look; only the class `moved` and the tooltip differ.
- Tooltip copy: "Moved since the last save". Existing copy unchanged: "Changed since the last save", "Removed since the last save".
- No commit without Chris asking (global CLAUDE.md).
- Any helper a test reads as `win.x` is a `function` declaration (project gotcha).

## Review Focus

- Two identical paragraphs, one moved: one "Moved" bar, no dot, no "Changed" bar. Test: `a moved copy of an identical paragraph is still one move`.
- A move plus a deletion in the gap the moved block left: the deletion's dot stays. Test: `a move and a deletion from the same gap keep the dot`.
- Move then edit the moved block: plain "Changed" (in `changed`, not `moved`). Test: `a moved block that is then edited is changed, not moved`.
- A move after a save: the hint was cleared by the new baseline, and the new move is hinted. Test: `a new baseline forgets earlier moves`.
- Undo of a move leaves no marks. Covered by the existing `undo back to the original: no marks` path plus `undoing a move leaves no marks`.

---

### Task 1: `changedBlocks` knows moves

**Files:**
- Modify: `Sources/QuillKit/Resources/change-bars.js` (`changedBlocks`)
- Test: `Scripts/test-editor-change-bars.js`

**Interfaces:**
- Produces: `changedBlocks(baseline, current, trailingAfter, keyOf, movedKeys?) -> { changed: number[], moved: number[], removedGaps: number[] }`. `movedKeys` is a `Set` of keys or absent. `moved` ⊆ `changed`.

- [ ] **Step 1: Failing tests** in `'changedBlocks, where the marks fall'`, calling `changedBlocks` directly:
  - `a block moved far is moved, and leaves no dot`: `A B C D`, move A to the end → `{ changed: [3], moved: [3], removedGaps: [] }`.
  - `a swap with a hint marks the hinted block`: `A B C`, A after B, `movedKeys` = A's key → `changed: [1], moved: [1]`; with B's key → `changed: [0], moved: [0]`; with no hint → `changed: [0]` (today's tie-break).
  - `a moved block that is then edited is changed, not moved`.
  - `a move and a deletion from the same gap keep the dot`: `A B C D`, move A to the end, delete B → dot at 0, `moved: [2]`.
  - `a moved copy of an identical paragraph is still one move`.
  - Update `a moved block: a bar at the new place, a dot at the old` → no dot, `moved: [3]`; `swapping two neighbours…` → one bar, no dot.
- [ ] **Step 2:** `node --test Scripts/test-editor-change-bars.js` → the new tests fail.
- [ ] **Step 3:** Implement. DP over `Float64Array`; match weight `W = min(before, after) + 1`, or `W - 1` for a key in `movedKeys`; traceback unchanged. Collect the ops, then pair each added entry with an unpaired removed entry of the same key (per key, in order); paired adds go to `moved`, paired removals are ignored for dots. A run gets a dot when it holds an unpaired removal and no unpaired addition.
- [ ] **Step 4:** Suite passes.

### Task 2: Move sites hint the diff, and the tooltip says "Moved"

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` (`setChangeBaseline`, `setContent`, `_changeMarks`, `_dropGripDrag`, `window.moveBlock`), `Sources/QuillKit/Resources/change-bars.js` (`redraw`, `showTip`)
- Test: `Scripts/test-editor-change-bars.js`

**Interfaces:**
- Consumes: Task 1's `changedBlocks`.
- Produces: `function _noteMovedBlocks(doc, from, to)` in `editor.html`, which adds `_changeBaselineKeyOf(doc.child(i))` for `i` in `[from, to)` to `_movedKeys` (no-op without a baseline). `_changeMarks()` returns `{ changed, moved, removedGaps }`, with `moved: []` on the early return.

- [ ] **Step 1: Failing tests**, new `describe('moves through the editor')`, via `setContent` + `setChangeBaseline` + `setBodyDirty(true)` and `win._changeMarks()`:
  - `Move Block Down past one block marks the moved block` (the issue's case: `win.moveBlock('down')` on block 0 of two → `changed: [1], moved: [1], removedGaps: []`).
  - `Move Block Up marks the moved block`.
  - `a grip drop past one block marks the dragged block` (drop on `#editor-wrap` at clientY 100, as in `test-editor-block-move.js`).
  - `a section moved past two blocks marks each of its blocks`.
  - `editing another block after a move keeps the move mark`.
  - `a new baseline forgets earlier moves`, `undoing a move leaves no marks`.
  - In `'overlay behaviour'`: `hovering a moved bar says it moved` → "Moved since the last save", bar has class `moved`.
- [ ] **Step 2:** Suite → those fail.
- [ ] **Step 3:** Implement `_movedKeys` (a `Set`), filled by `_noteMovedBlocks` before each move dispatch, replaced with a new `Set` in `setChangeBaseline` and `setContent`, passed to `changedBlocks` in `_changeMarks`. `redraw` adds class `moved`; `showTip` picks the copy by class.
- [ ] **Step 4:** Suite passes.

### Task 3: Docs, full run, build

- [ ] Update `docs/testing-plan.md` (suite count and tables, row 278, the §7.29 step for a move), `site/docs.html` Change Bars paragraph, the original spec's "a moved block gets a bar at its new place and leaves a dot at its old one" line.
- [ ] `./test.sh` → all pass; correct the header counts.
- [ ] The project build-and-run command → builds and opens.

---

## Revision after the hand check (2026-11-14)

Chris's hand check found a "Removed" dot left by an edited block moved below a moved Group. Tasks 1 and 2 were redone as described in the spec's revised Design section:

- `changedBlocks` became origin-based (`_originsByKey`, `_keptInOrder`).
- The `movedBlocks` plugin and `mapMovedBlocks` follow every block step by step.
- `_trackMove` flags moves.
- The tests in `'moves through the editor'` cover both edit orders, undo and redo, and seeded random sequences.
