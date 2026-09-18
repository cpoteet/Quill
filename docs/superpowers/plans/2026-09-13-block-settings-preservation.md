# Block Settings Preservation Implementation Plan

> **Stage 1 is committed (`01ec015`, `b6a2e8e`) and this document is its record.**
> The forward half — stages 2 and 3 — is superseded by
> `2026-09-13-block-settings-framework.md`, after a scope review against the
> site's actual content cut most of the per-setting work and replaced it with a
> registry. The Findings section below is still binding and is referenced from
> the new plan; the stage 2 and 3 tasks below are kept only as the source
> material that plan's stage F was built from.


> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop Quill silently deleting Gutenberg block settings when it edits a post.

**Architecture:** The Tiptap node attribute becomes the single source of truth for any setting that generates markup; both the rendered HTML and the `<!-- wp:x {…} -->` delimiter JSON are produced from it. The existing `withBlockAttrs` carrier is extended to every node as the floor for settings nobody modeled. Core nodes already preserve their whole `class` string, so class-derived settings there need only their comment key restored.

**Tech Stack:** Tiptap 2.x in a WKWebView, plain-JS transforms in `editor-transforms.js`, Node `node:test` + jsdom for tests.

**Spec:** `docs/superpowers/specs/2026-09-13-block-settings-preservation-design.md`

## Global Constraints

- **The oracle for markup is the site's own installed core, never GitHub trunk and never a fixture.** Before writing any `renderHTML` or `attrsFrom`, fetch `https://<site>/wp-includes/js/dist/block-library.js` and read that block's `save.mjs` and `block.json`. `Scripts/fixtures/README.md` records the day this rule cost when it was broken.
- The spec's inventory was drafted against GitHub trunk. **Every markup claim in it is provisional until re-checked against that bundle.** Where they disagree, the bundle wins and the spec gets corrected in the same commit.
- Fixtures carry no comments and no header. The bytes are the test.
- New fixtures are flat files in `Scripts/fixtures/`, named `settings-<block>.html`. `test-block-serializer.js` and `test-editor-preservation.js` glob that directory non-recursively; a subdirectory would silently opt out of both.
- Anything in `block-descriptors.js` that `editor-transforms.js` must reach has to be a `function` declaration. A top-level `const` is reachable by bare identifier but never as a property of `globalThis`, so it works in every Node test and reads `undefined` in the running app.
- Comments follow the repo rule in `CLAUDE.md`: default to none; one line maximum; never restate what the code does.
- Do not commit unless the user asks. Each task's commit step is written out so it is ready, but the user runs it.
- After each task: `./test.sh`. After each stage: quit the app, `./build.sh`, reopen, and check a **new local draft**, reading saved HTML from `drafts.db` rather than code view.

---

## Findings from execution (2026-09-13)

Stage 1 is complete and verified in the running app. Four things learned while
executing it change the tasks below; they are folded into those tasks, and
listed here so a reader does not have to rediscover them.

### 1. Sourced attributes are never written to the delimiter

`block.json` marks many attributes `source: "attribute" | "rich-text" | "query"`.
Gutenberg reads those back **out of the saved HTML** and omits them from the
comment. Writing one into the comment diverges from core and breaks fixture
byte-identity, so these get a `renderHTML` and **no** `attrsFrom` entry and
**no** `ownedAttrs` entry:

| Block | Sourced — markup only |
|---|---|
| button | `url`, `title`, `text`, `linkTarget`, `rel` |
| image | `url`, `alt`, `caption`, `title`, `href`, `rel`, `linkClass`, `linkTarget` |
| details | `name`, `summary` |
| tab-list | `tabs` |
| table | `caption`, `head`, `body`, `foot` |
| quote | `value`, `citation` |
| paragraph | `content` |
| list | `values` |
| embed | `caption` |

Confirmed against the installed bundle's `block.json` for every block in the
inventory. The capture in `Scripts/fixtures/settings-*.html` shows the same
thing from the other direction: the button that opens in a new tab carries
`target`/`rel` in its markup and a bare `<!-- wp:button -->` comment.

Everything else in the inventory is a real comment attribute, including
`paragraph.direction`, all four list keys, `quote.textAlign`,
`table.hasFixedLayout`, both columns keys, `column.width`,
`accordion-item.openByDefault` and `embed.responsive`.

### 2. The carrier already finished four settings

The task 3 checkpoint was run. Where `withClassAttr` keeps the class and the
carrier keeps the comment, no modeling is needed:

| Setting | Result | Action |
|---|---|---|
| paragraph `dropCap` | class + comment both survive | trimmed from task 5 |
| quote `textAlign` | class + comment both survive | trimmed from task 11 |
| separator `opacity` | class survives; core omits the default from the comment | trimmed from task 11 |
| table `hasFixedLayout` | **lost** — the carrier lands on `<table>`, the descriptor reads the save-time `<figure>` | kept in task 13 |

### 3. The carrier had to reach further than stage 1 assumed

Tasks 2-4 as written did not cover the media nodes. Two extra changes were
needed and are already in:

- `ResizableImage`, `EmbedBlock` and `GalleryBlock` were not wrapped in
  `withBlockAttrs` at all, so `mergeCarried` had nothing to read.
- `EmbedBlock` and `GalleryBlock` build a DOM element in `renderHTML` rather
  than returning a spec array, so the carrier skipped them. `withBlockAttrs`
  now handles both shapes.

### 4. An unplanned serializer bug, fixed

`block-serializer.js` serialized delimiter attributes with a plain
`JSON.stringify`. Core applies six escapes (`\u005c`, `\u002d\u002d`,
`\u003c`, `\u003e`, `\u0026`, `\u0022`), so any block whose attributes held
`&`, `<`, `>`, `--`, a backslash or a quote was re-serialized wrong — a fidelity
hole in the preservation path itself. Caught by the embed fixture, whose YouTube
URL contains an `&`. Fixed byte-for-byte against the site's own `blocks.js`.

### Not a product bug: the jsdom setContent quirk

Under jsdom, a document holding a single atom node (gallery or embed) leaves a
`NodeSelection` that makes the next `setContent` of figure-first content parse
to an empty paragraph. **Verified not to reproduce in the app** — the fix was
reverted, rebuilt and retested twice in WebKit, including forcing the selection
by clicking the gallery card. `window.setContent` resets the selection anyway so
the jsdom suites can drive the real entry point instead of each prefixing a
reset of its own.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `Sources/QuillKit/Resources/editor.html` | Tiptap node definitions, `withClassAttr`, `withBlockAttrs` | modified throughout |
| `Sources/QuillKit/Resources/block-descriptors.js` | node → block map, `attrsFrom`, `ownedAttrs` | modified throughout |
| `Sources/QuillKit/Resources/editor-transforms.js` | `toWordPressHTML`, `wrapInDelimiters`, image/gallery/embed attr builders | modified in tasks 4, 14 |
| `Scripts/test-editor-block-settings.js` | one test per inventory row | created in task 2 |
| `Scripts/test-editor-table.js` | the whole table redesign | created in task 12 |
| `Scripts/fixtures/settings-*.html` | round-trip regression subjects | created in task 1 |
| `docs/wordpress-release-audit.md` | per-release re-verification | modified in task 15 |

### Two mechanisms, two different jobs

Knowing which applies saves writing code that duplicates a class:

- **Core nodes** (paragraph, heading, lists, quote, code, separator, table and its cells) are wrapped in `withClassAttr`, which preserves the element's entire `class` string verbatim. A setting whose markup is a class therefore already survives. It needs **only** an `attrsFrom` entry to restore its comment key, and **no** `renderHTML` — adding one makes Tiptap's `mergeAttributes` concatenate the class twice.
- **Container nodes** (columns, column, buttons, button, accordion and friends, tabs, details) render a fixed attribute object and ignore `HTMLAttributes` entirely, so nothing survives. Every setting there needs a real Tiptap attribute with both `parseHTML` and `renderHTML`.

### One trap in `wrapInDelimiters`

The table's `<figure class="wp-block-table">` is **created at save time** (`editor-transforms.js:566`), before `wrapInDelimiters` runs at line 660. `nodeNameForElement` maps that figure to `'table'`, so the table descriptor's `attrsFrom` receives **the figure, not the `<table>`**. Read `className` off the figure and `hasFixedLayout` off `el.querySelector('table')`.

---

## Stage 1 — the carrier — DONE (2026-09-13)

All four tasks complete, `./test.sh` green (11 suites), verified in the app against
`drafts.db` bytes. Not committed; commit commands are in the session notes.

### Task 1: Capture the fixture corpus — DONE

No production code changes. This builds the regression subjects every later task asserts against.

**Files:**
- Create: `Scripts/fixtures/settings-paragraph.html`, `settings-list.html`, `settings-quote.html`, `settings-separator.html`, `settings-table.html`, `settings-image.html`, `settings-columns.html`, `settings-buttons.html`, `settings-accordion.html`, `settings-details.html`, `settings-tabs.html`, `settings-embed.html`
- Modify: `Scripts/fixtures/README.md`

**Interfaces:**
- Produces: twelve fixture files of real `post_content`, each containing one block type with every modeled setting from the spec's inventory turned on.

- [ ] **Step 1: Confirm with the user before touching their site**

This creates a draft post on the user's live WordPress. Ask, and wait for a yes. Say what will be created and that it will be deleted afterwards.

- [ ] **Step 2: Fetch the installed core bundle and record its version**

```bash
curl -s https://<site>/wp-includes/js/dist/block-library.js > /tmp/block-library.js
wc -c /tmp/block-library.js
curl -s https://<site>/wp-json/ | python3 -c "import sys,json; print(json.load(sys.stdin).get('description'))"
```

Note the WordPress version. It goes in the README table in step 6.

- [ ] **Step 3: Build the draft post in WordPress**

In the block editor, create one draft containing one of each: a paragraph with drop cap on; an ordered list with start 5, reversed, upper-roman; a quote with Plain style and a citation; a separator with Dots style; a table with a header row, a footer row, a caption, Stripes style and fixed layout off; an image with a link to the media file opening in a new tab, a title, and Rounded style; a two-column Columns block with vertical alignment centre, stack-on-mobile off and unequal widths; a Buttons block with one Fill and one Outline button, the Outline one opening in a new tab; an accordion with two items, the first open by default, icons on the left; a Details block with a `name`; a Tabs block with two tabs; an embed.

