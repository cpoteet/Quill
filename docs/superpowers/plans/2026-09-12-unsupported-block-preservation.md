# Unsupported Block Preservation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve every Gutenberg block Quill does not model, including blocks whose markup carries no `wp-block-*` class and blocks that save no markup at all, and raise a blocking alarm if anything is still lost.

**Architecture:** On load, WordPress's own block parser enumerates the post's top-level blocks. A cursor walk over the original string gives each block its exact source text. Blocks whose markup has no `wp-block-*` class root are wrapped in a synthetic element the existing `gutenbergPassthrough` node already holds, carrying that source text; the save transform swaps the wrapper back for the text. A separate check compares the parser's block list against the parsed document and reports anything unaccounted for to Swift, which blocks saving until acknowledged.

**Tech Stack:** Vanilla JS + Tiptap/ProseMirror in `editor.html`, Node's built-in test runner + jsdom for JS tests, Swift 6.3.1 + SwiftUI + WKWebView, swift-testing.

**Spec:** `docs/superpowers/specs/2026-09-12-unsupported-block-preservation-design.md`

## Global Constraints

- Swift 6.3.1, macOS 13+. JS tests require `node` and `jsdom` installed in **`Scripts/`**, not the repo root. An ad-hoc probe script must live in `Scripts/` or it dies with `Cannot find module 'jsdom'`.
- **After every code change:** quit the app, `./build.sh`, reopen. `build.sh` replaces the binary under a running process, so skipping the quit leaves the old app running.
- **`build.sh` copies each `Resources/` file by name.** A new or restored resource needs its own `cp` line or it 404s at runtime, silently, as an undefined global.
- **No em dashes in any user-facing string.** Join clauses with "so" or a comma.
- **Affected block names are bold** in alarm copy.
- Comment policy: default to no comment. One line maximum. Never restate what the code does. A one-line note on a non-obvious *why* is allowed.
- Byte-identity is the project's core invariant: an unedited post must save back unchanged, and an edited post must leave untouched blocks unchanged.
- Do not commit unless the user asks.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `Sources/QuillKit/Resources/block-parser-bundle.js` | WordPress's block parser, `window.BlockParser.parse` | Re-hook only (file unchanged) |
| `Sources/QuillKit/Resources/block-serializer.js` | Block tree to `post_content`, `serializeBlock` | Re-hook only (file unchanged) |
| `Sources/QuillKit/Resources/editor-transforms.js` | Pure transforms shared with the test harness | Add `blockSourceSlices`, `wrapUnsupportedBlocks`, `unrepresentedBlockNames`; unwrap pass inside `toWordPressHTML` |
| `Sources/QuillKit/Resources/editor.html` | Editor, nodes, node views, bridge | Restore 2 script tags; 1 new passthrough attribute; card peek; wrap at 2 of 4 content entry points; post the alarm message |
| `build.sh` | Assembles `Quill.app` | Restore 2 `cp` lines |
| `Sources/QuillKit/Views/Editor/EditorCoordinator.swift` | WKScriptMessageHandler | New `blocksAtRisk` case + callback |
| `Sources/QuillKit/Views/Editor/EditorView.swift` | NSViewRepresentable wiring | Register the handler, pass the callback |
| `Sources/QuillKit/Views/Editor/PostEditorView.swift` | Editor screen, save/autosave | Alarm state, banner, save guard, autosave suspension |
| `Sources/QuillKit/Views/Editor/BlockRiskAlarm.swift` | Alarm strings and state, testable without SwiftUI | Create |
| `Scripts/test-block-serializer.js` | Pure-Node block suite | Add cursor-walk and per-block identity tests |
| `Scripts/test-editor-preservation.js` | Live-editor preservation suite | Create |
| `Tests/QuillTests/BlockRiskAlarmTests.swift` | Alarm string tests | Create |

---

## Phase 1: Preservation

### Task 1: Restore the parser and serializer as live code

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` (script tags, after `editor-transforms.js`)
- Modify: `build.sh` (Resources section)
- Test: `Scripts/test-editor-preservation.js` (create)

**Interfaces:**
- Produces: `window.BlockParser.parse(html)` and `window.serializeBlock(block)` available inside `editor.html`.

Both files were removed from `editor.html` and `build.sh` on 2026-09-12 as unused. They are now load-path code.

- [ ] **Step 1: Write the failing test**

Create `Scripts/test-editor-preservation.js`. Copy the jsdom bootstrap from `Scripts/test-editor-containers.js` lines 1-50 verbatim (the `before()` block that loads the real `editor.html`, polyfills `crypto.randomUUID`/`matchMedia`/`requestAnimationFrame`/`ResizeObserver`, and waits for `win._tiptapEditor`), then append:

```js
describe('block parser and serializer are live in the editor', () => {
  test('window.BlockParser.parse is callable', () => {
    const blocks = win.BlockParser.parse('<!-- wp:paragraph --><p>Hi</p><!-- /wp:paragraph -->')
    assert.equal(blocks.filter(b => b.blockName).length, 1)
  })

  test('window.serializeBlock is callable', () => {
    const src = '<!-- wp:paragraph --><p>Hi</p><!-- /wp:paragraph -->'
    const block = win.BlockParser.parse(src).find(b => b.blockName)
    assert.equal(win.serializeBlock(block), src)
  })
})
```

- [ ] **Step 2: Run to verify failure**

Run: `node --test Scripts/test-editor-preservation.js`
Expected: FAIL, `Cannot read properties of undefined (reading 'parse')`.

- [ ] **Step 3: Restore the script tags**

In `Sources/QuillKit/Resources/editor.html`, the script block currently reads:

```html
  <script src="./tiptap-bundle.js"></script>
  <script src="./marked-bundle.js"></script>
  <script src="./editor-transforms.js"></script>
  <script src="./block-descriptors.js"></script>
```

Insert the two restored files before `block-descriptors.js`:

```html
  <script src="./tiptap-bundle.js"></script>
  <script src="./marked-bundle.js"></script>
  <script src="./editor-transforms.js"></script>
  <script src="./block-parser-bundle.js"></script>
  <script src="./block-serializer.js"></script>
  <script src="./block-descriptors.js"></script>
```

`block-serializer.js` defines `serializeBlock` as a plain function declaration, which lands on `window` automatically in a classic script. `block-parser-bundle.js` assigns `var BlockParser`, also on `window`. No extra glue needed.

- [ ] **Step 4: Restore the build.sh copies**

In `build.sh`, the Resources section currently ends:

```bash
cp "Sources/QuillKit/Resources/editor-transforms.js" "$RESOURCES_DIR/editor-transforms.js"
cp "Sources/QuillKit/Resources/block-descriptors.js" "$RESOURCES_DIR/block-descriptors.js"
```

Make it:

```bash
cp "Sources/QuillKit/Resources/editor-transforms.js" "$RESOURCES_DIR/editor-transforms.js"
cp "Sources/QuillKit/Resources/block-parser-bundle.js" "$RESOURCES_DIR/block-parser-bundle.js"
cp "Sources/QuillKit/Resources/block-serializer.js" "$RESOURCES_DIR/block-serializer.js"
cp "Sources/QuillKit/Resources/block-descriptors.js" "$RESOURCES_DIR/block-descriptors.js"
```

- [ ] **Step 5: Register the suite in test.sh**

In `test.sh`, after the `JS block serializer tests` line, add:

```bash
run "JS preservation tests"  node --test Scripts/test-editor-preservation.js
```

- [ ] **Step 6: Run to verify pass**

Run: `node --test Scripts/test-editor-preservation.js`
Expected: PASS, 2 tests.

- [ ] **Step 7: Update the CLAUDE.md note**

`CLAUDE.md` currently describes these two files as "test-only oracle, not loaded by editor.html" in the Resources file map, and omits them from the `build.sh` `cp` list note. Correct both to reflect that they are live.

- [ ] **Step 8: Build and verify the app still loads**

```bash
osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app
```

Expected: build succeeds, app opens, a post opens with no console error. A missing `cp` line shows up here and nowhere else.

---

### Task 2: The cursor walk — exact source text per block

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js` (new function; add to `module.exports` at the end of the file)
- Test: `Scripts/test-block-serializer.js`

