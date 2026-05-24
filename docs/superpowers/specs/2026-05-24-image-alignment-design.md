# Image Alignment with Text Wrap

**Date:** 2026-05-24  
**Status:** Approved

## Overview

Add left, center, and right alignment buttons to the main editor toolbar so users can float images and have text wrap around them. Alignment state is parsed from WordPress/Gutenberg content on load and round-tripped back to Gutenberg-format HTML (`<figure class="wp-block-image alignXXX">`) on save.

---

## Approach

Approach A: extend the existing `ResizableImage` Tiptap extension with an `alignment` attribute, add a `toWordPressHTML()` JS post-processor that wraps aligned images in Gutenberg `<figure>` tags on output, and add three alignment buttons to the main editor toolbar.

(Approach C — a figure-first `WPImage` Tiptap node — is documented in CLAUDE.md as a future architectural option.)

---

## Feature: alignment attribute

### New attribute

Add `alignment` to `ResizableImage.addAttributes()`:
- Type: `string | null`
- Default: `null`
- Values: `"left"`, `"center"`, `"right"`, `null`

### parseHTML — two rules

**Rule 1 — Gutenberg `<figure>`** (new):
```
tag: 'figure.wp-block-image'
getAttrs: el => {
  const img = el.querySelector('img')
  if (!img) return false
  return {
    src:       img.getAttribute('src'),
    alt:       img.getAttribute('alt') ?? null,
    title:     img.getAttribute('title') ?? null,
    width:     parseInt(img.getAttribute('width')) || null,
    height:    parseInt(img.getAttribute('height')) || null,
    mediaId:   (parseInt(img.getAttribute('data-media-id'))
                || parseInt((img.className.match(/wp-image-(\d+)/) ?? [])[1]))
               || null,
    alignment: extractAlignment(el.className),  // reads alignleft/right/center from figure
  }
}
```

`extractAlignment(cls)` returns `"left"` | `"right"` | `"center"` | `null`:
```js
function extractAlignment(cls) {
  if (cls.includes('alignleft'))   return 'left'
  if (cls.includes('alignright'))  return 'right'
  if (cls.includes('aligncenter')) return 'center'
  return null
}
```

**Rule 2 — classic `<img>`** (existing rule, extended):
```
tag: 'img[src]'
getAttrs: el => ({
  ...existingAttrs,
  alignment: extractAlignment(el.className),  // reads alignleft/right/center from img class
})
```

The figure rule must be listed first so it is tried before the img rule; otherwise the inner `<img>` would match rule 2 before rule 1 consumes the figure.

### renderHTML

Emit `class="alignXXX"` on the `<img>` when alignment is set:
```
renderHTML: attrs =>
  attrs.alignment ? { class: `align${attrs.alignment}` } : {}
```

Tiptap merges this with any existing class attrs. Internal representation stays as `<img class="alignleft ...">` (classic format); the postprocessor converts to Gutenberg figures on output.

---

## Feature: visual rendering in the editor

`ImageNodeView._applyAttrs()` reads `attrs.alignment` and toggles CSS classes on `this.wrapper`:

| alignment | CSS class     | Effect                                      |
|-----------|---------------|---------------------------------------------|
| `"left"`  | `align-left`  | `float: left; margin: 0 1em 0.5em 0`        |
| `"right"` | `align-right` | `float: right; margin: 0 0 0.5em 1em`       |
| `"center"`| `align-center`| `display: block; margin: 0 auto; width: fit-content` |
| `null`    | _(none)_      | default `inline-block`, no float            |

The image node is `inline: false` (a ProseMirror block node sitting as a sibling of paragraph nodes). CSS `float` applied to the wrapper causes adjacent paragraph text to flow around it — standard behavior across sibling block elements in the same formatting context. No content-model changes are needed.

New CSS rules added to `editor.html`:
```css
.image-wrapper.align-left  { float: left;  display: block; margin: 0 1em 0.5em 0; }
.image-wrapper.align-right { float: right; display: block; margin: 0 0 0.5em 1em; }
.image-wrapper.align-center { display: block; margin: 0 auto; width: fit-content; }
```

---