Save as draft. Do not publish.

- [ ] **Step 4: Pull `post_content` back and split it into fixtures**

```bash
POST_ID=<id>
curl -s -u "<user>:<app-password>" \
  "https://<site>/wp-json/wp/v2/posts/$POST_ID?context=edit" \
  | python3 -c "import sys,json; sys.stdout.write(json.load(sys.stdin)['content']['raw'])" \
  > /tmp/settings-corpus.html
```

Split on top-level block boundaries into the twelve files. Write the exact bytes — no reindenting, no trailing-newline normalization, no comments.

- [ ] **Step 5: Verify the corpus is well-formed before trusting it**

```bash
node --test Scripts/test-block-serializer.js
```

Expected: PASS. That suite globs `Scripts/fixtures/*.html` and asserts parse → serialize byte-identity, so it proves the captures are intact WordPress block markup. If a new fixture fails here, the capture is corrupt — re-pull it rather than editing it by hand.

- [ ] **Step 6: Add the fixtures to the README table**

Append twelve rows to the table in `Scripts/fixtures/README.md`, each naming the block and the settings it carries, plus the WordPress version from step 2. Do not add a header or comments to the fixture files themselves.

- [ ] **Step 7: Delete the draft post from WordPress**

- [ ] **Step 8: Commit**

```bash
git add Scripts/fixtures/
git commit -m "test: capture block-settings fixtures from the live site

One file per block, each carrying every setting phase 1 models. Captured from
a throwaway draft on WordPress <version>, which was deleted afterwards.
Subjects for round-trip regression, not references for renderHTML."
```

---

### Task 2: `withBlockAttrs` splices `className` into the rendered class list — DONE

Every block style a user can pick — Outline, Stripes, Dots, Plain, Rounded — lives in the delimiter's `className`, and Gutenberg splices it into the rendered class list for every block. Container nodes render a fixed class and drop it. One change to the carrier fixes all sixteen at once.

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html:2437-2464` (`withBlockAttrs`)
- Test: `Scripts/test-editor-block-settings.js` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `mergeClassNames(existing: string|null, extra: string|null): string` as a `function` declaration in `editor-transforms.js`, exported and reachable as a browser global; `carriedClassName(raw: string): string` as a `function` declaration in `editor.html`. Task 12 reuses `mergeClassNames`.

- [ ] **Step 1: Write the failing test**

Create `Scripts/test-editor-block-settings.js`:

```js
'use strict'

// Per-setting tests for the block-settings preservation work. Loads the REAL
// editor.html in jsdom -- a node's renderHTML and its parse rule cannot be
// exercised through the pure editor-transforms.js helpers.

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

// The post-visual-edit save path: getContent() returns _rawHTML verbatim until
// an edit clears it, so calling the transform directly is what a real save does.
function save(src) {
  win.setContent(src)
  return win.toWordPressHTML(editor.getHTML())
}

const fixture = name => fs.readFileSync(path.resolve(__dirname, 'fixtures', name), 'utf8')

describe('className survives on container blocks', () => {
  test('an outline button keeps its class and its comment attr', () => {
    const out = save(`<!-- wp:buttons -->
<div class="wp-block-buttons"><!-- wp:button {"className":"is-style-outline"} -->
<div class="wp-block-button is-style-outline"><a class="wp-block-button__link wp-element-button" href="https://x.test">Go</a></div>
<!-- /wp:button --></div>
<!-- /wp:buttons -->`)
    assert.match(out, /class="wp-block-button is-style-outline"/)
    assert.match(out, /wp:button \{"className":"is-style-outline"\}/)
  })

  test('the class is not doubled when it is already rendered', () => {
    const out = save(`<!-- wp:details {"className":"is-style-x"} -->
<details class="wp-block-details is-style-x"><summary>S</summary><!-- wp:paragraph --><p>D</p><!-- /wp:paragraph --></details>
<!-- /wp:details -->`)
    assert.equal((out.match(/is-style-x/g) || []).length, 2, 'once in the class, once in the comment')
  })

  test('a block with no className is unchanged', () => {
    const out = save(`<!-- wp:buttons -->
<div class="wp-block-buttons"><!-- wp:button -->
<div class="wp-block-button"><a class="wp-block-button__link wp-element-button" href="https://x.test">Go</a></div>
<!-- /wp:button --></div>
<!-- /wp:buttons -->`)
    assert.match(out, /class="wp-block-button"/)
    assert.doesNotMatch(out, /class="wp-block-button "/)
  })
})
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
node --test Scripts/test-editor-block-settings.js
```

Expected: FAIL — the first test reports `class="wp-block-button"` with no `is-style-outline`.

- [ ] **Step 3: Implement the splice**

`mergeClassNames` goes in `editor-transforms.js`, not `editor.html` — task 12
needs it from the transform side too. It is a `function` declaration, so it
reaches `globalThis` in the browser (where `editor-transforms.js` loads first as
a classic script) and is exported for Node. Add it beside `carriedBlockAttrs`:

```js
function mergeClassNames(existing, extra) {
  const seen = new Set(String(existing || '').split(/\s+/).filter(Boolean))
  for (const token of String(extra || '').split(/\s+/)) if (token) seen.add(token)
  return Array.from(seen).join(' ')
}
```

Add it to that file's `module.exports`. Then in `editor.html`, add the one
helper that is only needed there, immediately above `withBlockAttrs`:

```js
function carriedClassName(raw) {
  try {
    const parsed = JSON.parse(raw)
    return (parsed && typeof parsed.className === 'string') ? parsed.className : ''
  } catch (e) {
    return ''
  }
}
```

Then replace the body of `withBlockAttrs`'s `renderHTML`:

```js
      renderHTML(props) {
        const out = this.parent?.(props)
        const carried = props.node && props.node.attrs && props.node.attrs.blockAttrs
        if (!carried || !Array.isArray(out)) return out
        const attrs = out[1]
        if (!attrs || typeof attrs !== 'object' || Array.isArray(attrs)) return out
        const merged = mergeClassNames(attrs.class, carriedClassName(carried))
        out[1] = { ...attrs, 'data-quill-block-attrs': carried }
        if (merged) out[1].class = merged
        return out
      },
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
node --test Scripts/test-editor-block-settings.js
./test.sh
```

Expected: PASS, and no regressions in the existing suites.

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Scripts/test-editor-block-settings.js
git commit -m "fix: keep the block style class on container blocks

Container nodes render a fixed class list, so className from the delimiter was
dropped from the markup while surviving in the comment -- Gutenberg then reports
the block as invalid and the front end loses the styling. The carrier now
splices className back in, which covers all sixteen containers at once."
```

---

### Task 3: Apply `withBlockAttrs` to every core node — DONE

Core nodes lose the whole delimiter JSON on the first edit because only the sixteen containers carry it.

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html:3127-3147` (extension registration)
- Test: `Scripts/test-editor-block-settings.js`

**Interfaces:**
- Consumes: `withBlockAttrs` from task 2.
- Produces: nothing new.

- [ ] **Step 1: Write the failing test**

Append to `Scripts/test-editor-block-settings.js`:

```js
describe('delimiter attributes survive on core blocks', () => {
  test('a paragraph keeps dropCap', () => {
    const out = save('<!-- wp:paragraph {"dropCap":true} -->\n<p class="has-drop-cap">Hello</p>\n<!-- /wp:paragraph -->')
    assert.match(out, /wp:paragraph \{"dropCap":true\}/)
  })

  test('an ordered list keeps start, reversed and type', () => {
    const out = save('<!-- wp:list {"ordered":true,"start":5,"reversed":true,"type":"upper-roman"} -->\n<ol reversed start="5" style="list-style-type:upper-roman" class="wp-block-list"><!-- wp:list-item --><li>one</li><!-- /wp:list-item --></ol>\n<!-- /wp:list -->')
    assert.match(out, /"start":5/)
    assert.match(out, /"reversed":true/)
    assert.match(out, /"type":"upper-roman"/)
  })

  test('a separator keeps its className', () => {
    const out = save('<!-- wp:separator {"className":"is-style-dots"} -->\n<hr class="wp-block-separator has-alpha-channel-opacity is-style-dots"/>\n<!-- /wp:separator -->')
    assert.match(out, /"className":"is-style-dots"/)
  })

  test('an unmodeled attribute rides along untouched', () => {
    const out = save('<!-- wp:paragraph {"metadata":{"name":"Intro"}} -->\n<p>Hello</p>\n<!-- /wp:paragraph -->')
    assert.match(out, /"metadata":\{"name":"Intro"\}/)
  })
})
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
node --test Scripts/test-editor-block-settings.js
```

Expected: FAIL — every assertion in this block; the comments come back bare.

- [ ] **Step 3: Wrap the core nodes in the carrier**

In `editor.html`'s extension array, wrap each core node. `withBlockAttrs` goes **outside** `withClassAttr` so the class carrier runs first:

```js
        withBlockAttrs(withClassAttr(CodeBlock.extend({
          addKeyboardShortcuts() {
            const orig = this.parent?.()
            return Object.fromEntries(Object.entries(orig || {}).map(([k, fn]) =>
              [k, (...args) => _isInFootnote() ? !_fnPassthrough.has(k) : fn(...args)]))
          },
        }))),
        ParagraphWithClass,
        HeadingWithClass.configure({ levels: [1, 2, 3, 4, 5, 6] }),
        BulletListWithClass,
        OrderedListWithClass,
        ListItemWithClass,
        CustomBlockquote,
        Cite,
        Underline,
        withBlockAttrs(withClassAttr(Table)).configure({ resizable: false }),
        withBlockAttrs(withClassAttr(TableRow)),
        withBlockAttrs(withClassAttr(TableHeader)),
        withBlockAttrs(withClassAttr(TableCell)),
        withBlockAttrs(withClassAttr(HorizontalRule)),
```

Then change the five named constants at `editor.html:1425-1442` to wrap in the carrier as well:

```js
    const ParagraphWithClass  = withBlockAttrs(withClassAttr(Paragraph))
    const HeadingWithClass    = withBlockAttrs(withClassAttr(Heading))
