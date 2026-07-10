# Image Link-to-Full-Size Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a single inserted image be turned into a link to its own full-resolution file, via a new toggle button in the existing per-image toolbar.

**Architecture:** Two new attrs (`linkTo`, `linkHref`) on the `ResizableImage` Tiptap node. `renderHTML` wraps the `<img>` in an `<a href>` when linked; `parseHTML` detects an existing `<a>` wrapper on load. A new toolbar button reuses the media-sizes data already fetched for the Thumb/Medium/Large/Full size buttons — no new Swift↔JS bridge call.

**Tech Stack:** Tiptap 2.x (bundled IIFE, `tiptap-bundle.js`), vanilla JS in `Sources/QuillKit/Resources/editor.html`, Node's built-in test runner (`node --test`) against a real `editor.html` loaded in jsdom.

## Global Constraints

- Scope is binary only: `linkTo` is `'none'` or `'media'` — no Attachment Page, no Custom URL (per spec, `docs/superpowers/specs/2026-07-10-image-link-to-full-design.md`).
- New node attrs, exact names: `linkTo` (enum `'none'` / `'media'`, default `'none'`), `linkHref` (string or `null`, default `null`).
- No changes to `editor-transforms.js` / `toWordPressHTML` — the spec confirms the existing `figure:not(...)` handling already tolerates an `<a>` between `<figure>` and `<img>`.
- No visual change to `ImageNodeView` (the live editing canvas) — a linked image looks identical to an unlinked one while editing. Only the toolbar button's `.active` state reflects link status.
- New toolbar button: id `#img-tb-link`, label "Link to Full Image", in its own new third row of `#image-toolbar` (below the W/H/size-buttons row and the Alt row).
- Button visibility: hidden by default, shown only once the `full` size arrives via the existing `setMediaSizes`/`_updateNamedSizeButtons` mechanism — identical condition to the Full size button's own visibility.
- The linked URL always comes from the existing `#image-toolbar [data-size="full"]` button's `_sizeData.url` (the same lookup the Reset button already does at `editor.html:2959`) — never a new fetch.
- After every code change: quit Quill, run `./build.sh`, reopen (`CLAUDE.md`). Test only on a local draft, never a published post/page.

---

### Task 1: `linkTo`/`linkHref` node attrs + render/parse round-trip

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html:1357-1367` (attrs), `:1371-1376` (renderHTML), `:1378-1411` (parseHTML getAttrs)
- Test: `Scripts/test-editor-keyboard.js` (new `describe('image link-to-full-size', ...)` block after line 338)

**Interfaces:**
- Produces: `ResizableImage` node attrs `linkTo: 'none' | 'media'` (default `'none'`) and `linkHref: string | null` (default `null`), readable via `node.attrs.linkTo` / `node.attrs.linkHref` anywhere a `ResizableImage` node instance is in scope (used by Task 2's toolbar wiring).
- Consumes: nothing new — builds on the existing `ResizableImage` extension already in `editor.html`.

- [x] **Step 1: Write the failing tests**

Open `Scripts/test-editor-keyboard.js`. After the `describe('class preservation through schema round-trip', ...)` block closes (ends at line 338 with `})`), add:

```js

