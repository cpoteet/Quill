# Image Captions and Alt Text Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add inline image captions (always-visible figcaption, editable in place) and alt text editing (image toolbar + media detail panel, pre-populated from WordPress) to the post editor.

**Architecture:** `ResizableImage` gains `content: 'inline*'` and a new `renderHTML` that outputs `<figure><img ...><figcaption slot /></figure>`. The `ImageNodeView` exposes `contentDOM` pointing at the figcaption so ProseMirror manages caption text inline. `toWordPressHTML()` shifts from wrapping bare `<img>` to annotating existing `<figure>` elements with Gutenberg classes. Alt text flows through the `insertMediaURL` notification from media picker / drag-drop to `EditorCoordinator` to a JS function call.

**Tech Stack:** Swift 6 / SwiftUI / Tiptap 2.x (IIFE bundle in WKWebView), Swift Testing framework, Node + jsdom for JS tests.

---

## File map

| File | What changes |
|---|---|
| `Sources/QuillKit/Resources/editor-transforms.js` | Replace bare-img wrapping with figure-annotation; add figcaption handling |
| `Scripts/test-editor.js` | Update image test fixtures; add caption tests |
| `Sources/QuillKit/Resources/editor.html` | `ResizableImage` schema/renderHTML/parseHTML; `ImageNodeView` contentDOM + ignoreMutation; figcaption CSS; toolbar second row + alt handler |
| `Sources/QuillKit/API/Models/WPMedia.swift` | Add `altText: String` |
| `Tests/QuillTests/WPMediaDecodingTests.swift` | Test `alt_text` decoding |
| `Sources/QuillKit/API/WordPressClient.swift` | Add `updateMediaAltText(id:altText:)` |
| `Tests/QuillTests/WordPressClientTests.swift` | Test PATCH request + response decoding |
| `Sources/QuillKit/Views/Editor/PostEditorView.swift` | Pass `alt` in `.insertMediaURL` userInfo (picker + drag-drop) |
| `Sources/QuillKit/Views/Editor/EditorCoordinator.swift` | Read `alt` from notification; add to `insertImage` |
| `Sources/QuillKit/Views/Media/MediaDetailView.swift` | Editable alt text field + `onSaveAltText` callback |
| `Sources/QuillKit/Views/ContentView.swift` | Wire `onSaveAltText` callback |

---

## Task 1: Update JS tests for figure-based image format

`toWordPressHTML` currently expects bare `<img>` input. After Task 2 `renderHTML` will always produce `<figure><img ...><figcaption></figcaption></figure>`. Write failing tests for the new behaviour now so Task 2 makes them pass.

**Files:**
- Modify: `Scripts/test-editor.js`

> ⚠️ **JS file edit warning:** The Edit tool can corrupt ASCII quote delimiters to curly quotes in this file. If you see `SyntaxError: Invalid or unexpected token` after editing, fix with Python byte replacement — do NOT use the Edit tool again to fix it.

- [ ] **Step 1: Replace the `toWordPressHTML — images` describe block**

Find the existing block (lines ~168–209) and replace the entire `describe('toWordPressHTML — images', ...)` block with the version below. **Use the Edit tool with the full old block as `old_string`.**

Old block to remove (exact text):
```
describe('toWordPressHTML — images', () => {
  test('data-media-id produces wp-image-{id} class on img', () => {
    const out = wp('<img src="a.jpg" data-media-id="42">')
    assert.match(out, /wp-image-42/)
  })

  test('img.alignleft is wrapped in figure.wp-block-image.alignleft', () => {
    const out = wp('<img src="a.jpg" class="alignleft">')
    assert.match(out, /class="wp-block-image alignleft"/)
    assert.match(out, /<figure/)
  })

  test('img.alignright is wrapped in figure.wp-block-image.alignright', () => {
    const out = wp('<img src="a.jpg" class="alignright">')
    assert.match(out, /class="wp-block-image alignright"/)
  })

  test('img.aligncenter is wrapped in figure.wp-block-image.aligncenter', () => {
    const out = wp('<img src="a.jpg" class="aligncenter">')
    assert.match(out, /class="wp-block-image aligncenter"/)
  })

  test('align class is removed from img after wrapping in figure', () => {
    const out = wp('<img src="a.jpg" class="alignleft">')
    // The <img> inside the figure should not still have the align class
    const dom = new JSDOM(out).window.document
    const img = dom.querySelector('img')
    assert.ok(!img.classList.contains('alignleft'), 'img still has alignleft after wrapping')
  })

  test('image with both alignment and media-id gets figure wrapper and wp-image class', () => {
    const out = wp('<img src="a.jpg" class="alignleft" data-media-id="7">')
    assert.match(out, /wp-block-image alignleft/)
    assert.match(out, /wp-image-7/)
  })

  test('image with no alignment and no media-id is untouched (no figure wrap)', () => {
    const out = wp('<img src="a.jpg">')
    assert.doesNotMatch(out, /<figure/)
    assert.doesNotMatch(out, /wp-block-image/)
  })
})
```

