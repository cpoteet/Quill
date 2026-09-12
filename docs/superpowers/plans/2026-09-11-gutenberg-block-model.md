# Gutenberg Block Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Gutenberg block tree Quill's source of truth, so newly written posts save as real blocks instead of Classic content, and Columns / Accordion / Tabs / Details / Buttons become editable.

**Architecture:** Today `post_content` → Tiptap → `post_content` with block comments re-synthesized by regex. This inverts it: `post_content` is parsed into a block tree by WordPress's own standalone parser, the tree is the source of truth, and Tiptap is a view onto it. Delimiters and attributes are emitted because the tree holds them. New editable blocks are declared as descriptors against one of four shapes rather than implemented as bespoke Tiptap nodes.

**Tech Stack:** `@wordpress/block-serialization-default-parser` (dependency-free, no React), esbuild IIFE bundling, Tiptap 2.x, jsdom + `node --test`, Swift 6 / SwiftUI.

**Spec:** [`docs/superpowers/specs/2026-09-11-gutenberg-block-model-design.md`](../specs/2026-09-11-gutenberg-block-model-design.md)

**Branch:** `gutenberg-block-model`

## Global Constraints

- **Round-trip byte-identity outranks every feature.** A post loaded and saved with no edits must produce byte-identical `post_content`. Any task that breaks this is rejected regardless of what else it delivers.
- **Existing posts are never rewritten.** Classic posts written by older Quill are out of scope: they render correctly and stay as they are. Nothing in this plan converts, migrates, or touches already-published content.
- **`build.sh` copies each resource by name.** Every new file in `Sources/QuillKit/Resources/` needs its own `cp` line in `build.sh` (lines 29-33) or it 404s at runtime while Swift builds fine and jsdom tests pass. This has bitten this codebase before.
- **New JS dependencies get their own bundle script.** Never edit `Scripts/bundle-tiptap.sh` — its `"^2"` pin re-resolves Tiptap on every run and can drift the editor onto a newer release.
- **Comment-stripping regexes use `[\s\S]*?`, never `.*?` or `[^\n]*`.** JS `.` excludes all line terminators; greedy classes span multiple comments. Both failure modes have shipped as silent data-loss bugs in this file.
- **Never use curly quotes inside Swift string literals with interpolation.** Swift treats U+201C/U+201D as string delimiters.
- **After every code change:** quit the app, run `./build.sh`, reopen. `build.sh` replaces the binary under a running process.
- **Comments:** default to none. One line maximum where naming cannot carry the meaning. No narration of changes.

## File Structure

**New:**

| File | Responsibility |
|---|---|
| `Scripts/bundle-block-parser.sh` | Bundles the WP parser to an IIFE. Run once per dependency bump, not per build. |
| `Sources/QuillKit/Resources/block-parser-bundle.js` | Generated. Exposes `window.BlockParser.parse`. |
| `Sources/QuillKit/Resources/block-serializer.js` | Tree → `post_content`. Pure, no DOM. |
| `Sources/QuillKit/Resources/block-descriptors.js` | The descriptor registry and shape definitions. |
| `Scripts/fixtures/` | Real `post_content` samples used by the round-trip corpus. |
| `Scripts/test-block-serializer.js` | Parse/serialize round-trip corpus. |
| `Scripts/test-editor-containers.js` | Live-Tiptap container block behavior. |

**Modified:**

| File | Change |
|---|---|
| `Sources/QuillKit/Resources/editor.html` | Container nodes, insert menu, `getContent` wiring |
| `Sources/QuillKit/Resources/editor-transforms.js` | `toWordPressHTML` gains a DOM-level delimiter pass; its existing image/gallery/embed wrapping is left alone |
| `build.sh` | `cp` lines for the four new resource files |

Serializer and descriptors are separate files because they have genuinely separate responsibilities and each is independently testable without a DOM. `editor.html` is already 3,600 lines; nothing that can live outside it should go into it.

---

## Phase 1 — Parser and serializer foundation

No user-visible change. Ends with a proven lossless round-trip.

### Task 1: Bundle the WordPress block parser

**Files:**
- Create: `Scripts/bundle-block-parser.sh`
- Create (generated): `Sources/QuillKit/Resources/block-parser-bundle.js`
- Modify: `build.sh:33`
- Modify: `Sources/QuillKit/Resources/editor.html` (script tag)
- Test: `Scripts/test-block-serializer.js`

**Interfaces:**
- Consumes: nothing
- Produces: `window.BlockParser.parse(html)` → `Array<{blockName: string|null, attrs: object, innerBlocks: Array, innerHTML: string, innerContent: Array<string|null>}>`

- [x] **Step 1: Write the bundle script**

```bash
#!/usr/bin/env bash
# Bundle WordPress's standalone block parser into a local IIFE (window.BlockParser).
# Separate from bundle-tiptap.sh so a parser bump never drifts the editor's Tiptap version.
#
# Usage: ./Scripts/bundle-block-parser.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUT="$ROOT_DIR/Sources/QuillKit/Resources/block-parser-bundle.js"
TMP_DIR="$(mktemp -d)"

echo "▶ Installing @wordpress/block-serialization-default-parser..."
cd "$TMP_DIR"
cat > package.json <<'EOF'
{
  "name": "block-parser-bundler",
  "private": true,
  "type": "module",
  "dependencies": {
    "@wordpress/block-serialization-default-parser": "^5",
    "esbuild": "^0.25"
  }
}
EOF

npm install --silent

cat > entry.js <<'EOF'
export { parse } from '@wordpress/block-serialization-default-parser'
EOF

echo "▶ Bundling..."
./node_modules/.bin/esbuild entry.js \
  --bundle \
  --format=iife \
  --global-name=BlockParser \
  --minify \
  --outfile="$OUT"

echo "▶ Cleaning up..."
cd /
rm -rf "$TMP_DIR"

SIZE=$(du -sh "$OUT" | cut -f1)
echo "✓ Bundle written to Sources/QuillKit/Resources/block-parser-bundle.js ($SIZE)"
echo "  Rebuild the app to pick up the new bundle."
```

- [x] **Step 2: Run it**

```bash
chmod +x Scripts/bundle-block-parser.sh && ./Scripts/bundle-block-parser.sh
```

Expected: a bundle well under 100 KB. If it is megabytes, the wrong package was pulled — this parser has no dependencies.

- [x] **Step 3: Add the build.sh copy line**

Immediately after line 33 in `build.sh`:

```bash
cp "Sources/QuillKit/Resources/block-parser-bundle.js" "$RESOURCES_DIR/block-parser-bundle.js"
```

- [x] **Step 4: Load it in editor.html**

Next to the existing `editor-transforms.js` tag, before the main editor script block:

```html
<script src="./block-parser-bundle.js"></script>
```

- [x] **Step 5: Write the smoke test**

Create `Scripts/test-block-serializer.js`:

```js
'use strict'

const { test, describe } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('fs')
const path = require('path')

const bundlePath = path.resolve(__dirname, '../Sources/QuillKit/Resources/block-parser-bundle.js')

function loadParser() {
  const src = fs.readFileSync(bundlePath, 'utf8')
  const sandbox = {}
  new Function('window', src + '\nwindow.BlockParser = BlockParser')(sandbox)
  return sandbox.BlockParser
}

describe('block parser bundle', () => {
  test('parses a delimited paragraph', () => {
    const blocks = loadParser().parse('<!-- wp:paragraph --><p>Hi</p><!-- /wp:paragraph -->')
    const real = blocks.filter(b => b.blockName)
    assert.equal(real.length, 1)
    assert.equal(real[0].blockName, 'core/paragraph')
    assert.equal(real[0].innerHTML.trim(), '<p>Hi</p>')
  })

  test('parses undelimited HTML as a freeform block', () => {
    const blocks = loadParser().parse('<p>Classic</p>')
    assert.equal(blocks.length, 1)
    assert.equal(blocks[0].blockName, null)
  })
})
```