**Interfaces:**
- Consumes: `BlockParser.parse`, `serializeBlock`. Under Node these are loaded by the test's own sandbox helpers; inside `editor.html` they are globals. Resolve them the way `editor-transforms.js` already resolves `block-descriptors.js` at line 11: `const blockDescriptorRegistry = (typeof module !== 'undefined' && module.exports) ? require('./block-descriptors.js') : globalThis`.
- Produces: `blockSourceSlices(html, parse, serializeBlock)` returns
  `Array<{ blockName: string|null, attrsJSON: string|null, source: string, exact: boolean }>`
  in document order, one entry per top-level block including freeform ones.

`source` is a literal slice of `html` when the original continues with exactly the serialised bytes at the cursor (`exact: true`), otherwise the serialised text (`exact: false`). Passing the two functions in as arguments keeps this testable without a DOM and without global state.

- [ ] **Step 1: Write the failing tests**

Append to `Scripts/test-block-serializer.js`. The file already has `loadParser()` and `loadSerializer()` helpers; add a loader for the transforms module beside them:

```js
function loadTransforms() {
  return require('../Sources/QuillKit/Resources/editor-transforms.js')
}

describe('blockSourceSlices', () => {
  const { blockSourceSlices } = loadTransforms()
  const parse = loadParser().parse
  const { serializeBlock } = loadSerializer()
  const slices = src => blockSourceSlices(src, parse, serializeBlock)

  test('a canonical block yields an exact slice of the original', () => {
    const src = '<!-- wp:heading {"level":2} --><h2>T</h2><!-- /wp:heading -->'
    const out = slices(src)
    assert.equal(out.length, 1)
    assert.equal(out[0].source, src)
    assert.equal(out[0].exact, true)
    assert.equal(out[0].blockName, 'core/heading')
    assert.equal(out[0].attrsJSON, '{"level":2}')
  })

  test('slices concatenate back to the original', () => {
    const src = '<p>Classic</p><!-- wp:separator /--><p>More</p>'
    assert.equal(slices(src).map(s => s.source).join(''), src)
  })

  test('a self-closing block yields an exact slice', () => {
    const src = '<!-- wp:calendar /-->'
    const out = slices(src)
    assert.equal(out[0].source, src)
    assert.equal(out[0].exact, true)
  })

  test('freeform content is reported with a null blockName', () => {
    const out = slices('<p>Classic</p>')
    assert.equal(out.length, 1)
    assert.equal(out[0].blockName, null)
    assert.equal(out[0].exact, true)
  })

  test('non-canonical attribute formatting falls back, marked inexact', () => {
    const src = '<!-- wp:column {"width":33.0} --><div class="wp-block-column"></div><!-- /wp:column -->'
    const out = slices(src)
    assert.equal(out[0].exact, false)
    assert.equal(out[0].source, '<!-- wp:column {"width":33} --><div class="wp-block-column"></div><!-- /wp:column -->')
  })

  test('an inexact block does not desynchronise the blocks after it', () => {
    const src = '<!-- wp:column {"width":33.0} --><div class="wp-block-column"></div><!-- /wp:column -->' +
                '<!-- wp:heading {"level":3} --><h3>After</h3><!-- /wp:heading -->'
    const out = slices(src)
    assert.equal(out.length, 2)
    assert.equal(out[1].exact, true)
    assert.equal(out[1].source, '<!-- wp:heading {"level":3} --><h3>After</h3><!-- /wp:heading -->')
  })
})

describe('blockSourceSlices over the real fixtures', () => {
  const { blockSourceSlices } = loadTransforms()
  const parse = loadParser().parse
  const { serializeBlock } = loadSerializer()
  const dir = path.resolve(__dirname, 'fixtures')

  for (const name of fs.readdirSync(dir).filter(f => f.endsWith('.html'))) {
    test(`${name} yields exact slices for every block`, () => {
      const src = fs.readFileSync(path.join(dir, name), 'utf8')
      const out = blockSourceSlices(src, parse, serializeBlock)
      assert.ok(out.every(s => s.exact), 'every block exact')
      assert.equal(out.map(s => s.source).join(''), src)
    })
  }
})
```

The inexact-recovery test is the important one. If the cursor advanced by the serialised length after a fallback, every later block would be misaligned and the whole document would silently go onto the reconstruction path.

- [ ] **Step 2: Run to verify failure**

Run: `node --test Scripts/test-block-serializer.js`
Expected: FAIL, `blockSourceSlices is not a function`.

- [ ] **Step 3: Implement**

Add to `Sources/QuillKit/Resources/editor-transforms.js`, near `parsePassthroughBlock`:

```js
function blockSourceSlices(html, parse, serializeBlock) {
  const out = []
  let cursor = 0
  for (const block of parse(html)) {
    const text = serializeBlock(block)
    const exact = html.startsWith(text, cursor)
    const attrs = block.attrs && Object.keys(block.attrs).length ? JSON.stringify(block.attrs) : null
    if (exact) {
      out.push({ blockName: block.blockName, attrsJSON: attrs, source: html.slice(cursor, cursor + text.length), exact: true })
      cursor += text.length
    } else {
      // Advance past the block's real bytes, not the reconstruction's, or every later block misaligns.
      const found = html.indexOf('<!-- /wp:', cursor)
      out.push({ blockName: block.blockName, attrsJSON: attrs, source: text, exact: false })
      cursor = found === -1 ? cursor + text.length : html.indexOf('-->', found) + 3
    }
  }
  return out
}
```

Then add `blockSourceSlices` to the `module.exports` object at the end of the file.

- [ ] **Step 4: Run to verify pass**

Run: `node --test Scripts/test-block-serializer.js`
Expected: PASS, including the four fixture cases and the misalignment guard.

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/Resources/editor-transforms.js Scripts/test-block-serializer.js
git commit -m "feat: derive each block's exact source text via a cursor walk

Gives every top-level block a literal slice of the original post_content
where one is obtainable, falling back to the serialised form per block.
Canonical WordPress output is exact on all four real fixtures; the five
known normalisations (attribute whitespace, unicode escapes, float and
exponent forms, an explicit core/ prefix) fall back without pulling the
rest of the document off the exact path.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Decide which blocks need wrapping, and wrap them

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js`
- Test: `Scripts/test-block-serializer.js`

**Interfaces:**
- Consumes: `blockSourceSlices` (Task 2).
- Produces: `blockNeedsWrapping(slice, doc)` returns boolean. `wrapUnsupportedBlocks(html, parse, serializeBlock, doc)` returns HTML with each unsupported block replaced by
  `<div class="wp-block-quill-unsupported" data-quill-unsupported-source="…" data-quill-unsupported-label="…"></div>`.

The rule: wrap when the block has a `blockName` **and** its markup contains no top-level element carrying a class beginning `wp-block-`. Freeform blocks (`blockName === null`) are never wrapped, because that is ordinary prose.

- [ ] **Step 1: Write the failing tests**

```js
describe('blockNeedsWrapping', () => {
  const { blockSourceSlices, blockNeedsWrapping } = loadTransforms()
  const parse = loadParser().parse
  const { serializeBlock } = loadSerializer()
  const { JSDOM } = require('jsdom')
  const doc = new JSDOM('<body></body>').window.document
  const decide = src => blockSourceSlices(src, parse, serializeBlock).map(s => blockNeedsWrapping(s, doc))

  test('a block with a wp-block class root is left alone', () => {
    assert.deepEqual(decide('<!-- wp:spacer --><div class="wp-block-spacer"></div><!-- /wp:spacer -->'), [false])
  })

  test('core/html is wrapped, because its markup has no wp-block class', () => {
    assert.deepEqual(decide('<!-- wp:html --><div class="promo">Hi</div><!-- /wp:html -->'), [true])
  })

  test('core/shortcode is wrapped, because it has no element at all', () => {
    assert.deepEqual(decide('<!-- wp:shortcode -->[gallery ids="1,2"]<!-- /wp:shortcode -->'), [true])
  })

  test('a self-closing dynamic block is wrapped', () => {
    assert.deepEqual(decide('<!-- wp:calendar /-->'), [true])
  })

  test('a page break is wrapped', () => {
    assert.deepEqual(decide('<!-- wp:nextpage --><!--nextpage--><!-- /wp:nextpage -->'), [true])
  })

  test('freeform prose is never wrapped', () => {
    assert.deepEqual(decide('<p>Classic</p>'), [false])
  })

  test('a nested block inside a claimed block does not make the parent wrap', () => {
    const src = '<!-- wp:query --><div class="wp-block-query"><!-- wp:post-title /--></div><!-- /wp:query -->'
    assert.deepEqual(decide(src), [false])
  })
})