New block to insert:
```
describe('toWordPressHTML — images', () => {
  // renderHTML now always produces <figure><img ...><figcaption></figcaption></figure>

  test('figure with plain img gets wp-block-image class', () => {
    const out = wp('<figure><img src="a.jpg"><figcaption></figcaption></figure>')
    assert.match(out, /class="wp-block-image"/)
  })

  test('data-media-id produces wp-image-{id} class on img inside figure', () => {
    const out = wp('<figure><img src="a.jpg" data-media-id="42"><figcaption></figcaption></figure>')
    assert.match(out, /wp-image-42/)
  })

  test('alignleft on img is moved to figure class', () => {
    const out = wp('<figure><img src="a.jpg" class="alignleft"><figcaption></figcaption></figure>')
    const dom = new JSDOM(out).window.document
    const fig = dom.querySelector('figure')
    const img = dom.querySelector('img')
    assert.ok(fig.classList.contains('wp-block-image'), 'figure missing wp-block-image')
    assert.ok(fig.classList.contains('alignleft'), 'figure missing alignleft')
    assert.ok(!img.classList.contains('alignleft'), 'img should not have alignleft')
  })

  test('alignright on img is moved to figure class', () => {
    const out = wp('<figure><img src="a.jpg" class="alignright"><figcaption></figcaption></figure>')
    assert.match(out, /class="wp-block-image alignright"/)
  })

  test('aligncenter on img is moved to figure class', () => {
    const out = wp('<figure><img src="a.jpg" class="aligncenter"><figcaption></figcaption></figure>')
    assert.match(out, /class="wp-block-image aligncenter"/)
  })

  test('both alignment and media-id: figure gets align class, img gets wp-image class', () => {
    const out = wp('<figure><img src="a.jpg" class="alignleft" data-media-id="7"><figcaption></figcaption></figure>')
    assert.match(out, /wp-block-image alignleft/)
    assert.match(out, /wp-image-7/)
  })

  test('empty figcaption is removed from output', () => {
    const out = wp('<figure><img src="a.jpg"><figcaption></figcaption></figure>')
    assert.doesNotMatch(out, /<figcaption/)
  })

  test('non-empty figcaption gets wp-element-caption class', () => {
    const out = wp('<figure><img src="a.jpg"><figcaption>A caption</figcaption></figure>')
    assert.match(out, /class="wp-element-caption"/)
    assert.match(out, /A caption/)
  })

  test('whitespace-only figcaption is removed', () => {
    const out = wp('<figure><img src="a.jpg"><figcaption>   </figcaption></figure>')
    assert.doesNotMatch(out, /<figcaption/)
  })

  test('table figure is not treated as image figure', () => {
    const out = wp('<figure class="wp-block-table"><table><tbody><tr><td>x</td></tr></tbody></table></figure>')
    assert.doesNotMatch(out, /wp-block-image/)
  })
})
```

- [ ] **Step 2: Run the JS tests and verify the new image tests fail**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && node --test Scripts/test-editor.js 2>&1 | head -60
```

Expected: The new image tests fail (function still has old logic). Other tests pass.

- [ ] **Step 3: Commit the failing tests**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add Scripts/test-editor.js && git commit -m "test: add failing JS tests for figure-based image toWordPressHTML"
```

---

## Task 2: Update `toWordPressHTML` in `editor-transforms.js`

Replace the aligned-image wrapping section with figure-annotation logic.

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js`

> ⚠️ **JS file edit warning:** Same curly-quote risk. Use Python byte replacement if syntax errors appear after editing.

- [ ] **Step 1: Replace the image section in `toWordPressHTML`**

Find and replace the `// Re-emit wp-image-{id}` and `// Aligned images → Gutenberg figure wrapper` sections. Use Edit tool with this exact `old_string`:

```
  // Re-emit wp-image-{id} class so WordPress can associate images with media library entries
  div.querySelectorAll('img[data-media-id]').forEach(img => {
    const id = img.getAttribute('data-media-id')
    if (id) img.classList.add(`wp-image-${id}`)
  })

  // Aligned images → Gutenberg figure wrapper
  div.querySelectorAll('img.alignleft, img.alignright, img.aligncenter').forEach(img => {
    const align = ['alignleft', 'alignright', 'aligncenter']
      .find(c => img.classList.contains(c))
    if (!align) return
    const figure = doc.createElement('figure')
    figure.className = `wp-block-image ${align}`
    img.classList.remove('alignleft', 'alignright', 'aligncenter')
    img.parentNode.insertBefore(figure, img)
    figure.appendChild(img)
  })
```

Replace with:

```
  // Re-emit wp-image-{id} class so WordPress can associate images with media library entries
  div.querySelectorAll('img[data-media-id]').forEach(img => {
    const id = img.getAttribute('data-media-id')
    if (id) img.classList.add(`wp-image-${id}`)
  })

  // Image figures: renderHTML produces <figure><img ...><figcaption/></figure>.
  // Add wp-block-image class, move alignment from img to figure, handle caption.
  div.querySelectorAll('figure:not(.wp-block-table)').forEach(figure => {
    const img = figure.querySelector('img')
    if (!img) return
    const align = ['alignleft', 'alignright', 'aligncenter']
      .find(c => img.classList.contains(c))
    if (align) {
      figure.classList.add('wp-block-image', align)
      img.classList.remove(align)
    } else {
      figure.classList.add('wp-block-image')
    }
    const caption = figure.querySelector('figcaption')
    if (caption) {
      if (caption.textContent.trim()) {
        caption.classList.add('wp-element-caption')
      } else {
        caption.remove()
      }
    }
  })
```

- [ ] **Step 2: Run JS tests and verify all pass**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && node --test Scripts/test-editor.js 2>&1
```

Expected: All 37+ tests pass (the new image tests now pass, no regressions).

- [ ] **Step 3: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add Sources/QuillKit/Resources/editor-transforms.js && git commit -m "feat: update toWordPressHTML to handle figure-based images and captions"
```

---