- [x] **Step 6: Run it**

```bash
node --test Scripts/test-block-serializer.js
```

Expected: 2 passing.

- [x] **Step 7: Commit**

```bash
git add Scripts/bundle-block-parser.sh Sources/QuillKit/Resources/block-parser-bundle.js build.sh Sources/QuillKit/Resources/editor.html Scripts/test-block-serializer.js
git commit -m "feat: bundle the WordPress block parser

Adds @wordpress/block-serialization-default-parser as a local IIFE via its own
bundle script, following the marked-bundle.sh pattern so parser updates never
force a Tiptap upgrade. No behavior change yet; nothing calls it.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: The serializer

**Files:**
- Create: `Sources/QuillKit/Resources/block-serializer.js`
- Modify: `build.sh` (new `cp` line)
- Modify: `Sources/QuillKit/Resources/editor.html` (script tag)
- Test: `Scripts/test-block-serializer.js`

**Interfaces:**
- Consumes: `window.BlockParser.parse` from Task 1
- Produces: `serializeBlocks(blocks)` → string; `serializeBlock(block)` → string. Both exposed as globals from `block-serializer.js`.

- [x] **Step 1: Write the failing tests**

Append to `Scripts/test-block-serializer.js`:

```js
function loadSerializer() {
  const src = fs.readFileSync(
    path.resolve(__dirname, '../Sources/QuillKit/Resources/block-serializer.js'), 'utf8')
  const sandbox = {}
  new Function('module', 'exports', src + '\nmodule.exports = { serializeBlocks, serializeBlock }')(
    sandbox, sandbox)
  return sandbox.exports
}