```

and the same for `BulletListWithClass`, `OrderedListWithClass`, `ListItemWithClass`, and `CustomBlockquote` at line 3080.

Move the `withBlockAttrs` definition above these constants if it is not already — it is currently declared at line 2437, after them. A `function` declaration hoists, so no move is needed; confirm it is a `function` and not a `const` before assuming that.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
node --test Scripts/test-editor-block-settings.js
./test.sh
```

Expected: PASS. The `type` and `reversed` assertions may still fail — if so they belong to task 6, so comment them out with a `// task 6` note and restore them there.

- [ ] **Step 5: Checkpoint — find out how much of stage 2 is already done**

The carrier may have fixed more than stage 2 assumes. A class-only setting on a
core node has both halves preserved without any modeling: `withClassAttr` keeps
the class, the carrier keeps the comment, and Quill has no UI that could make
them disagree. Modeling those would add machinery that buys nothing — which is
what `block-descriptors.js`'s own rule already warns against.

Run these four now and record the result:

```js
// paste into Scripts/test-editor-block-settings.js temporarily
for (const [label, src] of Object.entries({
  dropCap:        '<!-- wp:paragraph {"dropCap":true} -->\n<p class="has-drop-cap">Hello</p>\n<!-- /wp:paragraph -->',
  quoteAlign:     '<!-- wp:quote {"textAlign":"center"} -->\n<blockquote class="wp-block-quote has-text-align-center"><!-- wp:paragraph --><p>Q</p><!-- /wp:paragraph --></blockquote>\n<!-- /wp:quote -->',
  separator:      '<!-- wp:separator -->\n<hr class="wp-block-separator has-alpha-channel-opacity"/>\n<!-- /wp:separator -->',
  tableFixed:     '<!-- wp:table {"hasFixedLayout":false} -->\n<figure class="wp-block-table"><table><tbody><tr><td>B</td></tr></tbody></table></figure>\n<!-- /wp:table -->',
})) console.log(label, '=>', save(src))
```

For each one where the class **and** the comment key both come back intact,
**delete its modeling from stage 2** rather than implementing it:

| Setting | Task to trim |
|---|---|
| `dropCap` | Task 5 — drop it entirely; the task becomes `direction` only |
| `textAlign` | Task 11 — drop the quote descriptor change |
| `opacity` | Task 11 — drop the separator descriptor change |
| `hasFixedLayout` | Task 13 — drop it; the task becomes `scope` / `data-align` only |

What must **not** be trimmed on this reasoning, because `withClassAttr` keeps
only `class` and `id`: paragraph `direction` (a `dir` attribute), list
`reversed` and numbering (attribute and inline style), everything on a container
node (they preserve nothing), and the whole table redesign in stage 3.

Note the outcome in the commit message so a later reader knows the trimmed
settings were verified rather than forgotten.

- [ ] **Step 6: Build and check in the app**

```bash
osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app
```

Open a new local draft, paste a block with a `className` into code view, make a visual edit, save, and read the bytes:

```bash
sqlite3 ~/Library/Application\ Support/Quill/drafts.db "select content from local_drafts order by updated_at desc limit 1;"
```

- [ ] **Step 7: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Scripts/test-editor-block-settings.js
git commit -m "fix: carry delimiter attributes on core blocks too

withBlockAttrs reached only the sixteen container nodes, so every comment-only
attribute on a paragraph, list, quote, table or separator was deleted on the
first edit -- block styles, drop caps, list numbering and fixed table layout
among them."
```

---

### Task 4: Merge carried attributes into the image, gallery and embed builders — DONE

These three do not go through `wrapBlock`. They strip any existing comment and rebuild attrs from scratch in `imageBlockAttrs` and its siblings, so the carrier never reaches them.

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js:369-386` (`imageBlockAttrs`), `:471-484` (image wrap), `:595-660` (embed and gallery wraps)
- Test: `Scripts/test-editor-block-settings.js`

**Interfaces:**
- Consumes: `carriedBlockAttrs(el)` — already exists at `editor-transforms.js:71`.
- Produces: `mergeCarried(el, attrs, ownedKeys)` in `editor-transforms.js`, exported on the module's CommonJS exports.

- [ ] **Step 1: Write the failing test**

```js
describe('image, gallery and embed keep unmodeled attributes', () => {
  test('an image keeps lightbox and className', () => {
    const out = save('<!-- wp:image {"id":9,"sizeSlug":"large","lightbox":{"enabled":true},"className":"is-style-rounded"} -->\n<figure class="wp-block-image size-large is-style-rounded"><img src="https://x.test/a.jpg" alt="" class="wp-image-9"/></figure>\n<!-- /wp:image -->')
    assert.match(out, /"lightbox":\{"enabled":true\}/)
    assert.match(out, /"className":"is-style-rounded"/)
  })

  test('a derived attribute still wins over a stale carried one', () => {
    const out = save('<!-- wp:image {"id":9,"sizeSlug":"thumbnail"} -->\n<figure class="wp-block-image size-large"><img src="https://x.test/a.jpg" alt="" class="wp-image-9"/></figure>\n<!-- /wp:image -->')
    assert.match(out, /"sizeSlug":"large"/)
    assert.doesNotMatch(out, /"sizeSlug":"thumbnail"/)
  })
})
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
node --test Scripts/test-editor-block-settings.js
```

Expected: FAIL on `lightbox` and `className`; the second test already passes and is a guard that the fix does not invert precedence.

- [ ] **Step 3: Implement the merge**

Add to `editor-transforms.js` beside `carriedBlockAttrs`:

```js
// The image, gallery and embed passes rebuild their attrs from the rendered
// figure instead of going through wrapBlock, so the carrier is merged in here.
function mergeCarried(el, attrs, ownedKeys) {
  const carried = { ...(carriedBlockAttrs(el) || {}) }
  for (const key of ownedKeys || []) delete carried[key]
  return { ...carried, ...attrs }
}
```

At the image wrap (`:479`), replace `const attrs = imageBlockAttrs(figure, img)` with:

```js
    const attrs = mergeCarried(figure, imageBlockAttrs(figure, img),
      ['id', 'sizeSlug', 'width', 'height', 'align', 'linkDestination', 'isDecorative'])
```

Apply the same shape at the embed wrap (`:605`) with owned keys `['url', 'type', 'providerNameSlug']`, and at the gallery wrap (`:657`) with `['columns', 'imageCrop', 'linkTo', 'sizeSlug', 'ids']`.

Add `mergeCarried` to the `module.exports` list at the foot of the file.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
node --test Scripts/test-editor-block-settings.js
node --test Scripts/test-editor-gallery.js
./test.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/Resources/editor-transforms.js Scripts/test-editor-block-settings.js
git commit -m "fix: carry unmodeled attrs through the image, gallery and embed wraps

These three rebuild their delimiter attrs from the rendered figure rather than
going through wrapBlock, so lightbox, className and anything else Quill does not
model were dropped. Derived keys still take precedence over carried ones."
```

---

## Stage 2 — per-block attributes

Every task in this stage starts by re-reading the block's `save.mjs` and `block.json` in `/tmp/block-library.js`. The spec's markup claims are provisional.

### Task 5: Paragraph `direction`

**Trimmed.** `dropCap` needs nothing: the task 3 checkpoint confirmed the class survives through `withClassAttr` and the comment key through the carrier, so modeling it would add machinery that buys nothing. `direction` is a real comment attribute whose `dir=` markup is still lost.

**Files:**
- Modify: `Sources/QuillKit/Resources/block-descriptors.js` (paragraph descriptor), `Sources/QuillKit/Resources/editor.html:1425` (`ParagraphWithClass`)
- Test: `Scripts/test-editor-block-settings.js`

**Interfaces:**
- Consumes: `withBlockAttrs`, `withClassAttr`.
- Produces: paragraph descriptor gains `ownedAttrs: ['direction']`.

- [ ] **Step 1: Verify the markup against installed core**

```bash
grep -o 'has-drop-cap.\{0,200\}' /tmp/block-library.js | head -3
```

Confirm the class name and that `dir` is emitted from `direction`. Correct the spec if they differ.

- [ ] **Step 2: Write the failing test**

```js
describe('paragraph settings', () => {
  test('drop cap round-trips in both the class and the comment', () => {
    const out = save('<!-- wp:paragraph {"dropCap":true} -->\n<p class="has-drop-cap">Hello</p>\n<!-- /wp:paragraph -->')
    assert.match(out, /class="has-drop-cap"/)
    assert.match(out, /wp:paragraph \{"dropCap":true\}/)
  })

  test('a paragraph with no drop cap gains no attr', () => {
    const out = save('<!-- wp:paragraph -->\n<p>Hello</p>\n<!-- /wp:paragraph -->')
    assert.doesNotMatch(out, /dropCap/)
  })

  test('text direction round-trips', () => {
    const out = save('<!-- wp:paragraph {"direction":"rtl"} -->\n<p dir="rtl">مرحبا</p>\n<!-- /wp:paragraph -->')
    assert.match(out, /dir="rtl"/)
    assert.match(out, /"direction":"rtl"/)
  })
})
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
node --test Scripts/test-editor-block-settings.js
```

Expected: FAIL on the `dir` assertions.

- [ ] **Step 4: Implement**

In `block-descriptors.js`, replace the paragraph entry:

```js
  paragraph: { blockName: 'core/paragraph', shape: 'text', childBlockName: null,
    ownedAttrs: ['direction'],
    attrsFrom: el => {
      const dir = el.getAttribute('dir')
      return (dir === 'ltr' || dir === 'rtl') ? { direction: dir } : {}
    } },
```

In `editor.html`, give the paragraph node a real `direction` attribute so `dir` survives the schema:

```js
    const ParagraphWithClass = withBlockAttrs(withClassAttr(Paragraph.extend({
      addAttributes() {
        return {
          ...this.parent?.(),
          direction: {
            default: null,
            parseHTML: el => el.getAttribute('dir') || null,
            renderHTML: attrs => attrs.direction ? { dir: attrs.direction } : {},
          },
        }
      },
    })))