## Feature: HTML postprocessor

A `toWordPressHTML(html)` function runs after every `editor.getHTML()` call before the string is sent to Swift.

Algorithm:
1. Parse the HTML string into a temporary DOM div
2. For each `<img class="alignleft/right/center ...">`:
   a. Determine the alignment class
   b. Create `<figure class="wp-block-image alignXXX">`
   c. Remove the alignment class from the `<img>`
   d. Insert the figure before the img in the DOM, then move the img inside it
3. Return `div.innerHTML`

Non-aligned images pass through unchanged. No regex — pure DOM operations.

Wired into:
- `window.getContent = () => toWordPressHTML(editor.getHTML())`
- The `contentChanged` debounce: `postMessage(toWordPressHTML(editor.getHTML()))`

---

## Feature: alignment buttons in the main toolbar

### Placement

Added to `#toolbar` in `editor.html` alongside existing controls. The buttons are wrapped in a `<span id="image-align-controls">` (mirroring the existing `<span id="table-controls">`). This span is hidden by default and shown only when an image node is selected, following the exact same show/hide pattern as table controls.

### HTML
```html
<span id="image-align-controls" style="display:none">
  <button data-cmd="alignLeft"   title="Float image left (text wraps right)">&#8678; Left</button>
  <button data-cmd="alignCenter" title="Center image">Center</button>
  <button data-cmd="alignRight"  title="Float image right (text wraps left)">Right &#8680;</button>
</span>
```

Unicode: `⇦` (U+21E6) for left, `⇨` (U+21E8) for right.

### Active state

When `updateToolbar()` runs and an image is selected, the button matching the current `alignment` attr gets the `.active` class. All three buttons are cleared first, then the active one is set. When no image is selected, all three are cleared and the span is hidden.

### Commands

Added to the `COMMANDS` map:
```js
alignLeft:   () => setImageAlignment('left'),
alignCenter: () => setImageAlignment('center'),
alignRight:  () => setImageAlignment('right'),
```

`setImageAlignment(value)` helper:
1. Get the current selection from `editor.state`
2. Walk the selection to find a selected image node and its position
3. If the current alignment equals `value`, set `null` (toggle off); otherwise set `value`
4. Commit via `state.tr.setNodeMarkup(pos, null, { ...node.attrs, alignment: newValue })`

This follows the same `setNodeMarkup` pattern used for image resize commits.

---

## Show/hide logic in `updateToolbar()`

`updateToolbar()` already handles `#table-controls` show/hide. Extend it to also handle `#image-align-controls`:

```js
// Find selected image node
let selectedImageNode = null
const { selection } = editor.state
if (selection.node?.type.name === 'image') {
  selectedImageNode = selection.node
}

const alignControls = document.getElementById('image-align-controls')
if (selectedImageNode) {
  alignControls.style.display = 'inline-flex'
  const align = selectedImageNode.attrs.alignment
  // Map alignment value to data-cmd string
  const alignCmdMap = { left: 'alignLeft', center: 'alignCenter', right: 'alignRight' }
  document.querySelectorAll('#image-align-controls button').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.cmd === alignCmdMap[align])
  })
} else {
  alignControls.style.display = 'none'
}
```

---

## Files changed

All changes are in a single file: `Sources/QuillKit/Resources/editor.html`

1. **CSS** — three `.image-wrapper.align-*` rules
2. **Toolbar HTML** — `#image-align-controls` span with three buttons
3. **`ResizableImage.addAttributes()`** — add `alignment` attr with parseHTML/renderHTML
4. **`ResizableImage.parseHTML()`** — figure rule (first) + extended img rule
5. **`ImageNodeView._applyAttrs()`** — apply/clear alignment classes
6. **`COMMANDS` map** — three align commands wiring to `setImageAlignment()`
7. **`setImageAlignment()` helper** — new function
8. **`toWordPressHTML()` helper** — new function
9. **`window.getContent`** — wrap with `toWordPressHTML`
10. **`contentChanged` debounce** — wrap with `toWordPressHTML`
11. **`updateToolbar()`** — image-align-controls show/hide + active state sync

No Swift files are changed.