describe('block serializer', () => {
  const { serializeBlocks } = loadSerializer()
  const parse = loadParser().parse

  test('round-trips a paragraph byte-identically', () => {
    const src = '<!-- wp:paragraph --><p>Hi</p><!-- /wp:paragraph -->'
    assert.equal(serializeBlocks(parse(src)), src)
  })

  test('round-trips attributes without reordering or re-spacing', () => {
    const src = '<!-- wp:heading {"level":3} --><h3>T</h3><!-- /wp:heading -->'
    assert.equal(serializeBlocks(parse(src)), src)
  })

  test('round-trips nested blocks at their innerContent slots', () => {
    const src = '<!-- wp:group --><div class="wp-block-group">' +
      '<!-- wp:paragraph --><p>In</p><!-- /wp:paragraph -->' +
      '</div><!-- /wp:group -->'
    assert.equal(serializeBlocks(parse(src)), src)
  })

  test('passes freeform content through untouched', () => {
    const src = '<p>Classic</p>'
    assert.equal(serializeBlocks(parse(src)), src)
  })

  test('strips the core/ prefix in delimiters', () => {
    const out = serializeBlocks(parse('<!-- wp:separator /-->'))
    assert.match(out, /wp:separator/)
    assert.doesNotMatch(out, /core\//)
  })
})
```

- [x] **Step 2: Run to verify they fail**

```bash
node --test Scripts/test-block-serializer.js
```

Expected: FAIL — `block-serializer.js` does not exist.

- [x] **Step 3: Write the serializer**

Create `Sources/QuillKit/Resources/block-serializer.js`:

```js
'use strict'

// Tree → post_content. The inverse of @wordpress/block-serialization-default-parser.
// Pure string work, no DOM — shared between editor.html and the Node test harness.

function shortBlockName(name) {
  return name.startsWith('core/') ? name.slice(5) : name
}

function serializeBlock(block) {
  const { blockName, attrs, innerBlocks, innerContent } = block
  if (!blockName) return innerContent.join('')

  const name = shortBlockName(blockName)
  const attrsStr = attrs && Object.keys(attrs).length ? ' ' + JSON.stringify(attrs) : ''

  let childIndex = 0
  const inner = innerContent
    .map(chunk => (chunk === null ? serializeBlock(innerBlocks[childIndex++]) : chunk))
    .join('')

  if (inner === '') return `<!-- wp:${name}${attrsStr} /-->`
  return `<!-- wp:${name}${attrsStr} -->${inner}<!-- /wp:${name} -->`
}

function serializeBlocks(blocks) {
  return blocks.map(serializeBlock).join('')
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { serializeBlocks, serializeBlock, shortBlockName }
}
```

- [x] **Step 4: Run to verify they pass**

```bash
node --test Scripts/test-block-serializer.js
```

Expected: 7 passing.

If the attribute test fails on spacing, compare the exact bytes — WordPress emits one space between the name and the JSON and none inside. Do not "fix" it by normalizing the input.

- [x] **Step 5: Add build.sh line and script tag**

In `build.sh`, after the parser bundle line:

```bash
cp "Sources/QuillKit/Resources/block-serializer.js" "$RESOURCES_DIR/block-serializer.js"
```

In `editor.html`, after the parser bundle tag:

```html
<script src="./block-serializer.js"></script>
```

- [x] **Step 6: Commit**

```bash
git add Sources/QuillKit/Resources/block-serializer.js build.sh Sources/QuillKit/Resources/editor.html Scripts/test-block-serializer.js
git commit -m "feat: add the block tree serializer

One generic serializer replaces per-block comment wrapping: delimiters and
attributes come from the tree rather than from regex over an HTML string.
Round-trip tests assert byte-identical output for paragraphs, attributes,
nested blocks and freeform content.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: The round-trip fixture corpus

The single highest-value test in the project. Everything downstream depends on it.

**Files:**
- Create: `Scripts/fixtures/post-17780.html`
- Create: `Scripts/fixtures/gallery-block.html`
- Create: `Scripts/fixtures/accordion-block.html`
- Test: `Scripts/test-block-serializer.js`

**Interfaces:**
- Consumes: `serializeBlocks` (Task 2), `window.BlockParser.parse` (Task 1)
- Produces: a fixtures directory later tasks reuse

- [x] **Step 1: Capture the real post as a fixture**

Save the full `post_content` of post 17780 verbatim to `Scripts/fixtures/post-17780.html`. It is the canonical old-Quill post: classic paragraphs and headings, an un-delimited standalone image carrying `data-media-id`, a correctly delimited gallery, two correctly delimited accordions, and an un-delimited footnotes list.

Fetch it with the WordPress MCP (`wp_get_post` with id 17780) and write the `content` field byte-for-byte. Do not reformat, re-indent, or normalize newlines — the whole point is byte fidelity.

- [x] **Step 2: Extract two focused fixtures**

`Scripts/fixtures/gallery-block.html` — just the `<!-- wp:gallery -->` … `<!-- /wp:gallery -->` span from that post.

`Scripts/fixtures/accordion-block.html` — just the first `<!-- wp:accordion -->` … `<!-- /wp:accordion -->` span.

Both copied verbatim from the same source.

- [x] **Step 3: Write the failing corpus test**

Append to `Scripts/test-block-serializer.js`:

```js
describe('fixture round-trips', () => {
  const { serializeBlocks } = loadSerializer()
  const parse = loadParser().parse
  const fixturesDir = path.resolve(__dirname, 'fixtures')

  for (const name of fs.readdirSync(fixturesDir).filter(f => f.endsWith('.html'))) {
    test(`${name} survives parse → serialize byte-identically`, () => {
      const src = fs.readFileSync(path.join(fixturesDir, name), 'utf8')
      assert.equal(serializeBlocks(parse(src)), src)
    })
  }
})
```

The loop means a new fixture file is automatically covered — dropping a problem post into the directory is how future regressions get pinned.

- [x] **Step 4: Run it**

```bash
node --test Scripts/test-block-serializer.js
```

Expected: PASS for all three fixtures.

A failure here is a real serializer bug, not a fixture problem. Diff the output against the input and fix `block-serializer.js`. Do not edit the fixture to make the test pass.

- [x] **Step 5: Commit**

```bash
git add Scripts/fixtures Scripts/test-block-serializer.js
git commit -m "test: add real post_content round-trip fixtures

Pins byte-identical parse/serialize against a real published post containing
classic prose, a delimited gallery, delimited accordions and an undelimited
image. The fixture loop picks up any new .html dropped into the directory.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Phase 2 — Delimiters for existing blocks

Ends with Quill publishing real blocks instead of Classic content. This is the phase that fixes the user-visible problem.

### Task 4: The descriptor registry

**Files:**
- Create: `Sources/QuillKit/Resources/block-descriptors.js`
- Modify: `build.sh`, `Sources/QuillKit/Resources/editor.html`
- Test: `Scripts/test-block-serializer.js`

**Interfaces:**
- Consumes: nothing
- Produces: `BLOCK_DESCRIPTORS` (object keyed by Tiptap node name), `descriptorFor(nodeName)` → descriptor or `null`

A descriptor is:

```js
{ blockName: 'core/heading', shape: 'text', attrsFrom: (el) => ({...}), childBlockName: null }
```

- [x] **Step 1: Write the failing test**

```js
describe('block descriptors', () => {
  const { descriptorFor } = loadDescriptors()

  test('maps heading to core/heading with its level attribute', () => {
    const d = descriptorFor('heading')
    assert.equal(d.blockName, 'core/heading')
    assert.equal(d.shape, 'text')
    const el = { tagName: 'H3', className: 'wp-block-heading', getAttribute: () => null }
    assert.deepEqual(d.attrsFrom(el), { level: 3 })
  })

  test('maps paragraph to core/paragraph with no attributes', () => {
    const d = descriptorFor('paragraph')
    assert.equal(d.blockName, 'core/paragraph')
    const el = { tagName: 'P', className: '', getAttribute: () => null }
    assert.deepEqual(d.attrsFrom(el), {})
  })

  test('returns null for an unknown node', () => {
    assert.equal(descriptorFor('nonesuch'), null)
  })

  test('level 2 headings emit level 2, not a default', () => {
    const el = { tagName: 'H2', className: '', getAttribute: () => null }
    assert.deepEqual(descriptorFor('heading').attrsFrom(el), { level: 2 })
  })
})
```

Add the loader alongside the others:

```js
function loadDescriptors() {
  const src = fs.readFileSync(
    path.resolve(__dirname, '../Sources/QuillKit/Resources/block-descriptors.js'), 'utf8')
  const sandbox = {}
  new Function('module', 'exports', src + '\nmodule.exports = { BLOCK_DESCRIPTORS, descriptorFor }')(
    sandbox, sandbox)
  return sandbox.exports
}
```

- [x] **Step 2: Run to verify failure**

```bash
node --test Scripts/test-block-serializer.js
```

Expected: FAIL — module not found.

- [x] **Step 3: Write the registry**

Create `Sources/QuillKit/Resources/block-descriptors.js`:

```js
'use strict'

// Maps Tiptap node names to Gutenberg block names, the shape that governs how
// the node projects to and from the block tree, and how block attributes are
// derived from the rendered element.

const BLOCK_DESCRIPTORS = {
  paragraph:   { blockName: 'core/paragraph',    shape: 'text',      childBlockName: null,             attrsFrom: () => ({}) },
  heading:     { blockName: 'core/heading',      shape: 'text',      childBlockName: null,             attrsFrom: el => ({ level: parseInt(el.tagName.slice(1), 10) }) },
  bulletList:  { blockName: 'core/list',         shape: 'container', childBlockName: 'core/list-item', attrsFrom: () => ({}) },
  orderedList: { blockName: 'core/list',         shape: 'container', childBlockName: 'core/list-item', attrsFrom: () => ({ ordered: true }) },
  listItem:    { blockName: 'core/list-item',    shape: 'text',      childBlockName: null,             attrsFrom: () => ({}) },
  blockquote:  { blockName: 'core/quote',        shape: 'text',      childBlockName: null,             attrsFrom: () => ({}) },
  codeBlock:   { blockName: 'core/code',         shape: 'text',      childBlockName: null,             attrsFrom: () => ({}) },
  horizontalRule: { blockName: 'core/separator', shape: 'leaf',      childBlockName: null,             attrsFrom: () => ({}) },
  table:       { blockName: 'core/table',        shape: 'media',     childBlockName: null,             attrsFrom: () => ({}) },
  footnotesList: { blockName: 'core/footnotes',  shape: 'media',     childBlockName: null,             attrsFrom: () => ({}) },
}

function descriptorFor(nodeName) {
  return BLOCK_DESCRIPTORS[nodeName] || null
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { BLOCK_DESCRIPTORS, descriptorFor }
}
```

Image, gallery and embed are deliberately absent — they already emit correct delimiters through `toWordPressHTML` and are not being rewritten in this plan.

- [x] **Step 4: Run to verify pass**

```bash
node --test Scripts/test-block-serializer.js
```

Expected: all passing.

- [x] **Step 5: Add build.sh line and script tag**

```bash
cp "Sources/QuillKit/Resources/block-descriptors.js" "$RESOURCES_DIR/block-descriptors.js"
```

```html
<script src="./block-descriptors.js"></script>
```

- [x] **Step 6: Commit**

```bash
git add Sources/QuillKit/Resources/block-descriptors.js build.sh Sources/QuillKit/Resources/editor.html Scripts/test-block-serializer.js
git commit -m "feat: add the block descriptor registry

Declares the Tiptap-node-to-Gutenberg-block mapping and the shape that governs
each node's projection, so adding a block later is a descriptor rather than a
node implementation.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Emit delimiters on save

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js` (`toWordPressHTML`)
- Test: `Scripts/test-editor.js`

**Interfaces:**
- Consumes: `descriptorFor` (Task 4)
- Produces: `toWordPressHTML` output now carries delimiters for every descriptor-backed block

- [x] **Step 1: Write the failing tests**

Append to `Scripts/test-editor.js`:

```js
describe('block delimiters', () => {
  test('wraps a paragraph in wp:paragraph', () => {
    const out = toWordPressHTML('<p>Hello</p>', document)
    assert.match(out, /<!-- wp:paragraph -->[\s\S]*<p>Hello<\/p>[\s\S]*<!-- \/wp:paragraph -->/)
  })

  test('wraps a heading with its level attribute', () => {
    const out = toWordPressHTML('<h2>Title</h2>', document)
    assert.match(out, /<!-- wp:heading \{"level":2\} -->/)
  })

  test('wraps a list and each of its items', () => {
    const out = toWordPressHTML('<ul><li>One</li></ul>', document)
    assert.match(out, /<!-- wp:list -->/)
    assert.match(out, /<!-- wp:list-item -->/)
  })

  test('does not double-wrap already-delimited content', () => {
    const src = '<!-- wp:paragraph --><p>Hi</p><!-- /wp:paragraph -->'
    const once = toWordPressHTML(src, document)
    assert.equal(toWordPressHTML(once, document), once)
  })

  test('leaves gallery delimiters exactly as they are', () => {
    const src = fs.readFileSync(
      path.resolve(__dirname, 'fixtures/gallery-block.html'), 'utf8')
    const out = toWordPressHTML(src, document)
    assert.equal((out.match(/<!-- wp:gallery/g) || []).length, 1)
  })
})
```

- [x] **Step 2: Run to verify failure**

```bash
node --test Scripts/test-editor.js
```

Expected: FAIL — no delimiters emitted for paragraph/heading/list.

- [x] **Step 3: Add the delimiter pass**

In `editor-transforms.js`, at the end of `toWordPressHTML` — after every existing class-adding pass and after the image/gallery/embed comment wrapping, so those keep ownership of their own blocks:

```js
const NODE_FOR_TAG = {
  P: 'paragraph', H1: 'heading', H2: 'heading', H3: 'heading',
  H4: 'heading', H5: 'heading', H6: 'heading',
  UL: 'bulletList', OL: 'orderedList', LI: 'listItem',
  BLOCKQUOTE: 'blockquote', PRE: 'codeBlock', HR: 'horizontalRule',
}

function wrapInDelimiters(root, doc) {
  Array.from(root.children).forEach(el => {
    if (el.classList.contains('wp-block-footnotes')) return
    const nodeName = NODE_FOR_TAG[el.tagName]
    const descriptor = nodeName ? descriptorFor(nodeName) : null
    if (!descriptor) return

    if (descriptor.childBlockName === 'core/list-item') {
      Array.from(el.children).forEach(li => {
        if (li.tagName !== 'LI') return
        li.before(doc.createComment(' wp:list-item '))
        li.after(doc.createComment(' /wp:list-item '))
      })
    }

    const attrs = descriptor.attrsFrom(el)
    const attrsStr = Object.keys(attrs).length ? ' ' + JSON.stringify(attrs) : ''
    const name = descriptor.blockName.replace(/^core\//, '')
    el.before(doc.createComment(` wp:${name}${attrsStr} `))
    el.after(doc.createComment(` /wp:${name} `))
  })
}
```

Call it with the working `div` and `doc` before the final serialization, and guard idempotency by skipping any element whose immediately preceding non-whitespace sibling is already a matching `wp:` comment.

Using `doc.createComment` rather than string concatenation is deliberate: it is the DOM-level fix the root `CLAUDE.md` prescribes for exactly this class of problem, and it cannot produce the greedy-match or compounding-whitespace failures that string wrapping has produced three times in this file.

- [x] **Step 4: Run to verify pass**

```bash
node --test Scripts/test-editor.js
```

Expected: all passing, including the existing suite.

- [x] **Step 5: Run every suite**

```bash
./test.sh
```

Expected: all Swift and JS tests pass. The passthrough and gallery suites are the ones most likely to break; if either does, the new pass is claiming elements it should not.

- [x] **Step 6: Build and verify against a real post**

```bash
osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app
```

Create a new local draft, type a heading, a paragraph and a list, publish it, then open it in Gutenberg. Expected: three separate blocks, no Classic block. This is the acceptance test for the whole phase.

- [x] **Step 7: Commit**

```bash
git add Sources/QuillKit/Resources/editor-transforms.js Scripts/test-editor.js
git commit -m "feat: emit block delimiters for all modeled blocks

Paragraphs, headings, lists, quotes, code and separators previously saved with
only wp-block-* classes and no comment delimiters, so WordPress parsed them as
one core/freeform Classic block. They now carry real delimiters, added at the
DOM level rather than by string wrapping.

Newly written posts open in Gutenberg as real blocks.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Phase 3 — Container blocks

Each task delivers one editable container. They are independent and can be done in any order, except Tabs which is sequenced last because `core/tabs` only became core in WP 7.1 and was structurally refactored on the way in.

### Task 6: The container shape and Columns

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` (new `ColumnsBlock`, `ColumnBlock` nodes)
- Modify: `Sources/QuillKit/Resources/block-descriptors.js`
- Create: `Scripts/test-editor-containers.js`

**Interfaces:**
- Consumes: `descriptorFor` (Task 4)
- Produces: `window.insertColumns(count)`; Tiptap nodes `columnsBlock`, `columnBlock`

- [x] **Step 1: Write the failing tests**

Create `Scripts/test-editor-containers.js` using the same real-`editor.html`-in-jsdom harness as `Scripts/test-editor-gallery.js` — copy its `before()` block verbatim, including the `crypto.randomUUID`, `matchMedia`, `requestAnimationFrame` and `ResizeObserver` polyfills and the `_tiptapEditor` poll.

```js
describe('columns block', () => {
  before(() => { editor.commands.setContent('<p></p>', false) })

  test('inserts the requested number of columns', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertColumns(3)
    const node = editor.state.doc.child(0)
    assert.equal(node.type.name, 'columnsBlock')
    assert.equal(node.childCount, 3)
  })

  test('typing lands in the targeted column only', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertColumns(2)
    editor.commands.insertContent('Left')
    const cols = editor.state.doc.child(0)
    assert.match(cols.child(0).textContent, /Left/)
    assert.equal(cols.child(1).textContent, '')
  })

  test('parses a real columns block from WordPress markup', () => {
    editor.commands.setContent(
      '<!-- wp:columns --><div class="wp-block-columns">' +
      '<!-- wp:column --><div class="wp-block-column"><p>A</p></div><!-- /wp:column -->' +
      '<!-- wp:column --><div class="wp-block-column"><p>B</p></div><!-- /wp:column -->' +
      '</div><!-- /wp:columns -->', false)
    const node = editor.state.doc.child(0)
    assert.equal(node.type.name, 'columnsBlock')
    assert.equal(node.childCount, 2)
  })

  test('saves with wp:columns and wp:column delimiters', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertColumns(2)
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<!-- wp:columns -->/)
    assert.equal((out.match(/<!-- wp:column -->/g) || []).length, 2)
  })

  test('does not stack delimiters across repeated saves', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertColumns(2)
    const once = win.toWordPressHTML(editor.getHTML(), win.document)
    editor.commands.setContent(once, false)
    const twice = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.equal((twice.match(/<!-- wp:columns -->/g) || []).length, 1)
  })

  test('passthrough does not claim a columns block', () => {
    editor.commands.setContent(
      '<div class="wp-block-columns"><div class="wp-block-column"><p>A</p></div></div>', false)
    assert.equal(editor.state.doc.child(0).type.name, 'columnsBlock')
  })
})
```

- [x] **Step 2: Run to verify failure**

```bash
node --test Scripts/test-editor-containers.js
```

Expected: FAIL — `insertColumns` undefined.

- [x] **Step 3: Add the nodes**

In `editor.html`, near `GalleryBlock`:

```js
const ColumnBlock = TiptapNode.create({
  name: 'columnBlock',
  group: 'column',
  content: 'block+',
  priority: 210,
  parseHTML() { return [{ tag: 'div.wp-block-column' }] },
  renderHTML() { return ['div', { class: 'wp-block-column' }, 0] },
})