## Task 3: Update `ResizableImage` — schema, `renderHTML`, `parseHTML`, `ImageNodeView`

This is the core Tiptap change. The image node gains `content: 'inline*'`, a `renderHTML` that outputs a figure with a content slot, and a NodeView that exposes the figcaption as `contentDOM`.

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`

- [ ] **Step 1: Add `content` and `renderHTML` to `ResizableImage`**

Inside the `ResizableImage` extension (around line 599), after the closing `}` of `addAttributes()`, find and replace the `parseHTML()` method start. First, add `content` and `renderHTML` by replacing this exact string:

Old:
```
      parseHTML() {
        return [
          {
            tag: 'figure.wp-block-image',
```

New:
```
      content: 'inline*',

      renderHTML({ HTMLAttributes }) {
        return ['figure', {}, ['img', HTMLAttributes], ['figcaption', 0]]
      },

      parseHTML() {
        return [
          {
            tag: 'figure.wp-block-image',
```

- [ ] **Step 2: Add `contentElement` to the `figure.wp-block-image` parse rule**

Find and replace inside the `figure.wp-block-image` parse rule:

Old:
```
                alignment: extractAlignment(el.getAttribute('class') || ''),
              }
            },
          },
          { tag: 'img[src]' },
```

New:
```
                alignment: extractAlignment(el.getAttribute('class') || ''),
              }
            },
            contentElement: 'figcaption',
          },
          { tag: 'img[src]' },
```

- [ ] **Step 3: Update `ImageNodeView` constructor to create and expose figcaption via contentDOM**

The constructor currently ends with `this.dom = this.wrapper`. Replace the entire `ImageNodeView` constructor:

Old:
```
      constructor(node, editor, getPos) {
        this.node    = node
        this.editor  = editor
        this.getPos  = getPos

        this.wrapper = document.createElement('div')
        this.wrapper.className = 'image-wrapper'

        this.img = document.createElement('img')
        this._applyAttrs(node.attrs)
        this.wrapper.appendChild(this.img)

        for (const pos of ['nw','n','ne','e','se','s','sw','w']) {
          const h = document.createElement('div')
          h.className = `resize-handle ${pos}`
          h.addEventListener('mousedown', e => this._onHandleMousedown(e, pos))
          this.wrapper.appendChild(h)
        }

        this.dom = this.wrapper
      }
```

New:
```
      constructor(node, editor, getPos) {
        this.node    = node
        this.editor  = editor
        this.getPos  = getPos

        this.wrapper = document.createElement('div')
        this.wrapper.className = 'image-wrapper'

        this.img = document.createElement('img')
        this._applyAttrs(node.attrs)
        this.wrapper.appendChild(this.img)

        for (const pos of ['nw','n','ne','e','se','s','sw','w']) {
          const h = document.createElement('div')
          h.className = `resize-handle ${pos}`
          h.addEventListener('mousedown', e => this._onHandleMousedown(e, pos))
          this.wrapper.appendChild(h)
        }

        this.figcaption = document.createElement('figcaption')
        this.figcaption.className = 'wp-caption-placeholder'
        this.wrapper.appendChild(this.figcaption)

        this.dom        = this.wrapper
        this.contentDOM = this.figcaption
      }
```

- [ ] **Step 4: Update `ignoreMutation` to allow ProseMirror to track caption edits**

Old:
```
      ignoreMutation() { return true }
```

New:
```
      ignoreMutation(mutation) {
        // Allow ProseMirror to track text changes inside the figcaption (contentDOM)
        if (this.figcaption.contains(mutation.target)) return false
        return true
      }