describe('image link-to-full-size', () => {
  test('image wrapped in <a> parses to linkTo media with linkHref, and round-trips', () => {
    const html = '<figure class="wp-block-image"><a href="https://example.com/full.jpg"><img src="https://example.com/thumb.jpg"></a><figcaption></figcaption></figure>'
    editor.commands.setContent(html, false)
    const node = editor.state.doc.firstChild
    assert.equal(node.attrs.linkTo, 'media')
    assert.equal(node.attrs.linkHref, 'https://example.com/full.jpg')
    const out = editor.getHTML()
    assert.match(out, /<a href="https:\/\/example\.com\/full\.jpg"><img[^>]*><\/a>/)
  })

  test('image without a link wrapper defaults to linkTo none and omits <a> from output', () => {
    const html = '<figure class="wp-block-image"><img src="https://example.com/thumb.jpg"><figcaption></figcaption></figure>'
    editor.commands.setContent(html, false)
    const node = editor.state.doc.firstChild
    assert.equal(node.attrs.linkTo, 'none')
    assert.equal(node.attrs.linkHref, null)
    const out = editor.getHTML()
    assert.doesNotMatch(out, /<a /)
  })

  test('linked image preserves alignment, custom class, and mediaId alongside the link', () => {
    const html = '<figure class="wp-block-image alignleft my-figure-class"><a href="https://example.com/full.jpg"><img src="https://example.com/thumb.jpg" class="wp-image-42"></a><figcaption>cap</figcaption></figure>'
    editor.commands.setContent(html, false)
    const node = editor.state.doc.firstChild
    assert.equal(node.attrs.linkTo, 'media')
    assert.equal(node.attrs.linkHref, 'https://example.com/full.jpg')
    assert.equal(node.attrs.alignment, 'left')
    assert.equal(node.attrs.figureClass, 'my-figure-class')
    assert.equal(node.attrs.mediaId, 42)
    const out = editor.getHTML()
    assert.match(out, /alignleft/)
    assert.match(out, /my-figure-class/)
    assert.match(out, /wp-image-42/)
    assert.match(out, /<a href="https:\/\/example\.com\/full\.jpg">/)
  })

  test('toggling linkTo to media via setNodeMarkup produces the <a> wrapper on save', () => {
    editor.commands.setContent('<figure class="wp-block-image"><img src="https://example.com/thumb.jpg"><figcaption></figcaption></figure>', false)
    const pos = posOfFirst('image')
    const node = editor.state.doc.nodeAt(pos)
    const { state, dispatch } = editor.view
    dispatch(state.tr.setNodeMarkup(pos, null, { ...node.attrs, linkTo: 'media', linkHref: 'https://example.com/full.jpg' }))
    const out = editor.getHTML()
    assert.match(out, /<a href="https:\/\/example\.com\/full\.jpg">/)
  })
})
```

- [x] **Step 2: Run tests to verify they fail**

Run: `node --test Scripts/test-editor-keyboard.js`
Expected: the 4 new tests FAIL — `node.attrs.linkTo` is `undefined`, not `'media'`/`'none'`, and `getHTML()` never contains `<a href=...>` around the image.

- [x] **Step 3: Add the two new attrs**

In `editor.html`, find this block inside `ResizableImage.extend({ addAttributes() { return { ... `:

```js
          figureClass: {
            default: null,
            rendered: false,
            parseHTML: () => null,
          },
          figureId: {
            default: null,
            rendered: false,
            parseHTML: () => null,
          },
        }
      },
```

Replace with:

```js
          figureClass: {
            default: null,
            rendered: false,
            parseHTML: () => null,
          },
          figureId: {
            default: null,
            rendered: false,
            parseHTML: () => null,
          },
          linkTo: {
            default: 'none',
            rendered: false,
            parseHTML: () => 'none',
          },
          linkHref: {
            default: null,
            rendered: false,
            parseHTML: () => null,
          },
        }
      },
```

(`rendered: false` keeps these off the `<img>` tag's own attributes — same treatment as `figureClass`/`figureId`. The dead-stub `parseHTML` here only matters for the bare `{ tag: 'img[src]' }` fallback rule at the bottom of `parseHTML()`, which has no custom `getAttrs`; a bare, non-figure-wrapped linked image is out of scope per the spec, so it always parses as unlinked, consistent with how that same fallback already gives bare images a null `figureClass`/`figureId`.)

- [x] **Step 4: Wrap the `<img>` in an `<a>` when linked**

Find:

```js
      renderHTML({ node, HTMLAttributes }) {
        const figureAttrs = {}
        if (node.attrs.figureClass) figureAttrs.class = node.attrs.figureClass
        if (node.attrs.figureId) figureAttrs.id = node.attrs.figureId
        return ['figure', figureAttrs, ['img', HTMLAttributes], ['figcaption', 0]]
      },