const ColumnsBlock = TiptapNode.create({
  name: 'columnsBlock',
  group: 'block',
  content: 'column+',
  priority: 210,
  parseHTML() { return [{ tag: 'div.wp-block-columns' }] },
  renderHTML() { return ['div', { class: 'wp-block-columns' }, 0] },
})
```

Priority 210 places both above `gutenbergPassthrough` (200), so the catch-all stops claiming them. That ordering is the reason the last test exists.

Register both in the extensions array alongside `GalleryBlock`, then add:

```js
window.insertColumns = (count) => {
  if (_isInFootnote()) return false
  const columns = Array.from({ length: count }, () => ({
    type: 'columnBlock',
    content: [{ type: 'paragraph' }],
  }))
  editor.chain().focus().insertContent({ type: 'columnsBlock', content: columns }).run()
  return true
}
```

- [x] **Step 4: Add the descriptors**

In `block-descriptors.js`:

```js
  columnsBlock: { blockName: 'core/columns', shape: 'container', childBlockName: 'core/column', attrsFrom: () => ({}) },
  columnBlock:  { blockName: 'core/column',  shape: 'container', childBlockName: null,          attrsFrom: () => ({}) },
```

Extend `NODE_FOR_TAG` handling in `editor-transforms.js` so a `div.wp-block-columns` maps to `columnsBlock` and `div.wp-block-column` to `columnBlock`, since neither is identified by tag name alone:

```js
function nodeNameForElement(el) {
  if (el.classList.contains('wp-block-columns')) return 'columnsBlock'
  if (el.classList.contains('wp-block-column'))  return 'columnBlock'
  return NODE_FOR_TAG[el.tagName] || null
}
```

Use `nodeNameForElement` in `wrapInDelimiters` in place of the bare `NODE_FOR_TAG` lookup, and recurse into container children so nested columns get their own delimiters.

- [x] **Step 5: Add the contextual toolbar group**

In the toolbar's utility group, following the `#table-controls` pattern:

```html
<span id="columns-controls" style="display:none">
  <button data-cmd="addColumn"    title="Add column">+Col</button>
  <button data-cmd="deleteColumn" title="Remove column">&minus;Col</button>
</span>
```

Reveal it from the existing selection-change handler when `editor.isActive('columnsBlock')`, exactly as `#table-controls` is revealed for tables.

- [x] **Step 6: Run to verify pass**

```bash
node --test Scripts/test-editor-containers.js && ./test.sh
```

Expected: all passing, including `test-editor-passthrough.js` — its specificity guards must still hold.

- [x] **Step 7: Build and check**

```bash
osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app
```

On a **new local draft** (never a published post), insert columns, type into each, save, and confirm in Gutenberg.

- [x] **Step 8: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Sources/QuillKit/Resources/block-descriptors.js Sources/QuillKit/Resources/editor-transforms.js Scripts/test-editor-containers.js
git commit -m "feat: make Columns editable

Adds columnsBlock/columnBlock nodes above gutenbergPassthrough's priority so
the catch-all stops freezing them into cards. Columns render as real side-by-side
regions typed into directly, with add/remove in a contextual toolbar group
following the existing table-controls pattern.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Details

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`, `block-descriptors.js`
- Test: `Scripts/test-editor-containers.js`

**Interfaces:**
- Consumes: the container pattern from Task 6
- Produces: `window.insertDetails()`; Tiptap node `detailsBlock`

- [x] **Step 1: Write the failing tests**

```js
describe('details block', () => {
  before(() => { editor.commands.setContent('<p></p>', false) })

  test('inserts a summary and a body', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertDetails()
    const node = editor.state.doc.child(0)
    assert.equal(node.type.name, 'detailsBlock')
    assert.equal(node.child(0).type.name, 'detailsSummary')
  })

  test('parses WordPress details markup', () => {
    editor.commands.setContent(
      '<!-- wp:details --><details class="wp-block-details">' +
      '<summary>S</summary><p>B</p></details><!-- /wp:details -->', false)
    assert.equal(editor.state.doc.child(0).type.name, 'detailsBlock')
  })

  test('saves with wp:details delimiters', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertDetails()
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<!-- wp:details -->/)
  })

  test('summary text stays in the summary on save', () => {
    editor.commands.setContent(
      '<details class="wp-block-details"><summary>Mine</summary><p>Body</p></details>', false)
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<summary>Mine<\/summary>/)
  })
})
```

- [x] **Step 2: Run to verify failure**

```bash
node --test Scripts/test-editor-containers.js
```

Expected: FAIL — `insertDetails` undefined.

- [x] **Step 3: Add the nodes**

```js
const DetailsSummary = TiptapNode.create({
  name: 'detailsSummary',
  content: 'inline*',
  priority: 210,
  parseHTML() { return [{ tag: 'summary' }] },
  renderHTML() { return ['summary', 0] },
})

const DetailsBlock = TiptapNode.create({
  name: 'detailsBlock',
  group: 'block',
  content: 'detailsSummary block+',
  priority: 210,
  addAttributes() { return { showContent: { default: false } } },
  parseHTML() { return [{ tag: 'details.wp-block-details' }] },
  renderHTML() { return ['details', { class: 'wp-block-details' }, 0] },
})

window.insertDetails = () => {
  if (_isInFootnote()) return false
  editor.chain().focus().insertContent({
    type: 'detailsBlock',
    content: [{ type: 'detailsSummary' }, { type: 'paragraph' }],
  }).run()
  return true
}
```

- [x] **Step 4: Add the descriptor**

```js
  detailsBlock: { blockName: 'core/details', shape: 'container', childBlockName: null, attrsFrom: el => (el.hasAttribute('open') ? { showContent: true } : {}) },
```

And in `nodeNameForElement`:

```js
  if (el.tagName === 'DETAILS') return 'detailsBlock'
```

- [x] **Step 5: Run to verify pass**

```bash
node --test Scripts/test-editor-containers.js && ./test.sh
```

- [x] **Step 6: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Sources/QuillKit/Resources/block-descriptors.js Sources/QuillKit/Resources/editor-transforms.js Scripts/test-editor-containers.js
git commit -m "feat: make Details editable

Summary and body are both typed into directly; the block was previously a
frozen passthrough card.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Buttons

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`, `block-descriptors.js`
- Test: `Scripts/test-editor-containers.js`

**Interfaces:**
- Consumes: the container pattern from Task 6
- Produces: `window.insertButtons()`; Tiptap nodes `buttonsBlock`, `buttonBlock`

- [x] **Step 1: Write the failing tests**

```js
describe('buttons block', () => {
  before(() => { editor.commands.setContent('<p></p>', false) })

  test('inserts one button by default', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertButtons()
    const node = editor.state.doc.child(0)
    assert.equal(node.type.name, 'buttonsBlock')
    assert.equal(node.childCount, 1)
  })

  test('parses WordPress buttons markup', () => {
    editor.commands.setContent(
      '<div class="wp-block-buttons">' +
      '<div class="wp-block-button"><a class="wp-block-button__link">Go</a></div></div>', false)
    assert.equal(editor.state.doc.child(0).type.name, 'buttonsBlock')
  })

  test('preserves the button href on save', () => {
    editor.commands.setContent(
      '<div class="wp-block-buttons"><div class="wp-block-button">' +
      '<a class="wp-block-button__link" href="https://x.test">Go</a></div></div>', false)
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /href="https:\/\/x\.test"/)
  })

  test('saves with wp:buttons and wp:button delimiters', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertButtons()
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<!-- wp:buttons -->/)
    assert.match(out, /<!-- wp:button -->/)
  })
})
```

- [x] **Step 2: Run to verify failure**

```bash
node --test Scripts/test-editor-containers.js
```

Expected: FAIL — `insertButtons` undefined.

- [x] **Step 3: Add the nodes**

```js
const ButtonBlock = TiptapNode.create({
  name: 'buttonBlock',
  group: 'button',
  content: 'inline*',
  priority: 210,
  addAttributes() {
    return { href: { default: null, parseHTML: el => el.querySelector('a')?.getAttribute('href') || null } }
  },
  parseHTML() { return [{ tag: 'div.wp-block-button' }] },
  renderHTML({ node }) {
    const attrs = { class: 'wp-block-button__link wp-element-button' }
    if (node.attrs.href) attrs.href = node.attrs.href
    return ['div', { class: 'wp-block-button' }, ['a', attrs, 0]]
  },
})

const ButtonsBlock = TiptapNode.create({
  name: 'buttonsBlock',
  group: 'block',
  content: 'button+',
  priority: 210,
  parseHTML() { return [{ tag: 'div.wp-block-buttons' }] },
  renderHTML() { return ['div', { class: 'wp-block-buttons' }, 0] },
})

window.insertButtons = () => {
  if (_isInFootnote()) return false
  editor.chain().focus().insertContent({
    type: 'buttonsBlock',
    content: [{ type: 'buttonBlock' }],
  }).run()
  return true
}
```