```

`dropCap` gets nothing at all — class and comment already round-trip (see Findings 2).

- [ ] **Step 5: Run the tests to verify they pass**

```bash
node --test Scripts/test-editor-block-settings.js && ./test.sh
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/Resources/block-descriptors.js Sources/QuillKit/Resources/editor.html Scripts/test-editor-block-settings.js
git commit -m "fix: preserve paragraph drop cap and text direction"
```

---

### Task 6: Ordered list `start`, `reversed` and `type`

The bundled Tiptap `OrderedList` has `start` (default 1) and `type`, and renders `type` as the HTML `type=` attribute. Gutenberg saves the numbering style as `style="list-style-type:…"` and never as `type=`, so Quill currently emits a form WordPress will not accept. `reversed` does not exist in Tiptap at all.

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html:1435` (`OrderedListWithClass`), `Sources/QuillKit/Resources/block-descriptors.js` (orderedList descriptor)
- Test: `Scripts/test-editor-block-settings.js`

**Interfaces:**
- Consumes: `withBlockAttrs`, `withClassAttr`.
- Produces: orderedList descriptor gains `ownedAttrs: ['ordered', 'start', 'reversed', 'type']`.

- [ ] **Step 1: Verify the markup against installed core**

```bash
grep -o 'list-style-type.\{0,200\}' /tmp/block-library.js | head -3
```

Confirm the style form and that `decimal` is omitted rather than written out.

- [ ] **Step 2: Write the failing test**

```js
describe('ordered list settings', () => {
  const src = '<!-- wp:list {"ordered":true,"start":5,"reversed":true,"type":"upper-roman"} -->\n<ol reversed start="5" style="list-style-type:upper-roman" class="wp-block-list"><!-- wp:list-item --><li>one</li><!-- /wp:list-item --></ol>\n<!-- /wp:list -->'

  test('numbering style saves as a style rule, never a type attribute', () => {
    const out = save(src)
    assert.match(out, /style="list-style-type:upper-roman"/)
    assert.doesNotMatch(out, /type="upper-roman"/)
  })

  test('reversed and start survive in the markup', () => {
    const out = save(src)
    assert.match(out, /reversed/)
    assert.match(out, /start="5"/)
  })

  test('all four keys reach the comment', () => {
    const out = save(src)
    assert.match(out, /"start":5/)
    assert.match(out, /"reversed":true/)
    assert.match(out, /"type":"upper-roman"/)
  })

  test('a plain ordered list gains none of them', () => {
    const out = save('<!-- wp:list {"ordered":true} -->\n<ol class="wp-block-list"><!-- wp:list-item --><li>one</li><!-- /wp:list-item --></ol>\n<!-- /wp:list -->')
    assert.match(out, /wp:list \{"ordered":true\}/)
    assert.doesNotMatch(out, /reversed/)
    assert.doesNotMatch(out, /list-style-type/)
  })

  test('decimal is omitted, matching core', () => {
    const out = save('<!-- wp:list {"ordered":true,"type":"decimal"} -->\n<ol class="wp-block-list"><!-- wp:list-item --><li>one</li><!-- /wp:list-item --></ol>\n<!-- /wp:list -->')
    assert.doesNotMatch(out, /list-style-type/)
  })
})
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
node --test Scripts/test-editor-block-settings.js
```

Expected: FAIL — `type="upper-roman"` is emitted and `reversed` is gone.

- [ ] **Step 4: Implement**

In `editor.html`, replace `OrderedListWithClass`:

```js
    const OrderedListWithClass = withBlockAttrs(withClassAttr(OrderedList.extend({
      addAttributes() {
        return {
          ...this.parent?.(),
          reversed: {
            default: false,
            parseHTML: el => el.hasAttribute('reversed'),
            renderHTML: attrs => attrs.reversed ? { reversed: '' } : {},
          },
          // Core saves the numbering style as a list-style-type rule; the HTML
          // type attribute is read on load only, for markup Quill wrote before.
          type: {
            default: null,
            parseHTML: el => {
              const m = (el.getAttribute('style') || '').match(/list-style-type:\s*([\w-]+)/)
              return m ? m[1] : (el.getAttribute('type') || null)
            },
            renderHTML: attrs => (attrs.type && attrs.type !== 'decimal')
              ? { style: `list-style-type:${attrs.type}` } : {},
          },
        }
      },
      addKeyboardShortcuts() {
        const orig = this.parent?.()
        return Object.fromEntries(Object.entries(orig || {}).map(([k, fn]) =>
          [k, (...args) => _isInFootnote() ? !_fnPassthrough.has(k) : fn(...args)]))
      },
    })))
```

Preserve whatever `addKeyboardShortcuts` body the existing `OrderedListWithClass` already has rather than the placeholder above — read `editor.html:1435` first and keep it verbatim.

In `block-descriptors.js`:

```js
  orderedList: { blockName: 'core/list', shape: 'container', childBlockName: 'core/list-item',
    ownedAttrs: ['ordered', 'start', 'reversed', 'type'],
    attrsFrom: el => {
      const attrs = { ordered: true }
      const start = parseInt(el.getAttribute('start') || '', 10)
      if (Number.isFinite(start) && start !== 1) attrs.start = start
      if (el.hasAttribute('reversed')) attrs.reversed = true
      const m = (el.getAttribute('style') || '').match(/list-style-type:\s*([\w-]+)/)
      if (m && m[1] !== 'decimal') attrs.type = m[1]
      return attrs
    } },
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
node --test Scripts/test-editor-block-settings.js && ./test.sh
```

Expected: PASS. Restore any assertions parked in task 3 step 4.

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Sources/QuillKit/Resources/block-descriptors.js Scripts/test-editor-block-settings.js
git commit -m "fix: save ordered list numbering the way core does

Quill emitted type=\"upper-roman\", which core never writes and WordPress does
not accept; the numbering style belongs in a list-style-type rule. reversed was
dropped from the markup and the comment alike."
```

---

### Task 7: Columns and column

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html:2155-2172` (`ColumnBlock`, `ColumnsBlock`), `block-descriptors.js`
- Test: `Scripts/test-editor-block-settings.js`

**Interfaces:**
- Consumes: `withBlockAttrs`, `blockCommentAttr`.
- Produces: `columnsBlock` gains `ownedAttrs: ['verticalAlignment', 'isStackedOnMobile']`; `columnBlock` gains `ownedAttrs: ['verticalAlignment', 'width']`.

- [ ] **Step 1: Verify the markup against installed core**

```bash
grep -o 'are-vertically-aligned.\{0,300\}' /tmp/block-library.js | head -2
grep -o 'is-not-stacked-on-mobile.\{0,200\}' /tmp/block-library.js | head -2
```

Confirm the class names and that `width` becomes `flex-basis`.

- [ ] **Step 2: Write the failing test**

```js
describe('columns settings', () => {
  const src = `<!-- wp:columns {"isStackedOnMobile":false,"verticalAlignment":"center"} -->
<div class="wp-block-columns are-vertically-aligned-center is-not-stacked-on-mobile"><!-- wp:column {"width":"33.33%"} -->
<div class="wp-block-column" style="flex-basis:33.33%"><!-- wp:paragraph --><p>A</p><!-- /wp:paragraph --></div>
<!-- /wp:column --><!-- wp:column {"width":"66.66%"} -->
<div class="wp-block-column" style="flex-basis:66.66%"><!-- wp:paragraph --><p>B</p><!-- /wp:paragraph --></div>
<!-- /wp:column --></div>
<!-- /wp:columns -->`

  test('vertical alignment and stacking keep their classes', () => {
    const out = save(src)
    assert.match(out, /are-vertically-aligned-center/)
    assert.match(out, /is-not-stacked-on-mobile/)
  })

  test('each column keeps its flex-basis', () => {
    const out = save(src)
    assert.match(out, /style="flex-basis:33\.33%"/)
    assert.match(out, /style="flex-basis:66\.66%"/)
  })

  test('the comment attrs survive too', () => {
    const out = save(src)
    assert.match(out, /"isStackedOnMobile":false/)
    assert.match(out, /"width":"33\.33%"/)
  })

  test('a default columns block gains no classes', () => {
    const out = save(`<!-- wp:columns -->
<div class="wp-block-columns"><!-- wp:column -->
<div class="wp-block-column"><!-- wp:paragraph --><p>A</p><!-- /wp:paragraph --></div>
<!-- /wp:column --></div>
<!-- /wp:columns -->`)
    assert.match(out, /class="wp-block-columns"/)
    assert.doesNotMatch(out, /is-not-stacked-on-mobile/)
    assert.doesNotMatch(out, /flex-basis/)
  })
})
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
node --test Scripts/test-editor-block-settings.js
```

Expected: FAIL on the class and `flex-basis` assertions.

- [ ] **Step 4: Implement**

```js
    const ColumnBlock = TiptapNode.create({
      name: 'columnBlock',
      group: 'column',
      content: 'block+',
      priority: 210,
      addAttributes() {
        return {
          verticalAlignment: {
            default: null,
            parseHTML: el => blockCommentAttr(el, 'verticalAlignment')
              || (el.className.match(/is-vertically-aligned-([\w]+)/) || [])[1] || null,
          },
          width: {
            default: null,
            parseHTML: el => blockCommentAttr(el, 'width')
              || (el.getAttribute('style') || '').match(/flex-basis:\s*([^;]+)/)?.[1]?.trim() || null,
          },
        }
      },
      parseHTML() { return [{ tag: 'div.wp-block-column' }] },
      renderHTML({ node }) {
        const { verticalAlignment, width } = node.attrs
        const attrs = { class: 'wp-block-column' }
        if (verticalAlignment) attrs.class += ` is-vertically-aligned-${verticalAlignment}`
        if (width) attrs.style = `flex-basis:${width}`
        return ['div', attrs, 0]
      },
    })

    const ColumnsBlock = TiptapNode.create({
      name: 'columnsBlock',
      group: 'block',
      content: 'column+',
      priority: 210,
      addAttributes() {
        return {
          verticalAlignment: {
            default: null,
            parseHTML: el => blockCommentAttr(el, 'verticalAlignment')
              || (el.className.match(/are-vertically-aligned-([\w]+)/) || [])[1] || null,
          },
          isStackedOnMobile: {
            default: true,
            parseHTML: el => {
              const carried = blockCommentAttr(el, 'isStackedOnMobile')
              if (typeof carried === 'boolean') return carried
              return !el.classList.contains('is-not-stacked-on-mobile')
            },
          },
        }
      },
      parseHTML() { return [{ tag: 'div.wp-block-columns' }] },
      renderHTML({ node }) {
        const { verticalAlignment, isStackedOnMobile } = node.attrs
        const attrs = { class: 'wp-block-columns' }
        if (verticalAlignment) attrs.class += ` are-vertically-aligned-${verticalAlignment}`
        if (!isStackedOnMobile) attrs.class += ' is-not-stacked-on-mobile'
        return ['div', attrs, 0]
      },
    })
```

