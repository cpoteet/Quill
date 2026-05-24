# Image Alignment with Text Wrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add left/center/right image alignment buttons to the main editor toolbar so text wraps around floated images, with clean round-trip to Gutenberg-format WordPress HTML.

**Architecture:** Extend the existing `ResizableImage` Tiptap extension with an `alignment` attribute that parses from both Gutenberg `<figure class="wp-block-image alignXXX">` and classic `<img class="alignXXX">` on load. A `toWordPressHTML()` post-processor re-wraps aligned images back into Gutenberg figures on every save/content-change event. Three toolbar buttons (Left, Center, Right) appear in the main toolbar only when an image node is selected — same show/hide pattern as the existing table controls.

**Tech Stack:** Tiptap 2.x (ResizableImage extension, ProseMirror NodeSelection), vanilla JS DOM, single file edit (`editor.html`). No Swift changes.

---

## File map

**Only one file changes:** `Sources/QuillKit/Resources/editor.html`

Sections touched:
- CSS block (~line 120): add `.image-wrapper.align-*` rules
- `#toolbar` HTML (~line 313): add `#image-align-controls` span
- `ResizableImage` extension (~line 543): add `alignment` attr + override `parseHTML()`
- `ImageNodeView._applyAttrs()` (~line 372): apply alignment CSS class to wrapper
- `COMMANDS` map (~line 607): add `alignLeft/Center/Right` entries
- `updateToolbar()` (~line 692): show/hide controls, set active state
- `contentChanged` debounce (~line 712): wrap with `toWordPressHTML`
- `window.getContent` (~line 726): wrap with `toWordPressHTML`

---

## Task 1: CSS alignment rules + toolbar HTML

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`

- [ ] **Step 1: Add CSS rules for aligned image wrappers**

Find this comment block in the CSS section (around line 121):
```css
    /* ── Image NodeView ─────────────────────────────── */
    .image-wrapper {
```

Insert these three rules immediately after the `.image-wrapper.selected .resize-handle` block (after line ~147):
```css
    .image-wrapper.align-left   { float: left;  display: block; margin: 0 1em 0.5em 0; }
    .image-wrapper.align-right  { float: right; display: block; margin: 0 0 0.5em 1em; }
    .image-wrapper.align-center { display: block; margin: 0 auto; width: fit-content; }
```

- [ ] **Step 2: Add image-align-controls span to the toolbar HTML**

Find this section in `#toolbar` (around line 312–313):
```html
    <button data-cmd="link"  title="Insert / remove link">&#128279; Link</button>
    <button data-cmd="image" title="Insert image from media library">&#128444; Image</button>
```

Insert the controls span immediately after the Image button:
```html
    <button data-cmd="link"  title="Insert / remove link">&#128279; Link</button>
    <button data-cmd="image" title="Insert image from media library">&#128444; Image</button>
    <span id="image-align-controls" style="display:none">
      <button data-cmd="alignLeft"   title="Float image left (text wraps right)">&#8678; Left</button>
      <button data-cmd="alignCenter" title="Center image">Center</button>
      <button data-cmd="alignRight"  title="Float image right (text wraps left)">Right &#8680;</button>
    </span>
```

`&#8678;` is ⇦, `&#8680;` is ⇨.

- [ ] **Step 3: Build and verify**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh && open Quill.app
```

Open a post. The three new buttons should NOT be visible yet (the span is `display:none`). Inspect the page source in a WebKit inspector to confirm the span is in the DOM.

- [ ] **Step 4: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
git add Sources/QuillKit/Resources/editor.html
git commit -m "feat(editor): add CSS alignment rules and toolbar HTML for image alignment"
```

---

## Task 2: alignment attribute + figure parseHTML + _applyAttrs

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`

- [ ] **Step 1: Add extractAlignment helper function**

Find this comment (around line 543):
```js
    // ── ResizableImage extension ──────────────────────
```

Insert `extractAlignment` immediately before it:
```js
    function extractAlignment(cls) {
      if (cls.includes('alignleft'))   return 'left'
      if (cls.includes('alignright'))  return 'right'
      if (cls.includes('aligncenter')) return 'center'
      return null
    }

    // ── ResizableImage extension ──────────────────────
```

- [ ] **Step 2: Add alignment to ResizableImage.addAttributes()**

Find the `mediaId` attribute block (ends around line 573) and add `alignment` after it, before the closing `}` of the `addAttributes` return:
```js
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
          alignment: {
            default: null,
            parseHTML: el => extractAlignment(el.getAttribute('class') || ''),
            renderHTML: attrs => attrs.alignment ? { class: `align${attrs.alignment}` } : {},
          },
