# Generic Gutenberg Block Passthrough Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop Quill from silently destroying Gutenberg blocks it doesn't natively model (Accordion, Columns, Group, etc.) when the user pastes them into code view or loads a post containing them — without adding any visual editing support for their internals.

**Architecture:** A new atomic Tiptap node, `gutenbergPassthrough`, catches any element carrying a `wp-block-*` class that no other, higher-priority parse rule already claimed, captures its `outerHTML` verbatim, and renders a static "unsupported block" card in place of it. On save, `toWordPressHTML` regenerates any `<!-- wp:name -->` block comments that were present around the original markup, using the same DOM-sibling-comment-insertion technique already used for embeds and galleries.

**Tech Stack:** Tiptap 2.x node running inside the existing WKWebView editor (`editor.html`), plain DOM transform functions in `editor-transforms.js`, Node + jsdom for JS tests (`node --test`).

## Global Constraints

- Read-only passthrough only — no visual editing of the block's internals. Editing requires code view.
- Detection is class-based (`wp-block-*` substring on any non-`<figure>` element), not comment-based — must work on markup with no `<!-- wp:name -->` comments at all (the common paste case), and additionally preserve those comments when present.
- The parse rule must never claim an element any other rule in the schema already claims — verified precedence: `figure` elements are excluded entirely from the catch-all, because `figure.wp-block-table` has no dedicated rule today and relies on transparent pass-through to the inner `<table>`.
- No new Swift code, no new toolbar button, no insertion UI — this node only ever arises from parsing existing content.
- Node priority: `1` — confirmed lower than Tiptap's default extension priority of `100` (`tiptap-bundle.js`: `C(r,'priority')||100`) and the footnote nodes' elevated `110`.

---

### Task 1: `formatHTML` — treat `<div>` as a block-level tag

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js:267` (the `BLOCK` set inside `formatHTML`)
- Test: `Scripts/test-editor.js`

**Interfaces:**
- Consumes: nothing new
- Produces: `formatHTML(html, doc)` now indents `<div>` elements (and recurses into their children) the same way it already does for `<figure>`/`<table>`/etc., instead of rendering them as one unbroken inline blob. No existing test's expected output contains a bare `<div>` today (no current node renders one), so this is additive only.

- [ ] **Step 1: Write the failing test**

Add to `Scripts/test-editor.js`, in the existing `describe('formatHTML', ...)` block:

```js
  test('div wrapping block children is indented like other block tags', () => {
    const html = '<div class="wp-block-accordion"><div class="wp-block-accordion-item"><h3>Title</h3></div></div>'
    const out = formatHTML(html, document)
    assert.equal(
      out,
      '<div class="wp-block-accordion">\n' +
      '  <div class="wp-block-accordion-item">\n' +
      '    <h3>Title</h3>\n' +
      '  </div>\n' +
      '</div>'
    )
  })
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test Scripts/test-editor.js`
Expected: FAIL — actual output is the whole thing on one line (`<div class="wp-block-accordion"><div class="wp-block-accordion-item">...`), since `div` isn't in `formatHTML`'s `BLOCK` set yet.

- [ ] **Step 3: Add `'div'` to the `BLOCK` set**

In `Sources/QuillKit/Resources/editor-transforms.js`, change:

```js
  const BLOCK = new Set(['p','h1','h2','h3','h4','h5','h6',
    'ul','ol','li','blockquote','pre','figure','figcaption',
    'table','thead','tbody','tfoot','tr','th','td','cite'])
```

to:

```js
  const BLOCK = new Set(['p','h1','h2','h3','h4','h5','h6',
    'ul','ol','li','blockquote','pre','figure','figcaption',
    'table','thead','tbody','tfoot','tr','th','td','cite','div'])
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test Scripts/test-editor.js`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/Resources/editor-transforms.js Scripts/test-editor.js
git commit -m "feat: indent div elements in code-view formatHTML output"
```

---

### Task 2: Pure parsing helpers for passthrough blocks

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js` (add three new functions near the top, after `extractAlignment`; update the `module.exports` list at the bottom)
- Test: `Scripts/test-editor.js`

**Interfaces:**
- Consumes: nothing new
- Produces:
  - `passthroughLabelFromClass(cls: string): string` — e.g. `'wp-block-accordion'` → `'Accordion'`
  - `passthroughLabelFromBlockName(name: string): string` — e.g. `'accordion'` → `'Accordion'`, `'core/accordion'` → `'Accordion'`, `'my-plugin/foo-bar'` → `'Foo Bar'`
  - `parsePassthroughBlock(el: Element): { blockLabel: string, blockName: string|null, attrsJSON: string|null, sourceHTML: string } | null` — `null` means "this element has no `wp-block-*` class, not a passthrough candidate." Task 4's Tiptap `getAttrs` calls this directly and translates `null` → `false`.

- [ ] **Step 1: Write the failing tests**

Add a new `describe` block to `Scripts/test-editor.js`, after the `extractAlignment` block:

```js
// ---------------------------------------------------------------------------
// passthroughLabelFromClass / passthroughLabelFromBlockName / parsePassthroughBlock
// ---------------------------------------------------------------------------