In `block-descriptors.js`:

```js
  columnsBlock: { blockName: 'core/columns', shape: 'container', childBlockName: 'core/column',
    ownedAttrs: ['verticalAlignment', 'isStackedOnMobile'],
    attrsFrom: el => {
      const attrs = {}
      const m = el.className.match(/are-vertically-aligned-([\w]+)/)
      if (m) attrs.verticalAlignment = m[1]
      if (el.classList.contains('is-not-stacked-on-mobile')) attrs.isStackedOnMobile = false
      return attrs
    } },
  columnBlock: { blockName: 'core/column', shape: 'container', childBlockName: null,
    ownedAttrs: ['verticalAlignment', 'width'],
    attrsFrom: el => {
      const attrs = {}
      const m = el.className.match(/is-vertically-aligned-([\w]+)/)
      if (m) attrs.verticalAlignment = m[1]
      const w = (el.getAttribute('style') || '').match(/flex-basis:\s*([^;]+)/)
      if (w) attrs.width = w[1].trim()
      return attrs
    } },
```

Delete the sentence in the file's header comment claiming `columnBlock` does not own `width` — it now does.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
node --test Scripts/test-editor-block-settings.js && node --test Scripts/test-editor-containers.js && ./test.sh
```

Expected: PASS. `test-editor-containers.js` has a guard asserting a column's `width` survives untouched; confirm it still passes rather than deleting it.

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Sources/QuillKit/Resources/block-descriptors.js Scripts/test-editor-block-settings.js
git commit -m "fix: preserve column widths, stacking and vertical alignment

The attributes survived in the delimiter while the flex-basis style and both
alignment classes were stripped from the markup, so the layout collapsed on the
front end and Gutenberg reported the block as invalid."
```

---

### Task 8: Accordion item `openByDefault` and details `name`

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html:2285-2292` (`AccordionItem`), `:2182-2204` (`DetailsBlock`), `block-descriptors.js`
- Test: `Scripts/test-editor-block-settings.js`

**Interfaces:**
- Consumes: `withBlockAttrs`, `blockCommentAttr`, `hasBlockComment`.
- Produces: `accordionItem` gains `ownedAttrs: ['openByDefault']`. `detailsBlock`'s `ownedAttrs` is **unchanged** — `name` is `source: "attribute"`, so core never writes it to the comment (Findings 1).

- [ ] **Step 1: Verify the markup against installed core**

```bash
grep -o 'is-open.\{0,200\}' /tmp/block-library.js | head -3
```

- [ ] **Step 2: Write the failing test**

```js
describe('accordion item and details settings', () => {
  test('an open-by-default item keeps is-open', () => {
    const out = save(`<!-- wp:accordion -->
<div role="group" class="wp-block-accordion"><!-- wp:accordion-item {"openByDefault":true} -->
<div class="wp-block-accordion-item is-open"><!-- wp:accordion-heading -->
<h3 class="wp-block-accordion-heading has-icon has-icon-right"><button type="button" class="wp-block-accordion-heading__toggle"><span class="wp-block-accordion-heading__toggle-title">T</span><span class="wp-block-accordion-heading__toggle-icon" aria-hidden="true">+</span></button></h3>
<!-- /wp:accordion-heading --><!-- wp:accordion-panel -->
<div role="region" class="wp-block-accordion-panel"><!-- wp:paragraph --><p>P</p><!-- /wp:paragraph --></div>
<!-- /wp:accordion-panel --></div>
<!-- /wp:accordion-item --></div>
<!-- /wp:accordion -->`)
    assert.match(out, /class="wp-block-accordion-item is-open"/)
    assert.match(out, /"openByDefault":true/)
  })

  test('a closed item gains neither', () => {
    const out = save(`<!-- wp:accordion -->
<div role="group" class="wp-block-accordion"><!-- wp:accordion-item -->
<div class="wp-block-accordion-item"><!-- wp:accordion-heading -->
<h3 class="wp-block-accordion-heading has-icon has-icon-right"><button type="button" class="wp-block-accordion-heading__toggle"><span class="wp-block-accordion-heading__toggle-title">T</span><span class="wp-block-accordion-heading__toggle-icon" aria-hidden="true">+</span></button></h3>
<!-- /wp:accordion-heading --><!-- wp:accordion-panel -->
<div role="region" class="wp-block-accordion-panel"><!-- wp:paragraph --><p>P</p><!-- /wp:paragraph --></div>
<!-- /wp:accordion-panel --></div>
<!-- /wp:accordion-item --></div>
<!-- /wp:accordion -->`)
    assert.match(out, /class="wp-block-accordion-item"/)
    assert.doesNotMatch(out, /openByDefault/)
  })

  // name is sourced from the element, so core writes a bare comment for it.
  test('a details name survives on the element', () => {
    const out = save('<!-- wp:details -->\n<details class="wp-block-details" name="faq"><summary>S</summary><!-- wp:paragraph --><p>D</p><!-- /wp:paragraph --></details>\n<!-- /wp:details -->')
    assert.match(out, /name="faq"/)
    assert.doesNotMatch(out, /"name":"faq"/)
  })
})
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
node --test Scripts/test-editor-block-settings.js
```

Expected: FAIL on `is-open` and on `name="faq"`.

- [ ] **Step 4: Implement**

```js
    const AccordionItem = TiptapNode.create({
      name: 'accordionItem',
      group: 'accordionItemGroup',
      content: 'accordionHeading accordionPanel',
      priority: 210,
      addAttributes() {
        return {
          openByDefault: {
            default: false,
            parseHTML: el => {
              const carried = blockCommentAttr(el, 'openByDefault')
              if (typeof carried === 'boolean') return carried
              return el.classList.contains('is-open')
            },
          },
        }
      },
      parseHTML() { return [{ tag: 'div.wp-block-accordion-item' }] },
      renderHTML({ node }) {
        const cls = node.attrs.openByDefault
          ? 'wp-block-accordion-item is-open'
          : 'wp-block-accordion-item'
        return ['div', { class: cls }, 0]
      },
    })
```

Add `name` to `DetailsBlock`'s attributes and emit it:

```js
          name: {
            default: null,
            parseHTML: el => el.getAttribute('name') || null,
          },
```

and in its `renderHTML`, after the `open` line:

```js
        if (node.attrs.name) attrs.name = node.attrs.name
```

In `block-descriptors.js`:

```js
  accordionItem: { blockName: 'core/accordion-item', shape: 'container', childBlockName: null,
    ownedAttrs: ['openByDefault'],
    attrsFrom: el => (el.classList.contains('is-open') ? { openByDefault: true } : {}) },
```

Leave the details descriptor alone — `name` lives in the markup only.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
node --test Scripts/test-editor-block-settings.js && node --test Scripts/test-editor-containers.js && ./test.sh
```

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Sources/QuillKit/Resources/block-descriptors.js Scripts/test-editor-block-settings.js
git commit -m "fix: preserve accordion open-by-default and the details name"
```

---

### Task 9: Button link target, rel and title

A button set to open in a new tab silently stops doing so after one edit — `target` and `rel` are deleted from the markup and never reach the comment.

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html:2206-2223` (`ButtonBlock`), `block-descriptors.js`
- Test: `Scripts/test-editor-block-settings.js`

**Interfaces:**
- Consumes: `withBlockAttrs`.
- Produces: nothing in `block-descriptors.js`. All four of `url`, `linkTarget`, `rel` and `title` are `source: "attribute"` on the `<a>`, so this task is **markup only** (Findings 1).

- [ ] **Step 1: Verify the markup against installed core**

```bash
grep -o 'wp-block-button__link.\{0,400\}' /tmp/block-library.js | head -2
```

Confirm the anchor's class list and that `target` and `rel` are emitted from `linkTarget` and `rel`. Also check whether the installed version serializes `style.dimensions.width`; if it does, note it and raise it with the user rather than modeling it here — the spec leaves button width to the carrier.

- [ ] **Step 2: Write the failing test**

```js
describe('button link settings', () => {
  const src = `<!-- wp:buttons -->
<div class="wp-block-buttons"><!-- wp:button -->
<div class="wp-block-button"><a class="wp-block-button__link wp-element-button" href="https://x.test" target="_blank" rel="noreferrer noopener">Go</a></div>
<!-- /wp:button --></div>
<!-- /wp:buttons -->`

  test('target and rel survive in the markup', () => {
    const out = save(src)
    assert.match(out, /target="_blank"/)
    assert.match(out, /rel="noreferrer noopener"/)
  })

  // Both are sourced from the anchor, so the delimiter stays bare.
  test('target and rel stay out of the comment, as core leaves them', () => {
    const out = save(src)
    assert.doesNotMatch(out, /"linkTarget"/)
    assert.doesNotMatch(out, /"rel":/)
  })

  test('a same-tab button gains neither', () => {
    const out = save(`<!-- wp:buttons -->
<div class="wp-block-buttons"><!-- wp:button -->
<div class="wp-block-button"><a class="wp-block-button__link wp-element-button" href="https://x.test">Go</a></div>
<!-- /wp:button --></div>
<!-- /wp:buttons -->`)
    assert.doesNotMatch(out, /target=/)
    assert.doesNotMatch(out, /linkTarget/)
  })
})
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
node --test Scripts/test-editor-block-settings.js
```

Expected: FAIL — `target` and `rel` are absent from both.

- [ ] **Step 4: Implement**

Extend `ButtonBlock`'s attributes beside the existing `href`:

```js
      addAttributes() {
        const fromAnchor = name => el => el.querySelector('a')?.getAttribute(name) || null
        return {
          href:       { default: null, parseHTML: fromAnchor('href') },
          linkTarget: { default: null, parseHTML: fromAnchor('target') },
          rel:        { default: null, parseHTML: fromAnchor('rel') },
          title:      { default: null, parseHTML: fromAnchor('title') },
        }
      },
```

and emit them:

```js
      renderHTML({ node }) {
        const attrs = { class: 'wp-block-button__link wp-element-button' }
        if (node.attrs.href) attrs.href = node.attrs.href
        if (node.attrs.linkTarget) attrs.target = node.attrs.linkTarget
        if (node.attrs.rel) attrs.rel = node.attrs.rel
        if (node.attrs.title) attrs.title = node.attrs.title
        return ['div', { class: 'wp-block-button' }, ['a', attrs, 0]]
      },
```

`block-descriptors.js` is **not** touched: every one of these is sourced from
the anchor, so core's own `save()` leaves the delimiter bare and Quill must too.

Do **not** model `tagName` in this task. A button saved as `<button>` rather than `<a>` has no anchor for the `contentElement: 'a'` parse rule to find, and handling it needs a second parse form. The spec permits leaving `tagName` to the carrier; if `tagName: "button"` markup is found in the fixtures, route it to the passthrough card and raise it with the user.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
node --test Scripts/test-editor-block-settings.js && node --test Scripts/test-editor-containers.js && ./test.sh
```

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Sources/QuillKit/Resources/block-descriptors.js Scripts/test-editor-block-settings.js
git commit -m "fix: keep a button's link target, rel and title

A button set to open in a new tab stopped doing so after one edit: target and
rel were stripped from the anchor and never written to the delimiter either."
```

---

### Task 10: Image link and display attributes

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html:1713+` (`ResizableImage`), `Sources/QuillKit/Resources/editor-transforms.js:369` (`imageBlockAttrs`)
- Test: `Scripts/test-editor-block-settings.js`

**Interfaces:**
- Consumes: `mergeCarried` from task 4.
- Produces: `imageBlockAttrs` additionally returns **only** `aspectRatio` and `scale` — the two that are real comment attributes. `linkTarget`, `rel`, `linkClass` and `title` are `source: "attribute"` and belong in the markup alone (Findings 1).

- [ ] **Step 1: Verify the markup against installed core**

```bash
grep -o 'aspectRatio.\{0,300\}' /tmp/block-library.js | head -2
grep -o 'objectFit.\{0,200\}' /tmp/block-library.js | head -2
```

- [ ] **Step 2: Write the failing test**

```js
describe('image link and display settings', () => {
  test('a linked image keeps target, rel and link class in the markup', () => {
    const out = save('<!-- wp:image {"id":9,"linkDestination":"media"} -->\n<figure class="wp-block-image"><a class="lightbox" href="https://x.test/full.jpg" target="_blank" rel="noreferrer noopener"><img src="https://x.test/a.jpg" alt="" class="wp-image-9"/></a></figure>\n<!-- /wp:image -->')
    assert.match(out, /target="_blank"/)
    assert.match(out, /rel="noreferrer noopener"/)
    assert.match(out, /class="lightbox"/)
    assert.doesNotMatch(out, /"linkTarget"/)
  })

  test('aspect ratio and scale survive as inline style', () => {
    const out = save('<!-- wp:image {"id":9,"aspectRatio":"16/9","scale":"cover"} -->\n<figure class="wp-block-image"><img src="https://x.test/a.jpg" alt="" class="wp-image-9" style="aspect-ratio:16/9;object-fit:cover"/></figure>\n<!-- /wp:image -->')
    assert.match(out, /aspect-ratio:16\/9/)
    assert.match(out, /object-fit:cover/)
    assert.match(out, /"aspectRatio":"16\/9"/)
  })

  test('a plain image gains none of them', () => {
    const out = save('<!-- wp:image {"id":9} -->\n<figure class="wp-block-image"><img src="https://x.test/a.jpg" alt="" class="wp-image-9"/></figure>\n<!-- /wp:image -->')
    assert.doesNotMatch(out, /aspect-ratio/)
    assert.doesNotMatch(out, /target=/)
  })
})
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
node --test Scripts/test-editor-block-settings.js
```

- [ ] **Step 4: Locate the code that emits the anchor**

`ResizableImage.renderHTML` emits `<figure><img></figure>` with no anchor; the
link-to-full-size feature builds the `<a>` elsewhere. Find it before writing the
link attributes, because `linkTarget`, `rel` and `linkClass` belong on that
element rather than on the `<img>`:

```bash
grep -n "linkTo\|linkHref" Sources/QuillKit/Resources/editor.html Sources/QuillKit/Resources/editor-transforms.js
```

Add `target`, `rel` and `class` to the anchor at whichever site that grep
identifies, reading from the node attributes defined in step 5.

- [ ] **Step 5: Implement the attributes**

Add to `ResizableImage.addAttributes`, beside the existing `imgRole`:

```js
          linkTarget: {
            default: null,
            parseHTML: el => {
              const a = el.tagName === 'FIGURE' ? el.querySelector('a') : el.closest('a')
              return a?.getAttribute('target') || null
            },
            renderHTML: () => ({}),
          },
          rel: {
            default: null,
            parseHTML: el => {
              const a = el.tagName === 'FIGURE' ? el.querySelector('a') : el.closest('a')
              return a?.getAttribute('rel') || null
            },
            renderHTML: () => ({}),
          },
          linkClass: {
            default: null,
            parseHTML: el => {
              const a = el.tagName === 'FIGURE' ? el.querySelector('a') : el.closest('a')
              return a?.getAttribute('class') || null
            },
            renderHTML: () => ({}),
          },
          title: {
            default: null,
            parseHTML: el => {
              const img = el.tagName === 'FIGURE' ? el.querySelector('img') : el
              return img?.getAttribute('title') || null
            },
            renderHTML: attrs => attrs.title ? { title: attrs.title } : {},
          },
          aspectRatio: {
            default: null,
            parseHTML: el => {
              const img = el.tagName === 'FIGURE' ? el.querySelector('img') : el
              return (img?.getAttribute('style') || '').match(/aspect-ratio:\s*([^;]+)/)?.[1]?.trim() || null
            },
            renderHTML: () => ({}),
          },
          scale: {
            default: null,
            parseHTML: el => {
              const img = el.tagName === 'FIGURE' ? el.querySelector('img') : el
              return (img?.getAttribute('style') || '').match(/object-fit:\s*([^;]+)/)?.[1]?.trim() || null
            },
            renderHTML: () => ({}),
          },
```

The three link attributes and the two style attributes render nothing of their
own — `linkTarget`/`rel`/`linkClass` are written onto the anchor by the code
found in step 4, and `aspectRatio`/`scale` join the inline style that
`applyImageDimensions` already builds at `editor-transforms.js:352`. Extend that
function to append them:

```js
  const extra = []
  if (figure._quillAspectRatio) extra.push(`aspect-ratio:${figure._quillAspectRatio}`)
  if (figure._quillScale) extra.push(`object-fit:${figure._quillScale}`)
```

following whatever style-assembly convention `applyImageDimensions` already
uses, rather than introducing a second one.

- [ ] **Step 6: Extend the comment builder**

In `imageBlockAttrs`, add each value to the returned object behind a presence
check so an image without them still produces a bare `<!-- wp:image -->`:

```js
  const style = img.getAttribute('style') || ''
  const ar = style.match(/aspect-ratio:\s*([^;]+)/)
  if (ar) attrs.aspectRatio = ar[1].trim()
  const fit = style.match(/object-fit:\s*([^;]+)/)
  if (fit) attrs.scale = fit[1].trim()
```

Add `aspectRatio` and `scale` — and only those two — to the owned list in task 4's `mergeCarried` call.

- [ ] **Step 7: Run the tests to verify they pass**

```bash
node --test Scripts/test-editor-block-settings.js && node --test Scripts/test-editor-keyboard.js && ./test.sh
```

Expected: PASS. `test-editor-keyboard.js` holds the image link-to-full-size and dimensions suites; both must stay green.

- [ ] **Step 8: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Sources/QuillKit/Resources/editor-transforms.js Scripts/test-editor-block-settings.js
git commit -m "fix: preserve image link target, rel, title, aspect ratio and scale"
```

---

### Task 11: Embed `responsive`

**Heavily trimmed — check whether anything is left before starting.** The task 3 checkpoint retired the quote and separator halves: both already round-trip through `withClassAttr` plus the carrier, and core omits `opacity` from the comment when it is the default. The tab list is retired too — `tabs` is `source: "query"` over the rendered buttons, so core never writes it to the comment and Quill already renders those buttons. What remains is the embed's `wp-has-aspect-ratio` class, which `embedClassFor` rebuilds and therefore drops.

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js` (embed attrs)
- Test: `Scripts/test-editor-block-settings.js`

**Interfaces:**
- Consumes: `withBlockAttrs`, `mergeCarried`.
- Produces: nothing in `block-descriptors.js`.

- [ ] **Step 1: Verify against installed core**

```bash
grep -o 'wp-has-aspect-ratio.\{0,200\}' /tmp/block-library.js | head -2
```

- [ ] **Step 2: Write the failing test**

```js
describe('embed settings', () => {
  test('a responsive embed keeps its aspect-ratio class', () => {
    const out = save(fixture('settings-embed.html'))
    assert.match(out, /wp-has-aspect-ratio/)
    assert.match(out, /"responsive":true/)
  })
})
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
node --test Scripts/test-editor-block-settings.js
```

- [ ] **Step 4: Implement**

The figure's class is rebuilt by `embedClassFor`, so `wp-has-aspect-ratio` is
dropped unless it is put back. At `editor-transforms.js`'s embed wrap, restore it
from the carried value alongside the task-4 merge:

```js
    const merged = mergeCarried(figure, attrs, ['url', 'type', 'providerNameSlug'])
    if (merged.responsive) figure.className = mergeClassNames(figure.className, 'wp-has-aspect-ratio')
    wrapElementWithComments(doc, figure, ` wp:embed ${JSON.stringify(merged)} `, ' /wp:embed ')
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
node --test Scripts/test-editor-block-settings.js && node --test Scripts/test-editor-containers.js && ./test.sh
```

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/Resources/editor-transforms.js Scripts/test-editor-block-settings.js
git commit -m "fix: keep an embed's aspect-ratio class through a save"
```

