# Tiptap 3 Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the editor bundle from Tiptap 2.27.3 to Tiptap 3.33.1 with no change in what Quill loads, shows or saves.

**Architecture:** Behaviour is pinned on v2 first with characterization tests and a schema dump, then the bundle is swapped and every difference is either reverted to v2 behaviour or recorded as accepted. No v3 feature is adopted in this change; candidates are listed at the end for later, separate work.

**Tech Stack:** Tiptap 3.33.1 (`@tiptap/core`, `starter-kit`, `extension-table`, `extension-list`, `extensions`, `pm`), esbuild 0.28.2, jsdom test suites, the real-WebKit fixture check.

**Spec:** None. There are no design decisions; the findings below are the evidence this plan argues from.

**Progress:** in progress on branch `tiptap-v3-migration`. The ledger is `.superpowers/sdd/2026-11-11-tiptap-v3-migration/progress.md` (git-ignored): which tasks are complete, every ruling that departs from this plan, and how to resume.

## Findings from the 2026-11-11 spike

A throwaway worktree was built against 3.33.1. Nothing from it was committed.

| Step | JS test failures (of 2,212) |
|---|---|
| v3 bundle, no editor changes | 143 |
| + `setContent` options object and four StarterKit opt-outs | 5 |
| + ordered-list `type` restored to v2's definition | 0 |

- The real-WebKit fixture check passed 28/28 and no script handler ran, on the build before the final ordered-list fix.
- ProseMirror is the same underneath: every `prosemirror-*` package resolves to the same version or one patch newer (`model` 1.25.12 → 1.25.13, `transform` 1.12.4 → 1.12.5, `changeset` 2.4.5 → 2.4.6). `prosemirror-history` is unchanged, so the `history$` plugin key and the `closeHistory$` meta still work.
- Unchanged in v3 source, so their gotchas stay: `elementFromString` whitespace dropping, `insertContentAt` inserting unmarked text verbatim, the code mark's `excludes: "_"`.
- The bundle grows from 369 KB to 451 KB.
- Not run in the spike: `swift test`, the paste harness, the manual pass, anything interactive.

A dump of the schema, extension list and plugin list under both bundles showed these differences that no test caught:

| Difference in v3 | Status |
|---|---|
| `orderedList.type` is derived from `list-style-type`, and `type="1"` is no longer rendered | Wrote `type="I"` into saved markup, which WordPress rejects. Fixed in Task 3 |
| `tableCell.align` and `tableHeader.align` attributes; the editor DOM gains `style="text-align: …"` | Saved output not compared. Pinned in Task 2, resolved in Task 4 |
| `link.title` attribute | A link with a title saved identically in one probe. Pinned in Task 2 |
| `listItemBranchingDeleteKeymap` extension (priority 101) | Untested. Pinned in Task 2, resolved in Task 4 |
| `handleClickLink$` plugin registered although `openOnClick: false` | Untested. Pinned in Task 2, resolved in Task 4 |
| `delete` and `textDirection` core extensions; `history` renamed `undoRedo`; placeholder key is `tiptap__placeholder$` | Accepted. Recorded in Task 4 |
| Plugin order differs throughout | Decides which keymap wins at equal priority. Covered by the keyboard suite plus the manual pass in Task 5 |
| The table node's `figure.wp-block-table` and `caption` parse rules appear five times instead of once; `th` and `td` gain one extra rule | Matches the number of stacked `.extend()` layers, so `this.parent()` appears to re-run per layer. Cause confirmed in Task 4 |
| Default `colspan="1" rowspan="1"` no longer rendered | Harmless; `toWordPressHTML` already strips them |

Found during execution (2026-11-12), after the spike:

| Difference in v3 | Status |
|---|---|
| Table cells saved `style="text-align:…"` beside `align` | Fixed in Task 4 (`_withoutCellAlign`, now `_cellAttrsAsV2`); test 4 |
| `OrderedList` adds a `handlePaste` plugin that turns plain-text `1. a` / `2. b` into a list | Turned off in Task 4 (`addProseMirrorPlugins() { return [] }`); characterization test written on v2. A candidate below |
| On v2, `StarterKit.extend({ addExtensions() { this.parent() } })` ignored `configure({ …: false })`, so the eight stock nodes Quill replaces were registered twice (80 keymap plugins vs 75) | v2 bug that v3 fixes. Accepted; block shortcuts added to the manual pass |
| Input rules are one plugin per extension instead of one global plugin | Accepted. `undoInputRule` walks every plugin; 36-case input-rule test equal to v2 |
| `codeBlockVSCodeHandler$1` gone | It was v2's duplicate CodeBlock. Accepted |
| `preserveCellSelectionOnContextMenu$` (table) | Accepted; right-click in a cell selection added to the manual pass |
| `Blockquote` binds Backspace (lift a non-first child; merge a following paragraph into the quote's last textblock) | Found by the Codex review. Turned off in `CustomBlockquote`; three characterization tests written on v2 |
| `listItemBranchingDeleteKeymap` outdents a nested branch on Delete when the nested item holds two paragraphs or its own list | Found by the Codex review; tests 6–8 were too shallow to see it. Turned off with `ListItem.extend({ addExtensions() { return [] } })`; two characterization tests written on v2 |
| `handleClickLink$` returns early unless `openOnClick` or `enableClickSelection` | Inert with Quill's options. Accepted; test 9 now sends `button: 0` so it reaches the plugin |
| New commands `insertDefaultBlock`, `setTextDirection`, `unsetTextDirection`, `updateDecorations` | From the accepted core extensions; nothing in Quill calls them |
| Real-WebKit paste: 19 fixture clipboards, plain numbered list, plain URL, two round trips | 22/22 saved identically under v2 and v3 |
| Pre-existing, same on v2 and v3: typing `---` in a footnote entry splits the footnotes list around a horizontal rule | Out of scope for the migration. Recorded by the input-rule test; worth its own issue |
| Cells read `colwidth` from the table's `<col width>`, so a classic table with a colgroup saved `colwidth` on every cell (invalid core/table) | Found by the final review. Fixed (`_cellAttrsAsV2`); characterization test from v2 |
| `Table` renders through `TableView` (`div.tableWrapper`) even when not resizable | Found by the final review. Fixed (`View: null`), live DOM equal to v2; test |
| `N. ` input rule joins only untyped lists, so `3. ` below a lettered list started a new list | Found by the final review. Fixed (`OrderedListWithClass.addInputRules` wraps the rule with v2's join); test |

## Global Constraints

- Exact versions: every `@tiptap/*` package at `3.33.1`, `esbuild` stays `0.28.2`.
- No v3 feature is adopted. `link`, `underline`, `trailingNode` and `listKeymap` stay off in StarterKit.
- A test added in Task 2 must pass on v2 before the bundle changes. Its expected value is never edited to make v3 pass; v3 is changed instead, or the difference goes to Chris.
- Do not commit. Each task ends at a checkpoint: summarize what changed and wait. When Chris asks for a commit, run the Codex review in `~/.claude/CLAUDE.md` first.
- Work in the main checkout. `build.sh` opens the app it builds, and any copy shares `~/Library/Application Support/Quill/` with the real app.
- After any change under `Sources/`: `pkill -f "^$PWD/Quill.app/Contents/MacOS/Quill"; sleep 2 && ./build.sh 2>&1 && open Quill.app`.
- A script that requires `jsdom` must live in `Scripts/`.
- This ships as its own release with no other change in it.

## Review Focus

1. **Loading a post must not mark it dirty.** v3's `setContent` emits an update unless told not to. Pinned by the existing bridge suite; any new `setContent` call needs `{ emitUpdate: false }` where v2 passed `false`.
2. **A list styled with `list-style-type` must not gain a `type` attribute on save.** Task 2 tests 1–3.
3. **Backspace and Delete at list-item boundaries, inside and outside a footnote.** Task 2 tests 6–8.
4. **⌘-click on a link opens it exactly once.** Task 2 test 9.
5. **Typing, undo, drag and image resize in real WebKit.** No automated test reaches these; Task 5's manual pass owns them.

---

### Task 1: Schema dump tool

**Files:**
- Create: `Scripts/dump-editor-schema.js`

**Interfaces:**
- Produces: `node Scripts/dump-editor-schema.js [path/to/editor.html]` prints one line per fact to stdout and exits 0. The path defaults to `Sources/QuillKit/Resources/editor.html`. Tasks 3, 4 and 6 diff two runs of it.

- [ ] **Step 1: Write the script**

It boots `editor.html` in jsdom the way `Scripts/test-editor-inline-formats.js` does in its `before()` (same polyfills, same wait for `win._tiptapEditor`), then prints, in this order:

```
node <name> content=… group=… marks=… inline=… atom=… defining=… isolating=… code=… draggable=… selectable=… whitespace=…
mark <name> excludes=… inclusive=… spanning=…
  attr <name>.<attr> default=<JSON>
  parse <name> tag=… style=… prio=… ctx=… consuming=… pw=… getAttrs=<bool> contentEl=<typeof>
ext <type> <name>
plugin <index> <key with a trailing numeric suffix replaced by N> props=<sorted prop names>
commands <sorted command names>
```

Nodes and marks come from `editor.schema.spec`, extensions from `editor.extensionManager.extensions`, plugins from `editor.state.plugins`. Sort node, mark and `ext` lines by name so a reorder does not hide a real change; keep plugin lines in registration order, because order is the fact.

- [ ] **Step 2: Capture the v2 baseline**

Run: `node Scripts/dump-editor-schema.js > /tmp/quill-schema-v2.txt && wc -l /tmp/quill-schema-v2.txt`
Expected: roughly 500 lines, including `plugin … history$ props=handleDOMEvents` and `ext extension history`.

- [ ] **Step 3: Checkpoint** — summarize and wait.

---

### Task 2: Pin v2 behaviour for everything v3 changes

**Files:**
- Modify: `Scripts/test-editor-preservation.js` (tests 1–5)
- Modify: `Scripts/test-editor-keyboard.js` (tests 6–9)

**Interfaces:**
- Consumes: each suite's existing helpers — `win.setContent`, `win.getContent`, `key(view, k, mods)`, `doc()`, `posOfFirst(typeName)`.
- Produces: nine tests that Tasks 3 and 4 must keep green.

Tests 1–5 share one helper: load `src`, put the caret before the first text node, insert `X`, return `win.getContent()`. If `test-editor-preservation.js` already has an equivalent, use it.

- [ ] **Step 1: Write tests 1–5 in a `describe('Tiptap 3 migration: saved markup')`**

Each asserts `strictEqual(editAndSave(src), expected)`.

| # | `src` | `expected` |
|---|---|---|
| 1 | `<!-- wp:list {"ordered":true,"type":"lower-alpha"} -->\n<ol style="list-style-type:lower-alpha" class="wp-block-list"><!-- wp:list-item -->\n<li>x</li>\n<!-- /wp:list-item --></ol>\n<!-- /wp:list -->` | `src` with `<li>Xx</li>` |
| 2 | `<!-- wp:list {"ordered":true} -->\n<ol type="a" class="wp-block-list"><!-- wp:list-item -->\n<li>x</li>\n<!-- /wp:list-item --></ol>\n<!-- /wp:list -->` | `src` with `<li>Xx</li>` |
| 3 | test 2's `src` with `type="1"` | `src` with `<li>Xx</li>` |
| 4 | `<!-- wp:table -->\n<figure class="wp-block-table"><table><tbody><tr><td align="center">c</td><th align="right">h</th></tr></tbody></table></figure>\n<!-- /wp:table -->` | `<!-- wp:table {"hasFixedLayout":false} -->\n<figure class="wp-block-table"><table><tbody><tr><td align="center">Xc</td><th align="right">h</th></tr></tbody></table></figure>\n<!-- /wp:table -->` |
| 5 | `<!-- wp:paragraph -->\n<p><a href="https://example.com" title="A title">link</a></p>\n<!-- /wp:paragraph -->` | `src` with `>Xlink<` |

Tests 1, 2, 4 and 5 were probed on v2 and produce exactly these values. Test 3 was not; if v2 saves something else, record what v2 saves as `expected` and say so at the checkpoint.

Add to test 2: `assert.match(editor.getHTML(), /<ol type="a"/)` before the edit, since v2 keeps the attribute in the editor.

- [ ] **Step 2: Write tests 6–9 in a `describe('Tiptap 3 migration: keys and clicks')`**

For 6–8 the expected `doc()` string is whatever v2 produces: run once on v2, read the actual value from the failure, and write it in as the literal. These are characterization tests.

- Test 6, `Delete at the end of a list item that has a nested list`: content `<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>`, caret at the end of `a`, `key(editor.view, 'Delete')`.
- Test 7, `Backspace at the start of a list item that follows a nested list`: same content, caret at the start of `c`, `key(editor.view, 'Backspace')`.
- Test 8, `Delete at the end of a footnote entry leaves the list intact`: `<p>body</p>`, `win.insertFootnote()`, insert `x`, caret at the end of the footnote text, `key(editor.view, 'Delete')`. The likely v2 value is `paragraph("body",MARKER) | footnotesList(footnoteItem("x"))`, but it was not probed; record what v2 gives.
- Test 9, `⌘-click on a link posts openLink once and a plain click posts nothing`: content `<p><a href="https://example.com/">l</a></p>`; set `win.webkit = { messageHandlers: { ...existing, openLink: { postMessage: href => calls.push(href) } } }`; also replace `win.open` with a stub that records its calls. A DOM `click` event never reaches ProseMirror's `handleClick` in jsdom (it runs from mouse-up through `posAtCoords`), so run the prop chain directly, as `Scripts/test-click-seat.js` does: `editor.view.someProp('handleClick', f => f(editor.view, 2, event))` with `event = { metaKey: true, target: theAnchor, preventDefault() {} }`, then again with `metaKey: false`. `someProp` walks every plugin's `handleClick` in order and stops at the first that returns true, which is what v3's extra link plugin could change. Assert `calls` equals `['https://example.com/']` and the `win.open` stub was never called.

- [ ] **Step 3: Run both suites on v2**

Run: `node --test Scripts/test-editor-preservation.js Scripts/test-editor-keyboard.js`
Expected: all pass (82 + 5 and 151 + 4).

- [ ] **Step 4: Checkpoint** — summarize, including any expected value that had to be read off v2, and wait.

---

### Task 3: Swap the bundle

**Files:**
- Modify: `Scripts/tiptap-bundle/package.json`, `Scripts/tiptap-bundle/package-lock.json`, `Scripts/tiptap-bundle/entry.js`
- Modify: `Sources/QuillKit/Resources/tiptap-bundle.js` (generated)
- Modify: `Sources/QuillKit/Resources/editor.html`
- Modify: every `Scripts/test-*.js` that calls `editor.commands.setContent(…, false)` (six files, 288 lines)

**Interfaces:**
- Produces: `window.TiptapBundle` exporting every name `editor.html` destructures from it today, unchanged.

- [ ] **Step 1: Set the dependencies in `Scripts/tiptap-bundle/package.json`**

```json
"@tiptap/core": "3.33.1",
"@tiptap/starter-kit": "3.33.1",
"@tiptap/extension-table": "3.33.1",
"@tiptap/extension-list": "3.33.1",
"@tiptap/extensions": "3.33.1",
"@tiptap/extension-image": "3.33.1",
"@tiptap/extension-link": "3.33.1",
"@tiptap/extension-underline": "3.33.1",
"@tiptap/extension-blockquote": "3.33.1",
"@tiptap/extension-paragraph": "3.33.1",
"@tiptap/extension-heading": "3.33.1",
"@tiptap/extension-code-block": "3.33.1",
"@tiptap/extension-horizontal-rule": "3.33.1",
"@tiptap/pm": "3.33.1",
"esbuild": "0.28.2"
```

Removed: `extension-table-row`, `-table-cell`, `-table-header`, `-task-list`, `-task-item`, `-placeholder`, `-bullet-list`, `-ordered-list`, `-list-item`. Added: `extension-list`, `extensions`, and `extension-horizontal-rule` (imported today but only present transitively).

Then: `cd Scripts/tiptap-bundle && rm package-lock.json && npm install --package-lock-only`

- [ ] **Step 2: Replace the changed lines of `Scripts/tiptap-bundle/entry.js`**

```js
export { Table, TableRow, TableCell, TableHeader } from '@tiptap/extension-table'
export { BulletList, OrderedList, ListItem, TaskList, TaskItem } from '@tiptap/extension-list'
export { Placeholder }                 from '@tiptap/extensions'
```

These replace the ten default-export lines for the same names. Every other line stays.

- [ ] **Step 3: Build the bundle**

Run: `./Scripts/bundle-tiptap.sh`
Expected: `✓ Bundle written …` at about 440 KB, no `Could not resolve`.

- [ ] **Step 4: Edit `editor.html`**

In the `StarterKit…configure({ … })` block, after `horizontalRule: false,`:

```js
link: false, underline: false, trailingNode: false, listKeymap: false,
```

The two `editor.commands.setContent(…, false)` calls (in `window.setContent` and the code-view exit) take `{ emitUpdate: false }` in place of `false`.

In `OrderedListWithClass`'s `OrderedList.extend({ … })`, restore v2's attribute and rendering:

```js
addAttributes() { return { ...this.parent?.(), type: { default: null, parseHTML: el => el.getAttribute('type') } } },
renderHTML({ HTMLAttributes }) {
  const { start, ...rest } = HTMLAttributes
  return ['ol', start === 1 ? rest : HTMLAttributes, 0]
},
```

- [ ] **Step 5: Update the tests' `setContent` calls**

Run: `sed -i '' "s/commands\.setContent(\(.*\), false)/commands.setContent(\1, { emitUpdate: false })/" Scripts/test-*.js`
Then: `git diff --stat -- Scripts/test-*.js` — expect six files, 288 lines each way, and `git diff -- Scripts/test-*.js | grep '^[-+]' | grep -v 'setContent\|^+++\|^---'` prints nothing.

- [ ] **Step 6: Run every JS suite**

Run: `./test.sh`
Expected: tests 1–3, 5 and 9 from Task 2 pass, and everything that passed before passes. Tests 4, 6, 7 and 8 may fail; those failures belong to Task 4. Any other failure stops the task.

- [ ] **Step 7: Checkpoint** — summarize with the exact pass and fail counts, and wait.

---

### Task 4: Resolve every remaining difference

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`
- Modify: `docs/editor-gotchas.md`

**Interfaces:**
- Consumes: `/tmp/quill-schema-v2.txt` from Task 1, the tests from Task 2.

- [ ] **Step 1: Diff the schema**

Run: `node Scripts/dump-editor-schema.js > /tmp/quill-schema-v3.txt; diff /tmp/quill-schema-v2.txt /tmp/quill-schema-v3.txt`

Every line of the diff must match a row of the findings table. A line that matches no row stops the task and goes to Chris.

- [ ] **Step 2: Table cell `align` (test 4)**

If test 4 fails, remove v3's attribute from both `TableCell` and `TableHeader` before they are wrapped, so the raw-attribute carrier keeps handling `align` as it does on v2:

```js
addAttributes() { const { align, ...rest } = this.parent?.() || {}; return rest },
```

Re-run test 4. Then confirm `editor.getHTML()` for test 4's `src` contains no `style="text-align` (ProseMirror must never render a style Quill did not author).

If test 4 passes untouched, still check the `getHTML()` condition; if the style is there, apply the same removal.

- [ ] **Step 3: The list-item delete keymap (tests 6–8)**

If any of 6–8 fails, remove the extension by overriding `addExtensions() { return [] }` on `ListItem` before it is wrapped, and confirm `ext extension listItemBranchingDeleteKeymap` is gone from the dump. If they all pass, leave it and record it in Step 6.

- [ ] **Step 4: The link click handler (test 9)**

If test 9 fails, the cause is `handleClickLink$` consuming the click before `editorProps.handleClick`. Read `clickHandler` in `node_modules/@tiptap/extension-link/dist/index.js` to find the option that keeps it from being registered, set it on `LinkWithRawAttrs.configure`, and confirm the plugin is gone from the dump.

- [ ] **Step 5: Confirm the cause of the duplicated table parse rules**

Count the `parse table tag=figure.wp-block-table` lines in the v3 dump and the `.extend()` and `.configure()` calls between `Table` and the editor's extension list. If the counts agree, the cause is `this.parent()` re-running per layer. Then check the two places where a repeat would change behaviour rather than add a duplicate rule:

- `BulletListWithClass`, `OrderedListWithClass` and `CodeBlock`'s `addKeyboardShortcuts` wrap `this.parent?.()`. Before trusting them, stash the v3 changes, write a keyboard test on v2 that presses Enter and then Backspace in a footnote entry and records `doc()` after each, then restore the changes and confirm v3 gives the same two values.
- Any `addAttributes` that spreads `this.parent?.()` and then overrides a key: confirm in the dump that each such attribute appears once.

If the counts do not agree, stop and take it to Chris.

- [ ] **Step 6: Record what was accepted**

In `docs/editor-gotchas.md`, add one gotcha titled **Tiptap 3's StarterKit adds Link, Underline, TrailingNode and ListKeymap, and all four must stay off**, giving the collision for each (Quill registers its own `link` and `underline`; `TrailingNode` appends after any block and at the very end of the doc, where Quill needs a paragraph only after the five types in `TRAILING_PARAGRAPH_AFTER` and before the footnotes list). Add a second gotcha for the duplicated parse rules with the cause found in Step 5. Index both titles in `Sources/QuillKit/Resources/CLAUDE.md`.

- [ ] **Step 7: Run everything**

Run: `./test.sh`
Expected: every suite passes, including all nine Task 2 tests.

- [ ] **Step 8: Checkpoint** — summarize which of Steps 2–4 needed a change, and wait.

---

### Task 5: Verify what jsdom cannot

**Files:** none modified unless a check fails.

- [ ] **Step 1: Build and run the real-WebKit fixture check**

Run: `pkill -f "^$PWD/Quill.app/Contents/MacOS/Quill"; sleep 2 && ./build.sh 2>&1 && ./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"`
Expected: `28/28 passed` and `ok    no script handler ran`.

- [ ] **Step 2: Run the paste harness**

Follow `Scripts/fixtures/paste/README.md`. Expected: every captured clipboard matches its recorded result.

- [ ] **Step 3: Run the manual pass**

Use the `manual-test-pass` skill for all of `docs/testing-plan.md` §7, on a new local draft. Beyond the checklist, exercise each of these, because plugin order changed and no automated test types into real WebKit:

- Enter, Backspace, Delete and Tab at the start, middle and end of: a list item, a nested list item, a footnote entry, an accordion heading, a tab title, a button, an image caption, a table cell, a blockquote with a cite.
- Undo and redo across a block move, a paste and an AI result; undo immediately after opening a post does nothing.
- Image resize by handle, grip drag of a block, ⌘-drag of a section.
- ⌘-click on a link and on a footnote marker.
- Open a published post and close it without editing: it is not marked dirty.

- [ ] **Step 4: Checkpoint** — report each check with its result, and wait. A failure here is fixed in this branch with a test, not deferred.

---

### Task 6: Update the docs and tooling

**Files:**
- Modify: `CLAUDE.md` ("Tiptap 2.x" under Key decisions)
- Modify: `docs/editor-gotchas.md` (the "bundled locally as IIFE" entry: version, pin date, and drop the "For Tiptap 3.x" sentence; the "`ResizableImage` must import `Image` as a named import" entry: `@tiptap/extension-image@2` → `@3`)
- Modify: `.claude/skills/update-dependencies/SKILL.md`
- Modify: `Scripts/check-dependencies.sh` if it names any removed package
- Modify: `docs/testing-plan.md` (suite counts)
- Modify: `NOTICES.md` (Tiptap copyright year, if the v3 `LICENSE.md` differs)

- [ ] **Step 1: Make the edits above**

In the skill, the Tiptap row's rule becomes: "Update within v3, one minor range at a time. Before and after any update, diff `node Scripts/dump-editor-schema.js`; every changed line needs an explanation." Remove the `mergeAttributes` advisory trap if `npm audit` in `Scripts/tiptap-bundle/` no longer reports it.

- [ ] **Step 2: Verify**

Run: `./Scripts/check-dependencies.sh` — expect it to complete and show every `@tiptap/*` package at 3.33.1.
Run: `grep -rn "2\.27\.3\|Tiptap 2" CLAUDE.md docs Sources/QuillKit .claude/skills --include='*.md'` — expect only historical records (specs, plans, the changelog).

- [ ] **Step 3: Checkpoint** — summarize and wait. The release itself is `/release <version>`, with this change alone.

---

## After the migration: what could move to v3

None of this is part of the plan above. Each would be its own change with its own tests. The honest summary is that v3 removes very little of Quill's own code; where it is interesting, it is as new capability.

| Candidate | What was checked in 3.33.1 | Take |
|---|---|---|
| **Replace `marked` with `@tiptap/markdown`** | It is MIT and depends on `marked ^17` itself. Quill's whole use of `marked` is one call, `marked.parse(text, { gfm: true })`, whose HTML then goes through `cleanPastedHTML` | **Don't swap.** `marked` would not go away; it would move inside the editor bundle at an older major, which is the coupling the "own bundle script" gotcha exists to prevent. What the package does add is the reverse direction, document to Markdown. If you want Copy as Markdown or a Markdown export, this is the reason to add it, as a feature |
| **Replace `TrailingParagraph` with `TrailingNode`** | Options are `node` and `notAfter`. It inserts after every last node except those listed, always at `doc.content.size` | **Keep yours.** Quill wants the opposite default (only after table, gallery, embed, passthrough, rule) and inserts before the footnotes list, which `TrailingNode` cannot do. Twenty lines of your own code beat a configuration that fights the extension |
| **Drop the code mark's `excludes` override** | v3 still sets `excludes: "_"` | **Still needed.** No change |
| **Use v3's image `resize` option or core's `ResizableNodeView`** | Both exist. `ImageNodeView` also owns the caption `contentDOM`, the frame, the toolbar hand-off and the `stopEvent` rules | **Probably not.** The resize handles are the small part of that class, and about ten documented gotchas live in the rest. Worth a look only if resize itself starts misbehaving in a future WebKit |
| **Use `@tiptap/extension-drag-handle` for the grip** | MIT in v3, positioned with Floating UI instead of tippy. cpoteet/Quill#23 recorded that only the 3.x version has a `nested` option | **The most interesting one.** `block-grip.js` moves top-level blocks only. If you want to drag a paragraph within or out of a column or group, v3's handle is the starting point. It would not replace the WebKit workarounds in the grip (empty pasteboard, edge autoscroll, ⌘ for sections); those would need re-proving on top of it. Not checked: whether it still imports the collaboration packages |
| **Table: stop stripping default `colspan`/`rowspan`** | v3 no longer renders them | **Leave the strip.** Pasted and classic markup can still carry them |
| **`onDelete` event for `FootnoteSync`** | The event exists in v3 core | **Unverified.** `FootnoteSync` rebuilds the list in `appendTransaction`, which must stay in the same transaction for undo. An event that fires afterwards likely cannot replace it |
| **`@tiptap/extension-details`** | MIT in v3 | **No.** `DetailsBlock` writes Gutenberg's exact shape, and the stock extension does not |
| **Plain-text numbered lists paste as a list** | Found during Task 4: v3's `OrderedList` adds a `handlePaste` plugin that turns `1. a` / `2. b` plain text into an ordered list. Turned off in the migration (`addProseMirrorPlugins() { return [] }`) | **Worth considering.** It is a small user-facing win. Taking it means deleting that override, changing the characterization test, and proving it in the real-WebKit paste harness, since WKWebView rewrites the clipboard first |

What actually makes the migration worth doing is not on this list: v3 is the line that receives ProseMirror updates, and `prosemirror-view` is where WebKit input and selection fixes land. v2 had two releases in 2026, one of them a security backport.