describe('passthroughLabelFromClass', () => {
  test('strips wp-block- prefix and title-cases', () => {
    assert.equal(passthroughLabelFromClass('wp-block-accordion'), 'Accordion')
  })

  test('splits multi-word block names on hyphens', () => {
    assert.equal(passthroughLabelFromClass('wp-block-media-text'), 'Media Text')
  })
})

describe('passthroughLabelFromBlockName', () => {
  test('bare core block name', () => {
    assert.equal(passthroughLabelFromBlockName('accordion'), 'Accordion')
  })

  test('namespaced core block name drops the namespace', () => {
    assert.equal(passthroughLabelFromBlockName('core/accordion'), 'Accordion')
  })

  test('namespaced plugin block name with multiple words', () => {
    assert.equal(passthroughLabelFromBlockName('my-plugin/foo-bar'), 'Foo Bar')
  })
})

describe('parsePassthroughBlock', () => {
  function el(html) {
    const div = document.createElement('div')
    div.innerHTML = html
    return div.firstElementChild
  }

  test('returns null for an element with no wp-block- class', () => {
    assert.equal(parsePassthroughBlock(el('<div class="something-else"></div>')), null)
  })

  test('class-only element (no adjacent comments)', () => {
    const result = parsePassthroughBlock(el('<div class="wp-block-accordion"><p>x</p></div>'))
    assert.equal(result.blockLabel, 'Accordion')
    assert.equal(result.blockName, null)
    assert.equal(result.attrsJSON, null)
    assert.equal(result.sourceHTML, '<div class="wp-block-accordion"><p>x</p></div>')
  })

  test('element with adjacent wp:name comments (no attrs)', () => {
    const container = document.createElement('div')
    container.innerHTML =
      '<!-- wp:accordion -->\n<div class="wp-block-accordion"><p>x</p></div>\n<!-- /wp:accordion -->'
    const target = container.querySelector('.wp-block-accordion')
    const result = parsePassthroughBlock(target)
    assert.equal(result.blockLabel, 'Accordion')
    assert.equal(result.blockName, 'accordion')
    assert.equal(result.attrsJSON, null)
  })

  test('element with adjacent wp:name comments including JSON attrs', () => {
    const container = document.createElement('div')
    container.innerHTML =
      '<!-- wp:accordion {"autoclose":false} -->\n<div class="wp-block-accordion"><p>x</p></div>\n<!-- /wp:accordion -->'
    const target = container.querySelector('.wp-block-accordion')
    const result = parsePassthroughBlock(target)
    assert.equal(result.blockName, 'accordion')
    assert.equal(result.attrsJSON, '{"autoclose":false}')
  })

  test('mismatched open/close comment names are not treated as a pair', () => {
    const container = document.createElement('div')
    container.innerHTML =
      '<!-- wp:accordion -->\n<div class="wp-block-accordion"><p>x</p></div>\n<!-- /wp:columns -->'
    const target = container.querySelector('.wp-block-accordion')
    const result = parsePassthroughBlock(target)
    assert.equal(result.blockName, null)
    assert.equal(result.blockLabel, 'Accordion')
  })
})
```

Update the `require` line at the top of `Scripts/test-editor.js` to pull in the three new functions:

```js
const { extractAlignment, toWordPressHTML, formatHTML, countStats, findMatches, findMatchesLoose, fuzzyAnchorRegex, detectEmbedProvider, embedClassFor, passthroughLabelFromClass, passthroughLabelFromBlockName, parsePassthroughBlock } = require('../Sources/QuillKit/Resources/editor-transforms.js')
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test Scripts/test-editor.js`
Expected: FAIL with `TypeError: passthroughLabelFromClass is not a function` (or `undefined`) — none of the three functions exist yet.

- [ ] **Step 3: Implement the three functions**

In `Sources/QuillKit/Resources/editor-transforms.js`, add immediately after `extractAlignment`:

```js
function passthroughLabelFromClass(cls) {
  return cls.replace(/^wp-block-/, '').split('-').filter(Boolean)
    .map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ')
}