```

- [ ] **Step 5: Update `update()` to toggle the placeholder class when caption content changes**

Inside the `update(node)` method, add a placeholder-class toggle after `this._applyAttrs(node.attrs)`:

Old:
```
      update(node) {
        if (node.type.name !== 'image') return false
        this.node = node
        this._applyAttrs(node.attrs)
        // Sync toolbar inputs if this image is currently selected
```

New:
```
      update(node) {
        if (node.type.name !== 'image') return false
        this.node = node
        this._applyAttrs(node.attrs)
        // Toggle placeholder class: present when caption is empty
        const hasCaption = node.content && node.content.size > 0
        this.figcaption.classList.toggle('wp-caption-placeholder', !hasCaption)
        // Sync toolbar inputs if this image is currently selected
```

- [ ] **Step 6: Add figcaption CSS**

Find the `/* ── Image toolbar ──` comment block (around line 198) and add the following CSS block immediately before it:

Old:
```
    /* ── Image toolbar ──────────────────────────────── */
```

New:
```
    /* ── Image caption ──────────────────────────────── */
    .image-wrapper figcaption {
      display: block;
      text-align: center;
      font-style: italic;
      font-size: 0.9em;
      color: #555;
      padding: 4px 8px 2px;
      outline: none;
    }
    body.dark .image-wrapper figcaption { color: #aaa; }
    .image-wrapper figcaption.wp-caption-placeholder:empty::before {
      content: "Add a caption\2026";
      color: #bbb;
      pointer-events: none;
    }
    body.dark .image-wrapper figcaption.wp-caption-placeholder:empty::before { color: #666; }

    /* ── Image toolbar ──────────────────────────────── */
```

- [ ] **Step 7: Build and smoke-test manually**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh 2>&1 | tail -5
```

Open `Quill.app`, load a post with images, verify:
- Images still display correctly
- An always-visible "Add a caption…" placeholder appears below each image
- Clicking the placeholder lets you type a caption inline
- Existing captions from WordPress posts load correctly

- [ ] **Step 8: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add Sources/QuillKit/Resources/editor.html && git commit -m "feat: add inline caption support to ResizableImage (contentDOM figcaption)"
```

---

## Task 4: Add alt text row to the image toolbar

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`

- [ ] **Step 1: Change `#image-toolbar` CSS from single-row to multi-row**

The toolbar uses `display: flex; align-items: center`. Change it to flex-column so rows stack:

Old:
```
    #image-toolbar {
      display: none;
      position: fixed;
      align-items: center;
      gap: 4px;
      padding: 4px 8px;
```

New:
```
    #image-toolbar {
      display: none;
      position: fixed;
      flex-direction: column;
      align-items: stretch;
      gap: 0;
      padding: 0;
```

- [ ] **Step 2: Add inner row CSS for the two rows**

After the `#image-toolbar` block, add new rules. Find:

Old:
```
    body.dark #image-toolbar { background: #2c2c2e; border-color: #444; color: #f0f0f0; }
    #image-toolbar input[type="number"] {
```

New:
```
    body.dark #image-toolbar { background: #2c2c2e; border-color: #444; color: #f0f0f0; }
    .img-tb-row {
      display: flex;
      align-items: center;
      gap: 4px;
      padding: 4px 8px;
    }
    .img-tb-row + .img-tb-row { border-top: 1px solid #eee; }
    body.dark .img-tb-row + .img-tb-row { border-top-color: #444; }
    #image-toolbar input[type="text"] {
      flex: 1;
      min-width: 140px;
      padding: 2px 4px;
      border: 1px solid #ccc;
      border-radius: 3px;
      font-size: 12px;
      background: transparent;
      color: inherit;
    }
    body.dark #image-toolbar input[type="text"] { border-color: #555; }
    #image-toolbar input[type="number"] {
```

- [ ] **Step 3: Update the toolbar HTML to use row wrappers and add alt row**

Old:
```
  <div id="image-toolbar">
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
```

New:
```
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
      <input type="text" id="img-tb-alt" placeholder="Alt text…">
    </div>
  </div>
```

- [ ] **Step 4: Populate alt input in `_showImageToolbar` and clear in `_hideImageToolbar`**

In `_showImageToolbar`, after the line `document.getElementById('img-tb-h').value = ...`, add:

Old:
```
      document.getElementById('img-tb-w').value = nv.node.attrs.width  ?? ''
      document.getElementById('img-tb-h').value = nv.node.attrs.height ?? ''
      _updateNamedSizeButtons(null)
```

New:
```
      document.getElementById('img-tb-w').value   = nv.node.attrs.width  ?? ''
      document.getElementById('img-tb-h').value   = nv.node.attrs.height ?? ''
      document.getElementById('img-tb-alt').value = nv.node.attrs.alt    ?? ''
      _updateNamedSizeButtons(null)
```

In `_hideImageToolbar`, after `tb.style.display = 'none'`:

Old:
```
      tb.style.display = 'none'
      tb._activeNodeView = null
```

New:
```
      tb.style.display = 'none'
      tb._activeNodeView = null
      const altIn = document.getElementById('img-tb-alt')
      if (altIn) altIn.value = ''
```

- [ ] **Step 5: Add the alt text change/blur event handler**

In the image toolbar IIFE (`(function () { ... })()`, around line 1058), add the following after the `img-tb-reset` click handler and before the named-size button loop. Find:

Old:
```
      document.getElementById('img-tb-reset').addEventListener('click', () => {
        const tb = document.getElementById('image-toolbar')
        const nv = tb?._activeNodeView
        if (!nv) return
        const pos = nv.getPos()
        if (typeof pos !== 'number') return
        const { state, dispatch } = nv.editor.view
        dispatch(state.tr.setNodeMarkup(pos, null, { ...nv.node.attrs, width: null, height: null }))
        document.getElementById('img-tb-w').value = ''
        document.getElementById('img-tb-h').value = ''
      })

      document.querySelectorAll('#image-toolbar [data-size]').forEach(btn => {
```

New:
```
      document.getElementById('img-tb-reset').addEventListener('click', () => {
        const tb = document.getElementById('image-toolbar')
        const nv = tb?._activeNodeView
        if (!nv) return
        const pos = nv.getPos()
        if (typeof pos !== 'number') return
        const { state, dispatch } = nv.editor.view
        dispatch(state.tr.setNodeMarkup(pos, null, { ...nv.node.attrs, width: null, height: null }))
        document.getElementById('img-tb-w').value = ''
        document.getElementById('img-tb-h').value = ''
      })

      let _altDebounceTimer = null
      function _commitAlt(value) {
        const tb = document.getElementById('image-toolbar')
        const nv = tb?._activeNodeView
        if (!nv) return
        const pos = nv.getPos()
        if (typeof pos !== 'number') return
        const { state, dispatch } = nv.editor.view
        dispatch(state.tr.setNodeMarkup(pos, null, { ...nv.node.attrs, alt: value || null }))
      }
      document.getElementById('img-tb-alt').addEventListener('input', e => {
        clearTimeout(_altDebounceTimer)
        _altDebounceTimer = setTimeout(() => _commitAlt(e.target.value), 500)
      })
      document.getElementById('img-tb-alt').addEventListener('blur', e => {
        clearTimeout(_altDebounceTimer)
        _commitAlt(e.target.value)
      })

      document.querySelectorAll('#image-toolbar [data-size]').forEach(btn => {
```

- [ ] **Step 6: Also add the alt input to the `deselectNode` delay check so it keeps the toolbar open when focused**

Find the `deselectNode` method. The check `tb.contains(document.activeElement)` already covers the alt input since it's inside `#image-toolbar`. No change needed here.

- [ ] **Step 7: Build and smoke-test**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh 2>&1 | tail -5
```

Open `Quill.app`, click an image, verify the second toolbar row shows "Alt" input. Type alt text, click away, reselect image — verify the alt text persists in the toolbar.

- [ ] **Step 8: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add Sources/QuillKit/Resources/editor.html && git commit -m "feat: add alt text row to image toolbar"
```

---

## Task 5: Add `altText` to `WPMedia` (test-driven)

**Files:**
- Modify: `Sources/QuillKit/API/Models/WPMedia.swift`
- Modify: `Tests/QuillTests/WPMediaDecodingTests.swift`

- [ ] **Step 1: Write the failing test**

Add to the end of `WPMediaDecodingTests.swift` (before the closing `}`):

```swift
@Test func altTextDecodesFromAltText() throws {
    let json = """
    {"id":8,"source_url":"https://example.com/img.jpg","alt_text":"A sunset photo"}
    """
    let media = try decode(json)
    #expect(media.altText == "A sunset photo")
}

@Test func missingAltTextDefaultsToEmpty() throws {
    let json = """
    {"id":9,"source_url":"https://example.com/img.jpg"}
    """
    let media = try decode(json)
    #expect(media.altText == "")
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && swift test --filter WPMediaDecodingTests 2>&1 | tail -15
```

Expected: compile error — `altText` does not exist on `WPMedia`.

- [ ] **Step 3: Add `altText` to `WPMedia`**

In `Sources/QuillKit/API/Models/WPMedia.swift`, update `WPMedia`:

Add `public var altText: String` to the struct properties (after `var date: String`):

Old:
```
    public var date: String       // ISO8601, server local time
    public var mediaDetails: MediaDetails?

    enum CodingKeys: String, CodingKey {
        case id, title
        case sourceURL = "source_url"
        case mediaType = "media_type"
        case mimeType = "mime_type"
        case link, date
        case mediaDetails = "media_details"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(RenderedString.self, forKey: .title) ?? RenderedString(raw: "")
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType) ?? ""
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType) ?? ""
        link = try c.decodeIfPresent(String.self, forKey: .link) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        mediaDetails = try c.decodeIfPresent(MediaDetails.self, forKey: .mediaDetails)
    }
```

New:
```
    public var date: String       // ISO8601, server local time
    public var altText: String
    public var mediaDetails: MediaDetails?

    enum CodingKeys: String, CodingKey {
        case id, title
        case sourceURL = "source_url"
        case mediaType = "media_type"
        case mimeType = "mime_type"
        case link, date
        case altText = "alt_text"
        case mediaDetails = "media_details"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(RenderedString.self, forKey: .title) ?? RenderedString(raw: "")
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType) ?? ""
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType) ?? ""
        link = try c.decodeIfPresent(String.self, forKey: .link) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        altText = try c.decodeIfPresent(String.self, forKey: .altText) ?? ""
        mediaDetails = try c.decodeIfPresent(MediaDetails.self, forKey: .mediaDetails)
    }
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && swift test --filter WPMediaDecodingTests 2>&1 | tail -15
```

Expected: All `WPMediaDecodingTests` pass.

- [ ] **Step 5: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add Sources/QuillKit/API/Models/WPMedia.swift Tests/QuillTests/WPMediaDecodingTests.swift && git commit -m "feat: add altText field to WPMedia"
```

---

## Task 6: Add `updateMediaAltText` to `WordPressClient` (test-driven)

**Files:**
- Modify: `Sources/QuillKit/API/WordPressClient.swift`
- Modify: `Tests/QuillTests/WordPressClientTests.swift`

- [ ] **Step 1: Write the failing tests**

In `WordPressClientTests.swift`, add after the `deleteMediaSendsDeleteWithForceTrueQuery` test:

```swift
@Test func updateMediaAltTextSendsPatchToMediaEndpoint() async throws {
    var capturedRequest: URLRequest?
    MockURLProtocol.requestHandler = { request in
        capturedRequest = request
        return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                minimalMediaJSON.data(using: .utf8)!)
    }
    _ = try await client.updateMediaAltText(id: 42, altText: "A sunset photo")
    #expect(capturedRequest?.httpMethod == "POST")
    #expect(capturedRequest?.url?.path.contains("media/42") == true)
}

@Test func updateMediaAltTextBodyContainsAltText() async throws {
    var bodyData: Data?
    MockURLProtocol.requestHandler = { request in
        var body = Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n > 0 { body.append(contentsOf: buffer[..<n]) }
            }
            stream.close()
        }
        bodyData = body
        return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                minimalMediaJSON.data(using: .utf8)!)
    }
    _ = try await client.updateMediaAltText(id: 42, altText: "Sunset over a lake")
    let bodyStr = String(data: bodyData ?? Data(), encoding: .utf8) ?? ""
    #expect(bodyStr.contains("alt_text"))
    #expect(bodyStr.contains("Sunset over a lake"))
}

