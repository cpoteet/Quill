# Footnote Back-Reference Arrow — Design Spec

**Date:** 2026-06-11
**Status:** Approved

## Goal

Add a `↩` back-arrow at the end of each footnote entry so users can return to the corresponding marker in the content. Works in two contexts:

- **Quill editor** — clickable arrow jumps to the marker in the document
- **Published WordPress site** — standard anchor link in the saved HTML

---

## What is not changing

- Node types (`FootnoteMarker`, `FootnotesList`, `FootnoteItem`) — no new attrs
- `FootnoteSync` — no changes
- The `fnId` UUID stays the sole identifier linking markers to entries

---

## Changes

### 1. `toWordPressHTML` — editor-transforms.js

Two new DOM operations added **after** the existing footnote-numbering step (`sup.fn[data-fn] > a` textContent assignment):

**Step A — Add `id` to each marker `<sup>`:**
```js
div.querySelectorAll('sup.fn[data-fn]').forEach(sup => {
  sup.id = 'ref-' + sup.getAttribute('data-fn')
})
```

**Step B — Append backref link to each footnote list item:**
```js
div.querySelectorAll('ol.wp-block-footnotes > li[id]').forEach(li => {
  if (li.querySelector('.footnote-backref')) return  // idempotency guard
  const a = document.createElement('a')
  a.href = '#ref-' + li.id
  a.className = 'footnote-backref'
  a.setAttribute('aria-label', 'Back to content')
  a.textContent = '↩'
  li.appendChild(a)
})
```

**Resulting saved HTML example:**
```html
<sup id="ref-fn-a" data-fn="fn-a" class="fn"><a href="#fn-a">1</a></sup>
…
<ol class="wp-block-footnotes">
  <li id="fn-a">Note text <a href="#ref-fn-a" class="footnote-backref" aria-label="Back to content">↩</a></li>
</ol>
```

**Idempotency:** The `li.querySelector('.footnote-backref')` guard prevents double-appending when `toWordPressHTML` is called more than once (autosave, code-view exit). Setting `sup.id` twice is safe — it overwrites with the same value.

---

### 2. `FootnoteMarker` — no parseHTML change needed

The `id="ref-fn-UUID"` attribute added to `<sup>` by `toWordPressHTML` is silently ignored on load. `FootnoteMarker.parseHTML` matches `sup.fn[data-fn]` and only reads `data-fn` into `fnId`. Since `id` is not declared in `addAttributes()`, Tiptap discards it. No change needed.

---

### 3. `FootnoteItem.parseHTML` — editor.html

Strip `.footnote-backref` links from each `<li>` before Tiptap parses its children. This prevents saved backrefs from reappearing as editable text when a post is reopened.

```js
parseHTML() {
  return [{
    tag: 'ol.wp-block-footnotes > li',
    getAttrs: el => {
      el.querySelectorAll('.footnote-backref').forEach(a => a.remove())
      return { fnId: el.getAttribute('id') }
    },
  }]
},
```

`getAttrs` runs before Tiptap recursively parses children, so the mutation takes effect.

---

### 4. `FootnoteItemNodeView` — editor.html

A plain JS class (same pattern as `EmbedNodeView`). Replaces the default `renderHTML` serialization in the live editor DOM.

**DOM structure:**
```
<li id="fn-UUID">           ← this.dom
  <span class="fn-item-content">  ← this.contentDOM (Tiptap writes here)
    [user's typed text]
  </span>
  <a class="fn-backref" title="Back to text">↩</a>  ← non-editable
</li>
```

**Interface:**

| Method | Behaviour |
|---|---|
| `constructor(node, editor, getPos)` | Build DOM, wire `mousedown` on arrow |
| `update(node)` | Sync `this.dom.id` if `fnId` changes; return `false` if node type differs |
| `stopEvent(e)` | Return `true` when `e.target === this.backArrow` — prevents ProseMirror stealing the click |
| `ignoreMutation(m)` | Return `true` when mutation target is the arrow or its descendants |

**Click handler (`mousedown` on `this.backArrow`):**
1. `e.preventDefault()`
2. Walk `editor.state.doc.descendants` to find the `footnoteMarker` whose `fnId` matches
3. `editor.chain().focus().setTextSelection(markerPos).scrollIntoView().run()`

`mousedown` is used (not `click`) so the editor does not lose focus before the command fires — consistent with the existing `btn-footnote` toolbar handler.

**Registration:** Add `addNodeView() { return ({ node, editor, getPos }) => new FootnoteItemNodeView(node, editor, getPos) }` to `FootnoteItem`.

---

### 5. CSS — editor.html `<style>` block

Add to the existing Footnotes section:

```css
.fn-backref {
  color: #b45309;
  text-decoration: none;
  margin-left: 0.35em;
  font-size: 0.85em;
  cursor: pointer;
  opacity: 0.65;
  user-select: none;
}
.fn-backref:hover { opacity: 1; }
body.dark .fn-backref { color: #d97706; }
```

---

## Tests

### New JS tests — `Scripts/test-editor.js`

Append a new `describe('toWordPressHTML — footnote backrefs', ...)` block:

| Test | Input | Assertion |
|---|---|---|
| Marker gains `id="ref-fn-UUID"` | `<sup data-fn="fn-a" class="fn">…</sup>` | output contains `id="ref-fn-a"` |
| List item gains backref link | `<li id="fn-a">Note</li>` in footnotes ol | output contains `<a href="#ref-fn-a" class="footnote-backref"` and `↩` |
| Idempotent — no double backref | Full round-trip HTML run through `wp()` twice | exactly one `.footnote-backref` in output |

### Manual verification

- Insert a footnote → type text in the entry → amber `↩` appears after the text, fades slightly, brightens on hover
- Click `↩` → editor jumps to and focuses the corresponding marker
- Multiple footnotes → each `↩` jumps to its own marker (not always the first)
- Code view → HTML shows `id="ref-fn-a"` on the `<sup>` and `<a class="footnote-backref" href="#ref-fn-a">↩</a>` on the `<li>`
- Save → open post on live WordPress site → `↩` links work as standard anchor navigation
- Reopen post in Quill → `↩` arrows still appear correctly, no duplicate arrows, no stray `↩` text in footnote content

---

## Out of scope

- Caption editing on embeds (separate future feature)
- Footnote `↩` keyboard shortcut
- Custom arrow character/label (amber `↩` is fixed for v1)