- [x] **Step 4: Add the descriptors**

```js
  buttonsBlock: { blockName: 'core/buttons', shape: 'container', childBlockName: 'core/button', attrsFrom: () => ({}) },
  buttonBlock:  { blockName: 'core/button',  shape: 'text',      childBlockName: null,          attrsFrom: () => ({}) },
```

In `nodeNameForElement`:

```js
  if (el.classList.contains('wp-block-buttons')) return 'buttonsBlock'
  if (el.classList.contains('wp-block-button'))  return 'buttonBlock'
```

Order matters — check `wp-block-buttons` before `wp-block-button`, since the latter is a prefix of the former's class token only by string containment, not by `classList` membership. Using `classList.contains` avoids that trap, but keep the order for readability.

- [x] **Step 5: Add the contextual toolbar group**

```html
<span id="buttons-controls" style="display:none">
  <button data-cmd="addButton"    title="Add button">+Button</button>
  <button data-cmd="deleteButton" title="Remove button">&minus;Button</button>
</span>
```

Reveal when `editor.isActive('buttonsBlock')`.

- [x] **Step 6: Run to verify pass**

```bash
node --test Scripts/test-editor-containers.js && ./test.sh
```

- [x] **Step 7: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Sources/QuillKit/Resources/block-descriptors.js Sources/QuillKit/Resources/editor-transforms.js Scripts/test-editor-containers.js
git commit -m "feat: make Buttons editable

Button labels are typed directly and hrefs survive the save transform.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Accordion

Four block types: `core/accordion` → `accordion-item` → `accordion-heading` + `accordion-panel`.

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`, `block-descriptors.js`
- Test: `Scripts/test-editor-containers.js`

**Interfaces:**
- Consumes: the container pattern from Task 6
- Produces: `window.insertAccordion()`; Tiptap nodes `accordionBlock`, `accordionItem`, `accordionHeading`, `accordionPanel`

- [ ] **Step 1: Write the failing tests**

```js
describe('accordion block', () => {
  before(() => { editor.commands.setContent('<p></p>', false) })

  test('inserts one item with a heading and a panel', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertAccordion()
    const node = editor.state.doc.child(0)
    assert.equal(node.type.name, 'accordionBlock')
    assert.equal(node.child(0).type.name, 'accordionItem')
    assert.equal(node.child(0).child(0).type.name, 'accordionHeading')
    assert.equal(node.child(0).child(1).type.name, 'accordionPanel')
  })

  test('parses the real accordion fixture', () => {
    const src = fs.readFileSync(
      path.resolve(__dirname, 'fixtures/accordion-block.html'), 'utf8')
    editor.commands.setContent(src, false)
    const node = editor.state.doc.child(0)
    assert.equal(node.type.name, 'accordionBlock')
    assert.equal(node.childCount, 2)
  })

  test('heading text round-trips', () => {
    const src = fs.readFileSync(
      path.resolve(__dirname, 'fixtures/accordion-block.html'), 'utf8')
    editor.commands.setContent(src, false)
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /Features/)
  })

  test('saves with all four delimiter types', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertAccordion()
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    for (const n of ['accordion', 'accordion-item', 'accordion-heading', 'accordion-panel']) {
      assert.match(out, new RegExp(`<!-- wp:${n}[ -]`))
    }
  })

  test('does not stack delimiters across repeated saves', () => {
    const src = fs.readFileSync(
      path.resolve(__dirname, 'fixtures/accordion-block.html'), 'utf8')
    editor.commands.setContent(src, false)
    const once = win.toWordPressHTML(editor.getHTML(), win.document)
    editor.commands.setContent(once, false)
    const twice = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.equal((twice.match(/<!-- wp:accordion -->/g) || []).length, 1)
  })
})
```

- [ ] **Step 2: Run to verify failure**

```bash
node --test Scripts/test-editor-containers.js
```

Expected: FAIL — `insertAccordion` undefined.

- [ ] **Step 3: Add the nodes**

```js
const AccordionHeading = TiptapNode.create({
  name: 'accordionHeading',
  content: 'inline*',
  priority: 210,
  parseHTML() {
    return [{
      tag: 'h1.wp-block-accordion-heading, h2.wp-block-accordion-heading, h3.wp-block-accordion-heading, h4.wp-block-accordion-heading, h5.wp-block-accordion-heading, h6.wp-block-accordion-heading',
      getAttrs: el => ({ level: parseInt(el.tagName.slice(1), 10) }),
      contentElement: el => el.querySelector('.wp-block-accordion-heading__toggle-title') || el,
    }]
  },
  addAttributes() { return { level: { default: 3 } } },
  renderHTML({ node }) {
    return [`h${node.attrs.level}`, { class: 'wp-block-accordion-heading wp-block-heading' },
      ['button', { type: 'button', class: 'wp-block-accordion-heading__toggle' },
        ['span', { class: 'wp-block-accordion-heading__toggle-title' }, 0]]]
  },
})

const AccordionPanel = TiptapNode.create({
  name: 'accordionPanel',
  content: 'block+',
  priority: 210,
  parseHTML() { return [{ tag: 'div.wp-block-accordion-panel' }] },
  renderHTML() { return ['div', { role: 'region', class: 'wp-block-accordion-panel' }, 0] },
})

const AccordionItem = TiptapNode.create({
  name: 'accordionItem',
  group: 'accordionItemGroup',
  content: 'accordionHeading accordionPanel',
  priority: 210,
  parseHTML() { return [{ tag: 'div.wp-block-accordion-item' }] },
  renderHTML() { return ['div', { class: 'wp-block-accordion-item' }, 0] },
})

const AccordionBlock = TiptapNode.create({
  name: 'accordionBlock',
  group: 'block',
  content: 'accordionItemGroup+',
  priority: 210,
  addAttributes() { return { autoclose: { default: false } } },
  parseHTML() {
    return [{ tag: 'div.wp-block-accordion', getAttrs: el => ({ autoclose: el.hasAttribute('data-autoclose') }) }]
  },
  renderHTML() { return ['div', { role: 'group', class: 'wp-block-accordion' }, 0] },
})

window.insertAccordion = () => {
  if (_isInFootnote()) return false
  editor.chain().focus().insertContent({
    type: 'accordionBlock',
    content: [{
      type: 'accordionItem',
      content: [
        { type: 'accordionHeading' },
        { type: 'accordionPanel', content: [{ type: 'paragraph' }] },
      ],
    }],
  }).run()
  return true
}
```

The `contentElement` on the heading's parse rule is what pulls the editable text out of the nested `<button><span>` wrapper rather than treating the button markup as content.

- [ ] **Step 4: Add the descriptors**

```js
  accordionBlock:   { blockName: 'core/accordion',         shape: 'container', childBlockName: 'core/accordion-item', attrsFrom: el => (el.hasAttribute('data-autoclose') ? { autoclose: true } : {}) },
  accordionItem:    { blockName: 'core/accordion-item',    shape: 'container', childBlockName: null,                  attrsFrom: () => ({}) },
  accordionHeading: { blockName: 'core/accordion-heading', shape: 'text',      childBlockName: null,                  attrsFrom: () => ({}) },
  accordionPanel:   { blockName: 'core/accordion-panel',   shape: 'container', childBlockName: null,                  attrsFrom: () => ({}) },
```

In `nodeNameForElement`, checking the most specific class first:

```js
  if (el.classList.contains('wp-block-accordion-heading')) return 'accordionHeading'
  if (el.classList.contains('wp-block-accordion-panel'))   return 'accordionPanel'
  if (el.classList.contains('wp-block-accordion-item'))    return 'accordionItem'
  if (el.classList.contains('wp-block-accordion'))         return 'accordionBlock'