@Test func updateMediaAltTextReturnsDecodedMedia() async throws {
    let mediaJSON = """
    {"id":42,"title":{"rendered":"photo.jpg"},\
    "source_url":"https://example.com/photo.jpg",\
    "media_type":"image","mime_type":"image/jpeg",\
    "link":"https://example.com/?attachment_id=42","date":"2024-01-01T00:00:00",\
    "alt_text":"Updated alt text"}
    """
    MockURLProtocol.requestHandler = { request in
        return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                mediaJSON.data(using: .utf8)!)
    }
    let updated = try await client.updateMediaAltText(id: 42, altText: "Updated alt text")
    #expect(updated.id == 42)
    #expect(updated.altText == "Updated alt text")
}
```

Note: WordPress's REST API uses `POST` (not `PATCH`) for media updates when sending JSON. Use `POST` here, not `PUT` — this matches how `updatePost` works (which uses `put`, i.e. HTTP PUT). Actually WordPress accepts both PUT and POST for updates. Use `POST` to match the WordPress REST API convention for media. 

Actually, looking at `updatePost` which calls `put()` (HTTP PUT), and `createPost` which calls `post()` (HTTP POST) — the WordPress media endpoint accepts `POST` for updates too. Use `post()` (HTTP POST) to match the convention used for taxonomy creation and media PATCH-style updates.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && swift test --filter WordPressClientTests/updateMediaAltText 2>&1 | tail -15
```

