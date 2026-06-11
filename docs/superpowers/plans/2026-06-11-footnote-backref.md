# Footnote Back-Reference Arrow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `↩` back-arrow at the end of each footnote entry that jumps to the corresponding marker — both as a clickable button in the Quill editor and as a working anchor link in saved WordPress HTML.

**Architecture:** Two layers. (1) `toWordPressHTML` adds `id="ref-fn-UUID"` to each marker `<sup>` and appends `<a class="footnote-backref">↩</a>` to each footnote `<li>` in saved HTML. (2) A `FootnoteItemNodeView` in `editor.html` renders a non-editable `↩` button outside the `contentDOM` (so it can never be accidentally deleted); clicking it uses ProseMirror position lookup to jump to the marker. `FootnoteItem.parseHTML` strips saved backref links before Tiptap parses content, preventing them from reappearing as editable text on reload.

**Tech Stack:** Swift 6 / SwiftUI, Tiptap 2 (local IIFE bundle), WKWebView, Node `node:test` + jsdom for JS tests.

**Spec:** `docs/superpowers/specs/2026-06-11-footnote-backref-design.md`

**Project rules that apply to every task:**
- After every resource change that affects the running app: quit Quill, `./build.sh`, reopen `Quill.app`.
- `./test.sh` runs all tests (Swift + JS). JS only: `node --test Scripts/test-editor.js`.
- Commit directly to `main` after each task.
- **Edit-tool gotcha:** when editing `Scripts/test-editor.js`, never let an Edit `old_string` span the unicode test region (~line 277, contains U+2019 as content) — the Edit tool can corrupt ASCII quote delimiters into curly quotes. Append new `describe` blocks at the END of the file. If you see `SyntaxError: Invalid or unexpected token` after an edit, fix with Python byte-level replacement, not another Edit.

---

## Task 1: backref transforms in toWordPressHTML (TDD)

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js`
- Test: `Scripts/test-editor.js` (append at end)

- [ ] **Step 1: Write the failing tests** — append at the very end of `Scripts/test-editor.js`. No change to the `require` line is needed — `toWordPressHTML` is already imported.

```js
// ---------------------------------------------------------------------------
// toWordPressHTML — footnote backrefs
// ---------------------------------------------------------------------------