---

## Stage 3 — the table

### Task 12: Claim the table figure, and with it `className` and the caption

Nothing in Quill currently sees the `<figure class="wp-block-table">`. Tiptap's bare `table` rule claims the inner `<table>` and the parser walks past the wrapper, so the figure's classes are invisible and its `<figcaption>` is orphaned into a loose paragraph block after the table.

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html:3142` (Table registration), `Sources/QuillKit/Resources/editor-transforms.js:566-573` (figure wrap), `block-descriptors.js` (table descriptor)
- Test: `Scripts/test-editor-table.js` (create)

**Interfaces:**
- Consumes: `withBlockAttrs`, `withClassAttr`.
- Produces: the `table` node gains `className: string|null` and `caption: string|null` attributes; the table descriptor gains `ownedAttrs: ['className']` only — `caption` is `source: "rich-text"` on the `<figcaption>`, so core reads it back from the markup and never writes it to the comment (Findings 1).

- [ ] **Step 1: Write the failing test**

Create `Scripts/test-editor-table.js` with the same jsdom bootstrap as `Scripts/test-editor-block-settings.js` (copy the `before`/`after`/`save` block verbatim), then:

```js
describe('the table figure', () => {
  const src = `<!-- wp:table {"className":"is-style-stripes"} -->
<figure class="wp-block-table is-style-stripes"><table class="has-fixed-layout"><tbody><tr><td>B1</td><td>B2</td></tr></tbody></table><figcaption class="wp-element-caption">My caption</figcaption></figure>
<!-- /wp:table -->`

  test('the caption stays inside the figure', () => {
    const out = save(src)
    assert.match(out, /<figcaption class="wp-element-caption">My caption<\/figcaption><\/figure>/)
  })

  test('the caption does not leak out as a paragraph', () => {
    const out = save(src)
    assert.doesNotMatch(out, /<p>My caption<\/p>/)
  })

  test('the figure keeps its block style', () => {
    const out = save(src)
    assert.match(out, /class="wp-block-table is-style-stripes"/)
    assert.match(out, /"className":"is-style-stripes"/)
  })

  test('a table with no caption emits no figcaption', () => {
    const out = save('<!-- wp:table -->\n<figure class="wp-block-table"><table class="has-fixed-layout"><tbody><tr><td>B1</td></tr></tbody></table></figure>\n<!-- /wp:table -->')
    assert.doesNotMatch(out, /figcaption/)
  })
})
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
node --test Scripts/test-editor-table.js
```

Expected: FAIL — the caption comes back as `<p>My caption</p>` after the table and the figure has no `is-style-stripes`.

- [ ] **Step 3: Implement the figure parse rule**

Give the Table node a figure-rooted parse rule using the same `contentElement` technique `Pullquote` already uses at `editor.html:2360`:

```js
    const QuillTable = Table.extend({
      addAttributes() {
        return {
          ...this.parent?.(),
          className: {
            default: null,
            parseHTML: el => blockCommentAttr(el.closest('figure.wp-block-table') || el, 'className') || null,
          },
          caption: {
            default: null,
            parseHTML: el => {
              const figure = el.closest('figure.wp-block-table')
              const cap = figure ? figure.querySelector(':scope > figcaption') : null
              return cap ? cap.innerHTML : null
            },
          },
        }
      },
      parseHTML() {
        return [
          { tag: 'figure.wp-block-table', contentElement: 'table' },
          ...(this.parent?.() || []),
        ]
      },
    })
```

Register it as `withBlockAttrs(withClassAttr(QuillTable)).configure({ resizable: false })`.

Then in `editor-transforms.js`'s figure-wrap pass, carry the values onto the generated figure:

```js
  div.querySelectorAll('table').forEach(table => {
    if (table.parentElement?.classList.contains('wp-block-table')) return
    const figure = doc.createElement('figure')
    figure.className = mergeClassNames('wp-block-table', table.getAttribute('data-quill-table-class'))
    table.removeAttribute('data-quill-table-class')
    table.parentNode.insertBefore(figure, table)
    figure.appendChild(table)
    const caption = table.getAttribute('data-quill-table-caption')
    if (caption) {
      const cap = doc.createElement('figcaption')
      cap.className = 'wp-element-caption'
      cap.innerHTML = caption
      figure.appendChild(cap)
    }
    table.removeAttribute('data-quill-table-caption')
  })
```

The node's `renderHTML` writes `data-quill-table-class` and `data-quill-table-caption` onto the `<table>`, since the figure does not exist in the editor. `mergeClassNames` is the task-2 helper, already defined in this file.

Add the table descriptor's `attrsFrom`, reading **from the figure**, which is what `nodeNameForElement` hands it:

```js
  table: { blockName: 'core/table', shape: 'media', childBlockName: null,
    ownedAttrs: ['className'],
    attrsFrom: el => {
      const attrs = {}
      const custom = el.className.replace('wp-block-table', '').trim()
      if (custom) attrs.className = custom
      return attrs
    } },
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
node --test Scripts/test-editor-table.js && node --test Scripts/test-editor.js && ./test.sh
```

Expected: PASS. `test-editor.js` holds the existing table transform tests including the Tiptap artifact cleanup; all must stay green.

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Sources/QuillKit/Resources/editor-transforms.js Sources/QuillKit/Resources/block-descriptors.js Scripts/test-editor-table.js
git commit -m "fix: stop tearing the caption out of a table

Nothing in Quill saw the wp-block-table figure: Tiptap's bare table rule claimed
the inner element and the parser walked past the wrapper, so the figcaption was
orphaned into a loose paragraph and the figure's block style was dropped. The
Table node now claims the figure with contentElement, the way pullquote does."
```

---

### Task 13: Table `hasFixedLayout` and cell `scope` / `data-align`

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` (`TableHeader`, `TableCell`), `block-descriptors.js` (table descriptor)
- Test: `Scripts/test-editor-table.js`

**Interfaces:**
- Consumes: task 12's `QuillTable`.
- Produces: table descriptor's `ownedAttrs` becomes `['className', 'hasFixedLayout']`. The checkpoint confirmed `hasFixedLayout` is genuinely lost today — the carrier lands on the `<table>` while the descriptor reads the save-time `<figure>` — so unlike the other class-only settings it is **not** trimmed.

- [ ] **Step 1: Write the failing test**

```js
describe('table layout and cell attributes', () => {
  test('fixed layout off reaches the comment', () => {
    const out = save('<!-- wp:table {"hasFixedLayout":false} -->\n<figure class="wp-block-table"><table><tbody><tr><td>B1</td></tr></tbody></table></figure>\n<!-- /wp:table -->')
    assert.match(out, /"hasFixedLayout":false/)
    assert.doesNotMatch(out, /has-fixed-layout/)
  })

  test('fixed layout on keeps its class', () => {
    const out = save('<!-- wp:table -->\n<figure class="wp-block-table"><table class="has-fixed-layout"><tbody><tr><td>B1</td></tr></tbody></table></figure>\n<!-- /wp:table -->')
    assert.match(out, /class="has-fixed-layout"/)
  })

  test('a header cell keeps its scope', () => {
    const out = save('<!-- wp:table -->\n<figure class="wp-block-table"><table class="has-fixed-layout"><thead><tr><th scope="col">H1</th></tr></thead><tbody><tr><td>B1</td></tr></tbody></table></figure>\n<!-- /wp:table -->')
    assert.match(out, /<th scope="col">H1<\/th>/)
  })

  test('a cell keeps data-align alongside its class', () => {
    const out = save('<!-- wp:table -->\n<figure class="wp-block-table"><table class="has-fixed-layout"><tbody><tr><td class="has-text-align-right" data-align="right">B1</td></tr></tbody></table></figure>\n<!-- /wp:table -->')
    assert.match(out, /data-align="right"/)
    assert.match(out, /has-text-align-right/)
  })
})
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
node --test Scripts/test-editor-table.js
```

Expected: FAIL on the comment key, on `scope` and on `data-align`.

- [ ] **Step 3: Implement**

Define the cell attributes once and share them, since `TableHeader` and
`TableCell` need identical handling:

```js
    // scope is meaningful only on a <th>, but parsing it on both keeps one
    // shared definition; a <td> never carries one to read.
    function cellAttributes(parent) {
      return {
        ...parent,
        scope: {
          default: null,
          parseHTML: el => el.getAttribute('scope') || null,
          renderHTML: attrs => attrs.scope ? { scope: attrs.scope } : {},
        },
        dataAlign: {
          default: null,
          parseHTML: el => el.getAttribute('data-align') || null,
          renderHTML: attrs => attrs.dataAlign ? { 'data-align': attrs.dataAlign } : {},
        },
      }
    }

    const QuillTableHeader = TableHeader.extend({
      addAttributes() { return cellAttributes(this.parent?.()) },
    })

    const QuillTableCell = TableCell.extend({
      addAttributes() { return cellAttributes(this.parent?.()) },
    })
```

Register them as `withBlockAttrs(withClassAttr(QuillTableHeader))` and
`withBlockAttrs(withClassAttr(QuillTableCell))`, replacing the plain
`withClassAttr(TableHeader)` and `withClassAttr(TableCell)` entries from task 3.

`has-text-align-*` needs no handling — `withClassAttr` already carries it.

Extend the table descriptor's `attrsFrom` to read the layout off the inner table, remembering the element it receives is the **figure**:

```js
      const table = el.querySelector('table')
      if (table && !table.classList.contains('has-fixed-layout')) attrs.hasFixedLayout = false
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
node --test Scripts/test-editor-table.js && ./test.sh
```

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Sources/QuillKit/Resources/block-descriptors.js Scripts/test-editor-table.js
git commit -m "fix: preserve table fixed layout and cell scope and alignment"
```

---

### Task 14: Table `rowType` and section grouping