```

- [ ] **Step 3: Override parseHTML() on ResizableImage to add the Gutenberg figure rule**

Find `addNodeView()` (around line 576) and insert `parseHTML()` immediately before it:
```js
      parseHTML() {
        return [
          {
            tag: 'figure.wp-block-image',
            getAttrs: el => {
              const img = el.querySelector('img')
              if (!img) return false
              const dataId = img.getAttribute('data-media-id')
              const clsMatch = (img.getAttribute('class') || '').match(/wp-image-(\d+)/)
              return {
                src:       img.getAttribute('src'),
                alt:       img.getAttribute('alt') ?? null,
                title:     img.getAttribute('title') ?? null,
                width:     parseInt(img.getAttribute('width'), 10) || null,
                height:    parseInt(img.getAttribute('height'), 10) || null,
                mediaId:   dataId ? parseInt(dataId, 10)
                                  : (clsMatch ? parseInt(clsMatch[1], 10) : null),
                alignment: extractAlignment(el.getAttribute('class') || ''),
              }
            },
          },
          { tag: 'img[src]' },
        ]
      },
      addNodeView() {
```

The figure rule is listed first. Its `getAttrs` extracts all attrs from the figure + inner img in one pass, so Tiptap uses that object directly (per-attribute `parseHTML` is bypassed for this rule). The `{ tag: 'img[src]' }` rule has no `getAttrs`, so Tiptap calls each attribute's `parseHTML(el)` individually — including the new `alignment` attribute which reads `alignleft/right/center` from the img's class.

- [ ] **Step 4: Update ImageNodeView._applyAttrs() to apply alignment CSS class**

Find the full `_applyAttrs` method (around line 372). Replace it entirely:
```js
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
        // Alignment
        this.wrapper.classList.remove('align-left', 'align-right', 'align-center')
        if (attrs.alignment) this.wrapper.classList.add(`align-${attrs.alignment}`)
      }
```

- [ ] **Step 5: Build and verify parsing**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh && open Quill.app
```

Test 1 — Load a WordPress post that contains a Gutenberg aligned image. The HTML from WordPress looks like:
```html
<figure class="wp-block-image alignleft"><img src="..." width="300" height="200" class="wp-image-42"/></figure>
```
Expected: The image renders floated to the left in the editor, with text wrapping around it.

Test 2 — Load a post with a classic aligned image:
```html
<img class="alignright wp-image-42" src="..." width="300" height="200"/>
```
Expected: The image renders floated to the right.

Test 3 — Load a post with an unaligned image. Expected: No float, image renders normally.

- [ ] **Step 6: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
git add Sources/QuillKit/Resources/editor.html
git commit -m "feat(editor): add alignment attr to ResizableImage — parses Gutenberg figures and classic img classes"
```

---

## Task 3: setImageAlignment command + toolbar show/hide + active state

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`

- [ ] **Step 1: Add setImageAlignment helper**

Find the `COMMANDS` map (around line 607, starts with `const COMMANDS = {`). Insert the helper function immediately before it:
```js
    function setImageAlignment(value) {
      const { state } = editor
      const node = state.selection.node
      if (!node || node.type.name !== 'image') return
      const pos = state.selection.from
      const newAlignment = node.attrs.alignment === value ? null : value
      editor.view.dispatch(
        state.tr.setNodeMarkup(pos, null, { ...node.attrs, alignment: newAlignment })
      )
      editor.view.focus()
    }

    const COMMANDS = {
```

- [ ] **Step 2: Add align commands to the COMMANDS map**

Find the `image:` entry in COMMANDS (around line 668):
```js
      image: () => {
        if (window.webkit?.messageHandlers?.insertImageAtIndex) {
          window.webkit.messageHandlers.insertImageAtIndex.postMessage(0)
        }
      },
    }
```

Add the three alignment commands before the closing `}`:
```js
      image: () => {
        if (window.webkit?.messageHandlers?.insertImageAtIndex) {
          window.webkit.messageHandlers.insertImageAtIndex.postMessage(0)
        }
      },
      alignLeft:   () => setImageAlignment('left'),
      alignCenter: () => setImageAlignment('center'),
      alignRight:  () => setImageAlignment('right'),
    }
```

- [ ] **Step 3: Extend updateToolbar() to handle image-align-controls**

Find the end of `updateToolbar()` (around line 707–709):
```js
      // Undo / Redo
      document.querySelector('[data-cmd="undo"]').disabled = !editor.can().undo()
      document.querySelector('[data-cmd="redo"]').disabled = !editor.can().redo()
    }
```

Insert the image alignment block before the closing `}`:
```js
      // Undo / Redo
      document.querySelector('[data-cmd="undo"]').disabled = !editor.can().undo()
      document.querySelector('[data-cmd="redo"]').disabled = !editor.can().redo()
      // Image alignment controls
      const selNode = editor.state.selection.node
      const selectedImage = selNode?.type.name === 'image' ? selNode : null
      const alignControls = document.getElementById('image-align-controls')
      if (selectedImage) {
        alignControls.style.display = 'contents'
        const alignCmdMap = { left: 'alignLeft', center: 'alignCenter', right: 'alignRight' }
        document.querySelectorAll('#image-align-controls button').forEach(btn => {
          btn.classList.toggle('active', btn.dataset.cmd === alignCmdMap[selectedImage.attrs.alignment])
        })
      } else {
        alignControls.style.display = 'none'
        document.querySelectorAll('#image-align-controls button').forEach(btn => {
          btn.classList.remove('active')
        })
      }
    }
```