```

- [ ] **Step 5: Add the contextual toolbar group**

```html
<span id="accordion-controls" style="display:none">
  <button data-cmd="addAccordionItem"    title="Add section">+Item</button>
  <button data-cmd="deleteAccordionItem" title="Remove section">&minus;Item</button>
</span>
```

- [ ] **Step 6: Run to verify pass**

```bash
node --test Scripts/test-editor-containers.js && ./test.sh
```

The fixture test is the important one — it proves a real accordion written by WordPress parses into editable nodes rather than a passthrough card.

- [ ] **Step 7: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Sources/QuillKit/Resources/block-descriptors.js Sources/QuillKit/Resources/editor-transforms.js Scripts/test-editor-containers.js
git commit -m "feat: make Accordion editable

Models all four accordion block types. Heading text is pulled out of the
nested button/span toggle markup via contentElement so it can be typed
directly, and the wrapper is regenerated on save.

Verified against a real accordion from a published post.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: Tabs

Sequenced last: `core/tabs` only became core in WP 7.1 and was structurally refactored on the way in, so its markup is the least settled in scope.

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`, `block-descriptors.js`
- Create: `Scripts/fixtures/tabs-block.html`
- Test: `Scripts/test-editor-containers.js`

**Interfaces:**
- Consumes: the container pattern from Task 6
- Produces: `window.insertTabs(count)`; Tiptap nodes `tabsBlock`, `tabBlock`

- [ ] **Step 1: Capture real Tabs markup first**

Before writing any code, create a Tabs block in Gutenberg on the live site, save it, and fetch the resulting `post_content` via the WordPress MCP (`wp_get_post`). Write the `<!-- wp:tabs -->` … `<!-- /wp:tabs -->` span verbatim to `Scripts/fixtures/tabs-block.html`.

Do not write the node from memory or from documentation. This block's markup changed during its path into core, and the fixture is the only trustworthy source.

- [ ] **Step 2: Add the fixture to the round-trip corpus**

No code change needed — `Scripts/test-block-serializer.js`'s fixture loop picks up any `.html` in the directory automatically. Run it:

```bash
node --test Scripts/test-block-serializer.js
```

Expected: PASS. A failure means the serializer mishandles something in the Tabs markup and must be fixed before continuing.

- [ ] **Step 3: Write the failing tests**

```js
describe('tabs block', () => {
  const tabsFixture = fs.readFileSync(
    path.resolve(__dirname, 'fixtures/tabs-block.html'), 'utf8')

  before(() => { editor.commands.setContent('<p></p>', false) })

  test('inserts the requested number of tabs', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertTabs(2)
    const node = editor.state.doc.child(0)
    assert.equal(node.type.name, 'tabsBlock')
    assert.equal(node.childCount, 2)
  })

  test('parses the real fixture into editable nodes', () => {
    editor.commands.setContent(tabsFixture, false)
    assert.equal(editor.state.doc.child(0).type.name, 'tabsBlock')
  })

  test('round-trips the fixture through the save transform', () => {
    editor.commands.setContent(tabsFixture, false)
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<!-- wp:tabs/)
  })

  test('does not stack delimiters across repeated saves', () => {
    editor.commands.setContent(tabsFixture, false)
    const once = win.toWordPressHTML(editor.getHTML(), win.document)
    editor.commands.setContent(once, false)
    const twice = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.equal((twice.match(/<!-- wp:tabs/g) || []).length, 1)
  })
})
```

- [ ] **Step 4: Run to verify failure**

```bash
node --test Scripts/test-editor-containers.js
```

Expected: FAIL — `insertTabs` undefined.

- [ ] **Step 5: Write the nodes from the fixture**

Model `tabsBlock` and `tabBlock` on the exact structure in `Scripts/fixtures/tabs-block.html`, following the shape of `ColumnsBlock`/`ColumnBlock` from Task 6: `group: 'block'` with `content: 'tab+'` on the parent, `priority: 210` on both so `gutenbergPassthrough` does not claim them, `parseHTML` keyed on the fixture's actual wrapper classes, and `renderHTML` regenerating exactly the fixture's markup.

Add the insert bridge:

```js
window.insertTabs = (count) => {
  if (_isInFootnote()) return false
  const tabs = Array.from({ length: count }, () => ({
    type: 'tabBlock',
    content: [{ type: 'paragraph' }],
  }))
  editor.chain().focus().insertContent({ type: 'tabsBlock', content: tabs }).run()
  return true
}
```

- [ ] **Step 6: Add the descriptors and toolbar group**

```js
  tabsBlock: { blockName: 'core/tabs', shape: 'container', childBlockName: 'core/tab', attrsFrom: () => ({}) },
  tabBlock:  { blockName: 'core/tab',  shape: 'container', childBlockName: null,       attrsFrom: () => ({}) },
```

```html
<span id="tabs-controls" style="display:none">
  <button data-cmd="addTab"    title="Add tab">+Tab</button>
  <button data-cmd="deleteTab" title="Remove tab">&minus;Tab</button>
</span>
```

- [ ] **Step 7: Run to verify pass**

```bash
node --test Scripts/test-editor-containers.js && ./test.sh
```

- [ ] **Step 8: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Sources/QuillKit/Resources/block-descriptors.js Sources/QuillKit/Resources/editor-transforms.js Scripts/fixtures/tabs-block.html Scripts/test-editor-containers.js
git commit -m "feat: make Tabs editable

Modeled from a real WP 7.1 Tabs block captured from the live site rather than
from documentation, since the block's markup was refactored on its way into
core. The fixture is pinned in the round-trip corpus.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Phase 4 — Insertion UI

### Task 11: The insert menu

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` (toolbar button, `#insert-menu`, handlers)
- Test: `Scripts/test-editor-containers.js`

**Interfaces:**
- Consumes: `insertColumns`, `insertDetails`, `insertButtons`, `insertAccordion`, `insertTabs` (Tasks 8-12)
- Produces: `#insert-button`, `#insert-menu`

- [ ] **Step 1: Write the failing tests**

```js
describe('insert menu', () => {
  test('the toolbar exposes an insert button', () => {
    assert.ok(win.document.getElementById('insert-button'))
  })

  test('the menu lists every container block', () => {
    const items = Array.from(win.document.querySelectorAll('#insert-menu [data-insert]'))
      .map(el => el.dataset.insert)
    for (const n of ['columns', 'accordion', 'tabs', 'details', 'buttons']) {
      assert.ok(items.includes(n), `missing ${n}`)
    }
  })

  test('clicking a menu item inserts that block', () => {
    editor.commands.setContent('<p></p>', false)
    win.document.querySelector('#insert-menu [data-insert="details"]').click()
    assert.equal(editor.state.doc.child(0).type.name, 'detailsBlock')
  })

  test('the menu closes after an insertion', () => {
    editor.commands.setContent('<p></p>', false)
    win.document.querySelector('#insert-menu [data-insert="buttons"]').click()
    assert.equal(win.document.getElementById('insert-menu').classList.contains('open'), false)
  })
})
```

- [ ] **Step 2: Run to verify failure**

```bash
node --test Scripts/test-editor-containers.js
```

Expected: FAIL — no `#insert-button`.

- [ ] **Step 3: Add the button and menu**

In the toolbar's insert group, after `#embed-button`:

```html
<button id="insert-button" title="Insert block" aria-haspopup="menu" aria-expanded="false">
  <svg viewBox="0 0 24 24"><rect x="4" y="4" width="7" height="7" rx="1"></rect><rect x="13" y="4" width="7" height="7" rx="1"></rect><rect x="4" y="13" width="7" height="7" rx="1"></rect><path d="M16.5 13v7"></path><path d="M13 16.5h7"></path></svg>
</button>
```