A `<tfoot>` row currently loses its identity on parse and comes back inside `<tbody>`.

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` (`TableRow`), `Sources/QuillKit/Resources/editor-transforms.js:551-564` (header promotion)
- Test: `Scripts/test-editor-table.js`

**Interfaces:**
- Consumes: task 12's `QuillTable`.
- Produces: `tableRow` gains `rowType: 'head' | 'body' | 'foot'`, default `'body'`. No descriptor change — `head`/`body`/`foot` are `source: "query"`, so the sections live in the markup only (Findings 1).

- [ ] **Step 1: Write the failing test**

```js
describe('table sections', () => {
  const src = `<!-- wp:table -->
<figure class="wp-block-table"><table class="has-fixed-layout"><thead><tr><th>H1</th><th>H2</th></tr></thead><tbody><tr><td>B1</td><td>B2</td></tr></tbody><tfoot><tr><td>F1</td><td>F2</td></tr></tfoot></table></figure>
<!-- /wp:table -->`

  test('the footer row stays in tfoot', () => {
    const out = save(src)
    assert.match(out, /<tfoot><tr><td>F1<\/td><td>F2<\/td><\/tr><\/tfoot>/)
  })

  test('the body keeps only its own row', () => {
    const out = save(src)
    assert.match(out, /<tbody><tr><td>B1<\/td><td>B2<\/td><\/tr><\/tbody>/)
  })

  test('sections come out in core order', () => {
    const out = save(src)
    assert.ok(out.indexOf('<thead>') < out.indexOf('<tbody>'), 'head before body')
    assert.ok(out.indexOf('<tbody>') < out.indexOf('<tfoot>'), 'body before foot')
  })

  test('saving twice is idempotent', () => {
    const once = save(src)
    assert.equal(save(once), once)
  })

  test('a classic table with no sections still gets its header promoted', () => {
    const out = save('<figure class="wp-block-table"><table><tbody><tr><th>H1</th><th>H2</th></tr><tr><td>B1</td><td>B2</td></tr></tbody></table></figure>')
    assert.match(out, /<thead><tr><th>H1<\/th><th>H2<\/th><\/tr><\/thead>/)
  })

  // Recorded limit, not desired behaviour. ProseMirror pads every row to a
  // uniform cell count at parse time, upstream of the save transform. If this
  // test starts failing, the limit is gone -- update docs/testing-plan.md.
  test('colspan plus explicit sections gains a phantom cell', () => {
    const out = save(`<!-- wp:table -->
<figure class="wp-block-table"><table class="has-fixed-layout"><thead><tr><th>H1</th><th>H2</th></tr></thead><tbody><tr><td colspan="2">spanned</td></tr></tbody></table></figure>
<!-- /wp:table -->`)
    assert.match(out, /<thead><tr><th>H1<\/th><th>H2<\/th><th><\/th><\/tr><\/thead>/)
  })
})
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
node --test Scripts/test-editor-table.js
```

Expected: FAIL — the footer row appears inside `<tbody>` and there is no `<tfoot>`.

- [ ] **Step 3: Implement `rowType`**

```js
    const QuillTableRow = TableRow.extend({
      addAttributes() {
        return {
          ...this.parent?.(),
          rowType: {
            default: 'body',
            parseHTML: el => {
              const section = el.parentElement
              if (!section) return 'body'
              if (section.tagName === 'THEAD') return 'head'
              if (section.tagName === 'TFOOT') return 'foot'
              return 'body'
            },
            renderHTML: attrs => attrs.rowType && attrs.rowType !== 'body'
              ? { 'data-quill-row-type': attrs.rowType } : {},
          },
        }
      },
    })
```

Register it as `withBlockAttrs(withClassAttr(QuillTableRow))`.

Then replace the header-promotion pass in `editor-transforms.js` with section grouping:

```js
  // Rows carry their own section from parse. The all-<th>-first-row promotion
  // below is the fallback for classic tables and rows Quill created itself.
  div.querySelectorAll('table').forEach(table => {
    const rows = Array.from(table.querySelectorAll('tr'))
    const typed = rows.some(r => r.hasAttribute('data-quill-row-type'))
    if (!typed) return
    const sections = { head: [], body: [], foot: [] }
    rows.forEach(r => {
      sections[r.getAttribute('data-quill-row-type') || 'body'].push(r)
      r.removeAttribute('data-quill-row-type')
    })
    Array.from(table.children).forEach(c => c.remove())
    for (const name of ['head', 'body', 'foot']) {
      if (!sections[name].length) continue
      const section = doc.createElement('t' + name)
      sections[name].forEach(r => section.appendChild(r))
      table.appendChild(section)
    }
  })
```

Leave the existing promotion pass immediately after it, guarded so it only runs when no row was typed — `if (table.querySelector('thead')) return` already covers the typed case, since grouping runs first and creates the `<thead>`.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
node --test Scripts/test-editor-table.js && node --test Scripts/test-editor.js && ./test.sh
```

Expected: PASS.

- [ ] **Step 5: Build and check in the app**

```bash
osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app
```

On a new local draft, paste the task-1 table fixture into code view, exit to visual, type a character in a cell, save, and read the bytes from `drafts.db`. Confirm the footer row and the caption are both intact.

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Sources/QuillKit/Resources/editor-transforms.js Scripts/test-editor-table.js
git commit -m "fix: keep a table's footer row in tfoot

Tiptap's schema has no section concept, so a tfoot row parsed as an ordinary
body row and was re-emitted inside tbody. Rows now carry their own section and
the save transform regroups them in core's head-body-foot order; the old
all-th-first-row promotion stays as the fallback for classic tables."
```

---

## Wrap-up

### Task 15: Corpus assertion, drift guard, docs and cleanup

**Files:**
- Modify: `Scripts/test-editor-block-settings.js`, `docs/wordpress-release-audit.md`, `docs/testing-plan.md`, `docs/gutenberg-block-snippets.md`, `Sources/QuillKit/Resources/block-descriptors.js`, `CLAUDE.md`
- Delete: `Scripts/probe-attrs.js`

**Interfaces:**
- Consumes: everything above.
- Produces: nothing.

- [ ] **Step 1: Write the whole-corpus test**

```js
describe('the settings corpus survives an edit', () => {
  const files = fs.readdirSync(path.resolve(__dirname, 'fixtures'))
    .filter(f => f.startsWith('settings-') && f.endsWith('.html'))

  test('there is at least one fixture per modeled block', () => {
    assert.ok(files.length >= 12, `expected 12 fixtures, found ${files.length}`)
  })

  for (const name of files) {
    test(`${name} round-trips byte-identically with no edit`, () => {
      const src = fixture(name)
      win.setContent(src)
      assert.equal(win.getContent(), src)
    })

    test(`${name} survives an edit and is idempotent`, () => {
      const src = fixture(name)
      win.setContent(src)
      editor.commands.setTextSelection(2)
      editor.commands.insertContent('X')
      const once = win.getContent()
      win.setContent(once)
      assert.equal(win.getContent(), once, 'second save differs from the first')
    })
  }
})
```

- [ ] **Step 2: Run it**

```bash
node --test Scripts/test-editor-block-settings.js
```

Expected: PASS. A failure here means an earlier task's markup disagrees with what the site's own WordPress wrote — fix the earlier task rather than editing the fixture. The fixtures README is explicit that fixtures are never edited to match Quill.

- [ ] **Step 3: Add the drift guard**

```js
test('every descriptor with ownedAttrs has a fixture naming its block', () => {
  const registry = require('../Sources/QuillKit/Resources/block-descriptors.js')
  const corpus = fs.readdirSync(path.resolve(__dirname, 'fixtures'))
    .filter(f => f.startsWith('settings-'))
    .map(f => fixture(f)).join('\n')
  for (const [node, d] of Object.entries(registry.BLOCK_DESCRIPTORS)) {
    if (!d.ownedAttrs || !d.ownedAttrs.length) continue
    assert.ok(corpus.includes('<!-- wp:' + d.blockName.replace(/^core\//, '')),
      `${node} models attributes but no fixture carries a ${d.blockName}`)
  }
})
```

- [ ] **Step 4: Update the docs**

- `docs/wordpress-release-audit.md` — add a "Block settings" section listing every modeled attribute from the spec's inventory and the class or attribute each one generates, with the instruction to re-verify them against the site's own `block-library.js` each WordPress major release.
- `docs/testing-plan.md` — add the two new suites and the colspan-plus-sections limit.
- `docs/gutenberg-block-snippets.md` — correct the pullquote entry, which still says the block is not visually editable; it has been since commit `f552d07`.
- `Sources/QuillKit/Resources/block-descriptors.js` — rewrite the header comment. `ownedAttrs` no longer means "only keys the node genuinely round-trips"; it now means the full modeled set for that block. Delete the sentence about `columnBlock` not owning `width`.
- `CLAUDE.md` — update the test counts in the "Test suite status" section by running each suite, and add the two new files to the command list at the top.

- [ ] **Step 5: Delete the probe and the capture draft**

```bash
rm Scripts/probe-attrs.js
```

Also delete WordPress draft **18195** ("Block Test"), kept through stage 2 so its
settings could be re-checked in Gutenberg. Ask before deleting — it is on the live site.

- [ ] **Step 6: Full verification**

```bash
./test.sh
osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app
```

Then the manual pass on a new local draft: load each of the twelve fixtures through code view, make one visual edit, save, and diff the bytes from `drafts.db` against the fixture. Discard the draft.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "test: assert the settings corpus round-trips, and guard against drift

Adds the whole-corpus byte-identity check, a guard that a descriptor cannot gain
modeled attributes without a fixture covering them, and the per-release
re-verification section the modeled markup now needs."
```

---

## Verification checklist

- [ ] `./test.sh` passes
- [ ] All twelve `settings-*.html` fixtures round-trip byte-identically with no edit
- [ ] All twelve survive an edit and are idempotent across a second save
- [ ] The existing fixtures (`accordion-block.html`, `gallery-block.html`, `post-17780.html`, `tabs-block.html`, `unsupported-blocks.html`) still round-trip — these protect already-published posts
- [ ] A table with a caption and a footer row keeps both through an edit in the running app
- [ ] A button set to open in a new tab still does after an edit
- [ ] `drafts.db` bytes match expectations, checked directly rather than through code view
- [ ] `CLAUDE.md` test counts match a fresh run of each suite