Expected: compile error — method does not exist.

- [ ] **Step 3: Add `updateMediaAltText` to `WordPressClient`**

In `WordPressClient.swift`, add this method after `deleteMedia`:

Old:
```
    public func deleteMedia(id: Int) async throws {
        let url = try endpoint("media/\(id)", query: ["force": "true"])
        let request = authorizedRequest(url: url, method: "DELETE")
        try await performVoid(request)
    }

    // MARK: - Taxonomies
```

New:
```
    public func deleteMedia(id: Int) async throws {
        let url = try endpoint("media/\(id)", query: ["force": "true"])
        let request = authorizedRequest(url: url, method: "DELETE")
        try await performVoid(request)
    }

    public func updateMediaAltText(id: Int, altText: String) async throws -> WPMedia {
        let url = try endpoint("media/\(id)")
        return try await post(url, body: MediaAltPayload(altText: altText))
    }

    // MARK: - Taxonomies
```

Add the private payload struct (place it near `TaxonomyPayload`, around line 296):

Old:
```
    private struct TaxonomyPayload: Encodable {
        let name: String
    }
```

New:
```
    private struct TaxonomyPayload: Encodable {
        let name: String
    }

    private struct MediaAltPayload: Encodable {
        let altText: String
        enum CodingKeys: String, CodingKey { case altText = "alt_text" }
    }
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && swift test --filter WordPressClientTests 2>&1 | tail -20
```

Expected: All `WordPressClientTests` pass (including the three new tests).

- [ ] **Step 5: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add Sources/QuillKit/API/WordPressClient.swift Tests/QuillTests/WordPressClientTests.swift && git commit -m "feat: add updateMediaAltText to WordPressClient"
```

---

## Task 7: Thread alt text through the image insert path

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`
- Modify: `Sources/QuillKit/Views/Editor/EditorCoordinator.swift`
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift`

- [ ] **Step 1: Update `window.insertImageAt` to accept and apply alt text**

In `editor.html`, find:

Old:
```
    window.insertImageAt = (_index, url, width, height, mediaId) => {
      const attrs = { src: url }
      if (width  != null) attrs.width   = width
      if (height != null) attrs.height  = height
      if (mediaId != null) attrs.mediaId = mediaId
      editor.chain().focus().setImage(attrs).run()
    }
```

New:
```
    window.insertImageAt = (_index, url, width, height, mediaId, alt) => {
      const attrs = { src: url }
      if (width   != null) attrs.width   = width
      if (height  != null) attrs.height  = height
      if (mediaId != null) attrs.mediaId = mediaId
      if (alt)             attrs.alt     = alt
      editor.chain().focus().setImage(attrs).run()
    }
```

- [ ] **Step 2: Update `EditorCoordinator.insertImage` to accept and pass `alt`**

In `EditorCoordinator.swift`, find:

Old:
```
    func insertImage(url: String, at index: Int, width: Int? = nil, height: Int? = nil, mediaId: Int? = nil) {
        guard let wv = webView else { return }
        guard let jsonURL = try? JSONEncoder().encode(url),
            let urlStr = String(data: jsonURL, encoding: .utf8)
        else { return }
        let wStr  = width.map   { String($0) } ?? "null"
        let hStr  = height.map  { String($0) } ?? "null"
        let idStr = mediaId.map { String($0) } ?? "null"
        wv.evaluateJavaScript("insertImageAt(\(index), \(urlStr), \(wStr), \(hStr), \(idStr))", completionHandler: nil)
    }
```

New:
```
    func insertImage(url: String, at index: Int, width: Int? = nil, height: Int? = nil, mediaId: Int? = nil, alt: String? = nil) {
        guard let wv = webView else { return }
        guard let jsonURL = try? JSONEncoder().encode(url),
            let urlStr = String(data: jsonURL, encoding: .utf8)
        else { return }
        let wStr   = width.map   { String($0) } ?? "null"
        let hStr   = height.map  { String($0) } ?? "null"
        let idStr  = mediaId.map { String($0) } ?? "null"
        let altStr: String
        if let alt, !alt.isEmpty,
           let jsonAlt = try? JSONEncoder().encode(alt),
           let s = String(data: jsonAlt, encoding: .utf8) {
            altStr = s
        } else {
            altStr = "null"
        }
        wv.evaluateJavaScript("insertImageAt(\(index), \(urlStr), \(wStr), \(hStr), \(idStr), \(altStr))", completionHandler: nil)
    }
