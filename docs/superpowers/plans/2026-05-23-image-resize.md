# Image Resize Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add inline image resizing (drag handles + size picker) and preserve WordPress width/height attributes on round-trip.

**Architecture:** Custom Tiptap Image extension adds `width`, `height`, `mediaId` attributes. A ProseMirror NodeView renders each image with 8 drag handles and a floating size picker toolbar. Swift passes dimensions when inserting images; a `requestMediaSizes`/`setMediaSizes` round-trip populates named-size buttons.

**Tech Stack:** Tiptap 2.x (esm.sh CDN), ProseMirror NodeView API, Swift 6, WKWebView message handlers

---

## Files Changed

| File | Changes |
|---|---|
| `Sources/QuillKit/Resources/editor.html` | Custom Image extension, ImageNodeView class, handle + toolbar CSS, toolbar HTML, updated JS globals |
| `Sources/QuillKit/Views/Editor/EditorCoordinator.swift` | Expanded `insertImage` signature, `requestMediaSizes` handler, `onRequestMediaSizes` closure |
| `Sources/QuillKit/Views/Editor/EditorView.swift` | New `onRequestMediaSizes` param, register message handler, wire closure |
| `Sources/QuillKit/Views/Editor/PostEditorView.swift` | Pass `width`, `height`, `mediaId` in both `insertMediaURL` call sites; add `onRequestMediaSizes` to `EditorView` |

---

## Task 1: Custom ResizableImage Tiptap Extension

Extends the base Image extension with `width`, `height`, and `mediaId` attributes. No NodeView yet — Tiptap's default rendering is used so the build stays green while we verify HTML round-tripping.

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`

- [ ] **Step 1: Change the Image import to a named import**

Find:
```javascript
    import Image        from 'https://esm.sh/@tiptap/extension-image@2'
```
Replace with:
```javascript
    import { Image as TiptapImage } from 'https://esm.sh/@tiptap/extension-image@2'
