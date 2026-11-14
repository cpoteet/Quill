# Change bars for moved blocks

Issue: cpoteet/Quill#28. Amends `2026-10-31-change-bars-design.md`.

## Why

Dragging a block past its neighbour, or pressing Move Block Up/Down, currently puts the bar on the neighbour and a "Removed since the last save" dash where the dragged block used to be. The marks read as an edit plus a deletion on the wrong block, when the author only reordered.

## Goals

- The block the author moved gets the mark, not the block it passed.
- A move reads as a move: its bar's tooltip says "Moved since the last save".
- A pure move leaves no dash at its old place.

## Non-goals

- A separate look for moved bars. Moved bars stay the same grey bar; only the tooltip differs (Chris, 2026-11-14).
- One combined mark for a section move. Each block in a moved section gets its own bar (Chris, 2026-11-14).
- Tracking moves made some other way, such as cut and paste, or an undo. These use today's tie-break.

## Anti-goals

- A move mark on a block whose content changed. A block that was moved and also edited, in either order, gets the plain "Changed" bar and no dash.
- Hiding a real deletion. A dash stays whenever a block removed from that gap is not accounted for by a move.

## Approaches

1. **Hint the tie-break, then pair leftovers (first build, replaced by 4).** The grip drop and Move Block record the saved-HTML keys of the blocks they moved. The LCS gives a match of a recorded key slightly less weight than any other match. That weight only breaks ties, so the block the author moved is the one left unmatched. After the LCS, each unmatched current block whose key equals an unmatched baseline block is paired with it, counted per key, and marked as moved. Paired baseline blocks leave no dash.
2. **Pair leftovers only, without a hint.** Labels moves correctly but still marks the wrong block on every adjacent swap, which covers every Move Block Up/Down press. Rejected: it fixes half the issue.
3. **Track moves through the transaction mapping instead of by key.** First rejected as a lot of machinery. The hand check showed it is needed: an edited block has no key in common with its saved self.
4. **Follow every block's origin (chosen).** Approach 3 for every block, not only moved ones, plus node identity for undo and redo. A seeded random test of moves, edits, deletions, undo and redo found three gaps in approaches 1 and 3 that this closes.

## Design

*Revised the same day after Chris's hand check: an edited block moved below a moved Group left a "Removed" dash where it had been. Pairing by saved HTML alone cannot know that an edited block is the saved block it came from, so the bars now follow every block.*

- **Every block knows where it came from.** A ProseMirror plugin (`movedBlocks` in `editor.html`) keeps, for each top-level block, the index of the saved block it came from (or null for a new block) and whether the author moved it. When the baseline arrives, the origins come from the saved-HTML comparison (`_originsByKey`). After that, `mapMovedBlocks` maps each block's start through every step of every transaction, appended ones included. A block whose start was deleted loses its entry. A block that comes back as a node object seen before, such as by undo, redo or a move, which all reuse the same node, gets that object's entry back. The plugin follows each step, not just the transaction's end state, because one undo can put a block back and then reverse edits made to it.
- **Moves.** The grip drop and Move Block flag the blocks they carry, on the move's own transaction (`_trackMove`). Blocks back in their saved order lose the flag.
- **`changedBlocks(baseline, current, trailingAfter, keyOf, known)`** returns `{ changed, moved, removedGaps, origins, placed }`. With `known`, known origins are reserved first. Only a block with no known origin takes the unclaimed saved block with the same HTML, after a paste or leaving code view for example. Without `known`, the origins come from the saved HTML, as before.
- **Order.** The blocks kept in their saved order are the heaviest increasing run of origins. A block the author moved is worth less than all the others together, so only moved blocks fall out of it. Ties go to the earlier rule: of two swapped blocks, the first in the new order is marked.
- **Marks.**
  - An edited block (no origin, or HTML differing from its origin's) gets a "Changed" bar.
  - An unedited block out of order gets a "Moved" bar.
  - A saved block no current block came from was removed. Removals between the same two unchanged, in-order blocks share one dash. As before, an edit between those two stands in for them and hides the dash, but a block the author moved there never does.
  - The plugin keeps a block's origin through a change that replaces its opening (heading, list wrap). Enter at a block's start gives the origin to the text, not the new empty block. A move flag stays with whichever block reads as the moved saved block.
  - Known gap: undoing a join splits the block back off as a node the plugin has never seen. If it was edited and is then moved, its old place shows a dash, as on main.
- **Tooltip:** a moved bar gets the class `change-bar moved` and the text "Moved since the last save".
- The plugin resets when a baseline arrives (`setChangeBaseline`, which Swift sends only when it differs, and after every content push).

## Left to the builder

- Naming, and whether the weight constant is derived from the block count or fixed.