describe('toWordPressHTML — footnote backrefs', () => {
  test('marker sup gains id="ref-fn-UUID"', () => {
    const html = '<p><sup data-fn="fn-a" class="fn"><a href="#fn-a"></a></sup></p>'
    assert.match(wp(html), /id="ref-fn-a"/)
  })

  test('footnote list item gains backref link', () => {
    const html = '<ol class="wp-block-footnotes"><li id="fn-a">Note</li></ol>'
    const out = wp(html)
    assert.match(out, /href="#ref-fn-a"/)
    assert.match(out, /class="footnote-backref"/)
    assert.match(out, /↩/)
  })

  test('backref is idempotent — not added twice on double transform', () => {
    const html = '<p><sup data-fn="fn-a" class="fn"><a href="#fn-a"></a></sup></p>' +
      '<ol class="wp-block-footnotes"><li id="fn-a">Note</li></ol>'
    const twice = wp(wp(html))
    assert.equal((twice.match(/footnote-backref/g) || []).length, 1)
  })
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test Scripts/test-editor.js`
Expected: 3 failures — `id="ref-fn-a"` not found, backref link not found, etc.

- [ ] **Step 3: Implement** — in `Sources/QuillKit/Resources/editor-transforms.js`, add the two new DOM operations inside `toWordPressHTML` **after** the existing footnote-numbering block (lines 121–126) and **before** the `let result = div.innerHTML` line.

Find this block:
```js
  // Footnote markers: write 1-based numbers into anchors in document order.
  // The editor leaves anchors empty (CSS counters display numbers live);
  // the saved HTML carries real text so it renders anywhere.
  div.querySelectorAll('sup.fn[data-fn] > a').forEach((a, i) => {
    a.textContent = String(i + 1)
  })
```

After it (before `let result = div.innerHTML`), add:
```js
  // Footnote backrefs: add a ref-id to each marker sup so backref hrefs have a
  // target, then append a return arrow to each list item (idempotency-guarded).
  div.querySelectorAll('sup.fn[data-fn]').forEach(sup => {
    sup.id = 'ref-' + sup.getAttribute('data-fn')
  })
  div.querySelectorAll('ol.wp-block-footnotes > li[id]').forEach(li => {
    if (li.querySelector('.footnote-backref')) return
    const a = doc.createElement('a')
    a.href = '#ref-' + li.id
    a.className = 'footnote-backref'
    a.setAttribute('aria-label', 'Back to content')
    a.textContent = '↩'
    li.appendChild(a)
  })
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test Scripts/test-editor.js`
Expected: all 92 tests pass (89 existing + 3 new)

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/Resources/editor-transforms.js Scripts/test-editor.js
git commit -m "feat: footnote backref — add ref-id to markers and return link to list items"
```

---

## Task 2: FootnoteItemNodeView, parseHTML strip, and CSS

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`

This task has no new automated tests — the NodeView and click-to-jump are editor-only behaviours verified manually.

- [ ] **Step 1: Strip backref links in `FootnoteItem.parseHTML`**

Find `FootnoteItem` (~line 1397). Its `parseHTML` currently reads:

```js
      parseHTML() {
        return [{
          tag: 'ol.wp-block-footnotes > li',
          getAttrs: el => ({ fnId: el.getAttribute('id') }),
        }]
      },
```

Replace it with:

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

`getAttrs` runs before Tiptap recurses into children, so removing the backref here prevents it from appearing as editable text when a saved post is reopened.

- [ ] **Step 2: Add `FootnoteItemNodeView` class**

Find the `FootnoteItem` definition and its closing `})` (~line 1414). After that closing `})` and before the `FootnoteSync` comment block, add:

```js
    class FootnoteItemNodeView {
      constructor(node, editor, getPos) {
        this.node = node
        this.editor = editor

        this.dom = document.createElement('li')
        this.dom.id = node.attrs.fnId || ''

        this.contentDOM = document.createElement('span')
        this.contentDOM.className = 'fn-item-content'

        this.backArrow = document.createElement('a')
        this.backArrow.className = 'fn-backref'
        this.backArrow.textContent = '↩'
        this.backArrow.setAttribute('aria-label', 'Back to content')
        this.backArrow.addEventListener('mousedown', e => {
          e.preventDefault()
          const fnId = this.node.attrs.fnId
          let markerPos = null
          let markerSize = 0
          this.editor.state.doc.descendants((n, pos) => {
            if (n.type.name === 'footnoteMarker' && n.attrs.fnId === fnId) {
              markerPos = pos
              markerSize = n.nodeSize
              return false
            }
            return true
          })
          if (markerPos !== null) {
            this.editor.chain().focus().setTextSelection(markerPos + markerSize).scrollIntoView().run()
          }
        })

        this.dom.appendChild(this.contentDOM)
        this.dom.appendChild(this.backArrow)
      }

      update(node) {
        if (node.type !== this.node.type) return false
        this.node = node
        this.dom.id = node.attrs.fnId || ''
        return true
      }

      stopEvent(event) {
        return event.target === this.backArrow
      }

      ignoreMutation(mutation) {
        return mutation.target === this.backArrow ||
          this.backArrow.contains(mutation.target)
      }
    }
```

- [ ] **Step 3: Register `addNodeView()` on `FootnoteItem`**

Inside `FootnoteItem`, after the `renderHTML` method and before the closing `})`, add:

```js
      addNodeView() {
        return ({ node, editor, getPos }) => new FootnoteItemNodeView(node, editor, getPos)
      },
```

The `FootnoteItem` block should now end like this:
```js
      renderHTML({ node }) {
        return ['li', { id: node.attrs.fnId }, 0]
      },
      addNodeView() {
        return ({ node, editor, getPos }) => new FootnoteItemNodeView(node, editor, getPos)
      },
    })
```

- [ ] **Step 4: Add CSS**

Find the footnotes CSS section (~line 719):
```css
    body.dark ol.wp-block-footnotes { border-top-color: rgba(255,255,255,0.2); color: #aaa; }
```

After that line, add:
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

- [ ] **Step 5: Run tests**

Run: `./test.sh`
Expected: all 233 Swift + 92 JS tests pass (no new automated tests for this task)

- [ ] **Step 6: Build and verify manually**

Run: `./build.sh && open Quill.app`

Verify:
1. Open a post with existing footnotes → each entry ends with a faded amber `↩`; hovering brightens it
2. Click `↩` on a footnote entry → editor scrolls to and focuses the corresponding marker in the content
3. With multiple footnotes → each `↩` jumps to its own marker (not always the first)
4. Insert a new footnote (toolbar or context menu) → the new entry immediately shows `↩`
5. Open code view (`</>`) → the `<sup>` marker has `id="ref-fn-UUID"`, the `<li>` ends with `<a href="#ref-fn-UUID" class="footnote-backref" aria-label="Back to content">↩</a>`
6. Save the post → open on the live WordPress site → `↩` links work as standard anchor navigation, clicking them scrolls to the corresponding superscript marker in the text
7. Reopen the post in Quill → `↩` arrows appear correctly in the editor; no duplicate arrows; no stray `↩` text inside the editable footnote content

- [ ] **Step 7: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html
git commit -m "feat: footnote back-arrow — NodeView button in editor, anchor link in saved HTML"
```