```

- [ ] **Step 2: Add the ResizableImage extension before `const editor = new Editor({`**

Insert this entire block immediately before `const editor = new Editor({`:

```javascript
    // ── ResizableImage extension ──────────────────────
    const ResizableImage = TiptapImage.extend({
      addAttributes() {
        return {
          ...this.parent?.(),
          width: {
            default: null,
            parseHTML: el => {
              const v = el.getAttribute('width')
              return v ? parseInt(v, 10) : null
            },
            renderHTML: attrs => attrs.width != null ? { width: attrs.width } : {},
          },
          height: {
            default: null,
            parseHTML: el => {
              const v = el.getAttribute('height')
              return v ? parseInt(v, 10) : null
            },
            renderHTML: attrs => attrs.height != null ? { height: attrs.height } : {},
          },
          mediaId: {
            default: null,
            parseHTML: el => {
              const dataId = el.getAttribute('data-media-id')
              if (dataId) return parseInt(dataId, 10)
              const m = (el.getAttribute('class') || '').match(/wp-image-(\d+)/)
              return m ? parseInt(m[1], 10) : null
            },
            renderHTML: attrs => attrs.mediaId != null ? { 'data-media-id': attrs.mediaId } : {},
          },
        }
      },
    })
```

- [ ] **Step 3: Replace Image.configure in the extensions list**

Find:
```javascript
        Image.configure({ inline: false }),
```
Replace with:
```javascript
        ResizableImage.configure({ inline: false }),
```

- [ ] **Step 4: Update `window.insertImageAt` to accept width, height, mediaId**

Find:
```javascript
    window.insertImageAt = (_index, url) => {
      editor.chain().focus().setImage({ src: url }).run()
    }
```
Replace with:
```javascript
    window.insertImageAt = (_index, url, width, height, mediaId) => {
      const attrs = { src: url }
      if (width  != null) attrs.width   = width
      if (height != null) attrs.height  = height
      if (mediaId != null) attrs.mediaId = mediaId
      editor.chain().focus().setImage(attrs).run()
    }
```

- [ ] **Step 5: Build**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh
```
Expected: compiles with no errors.

- [ ] **Step 6: Verify HTML round-trip**

Open `Quill.app`. Open any post that has images. Open DevTools (right-click in editor → Inspect Element if available, or check via Xcode). Confirm that images with existing `width` attributes in the WordPress HTML render at that width. Confirm a newly inserted image (via Image button) goes in without crashing.

- [ ] **Step 7: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
git add Sources/QuillKit/Resources/editor.html
git commit -m "feat: extend Image node with width, height, mediaId attributes"
```

---

## Task 2: ImageNodeView, Handle CSS, and Toolbar HTML

Adds the NodeView class that wraps images in a `<div>` with 8 drag handles and selection styling. Also adds the singleton `#image-toolbar` floating div and the CSS/JS infrastructure for both. Drag behavior is wired in Task 3.

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`

- [ ] **Step 1: Add CSS for image wrapper, handles, and toolbar**

In the `<style>` block, after the `.ProseMirror img { max-width: 100%; border-radius: 4px; }` line, insert:

```css
    /* ── Image NodeView ─────────────────────────────── */
    .image-wrapper {
      position: relative;
      display: inline-block;
      max-width: 100%;
      line-height: 0;
    }
    .image-wrapper img { display: block; max-width: 100%; border-radius: 4px; }
    .image-wrapper.selected img {
      outline: 2px solid #007aff;
      border-radius: 4px;
    }
    body.dark .image-wrapper.selected img { outline-color: #0a84ff; }

    .resize-handle {
      position: absolute;
      width: 8px;
      height: 8px;
      background: #007aff;
      border: 1.5px solid #fff;
      border-radius: 2px;
      opacity: 0;
      pointer-events: none;
      z-index: 10;
    }
    body.dark .resize-handle { background: #0a84ff; }
    .image-wrapper.selected .resize-handle { opacity: 1; pointer-events: auto; }

    .resize-handle.nw { top: -4px; left: -4px; cursor: nwse-resize; }
    .resize-handle.n  { top: -4px; left: calc(50% - 4px); cursor: ns-resize; }
    .resize-handle.ne { top: -4px; right: -4px; cursor: nesw-resize; }
    .resize-handle.e  { top: calc(50% - 4px); right: -4px; cursor: ew-resize; }
    .resize-handle.se { bottom: -4px; right: -4px; cursor: nwse-resize; }
    .resize-handle.s  { bottom: -4px; left: calc(50% - 4px); cursor: ns-resize; }
    .resize-handle.sw { bottom: -4px; left: -4px; cursor: nesw-resize; }
    .resize-handle.w  { top: calc(50% - 4px); left: -4px; cursor: ew-resize; }

    /* ── Image toolbar ──────────────────────────────── */
    #image-toolbar {
      display: none;
      position: fixed;
      align-items: center;
      gap: 4px;
      padding: 4px 8px;
      background: #fff;
      border: 1px solid #ddd;
      border-radius: 6px;
      box-shadow: 0 2px 8px rgba(0,0,0,0.12);
      font-size: 12px;
      white-space: nowrap;
      z-index: 200;
      user-select: none;
    }
    body.dark #image-toolbar { background: #2c2c2e; border-color: #444; color: #f0f0f0; }
    #image-toolbar input[type="number"] {
      width: 52px;
      padding: 2px 4px;
      border: 1px solid #ccc;
      border-radius: 3px;
      font-size: 12px;
      text-align: center;
      background: transparent;
      color: inherit;
    }
    body.dark #image-toolbar input[type="number"] { border-color: #555; }
    #image-toolbar input[type="number"]::-webkit-inner-spin-button,
    #image-toolbar input[type="number"]::-webkit-outer-spin-button { -webkit-appearance: none; }
    #image-toolbar button {
      font-size: 12px;
      padding: 2px 6px;
      border: 1px solid transparent;
      border-radius: 3px;
      cursor: pointer;
      background: transparent;
      color: inherit;
    }
    #image-toolbar button:hover { background: rgba(0,0,0,0.07); }
    body.dark #image-toolbar button:hover { background: rgba(255,255,255,0.1); }
    #image-toolbar button:disabled { opacity: 0.4; cursor: default; }
    #image-toolbar .img-tb-sep { width: 1px; height: 14px; background: #ddd; margin: 0 2px; }
    body.dark #image-toolbar .img-tb-sep { background: #444; }
    #image-toolbar .img-tb-label { color: #999; }
```

- [ ] **Step 2: Add `#image-toolbar` HTML element to the body**

Find:
```html
  <div id="drop-overlay"><span>Drop to upload</span></div>
```
After that line, insert:
```html
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

- [ ] **Step 3: Add `ImageNodeView` class before the ResizableImage extension block**

Insert this entire block immediately before `// ── ResizableImage extension ──`:

```javascript
    // ── ImageNodeView ─────────────────────────────────
    class ImageNodeView {
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

      _applyAttrs(attrs) {
        this.img.src = attrs.src || ''
        if (attrs.alt)   this.img.alt   = attrs.alt
        if (attrs.title) this.img.title = attrs.title
        if (attrs.width != null) {
          this.img.width = attrs.width
          this.wrapper.style.width = attrs.width + 'px'
        } else {
          this.img.removeAttribute('width')
          this.wrapper.style.width = ''
        }
        if (attrs.height != null) {
          this.img.height = attrs.height
        } else {
          this.img.removeAttribute('height')
        }
      }

      update(node) {
        if (node.type.name !== 'image') return false
        this.node = node
        this._applyAttrs(node.attrs)
        // Sync toolbar inputs if this image is currently selected
        const tb = document.getElementById('image-toolbar')
        if (tb?._activeNodeView === this) {
          document.getElementById('img-tb-w').value = node.attrs.width  ?? ''
          document.getElementById('img-tb-h').value = node.attrs.height ?? ''
        }
        return true
      }

      selectNode() {
        this.wrapper.classList.add('selected')
        _showImageToolbar(this)
      }

      deselectNode() {
        this.wrapper.classList.remove('selected')
        // Delay so toolbar inputs can receive focus before we check
        setTimeout(() => {
          const tb = document.getElementById('image-toolbar')
          if (tb && tb.contains(document.activeElement)) return
          if (tb?._activeNodeView === this) _hideImageToolbar()
        }, 80)
      }

      destroy() {
        const tb = document.getElementById('image-toolbar')
        if (tb?._activeNodeView === this) _hideImageToolbar()
      }

      stopEvent(e) {
        // Prevent ProseMirror from stealing handle mousedown events
        return e.type === 'mousedown' && e.target.classList.contains('resize-handle')
      }

      ignoreMutation() { return true }

      _onHandleMousedown(_e, _pos) { /* filled in Task 3 */ }
    }

    // ── Image toolbar helpers ──────────────────────────
    function _positionImageToolbar(tb, wrapper) {
      const wRect = wrapper.getBoundingClientRect()
      tb.style.left = wRect.left + 'px'
      tb.style.top  = (wRect.bottom + 6) + 'px'
    }

    function _showImageToolbar(nv) {
      const tb = document.getElementById('image-toolbar')
      if (!tb) return
      tb._activeNodeView = nv
      document.getElementById('img-tb-w').value = nv.node.attrs.width  ?? ''
      document.getElementById('img-tb-h').value = nv.node.attrs.height ?? ''
      _updateNamedSizeButtons(null)

      _positionImageToolbar(tb, nv.wrapper)
      tb.style.display = 'flex'

      // Reposition on scroll so the toolbar tracks the image
      tb._scrollHandler = () => _positionImageToolbar(tb, nv.wrapper)
      document.getElementById('editor-wrap').addEventListener('scroll', tb._scrollHandler)

      if (nv.node.attrs.mediaId != null) {
        window.webkit?.messageHandlers?.requestMediaSizes
          ?.postMessage({ mediaId: nv.node.attrs.mediaId })
      }
    }

    function _hideImageToolbar() {
      const tb = document.getElementById('image-toolbar')
      if (!tb) return
      if (tb._scrollHandler) {
        document.getElementById('editor-wrap').removeEventListener('scroll', tb._scrollHandler)
        tb._scrollHandler = null
      }
      tb.style.display = 'none'
      tb._activeNodeView = null
    }

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

- [ ] **Step 4: Add `addNodeView()` to the ResizableImage extension**

Inside the `ResizableImage` extension (after the closing `},` of `addAttributes()`), add:

```javascript
      addNodeView() {
        return ({ node, editor, getPos }) => new ImageNodeView(node, editor, getPos)
      },
```

So the extension now reads:
```javascript
    const ResizableImage = TiptapImage.extend({
      addAttributes() {
        // ... (unchanged)
      },
      addNodeView() {
        return ({ node, editor, getPos }) => new ImageNodeView(node, editor, getPos)
      },
    })
```

- [ ] **Step 5: Add `window.setMediaSizes` global alongside the other globals**

After `window.removeLink = () => { ... }`, add:

```javascript
    window.setMediaSizes = (mediaId, sizes) => {
      const tb = document.getElementById('image-toolbar')
      if (!tb || tb.style.display === 'none') return
      const nv = tb._activeNodeView
      if (!nv || nv.node.attrs.mediaId !== mediaId) return
      _updateNamedSizeButtons(sizes)
    }
```

- [ ] **Step 6: Build**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh
```
Expected: compiles with no errors.

- [ ] **Step 7: Verify**

Open `Quill.app`. Insert an image via the Image button in the toolbar. Click the image — it should get a blue outline. Handles should appear at corners and edges. The small toolbar should appear just below the image (W/H inputs, Reset button; size buttons hidden). Click elsewhere — handles and toolbar disappear.

- [ ] **Step 8: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
git add Sources/QuillKit/Resources/editor.html
git commit -m "feat: add ImageNodeView with resize handles and size picker toolbar"
```

---

## Task 3: Drag-to-Resize Behavior

Fills in the `_onHandleMousedown` method in `ImageNodeView`. Corner handles maintain aspect ratio; Shift breaks the lock. Edge handles resize one axis only.

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`

- [ ] **Step 1: Replace the `_onHandleMousedown` stub**

Find:
```javascript
      _onHandleMousedown(_e, _pos) { /* filled in Task 3 */ }
```
Replace with:
```javascript
      _onHandleMousedown(e, handlePos) {
        e.preventDefault()
        e.stopPropagation()

        const startX   = e.clientX
        const startY   = e.clientY
        const startW   = this.img.offsetWidth  || 300
        const startH   = this.img.offsetHeight || 200
        const ratio    = startW / startH
        const isCorner = ['nw','ne','sw','se'].includes(handlePos)
        const wSign    = handlePos.includes('e') ? 1 : handlePos.includes('w') ? -1 : 0
        const hSign    = handlePos.includes('s') ? 1 : handlePos.includes('n') ? -1 : 0

        const onMove = me => {
          const dx = (me.clientX - startX) * wSign
          const dy = (me.clientY - startY) * hSign
          let newW = startW
          let newH = startH

          if (isCorner && !me.shiftKey) {
            newW = Math.max(50, startW + dx)
            newH = newW / ratio
          } else {
            if (wSign !== 0) newW = Math.max(50, startW + dx)
            if (hSign !== 0) newH = Math.max(50, startH + dy)
          }

          newW = Math.round(newW)
          newH = Math.round(newH)

          this.img.style.width  = newW + 'px'
          this.img.style.height = newH + 'px'
          this.wrapper.style.width = newW + 'px'

          const wIn = document.getElementById('img-tb-w')
          const hIn = document.getElementById('img-tb-h')
          if (wIn) wIn.value = newW
          if (hIn) hIn.value = newH
        }

        const onUp = () => {
          document.removeEventListener('mousemove', onMove)
          document.removeEventListener('mouseup', onUp)

          const newW = Math.round(parseFloat(this.img.style.width)  || this.img.offsetWidth)
          const newH = Math.round(parseFloat(this.img.style.height) || this.img.offsetHeight)
          this.img.style.width  = ''
          this.img.style.height = ''

          const pos = this.getPos()
          if (typeof pos === 'number') {
            const { state, dispatch } = this.editor.view
            dispatch(state.tr.setNodeMarkup(pos, null, { ...this.node.attrs, width: newW, height: newH }))
          }
        }

        document.addEventListener('mousemove', onMove)
        document.addEventListener('mouseup', onUp)
      }
```

- [ ] **Step 2: Build**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh
```
Expected: compiles with no errors.

- [ ] **Step 3: Verify drag behavior**

Open `Quill.app`. Insert an image and click to select it. Drag a corner handle — image resizes proportionally, toolbar W/H inputs update live, commit on release. Drag a corner while holding Shift — width and height resize independently. Drag an edge (N/S or E/W) — only one axis changes. Minimum size is 50px; you cannot drag below that.

- [ ] **Step 4: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
git add Sources/QuillKit/Resources/editor.html
git commit -m "feat: implement drag-to-resize with aspect ratio locking"
```

---

## Task 4: Toolbar — Dimension Inputs, Reset, and Named Size Buttons

Wires up the `#image-toolbar` input fields and buttons. Typing in W recalculates H (and vice versa). Reset clears dimensions. Named size buttons swap src + dimensions (data populated in Task 6 when Swift sends sizes).

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`

- [ ] **Step 1: Add toolbar event handlers**

After `window.setMediaSizes = ...` (the last global added in Task 2, Step 5), insert:

```javascript
    // ── Image toolbar event handlers ──────────────────
    ;(function () {
      function commitDims(newW, newH) {
        const tb = document.getElementById('image-toolbar')
        const nv = tb?._activeNodeView
        if (!nv) return
        const pos = nv.getPos()
        if (typeof pos !== 'number') return
        const { state, dispatch } = nv.editor.view
        dispatch(state.tr.setNodeMarkup(pos, null, { ...nv.node.attrs, width: newW, height: newH }))
      }

      document.getElementById('img-tb-w').addEventListener('change', e => {
        const tb  = document.getElementById('image-toolbar')
        const nv  = tb?._activeNodeView
        const newW = Math.max(50, parseInt(e.target.value) || 50)
        let newH = nv?.node.attrs.height ?? null
        const attrs = nv?.node.attrs
        if (attrs?.width && attrs?.height) {
          newH = Math.round(newW * (attrs.height / attrs.width))
          document.getElementById('img-tb-h').value = newH
        }
        commitDims(newW, newH)
      })

      document.getElementById('img-tb-h').addEventListener('change', e => {
        const tb  = document.getElementById('image-toolbar')
        const nv  = tb?._activeNodeView
        const newH = Math.max(50, parseInt(e.target.value) || 50)
        let newW = nv?.node.attrs.width ?? null
        const attrs = nv?.node.attrs
        if (attrs?.width && attrs?.height) {
          newW = Math.round(newH * (attrs.width / attrs.height))
          document.getElementById('img-tb-w').value = newW
        }
        commitDims(newW, newH)
      })

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

- [ ] **Step 2: Build**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh
```
Expected: compiles with no errors.

- [ ] **Step 3: Verify toolbar controls**

Open `Quill.app`. Insert an image, click to select it, type a new value in the W input and press Enter — the image resizes and H updates proportionally. Do the same for H. Click Reset — the image returns to natural/unconstrained size and both inputs clear.

- [ ] **Step 4: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
git add Sources/QuillKit/Resources/editor.html
git commit -m "feat: wire up image toolbar dimension inputs, reset, and named size buttons"
```

---

## Task 5: Swift — EditorCoordinator + EditorView

Expands `insertImage` to carry dimensions and mediaId. Adds the `requestMediaSizes` message handler and `onRequestMediaSizes` closure to the coordinator. Registers the new handler in `EditorView`.

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/EditorCoordinator.swift`
- Modify: `Sources/QuillKit/Views/Editor/EditorView.swift`

- [ ] **Step 1: Add `onRequestMediaSizes` closure to `EditorCoordinator`**

In `EditorCoordinator.swift`, find the existing closure properties:
```swift
    var onInsertImageAt: ((Int) -> Void)?
    var onSearchLinks: ((String) async throws -> [LinkSearchResult])?
```
Add after them:
```swift
    var onRequestMediaSizes: ((Int) -> WPMedia?)?
```

- [ ] **Step 2: Expand `insertImage(url:at:)` signature**

Find:
```swift
    func insertImage(url: String, at index: Int) {
        guard let wv = webView else { return }
        guard let jsonURL = try? JSONEncoder().encode(url),
            let urlStr = String(data: jsonURL, encoding: .utf8)
        else { return }
        wv.evaluateJavaScript("insertImageAt(\(index), \(urlStr))", completionHandler: nil)
    }
```
Replace with:
```swift
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

- [ ] **Step 3: Update `handleInsertMedia` to extract new keys**

Find:
```swift
    @objc private func handleInsertMedia(_ note: Notification) {
        guard let url = note.userInfo?["url"] as? String,
            let index = note.userInfo?["index"] as? Int
        else { return }
        insertImage(url: url, at: index)
    }
```
Replace with:
```swift
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

- [ ] **Step 4: Add `requestMediaSizes` case to `userContentController`**

In the `switch message.name` block, after the `case "showLinkPicker":` block (before `default:`), add:

```swift
        case "requestMediaSizes":
            if let body = message.body as? [String: Any],
               let mediaId = body["mediaId"] as? Int {
                DispatchQueue.main.async { self.handleRequestMediaSizes(mediaId: mediaId) }
            }
```

- [ ] **Step 5: Add `handleRequestMediaSizes` private method**

After the `showLinkPicker` private method, add:

```swift
    private func handleRequestMediaSizes(mediaId: Int) {
        guard let wv = webView else { return }
        guard let media = onRequestMediaSizes?(mediaId),
              let sizes = media.mediaDetails?.sizes,
              !sizes.isEmpty
        else {
            wv.evaluateJavaScript("setMediaSizes(\(mediaId), null)", completionHandler: nil)
            return
        }
        var dict: [String: Any] = [:]
        for (name, size) in sizes {
            dict[name] = ["url": size.sourceURL, "width": size.width, "height": size.height]
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict),
              let jsonStr  = String(data: jsonData, encoding: .utf8)
        else { return }
        wv.evaluateJavaScript("setMediaSizes(\(mediaId), \(jsonStr))", completionHandler: nil)
    }
```

- [ ] **Step 6: Add `onRequestMediaSizes` to `EditorView`**

In `EditorView.swift`, add the property after `onSearchLinks`:
```swift
    var onRequestMediaSizes: ((Int) -> WPMedia?)?
```

In the `init`, add the parameter with a default of `nil`:
```swift
    public init(
        html: Binding<String>,
        onContentChange: @escaping (String) -> Void,
        onInsertImageAt: ((Int) -> Void)? = nil,
        onImageFilesDropped: (([URL]) -> Void)? = nil,
        onSearchLinks: ((String) async throws -> [LinkSearchResult])? = nil,
        onRequestMediaSizes: ((Int) -> WPMedia?)? = nil
    ) {
        self._html = html
        self.onContentChange = onContentChange
        self.onInsertImageAt = onInsertImageAt
        self.onImageFilesDropped = onImageFilesDropped
        self.onSearchLinks = onSearchLinks
        self.onRequestMediaSizes = onRequestMediaSizes
    }
```

In `makeNSView`, after the existing `config.userContentController.add(context.coordinator, name: "showLinkPicker")` line, add:
```swift
        config.userContentController.add(context.coordinator, name: "requestMediaSizes")
```

After `context.coordinator.onSearchLinks = onSearchLinks` in `makeNSView`, add:
```swift
        context.coordinator.onRequestMediaSizes = onRequestMediaSizes
```

In `updateNSView`, after `context.coordinator.onSearchLinks = onSearchLinks`, add:
```swift
        context.coordinator.onRequestMediaSizes = onRequestMediaSizes
```

- [ ] **Step 7: Build**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh
```
Expected: compiles with no errors.

- [ ] **Step 8: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
git add Sources/QuillKit/Views/Editor/EditorCoordinator.swift \
        Sources/QuillKit/Views/Editor/EditorView.swift
git commit -m "feat: add requestMediaSizes handler and expand insertImage signature"
```

---

## Task 6: PostEditorView — Pass Dimensions and Wire Named Sizes

Updates both `insertMediaURL` post sites to include `width`, `height`, and `mediaId`. Passes the `onRequestMediaSizes` closure to `EditorView`.

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift`

- [ ] **Step 1: Update the media picker call site**

Find:
```swift
                        MediaPickerView { selected in
                            NotificationCenter.default.post(
                                name: .insertMediaURL,
                                object: nil,
                                userInfo: ["url": selected.sourceURL, "index": idx]
                            )
                            imageInsertIndex = nil
                        }
```
Replace with:
```swift
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

- [ ] **Step 2: Update the drag-and-drop call site**

Find:
```swift
                NotificationCenter.default.post(
                    name: .insertMediaURL,
                    object: nil,
                    userInfo: ["url": media.sourceURL, "index": 0]
                )
```
Replace with:
```swift
                var info: [String: Any] = ["url": media.sourceURL, "index": 0, "mediaId": media.id]
                if let w = media.mediaDetails?.width  { info["width"]  = w }
                if let h = media.mediaDetails?.height { info["height"] = h }
                NotificationCenter.default.post(name: .insertMediaURL, object: nil, userInfo: info)
```

- [ ] **Step 3: Add `onRequestMediaSizes` to the `EditorView` call in the body**

Find the `EditorView(` instantiation in `PostEditorView.body`. It ends with:
```swift
                    onSearchLinks: { query in
                        guard let creds = appState.credentials else { return [] }
                        return try await WordPressClient(credentials: creds).searchLinks(query: query)
                    }
```
Add after that (before the closing `)`):
```swift
                    ,
                    onRequestMediaSizes: { mediaId in
                        appState.mediaItems.first(where: { $0.id == mediaId })
                    }
```

- [ ] **Step 4: Build**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh
```
Expected: compiles with no errors.

- [ ] **Step 5: Verify end-to-end**

Open `Quill.app`. Go to the Media tab so `appState.mediaItems` is populated. Open a post, insert an image from the media library via the toolbar Image button. The image should appear at its natural pixel dimensions (check by hovering over it or looking at toolbar inputs after clicking it). Click the image — if the media item has WordPress-generated sizes (e.g. thumbnail, medium), those buttons appear in the toolbar and are clickable. Clicking "Medium" swaps to the medium URL and resizes.

Also test drag-and-drop: drag an image from Finder onto the editor. After upload completes, the inserted image should show at the uploaded file's natural dimensions.

- [ ] **Step 6: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
git add Sources/QuillKit/Views/Editor/PostEditorView.swift
git commit -m "feat: pass image dimensions and mediaId on insert; wire named size lookup"
```

---

## Task 7: Final Verification Checklist

Manual smoke test before marking complete.

**Files:** none

- [ ] **Build fresh**
```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh && open Quill.app
```

- [ ] **Load existing post with sized images** — open a WordPress post whose HTML contains `<img width="..." height="...">`. Confirm the images render at those sizes, not full-width.

- [ ] **Load existing post with `wp-image-{id}` class** — if a post has images with `class="wp-image-42"`, confirm `mediaId` is parsed (named size buttons appear in toolbar after clicking).

- [ ] **Insert via media picker** — insert an image; confirm it appears at natural dimensions and the W/H inputs in the toolbar show those dimensions.

- [ ] **Insert via drag-and-drop** — drag an image from Finder; confirm it uploads, inserts, and appears at natural size.

- [ ] **Corner drag, ratio locked** — drag a corner handle; width and height scale proportionally.

- [ ] **Corner drag, Shift held** — drag a corner while holding Shift; only one axis changes.

- [ ] **Edge drag** — drag N, S, E, or W handles; only the corresponding axis changes.

- [ ] **Minimum size** — drag to try to make an image smaller than 50px in either dimension; confirm it clamps.

- [ ] **Toolbar W input** — type a new W value and press Enter; H recalculates proportionally.

- [ ] **Toolbar H input** — same for H.

- [ ] **Reset** — click Reset; image returns to unconstrained max-width behaviour, inputs clear.

- [ ] **Named sizes** — if available, click Thumb/Medium/Large/Full; image swaps URL and dimensions.

- [ ] **Save round-trip** — after resizing an image and saving, reload the post; confirm the image loads at the resized dimensions.

- [ ] **Dark mode** — toggle dark mode; handles and toolbar style correctly.

- [ ] **Mark TODO complete in CLAUDE.md**

Find in `CLAUDE.md`:
```
- [ ] Image resizing in the editor — ability to resize images inline, and respect sizes that come from WordPress
```
Replace with:
```
- [x] Image resizing in the editor — ability to resize images inline, and respect sizes that come from WordPress
```

- [ ] **Final commit**
```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
git add CLAUDE.md
git commit -m "docs: mark image resize TODO complete"
```