```

Replace with:

```js
      renderHTML({ node, HTMLAttributes }) {
        const figureAttrs = {}
        if (node.attrs.figureClass) figureAttrs.class = node.attrs.figureClass
        if (node.attrs.figureId) figureAttrs.id = node.attrs.figureId
        const imgSpec = ['img', HTMLAttributes]
        const imageContent = (node.attrs.linkTo === 'media' && node.attrs.linkHref)
          ? ['a', { href: node.attrs.linkHref }, imgSpec]
          : imgSpec
        return ['figure', figureAttrs, imageContent, ['figcaption', 0]]
      },
```

- [x] **Step 5: Detect an existing `<a>` wrapper on parse**

Find (inside `parseHTML() { return [ { tag: 'figure.wp-block-image', getAttrs: el => { ... } ...`):

```js
            getAttrs: el => {
              const img = el.querySelector('img')
              if (!img) return false
              const dataId = img.getAttribute('data-media-id')
              const imgCls = img.getAttribute('class') || ''
              const clsMatch = imgCls.match(/wp-image-(\d+)/)
              const _knownImgCls = /^(alignleft|alignright|aligncenter|wp-image-\d+)$/
              const customImgCls = imgCls.split(/\s+/).filter(c => c && !_knownImgCls.test(c)).join(' ')
              const figCls = el.getAttribute('class') || ''
              const _knownFigCls = /^(wp-block-image|alignleft|alignright|aligncenter)$/
              const customFigCls = figCls.split(/\s+/).filter(c => c && !_knownFigCls.test(c)).join(' ')
              return {
                src:       img.getAttribute('src'),
                alt:       img.getAttribute('alt') ?? null,
                title:     img.getAttribute('title') ?? null,
                width:     parseInt(img.getAttribute('width'), 10) || null,
                height:    parseInt(img.getAttribute('height'), 10) || null,
                mediaId:   dataId ? parseInt(dataId, 10)
                                  : (clsMatch ? parseInt(clsMatch[1], 10) : null),
                alignment: extractAlignment(figCls),
                imgClass:    customImgCls || null,
                figureClass: customFigCls || null,
                figureId:  el.getAttribute('id') || null,
              }
            },
```

Replace with:

```js
            getAttrs: el => {
              const img = el.querySelector('img')
              if (!img) return false
              const dataId = img.getAttribute('data-media-id')
              const imgCls = img.getAttribute('class') || ''
              const clsMatch = imgCls.match(/wp-image-(\d+)/)
              const _knownImgCls = /^(alignleft|alignright|aligncenter|wp-image-\d+)$/
              const customImgCls = imgCls.split(/\s+/).filter(c => c && !_knownImgCls.test(c)).join(' ')
              const figCls = el.getAttribute('class') || ''
              const _knownFigCls = /^(wp-block-image|alignleft|alignright|aligncenter)$/
              const customFigCls = figCls.split(/\s+/).filter(c => c && !_knownFigCls.test(c)).join(' ')
              const linkEl = img.parentElement
              const linkedToMedia = linkEl && linkEl.tagName === 'A'
              return {
                src:       img.getAttribute('src'),
                alt:       img.getAttribute('alt') ?? null,
                title:     img.getAttribute('title') ?? null,
                width:     parseInt(img.getAttribute('width'), 10) || null,
                height:    parseInt(img.getAttribute('height'), 10) || null,
                mediaId:   dataId ? parseInt(dataId, 10)
                                  : (clsMatch ? parseInt(clsMatch[1], 10) : null),
                alignment: extractAlignment(figCls),
                imgClass:    customImgCls || null,
                figureClass: customFigCls || null,
                figureId:  el.getAttribute('id') || null,
                linkTo:    linkedToMedia ? 'media' : 'none',
                linkHref:  linkedToMedia ? linkEl.getAttribute('href') : null,
              }
            },
```

- [x] **Step 6: Run tests to verify they pass**

Run: `node --test Scripts/test-editor-keyboard.js`
Expected: all tests PASS, including the 4 new ones.

- [x] **Step 7: Run the full JS suite to check for regressions**

Run: `node --test Scripts/test-editor.js && node --test Scripts/test-editor-keyboard.js && node --test Scripts/test-editor-gallery.js`
Expected: all PASS (this task didn't touch `editor-transforms.js` or the gallery node, but confirms nothing else broke).

- [x] **Step 8: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Scripts/test-editor-keyboard.js
git commit -m "feat: add linkTo/linkHref attrs to ResizableImage for link-to-full-size"
```

---

### Task 2: Toolbar button — UI, visibility, and click wiring

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html:957-975` (toolbar HTML), `:608-609` (toolbar CSS), `:1115-1130` (`ImageNodeView.update()`), `:1297-1308` (`_updateNamedSizeButtons`), `:2990-3004` (toolbar click-handler IIFE)

**Interfaces:**
- Consumes: `node.attrs.linkTo` / `node.attrs.linkHref` (Task 1), the existing `#image-toolbar [data-size="full"]` button's `_sizeData` (set by `_updateNamedSizeButtons`, existing code), the existing `nv.getPos()` / `nv.editor.view` / `setNodeMarkup` commit pattern used by the Reset and size buttons.
- Produces: nothing consumed by a later task — this is the last task in the plan.

- [x] **Step 1: Add the third toolbar row**

Find in `editor.html`:

```html
  <div id="image-toolbar">
    <div class="img-tb-row">
      <span class="img-tb-label">W</span>
      <input type="number" id="img-tb-w" min="50" placeholder="—">
      <span class="img-tb-label">H</span>
      <input type="number" id="img-tb-h" min="50" placeholder="—">
      <span class="img-tb-sep"></span>
      <button data-size="thumbnail" style="display:none">Thumb</button>
      <button data-size="medium"    style="display:none">Medium</button>
      <button data-size="large"     style="display:none">Large</button>
      <button data-size="full"      style="display:none">Full</button>
      <span class="img-tb-sep"></span>
      <button id="img-tb-reset">Reset</button>
    </div>
    <div class="img-tb-row">
      <span class="img-tb-label">Alt</span>
      <input type="text" id="img-tb-alt">
    </div>
  </div>
```

Replace with:

```html
  <div id="image-toolbar">
    <div class="img-tb-row">
      <span class="img-tb-label">W</span>
      <input type="number" id="img-tb-w" min="50" placeholder="—">
      <span class="img-tb-label">H</span>
      <input type="number" id="img-tb-h" min="50" placeholder="—">
      <span class="img-tb-sep"></span>
      <button data-size="thumbnail" style="display:none">Thumb</button>
      <button data-size="medium"    style="display:none">Medium</button>
      <button data-size="large"     style="display:none">Large</button>
      <button data-size="full"      style="display:none">Full</button>
      <span class="img-tb-sep"></span>
      <button id="img-tb-reset">Reset</button>
    </div>
    <div class="img-tb-row">
      <span class="img-tb-label">Alt</span>
      <input type="text" id="img-tb-alt">
    </div>
    <div class="img-tb-row">
      <button id="img-tb-link" style="display:none">Link to Full Image</button>
    </div>
  </div>
```

- [x] **Step 2: Add `.active` styling for image-toolbar buttons**

Find:

```css
    #image-toolbar button:disabled { opacity: 0.4; cursor: default; }
    #image-toolbar .img-tb-sep { width: 1px; height: 14px; background: #ddd; margin: 0 2px; }
```

Replace with:

```css
    #image-toolbar button:disabled { opacity: 0.4; cursor: default; }
    #image-toolbar button.active {
      background: #ececef;
      color: #3f434d;
      border-color: transparent;
    }
    body.dark #image-toolbar button.active {
      background: rgba(255,255,255,0.12);
      color: #f4f4f5;
    }
    #image-toolbar .img-tb-sep { width: 1px; height: 14px; background: #ddd; margin: 0 2px; }
```

- [x] **Step 3: Sync the button's visibility and active state whenever sizes update**

Find:

```js
    function _updateNamedSizeButtons(sizes) {
      document.querySelectorAll('#image-toolbar [data-size]').forEach(btn => {
        if (!sizes || !sizes[btn.dataset.size]) {
          btn.style.display = 'none'
          btn._sizeData = null
        } else {
          btn.style.display = ''
          btn.disabled = false
          btn._sizeData = sizes[btn.dataset.size]
        }
      })
    }
```

Replace with:

```js
    function _updateNamedSizeButtons(sizes) {
      document.querySelectorAll('#image-toolbar [data-size]').forEach(btn => {
        if (!sizes || !sizes[btn.dataset.size]) {
          btn.style.display = 'none'
          btn._sizeData = null
        } else {
          btn.style.display = ''
          btn.disabled = false
          btn._sizeData = sizes[btn.dataset.size]
        }
      })
      const linkBtn = document.getElementById('img-tb-link')
      if (linkBtn) {
        const fullBtn = document.querySelector('#image-toolbar [data-size="full"]')
        linkBtn.style.display = fullBtn?._sizeData ? '' : 'none'
        const tb = document.getElementById('image-toolbar')
        linkBtn.classList.toggle('active', tb?._activeNodeView?.node.attrs.linkTo === 'media')
      }
    }
```

(This function already runs at the right two times — `_showImageToolbar` calls it with `null` immediately on selection, and `window.setMediaSizes` calls it again once the real sizes arrive — so no new call sites are needed. Because `_showImageToolbar` sets `tb._activeNodeView = nv` *before* calling `_updateNamedSizeButtons(null)`, the active-state check above already reads the newly-selected image, not the previous one.)

- [x] **Step 4: Sync the button's active state on any attrs update**

Find in `ImageNodeView`:

```js
      update(node) {
        if (node.type.name !== 'image') return false
        this.node = node
        this._applyAttrs(node.attrs)
        // Toggle placeholder class: present when caption is empty
        const hasCaption = node.content.size > 0
        this.figcaption.classList.toggle('caption-placeholder', !hasCaption)
        // Sync toolbar inputs if this image is currently selected
        const tb = document.getElementById('image-toolbar')
        if (tb?._activeNodeView === this) {
          document.getElementById('img-tb-w').value   = node.attrs.width  ?? ''
          document.getElementById('img-tb-h').value   = node.attrs.height ?? ''
          document.getElementById('img-tb-alt').value = node.attrs.alt    ?? ''
        }
        return true
      }
```

Replace with:

```js
      update(node) {
        if (node.type.name !== 'image') return false
        this.node = node
        this._applyAttrs(node.attrs)
        // Toggle placeholder class: present when caption is empty
        const hasCaption = node.content.size > 0
        this.figcaption.classList.toggle('caption-placeholder', !hasCaption)
        // Sync toolbar inputs if this image is currently selected
        const tb = document.getElementById('image-toolbar')
        if (tb?._activeNodeView === this) {
          document.getElementById('img-tb-w').value   = node.attrs.width  ?? ''
          document.getElementById('img-tb-h').value   = node.attrs.height ?? ''
          document.getElementById('img-tb-alt').value = node.attrs.alt    ?? ''
          const linkBtn = document.getElementById('img-tb-link')
          if (linkBtn) linkBtn.classList.toggle('active', node.attrs.linkTo === 'media')
        }
        return true
      }
```

- [x] **Step 5: Wire the click handler**

Find, inside the `;(function () { ... })()` image-toolbar-handlers block:

```js
      document.querySelectorAll('#image-toolbar [data-size]').forEach(btn => {
        btn.addEventListener('click', () => {
          const tb = document.getElementById('image-toolbar')
          const nv = tb?._activeNodeView
          if (!nv || !btn._sizeData) return
          const { url, width, height } = btn._sizeData
          const pos = nv.getPos()
          if (typeof pos !== 'number') return
          const { state, dispatch } = nv.editor.view
          dispatch(state.tr.setNodeMarkup(pos, null, { ...nv.node.attrs, src: url, width, height }))
          document.getElementById('img-tb-w').value = width
          document.getElementById('img-tb-h').value = height
        })
      })
    })()
```

Replace with:

```js
      document.querySelectorAll('#image-toolbar [data-size]').forEach(btn => {
        btn.addEventListener('click', () => {
          const tb = document.getElementById('image-toolbar')
          const nv = tb?._activeNodeView
          if (!nv || !btn._sizeData) return
          const { url, width, height } = btn._sizeData
          const pos = nv.getPos()
          if (typeof pos !== 'number') return
          const { state, dispatch } = nv.editor.view
          dispatch(state.tr.setNodeMarkup(pos, null, { ...nv.node.attrs, src: url, width, height }))
          document.getElementById('img-tb-w').value = width
          document.getElementById('img-tb-h').value = height
        })
      })

      document.getElementById('img-tb-link').addEventListener('click', () => {
        const tb = document.getElementById('image-toolbar')
        const nv = tb?._activeNodeView
        if (!nv) return
        const pos = nv.getPos()
        if (typeof pos !== 'number') return
        const turningOn = nv.node.attrs.linkTo !== 'media'
        const newAttrs = { ...nv.node.attrs, linkTo: turningOn ? 'media' : 'none' }
        if (turningOn) {
          const fullBtn = document.querySelector('#image-toolbar [data-size="full"]')
          if (fullBtn?._sizeData) newAttrs.linkHref = fullBtn._sizeData.url
        }
        const { state, dispatch } = nv.editor.view
        dispatch(state.tr.setNodeMarkup(pos, null, newAttrs))
      })
    })()
```

- [x] **Step 6: Rebuild and manually verify** — rebuilt successfully; manual in-app checklist confirmed by user.

```bash
./build.sh
open Quill.app
```

In the running app:
1. Create a new local draft (per project convention, never test on a published post).
2. Insert an image from the WordPress media library (so it has a `mediaId`). Select it — confirm the "Link to Full Image" button is **not** visible immediately, then appears shortly after (once `setMediaSizes` delivers the `full` size).
3. Click "Link to Full Image" — confirm it visually activates (matches the `.active` style used elsewhere, e.g. the `</>` code-view button).
4. Toggle the `</>` code view button and confirm the saved HTML shows `<figure class="wp-block-image">...<a href="...full-size-url..."><img ...></a>...`.
5. Click "Link to Full Image" again to turn it off — confirm the code view no longer shows an `<a>` wrapper.
6. Drag-and-drop or paste an image with no media-library backing (no `mediaId`) — confirm the "Link to Full Image" button never appears for it, same as the size buttons.
7. Quit and reopen the draft (or switch away and back) — confirm a previously-linked image still shows the button in its active state when reselected.

- [x] **Step 7: Run the full test suite**

Run: `./test.sh`
Expected: all Swift and JS tests pass (no Swift changes in this plan, so this is primarily a regression check on the JS suite).

- [x] **Step 8: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html
git commit -m "feat: add Link to Full Image toggle to the image toolbar"
```

---

## Self-Review Notes

- **Spec coverage:** Data model (Task 1, Step 3) ✅. Parse/render round-trip (Task 1, Steps 4-5) ✅. UI placement/visibility/click behavior (Task 2, Steps 1, 3, 5) ✅. No `toWordPressHTML` changes (confirmed, no task touches `editor-transforms.js`) ✅. No `ImageNodeView` canvas visual change (confirmed — `update()` change in Task 2 Step 4 only syncs the *toolbar* button, not the canvas image itself) ✅. Testing section (Task 1 Steps 1-2, 6-7; Task 2 Step 6 manual checklist covers the spec's manual test) ✅.
- **Placeholder scan:** none found — every step has literal, complete code.
- **Type/naming consistency:** `linkTo`/`linkHref` attr names, `#img-tb-link` element id, and the `_updateNamedSizeButtons`/`update()`/click-handler code all reference the same names throughout both tasks.