```

- [ ] **Step 3: Update `handleInsertMedia` to read and pass `alt`**

In `EditorCoordinator.swift`:

Old:
```
    @objc private func handleInsertMedia(_ note: Notification) {
        guard let url = note.userInfo?["url"] as? String,
            let index = note.userInfo?["index"] as? Int
        else { return }
        let width   = note.userInfo?["width"]   as? Int
        let height  = note.userInfo?["height"]  as? Int
        let mediaId = note.userInfo?["mediaId"] as? Int
        insertImage(url: url, at: index, width: width, height: height, mediaId: mediaId)
    }
```

New:
```
    @objc private func handleInsertMedia(_ note: Notification) {
        guard let url = note.userInfo?["url"] as? String,
            let index = note.userInfo?["index"] as? Int
        else { return }
        let width   = note.userInfo?["width"]   as? Int
        let height  = note.userInfo?["height"]  as? Int
        let mediaId = note.userInfo?["mediaId"] as? Int
        let alt     = note.userInfo?["alt"]     as? String
        insertImage(url: url, at: index, width: width, height: height, mediaId: mediaId, alt: alt)
    }
```

- [ ] **Step 4: Pass `altText` in the media picker insert notification (PostEditorView)**

In `PostEditorView.swift`, find the `MediaPickerView { selected in ... }` closure:

Old:
```
                    if let idx = imageInsertIndex {
                        MediaPickerView { selected in
                            var info: [String: Any] = [
                                "url":     selected.sourceURL,
                                "index":   idx,
                                "mediaId": selected.id,
                            ]
                            if let w = selected.mediaDetails?.width  { info["width"]  = w }
                            if let h = selected.mediaDetails?.height { info["height"] = h }
                            NotificationCenter.default.post(name: .insertMediaURL, object: nil, userInfo: info)
                            imageInsertIndex = nil
                        }
```

New:
```
                    if let idx = imageInsertIndex {
                        MediaPickerView { selected in
                            var info: [String: Any] = [
                                "url":     selected.sourceURL,
                                "index":   idx,
                                "mediaId": selected.id,
                            ]
                            if let w = selected.mediaDetails?.width  { info["width"]  = w }
                            if let h = selected.mediaDetails?.height { info["height"] = h }
                            if !selected.altText.isEmpty { info["alt"] = selected.altText }
                            NotificationCenter.default.post(name: .insertMediaURL, object: nil, userInfo: info)
                            imageInsertIndex = nil
                        }
```

- [ ] **Step 5: Also pass `altText` in the drag-drop insert notification (PostEditorView)**

Find `handleDroppedImages`:

Old:
```
                var info: [String: Any] = ["url": media.sourceURL, "index": 0, "mediaId": media.id]
                if let w = media.mediaDetails?.width  { info["width"]  = w }
                if let h = media.mediaDetails?.height { info["height"] = h }
                NotificationCenter.default.post(name: .insertMediaURL, object: nil, userInfo: info)
```

New:
```
                var info: [String: Any] = ["url": media.sourceURL, "index": 0, "mediaId": media.id]
                if let w = media.mediaDetails?.width  { info["width"]  = w }
                if let h = media.mediaDetails?.height { info["height"] = h }
                if !media.altText.isEmpty { info["alt"] = media.altText }
                NotificationCenter.default.post(name: .insertMediaURL, object: nil, userInfo: info)
```

- [ ] **Step 6: Build and verify**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh 2>&1 | tail -5
```

Open `Quill.app`. Insert an image from the media library that has alt text set in WordPress. Verify the alt text is pre-filled in the image toolbar's Alt row.

- [ ] **Step 7: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add Sources/QuillKit/Resources/editor.html Sources/QuillKit/Views/Editor/EditorCoordinator.swift Sources/QuillKit/Views/Editor/PostEditorView.swift && git commit -m "feat: pre-populate alt text from WordPress media library on image insert"
```

---

## Task 8: Add editable alt text field to `MediaDetailView`

**Files:**
- Modify: `Sources/QuillKit/Views/Media/MediaDetailView.swift`

- [ ] **Step 1: Add state and callback to `MediaDetailView`**

Replace the struct declaration and body opening:

Old:
```
struct MediaDetailView: View {
    let media: WPMedia

    var body: some View {
```

New:
```
struct MediaDetailView: View {
    let media: WPMedia
    var onSaveAltText: ((String) async -> Void)? = nil

    @State private var altTextDraft = ""
    @State private var altSaveState: AltSaveState = .idle
    @FocusState private var altFieldFocused: Bool

    private enum AltSaveState { case idle, saving, saved }

    init(media: WPMedia, onSaveAltText: ((String) async -> Void)? = nil) {
        self.media = media
        self.onSaveAltText = onSaveAltText
        self._altTextDraft = State(initialValue: media.altText)
    }

    var body: some View {
```

- [ ] **Step 2: Add the alt text row helper**

Add a new computed property after the `urlRow` property (before `formattedDate`):

Old:
```
    private func formattedDate(_ iso: String) -> String {
```

New:
```
    @ViewBuilder
    private var altTextRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("ALT TEXT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Describe this image…", text: $altTextDraft, axis: .vertical)
                .font(.system(size: 13))
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.secondary.opacity(0.3))
                )
                .onSubmit { commitAltText() }
            HStack {
                switch altSaveState {
                case .saving:
                    ProgressView().scaleEffect(0.6)
                    Text("Saving…").font(.system(size: 10)).foregroundStyle(.secondary)
                case .saved:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10)).foregroundStyle(.green)
                    Text("Saved").font(.system(size: 10)).foregroundStyle(.secondary)
                case .idle:
                    EmptyView()
                }
            }
            .frame(height: 14)
        }
        .onChange(of: altTextDraft) { _, _ in
            altSaveState = .idle
        }
    }

    private func commitAltText() {
        guard let save = onSaveAltText else { return }
        let text = altTextDraft
        altSaveState = .saving
        Task {
            await save(text)
            await MainActor.run { altSaveState = .saved }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { if altSaveState == .saved { altSaveState = .idle } }
        }
    }

    private func formattedDate(_ iso: String) -> String {
```

- [ ] **Step 3: Insert `altTextRow` after the Dimensions row in `metadataPanel`**

Old:
```
                if let details = media.mediaDetails,
                   let w = details.width, let h = details.height,
                   w > 0, h > 0 {
                    metadataRow(label: "Dimensions", value: "\(w) × \(h) px")
                }

                if !media.date.isEmpty {
```

New:
```
                if let details = media.mediaDetails,
                   let w = details.width, let h = details.height,
                   w > 0, h > 0 {
                    metadataRow(label: "Dimensions", value: "\(w) × \(h) px")
                }

                altTextRow

                if !media.date.isEmpty {
```

- [ ] **Step 4: Add blur-commit via `@FocusState`**

SwiftUI's `TextField` with `onSubmit` handles Return. To also save on blur (clicking away), wire the `@FocusState` property declared in Step 1 to the TextField. Find the `TextField` created in `altTextRow` and add `.focused` + `.onChange` modifiers after `.onSubmit`:

Old (inside `altTextRow`):
```
                .onSubmit { commitAltText() }
            HStack {
```

New:
```
                .onSubmit { commitAltText() }
                .focused($altFieldFocused)
                .onChange(of: altFieldFocused) { _, focused in
                    if !focused { commitAltText() }
                }
            HStack {
```

- [ ] **Step 5: Build and verify the view compiles**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && swift build 2>&1 | grep -E "error:|warning:" | head -20
```

Expected: No errors.

- [ ] **Step 6: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add Sources/QuillKit/Views/Media/MediaDetailView.swift && git commit -m "feat: add editable alt text field to MediaDetailView"
```

---

## Task 9: Wire `onSaveAltText` in `ContentView`

**Files:**
- Modify: `Sources/QuillKit/Views/ContentView.swift`

- [ ] **Step 1: Update the `MediaDetailView` call site**

In `ContentView.swift`:

Old:
```
                    if let media = appState.selectedMedia {
                        MediaDetailView(media: media)
                    } else {
```

New:
```
                    if let media = appState.selectedMedia {
                        MediaDetailView(media: media) { [media] altText in
                            guard let creds = appState.credentials else { return }
                            guard let idx = appState.mediaItems.firstIndex(where: { $0.id == media.id }) else { return }
                            do {
                                let updated = try await WordPressClient(credentials: creds)
                                    .updateMediaAltText(id: media.id, altText: altText)
                                appState.mediaItems[idx] = updated
                            } catch {
                                // Save failed silently — field retains the edited value
                            }
                        }
                        .id(media.id)
                    } else {
```

The `.id(media.id)` ensures SwiftUI recreates `MediaDetailView` when a different image is selected, resetting `altTextDraft` to the new image's `altText`.

- [ ] **Step 2: Build the full app**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh 2>&1 | tail -10
```

Expected: Build succeeds.

- [ ] **Step 3: Run the full test suite**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./test.sh 2>&1 | tail -20
```

Expected: All 192+ Swift tests and 37+ JS tests pass.

- [ ] **Step 4: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add Sources/QuillKit/Views/ContentView.swift && git commit -m "feat: wire alt text save callback in ContentView"
```

---

## Task 10: End-to-end smoke test and CLAUDE.md update

- [ ] **Step 1: Full manual test**

Open `Quill.app` and verify each of the following:

**Captions:**
- Load a post with existing `<figure class="wp-block-image"><img ...><figcaption class="wp-element-caption">Caption text</figcaption></figure>` — the caption loads and displays in the editor
- An image with no caption shows "Add a caption…" placeholder below it
- Click the placeholder, type a caption — it appears inline
- Save the post — the WordPress API receives `<figcaption class="wp-element-caption">Caption text</figcaption>` inside the `<figure>`
- Delete the caption text — placeholder reappears on blur
- Save again — `<figcaption>` is absent from the stored HTML

**Alt text (toolbar):**
- Click an image — alt text row appears in the image toolbar
- Type alt text — after blur or 500ms debounce, it is stored on the node
- Reload the post — alt text persists (it's saved in the post HTML as `<img alt="...">`)
- Insert a new image from the media library that has alt text in WordPress — alt field is pre-populated

**Alt text (media detail):**
- Click Media tab, select an image
- Alt text field appears after Dimensions row, populated with the attachment's current alt text
- Edit the field, press Return or click away — "Saving…" spinner appears then "Saved" confirmation
- Reload the page in WordPress admin and verify the alt text was updated

- [ ] **Step 2: Run the full test suite one final time**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./test.sh 2>&1 | tail -10
```

Expected: All tests pass.

- [ ] **Step 3: Update CLAUDE.md**

Run the `claude-md-management:revise-claude-md` skill to update CLAUDE.md with the new image caption and alt text architecture, toolbar layout, `toWordPressHTML` figure-annotation logic, and `WPMedia.altText` field.

- [ ] **Step 4: Final commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add CLAUDE.md && git commit -m "docs: update CLAUDE.md for image captions and alt text feature"
```