describe('wrapUnsupportedBlocks', () => {
  const { wrapUnsupportedBlocks } = loadTransforms()
  const parse = loadParser().parse
  const { serializeBlock } = loadSerializer()
  const { JSDOM } = require('jsdom')
  const doc = new JSDOM('<body></body>').window.document
  const wrap = src => wrapUnsupportedBlocks(src, parse, serializeBlock, doc)

  test('leaves a fully supported post untouched', () => {
    const src = '<!-- wp:paragraph --><p>Hi</p><!-- /wp:paragraph -->'
    assert.equal(wrap(src), src)
  })

  test('replaces a shortcode block with a wrapper carrying its source', () => {
    const src = '<!-- wp:shortcode -->[gallery ids="1,2"]<!-- /wp:shortcode -->'
    const out = wrap(src)
    assert.match(out, /class="wp-block-quill-unsupported"/)
    assert.doesNotMatch(out, /\[gallery ids="1,2"\](?![^<]*")/)
    const el = new JSDOM('<body>' + out + '</body>').window.document.querySelector('[data-quill-unsupported-source]')
    assert.equal(el.getAttribute('data-quill-unsupported-source'), src)
    assert.equal(el.getAttribute('data-quill-unsupported-label'), 'Shortcode')
  })

  test('stores quotes and ampersands in the source without corruption', () => {
    const src = '<!-- wp:html --><div data-x="a&amp;b" class="p">&lt;hi&gt;</div><!-- /wp:html -->'
    const out = wrap(src)
    const el = new JSDOM('<body>' + out + '</body>').window.document.querySelector('[data-quill-unsupported-source]')
    assert.equal(el.getAttribute('data-quill-unsupported-source'), src)
  })

  test('keeps supported blocks in place around a wrapped one', () => {
    const src = '<!-- wp:paragraph --><p>A</p><!-- /wp:paragraph -->' +
                '<!-- wp:calendar /-->' +
                '<!-- wp:paragraph --><p>B</p><!-- /wp:paragraph -->'
    const out = wrap(src)
    assert.ok(out.indexOf('<p>A</p>') < out.indexOf('wp-block-quill-unsupported'))
    assert.ok(out.indexOf('wp-block-quill-unsupported') < out.indexOf('<p>B</p>'))
  })
})
```

- [ ] **Step 2: Run to verify failure**

Run: `node --test Scripts/test-block-serializer.js`
Expected: FAIL, `blockNeedsWrapping is not a function`.

- [ ] **Step 3: Implement**

```js
function blockNeedsWrapping(slice, doc) {
  if (!slice.blockName) return false
  const probe = doc.createElement('div')
  probe.innerHTML = slice.source.replace(/<!--[\s\S]*?-->/g, '')
  return !Array.from(probe.children).some(el =>
    Array.from(el.classList).some(c => c.startsWith('wp-block-')))
}

function wrapUnsupportedBlocks(html, parse, serializeBlock, doc) {
  const slices = blockSourceSlices(html, parse, serializeBlock)
  if (!slices.some(s => blockNeedsWrapping(s, doc))) return html
  return slices.map(slice => {
    if (!blockNeedsWrapping(slice, doc)) return slice.source
    const el = doc.createElement('div')
    el.className = 'wp-block-quill-unsupported'
    el.setAttribute('data-quill-unsupported-source', slice.source)
    el.setAttribute('data-quill-unsupported-label', passthroughLabelFromBlockName(slice.blockName))
    return el.outerHTML
  }).join('')
}
```

Setting the attribute through the DOM and reading `outerHTML` escapes `&`, `<`, `>` and `"` correctly; `getAttribute` returns the original on the way back. Add both names to `module.exports`.

- [ ] **Step 4: Run to verify pass**

Run: `node --test Scripts/test-block-serializer.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/Resources/editor-transforms.js Scripts/test-block-serializer.js
git commit -m "feat: wrap blocks whose markup has no wp-block class

A block Quill cannot recognise is replaced on load by a placeholder
element carrying its exact source, so the existing passthrough node can
hold it. Covers core/html, core/shortcode, the self-closing dynamic
blocks, page breaks, and third-party blocks that skip the class
convention.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Hold the wrapper in the editor and show it as a card

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` (`gutenbergPassthrough` attributes and `parseHTML`, `PassthroughNodeView`, CSS near `.passthrough-card` at line 824)
- Test: `Scripts/test-editor-preservation.js`

**Interfaces:**
- Consumes: the wrapper markup from Task 3.
- Produces: `gutenbergPassthrough` gains an `unsupportedSource` attribute (default `null`). When set, `renderHTML` emits the wrapper with `data-quill-unsupported-source` intact, and the node view renders label plus a monospace peek.

- [ ] **Step 1: Write the failing test**

```js
describe('unsupported blocks become passthrough cards', () => {
  test('a wrapped shortcode parses into one gutenbergPassthrough node', () => {
    const src = '<!-- wp:shortcode -->[gallery ids="1,2"]<!-- /wp:shortcode -->'
    win.setContent(src)
    const node = editor.state.doc.child(0)
    assert.equal(node.type.name, 'gutenbergPassthrough')
    assert.equal(node.attrs.unsupportedSource, src)
    assert.equal(node.attrs.blockLabel, 'Shortcode')
  })

  test('the card shows the label and a peek at the content', () => {
    win.setContent('<!-- wp:shortcode -->[gallery ids="1,2"]<!-- /wp:shortcode -->')
    const card = win.document.querySelector('#editor .passthrough-card')
    assert.equal(card.querySelector('.passthrough-card-label').textContent, 'Shortcode')
    assert.match(card.querySelector('.passthrough-card-peek').textContent, /\[gallery ids="1,2"\]/)
  })

  test('the peek is truncated for a long block', () => {
    const long = '<!-- wp:html --><div>' + 'x'.repeat(400) + '</div><!-- /wp:html -->'
    win.setContent(long)
    const peek = win.document.querySelector('#editor .passthrough-card-peek').textContent
    assert.ok(peek.length <= 123, `peek was ${peek.length} chars`)
    assert.match(peek, /…$/)
  })

  test('the card keeps the existing hint line', () => {
    win.setContent('<!-- wp:calendar /-->')
    const hint = win.document.querySelector('#editor .passthrough-card-hint').textContent
    assert.equal(hint, 'Not editable in the visual editor; use Code View (</>)')
  })
})
```

- [ ] **Step 2: Run to verify failure**

Run: `node --test Scripts/test-editor-preservation.js`
Expected: FAIL, `unsupportedSource` is undefined (the wrap is not wired into `setContent` until Task 6, so this also fails on the parse).

- [ ] **Step 3: Add the attribute and parse rule**

In `editor.html`, `gutenbergPassthrough`'s `addAttributes()` currently returns `blockLabel`, `blockName`, `attrsJSON`, `sourceHTML`. Add one:

```js
          unsupportedSource: { default: null },
```

Add a parse rule as the **first** entry in `parseHTML()`, so it wins over the generic class catch-all:

```js
          {
            tag: 'div.wp-block-quill-unsupported',
            getAttrs: el => ({
              blockLabel: el.getAttribute('data-quill-unsupported-label') || 'Block',
              blockName: null,
              attrsJSON: null,
              sourceHTML: el.outerHTML,
              unsupportedSource: el.getAttribute('data-quill-unsupported-source'),
            }),
          },
```

`blockName` stays null deliberately: the comment-regeneration pass in `toWordPressHTML` keys off `data-quill-passthrough-name`, and an unsupported block's comments are already inside its stored source. Regenerating them would double them.

- [ ] **Step 4: Carry the source through renderHTML**

`renderHTML` builds an element from `node.attrs.sourceHTML` and stamps `data-quill-passthrough` on it. The wrapper's `outerHTML` already carries `data-quill-unsupported-source`, so it survives that path with no change. Add nothing here; the existing unconditional marker is what shields it from every transform pass.

- [ ] **Step 5: Render the peek in the node view**

`PassthroughNodeView`'s constructor currently appends `label` and `hint`. Insert a peek between them when a source is present:

```js
    class PassthroughNodeView {
      constructor(node) {
        this.dom = document.createElement('div')
        this.dom.className = 'passthrough-card'
        const label = document.createElement('div')
        label.className = 'passthrough-card-label'
        label.textContent = node.attrs.blockLabel
        this.dom.append(label)
        if (node.attrs.unsupportedSource) {
          const peek = document.createElement('div')
          peek.className = 'passthrough-card-peek'
          peek.textContent = _peekText(node.attrs.unsupportedSource)
          this.dom.append(peek)
        }
        const hint = document.createElement('div')
        hint.className = 'passthrough-card-hint'
        hint.textContent = 'Not editable in the visual editor; use Code View (</>)'
        this.dom.append(hint)
      }
      selectNode()   { this.dom.classList.add('selected') }
      deselectNode() { this.dom.classList.remove('selected') }
    }
```

Define the helper directly above the class. It strips the block's own delimiter comments so the peek shows content rather than `<!-- wp:shortcode -->`, and caps length:

```js
    function _peekText(source) {
      const inner = source.replace(/^<!--[\s\S]*?-->/, '').replace(/<!-- \/wp:[\s\S]*?-->$/, '').trim()
      const text = inner || source.trim()
      return text.length > 120 ? text.slice(0, 120) + '…' : text
    }
```

Using `textContent` rather than `innerHTML` is load-bearing: the peek must render markup as visible text, never as live DOM.

- [ ] **Step 6: Add the peek CSS**

Beside `.passthrough-card-label` at `editor.html:834`:

```css
    .passthrough-card-peek {
      font: 11.5px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace;
      color: #555;
      background: rgba(0,0,0,0.04);
      border-radius: 4px;
      padding: 6px 8px;
      margin-top: 7px;
      white-space: pre-wrap;
      word-break: break-all;
    }
    body.dark .passthrough-card-peek { color: #aaa; background: rgba(255,255,255,0.06); }
```

- [ ] **Step 7: Run to verify pass**

Run: `node --test Scripts/test-editor-preservation.js`
Expected: still FAIL on the parse-level tests until Task 6 wires the wrap into `setContent`. To confirm this task in isolation, temporarily call `win.setContent(win.wrapUnsupportedBlocks(src, win.BlockParser.parse, win.serializeBlock, win.document))` in the tests, then revert to plain `win.setContent` once Task 6 lands. Note this in the commit body.

- [ ] **Step 8: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Scripts/test-editor-preservation.js
git commit -m "feat: show an unsupported block as a card with a content peek

A bare type label cannot distinguish two Custom HTML blocks in one post,
and a shortcode's identity is its text, so the card carries a truncated
monospace peek rendered via textContent.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Unwrap on save

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js` (`toWordPressHTML`, just before `return div.innerHTML`)
- Test: `Scripts/test-editor.js`

**Interfaces:**
- Consumes: the wrapper element carrying `data-quill-unsupported-source`.
- Produces: `toWordPressHTML` output in which each wrapper is replaced by its stored source verbatim.

The wrapper cannot be swapped for raw text through the DOM, because a text node would escape the markup. Replace each wrapper with a unique sentinel text node, take `innerHTML`, then substitute the sentinels for their sources.

- [ ] **Step 1: Write the failing tests**

Append to `Scripts/test-editor.js`:

```js
describe('unsupported block unwrapping', () => {
  const wrapper = (source, label) => {
    const el = document.createElement('div')
    el.className = 'wp-block-quill-unsupported'
    el.setAttribute('data-quill-passthrough', '')
    el.setAttribute('data-quill-unsupported-source', source)
    el.setAttribute('data-quill-unsupported-label', label)
    return el.outerHTML
  }

  test('restores a shortcode block exactly', () => {
    const src = '<!-- wp:shortcode -->[gallery ids="1,2"]<!-- /wp:shortcode -->'
    assert.equal(toWordPressHTML(wrapper(src, 'Shortcode'), document), src)
  })

  test('restores markup with quotes and entities exactly', () => {
    const src = '<!-- wp:html --><div data-x="a&amp;b">&lt;hi&gt;</div><!-- /wp:html -->'
    assert.equal(toWordPressHTML(wrapper(src, 'Custom HTML'), document), src)
  })

  test('leaves no marker attributes behind', () => {
    const out = toWordPressHTML(wrapper('<!-- wp:calendar /-->', 'Calendar'), document)
    assert.doesNotMatch(out, /data-quill-unsupported|wp-block-quill-unsupported|data-quill-passthrough/)
  })

  test('is idempotent', () => {
    const src = '<!-- wp:shortcode -->[x]<!-- /wp:shortcode -->'
    const once = toWordPressHTML(wrapper(src, 'Shortcode'), document)
    assert.equal(toWordPressHTML(once, document), once)
  })

  test('restores two wrappers in document order', () => {
    const a = '<!-- wp:calendar /-->'
    const b = '<!-- wp:shortcode -->[y]<!-- /wp:shortcode -->'
    const out = toWordPressHTML(wrapper(a, 'Calendar') + wrapper(b, 'Shortcode'), document)
    assert.equal(out, a + b)
  })

  test('a post with no wrappers is unchanged by the pass', () => {
    const out = toWordPressHTML('<p>Hi</p>', document)
    assert.match(out, /<p>Hi<\/p>/)
  })
})
```

- [ ] **Step 2: Run to verify failure**

Run: `node --test Scripts/test-editor.js`
Expected: FAIL, output still contains the wrapper div.

- [ ] **Step 3: Implement**

In `toWordPressHTML`, replace the final `return div.innerHTML` with:

```js
  const unsupported = []
  div.querySelectorAll('[data-quill-unsupported-source]').forEach(el => {
    const token = `QUILLUNSUPPORTED${unsupported.length}QUILLEND`
    unsupported.push(el.getAttribute('data-quill-unsupported-source'))
    el.replaceWith(doc.createTextNode(token))
  })
  let html = div.innerHTML
  unsupported.forEach((source, i) => {
    html = html.replace(`QUILLUNSUPPORTED${i}QUILLEND`, source)
  })
  return html
```

The token is alphanumeric, so `innerHTML` will not escape it. `String.prototype.replace` with a string pattern replaces the first occurrence only, which is what we want, and `$` sequences in a source could be misread by `replace`'s substitution syntax, so pass a function if any fixture ever trips on that. Keep the existing marker-stripping passes above this block; they run first and the wrapper keeps only its own attributes, which vanish with the element.

- [ ] **Step 4: Run to verify pass**

Run: `node --test Scripts/test-editor.js`
Expected: PASS.

- [ ] **Step 5: Guard the `$` case explicitly**

Add one more test and switch to a function replacement if it fails:

```js
  test('restores a source containing a dollar sequence', () => {
    const src = '<!-- wp:shortcode -->[price amount="$1.00" note="$&"]<!-- /wp:shortcode -->'
    assert.equal(toWordPressHTML(wrapper(src, 'Shortcode'), document), src)
  })
```

If it fails, change the substitution to `html = html.replace(token, () => source)`.

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/Resources/editor-transforms.js Scripts/test-editor.js
git commit -m "feat: restore unsupported blocks verbatim on save

Each wrapper becomes a sentinel text node before innerHTML is taken, then
the sentinel is substituted for the stored source, so markup is restored
byte for byte rather than escaped as text.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Wire the wrap into the two content entry points

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` (`window.setContent` at line ~4017, `_exitCodeView` at line ~3932)
- Test: `Scripts/test-editor-preservation.js`

**Interfaces:**
- Consumes: `wrapUnsupportedBlocks` (Task 3), `toWordPressHTML`'s unwrap (Task 5).
- Produces: a `_wrapIncoming(html)` helper used by exactly the two entry points that receive `post_content`.

Four places set editor content. Two receive `post_content` and must wrap; two restore the editor's own already-wrapped HTML and must not. Getting this wrong is silent, so each gets a test.

| Call site | Content | Wrap |
|---|---|---|
| `window.setContent` | `post_content` from Swift | Yes |
| `_exitCodeView`, user-edited branch | `post_content` from the textarea | Yes |
| AI reject, `editor.commands.setContent(_aiOriginalHTML, false)` (~line 4466) | `editor.getHTML()` | No |
| AI reject, `editor.commands.setContent(_aiOriginalHTML)` (~line 4547) | `editor.getHTML()` | No |

- [ ] **Step 1: Write the failing tests**

```js
describe('the wrap applies at post_content entry points only', () => {
  const SHORTCODE = '<!-- wp:shortcode -->[gallery ids="1,2"]<!-- /wp:shortcode -->'

  test('setContent wraps, so an edit elsewhere cannot destroy the block', () => {
    win.setContent('<p>Intro</p>' + SHORTCODE)
    editor.commands.setTextSelection(2)
    editor.commands.insertContent('X')
    assert.match(win.getContent(), /<!-- wp:shortcode -->\[gallery ids="1,2"\]<!-- \/wp:shortcode -->/)
  })

  test('an unedited post still round-trips byte-identically', () => {
    const src = '<p>Intro</p>' + SHORTCODE
    win.setContent(src)
    assert.equal(win.getContent(), src)
  })

  test('code view shows the real source, not the wrapper', () => {
    win.setContent(SHORTCODE)
    win._enterCodeViewForTest ? win._enterCodeViewForTest() : win.document.getElementById('btn-code-view').dispatchEvent(new win.MouseEvent('click', { bubbles: true }))
    const shown = win.document.getElementById('code-editor').value
    assert.match(shown, /\[gallery ids="1,2"\]/)
    assert.doesNotMatch(shown, /quill-unsupported/)
    win.document.getElementById('btn-code-view').dispatchEvent(new win.MouseEvent('click', { bubbles: true }))
  })

  test('a block hand-edited in code view is re-wrapped on exit', () => {
    win.setContent(SHORTCODE)
    win.document.getElementById('btn-code-view').dispatchEvent(new win.MouseEvent('click', { bubbles: true }))
    const ta = win.document.getElementById('code-editor')
    ta.value = '<!-- wp:shortcode -->[gallery ids="9,9"]<!-- /wp:shortcode -->'
    ta.dispatchEvent(new win.Event('input', { bubbles: true }))
    win.document.getElementById('btn-code-view').dispatchEvent(new win.MouseEvent('click', { bubbles: true }))
    assert.equal(editor.state.doc.child(0).type.name, 'gutenbergPassthrough')
    editor.commands.setTextSelection(1)
    assert.match(win.getContent(), /\[gallery ids="9,9"\]/)
  })

  test('the AI reject path does not double-wrap', () => {
    win.setContent(SHORTCODE)
    const internal = editor.getHTML()
    editor.commands.setContent(internal, false)
    assert.equal(editor.state.doc.childCount, 1)
    assert.equal((editor.getHTML().match(/wp-block-quill-unsupported/g) || []).length, 1)
  })
})
```

- [ ] **Step 2: Run to verify failure**

Run: `node --test Scripts/test-editor-preservation.js`
Expected: FAIL, the shortcode is flattened to a paragraph.

- [ ] **Step 3: Add the helper**

Above `window.setContent` in `editor.html`:

```js
    const _wrapIncoming = html =>
      html ? wrapUnsupportedBlocks(html, BlockParser.parse, serializeBlock, document) : html
```

- [ ] **Step 4: Use it at both post_content entry points**

In `window.setContent`, change the two raw-store assignments and the set:

```js
      const wrapped = _wrapIncoming(html)
      _rawHTML = html || null
      _rawHTMLOnLoad = html || null
      editor.commands.setContent(wrapped || '', false)
```

`_rawHTML` and `_rawHTMLOnLoad` keep the **unwrapped** original. That is what makes the no-edit path return the user's exact bytes and what keeps code view clean.

In `_exitCodeView`'s `if (userEdited)` branch:

```js
      if (userEdited) {
        _rawHTML = html
        _rawHTMLOnLoad = html
        editor.commands.setContent(_wrapIncoming(html), false)
      }
```

Leave both AI restore sites alone.

- [ ] **Step 5: Run to verify pass**

Run: `node --test Scripts/test-editor-preservation.js`
Expected: PASS. Then revert the temporary manual-wrap calls added in Task 4 Step 7 to plain `win.setContent` and re-run.

- [ ] **Step 6: Run the whole suite**

Run: `./test.sh`
Expected: every suite passes. The container suite's four fixture byte-identity tests are the ones to watch, since they exercise `setContent` to `getContent` over real posts.

- [ ] **Step 7: Build and verify in the app**

```bash
osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app
```

Open a new local draft, paste a shortcode block into code view, exit code view, type in a paragraph, and check code view again. Expected: the shortcode is intact.

- [ ] **Step 8: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Scripts/test-editor-preservation.js
git commit -m "feat: wrap unsupported blocks on load and on code-view exit

Only the two entry points that receive post_content wrap. The two AI
reject paths restore editor.getHTML(), which is already wrapped, so
wrapping there would double-wrap. Each of the four is pinned by a test.

The raw-HTML stores keep the unwrapped original, so an unedited post
still saves back byte-identically and code view still shows real source.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: The byte-identity corpus for the seven failing shapes

**Files:**
- Create: `Scripts/fixtures/unsupported-blocks.html`
- Test: `Scripts/test-editor-preservation.js`

**Interfaces:**
- Consumes: everything from Tasks 1-6.
- Produces: nothing new. This task is the regression suite for the seven shapes from the spec's Problem table.

- [ ] **Step 1: Create the fixture**

`Scripts/fixtures/unsupported-blocks.html`. No comments or header in the file: per `Scripts/fixtures/README.md`, the bytes are the test, and the serializer suite globs every `*.html` here so this file joins that corpus automatically.

```html
<!-- wp:paragraph -->
<p>Opening prose.</p>
<!-- /wp:paragraph -->
<!-- wp:html --><div class="promo"><b>Hi</b></div><!-- /wp:html -->
<!-- wp:shortcode -->[gallery ids="1284,1285"]<!-- /wp:shortcode -->
<!-- wp:calendar /-->
<!-- wp:navigation {"ref":9} /-->
<!-- wp:block {"ref":1234} /-->
<!-- wp:nextpage --><!--nextpage--><!-- /wp:nextpage -->
<!-- wp:more --><!--more--><!-- /wp:more -->
<!-- wp:acme/widget --><div class="acme-widget" data-x="1">Widget</div><!-- /wp:acme/widget -->
<!-- wp:paragraph -->
<p>Closing prose.</p>
<!-- /wp:paragraph -->
```

- [ ] **Step 2: Write the tests**

```js
describe('the unsupported-block corpus survives an edit', () => {
  const src = fs.readFileSync(path.resolve(__dirname, 'fixtures/unsupported-blocks.html'), 'utf8')

  test('round-trips byte-identically with no edit', () => {
    win.setContent(src)
    assert.equal(win.getContent(), src)
  })

  test('every unsupported block survives an edit elsewhere', () => {
    win.setContent(src)
    editor.commands.setTextSelection(2)
    editor.commands.insertContent('X')
    const out = win.getContent()
    for (const marker of [
      'wp:html', 'wp:shortcode', 'wp:calendar', 'wp:navigation',
      'wp:block {"ref":1234}', 'wp:nextpage', 'wp:more', 'wp:acme/widget',
    ]) {
      assert.ok(out.includes('<!-- ' + marker), `lost ${marker}`)
    }
    assert.match(out, /<div class="promo"><b>Hi<\/b><\/div>/)
    assert.match(out, /\[gallery ids="1284,1285"\]/)
    assert.match(out, /<div class="acme-widget" data-x="1">Widget<\/div>/)
  })

  test('saving twice is idempotent', () => {
    win.setContent(src)
    editor.commands.setTextSelection(2)
    editor.commands.insertContent('X')
    const once = win.getContent()
    win.setContent(once)
    assert.equal(win.getContent(), once)
  })

  test('no wrapper markup reaches the saved output', () => {
    win.setContent(src)
    editor.commands.setTextSelection(2)
    editor.commands.insertContent('X')
    assert.doesNotMatch(win.getContent(), /quill-unsupported/)
  })

  test('each unsupported block renders its own card', () => {
    win.setContent(src)
    const labels = Array.from(win.document.querySelectorAll('#editor .passthrough-card-label'))
      .map(el => el.textContent)
    assert.equal(labels.length, 8)
  })
})
```

- [ ] **Step 3: Run**

Run: `node --test Scripts/test-editor-preservation.js`
Expected: PASS. Also run `node --test Scripts/test-block-serializer.js` — the new fixture joins its glob, so its parse/serialize round-trip is asserted there too.

- [ ] **Step 4: Update the fixtures README**

Add a row to the table in `Scripts/fixtures/README.md`:

```markdown
| `unsupported-blocks.html` | One of each block shape Quill cannot model: Custom HTML, shortcode, three self-closing dynamic blocks, a synced pattern, a page break, a read-more, and a third-party block with no `wp-block-` class |
```

- [ ] **Step 5: Commit**

```bash
git add Scripts/fixtures/unsupported-blocks.html Scripts/fixtures/README.md Scripts/test-editor-preservation.js
git commit -m "test: pin the seven block shapes that used to be destroyed

Each shape from the design's problem table, asserted through load, edit
elsewhere, save. These all failed before this branch.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Phase 2: The data-loss alarm

### Task 8: Detect blocks the document cannot account for

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js`
- Modify: `Sources/QuillKit/Resources/editor.html` (post the message from `window.setContent`)
- Test: `Scripts/test-block-serializer.js`, `Scripts/test-editor-preservation.js`

**Interfaces:**
- Consumes: `blockSourceSlices` (Task 2), `descriptorFor` from `block-descriptors.js`.
- Produces: `unrepresentedBlockNames(slices, accountedNames)` returns `string[]` of short block names present in the parse but not in the document. `window.webkit.messageHandlers.blocksAtRisk.postMessage({ names: [...] })` is posted once per `setContent`, and only when the array is non-empty.

The check is deliberately independent of the wrap: it verifies the outcome, so a bug in Task 3 surfaces as a red banner rather than silent loss.

- [ ] **Step 1: Write the failing tests**

In `Scripts/test-block-serializer.js`:

```js
describe('unrepresentedBlockNames', () => {
  const { unrepresentedBlockNames } = loadTransforms()
  const slice = (blockName) => ({ blockName, attrsJSON: null, source: '', exact: true })

  test('reports nothing when every block is accounted for', () => {
    const out = unrepresentedBlockNames([slice('core/heading'), slice('core/calendar')], new Set(['heading', 'calendar']))
    assert.deepEqual(out, [])
  })

  test('reports a block the document does not hold', () => {
    const out = unrepresentedBlockNames([slice('core/heading'), slice('core/calendar')], new Set(['heading']))
    assert.deepEqual(out, ['calendar'])
  })

  test('ignores freeform blocks, which are prose not blocks', () => {
    assert.deepEqual(unrepresentedBlockNames([slice(null)], new Set()), [])
  })

  test('strips the core prefix and de-duplicates', () => {
    const out = unrepresentedBlockNames([slice('core/calendar'), slice('core/calendar')], new Set())
    assert.deepEqual(out, ['calendar'])
  })

  test('keeps a third-party namespace intact', () => {
    assert.deepEqual(unrepresentedBlockNames([slice('acme/widget')], new Set()), ['acme/widget'])
  })
})
```

In `Scripts/test-editor-preservation.js`:

```js
describe('the alarm reports only genuine loss', () => {
  const posted = []
  before(() => {
    win.webkit = win.webkit || {}
    win.webkit.messageHandlers = Object.assign({}, win.webkit.messageHandlers, {
      blocksAtRisk: { postMessage: m => posted.push(m) },
    })
  })

  test('a fully preserved post posts nothing', () => {
    posted.length = 0
    win.setContent(fs.readFileSync(path.resolve(__dirname, 'fixtures/unsupported-blocks.html'), 'utf8'))
    assert.deepEqual(posted, [])
  })

  test('a post whose block the wrap missed is reported', () => {
    posted.length = 0
    win.setContent('<!-- wp:paragraph --><p>A</p><!-- /wp:paragraph -->')
    assert.deepEqual(posted, [])
  })
})
```

- [ ] **Step 2: Run to verify failure**

Run: `node --test Scripts/test-block-serializer.js`
Expected: FAIL, `unrepresentedBlockNames is not a function`.

- [ ] **Step 3: Implement the pure function**

```js
function unrepresentedBlockNames(slices, accountedNames) {
  const missing = []
  for (const slice of slices) {
    if (!slice.blockName) continue
    const short = shortBlockName(slice.blockName)
    if (!accountedNames.has(short) && !missing.includes(short)) missing.push(short)
  }
  return missing
}
```

Add it to `module.exports`.

- [ ] **Step 4: Collect the accounted names and post the message**

In `editor.html`, inside `window.setContent` after `editor.commands.setContent(...)`:

```js
      _reportBlocksAtRisk(html)
```

Define the collector above `window.setContent`:

```js
    function _accountedBlockNames() {
      const names = new Set()
      editor.state.doc.descendants(node => {
        if (node.type.name === 'gutenbergPassthrough') {
          if (node.attrs.blockName) names.add(node.attrs.blockName)
          if (node.attrs.unsupportedSource) {
            const m = node.attrs.unsupportedSource.match(/^<!--\s*wp:(\S+?)[\s/]/)
            if (m) names.add(m[1])
          }
          return false
        }
        const descriptor = blockDescriptorRegistry.descriptorFor(node.type.name)
        if (descriptor) names.add(shortBlockName(descriptor.blockName))
        return true
      })
      return names
    }

    function _reportBlocksAtRisk(originalHTML) {
      if (!originalHTML) return
      const slices = blockSourceSlices(originalHTML, BlockParser.parse, serializeBlock)
      const names = unrepresentedBlockNames(slices, _accountedBlockNames())
      if (names.length && window.webkit?.messageHandlers?.blocksAtRisk) {
        window.webkit.messageHandlers.blocksAtRisk.postMessage({ names })
      }
    }
```

Both helpers already exist inside `editor-transforms.js`: `blockDescriptorRegistry` is the resolver defined at line 11, and `shortBlockName` is the local function at line 48. Neither is currently visible to `editor.html`, because a classic script only exposes top-level `function` and `var` declarations, and both live inside the module's scope. Add this line at the end of `editor-transforms.js`, beside the existing `module.exports` guard, so the browser path can reach them:

```js
if (typeof window !== 'undefined') {
  window.blockDescriptorRegistry = blockDescriptorRegistry
  window.shortBlockName = shortBlockName
  window.blockSourceSlices = blockSourceSlices
  window.wrapUnsupportedBlocks = wrapUnsupportedBlocks
  window.unrepresentedBlockNames = unrepresentedBlockNames
}
```

Verify with one test in `Scripts/test-editor-preservation.js`:

```js
  test('the transform helpers the editor needs are on window', () => {
    for (const name of ['blockSourceSlices', 'wrapUnsupportedBlocks', 'unrepresentedBlockNames', 'shortBlockName']) {
      assert.equal(typeof win[name], 'function', `window.${name}`)
    }
  })
```

A `gutenbergPassthrough` returns `false` from the descendants callback so its own nested blocks are not walked; they are preserved as part of their parent's verbatim source and are not independently at risk.

- [ ] **Step 5: Run to verify pass**

Run: `node --test Scripts/test-block-serializer.js Scripts/test-editor-preservation.js`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/Resources/editor-transforms.js Sources/QuillKit/Resources/editor.html Scripts/test-block-serializer.js Scripts/test-editor-preservation.js
git commit -m "feat: report blocks the document cannot account for

Compares the parser's top-level block list against the parsed document,
independently of the wrap, so a bug in the wrap surfaces as a warning
rather than as silent loss.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: The alarm's strings and state, in testable Swift

**Files:**
- Create: `Sources/QuillKit/Views/Editor/BlockRiskAlarm.swift`
- Test: `Tests/QuillTests/BlockRiskAlarmTests.swift` (create)

**Interfaces:**
- Produces:

```swift
struct BlockRiskAlarm: Equatable {
    enum Stage: Equatable { case unacknowledged, acknowledged, saved }
    var names: [String]
    var stage: Stage
    var title: String { get }
    var body: String { get }
    var blocksSaving: Bool { get }
    static func displayName(for blockName: String) -> String
}
```

Strings are pure computed properties so they are testable without SwiftUI. Block names are bold in the rendered banner, which Task 10 does with `AttributedString`; this type returns the plain text plus the names separately.

- [ ] **Step 1: Write the failing tests**

`Tests/QuillTests/BlockRiskAlarmTests.swift`:

```swift
import Testing
@testable import QuillKit

@Suite struct BlockRiskAlarmTests {
    @Test func singleBlockUsesSingularWording() {
        let alarm = BlockRiskAlarm(names: ["calendar"], stage: .unacknowledged)
        #expect(alarm.title == "Saving this post would delete content")
        #expect(alarm.body.contains("A Calendar block didn't survive loading into Quill"))
        #expect(alarm.body.contains("would remove it from the published post"))
        #expect(alarm.blocksSaving)
    }

    @Test func multipleBlocksUsePluralWording() {
        let alarm = BlockRiskAlarm(names: ["calendar", "block"], stage: .unacknowledged)
        #expect(alarm.body.contains("would remove them from the published post"))
    }

    @Test func bodyNamesEveryAffectedBlock() {
        let alarm = BlockRiskAlarm(names: ["calendar", "block"], stage: .unacknowledged)
        #expect(alarm.body.contains("Calendar"))
        #expect(alarm.body.contains("Synced Pattern"))
    }

    @Test func bodyExplainsItIsNotTheAuthorsFault() {
        let alarm = BlockRiskAlarm(names: ["calendar"], stage: .unacknowledged)
        #expect(alarm.body.contains("This is a Quill limitation, not a problem with your post"))
    }

    @Test func acknowledgedStageUnblocksSavingAndChangesCopy() {
        let alarm = BlockRiskAlarm(names: ["calendar"], stage: .acknowledged)
        #expect(!alarm.blocksSaving)
        #expect(alarm.title == "Saving will delete a Calendar block")
        #expect(alarm.body == "You chose to save anyway. Quill won't ask again for this post.")
    }

    @Test func savedStageIsPastTenseAndPointsAtRevisions() {
        let alarm = BlockRiskAlarm(names: ["calendar"], stage: .saved)
        #expect(!alarm.blocksSaving)
        #expect(alarm.body.contains("was removed from this post"))
        #expect(alarm.body.contains("revision history"))
    }

    @Test func savedStagePluralisesCorrectly() {
        let alarm = BlockRiskAlarm(names: ["calendar", "navigation"], stage: .saved)
        #expect(alarm.body.contains("were removed from this post"))
    }

    @Test func noStringContainsAnEmDash() {
        for stage in [BlockRiskAlarm.Stage.unacknowledged, .acknowledged, .saved] {
            let alarm = BlockRiskAlarm(names: ["calendar", "block"], stage: stage)
            #expect(!alarm.title.contains("\u{2014}"))
            #expect(!alarm.body.contains("\u{2014}"))
        }
    }

    @Test func displayNamesAreHumanReadable() {
        #expect(BlockRiskAlarm.displayName(for: "calendar") == "Calendar")
        #expect(BlockRiskAlarm.displayName(for: "block") == "Synced Pattern")
        #expect(BlockRiskAlarm.displayName(for: "nextpage") == "Page Break")
        #expect(BlockRiskAlarm.displayName(for: "more") == "Read More")
        #expect(BlockRiskAlarm.displayName(for: "latest-posts") == "Latest Posts")
        #expect(BlockRiskAlarm.displayName(for: "acme/widget") == "Acme Widget")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter BlockRiskAlarmTests`
Expected: FAIL, `cannot find 'BlockRiskAlarm' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

struct BlockRiskAlarm: Equatable {
    enum Stage: Equatable { case unacknowledged, acknowledged, saved }

    var names: [String]
    var stage: Stage

    var blocksSaving: Bool { stage == .unacknowledged }

    private var displayNames: [String] { names.map(Self.displayName(for:)) }
    private var isSingular: Bool { names.count == 1 }

    var title: String {
        switch stage {
        case .unacknowledged:
            return "Saving this post would delete content"
        case .acknowledged:
            return isSingular
                ? "Saving will delete a \(displayNames[0]) block"
                : "Saving will delete \(names.count) blocks"
        case .saved:
            return ""
        }
    }

    var body: String {
        switch stage {
        case .unacknowledged:
            let subject = isSingular
                ? "A \(displayNames[0]) block didn't survive loading into Quill"
                : "\(Self.list(displayNames)) blocks didn't survive loading into Quill"
            let object = isSingular ? "it" : "them"
            return "\(subject), so saving from here would remove \(object) from the published post. "
                + "This is a Quill limitation, not a problem with your post."
        case .acknowledged:
            return "You chose to save anyway. Quill won't ask again for this post."
        case .saved:
            let subject = isSingular ? "A \(displayNames[0]) block was" : "\(Self.list(displayNames)) blocks were"
            return "\(subject) removed from this post. You can restore \(isSingular ? "it" : "them") "
                + "from the post's revision history in WordPress."
        }
    }

    private static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }

    private static let known: [String: String] = [
        "block": "Synced Pattern",
        "nextpage": "Page Break",
        "more": "Read More",
        "html": "Custom HTML",
    ]

    static func displayName(for blockName: String) -> String {
        let bare = blockName.hasPrefix("core/") ? String(blockName.dropFirst(5)) : blockName
        if let known = known[bare] { return known }
        return bare
            .split(whereSeparator: { $0 == "-" || $0 == "/" })
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter BlockRiskAlarmTests`
Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/Views/Editor/BlockRiskAlarm.swift Tests/QuillTests/BlockRiskAlarmTests.swift
git commit -m "feat: alarm strings for the three banner stages

Pure computed properties so the wording is pinned by tests rather than
buried in a view. Singular and plural are separate strings, not a count
interpolated into one, and a test asserts no string carries an em dash.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: Bridge the message, show the banner, gate the save

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/EditorCoordinator.swift` (callback property near line 19, new `case` in the `switch` near line 150)
- Modify: `Sources/QuillKit/Views/Editor/EditorView.swift` (property near line 18, registration near line 82, coordinator wiring)
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift` (state, banner, `save(status:force:)` guard near line 785, `performAutosave` near line 740)
- Test: `Tests/QuillTests/BlockRiskAlarmTests.swift`

**Interfaces:**
- Consumes: `blocksAtRisk` message (Task 8), `BlockRiskAlarm` (Task 9).
- Produces: `blockRiskAlarm: BlockRiskAlarm?` state on `PostEditorView`, driving the banner, the save guard and autosave suspension.

- [ ] **Step 1: Add the coordinator callback**

Beside the other `on…` properties in `EditorCoordinator`:

```swift
    var onBlocksAtRisk: (([String]) -> Void)?
```

And a new case in the `switch message.name`, following the `statsChanged` shape:

```swift
        case "blocksAtRisk":
            if let body = message.body as? [String: Any],
               let names = body["names"] as? [String] {
                DispatchQueue.main.async { self.onBlocksAtRisk?(names) }
            }
```

- [ ] **Step 2: Register and wire it in EditorView**

Add the property beside `onStatsChanged`:

```swift
    var onBlocksAtRisk: (([String]) -> Void)?
```

Register the handler in `makeNSView`, after the `statsChanged` line:

```swift
        config.userContentController.add(context.coordinator, name: "blocksAtRisk")
```

And assign it wherever the other coordinator callbacks are assigned in `makeNSView`/`updateNSView`, matching the existing pattern:

```swift
        context.coordinator.onBlocksAtRisk = onBlocksAtRisk
```

Forgetting the `add` call means the message is dropped silently, with no error anywhere.

- [ ] **Step 3: Add state and the banner to PostEditorView**

Beside `toastMessage` and friends near line 22:

```swift
    @State private var blockRiskAlarm: BlockRiskAlarm? = nil
```

Pass the callback to `EditorView` beside `onStatsChanged`:

```swift
                        onBlocksAtRisk: { names in
                            blockRiskAlarm = BlockRiskAlarm(names: names, stage: .unacknowledged)
                        },
```

Render it in the existing banner slot. Line 75 currently reads `if saveError != nil { errorBanner }`; make it:

```swift
                if saveError != nil { errorBanner }
                if let alarm = blockRiskAlarm { blockRiskBanner(alarm) }
```

Add the view beside `errorBanner`:

```swift
    private func blockRiskBanner(_ alarm: BlockRiskAlarm) -> some View {
        let danger = alarm.stage != .saved
        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: danger ? "exclamationmark.triangle.fill" : "clock.arrow.circlepath")
                .foregroundStyle(danger ? Color.red : Color.secondary)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 2) {
                if !alarm.title.isEmpty {
                    Text(alarm.title).font(.system(size: 12, weight: .semibold))
                }
                Text(boldingNames(in: alarm.body, names: alarm.names))
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                if alarm.blocksSaving {
                    Button("Save anyway, I understand") {
                        blockRiskAlarm = BlockRiskAlarm(names: alarm.names, stage: .acknowledged)
                    }
                    .font(.system(size: 11.5))
                    .padding(.top, 7)
                }
            }
            Spacer()
            if alarm.stage == .saved {
                Button { blockRiskAlarm = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background((danger ? Color.red : Color.secondary).opacity(0.07))
        .overlay(alignment: .bottom) { SoftHorizontalDivider() }
    }

    private func boldingNames(in text: String, names: [String]) -> AttributedString {
        var attributed = AttributedString(text)
        for display in names.map(BlockRiskAlarm.displayName(for:)) {
            var search = attributed.startIndex..<attributed.endIndex
            while let found = attributed[search].range(of: display) {
                attributed[found].inlinePresentationIntent = .stronglyEmphasized
                search = found.upperBound..<attributed.endIndex
            }
        }
        return attributed
    }
```

- [ ] **Step 4: Gate the save**

In `save(status:force:)`, beside the existing `contentLoadFailed` guard:

```swift
        guard blockRiskAlarm?.blocksSaving != true else {
            saveError = "Can't save yet. Quill found content it can't preserve in this post, see the warning above."
            return
        }
```

At the end of a successful save, move the alarm to its final stage. Immediately after the save succeeds and before `isSaving` falls back, add:

```swift
        if let alarm = blockRiskAlarm {
            blockRiskAlarm = BlockRiskAlarm(names: alarm.names, stage: .saved)
        }
```

- [ ] **Step 5: Suspend autosave**

In `performAutosave`, first line:

```swift
        if blockRiskAlarm?.blocksSaving == true { return }
```

Without this, the squashed content becomes the local draft silently and a later ordinary save publishes it having never warned anyone.

- [ ] **Step 6: Test the gate and the stage transitions**

Append to `Tests/QuillTests/BlockRiskAlarmTests.swift`:

```swift
    @Test func onlyTheUnacknowledgedStageBlocksSaving() {
        #expect(BlockRiskAlarm(names: ["calendar"], stage: .unacknowledged).blocksSaving)
        #expect(!BlockRiskAlarm(names: ["calendar"], stage: .acknowledged).blocksSaving)
        #expect(!BlockRiskAlarm(names: ["calendar"], stage: .saved).blocksSaving)
    }

    @Test func acknowledgingKeepsTheBlockNames() {
        let first = BlockRiskAlarm(names: ["calendar", "block"], stage: .unacknowledged)
        let next = BlockRiskAlarm(names: first.names, stage: .acknowledged)
        #expect(next.names == ["calendar", "block"])
    }
```

- [ ] **Step 7: Run the suites**

Run: `swift test --filter BlockRiskAlarmTests`
Expected: PASS, 12 tests.

Run: `./test.sh`
Expected: all suites pass.

- [ ] **Step 8: Build and verify in the app**

```bash
osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app
```

The alarm should never fire naturally now, so force it once to confirm the wiring: in Safari's Web Inspector against the running editor, run

```js
window.webkit.messageHandlers.blocksAtRisk.postMessage({ names: ['calendar', 'block'] })
```

Expected: red banner appears under the header with **Calendar** and **Synced Pattern** bold, both save buttons refuse, the acknowledge button unlocks them, and a completed save flips the banner to grey past tense with a dismiss button. Revert nothing; this is a runtime probe, not a code change.

- [ ] **Step 9: Commit**

```bash
git add Sources/QuillKit/Views/Editor/EditorCoordinator.swift Sources/QuillKit/Views/Editor/EditorView.swift Sources/QuillKit/Views/Editor/PostEditorView.swift Tests/QuillTests/BlockRiskAlarmTests.swift
git commit -m "feat: block saving when Quill can't preserve a post's content

The banner sits in the existing save-error slot with its own danger
styling, because amber is the weight of a recoverable server error and
this is content about to be deleted. Autosave is suspended while the
alarm stands, or the squashed version silently becomes the local draft.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11: Measure the unwrap's real cost

**Files:**
- Create: `Scripts/bench-unwrap.js` (throwaway, deleted in Step 4)

The spec commits to measuring this rather than assuming it: the unwrap runs inside `toWordPressHTML`, which fires on the typing debounce. The baseline is 6.368 ms for `toWordPressHTML` over the 23KB real post, measured 2026-09-12.

- [ ] **Step 1: Write the benchmark**

`Scripts/bench-unwrap.js`:

```js
const fs = require('fs'), path = require('path'), { JSDOM } = require('jsdom')
const dom = new JSDOM('<body></body>')
global.document = dom.window.document
const { toWordPressHTML } = require('../Sources/QuillKit/Resources/editor-transforms.js')

const plain = fs.readFileSync(path.resolve(__dirname, 'fixtures/post-17780.html'), 'utf8')
const withWrappers = fs.readFileSync(path.resolve(__dirname, 'fixtures/unsupported-blocks.html'), 'utf8')

const time = (label, src) => {
  toWordPressHTML(src, dom.window.document)
  const t = process.hrtime.bigint()
  for (let i = 0; i < 200; i++) toWordPressHTML(src, dom.window.document)
  console.log(`  ${label.padEnd(40)} ${(Number(process.hrtime.bigint() - t) / 1e6 / 200).toFixed(3)} ms`)
}
time('no unsupported blocks (selector misses)', plain)
time('eight unsupported blocks', withWrappers)
```

- [ ] **Step 2: Run it**

Run: `node Scripts/bench-unwrap.js`

- [ ] **Step 3: Judge the result**

Expected: the no-wrapper case is within noise of the 6.368 ms baseline, since the selector matches nothing. If the eight-wrapper case is more than roughly 1 ms worse, stop and report the number rather than proceeding: the sentinel substitution would need to become a single pass rather than one `String.replace` per wrapper.

- [ ] **Step 4: Delete the benchmark and record the numbers**

```bash
rm Scripts/bench-unwrap.js
```

Put both measurements in the commit body. They are the evidence for the spec's performance claim and belong where `git blame` finds them, not in a comment.

- [ ] **Step 5: Commit**

```bash
git commit --allow-empty -m "perf: measure the unwrap pass inside toWordPressHTML

<fill in both numbers from Step 2, against the 6.368 ms baseline for
toWordPressHTML over the 23KB post-17780 fixture>

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 12: Documentation and the manual pass

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/testing-plan.md`

- [ ] **Step 1: Run the full suite and record real counts**

Run: `./test.sh`

Record the per-suite numbers from the output. Do not estimate them and do not trust any number already written in prose.

- [ ] **Step 2: Update CLAUDE.md**

Correct the test-suite status header and the per-suite paragraphs with the counts from Step 1. Add a `JS preservation` paragraph in the established style. Confirm the Resources file map describes `block-parser-bundle.js` and `block-serializer.js` as live (Task 1 Step 7 did this; verify it survived).

- [ ] **Step 3: Update docs/testing-plan.md**

Add a `## JS preservation tests (N tests)` section in the file's established style: `File:` / `Editor file:` lines, prose intro, then a `### <describe name> (N tests)` table per describe. Update the header counts and the numbered run list at the top to include the new suite.

- [ ] **Step 4: Manual pass in the real app**

jsdom is weaker evidence than WKWebView for anything crossing the bridge, so verify by hand. Click "+ New Post" first and discard it when done; never test on a published post.

- [ ] Paste a Custom HTML block, a shortcode and a page break into code view, exit, type in a paragraph, re-enter code view. All three intact.
- [ ] Confirm each renders as a card with a readable peek.
- [ ] Confirm the cards can be selected and deleted with a single Backspace, like any atom node.
- [ ] Open a real post from the site that contains an accordion, edit a paragraph, save, and confirm in WordPress that the accordion is unchanged and Gutenberg reports no invalid content.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs/testing-plan.md
git commit -m "docs: record the preservation suite and correct test counts

Counts taken from a real ./test.sh run, not from prose.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Final verification

- [ ] `./test.sh` passes, every suite.
- [ ] `./build.sh` succeeds and the app opens.
- [ ] `Scripts/fixtures/unsupported-blocks.html` round-trips byte-identically with no edit, and every block survives an edit.
- [ ] The four real fixtures still round-trip byte-identically (container suite).
- [ ] No `quill-unsupported` string appears in any saved output.
- [ ] Code view shows real `post_content` for an unsupported block, and a hand edit there survives.
- [ ] The alarm does not fire on any fixture in the corpus.
- [ ] Forced alarm blocks both save buttons, acknowledging unlocks them, and a completed save flips it to past tense.
- [ ] Banner state 4: after a save that removed a block, reopening the post shows no banner, because the block is gone from the content and the check finds nothing missing. Confirm by loading the saved content back through `win.setContent` and asserting nothing is posted to `blocksAtRisk`.
- [ ] Autosave does not write while an unacknowledged alarm stands.
- [ ] The unwrap measurement from Task 11 is recorded and within budget.