function passthroughLabelFromBlockName(name) {
  const base = name.includes('/') ? name.split('/').pop() : name
  return base.split('-').filter(Boolean)
    .map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ')
}

// Given an element already known to be an unmodeled Gutenberg block (a
// wp-block-* classed element no other parse rule claimed), extracts what's
// needed to preserve and re-display it. Returns null if `el` has no
// wp-block-* class at all (not a passthrough candidate).
//
// Checks for immediately-adjacent `<!-- wp:name --> / <!-- /wp:name -->`
// comment siblings (skipping whitespace-only text nodes in between, since
// real Gutenberg source has a newline between a comment and its element).
// If found and their names match, blockName/attrsJSON are populated from the
// comment text verbatim so toWordPressHTML can regenerate identical comments
// on save. If not found, this is class-only markup (e.g. a live page's
// rendered HTML) — blockName/attrsJSON stay null and no comments are
// synthesized later.
function parsePassthroughBlock(el) {
  const wpClass = Array.from(el.classList).find(c => c.startsWith('wp-block-'))
  if (!wpClass) return null

  function adjacentComment(node, direction) {
    let n = node[direction]
    while (n && n.nodeType === 3 && n.textContent.trim() === '') n = n[direction]
    return (n && n.nodeType === 8) ? n : null
  }

  const openComment = adjacentComment(el, 'previousSibling')
  const closeComment = adjacentComment(el, 'nextSibling')
  const openMatch = openComment && openComment.nodeValue.match(/^\s*wp:(\S+?)(?:\s+(\{[\s\S]*\}))?\s*$/)
  const closeMatch = closeComment && closeComment.nodeValue.match(/^\s*\/wp:(\S+)\s*$/)

  if (openMatch && closeMatch && openMatch[1] === closeMatch[1]) {
    return {
      blockLabel: passthroughLabelFromBlockName(openMatch[1]),
      blockName: openMatch[1],
      attrsJSON: openMatch[2] || null,
      sourceHTML: el.outerHTML,
    }
  }

  return {
    blockLabel: passthroughLabelFromClass(wpClass),
    blockName: null,
    attrsJSON: null,
    sourceHTML: el.outerHTML,
  }
}
```

Update the `module.exports` line at the bottom of the file:

```js
module.exports = { extractAlignment, toWordPressHTML, formatHTML, countStats, findMatches, findMatchesLoose, fuzzyAnchorRegex, detectEmbedProvider, embedClassFor, passthroughLabelFromClass, passthroughLabelFromBlockName, parsePassthroughBlock }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test Scripts/test-editor.js`
Expected: PASS (all new tests, plus all previously-passing tests still pass)

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/Resources/editor-transforms.js Scripts/test-editor.js
git commit -m "feat: add pure parsing helpers for unmodeled Gutenberg blocks"
```

---

