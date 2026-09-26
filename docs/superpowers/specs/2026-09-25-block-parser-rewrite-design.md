# Replacing the GPL block parser

_Design, 2026-09-25. Replaces the parser that unsupported-block preservation (`2026-09-12-unsupported-block-preservation-design.md`) depends on._

## Problem

`block-parser-bundle.js` is `@wordpress/block-serialization-default-parser`, licensed GPL-2.0-or-later, bundled into Quill.app. Quill is distributed under an EULA that forbids modification, redistribution and derivative works. The GPL requires a distributed program that includes GPL code to be offered on GPL terms, so shipping the bundle puts the EULA and the parser's license in conflict. Every other bundled dependency (Tiptap, ProseMirror, Marked, SQLite.swift) is MIT, which imposes only a notice requirement.

`editor-transforms.js` also carries `BLOCK_DELIMITER`, a copy of that parser's delimiter pattern, used by `topLevelBlockRanges` to recover the byte offsets the parser does not report.

## Goals

1. Quill ships no GPL code: the bundle, its build script and the copied pattern are gone.
2. Quill's own parser returns the same block tree WordPress's does, except in the one case named below.
3. Every preserved block's stored source is the original text, taken by position. A block left unclosed at the end of a post also gets the closing comment it is missing.
4. Nothing an author sees changes: loading, saving and the blocks-at-risk banner behave as they do today.

Non-goals: changing which blocks Quill models, changing the save path (`toWordPressHTML`), and releases already shipped.

## Compatibility with WordPress

WordPress defines correct. The parser reads WordPress's documented block format, and the comparison test (below) runs WordPress's own parser beside it and fails on any difference in output apart from the one named below. Any ambiguity in the format is settled by measuring WordPress, not by judgement.

What the parser does not reuse is WordPress's code. The GPL covers the implementation, not the format, so a translation of WordPress's parser would carry the license problem this work removes. The implementation is written from the format and the measured behaviour, without consulting the GPL source, and is built differently: a hand-written scanner, where WordPress's parser is built around one large regular expression. It was written by a model that has likely seen WordPress's source in training, so this is not a clean-room process in the strict sense; it is an independent implementation that is not a copy.

## The parser

**File:** `Sources/QuillKit/Resources/block-parser.js`. One top-level `function parseBlocks(html)` declaration, so it reaches `window` from `editor.html` (a top-level `const` would not; see CLAUDE.md). It exports `{ parseBlocks }` under CommonJS the same way `block-serializer.js` does, so the Node suites load it either by `require` or by `new Function`.

**Output:** an array of blocks, each `{ blockName, attrs, innerBlocks, innerHTML, innerContent, start, end }`, plus `closed: false` on a block the parser had to close at the end of the document.

- `blockName`: `namespace/name`, with `core/` supplied when the comment has no namespace. `null` for freeform text.
- `attrs`: the parsed attribute object; `{}` when the comment has none; `null` when the attribute text is not valid JSON.
- `innerHTML`: the block's own HTML with its inner blocks removed.
- `innerContent`: the block's own HTML split at each inner block, with `null` marking where each inner block sits.
- `start`, `end`: character offsets into the input. A named block runs from the start of its opening comment to the end of its closing comment (or to the end of the input when unclosed). A freeform block covers its text. Every block at every depth carries them.

**Recognising a block comment.** At each `<!--`, the scanner accepts a block comment only if the text continues with, in order:

1. one or more whitespace characters
2. an optional `/` (a closing comment)
3. `wp:`
4. an optional namespace: a lowercase letter, then lowercase letters, digits, `_` or `-`, then `/`
5. a name in the same character set
6. one or more whitespace characters
7. optionally, attributes: `{` through the first `}` that is followed by whitespace and then `-->` or `/-->`, then that whitespace
8. an optional `/` (a self-closing comment)
9. `-->`

Anything else at a `<!--` is ordinary text. So `<!--wp:a /-->` (no space), `<!-- wp:A /-->` (uppercase) and `<!-- wp:a [1] /-->` (not an object) are text.

**Building the tree.** A stack of open blocks.

| Token | Effect |
|---|---|
| Opening comment | Pushes a block. |
| Self-closing comment | Adds a block with empty `innerHTML` and `innerContent: []`. |
| Closing comment, stack not empty | Closes the innermost open block, whatever name the closing comment carries. Attributes on a closing comment are ignored. |
| Closing comment, stack empty | Everything from this comment to the end of the input becomes one freeform block, including any later valid blocks. |
| Text at the top level | A freeform block, including whitespace-only text between blocks. |
| Text inside a block | Appended to that block's `innerHTML` and `innerContent`. |
| End of input, blocks still open | Each is closed at the end of the input and marked `closed: false`. |

An empty input returns `[]`. A block with nothing between its opening and closing comments has `innerHTML: ''` and `innerContent: []`.