`display: 'contents'` makes the `<span>` invisible to the flex layout so its buttons join `#toolbar`'s flex container directly — the same approach used by `#table-controls`.

- [ ] **Step 4: Build and verify toolbar buttons**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh && open Quill.app
```

Test 1 — Click anywhere in body text. Expected: alignment buttons are hidden.

Test 2 — Click an image. Expected: "⇦ Left", "Center", "Right ⇨" buttons appear in the toolbar.

Test 3 — With an image selected, click "⇦ Left". Expected: image floats left, "⇦ Left" button gets the `.active` style (blue background, matching other active toolbar buttons). Body text after the image should wrap around it.

Test 4 — With left-aligned image selected, click "⇦ Left" again. Expected: alignment toggles off, image returns to default inline layout.

Test 5 — Click "Center". Expected: image is centered with `margin: 0 auto`, no float. "Center" button shows active.

Test 6 — Click "Right ⇨". Expected: image floats right, text wraps to its left.

Test 7 — Undo (⌘Z). Expected: alignment reverts one step.

- [ ] **Step 5: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
git add Sources/QuillKit/Resources/editor.html
git commit -m "feat(editor): add alignment toolbar buttons with show/hide and active-state sync"
```

---

## Task 4: toWordPressHTML postprocessor — Gutenberg output

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`

- [ ] **Step 1: Add toWordPressHTML helper**

Find the `// ── Content change → Swift` comment (around line 711). Insert the helper immediately before it:
```js
    function toWordPressHTML(html) {
      const div = document.createElement('div')
      div.innerHTML = html
      div.querySelectorAll('img.alignleft, img.alignright, img.aligncenter').forEach(img => {
        const align = ['alignleft', 'alignright', 'aligncenter']
          .find(c => img.classList.contains(c))
        if (!align) return
        const figure = document.createElement('figure')
        figure.className = `wp-block-image ${align}`
        img.classList.remove('alignleft', 'alignright', 'aligncenter')
        img.parentNode.insertBefore(figure, img)
        figure.appendChild(img)
      })
      return div.innerHTML
    }

    // ── Content change → Swift ─────────────────────────
```

- [ ] **Step 2: Wire toWordPressHTML into the contentChanged debounce**

Find the debounce (around line 716):
```js
        window.webkit.messageHandlers.contentChanged.postMessage(editor.getHTML())
```

Replace with:
```js
        window.webkit.messageHandlers.contentChanged.postMessage(toWordPressHTML(editor.getHTML()))
```

- [ ] **Step 3: Wire toWordPressHTML into window.getContent**

Find (around line 726):
```js
    window.getContent = () => editor.getHTML()
```

Replace with:
```js
    window.getContent = () => toWordPressHTML(editor.getHTML())
```

- [ ] **Step 4: Build and verify the full round-trip**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh && open Quill.app
```

Test 1 — Open a post with no aligned images. Float an image left. Save (⌘S). Open the post in WordPress admin and verify the image is wrapped in:
```html
<figure class="wp-block-image alignleft"><img src="..." ...></figure>
```

Test 2 — Open that same post back in Quill. Verify the image is still floated left (alignment round-tripped correctly from the figure class).

Test 3 — Open a post with a Gutenberg right-aligned image already in WordPress. Verify it loads with the image floated right in Quill, and after save the Gutenberg figure structure is preserved.

Test 4 — Center an image and save. Verify the saved HTML is `<figure class="wp-block-image aligncenter"><img ...></figure>`.

Test 5 — Remove alignment from an image (toggle active button off) and save. Verify no `<figure>` wrapper is emitted — the img appears as a plain `<img ...>` without any alignment class.

- [ ] **Step 5: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
git add Sources/QuillKit/Resources/editor.html
git commit -m "feat(editor): add toWordPressHTML postprocessor for Gutenberg figure output on save"
```

---

## Self-review notes

- All 11 spec items have a corresponding implementation step.
- `extractAlignment` is defined before `ResizableImage` (Task 2 Step 1) so it's in scope for both the extension's `parseHTML` and `addAttributes`.
- `setImageAlignment` toggles off when the active value is clicked again (null branch). This matches standard toolbar toggle behavior.
- The figure `parseHTML` rule is listed first in the returned array, ensuring Gutenberg content is matched before the fallback `img[src]` rule tries to match the inner img. ProseMirror's DOMParser applies rules in order and the figure rule has `getAttrs` returning a full object, consuming the element.
- `display: 'contents'` on `#image-align-controls` matches the existing `#table-controls` pattern so buttons integrate seamlessly into the flex toolbar.
- `toWordPressHTML` uses DOM operations (not regex) so it handles nested markup safely.
- No Swift files are changed.