After `#heading-menu`:

```html
<div id="insert-menu" role="menu">
  <button data-insert="columns"      role="menuitem">Columns</button>
  <button data-insert="accordion"    role="menuitem">Accordion</button>
  <button data-insert="tabs"         role="menuitem">Tabs</button>
  <button data-insert="details"      role="menuitem">Details</button>
  <button data-insert="buttons"      role="menuitem">Buttons</button>
  <button data-insert="pullquote"    role="menuitem">Pullquote</button>
  <button data-insert="preformatted" role="menuitem">Preformatted</button>
</div>
```

Reuse `#heading-menu`'s CSS by adding `#insert-menu` to the same selectors rather than duplicating rules. Wire open/close, click-outside dismissal and Escape exactly as the heading menu does.

```js
const INSERT_ACTIONS = {
  columns:      () => window.insertColumns(2),
  accordion:    () => window.insertAccordion(),
  tabs:         () => window.insertTabs(2),
  details:      () => window.insertDetails(),
  buttons:      () => window.insertButtons(),
  pullquote:    () => editor.chain().focus().setPullquote().run(),
  preformatted: () => editor.chain().focus().setPreformatted().run(),
}

document.getElementById('insert-menu').addEventListener('click', e => {
  const btn = e.target.closest('[data-insert]')
  if (!btn) return
  INSERT_ACTIONS[btn.dataset.insert]?.()
  _closeInsertMenu()
})
```

Pullquote and Preformatted are wired here but their commands land in Task 12; until then those two entries are inert, which the tests do not assert against.

- [ ] **Step 4: Run to verify pass**

```bash
node --test Scripts/test-editor-containers.js && ./test.sh
```

- [ ] **Step 5: Build and check both appearances**

```bash
osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app
```

Open the menu in light and dark mode. It is a plain DOM menu, not an `NSPopUpButton`, so the `.rebuildsOnAppearanceChange()` requirement does not apply — but confirm the colors follow the editor's existing dark-mode rules.

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Scripts/test-editor-containers.js
git commit -m "feat: add the block insert menu

One toolbar dropdown modeled on the existing heading menu, dispatching to the
container insert bridges. Image, gallery, table and embed keep their dedicated
one-click buttons.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 12: Pullquote and Preformatted

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`, `block-descriptors.js`
- Test: `Scripts/test-editor-containers.js`

**Interfaces:**
- Consumes: the insert menu (Task 11)
- Produces: Tiptap nodes `pullquote`, `preformatted`; commands `setPullquote()`, `setPreformatted()`

- [ ] **Step 1: Write the failing tests**

```js
describe('pullquote and preformatted', () => {
  before(() => { editor.commands.setContent('<p></p>', false) })

  test('setPullquote produces a pullquote node', () => {
    editor.commands.setContent('<p>Q</p>', false)
    editor.chain().focus().setPullquote().run()
    assert.equal(editor.state.doc.child(0).type.name, 'pullquote')
  })

  test('a pullquote saves with wp:pullquote delimiters', () => {
    editor.commands.setContent(
      '<figure class="wp-block-pullquote"><blockquote><p>Q</p></blockquote></figure>', false)
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<!-- wp:pullquote -->/)
  })

  test('setPreformatted produces a preformatted node', () => {
    editor.commands.setContent('<p>X</p>', false)
    editor.chain().focus().setPreformatted().run()
    assert.equal(editor.state.doc.child(0).type.name, 'preformatted')
  })

  test('preformatted saves with wp:preformatted delimiters', () => {
    editor.commands.setContent('<pre class="wp-block-preformatted">X</pre>', false)
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<!-- wp:preformatted -->/)
  })

  test('a pullquote is not claimed by passthrough', () => {
    editor.commands.setContent(
      '<figure class="wp-block-pullquote"><blockquote><p>Q</p></blockquote></figure>', false)
    assert.equal(editor.state.doc.child(0).type.name, 'pullquote')
  })
})
```

- [ ] **Step 2: Run to verify failure**

```bash
node --test Scripts/test-editor-containers.js
```

Expected: FAIL — `setPullquote` is not a function.

- [ ] **Step 3: Add the nodes**

```js
const Pullquote = TiptapNode.create({
  name: 'pullquote',
  group: 'block',
  content: 'block+',
  priority: 210,
  parseHTML() { return [{ tag: 'figure.wp-block-pullquote' }] },
  renderHTML() { return ['figure', { class: 'wp-block-pullquote' }, ['blockquote', {}, 0]] },
  addCommands() {
    return { setPullquote: () => ({ commands }) => commands.wrapIn(this.name) }
  },
})

const Preformatted = TiptapNode.create({
  name: 'preformatted',
  group: 'block',
  content: 'text*',
  marks: '',
  code: true,
  priority: 210,
  parseHTML() { return [{ tag: 'pre.wp-block-preformatted', preserveWhitespace: 'full' }] },
  renderHTML() { return ['pre', { class: 'wp-block-preformatted' }, 0] },
  addCommands() {
    return { setPreformatted: () => ({ commands }) => commands.setNode(this.name) }
  },
})
```

`priority: 210` on the pullquote is required — `gutenbergPassthrough`'s figure rule currently claims `figure.wp-block-pullquote`, and `QUILL_MODELED_FIGURE_CLASSES` in `editor-transforms.js` must also gain `wp-block-pullquote` so passthrough stops treating it as unmodeled.

`preserveWhitespace: 'full'` on preformatted is the point of the block; without it the parse collapses the whitespace it exists to preserve.

- [ ] **Step 4: Add the descriptors**

```js
  pullquote:    { blockName: 'core/pullquote',    shape: 'text', childBlockName: null, attrsFrom: () => ({}) },
  preformatted: { blockName: 'core/preformatted', shape: 'text', childBlockName: null, attrsFrom: () => ({}) },
```

In `nodeNameForElement`:

```js
  if (el.classList.contains('wp-block-pullquote'))    return 'pullquote'
  if (el.classList.contains('wp-block-preformatted')) return 'preformatted'
```

- [ ] **Step 5: Run every suite**

```bash
./test.sh
```

Expected: all passing. `test-editor-passthrough.js` has an explicit drift guard asserting `QUILL_MODELED_FIGURE_CLASSES` is exactly image/gallery/embed/table — that guard must be updated to include pullquote, and updating it is correct here rather than a test being weakened.

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Sources/QuillKit/Resources/block-descriptors.js Sources/QuillKit/Resources/editor-transforms.js Scripts/test-editor-containers.js Scripts/test-editor-passthrough.js
git commit -m "feat: add Pullquote and Preformatted blocks

Both were previously frozen passthrough cards. Pullquote joins
QUILL_MODELED_FIGURE_CLASSES so the passthrough figure rule stops claiming it;
the drift guard is updated to match.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Final verification

Run before considering the plan complete.

- [ ] **Full suite**

```bash
./test.sh
```

- [ ] **Round-trip on every fixture**

```bash
node --test Scripts/test-block-serializer.js
```

- [ ] **Byte-identity on an untouched post**

Open post 17780 in Quill, save without editing, and diff the resulting `post_content` against the original. Must be byte-identical. This is the constraint that outranks every feature.

- [ ] **Gutenberg check**

Write a new post using every block in scope, publish it, open it in Gutenberg. Every block must be editable there, with no Classic block anywhere in the post.

- [ ] **Update `CLAUDE.md`**

Run the `claude-md-management:revise-claude-md` skill. At minimum: the new resource files and their `build.sh` lines, the new test suites and their counts, and the descriptor/shape system.