**The one deliberate difference from WordPress.** When two or more blocks are still open at the end of the input, WordPress returns the inner block as a top-level block and then the outer block with the inner block's text repeated in its `innerHTML`, so that text appears twice. Quill's parser closes them in nesting order instead: the outer block contains the inner one, and no text is repeated. With exactly one block open at the end, the two parsers agree.

**Guarantee:** the top-level blocks' ranges cover the input with no gaps and no overlaps, so `blocks.map(b => html.slice(b.start, b.end)).join('')` equals the input for every input.

## Changes around the parser

**`blockSourceSlices(html, parse)`** in `editor-transforms.js` returns one slice per top-level block:

```js
{ blockName, attrsJSON, source }
```

`source` is `html.slice(block.start, block.end)`, followed, for a block marked `closed: false`, by a closing comment for it and for each unclosed block along its last-child chain, innermost first, written as `<!-- /wp:NAME -->` with `shortBlockName`. So `<!-- wp:group -->\n<div class="wp-block-group">unclosed` is stored as that text plus `<!-- /wp:group -->`, the same result the current reconstruction produces, reached without rebuilding the block. `attrsJSON` is unchanged (`JSON.stringify(block.attrs)` when non-empty, otherwise `null`).

**Removed from `editor-transforms.js`:** `BLOCK_DELIMITER`, `topLevelBlockRanges`, the reconstruction fallback and its cursor walk, and the `exact` field, which nothing outside the tests reads.

**Signatures:** `blockSourceSlices(html, parse)` and `wrapUnsupportedBlocks(html, parse, doc)` lose their `serializeBlock` parameter. `parse` stays injected.

**`editor.html`:** the `<script>` tag loads `block-parser.js` in place of `block-parser-bundle.js`, and the three `BlockParser.parse` call sites (`_wrapIncoming`, `_accountedBlockCounts`, `_reportBlocksAtRisk`) call `parseBlocks`. `block-serializer.js` stays loaded: `toWordPressHTML` uses `serializeAttributes` and `countBlockNames` uses `shortBlockName`.

**`build.sh`:** its `cp` line copies `block-parser.js` in place of the bundle. A missing line passes every test and fails only in the running app (CLAUDE.md gotcha).

**Deleted:** `Sources/QuillKit/Resources/block-parser-bundle.js`, `Scripts/bundle-block-parser.sh`.

## Testing

**New suite: `Scripts/test-block-parser.js`**, plain Node, added to `test.sh`.

- **Comparison with WordPress.** For each input, `parseBlocks` must deep-equal the reference parser's output once `start`, `end` and `closed` are removed. Inputs:
  - every `*.html` in `Scripts/fixtures/` and `Scripts/fixtures/ai/`
  - the edge cases measured on 2026-09-25: whitespace between blocks, leading and trailing text, invalid attribute JSON, one unclosed block, a stray closing comment before a valid block, a closing comment with the wrong name, text around a nested block, `<!--wp:` with no space, an uppercase name, a namespaced name with `-` and `_`, `}  -->` inside an attribute string, attributes spanning lines, attributes on a closing comment, a closing comment after a self-closing block, the empty input, an empty block, an array in place of attributes
  - about 2,000 inputs from a seeded generator built from openers, closers and self-closing comments with varied names, valid and invalid attributes, attributes containing `}` and `-->`, near-miss comments, text and whitespace. The generator tracks the nesting depth it emits and skips inputs that end with two or more blocks open.
- **The deliberate difference:** `<!-- wp:a --><!-- wp:b --><p>x` returns one top-level `core/a` holding `core/b`, both `closed: false`, with `<p>x` appearing once.
- **Coverage:** for every input above, the top-level slices join back into the input.
- **Positions:** each named block's range starts with its opening comment and, when closed, ends with its closing comment; each inner block's range lies within its parent's.

**`Scripts/test-block-serializer.js`:** loads `block-parser.js` instead of the bundle; the `blockSourceSlices` tests drop the `exact` assertions and the serializer argument; the unclosed-block test keeps its expected output.

**`Scripts/test-editor-preservation.js`:** checks `window.parseBlocks` instead of `window.BlockParser.parse`.

**Reference parser:** `@wordpress/block-serialization-default-parser` pinned at `5.55.0` in `Scripts/package.json` `devDependencies`. It is installed today only as a dependency of `@wordpress/blocks`. It is a test tool and never ships.

**Verification before sign-off:**

1. `./test.sh`
2. `./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"` on a current build
3. In the running app, on a new local draft: paste `Scripts/fixtures/unsupported-blocks.html` through code view, edit a paragraph, save, and confirm the saved HTML in SQLite holds every unsupported block byte for byte

## Docs

- `CLAUDE.md`: the Resources line names `block-parser.js`; correct the claim that `Scripts/package.json` is gitignored (only `Scripts/node_modules/` is).
- `docs/testing-plan.md`: the new suite, and corrected counts for every suite touched.
- `docs/gotchas.md`: the bundle-script entry no longer covers the parser.
