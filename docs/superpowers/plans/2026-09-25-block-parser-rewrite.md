# Block Parser Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bundled GPL WordPress block parser with Quill's own `parseBlocks`, which reports block positions, and use those positions to cut preserved-block source directly.

**Architecture:** A hand-written scanner plus a stack in `block-parser.js` produces WordPress's block tree with `start`/`end` offsets. A comparison suite holds it to WordPress's parser, pinned as a test-only dependency. `blockSourceSlices` then slices by position, and the rescan, the copied delimiter pattern and the reconstruction fallback are deleted.

**Tech Stack:** Plain JavaScript loaded as a classic script in `editor.html` and via CommonJS in Node; `node:test`; jsdom for the editor suites.

**Spec:** `docs/superpowers/specs/2026-09-25-block-parser-rewrite-design.md`. Read it first. It holds the delimiter grammar, the tree-building table and the one deliberate difference from WordPress.

## Global Constraints

- The parser is written from the spec's grammar and measured behaviour. Do not open, read or paste the source of `@wordpress/block-serialization-default-parser`. It is used only as a black box in tests.
- `parseBlocks` is a top-level `function` declaration, never a `const`. See the CLAUDE.md gotcha on `window` reachability.
- Every new or renamed file under `Sources/QuillKit/Resources/` needs its own `cp` line in `build.sh`.
- Reference parser: `@wordpress/block-serialization-default-parser` at exactly `5.55.0`, in `Scripts/package.json` `devDependencies`. It never ships.
- Comments: none by default. One line at most, and never narrating the change (user's CLAUDE.md).
- After any code change, rebuild and relaunch with the command in the root CLAUDE.md. Do not commit unless the user asks. The commit steps below are the points to offer a commit.

## Review Focus

1. **Non-ASCII text.** Emoji (surrogate pairs), CJK and accented text inside and between blocks: offsets are UTF-16 indices, so slices must still join back into the input exactly. Test in Task 1.
2. **Whitespace variants in delimiters.** Tabs, `\r\n` and multiple spaces where the grammar says "whitespace", as in `<!--\twp:a\r\n/-->`. These must match WordPress. Test in Task 1 (edge cases).
3. **Delimiter-shaped text inside content.** `<!-- wp:a /-->` inside a `<script>` or an attribute value in a Custom HTML block is read as a delimiter, as WordPress reads it. Test in Task 1 (edge cases).
4. **Pathological input size.** 5,000 repetitions of `<!-- wp:a {` with no closing `}` must parse in under 1 second, so a malformed paste cannot hang the editor. Test in Task 1.
5. **Nested unclosed blocks through preservation.** `<!-- wp:group --><!-- wp:acme/x -->t` must be stored as the original text plus `<!-- /wp:acme/x --><!-- /wp:group -->`, with the namespace kept on the third-party name. Test in Task 2.

---

### Task 1: The parser and its comparison suite

**Files:**
- Create: `Sources/QuillKit/Resources/block-parser.js`
- Create: `Scripts/test-block-parser.js`
- Modify: `Scripts/package.json` (add the reference parser to `devDependencies`)
- Modify: `test.sh` (a `run "JS block parser tests"  node --test Scripts/test-block-parser.js` line directly above the serializer line)
- Modify: `docs/testing-plan.md` (a section for the new suite in the established format; the header totals and the numbered `test.sh` list)
- Modify: `docs/wordpress-release-audit.md` (a new step 6 under **Steps**, renumbering the rest: in `Scripts/`, run `npm install --save-dev --save-exact @wordpress/block-serialization-default-parser@latest`, then `node --test Scripts/test-block-parser.js`. A failure means WordPress changed how it reads block comments, and the failing input shows where)

**Interfaces:**
- Produces: `parseBlocks(html: string) → Block[]`, where `Block = { blockName: string|null, attrs: object|null, innerBlocks: Block[], innerHTML: string, innerContent: (string|null)[], start: number, end: number, closed?: false }`. `closed` is present only as `false`, on blocks closed at the end of the input. Under CommonJS: `module.exports = { parseBlocks }`, guarded by `typeof module !== 'undefined' && module.exports`, as in `block-serializer.js`.

- [ ] **Step 1: Pin the reference parser.** In `Scripts/`, run `npm install --save-dev --save-exact @wordpress/block-serialization-default-parser@5.55.0`. Check: `node -p "require('@wordpress/block-serialization-default-parser/package.json').version"` in `Scripts/` prints `5.55.0`.

- [ ] **Step 2: Write the failing suite `Scripts/test-block-parser.js`.** It loads `parseBlocks` with `require('../Sources/QuillKit/Resources/block-parser.js')` and the reference with `require('@wordpress/block-serialization-default-parser').parse`. Helpers: `strip(blocks)` deep-copies a tree, removing `start`, `end` and `closed` at every depth; `slices(html, blocks)` returns `blocks.map(b => html.slice(b.start, b.end))`.

  - `describe('matches WordPress')`, one test per input: `assert.deepEqual(strip(parseBlocks(src)), reference(src))`. Inputs:
    - every `*.html` in `Scripts/fixtures/` and `Scripts/fixtures/ai/` (33 today)
    - the spec's edge-case list, each as a named test; the exact strings are in the table below
    - Review Focus 2 and 3: `'<!--\twp:a\r\n/-->'`, `'<!-- wp:a  {"x":1}   /-->'`, `'<!-- wp:html --><script>"<!-- wp:a /-->"</script><!-- /wp:html -->'`, `'<p title="<!-- wp:a /-->">x</p>'`
  - `test('matches WordPress on 2,000 generated inputs')`: a seeded `mulberry32(20260925)` PRNG builds each input from 0–12 pieces drawn from:
    - names `a`, `b`, `core/c`, `acme/w-x_1`, `A`
    - attributes `''`, `'{"x":1}'`, `'{"x":}'`, `'{"s":"}  -->"}'`, `'{\n"y":2\n}'`, `'[1]'`
    - forms: opener, closer, self-closing
    - near-misses `'<!--wp:a -->'`, `'<!-- wp:a-->'`, `'<!-- -->'`, `'<!-- wp: -->'`
    - text `'<p>t</p>'`, `'x'`, `'  '`, `'\n\n'`, `'}'`, `' -->'`, `'é😀'`

    Skip an input when `parseBlocks` marks two or more blocks `closed: false`. Assert on each compared input and include the input in the failure message. After the loop, `assert.ok(skipped < 500)`.
  - `test('two unclosed blocks nest instead of repeating text')`: for `'<!-- wp:a --><!-- wp:b --><p>x'`, the result has length 1 with `blockName 'core/a'` and `closed false`; its `innerBlocks[0]` has `blockName 'core/b'`, `closed false` and `innerHTML '<p>x'`; the outer `innerContent` is `[null]` and its `innerHTML` is `''` (WordPress's shape for the closed form, measured 2026-09-25: empty text around an inner block is never recorded); `JSON.stringify(result)` contains `<p>x` exactly once.
  - `test('top-level slices join back into the input')`, run over every input above, including the generated ones: `assert.equal(slices(src, parseBlocks(src)).join(''), src)`.
  - `test('positions frame each block')`, over the same inputs, at every depth:
    - a named block's slice starts with `'<!--'`
    - a named block without `closed: false` has a slice ending with `'-->'`
    - an inner block's `[start, end]` lies within its parent's
    - a top-level freeform block's slice equals its `innerHTML`
  - `test('non-ASCII text keeps exact offsets')`: `'é<!-- wp:a -->😀字<!-- /wp:a -->😀'` gives slices `['é', '<!-- wp:a -->😀字<!-- /wp:a -->', '😀']`.
  - `test('a long run of unterminated attributes parses in under a second')`: `'<!-- wp:a {'.repeat(5000)` finishes in under 1000 ms.

  Edge-case strings:

  | Test name | Input |
  |---|---|
  | whitespace between blocks | `'<!-- wp:a /-->\n\n<!-- wp:b /-->'` |
  | leading and trailing text | `'  <!-- wp:a /-->  '` |
  | invalid attribute JSON | `'<!-- wp:a {"x":} /-->'` |
  | one unclosed block | `'<!-- wp:a --><p>x'` |
  | stray closer before a valid block | `'<p>A</p><!-- /wp:a --><p>B</p><!-- wp:c /-->'` |
  | closer with the wrong name | `'<!-- wp:a -->x<!-- /wp:b -->y'` |
  | text around a nested block | `'<!-- wp:a -->1<!-- wp:b -->2<!-- /wp:b -->3<!-- /wp:a -->'` |
  | no space after `<!--` | `'<!--wp:a /-->'` |
  | uppercase name | `'<!-- wp:A /-->'` |
  | namespaced name | `'<!-- wp:acme/w-x_1 /-->'` |
  | `}  -->` inside an attribute string | `'<!-- wp:a {"s":"}  -->"} /-->'` |
  | attributes spanning lines | `'<!-- wp:a {\n"x":1\n} /-->'` |
  | attributes on a closer | `'<!-- wp:a -->x<!-- /wp:a {"y":1} -->'` |
  | closer after a self-closing block | `'<!-- wp:a /-->x<!-- /wp:a -->'` |
  | empty input | `''` |
  | empty block | `'<!-- wp:a --><!-- /wp:a -->'` |
  | array in place of attributes | `'<!-- wp:a [1] /-->'` |

- [ ] **Step 3: Run it to see it fail.** Run `node --test Scripts/test-block-parser.js`. Expected: fails with `Cannot find module '../Sources/QuillKit/Resources/block-parser.js'`.

- [ ] **Step 4: Implement `parseBlocks(html)` in `Sources/QuillKit/Resources/block-parser.js`.** The spec's "Recognising a block comment" list and "Building the tree" table determine the behaviour. Structure:
  - a scanner that, from a position, finds the next `<!--` and either returns a token `{ kind: 'open'|'close'|'void', blockName, attrs, start, end }` or moves past it by one character when the text there does not fit the grammar
  - a loop that feeds tokens to a stack

  Attribute text runs from `{` to the first `}` followed by whitespace and then `-->` or `/-->`. Parse it with `JSON.parse` in a `try`, with `null` on failure. To keep Review Focus 4 linear, find that terminator with one forward search per `<!--`, and stop scanning for attributes once no terminator remains after the current position (remember that fact rather than re-searching).

- [ ] **Step 5: Run it to see it pass.** Run `node --test Scripts/test-block-parser.js`. Expected: every test passes, with 0 failures. If a comparison fails, the difference is WordPress's behaviour; change the parser, not the test.

- [ ] **Step 6: Wire it into the test runner and docs.** Add the `test.sh` line, the `testing-plan.md` section and counts, and the audit step listed under **Files**. Then run `./test.sh`. Expected: `✓ All test suites passed`, with one more suite than before.

- [ ] **Step 7: Offer a commit:** `feat: add Quill's own block parser, checked against WordPress's`.

---

### Task 2: Slice by position and remove the GPL parser

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js`:
  - delete `BLOCK_DELIMITER`, `topLevelBlockRanges` and the comment block above them (about lines 250–289)
  - rewrite `blockSourceSlices` (about line 291)
  - change `wrapUnsupportedBlocks` (about line 374)
- Modify: `Sources/QuillKit/Resources/editor.html`:
  - script tag, line 1559
  - `_wrapIncoming`, line 5515
  - `_accountedBlockCounts`, line 5528
  - `_reportBlocksAtRisk`, line 5548
- Modify: `build.sh:44`
- Delete: `Sources/QuillKit/Resources/block-parser-bundle.js`, `Scripts/bundle-block-parser.sh`
- Test: `Scripts/test-block-serializer.js`, `Scripts/test-editor-preservation.js`
- Docs:
  - `CLAUDE.md`: in the Resources line, name `block-parser.js`; in Requirements, change "`Scripts/package.json`, gitignored" to say only `Scripts/node_modules/` is ignored
  - `docs/gotchas.md`: remove `block-parser-bundle.js` from the `build.sh` list on line 17 and add `block-parser.js`; remove the `bundle-block-parser.sh` example from line 19
  - `docs/testing-plan.md`: counts and descriptions for the two suites touched

**Interfaces:**
- Consumes: `parseBlocks` (Task 1), and `shortBlockName(blockName)` already in `editor-transforms.js:53`.
- Produces: `blockSourceSlices(html, parse) → { blockName: string|null, attrsJSON: string|null, source: string }[]` and `wrapUnsupportedBlocks(html, parse, doc) → string`. Both drop the `serializeBlock` parameter, and slices no longer carry `exact`.

- [ ] **Step 1: Update the tests to the new interface.**
  - **`test-block-serializer.js`:** `loadParser()` returns `require('../Sources/QuillKit/Resources/block-parser.js')`, and `loadParser().parse` becomes `parseBlocks` throughout. Remove the `serializeBlock` argument from every `blockSourceSlices` and `wrapUnsupportedBlocks` call, and every `exact` assertion. In the fixture sweep, keep the join assertion. The unclosed-block test keeps `assert.equal(out[0].source, src + '<!-- /wp:group -->')` and is renamed `an unclosed block keeps its text and gains its closing comment`. Rename the `describe('block parser bundle')` block to `describe('block parser')`.
  - **Add** `test('nested unclosed blocks gain closers innermost first')` (Review Focus 5): `blockSourceSlices('<!-- wp:group --><!-- wp:acme/x -->t', parseBlocks)` has one slice whose `source` is the input plus `'<!-- /wp:acme/x --><!-- /wp:group -->'`.
  - **`test-editor-preservation.js`:** the first test becomes `window.parseBlocks is callable`, asserting on `win.parseBlocks(...)`, and the second calls `win.parseBlocks` in place of `win.BlockParser.parse`.

- [ ] **Step 2: Run them to see them fail.**
  - `node --test Scripts/test-block-serializer.js`. Expected: fails on the nested-closers test, whose second closer is missing.
  - `node --test Scripts/test-editor-preservation.js`. Expected: fails with `win.parseBlocks is not a function`.

- [ ] **Step 3: Rewrite `blockSourceSlices(html, parse)`.**
  - Each top-level block gives `source = html.slice(block.start, block.end) + missingClosers(block)`.
  - `missingClosers(block)` follows the chain of `closed === false` blocks from `block` through each `innerBlocks` last element, and returns `<!-- /wp:${shortBlockName(name)} -->` for each, innermost first.
  - `attrsJSON` keeps its current rule.
  - Delete `BLOCK_DELIMITER`, `topLevelBlockRanges` and the reconstruction branch.
  - `wrapUnsupportedBlocks(html, parse, doc)` passes `parse` through.

- [ ] **Step 4: Switch `editor.html` and `build.sh`.**
  - The script tag becomes `<script src="./block-parser.js"></script>`.
  - The three call sites call `parseBlocks`, and `_wrapIncoming` becomes `wrapUnsupportedBlocks(html, parseBlocks, document)`.
  - `build.sh:44` becomes `cp "Sources/QuillKit/Resources/block-parser.js" "$RESOURCES_DIR/block-parser.js"`.
  - Delete the bundle and its script.
  - Check: `grep -rn "BlockParser\|block-parser-bundle\|bundle-block-parser\|BLOCK_DELIMITER\|topLevelBlockRanges" Sources Scripts/*.js Scripts/*.sh build.sh test.sh CLAUDE.md docs/gotchas.md docs/testing-plan.md` prints nothing. Older specs and plans under `docs/superpowers/` are history and stay as they are.

- [ ] **Step 5: Run the full suite.** Run `./test.sh`. Expected: `✓ All test suites passed`.

- [ ] **Step 6: Build and check in real WebKit.** Run the root CLAUDE.md build-and-run command, then `./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"`. Expected: every fixture passes. A failure here, with `./test.sh` green, most likely means a missing `cp` line or a `const` where a `function` was needed.

- [ ] **Step 7: Check in the running app.**
  1. In the running dev build, click "+ New Post".
  2. Open code view and paste `Scripts/fixtures/unsupported-blocks.html`.
  3. Leave code view, edit a paragraph, then Save Draft.
  4. Run the SQLite query from the `docs/gotchas.md` "Verify saved draft HTML straight from SQLite" entry.

  Expected: every one of the fixture's eight unsupported blocks appears in the saved content byte for byte, and no blocks-at-risk banner showed. Discard the draft.

- [ ] **Step 8: Update the docs listed under Files,** then re-run `./test.sh` if any count was re-measured.

- [ ] **Step 9: Offer a commit:** `refactor: slice preserved blocks by position and drop the GPL parser`.
