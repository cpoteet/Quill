# Blockquote Citation (`<cite>`) Support

**Date:** 2026-05-29
**Status:** Approved

## Overview

Add `<cite>` attribution support to blockquotes in the Tiptap editor. When a blockquote is inserted via the toolbar, an empty cite line is automatically appended. The cite line is visually subdued and right-aligned. If left empty, it is omitted from saved HTML. The round-trip with WordPress/Gutenberg is lossless.

## Tiptap model

### `Cite` node

A new Tiptap node defined in `editor.html`:

- `name: 'cite'`
- `content: 'inline*'` — contains inline text and marks, same shape as a paragraph
- No `group` — not a generic block node; only the extended Blockquote schema can contain it
- `parseHTML`: `[{ tag: 'cite' }]` — loads existing WordPress blockquotes with `<cite>` correctly
- `renderHTML`: `['cite', {}, 0]` — outputs `<cite>text</cite>`, already correct Gutenberg HTML

**Keyboard shortcuts** on the `Cite` node:
- **Enter**: exit the blockquote and insert a new paragraph after it
- **Backspace** (when cite is empty): delete the cite node, move cursor to end of last paragraph in blockquote

### Extended `Blockquote`

Override the default Tiptap `Blockquote` extension's content model:

- Before: `content: 'block+'`
- After: `content: 'block+ cite?'`

This allows one or more block nodes followed by an optional single cite node. Because `cite` has no `group`, it cannot appear anywhere else `block` is accepted.

## Toolbar behavior

The `blockquote` command in the toolbar's command dispatch table is updated:

- **Toggle off** (cursor is inside a blockquote): `toggleBlockquote()` — unchanged behavior
- **Toggle on** (cursor is not in a blockquote): `toggleBlockquote()` followed by a chained ProseMirror transaction that walks up from the cursor to locate the newly created blockquote node and inserts an empty `cite` node at its end

The cursor remains in the quote text after insertion — the cite line is available but the user is not auto-jumped to it.

**Loading existing posts:**
- Blockquotes loaded from WordPress that already contain `<cite>` are parsed correctly by the `Cite` node's `parseHTML` rule — no special loading path needed.
- Blockquotes without a `<cite>` (older posts) load without a cite node. No cite is injected on load.

## CSS

Added to `editor.html` alongside existing blockquote styles:

```css
.ProseMirror blockquote cite {
  display: block;
  font-style: normal;
  font-size: 0.85em;
  color: #999;
  text-align: right;
  margin-top: 0.5em;
}
body.dark .ProseMirror blockquote cite { color: #666; }
```

## HTML output

`toWordPressHTML()` gets one addition — strip empty cite elements before saving:

```javascript
div.querySelectorAll('blockquote cite').forEach(el => {
  if (!el.textContent.trim()) el.remove()
})
```

When the cite has content, the saved HTML matches Gutenberg's expected format exactly:

```html
<blockquote class="wp-block-quote">
  <p>The quote text.</p>
  <cite>— Source Name</cite>
</blockquote>
```

No other changes to `toWordPressHTML()` are needed — the `wp-block-quote` class is already added to `blockquote` elements, and `<cite>` is already the correct element name.

## Scope

All changes are contained in `Sources/QuillKit/Resources/editor.html`. No Swift changes required.