### Task 3: `toWordPressHTML` — regenerate `wp:name` comments on save

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js` (new pass inside `toWordPressHTML`, immediately before `return div.innerHTML`)
- Test: `Scripts/test-editor.js`

**Interfaces:**
- Consumes: an element carrying `data-quill-passthrough-name` (and optionally `data-quill-passthrough-attrs`) attributes — the shape Task 4's `renderHTML` will produce. This task's tests construct that shape directly as an HTML string, the same way the existing gallery/embed wrap tests feed `toWordPressHTML` hand-built figures without going through the live Tiptap editor.
- Produces: `toWordPressHTML` wraps any such element in fresh `<!-- wp:{name} {attrs} -->` / `<!-- /wp:{name} -->` comments (via DOM sibling insertion, mirroring the existing embed/gallery wrap code) and removes the two temporary `data-quill-passthrough-*` attributes from the element itself.

- [ ] **Step 1: Write the failing tests**

Add to `Scripts/test-editor.js`, after the existing `describe('toWordPressHTML — gallery', ...)` block:

```js
describe('toWordPressHTML — passthrough blocks', () => {
  test('an element with data-quill-passthrough-name gets wrapped in matching wp:name comments', () => {
    const html = '<div data-quill-passthrough-name="accordion" class="wp-block-accordion"><p>x</p></div>'
    const out = wp(html)
    assert.match(out, /<!-- wp:accordion -->/)
    assert.match(out, /<!-- \/wp:accordion -->/)
    assert.ok(!out.includes('data-quill-passthrough-name'))
  })

  test('data-quill-passthrough-attrs is emitted inside the opening comment', () => {
    const html = '<div data-quill-passthrough-name="accordion" data-quill-passthrough-attrs="{&quot;autoclose&quot;:false}" class="wp-block-accordion"></div>'
    const out = wp(html)
    assert.match(out, /<!-- wp:accordion \{"autoclose":false\} -->/)
    assert.ok(!out.includes('data-quill-passthrough-attrs'))
  })

  test('an element with no data-quill-passthrough-name attribute is left alone', () => {
    const html = '<div class="wp-block-accordion"><p>x</p></div>'
    const out = wp(html)
    assert.ok(!out.includes('<!--'))
  })

  test('wrapping is idempotent', () => {
    const html = '<div data-quill-passthrough-name="accordion" class="wp-block-accordion"><p>x</p></div>'
    const once = wp(html)
    assert.equal(wp(once), once)
  })
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test Scripts/test-editor.js`
Expected: FAIL — no `wp:accordion` comments appear in the output yet (the pass doesn't exist), and `data-quill-passthrough-name` survives unchanged in the output.

- [ ] **Step 3: Implement the new pass**

In `Sources/QuillKit/Resources/editor-transforms.js`, add immediately before the final `return div.innerHTML` in `toWordPressHTML` (i.e. right after the existing `figure.wp-block-gallery` wrap block):

```js
  // Regenerate wp:name block comments for passthrough (unmodeled Gutenberg
  // block) elements. gutenbergPassthrough's renderHTML smuggles the original
  // comment's name/attrs through as temporary data-quill-passthrough-*
  // attributes (mirroring the data-media-id -> wp-image-{id} class
  // conversion above); this pass wraps the element in fresh
  // <!-- wp:name --> comments using those attributes (if the original had
  // none, no comments are added — see the "no data-quill-passthrough-name"
  // test), then strips the temporary attributes so they never appear in the
  // saved HTML. DOM-level insertion, not string replace, so repeated saves
  // don't double-wrap — same approach as the embed/gallery wrapping above.
  div.querySelectorAll('[data-quill-passthrough-name]').forEach(el => {
    const name = el.getAttribute('data-quill-passthrough-name')
    const attrsJSON = el.getAttribute('data-quill-passthrough-attrs')
    el.removeAttribute('data-quill-passthrough-name')
    el.removeAttribute('data-quill-passthrough-attrs')
    const open = doc.createComment(attrsJSON ? ` wp:${name} ${attrsJSON} ` : ` wp:${name} `)
    const close = doc.createComment(` /wp:${name} `)
    const parent = el.parentNode
    const next = el.nextSibling
    parent.insertBefore(open, el)
    parent.insertBefore(doc.createTextNode('\n'), el)
    parent.insertBefore(doc.createTextNode('\n'), next)
    parent.insertBefore(close, next)
  })
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test Scripts/test-editor.js`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/Resources/editor-transforms.js Scripts/test-editor.js
git commit -m "feat: regenerate wp:name comments for passthrough blocks on save"
```

---

### Task 4: `gutenbergPassthrough` Tiptap node — schema, card UI, registration

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`:
  - CSS: add a `.passthrough-card` block near `.gallery-card` (around line 771)
  - JS: add `PassthroughNodeView` class and `GutenbergPassthrough` node definition near `GalleryBlock` (around line 1719, right after the existing gallery block)
  - JS: register `GutenbergPassthrough` in the `extensions: [...]` array (around line 2037, right after `GalleryBlock,`)
- Test: new file `Scripts/test-editor-passthrough.js`
- Modify: `test.sh` (register the new suite)

**Interfaces:**
- Consumes: `parsePassthroughBlock(el)`, `passthroughLabelFromClass`/`passthroughLabelFromBlockName` from Task 2 (loaded as globals via `editor-transforms.js`, same as every other function in `editor.html`)
- Produces: a `gutenbergPassthrough` node type registered in the Tiptap schema, insertable/parseable like any other block node. `editor.getJSON()` nodes of this type have `attrs: { blockLabel, blockName, attrsJSON, sourceHTML }`.

- [ ] **Step 1: Write the failing tests**

Create `Scripts/test-editor-passthrough.js`:

```js
'use strict'

// Live Tiptap tests for the gutenbergPassthrough node — loads the REAL
// editor.html in jsdom, same approach as test-editor-gallery.js, because a
// custom node's parseHTML/renderHTML can't be exercised through the pure
// editor-transforms.js helpers alone.

const { test, describe, before, after } = require('node:test')
const assert = require('node:assert/strict')
const { JSDOM, VirtualConsole } = require('jsdom')
const fs = require('fs')
const path = require('path')
const nodeCrypto = require('crypto')

const htmlPath = path.resolve(__dirname, '../Sources/QuillKit/Resources/editor.html')

let editor
let win

before(async () => {
  const html = fs.readFileSync(htmlPath, 'utf8')
  const vc = new VirtualConsole()
  const logs = []
  vc.on('jsdomError', e => logs.push('JSDOM_ERROR: ' + (e.detail?.stack || e.message || e)))

  const dom = new JSDOM(html, {
    runScripts: 'dangerously',
    resources: 'usable',
    pretendToBeVisual: true,
    url: 'file://' + htmlPath,
    virtualConsole: vc,
  })
  win = dom.window

  if (!win.crypto) win.crypto = {}
  if (!win.crypto.randomUUID) win.crypto.randomUUID = () => nodeCrypto.randomUUID()
  if (!win.matchMedia) win.matchMedia = () => ({ matches: false, addEventListener() {}, removeEventListener() {}, addListener() {}, removeListener() {} })
  if (!win.requestAnimationFrame) win.requestAnimationFrame = cb => setTimeout(cb, 0)
  if (!win.ResizeObserver) win.ResizeObserver = class { observe() {} unobserve() {} disconnect() {} }

  editor = await new Promise((resolve, reject) => {
    let tries = 0
    const t = setInterval(() => {
      if (win._tiptapEditor) { clearInterval(t); resolve(win._tiptapEditor) }
      else if (++tries > 400) { clearInterval(t); reject(new Error('editor never became ready.\n' + logs.join('\n'))) }
    }, 25)
  })
})

after(() => { if (win) win.close() })

function nodesOfType(typeName) {
  const out = []
  editor.state.doc.descendants(n => { if (n.type.name === typeName) out.push(n) })
  return out
}

const ACCORDION_CLASS_ONLY =
  '<div class="wp-block-accordion" data-wp-interactive="core/accordion">' +
  '<div class="wp-block-accordion-item">' +
  '<h3 class="wp-block-accordion-heading"><button type="button" class="wp-block-accordion-heading__toggle">Features</button></h3>' +
  '<div class="wp-block-accordion-panel"><ul class="wp-block-list"><li>One</li></ul></div>' +
  '</div></div>'

describe('gutenbergPassthrough — class-only markup (no wp: comments)', () => {
  test('parses into a single gutenbergPassthrough node', () => {
    win.setContent(ACCORDION_CLASS_ONLY)
    const nodes = nodesOfType('gutenbergPassthrough')
    assert.equal(nodes.length, 1)
    assert.equal(nodes[0].attrs.blockLabel, 'Accordion')
    assert.equal(nodes[0].attrs.blockName, null)
  })

  test('round-trips the essential markup through getContent()', () => {
    win.setContent(ACCORDION_CLASS_ONLY)
    const out = win.getContent()
    assert.match(out, /data-wp-interactive="core\/accordion"/)
    assert.match(out, /wp-block-accordion-heading__toggle/)
    assert.match(out, /<li>One<\/li>/)
    assert.ok(!out.includes('<!--'))
  })

  test('an unrelated edit elsewhere in the document does not disturb the passthrough node', () => {
    win.setContent('<p>hello</p>' + ACCORDION_CLASS_ONLY)
    editor.commands.setTextSelection(1)
    editor.commands.insertContent('X')
    const out = win.getContent()
    assert.match(out, /Xhello|helloX/)
    assert.match(out, /wp-block-accordion-heading__toggle/)
  })

  test('renders a static card, not the raw accordion markup, in the editor DOM', () => {
    win.setContent(ACCORDION_CLASS_ONLY)
    const card = win.document.querySelector('.passthrough-card')
    assert.ok(card, 'expected a .passthrough-card element in the editor DOM')
    assert.match(card.textContent, /Accordion/)
    assert.equal(win.document.querySelector('#editor button.wp-block-accordion-heading__toggle'), null)
  })
})

describe('gutenbergPassthrough — comment-wrapped markup', () => {
  const ACCORDION_WITH_COMMENTS =
    '<!-- wp:accordion {"autoclose":false} -->\n' +
    ACCORDION_CLASS_ONLY.replace('<div class="wp-block-accordion"', '<div class="wp-block-accordion"') +
    '\n<!-- /wp:accordion -->'

  test('recovers blockName and attrsJSON from adjacent comments', () => {
    win.setContent(ACCORDION_WITH_COMMENTS)
    const nodes = nodesOfType('gutenbergPassthrough')
    assert.equal(nodes.length, 1)
    assert.equal(nodes[0].attrs.blockName, 'accordion')
    assert.equal(nodes[0].attrs.attrsJSON, '{"autoclose":false}')
    assert.equal(nodes[0].attrs.blockLabel, 'Accordion')
  })

  test('regenerates matching wp:accordion comments on save', () => {
    win.setContent(ACCORDION_WITH_COMMENTS)
    const out = win.getContent()
    assert.match(out, /<!-- wp:accordion \{"autoclose":false\} -->/)
    assert.match(out, /<!-- \/wp:accordion -->/)
  })
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test Scripts/test-editor-passthrough.js`
Expected: FAIL — `gutenbergPassthrough` isn't a registered node type yet, so `nodesOfType` returns an empty array and the round-trip assertions fail (the accordion content is flattened away, matching the bug from the original investigation).

- [ ] **Step 3: Add the CSS**

In `Sources/QuillKit/Resources/editor.html`, immediately after the existing `.gallery-card` CSS block (after the `body.dark .gallery-card-hint { color: #777; }` line, before `#embed-menu {`):

```css
    /* ── Passthrough card (unsupported Gutenberg block) ─── */
    .passthrough-card {
      margin: 1em 0;
      padding: 14px 16px;
      border: 1px solid rgba(0,0,0,0.14);
      border-radius: 8px;
      background: rgba(0,0,0,0.025);
      cursor: default;
      user-select: none;
    }
    .passthrough-card.selected { outline: 2px solid #b45309; outline-offset: 1px; }
    .passthrough-card-label { font-weight: 600; font-size: 13px; margin-bottom: 3px; }
    .passthrough-card-hint { font-size: 11px; color: #999; margin-top: 6px; font-style: italic; }
    body.dark .passthrough-card { border-color: rgba(255,255,255,0.18); background: rgba(255,255,255,0.04); }
    body.dark .passthrough-card-hint { color: #777; }
```

- [ ] **Step 4: Add the NodeView and node definition**

In `Sources/QuillKit/Resources/editor.html`, immediately after the `GalleryBlock` node definition (after its closing `})` around line 1719, before the `// ── Footnotes ─────` comment):

```js
    // ── Generic Gutenberg block passthrough ────────────
    // Catches any wp-block-* classed element (other than a <figure>, which
    // Quill's own image/gallery/embed/table rules already own or
    // transparently pass through) that no other, higher-priority parse rule
    // claimed. Renders as a static, non-editable "unsupported block" card;
    // saves the original markup back byte-for-byte, regenerating any
    // original wp:name comments. See docs/superpowers/specs/
    // 2026-07-12-gutenberg-passthrough-block-design.md.
    class PassthroughNodeView {
      constructor(node) {
        this.dom = document.createElement('div')
        this.dom.className = 'passthrough-card'
        const label = document.createElement('div')
        label.className = 'passthrough-card-label'
        label.textContent = node.attrs.blockLabel
        const hint = document.createElement('div')
        hint.className = 'passthrough-card-hint'
        hint.textContent = 'Unsupported block — edit via Code View (</>)'
        this.dom.append(label, hint)
      }
      selectNode()   { this.dom.classList.add('selected') }
      deselectNode() { this.dom.classList.remove('selected') }
    }

    const GutenbergPassthrough = TiptapNode.create({
      name: 'gutenbergPassthrough',
      group: 'block',
      atom: true,
      draggable: true,
      priority: 1,

      addAttributes() {
        return {
          blockLabel: { default: '' },
          blockName:  { default: null },
          attrsJSON:  { default: null },
          sourceHTML: { default: '' },
        }
      },

      parseHTML() {
        return [{
          tag: '[class*="wp-block-"]:not(figure)',
          getAttrs: el => parsePassthroughBlock(el) || false,
        }]
      },

      renderHTML({ node }) {
        const wrapper = document.createElement('div')
        wrapper.innerHTML = node.attrs.sourceHTML
        const el = wrapper.firstElementChild
        if (node.attrs.blockName) {
          el.setAttribute('data-quill-passthrough-name', node.attrs.blockName)
          if (node.attrs.attrsJSON) {
            el.setAttribute('data-quill-passthrough-attrs', node.attrs.attrsJSON)
          }
        }
        return el
      },

      addNodeView() {
        return ({ node }) => new PassthroughNodeView(node)
      },
    })

```

- [ ] **Step 5: Register the node in the extensions list**

In `Sources/QuillKit/Resources/editor.html`, in the `extensions: [...]` array, change:

```js
        EmbedBlock,
        GalleryBlock,
        FootnoteMarker,
```

to:

```js
        EmbedBlock,
        GalleryBlock,
        GutenbergPassthrough,
        FootnoteMarker,
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `node --test Scripts/test-editor-passthrough.js`
Expected: PASS

- [ ] **Step 7: Run the full JS suite to check for regressions**

Run: `node --test Scripts/test-editor.js Scripts/test-editor-keyboard.js Scripts/test-editor-gallery.js Scripts/test-editor-passthrough.js`
Expected: PASS — all suites, no regressions from the new catch-all parse rule.

- [ ] **Step 8: Register the new suite in `test.sh`**

In `test.sh`, add a line after the existing gallery-test line:

```bash
run "JS gallery tests"  node --test Scripts/test-editor-gallery.js
run "JS passthrough tests"  node --test Scripts/test-editor-passthrough.js
```

- [ ] **Step 9: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Scripts/test-editor-passthrough.js test.sh
git commit -m "feat: add gutenbergPassthrough node for unmodeled Gutenberg blocks"
```

---

### Task 5: Specificity regression guards — existing block types still parse correctly

**Files:**
- Modify: `Scripts/test-editor-passthrough.js` (add a new `describe` block)

**Interfaces:**
- Consumes: `editor.commands.setContent`, `editor.state.doc.descendants` (already used above)
- Produces: nothing new — this task is pure verification that Task 4's catch-all rule didn't regress any existing content type. This is the concrete test for the "why `<figure>` is excluded" reasoning in the spec/plan header.

- [ ] **Step 1: Write the tests**

Add to `Scripts/test-editor-passthrough.js`:

```js
describe('gutenbergPassthrough — does not steal elements other rules already claim', () => {
  test('a real gallery figure still parses as galleryBlock, not gutenbergPassthrough', () => {
    const html = '<figure class="wp-block-gallery has-nested-images columns-3 is-cropped">' +
      '<figure class="wp-block-image size-large"><img src="http://x.test/a.png" alt="" class="wp-image-1"></figure>' +
      '</figure>'
    win.setContent(html)
    assert.equal(nodesOfType('galleryBlock').length, 1)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
  })

  test('a real image figure still parses as image, not gutenbergPassthrough', () => {
    win.setContent('<figure class="wp-block-image"><img src="http://x.test/a.png" alt=""></figure>')
    assert.equal(nodesOfType('image').length, 1)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
  })

  test('a real embed figure still parses as embedBlock, not gutenbergPassthrough', () => {
    win.setContent('<figure class="wp-block-embed"><div class="wp-block-embed__wrapper">\nhttps://example.com/video\n</div></figure>')
    assert.equal(nodesOfType('embedBlock').length, 1)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
  })

  test('a table wrapped in figure.wp-block-table still parses as a table, not gutenbergPassthrough', () => {
    win.setContent('<figure class="wp-block-table"><table><tbody><tr><td>x</td></tr></tbody></table></figure>')
    assert.equal(nodesOfType('table').length, 1)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
  })

  test('a heading with a wp-block-heading class still parses as heading, not gutenbergPassthrough', () => {
    win.setContent('<h2 class="wp-block-heading">Title</h2>')
    assert.equal(nodesOfType('heading').length, 1)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
  })
})
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `node --test Scripts/test-editor-passthrough.js`
Expected: PASS. (These should already pass given Task 4's `:not(figure)` exclusion and the fact that heading/list/quote/code/hr rules match by bare tag, not class — this task exists to make that guarantee an explicit, permanent regression test rather than an untested assumption.)

If any of these FAIL, do not weaken the assertions — this means the precedence analysis in the spec was wrong and the parse rule's tag selector needs revisiting before proceeding.

- [ ] **Step 3: Commit**

```bash
git add Scripts/test-editor-passthrough.js
git commit -m "test: add specificity regression guards for gutenbergPassthrough"
```

---

### Task 6: Documentation

**Files:**
- Modify: `docs/testing-plan.md` (update the JS editor test count on line 20, add an entry for the new suite on line 22, add a new detail section after line ~1070)

**Interfaces:**
- Consumes: nothing
- Produces: nothing code-facing — documentation only

- [ ] **Step 1: Update the JS editor test count and add the new suite to the summary list**

`Scripts/test-editor.js` gains 15 tests across Tasks 1–3 (1 `formatHTML` div test + 10 `passthroughLabelFromClass`/`passthroughLabelFromBlockName`/`parsePassthroughBlock` tests + 4 `toWordPressHTML` passthrough-comment tests), so its documented count goes from 120 to 135. `Scripts/test-editor-passthrough.js` is new, with 11 tests (4 class-only + 2 comment-wrapped + 5 specificity guards from Tasks 4–5).

In `docs/testing-plan.md`, change line 20 from:

```markdown
2. **JS editor tests** — `node --test Scripts/test-editor.js` (120 tests via Node's built-in runner + jsdom)
```

to:

```markdown
2. **JS editor tests** — `node --test Scripts/test-editor.js` (135 tests via Node's built-in runner + jsdom)
```

Change line 22 from:

```markdown
4. **JS gallery tests** — `node --test Scripts/test-editor-gallery.js` (19 tests — live Tiptap editor in jsdom)
```

to:

```markdown
4. **JS gallery tests** — `node --test Scripts/test-editor-gallery.js` (19 tests — live Tiptap editor in jsdom)
5. **JS passthrough tests** — `node --test Scripts/test-editor-passthrough.js` (11 tests — live Tiptap editor in jsdom)
```

- [ ] **Step 2: Add a detail section**

After the existing `## JS gallery tests (19 tests)` section (ends around line 1114, right before the next `##` heading), add:

```markdown
## JS passthrough tests (11 tests)

File: `Scripts/test-editor-passthrough.js`
Editor file: `Sources/QuillKit/Resources/editor.html`

Tests load the real `editor.html` in jsdom and instantiate the live Tiptap editor via `window._tiptapEditor` — the same approach as the JS gallery/keyboard tests — because `gutenbergPassthrough`'s `parseHTML`/`renderHTML` can't be exercised through the pure `editor-transforms.js` helpers alone.

### `gutenbergPassthrough` — class-only markup, no wp: comments (4 tests)

| Test | What it checks |
|---|---|
| `parses into a single gutenbergPassthrough node` | An accordion's `div.wp-block-accordion` (no adjacent comments) parses into exactly one `gutenbergPassthrough` node with `blockLabel: 'Accordion'`, `blockName: null` |
| `round-trips the essential markup through getContent()` | `data-wp-interactive`, the heading toggle class, and list item text all survive a save with no `<!--` comments introduced |
| `an unrelated edit elsewhere in the document does not disturb the passthrough node` | Typing into a paragraph before the accordion doesn't touch the accordion's markup — it's a real schema node, not text riding on the `_rawHTML` safety net |
| `renders a static card, not the raw accordion markup, in the editor DOM` | The live editor DOM shows a `.passthrough-card` labeled "Accordion", not an actual clickable `<button class="wp-block-accordion-heading__toggle">` |

### `gutenbergPassthrough` — comment-wrapped markup (2 tests)

| Test | What it checks |
|---|---|
| `recovers blockName and attrsJSON from adjacent comments` | `<!-- wp:accordion {"autoclose":false} -->`/`<!-- /wp:accordion -->` around the same markup populates `blockName: 'accordion'`, `attrsJSON: '{"autoclose":false}'` |
| `regenerates matching wp:accordion comments on save` | Saving re-emits `<!-- wp:accordion {"autoclose":false} -->`/`<!-- /wp:accordion -->` around the element |

### `gutenbergPassthrough` — does not steal elements other rules already claim (5 tests)

| Test | What it checks |
|---|---|
| `a real gallery figure still parses as galleryBlock, not gutenbergPassthrough` | `figure.wp-block-gallery` still parses as `galleryBlock` |
| `a real image figure still parses as image, not gutenbergPassthrough` | `figure.wp-block-image` still parses as `image` |
| `a real embed figure still parses as embedBlock, not gutenbergPassthrough` | `figure.wp-block-embed` still parses as `embedBlock` |
| `a table wrapped in figure.wp-block-table still parses as a table, not gutenbergPassthrough` | Regression guard for the precedence gap found during planning: the table's figure wrapper has no dedicated rule of its own and relies on `:not(figure)` to stay out of the catch-all's reach |
| `a heading with a wp-block-heading class still parses as heading, not gutenbergPassthrough` | Bare-tag rules (heading, by extension list, quote, code, hr) keep winning regardless of their `wp-block-*` class |
```

- [ ] **Step 3: Run the full test suite**

Run: `./test.sh`
Expected: all suites pass, including the new one.

- [ ] **Step 4: Rebuild and manually verify**

Run: `./build.sh`, then `open Quill.app`. Open a local draft, enter code view, paste the reproduction accordion markup from this investigation, exit code view, and confirm an "Accordion" card appears instead of flattened text. Make an unrelated edit elsewhere in the post, save, re-enter code view, and confirm the accordion's original markup is still present.

- [ ] **Step 5: Run the `claude-md-management:revise-claude-md` skill**

Per this project's own `CLAUDE.md` ("After major changes: run the `claude-md-management:revise-claude-md` skill to keep this file current"), invoke it now to fold in what was learned this session — in particular the `figure` exclusion precedence gotcha from Task 4/5 and the new `gutenbergPassthrough` node's place in the Gutenberg-compatibility reference table in `Sources/QuillKit/Resources/CLAUDE.md`.

- [ ] **Step 6: Commit**

```bash
git add docs/testing-plan.md
git commit -m "docs: document gutenbergPassthrough test suite"
```
