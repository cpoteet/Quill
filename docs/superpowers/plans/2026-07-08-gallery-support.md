# Gallery Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users insert WordPress galleries in Quill via a native picker, and recognize (read-only) galleries already present in loaded posts, without adding any in-place gallery editing to the Tiptap/ProseMirror document model.

**Architecture:** A new atomic Tiptap node (`galleryBlock`) renders as a static, non-editable card in the editor — the same pattern `EmbedBlock` already uses. All authoring happens in a new native SwiftUI sheet (`GallerySheet`), reached from a new toolbar button. On insert, Swift sends a JSON payload across the existing WKWebView bridge to a new `insertGallery()` JS function. `editor-transforms.js`'s `toWordPressHTML` wraps the rendered gallery figure with the Gutenberg `<!-- wp:gallery -->`/`<!-- wp:image -->` block comments WordPress requires, mirroring how it already wraps `EmbedBlock` output.

**Tech Stack:** Swift 6 / SwiftUI (native sheet + bridge), Tiptap 2.x node running inside the existing WKWebView editor, plain DOM transforms in `editor-transforms.js`, Node + jsdom for JS tests, Swift Testing for Swift tests.

## Global Constraints

- Insert-only for v1: existing galleries load as read-only cards; they do not open the `GallerySheet` for editing.
- Gallery-wide (not per-image) `linkTo` setting, two options only: `none` / `media` (full-resolution image file). No "link to attachment page."
- No per-image captions.
- Columns (1–8) and "crop to square" are both exposed as gallery-wide settings in the sheet.
- Image URL stored on each gallery image is `mediaDetails.sizes["large"]?.sourceURL ?? sourceURL` (prefer the real "large" derivative when WordPress generated one; fall back to the original file otherwise — WordPress does this itself when an image is smaller than the "large" threshold).
- Every serialized attribute (`ids`, `columns`, `linkTo` on `wp:gallery`; `sizeSlug`, `linkDestination` on each `wp:image`) is emitted explicitly, never omitted at a default value — confirmed safe against a real gallery block fetched from the user's local WordPress site (see Task 1), and avoids guessing at WordPress's default-omission rules, which are not fully consistent (`linkTo`/`linkDestination` are always present even at their default in the observed sample, so "omit at default" is not a reliable rule to lean on for the untested `imageCrop` case either). The `id` key is included only when known (omitted, not `null`, for images without a recognized `wp-image-{id}` class).
- **Existing galleries round-trip verbatim, not reconstructed.** `galleryBlock` captures the original `figure.wp-block-gallery` element's `outerHTML` in a `sourceHTML` attr on load. `renderHTML` re-emits `sourceHTML` unchanged when it's set, instead of rebuilding the figure from the structured `images`/`columns`/`cropped`/`linkTo` attrs (those are still populated from the parse, and still drive the read-only card's thumbnail grid — they just aren't the source of truth for what gets saved). This is the same verbatim-preservation approach `EmbedBlock.caption` already uses. Without it, any post edit that clears `_rawHTML` would silently drop per-image captions, a gallery-level caption, the original `sizeSlug` (if not "large"), and any other comment-JSON attributes Quill doesn't model — turning "block survives or vanishes" into "block always survives but silently loses fidelity," which is worse in an important way (invisible) even though it's better in aggregate (never fully dropped). Sheet-inserted galleries never set `sourceHTML` (it's `null` by default), so they always use the structured reconstruction path.
- **Never make `galleryBlock.parseHTML`'s `getAttrs` return `false` for a gallery it can partially handle** (e.g. as a shortcut to "opt out" of a case with captions). Confirmed via `ResizableImage`'s parse rules (`editor.html:1392`): there's a catch-all `{ tag: 'img[src]' }` rule with no `getAttrs` restriction, so any `<img>` not claimed by `galleryBlock` gets individually claimed by `ResizableImage` instead — the gallery would visually explode into a sequence of standalone resizable images, not degrade gracefully. `getAttrs` returning `false` is only correct for genuinely non-gallery-shaped input (zero `figure.wp-block-image` children — e.g. the pre-WP-5.9 `ul.blocks-gallery-grid` format, which already exhibits this same explosion today and is out of scope for this plan).
- Confirmed reference markup (fetched 2026-07-08 from `http://localhost:8881`, post 170, image IDs 145/146/147 — this is ground truth, not a guess):

```html
<!-- wp:gallery {"ids":[145,146,147],"columns":3,"linkTo":"none"} -->
<figure class="wp-block-gallery has-nested-images columns-3 is-cropped"><!-- wp:image {"id":145,"sizeSlug":"large","linkDestination":"none"} -->
<figure class="wp-block-image size-large"><img src="http://localhost:8881/wp-content/uploads/2026/06/ai-writing-9.06.39-PM.png" alt="" class="wp-image-145"/></figure>
<!-- /wp:image -->

<!-- wp:image {"id":146,"sizeSlug":"large","linkDestination":"none"} -->
<figure class="wp-block-image size-large"><img src="http://localhost:8881/wp-content/uploads/2026/06/ai-writing-9.06.39-PM-1.png" alt="" class="wp-image-146"/></figure>
<!-- /wp:image -->

<!-- wp:image {"id":147,"sizeSlug":"large","linkDestination":"none"} -->
<figure class="wp-block-image size-large"><img src="http://localhost:8881/wp-content/uploads/2026/06/screenshot.png" alt="" class="wp-image-147"/></figure>
<!-- /wp:image --></figure>
<!-- /wp:gallery -->
```

---

### Task 1: `editor-transforms.js` — gallery block-comment wrapping

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js:16-22` (strip-stale-comments header), `:32` (image-figure selector), and add a new block before `return div.innerHTML` (currently `:179`, will shift as earlier edits land — insert immediately after the existing embed-wrapping block).
- Test: `Scripts/test-editor.js`

**Interfaces:**
- Consumes: nothing new — operates purely on HTML strings, same as the existing `toWordPressHTML(html, doc)`.
- Produces: `toWordPressHTML` now also wraps any `figure.wp-block-gallery` (with nested `figure.wp-block-image` children) with `<!-- wp:gallery {...} -->`/`<!-- /wp:gallery -->` and per-image `<!-- wp:image {...} -->`/`<!-- /wp:image -->` comments. Later tasks' `renderHTML` for `galleryBlock` must produce exactly the DOM shape this expects: an outer `<figure class="wp-block-gallery has-nested-images columns-N[ is-cropped]">` containing, for each image, a `<figure class="wp-block-image size-large">` wrapping either a bare `<img class="wp-image-{id}">` (linkTo none) or `<a href="{full url}"><img class="wp-image-{id}"></a>` (linkTo media).

- [ ] **Step 1: Write the failing tests**

Add to `Scripts/test-editor.js`, after the existing `describe('toWordPressHTML — embeds', ...)` block (around line 737):

```js
describe('toWordPressHTML — gallery', () => {
  const GALLERY_FIGURE =
    '<figure class="wp-block-gallery has-nested-images columns-3 is-cropped">' +
    '<figure class="wp-block-image size-large"><img src="http://x.test/a.png" alt="" class="wp-image-145"></figure>' +
    '<figure class="wp-block-image size-large"><img src="http://x.test/b.png" alt="" class="wp-image-146"></figure>' +
    '<figure class="wp-block-image size-large"><img src="http://x.test/c.png" alt="" class="wp-image-147"></figure>' +
    '</figure>'

  test('gallery figure gets wp:gallery and wp:image comment wrappers', () => {
    const out = wp(GALLERY_FIGURE)
    assert.match(out, /<!-- wp:gallery \{"ids":\[145,146,147\],"columns":3,"linkTo":"none"\} -->/)
    assert.match(out, /<!-- \/wp:gallery -->/)
    const openImg = (out.match(/<!-- wp:image /g) || []).length
    const closeImg = (out.match(/<!-- \/wp:image -->/g) || []).length
    assert.equal(openImg, 3)
    assert.equal(closeImg, 3)
    assert.match(out, /<!-- wp:image \{"id":145,"sizeSlug":"large","linkDestination":"none"\} -->/)
  })

  test('gallery wrapping is idempotent', () => {
    const once = wp(GALLERY_FIGURE)
    assert.equal(wp(once), once)
  })

  test('outer gallery figure does not gain wp-block-image class', () => {
    const out = wp(GALLERY_FIGURE)
    const outerTag = out.slice(out.indexOf('<figure class="wp-block-gallery'))
    assert.ok(!outerTag.startsWith('<figure class="wp-block-gallery has-nested-images columns-3 is-cropped wp-block-image'))
  })

  test('gallery with linkTo=media wraps images in anchors and records linkDestination', () => {
    const linked = GALLERY_FIGURE.replace(
      /<img src="([^"]+)"([^>]*)>/g,
      '<a href="$1"><img src="$1"$2></a>'
    )
    const out = wp(linked)
    assert.match(out, /"linkTo":"media"/)
    assert.match(out, /"linkDestination":"media"/)
    assert.ok(out.includes('<a href="http://x.test/a.png">'))
  })

  test('cropped=false omits is-cropped class and sets imageCrop:false', () => {
    const uncropped = GALLERY_FIGURE.replace(' is-cropped', '')
    const out = wp(uncropped)
    assert.match(out, /"imageCrop":false/)
  })

  test('sizeSlug is read from the image figure class, not hardcoded', () => {
    const medium = GALLERY_FIGURE.replace(/size-large/g, 'size-medium')
    const out = wp(medium)
    assert.match(out, /"sizeSlug":"medium"/)
    assert.ok(!out.includes('"sizeSlug":"large"'))
  })

  test('an image with no wp-image-N class omits the id key instead of writing null', () => {
    const noId = GALLERY_FIGURE.replace(' class="wp-image-145"', '')
    const out = wp(noId)
    assert.ok(!out.includes('"id":null'))
    assert.match(out, /<!-- wp:image \{"sizeSlug":"large","linkDestination":"none"\} -->/)
  })
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test Scripts/test-editor.js`
Expected: the 7 new tests under `toWordPressHTML — gallery` FAIL (no gallery wrapping exists yet); all other existing tests still PASS.

- [ ] **Step 3: Strip stale gallery/image comments on re-save**

In `Sources/QuillKit/Resources/editor-transforms.js`, extend the existing strip block (currently lines 19-22):

```js
  div.innerHTML = html
    .replace(/<!-- wp:embed [^\n]*-->\n?/g, '')
    .replace(/\n?<!-- \/wp:embed -->/g, '')
    .replace(/<!-- wp:gallery [^\n]*-->\n?/g, '')
    .replace(/\n?<!-- \/wp:gallery -->/g, '')
    // wp:image comments only ever appear nested inside a gallery today (standalone
    // images aren't comment-wrapped at all — see the images row in CLAUDE.md's
    // Gutenberg-compatibility table), so this strip is gallery-scoped in practice.
    // If a future change routes raw WordPress HTML through toWordPressHTML, revisit —
    // this would strip a standalone image's own wp:image block identity too.
    .replace(/<!-- wp:image [^\n]*-->\n?/g, '')
    .replace(/\n?<!-- \/wp:image -->/g, '')
```

- [ ] **Step 4: Exclude gallery figures from the generic image-figure transform**

Change line 32 from:

```js
  div.querySelectorAll('figure:not(.wp-block-table):not(.wp-block-embed)').forEach(figure => {
```

to:

```js
  div.querySelectorAll('figure:not(.wp-block-table):not(.wp-block-embed):not(.wp-block-gallery)').forEach(figure => {
```

Without this, the generic loop's `figure.querySelector('img')` would find the *first descendant* image inside a gallery figure and wrongly add a stray `wp-block-image` class to the outer gallery figure itself. The nested per-image figures (which already carry `wp-block-image` class directly from `renderHTML`, added in Task 2) still pass through this loop harmlessly — they have no alignment classes and no caption, so the loop's `else` branch just re-adds a class they already have.

- [ ] **Step 5: Add the gallery comment-wrapping block**

Add this immediately after the existing embed-wrapping block (the one ending `return div.innerHTML` follows), i.e. directly before `return div.innerHTML`:

```js
  // Wrap gallery figures with Gutenberg block comments: one wp:gallery pair
  // around the whole figure, one wp:image pair per nested image figure.
  // Mirrors the embed-wrapping approach above — DOM-level insertion, not
  // string replace, so repeated saves and duplicate content don't double-wrap.
  div.querySelectorAll('figure.wp-block-gallery').forEach(figure => {
    const columnsMatch = figure.className.match(/columns-(\d+)/)
    const columns = columnsMatch ? parseInt(columnsMatch[1], 10) : 3
    const cropped = figure.classList.contains('is-cropped')
    const imageFigures = Array.from(figure.children).filter(
      c => c.tagName === 'FIGURE' && c.classList.contains('wp-block-image')
    )
    const ids = []
    let linkTo = 'none'
    imageFigures.forEach((imgFigure, i) => {
      const img = imgFigure.querySelector('img')
      if (!img) return
      const idMatch = img.className.match(/wp-image-(\d+)/)
      const id = idMatch ? parseInt(idMatch[1], 10) : null
      if (id !== null) ids.push(id)
      const linkedToMedia = img.parentElement.tagName === 'A'
      if (i === 0) linkTo = linkedToMedia ? 'media' : 'none'
      // Read the real size slug from the image figure's own class rather than
      // hardcoding "large" — this matters once galleryBlock can round-trip an
      // existing gallery's original figure verbatim (Task 2's sourceHTML attr),
      // where the true sizeSlug may not be "large".
      const sizeMatch = imgFigure.className.match(/size-(\S+)/)
      const sizeSlug = sizeMatch ? sizeMatch[1] : 'large'
      const imageAttrs = {}
      if (id !== null) imageAttrs.id = id
      imageAttrs.sizeSlug = sizeSlug
      imageAttrs.linkDestination = linkedToMedia ? 'media' : 'none'
      const openImg = doc.createComment(` wp:image ${JSON.stringify(imageAttrs)} `)
      const closeImg = doc.createComment(' /wp:image ')
      const afterImg = imgFigure.nextSibling
      if (i > 0) figure.insertBefore(doc.createTextNode('\n\n'), imgFigure)
      figure.insertBefore(openImg, imgFigure)
      figure.insertBefore(doc.createTextNode('\n'), imgFigure)
      figure.insertBefore(doc.createTextNode('\n'), afterImg)
      figure.insertBefore(closeImg, afterImg)
    })
    const galleryAttrs = { ids, columns, linkTo }
    if (!cropped) galleryAttrs.imageCrop = false
    const openGallery = doc.createComment(` wp:gallery ${JSON.stringify(galleryAttrs)} `)
    const closeGallery = doc.createComment(' /wp:gallery ')
    const parent = figure.parentNode
    const next = figure.nextSibling
    parent.insertBefore(openGallery, figure)
    parent.insertBefore(doc.createTextNode('\n'), figure)
    parent.insertBefore(doc.createTextNode('\n'), next)
    parent.insertBefore(closeGallery, next)
  })

```

- [ ] **Step 6: Run tests to verify they pass**

Run: `node --test Scripts/test-editor.js`
Expected: all tests PASS, including the 7 new gallery tests and every pre-existing test (111 previously, 118 now).

- [ ] **Step 7: Commit**

```bash
git add Sources/QuillKit/Resources/editor-transforms.js Scripts/test-editor.js
git commit -m "feat: wrap gallery figures with Gutenberg block comments on save"
```

---

### Task 2: `editor.html` — `galleryBlock` Tiptap node

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` — add `GalleryNodeView` class and `GalleryBlock` node definition (near `EmbedBlock`, currently around line 1465-1532), register `GalleryBlock` in the extensions array (currently line 1849, immediately after `EmbedBlock,`), add `.gallery-card` CSS (near `.embed-card` CSS, currently lines 728-744).
- Test: `Scripts/test-editor-gallery.js` (new file)

**Interfaces:**
- Consumes: nothing new.
- Produces: a Tiptap node type named `galleryBlock` with attrs `{ images: [{id, url, alt}], columns: number, cropped: boolean, linkTo: 'none'|'media', sourceHTML: string|null }`, insertable via `editor.chain().focus().insertContent({ type: 'galleryBlock', attrs: {...} }).run()`. When `sourceHTML` is null (sheet-inserted galleries), `editor.getHTML()` reconstructs the figure from `images`/`columns`/`cropped`/`linkTo`, producing the `figure.wp-block-gallery > figure.wp-block-image > img` shape Task 1's `toWordPressHTML` expects. When `sourceHTML` is set (galleries loaded from an existing post), `editor.getHTML()` re-emits it verbatim instead — captions, original `sizeSlug`, and any other content inside the figure survive untouched. Loading HTML containing `figure.wp-block-gallery` always produces a `galleryBlock` node with both the structured attrs (used by the read-only card's thumbnail grid) and `sourceHTML` (the source of truth for what gets saved) populated from the DOM.

- [ ] **Step 1: Write the failing tests**

Create `Scripts/test-editor-gallery.js`:

```js
'use strict'

// Live Tiptap tests for the galleryBlock node — loads the REAL editor.html in
// jsdom, same approach as test-editor-keyboard.js, because parseHTML/renderHTML
// for a custom Tiptap node can't be tested via the pure editor-transforms.js
// helpers (those only cover post-serialization DOM transforms).

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

describe('galleryBlock — insert and render', () => {
  test('inserting a galleryBlock renders wp-block-gallery figure with nested image figures', () => {
    editor.commands.setContent('<p></p>')
    editor.commands.insertContent({
      type: 'galleryBlock',
      attrs: {
        images: [
          { id: 1, url: 'http://x.test/a.png', alt: '' },
          { id: 2, url: 'http://x.test/b.png', alt: '' },
        ],
        columns: 3,
        cropped: true,
        linkTo: 'none',
      },
    })
    const html = editor.getHTML()
    assert.match(html, /<figure class="wp-block-gallery has-nested-images columns-3 is-cropped">/)
    assert.match(html, /class="wp-block-image size-large"/)
    assert.match(html, /class="wp-image-1"/)
    assert.match(html, /class="wp-image-2"/)
  })

  test('linkTo media wraps each image in an anchor to its own url', () => {
    editor.commands.setContent('<p></p>')
    editor.commands.insertContent({
      type: 'galleryBlock',
      attrs: {
        images: [{ id: 5, url: 'http://x.test/full.png', alt: '' }],
        columns: 3,
        cropped: true,
        linkTo: 'media',
      },
    })
    const html = editor.getHTML()
    assert.match(html, /<a href="http:\/\/x\.test\/full\.png"><img[^>]*class="wp-image-5"[^>]*><\/a>/)
  })

  test('cropped false omits is-cropped class', () => {
    editor.commands.setContent('<p></p>')
    editor.commands.insertContent({
      type: 'galleryBlock',
      attrs: { images: [{ id: 1, url: 'http://x.test/a.png', alt: '' }], columns: 2, cropped: false, linkTo: 'none' },
    })
    const html = editor.getHTML()
    assert.match(html, /<figure class="wp-block-gallery has-nested-images columns-2">/)
  })
})

describe('galleryBlock — load (parseHTML)', () => {
  test('loading real gallery HTML recovers images, columns, cropped, linkTo', () => {
    const realGallery =
      '<figure class="wp-block-gallery has-nested-images columns-3 is-cropped">' +
      '<figure class="wp-block-image size-large"><img src="http://localhost:8881/wp-content/uploads/2026/06/ai-writing-9.06.39-PM.png" alt="" class="wp-image-145"/></figure>' +
      '<figure class="wp-block-image size-large"><img src="http://localhost:8881/wp-content/uploads/2026/06/ai-writing-9.06.39-PM-1.png" alt="" class="wp-image-146"/></figure>' +
      '</figure>'
    editor.commands.setContent(realGallery)
    let found = null
    editor.state.doc.descendants(n => { if (n.type.name === 'galleryBlock') found = n })
    assert.ok(found, 'expected a galleryBlock node in the parsed document')
    assert.equal(found.attrs.images.length, 2)
    assert.equal(found.attrs.images[0].id, 145)
    assert.equal(found.attrs.images[0].url, 'http://localhost:8881/wp-content/uploads/2026/06/ai-writing-9.06.39-PM.png')
    assert.equal(found.attrs.columns, 3)
    assert.equal(found.attrs.cropped, true)
    assert.equal(found.attrs.linkTo, 'none')
  })

  test('loading a gallery with images linked to media recovers linkTo=media', () => {
    const linked =
      '<figure class="wp-block-gallery has-nested-images columns-3 is-cropped">' +
      '<figure class="wp-block-image size-large"><a href="http://x.test/a.png"><img src="http://x.test/a.png" alt="" class="wp-image-1"/></a></figure>' +
      '</figure>'
    editor.commands.setContent(linked)
    let found = null
    editor.state.doc.descendants(n => { if (n.type.name === 'galleryBlock') found = n })
    assert.ok(found)
    assert.equal(found.attrs.linkTo, 'media')
  })

  test('captures sourceHTML verbatim, including content the structured attrs do not model', () => {
    const captioned =
      '<figure class="wp-block-gallery has-nested-images columns-3 is-cropped">' +
      '<figure class="wp-block-image size-medium"><img src="http://x.test/a.png" alt="" class="wp-image-1"/><figcaption class="wp-element-caption">A caption</figcaption></figure>' +
      '</figure>'
    editor.commands.setContent(captioned)
    let found = null
    editor.state.doc.descendants(n => { if (n.type.name === 'galleryBlock') found = n })
    assert.ok(found)
    assert.ok(found.attrs.sourceHTML.includes('A caption'))
    assert.ok(found.attrs.sourceHTML.includes('size-medium'))
  })
})

describe('galleryBlock — verbatim re-render (sourceHTML)', () => {
  test('a loaded gallery with a caption re-renders with the caption intact', () => {
    const captioned =
      '<figure class="wp-block-gallery has-nested-images columns-3 is-cropped">' +
      '<figure class="wp-block-image size-medium"><img src="http://x.test/a.png" alt="" class="wp-image-1"/><figcaption class="wp-element-caption">A caption</figcaption></figure>' +
      '</figure>'
    editor.commands.setContent(captioned)
    const html = editor.getHTML()
    assert.ok(html.includes('A caption'))
    assert.ok(html.includes('size-medium'))
  })

  test('sheet-inserted galleries (sourceHTML null) still use the reconstruction path', () => {
    editor.commands.setContent('<p></p>')
    editor.commands.insertContent({
      type: 'galleryBlock',
      attrs: { images: [{ id: 1, url: 'http://x.test/a.png', alt: '' }], columns: 3, cropped: true, linkTo: 'none' },
    })
    let found = null
    editor.state.doc.descendants(n => { if (n.type.name === 'galleryBlock') found = n })
    assert.equal(found.attrs.sourceHTML, null)
    assert.ok(editor.getHTML().includes('size-large'))
  })
})

describe('galleryBlock — code-view round-trip', () => {
  test('serialize via toWordPressHTML then re-parse preserves a sheet-inserted gallery', () => {
    editor.commands.setContent('<p></p>')
    editor.commands.insertContent({
      type: 'galleryBlock',
      attrs: {
        images: [
          { id: 1, url: 'http://x.test/a.png', alt: '' },
          { id: 2, url: 'http://x.test/b.png', alt: '' },
        ],
        columns: 4,
        cropped: false,
        linkTo: 'media',
      },
    })
    const serialized = win.toWordPressHTML(editor.getHTML())
    assert.match(serialized, /<!-- wp:gallery /)
    editor.commands.setContent(serialized)
    let found = null
    editor.state.doc.descendants(n => { if (n.type.name === 'galleryBlock') found = n })
    assert.ok(found, 'gallery survived the code-view round trip')
    assert.equal(found.attrs.images.length, 2)
    assert.equal(found.attrs.columns, 4)
    assert.equal(found.attrs.cropped, false)
    assert.equal(found.attrs.linkTo, 'media')
  })

  test('serialize then re-parse preserves a loaded, captioned gallery verbatim', () => {
    const captioned =
      '<figure class="wp-block-gallery has-nested-images columns-3 is-cropped">' +
      '<figure class="wp-block-image size-medium"><img src="http://x.test/a.png" alt="" class="wp-image-1"/><figcaption class="wp-element-caption">A caption</figcaption></figure>' +
      '</figure>'
    editor.commands.setContent(captioned)
    const serialized = win.toWordPressHTML(editor.getHTML())
    assert.match(serialized, /"sizeSlug":"medium"/)
    editor.commands.setContent(serialized)
    let found = null
    editor.state.doc.descendants(n => { if (n.type.name === 'galleryBlock') found = n })
    assert.ok(found)
    assert.ok(found.attrs.sourceHTML.includes('A caption'))
  })
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test Scripts/test-editor-gallery.js`
Expected: FAIL — `galleryBlock` node type does not exist yet, `editor.getHTML()` won't contain gallery markup, `descendants` won't find any `galleryBlock` node.

- [ ] **Step 3: Add `.gallery-card` CSS**

In `Sources/QuillKit/Resources/editor.html`, immediately after the existing embed-card CSS block (after line 744, `body.dark .embed-card-hint { color: #777; }`):

```css

    /* ── Gallery card ───────────────────────────────── */
    .gallery-card {
      margin: 1em 0;
      padding: 14px 16px;
      border: 1px solid rgba(0,0,0,0.14);
      border-radius: 8px;
      background: rgba(0,0,0,0.025);
      cursor: default;
      user-select: none;
    }
    .gallery-card.selected { outline: 2px solid #b45309; outline-offset: 1px; }
    .gallery-card-grid { display: flex; flex-wrap: wrap; gap: 6px; }
    .gallery-card-grid img {
      width: 64px;
      height: 64px;
      object-fit: cover;
      border-radius: 4px;
    }
    .gallery-card-hint { font-size: 11px; color: #999; margin-top: 8px; font-style: italic; }
    body.dark .gallery-card { border-color: rgba(255,255,255,0.18); background: rgba(255,255,255,0.04); }
    body.dark .gallery-card-hint { color: #777; }
```

- [ ] **Step 4: Add `GalleryNodeView` and `GalleryBlock` node**

In `Sources/QuillKit/Resources/editor.html`, immediately after the closing `})` of `EmbedBlock` (currently line 1532, right before the `// ── Footnotes ─────` comment):

```js

    // ── Gallery block ─────────────────────────────────
    // Atomic block storing an ordered image list + gallery-wide settings.
    // Saved HTML is the Gutenberg gallery figure (nested wp-block-image
    // figures, wrapped with wp:gallery/wp:image comments by toWordPressHTML);
    // in the editor it renders as a static thumbnail-grid card — all editing
    // happens in the native GallerySheet, not in Tiptap. Read-only: galleries
    // loaded from existing posts render the same card but are not re-openable
    // for editing in v1.
    class GalleryNodeView {
      constructor(node) {
        this.dom = document.createElement('div')
        this.dom.className = 'gallery-card'
        const grid = document.createElement('div')
        grid.className = 'gallery-card-grid'
        node.attrs.images.forEach(image => {
          const img = document.createElement('img')
          img.src = image.url
          img.alt = image.alt || ''
          grid.appendChild(img)
        })
        const hint = document.createElement('div')
        hint.className = 'gallery-card-hint'
        const count = node.attrs.images.length
        hint.textContent = `${count} image${count === 1 ? '' : 's'} · Renders as a WordPress gallery`
        this.dom.append(grid, hint)
      }
      selectNode()   { this.dom.classList.add('selected') }
      deselectNode() { this.dom.classList.remove('selected') }
    }

    const GalleryBlock = TiptapNode.create({
      name: 'galleryBlock',
      group: 'block',
      atom: true,
      draggable: true,
      priority: 110,

      addAttributes() {
        return {
          images:     { default: [] },
          columns:    { default: 3 },
          cropped:    { default: true },
          linkTo:     { default: 'none' },
          // Verbatim copy of the original figure's outerHTML, captured on load.
          // When set, renderHTML re-emits this unchanged instead of reconstructing
          // from the structured attrs above — preserves captions, original
          // sizeSlug, and anything else Quill doesn't model. null for
          // sheet-inserted galleries, which always use the reconstruction path.
          sourceHTML: { default: null },
        }
      },

      parseHTML() {
        return [{
          tag: 'figure.wp-block-gallery',
          getAttrs: el => {
            const imageFigures = Array.from(el.querySelectorAll('figure.wp-block-image'))
            if (imageFigures.length === 0) return false
            const images = imageFigures.map(fig => {
              const img = fig.querySelector('img')
              const idMatch = img?.className.match(/wp-image-(\d+)/)
              return {
                id: idMatch ? parseInt(idMatch[1], 10) : null,
                url: img?.getAttribute('src') || '',
                alt: img?.getAttribute('alt') || '',
              }
            })
            const columnsMatch = el.className.match(/columns-(\d+)/)
            const firstImg = imageFigures[0].querySelector('img')
            return {
              images,
              columns: columnsMatch ? parseInt(columnsMatch[1], 10) : 3,
              cropped: el.classList.contains('is-cropped'),
              linkTo: firstImg?.parentElement.tagName === 'A' ? 'media' : 'none',
              sourceHTML: el.outerHTML,
            }
          },
        }]
      },

      renderHTML({ node }) {
        if (node.attrs.sourceHTML) {
          const wrapper = document.createElement('div')
          wrapper.innerHTML = node.attrs.sourceHTML
          return wrapper.firstElementChild
        }
        const figure = document.createElement('figure')
        figure.className = `wp-block-gallery has-nested-images columns-${node.attrs.columns}` +
          (node.attrs.cropped ? ' is-cropped' : '')
        node.attrs.images.forEach(image => {
          const imgFigure = document.createElement('figure')
          imgFigure.className = 'wp-block-image size-large'
          const img = document.createElement('img')
          img.setAttribute('src', image.url)
          img.setAttribute('alt', image.alt || '')
          if (image.id) img.classList.add(`wp-image-${image.id}`)
          if (node.attrs.linkTo === 'media') {
            const a = document.createElement('a')
            a.setAttribute('href', image.url)
            a.appendChild(img)
            imgFigure.appendChild(a)
          } else {
            imgFigure.appendChild(img)
          }
          figure.appendChild(imgFigure)
        })
        return figure
      },

      addNodeView() {
        return ({ node }) => new GalleryNodeView(node)
      },
    })
```

- [ ] **Step 5: Register `GalleryBlock` in the extensions array**

In the same file, change line 1849 from:

```js
        EmbedBlock,
```

to:

```js
        EmbedBlock,
        GalleryBlock,
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `node --test Scripts/test-editor-gallery.js`
Expected: all 10 tests PASS.

- [ ] **Step 7: Run the full JS suite to check for regressions**

Run: `node --test Scripts/test-editor.js Scripts/test-editor-keyboard.js Scripts/test-editor-gallery.js`
Expected: all suites PASS — 118 in `test-editor.js` (111 + Task 1's 7 gallery-transform tests) + 16 in `test-editor-keyboard.js` + 10 in the new `test-editor-gallery.js` = 144 total.

- [ ] **Step 8: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Scripts/test-editor-gallery.js
git commit -m "feat: add galleryBlock Tiptap node with read-only card rendering"
```

---

### Task 3: `editor.html` — insert function and toolbar button

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` — toolbar button HTML (near line 896-901), `BLOCK_CMDS` array (~line 1946), `COMMANDS.gallery` entry (near `COMMANDS.image`, ~line 2037-2042), `window.insertGallery` global function (near `window.insertImage`, ~line 2729-2737).
- Test: `Scripts/test-editor-gallery.js`

**Interfaces:**
- Consumes: `galleryBlock` node type from Task 2.
- Produces: `window.insertGallery(jsonString)` — parses `jsonString` as `{images, columns, cropped, linkTo}` and inserts a `galleryBlock`. A toolbar button (`data-cmd="gallery"`) that posts an empty message to `window.webkit.messageHandlers.insertGallery` (consumed by Task 4's Swift bridge).

- [ ] **Step 1: Write the failing test**

Add to `Scripts/test-editor-gallery.js`, in a new `describe` block:

```js
describe('window.insertGallery bridge function', () => {
  test('inserts a galleryBlock from a JSON payload', () => {
    editor.commands.setContent('<p></p>')
    win.insertGallery(JSON.stringify({
      images: [{ id: 9, url: 'http://x.test/z.png', alt: '' }],
      columns: 4,
      cropped: false,
      linkTo: 'none',
    }))
    let found = null
    editor.state.doc.descendants(n => { if (n.type.name === 'galleryBlock') found = n })
    assert.ok(found)
    assert.equal(found.attrs.columns, 4)
    assert.equal(found.attrs.cropped, false)
    assert.equal(found.attrs.images[0].id, 9)
  })

  test('ignores an empty images array', () => {
    editor.commands.setContent('<p>unchanged</p>')
    win.insertGallery(JSON.stringify({ images: [], columns: 3, cropped: true, linkTo: 'none' }))
    let found = null
    editor.state.doc.descendants(n => { if (n.type.name === 'galleryBlock') found = n })
    assert.equal(found, null)
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test Scripts/test-editor-gallery.js`
Expected: FAIL — `win.insertGallery is not a function`.

- [ ] **Step 3: Add the toolbar button**

In `Sources/QuillKit/Resources/editor.html`, change the utility group (currently lines 896-901) from:

```html
    <span class="tb-group">
      <button data-cmd="image" title="Insert image from media library" class="tb-add">
        <svg viewBox="0 0 24 24"><rect x="4" y="7" width="14" height="14" rx="2"></rect><path d="m4 18 4.6-4.6 3.2 3.2 2.2-2.2 4 4"></path><path class="tb-image-plus-cutout" d="M18 3.5v7M14.5 7h7"></path><path class="tb-image-plus" d="M18 3.5v7M14.5 7h7"></path></svg>
        <span>Add</span>
      </button>
    </span>
```

to:

```html
    <span class="tb-group">
      <button data-cmd="image" title="Insert image from media library" class="tb-add">
        <svg viewBox="0 0 24 24"><rect x="4" y="7" width="14" height="14" rx="2"></rect><path d="m4 18 4.6-4.6 3.2 3.2 2.2-2.2 4 4"></path><path class="tb-image-plus-cutout" d="M18 3.5v7M14.5 7h7"></path><path class="tb-image-plus" d="M18 3.5v7M14.5 7h7"></path></svg>
        <span>Add</span>
      </button>
      <button data-cmd="gallery" title="Insert gallery from media library" class="tb-add">
        <svg viewBox="0 0 24 24"><rect x="3" y="4" width="8" height="8" rx="1"></rect><rect x="13" y="4" width="8" height="8" rx="1"></rect><rect x="3" y="14" width="8" height="8" rx="1"></rect><rect x="13" y="14" width="8" height="8" rx="1"></rect></svg>
        <span>Gallery</span>
      </button>
    </span>
```

- [ ] **Step 4: Add `'gallery'` to `BLOCK_CMDS`**

Change (currently ~line 1946-1947):

```js
    const BLOCK_CMDS = ['blockquote','codeBlock','bulletList','orderedList',
                        'insertTable','image']
```

to:

```js
    const BLOCK_CMDS = ['blockquote','codeBlock','bulletList','orderedList',
                        'insertTable','image','gallery']
```

This ensures the Gallery toolbar button is disabled inside footnotes, matching the existing `image` button.

- [ ] **Step 5: Add `COMMANDS.gallery`**

In the `COMMANDS` object, immediately after the existing `image: () => {...}` entry (currently lines 2037-2042):

```js
      gallery: () => {
        if (_isInFootnote()) return
        if (window.webkit?.messageHandlers?.insertGallery) {
          window.webkit.messageHandlers.insertGallery.postMessage({})
        }
      },
```

- [ ] **Step 6: Add `window.insertGallery`**

Immediately after `window.insertImage = (...) => {...}` (currently lines 2729-2737):

```js
    window.insertGallery = (json) => {
      if (_isInFootnote()) return
      let payload
      try { payload = JSON.parse(json) } catch { return }
      if (!Array.isArray(payload.images) || payload.images.length === 0) return
      editor.chain().focus().insertContent({
        type: 'galleryBlock',
        attrs: {
          images: payload.images,
          columns: payload.columns ?? 3,
          cropped: payload.cropped ?? true,
          linkTo: payload.linkTo ?? 'none',
        },
      }).run()
    }
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `node --test Scripts/test-editor-gallery.js`
Expected: all tests PASS (12 total in this file).

- [ ] **Step 8: Run full JS suite**

Run: `node --test Scripts/test-editor.js Scripts/test-editor-keyboard.js Scripts/test-editor-gallery.js`
Expected: all PASS, no regressions.

- [ ] **Step 9: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Scripts/test-editor-gallery.js
git commit -m "feat: add gallery toolbar button and insertGallery bridge function"
```

---

### Task 4: Swift bridge — `EditorCoordinator` + `EditorView`

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/EditorCoordinator.swift` (add property, notification observer/handler, message-handler case, `insertGallery` method, notification name)
- Modify: `Sources/QuillKit/Views/Editor/EditorView.swift` (add param, register message handler, wire callback)

**Interfaces:**
- Consumes: the `"insertGallery"` WKScriptMessage posted by Task 3's toolbar button, and `window.insertGallery(json)` from Task 3.
- Produces: `EditorCoordinator.onInsertGallery: (() -> Void)?` (fired when the toolbar button is clicked — Task 5/6 wires this to show `GallerySheet`), `Notification.Name.insertGalleryData` (posted with userInfo `["images": [[String: Any]], "columns": Int, "cropped": Bool, "linkTo": String]` — Task 6 posts this from `GallerySheet`'s insert action), `EditorView.onInsertGallery: (() -> Void)?` init param mirroring `onInsertImage`.

- [ ] **Step 1: Add the notification name**

In `Sources/QuillKit/Views/Editor/EditorCoordinator.swift`, find `static let insertMediaURL = Notification.Name("Quill.insertMediaURL")` (currently line 313) and add immediately after:

```swift
    static let insertGalleryData = Notification.Name("Quill.insertGalleryData")
```

- [ ] **Step 2: Add the `onInsertGallery` property**

Add immediately after `var onInsertImage: (() -> Void)?` (currently line 12):

```swift
    var onInsertGallery: (() -> Void)?
```

- [ ] **Step 3: Register the notification observer**

In `init(onContentChange:onReady:)` (currently lines 24-34), add after the existing `.insertMediaURL` observer registration:

```swift
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInsertGallery(_:)),
            name: .insertGalleryData,
            object: nil
        )
```

- [ ] **Step 4: Add the notification handler and `insertGallery` method**

Immediately after `handleInsertMedia(_:)` (currently lines 36-43):

```swift
    @objc private func handleInsertGallery(_ note: Notification) {
        guard
            let images  = note.userInfo?["images"] as? [[String: Any]],
            let columns = note.userInfo?["columns"] as? Int,
            let cropped = note.userInfo?["cropped"] as? Bool,
            let linkTo  = note.userInfo?["linkTo"] as? String
        else { return }
        insertGallery(images: images, columns: columns, cropped: cropped, linkTo: linkTo)
    }
```

And immediately after the `insertImage(url:width:height:mediaId:alt:)` method (currently lines 198-215):

```swift
    func insertGallery(images: [[String: Any]], columns: Int, cropped: Bool, linkTo: String) {
        guard let wv = webView else { return }
        let payload: [String: Any] = [
            "images": images,
            "columns": columns,
            "cropped": cropped,
            "linkTo": linkTo,
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: jsonData, encoding: .utf8),
              let escapedData = try? JSONEncoder().encode(jsonStr),
              let escapedStr = String(data: escapedData, encoding: .utf8)
        else { return }
        wv.evaluateJavaScript("insertGallery(\(escapedStr))", completionHandler: nil)
    }
```

- [ ] **Step 5: Handle the `"insertGallery"` script message**

In `userContentController(_:didReceive:)`, add a case immediately after `case "insertImage":` (currently lines 67-68):

```swift
        case "insertGallery":
            DispatchQueue.main.async { self.onInsertGallery?() }
```

- [ ] **Step 6: Wire `EditorView`**

In `Sources/QuillKit/Views/Editor/EditorView.swift`:

Add the property (after `var onInsertImage: (() -> Void)?`, line 9):
```swift
    var onInsertGallery: (() -> Void)?
```

Add the init param (after `onInsertImage: (() -> Void)? = nil,`, line 28):
```swift
        onInsertGallery: (() -> Void)? = nil,
```

Add the assignment (after `self.onInsertImage = onInsertImage`, line 46):
```swift
        self.onInsertGallery = onInsertGallery
```

Register the message handler in `makeNSView` (after `config.userContentController.add(context.coordinator, name: "insertImage")`, line 70):
```swift
        config.userContentController.add(context.coordinator, name: "insertGallery")
```

Wire the coordinator in `makeNSView` (after `context.coordinator.onInsertImage = onInsertImage`, line 90):
```swift
        context.coordinator.onInsertGallery = onInsertGallery
```

Wire the coordinator in `updateNSView` (after `context.coordinator.onInsertImage = onInsertImage`, line 110):
```swift
        context.coordinator.onInsertGallery = onInsertGallery
```

- [ ] **Step 7: Verify the build**

Run: `swift build`
Expected: builds with no errors or warnings about unused `onInsertGallery`.

- [ ] **Step 8: Run Swift tests to check for regressions**

Run: `swift test`
Expected: all existing tests still PASS (this task adds no new Swift tests — bridge/WKWebView methods aren't unit tested elsewhere in this codebase either, e.g. `insertImage` has no dedicated test).

- [ ] **Step 9: Commit**

```bash
git add Sources/QuillKit/Views/Editor/EditorCoordinator.swift Sources/QuillKit/Views/Editor/EditorView.swift
git commit -m "feat: wire gallery insert bridge through EditorCoordinator and EditorView"
```

---

### Task 5: `GallerySheet` SwiftUI view

**Files:**
- Create: `Sources/QuillKit/Views/Media/GallerySheet.swift`

**Interfaces:**
- Consumes: `WPMedia` (`Sources/QuillKit/API/Models/WPMedia.swift`), `WordPressClient.fetchMedia(page:perPage:)`, `AppState.credentials` (same as `MediaPickerView`).
- Produces: `GallerySheet(onInsert: (_ images: [WPMedia], _ columns: Int, _ cropped: Bool, _ linkTo: String) -> Void, onCancel: (() -> Void)?)` — a SwiftUI view. Task 6 presents this in a `.sheet` and translates `onInsert`'s parameters into the `[String: Any]` dictionary `EditorCoordinator.handleInsertGallery` expects (`images` as `[[String: Any]]` built from each `WPMedia`).

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

public struct GallerySheet: View {
    var onInsert: (_ images: [WPMedia], _ columns: Int, _ cropped: Bool, _ linkTo: String) -> Void
    var onCancel: (() -> Void)?

    @EnvironmentObject private var appState: AppState
    @State private var mediaItems: [WPMedia] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var currentPage: Int = 1
    @State private var hasMore: Bool = false
    @State private var isLoadingMore = false
    @State private var selected: [WPMedia] = []
    @State private var columns: Int = 3
    @State private var cropped: Bool = true
    @State private var linkTo: String = "none"

    public init(
        onInsert: @escaping (_ images: [WPMedia], _ columns: Int, _ cropped: Bool, _ linkTo: String) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.onInsert = onInsert
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                mediaPane
                SoftPanelBoundary()
                selectionPane
            }
        }
        .task { await loadMedia() }
    }

    private var toolbar: some View {
        HStack {
            Button("Cancel") { onCancel?() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Text("Insert Gallery").font(.headline)
            Spacer()
            Button("Insert Gallery") {
                onInsert(selected, columns, cropped, linkTo)
            }
            .disabled(selected.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var mediaPane: some View {
        Group {
            if isLoading {
                ProgressView("Loading media…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                VStack(spacing: 8) {
                    Text(error).foregroundStyle(.secondary)
                    Button("Retry") { Task { await loadMedia() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(mediaItems.filter { $0.mediaType == "image" }) { media in
                            GalleryMediaThumbnail(media: media, isSelected: selected.contains(where: { $0.id == media.id }))
                                .contentShape(Rectangle())
                                .onTapGesture { toggle(media) }
                        }
                    }
                    .padding(12)
                    if hasMore {
                        Button {
                            Task { await loadMoreMedia() }
                        } label: {
                            if isLoadingMore {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Text("Load More")
                            }
                        }
                        .disabled(isLoadingMore)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 12)
                    }
                }
            }
        }
        .frame(minWidth: 340)
    }

    private var selectionPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selected (\(selected.count))")
                .font(.subheadline.weight(.semibold))
                .padding(.top, 12)
                .padding(.horizontal, 12)

            if selected.isEmpty {
                Text("Tap images to add them to the gallery.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            } else {
                List {
                    ForEach(selected) { media in
                        HStack {
                            AsyncImage(url: URL(string: media.thumbnailURL)) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    Rectangle().fill(.quaternary)
                                }
                            }
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(media.title.decodedTitle)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer()
                            Button {
                                selected.removeAll { $0.id == media.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onMove { indices, newOffset in
                        selected.move(fromOffsets: indices, toOffset: newOffset)
                    }
                }
                .listStyle(.plain)
            }

            Divider().padding(.horizontal, 12)

            Stepper("Columns: \(columns)", value: $columns, in: 1...8)
                .padding(.horizontal, 12)
            Toggle("Crop images to square", isOn: $cropped)
                .padding(.horizontal, 12)
            Picker("Link to", selection: $linkTo) {
                Text("None").tag("none")
                Text("Full Image").tag("media")
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 12)

            Spacer()
        }
        .frame(minWidth: 260, maxWidth: 300)
    }

    private func toggle(_ media: WPMedia) {
        if let idx = selected.firstIndex(where: { $0.id == media.id }) {
            selected.remove(at: idx)
        } else {
            selected.append(media)
        }
    }

    private let perPage = 50

    private func loadMedia() async {
        guard let creds = appState.credentials else { return }
        isLoading = true
        loadError = nil
        currentPage = 1
        defer { isLoading = false }
        do {
            let items = try await WordPressClient(credentials: creds).fetchMedia(page: 1, perPage: perPage)
            mediaItems = items
            hasMore = items.count == perPage
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadMoreMedia() async {
        guard let creds = appState.credentials else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let nextPage = currentPage + 1
        do {
            let items = try await WordPressClient(credentials: creds).fetchMedia(page: nextPage, perPage: perPage)
            mediaItems.append(contentsOf: items)
            currentPage = nextPage
            hasMore = items.count == perPage
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct GalleryMediaThumbnail: View {
    let media: WPMedia
    let isSelected: Bool

    var body: some View {
        Color.clear
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 80, maxHeight: 80)
            .overlay {
                AsyncImage(url: URL(string: media.thumbnailURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        Rectangle().fill(.quaternary)
                            .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
                    @unknown default:
                        Rectangle().fill(.quaternary)
                    }
                }
                .clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2 : 0.5)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(4)
                }
            }
    }
}
```

Note: `Color.clear`/`.overlay` thumbnail pattern and the fetch/error/retry structure intentionally mirror `MediaPickerView` (`Sources/QuillKit/Views/Media/MediaPickerView.swift`) — see its `MediaThumbnail` and `loadMedia()` for the precedent this follows.

- [ ] **Step 2: Verify the build**

Run: `swift build`
Expected: builds with no errors. (No automated test for this task — SwiftUI views aren't unit-tested elsewhere in this codebase; verification is the manual pass in Task 8.)

- [ ] **Step 3: Commit**

```bash
git add Sources/QuillKit/Views/Media/GallerySheet.swift
git commit -m "feat: add GallerySheet for multi-image gallery creation"
```

---

### Task 6: Wire `GallerySheet` into `PostEditorView`

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift`

**Interfaces:**
- Consumes: `EditorView.onInsertGallery` (Task 4), `GallerySheet` (Task 5), `Notification.Name.insertGalleryData` (Task 4).
- Produces: clicking the toolbar's Gallery button opens `GallerySheet`; inserting posts `.insertGalleryData` with the exact userInfo shape `EditorCoordinator.handleInsertGallery` expects.

- [ ] **Step 1: Add the sheet-presentation state**

In `Sources/QuillKit/Views/Editor/PostEditorView.swift`, add after `@State private var showImagePicker = false` (currently line 20):

```swift
    @State private var showGallerySheet = false
```

- [ ] **Step 2: Wire the toolbar callback**

In the `EditorView(...)` call (currently lines 72-84), add after `onInsertImage: { showImagePicker = true },` (lines 82-84):

```swift
                        onInsertGallery: {
                            showGallerySheet = true
                        },
```

- [ ] **Step 3: Add the `.sheet` presentation**

Immediately after the existing `.sheet(isPresented: $showImagePicker) { ... }` block (currently lines 153-173), add:

```swift
                .sheet(isPresented: $showGallerySheet) {
                    GallerySheet(onInsert: { images, columns, cropped, linkTo in
                        let imagePayload: [[String: Any]] = images.map { media in
                            let url = media.mediaDetails?.sizes?["large"]?.sourceURL ?? media.sourceURL
                            return [
                                "id": media.id,
                                "url": url,
                                "alt": media.altText,
                            ]
                        }
                        let info: [String: Any] = [
                            "images": imagePayload,
                            "columns": columns,
                            "cropped": cropped,
                            "linkTo": linkTo,
                        ]
                        NotificationCenter.default.post(name: .insertGalleryData, object: nil, userInfo: info)
                        showGallerySheet = false
                    }, onCancel: {
                        showGallerySheet = false
                    })
                    .environmentObject(appState)
                    .frame(minWidth: 720, minHeight: 480)
                }
```

- [ ] **Step 4: Verify the build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 5: Manual smoke test**

Run: `./build.sh && open Quill.app`

In the app: open a local draft, click the new Gallery toolbar button, select 2-3 images, click Insert Gallery, confirm a thumbnail-grid card appears in the editor. Toggle code view (`</>`) and confirm the gallery HTML looks correct — `formatHTML` preserves comment nodes verbatim, so the `<!-- wp:gallery -->`/`<!-- wp:image -->` comments Task 1 adds should be visible directly in the code-view textarea, not just in the saved/fetched content.

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/Views/Editor/PostEditorView.swift
git commit -m "feat: wire GallerySheet into PostEditorView toolbar"
```

---

### Task 7: Swift decode sanity test

**Files:**
- Modify: `Tests/QuillTests/WPPostDecodingTests.swift`

**Interfaces:**
- Consumes: `WPPost`, `RenderedString.editorHTML` (existing).
- Produces: a regression test confirming a post containing real `wp:gallery`/`wp:image` block-comment HTML survives `editorHTML` unchanged — guards against a future change to `editorHTML`'s classic-content detection (`wpautop`) accidentally mangling gallery block comments the way it currently handles other `<!-- wp:`-prefixed content.

- [ ] **Step 1: Write the failing test**

Add to `Tests/QuillTests/WPPostDecodingTests.swift`, following the existing `private let fullJSON` / `@Test` pattern (e.g. near the shortcode-gallery test at line 252):

```swift
    @Test func blockGalleryContentSurvivesEditorHTML() throws {
        let json = """
        {"id":170,"title":{"rendered":"T"},
         "content":{"rendered":"<div>rendered</div>","raw":"<!-- wp:gallery {\\"ids\\":[145,146],\\"columns\\":3,\\"linkTo\\":\\"none\\"} -->\\n<figure class=\\"wp-block-gallery has-nested-images columns-3 is-cropped\\"><!-- wp:image {\\"id\\":145,\\"sizeSlug\\":\\"large\\",\\"linkDestination\\":\\"none\\"} -->\\n<figure class=\\"wp-block-image size-large\\"><img src=\\"http://localhost:8881/a.png\\" alt=\\"\\" class=\\"wp-image-145\\"/></figure>\\n<!-- /wp:image --></figure>\\n<!-- /wp:gallery -->"},
         "excerpt":{"rendered":""},"status":"publish",
         "date":"2024-01-01T00:00:00","modified":"2024-01-01T00:00:00",
         "slug":"t","link":"https://example.com/t"}
        """
        let post = try decode(json)
        let html = post.content.editorHTML
        #expect(html.contains("<!-- wp:gallery {\"ids\":[145,146],\"columns\":3,\"linkTo\":\"none\"} -->"))
        #expect(html.contains("wp-image-145"))
        #expect(html.contains("<!-- /wp:gallery -->"))
    }
```

- [ ] **Step 2: Run test to verify it currently passes (regression guard, not new behavior)**

Run: `swift test --filter WPPostDecodingTests`
Expected: PASS already — `editorHTML` doesn't touch raw content that already contains `<!-- wp:` comments (only classic/pre-Gutenberg content without them goes through `wpautop`). This test exists to catch a *future* regression, not to drive new implementation.

- [ ] **Step 3: Commit**

```bash
git add Tests/QuillTests/WPPostDecodingTests.swift
git commit -m "test: guard block-gallery content against editorHTML regressions"
```

---

### Task 8: Wire new test file into `test.sh`, update docs, final verification

**Files:**
- Modify: `test.sh`
- Modify: `docs/testing-plan.md` (add entries for the new gallery tests, following its existing per-test documentation format)
- Run: `claude-md-management:revise-claude-md` skill (per this project's own `CLAUDE.md` instruction: "After major changes: run the `claude-md-management:revise-claude-md` skill to keep this file current")

**Interfaces:**
- Consumes: all prior tasks.
- Produces: `./test.sh` runs the new gallery JS suite as part of the standard test command; `CLAUDE.md` and `docs/testing-plan.md` reflect the new feature for future sessions.

- [ ] **Step 1: Add the gallery test suite to `test.sh`**

Change `test.sh` from:

```bash
run "Swift tests"  swift test
run "JS editor tests"  node --test Scripts/test-editor.js
run "JS editor keyboard tests"  node --test Scripts/test-editor-keyboard.js
```

to:

```bash
run "Swift tests"  swift test
run "JS editor tests"  node --test Scripts/test-editor.js
run "JS editor keyboard tests"  node --test Scripts/test-editor-keyboard.js
run "JS gallery tests"  node --test Scripts/test-editor-gallery.js
```

- [ ] **Step 2: Run the full test suite**

Run: `./test.sh`
Expected: all suites pass, including the new "JS gallery tests" line.

- [ ] **Step 3: Update `docs/testing-plan.md`**

Add an entry documenting `Scripts/test-editor-gallery.js` (its 12 tests: insert/render with default settings, linkTo=media anchor wrapping, cropped=false; load/parseHTML recovery of images+columns+cropped+linkTo, load with linkTo=media, sourceHTML capture of captioned/non-default content; verbatim re-render of a loaded captioned gallery, reconstruction path for sheet-inserted galleries; code-view round-trip for both a sheet-inserted and a loaded captioned gallery; bridge-function insert, bridge-function empty-selection no-op) and the 7 new `toWordPressHTML — gallery` tests in `Scripts/test-editor.js` (comment wrapping, idempotency, no stray `wp-block-image` class, linkTo=media, cropped=false, dynamic sizeSlug, id-omission-when-unknown), following the file's existing per-suite documentation style.

- [ ] **Step 4: Full manual end-to-end verification**

Run: `./build.sh && open Quill.app`

1. Open a local draft (per project convention — never test on published posts/pages).
2. Click the Gallery toolbar button, select 3 images, set columns to 2, disable crop, set Link to "Full Image", click Insert Gallery.
3. Save the draft.
4. Fetch the saved raw content: `curl -s -u "admin:<app password>" "http://localhost:8881/wp-json/wp/v2/posts/{id}?context=edit&_fields=content" | python3 -c "import json,sys; print(json.load(sys.stdin)['content']['raw'])"` and confirm: `<!-- wp:gallery {...,"columns":2,"linkTo":"media","imageCrop":false} -->`, three `<!-- wp:image {...,"linkDestination":"media"} -->` blocks, each image wrapped in `<a href="...">`.
5. Open the same post in the local WordPress block editor (`http://localhost:8881/wp-admin`) and confirm it renders as a real, editable Gutenberg gallery block (not an "unrecognized block" / classic HTML fallback) — this is the concrete check for the two markup details (`imageCrop:false`, `linkDestination:"media"`) that weren't verified from an existing example in this plan, closing out the open item from the design spec.
6. Reopen the draft in Quill, confirm the gallery still renders as a card with the correct number of thumbnails (read-only recognition working on reload).
7. Verbatim round-trip check: in the WordPress block editor, add a caption to one image in an existing gallery (post 170, or a copy of it) and save. Open that post in Quill, confirm the gallery card still renders. Make an unrelated visual edit elsewhere in the post (e.g. type a sentence in a paragraph) and save. Re-fetch the post's raw content via the REST API and confirm the caption is still present in the saved `wp:image` block — this is the end-to-end check for the `sourceHTML` verbatim-preservation fix (Global Constraints), confirming captions survive an edit that would have silently dropped them under the reconstruction-only approach.

- [ ] **Step 5: Invoke the CLAUDE.md revision skill**

Invoke the `claude-md-management:revise-claude-md` skill to fold this feature's key decisions (gallery data model, insert-only v1 scope, the DOM-driven `linkTo`/`columns`/`cropped` recovery approach in `toWordPressHTML`) into `CLAUDE.md`, per this project's own stated convention.

- [ ] **Step 6: Final commit**

```bash
git add test.sh docs/testing-plan.md CLAUDE.md
git commit -m "docs: document gallery test coverage and update CLAUDE.md"
```
