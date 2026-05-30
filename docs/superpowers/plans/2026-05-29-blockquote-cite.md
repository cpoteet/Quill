# Blockquote Citation (`<cite>`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `<cite>` attribution line that auto-appears when a blockquote is inserted, is visually subdued/right-aligned, omitted from saved HTML when empty, and round-trips correctly with WordPress/Gutenberg.

**Architecture:** A new `Cite` Tiptap node (created via `TiptapNode.create`) lives as the optional last child of a custom `Blockquote` extension whose content model is `block+ cite?`. The toolbar blockquote command inserts an empty cite node on toggle-on. `toWordPressHTML()` strips empty cite elements before saving.

**Tech Stack:** Tiptap 2.x (IIFE bundle), ProseMirror, editor.html (all changes in one file + bundle script)

---

### Task 1: Add `TiptapNode` and `Blockquote` exports to the bundle

`Node` from `@tiptap/core` is needed to define new Tiptap nodes. It isn't currently exported from `tiptap-bundle.js`. It must be aliased as `TiptapNode` to avoid shadowing the browser's global `window.Node` (used elsewhere in editor.html as `Node.TEXT_NODE`). The Blockquote extension from `@tiptap/extension-blockquote` is needed so we can extend its default implementation rather than rewriting it from scratch.

**Files:**
- Modify: `Scripts/bundle-tiptap.sh`
- Modify (generated): `Sources/QuillKit/Resources/tiptap-bundle.js` (via rebuild)

- [ ] **Step 1: Add `@tiptap/extension-blockquote` to the bundle's package.json block and export `TiptapNode` and `Blockquote` from entry.js**

In `Scripts/bundle-tiptap.sh`, find the `package.json` heredoc and add the blockquote package, then add two lines to `entry.js`:

```bash
# In the package.json block, add after "@tiptap/extension-placeholder":
"@tiptap/extension-blockquote": "^2",
```

The full updated `entry.js` heredoc in the script should read:

```javascript
export { Editor, Extension }           from '@tiptap/core'
export { Node as TiptapNode }          from '@tiptap/core'
export { default as StarterKit }       from '@tiptap/starter-kit'
export { default as Underline }        from '@tiptap/extension-underline'
export { default as Table }            from '@tiptap/extension-table'
export { default as TableRow }         from '@tiptap/extension-table-row'
export { default as TableCell }        from '@tiptap/extension-table-cell'
export { default as TableHeader }      from '@tiptap/extension-table-header'
export { Image as TiptapImage }        from '@tiptap/extension-image'
export { default as Blockquote }       from '@tiptap/extension-blockquote'
export { default as Link }             from '@tiptap/extension-link'
export { default as TaskList }         from '@tiptap/extension-task-list'
export { default as TaskItem }         from '@tiptap/extension-task-item'
export { default as Placeholder }      from '@tiptap/extension-placeholder'
export { Plugin, PluginKey }           from '@tiptap/pm/state'
export { DecorationSet, Decoration }   from '@tiptap/pm/view'
```

- [ ] **Step 2: Rebuild the bundle**

```bash
./Scripts/bundle-tiptap.sh
```

Expected output ends with:
```
✓ Bundle written to Sources/QuillKit/Resources/tiptap-bundle.js (NNkb)
  Rebuild the app to pick up the new bundle.
```

- [ ] **Step 3: Commit**

```bash
git add Scripts/bundle-tiptap.sh Sources/QuillKit/Resources/tiptap-bundle.js
git commit -m "build: export TiptapNode and Blockquote from tiptap bundle"
```

---

### Task 2: Add CSS for the cite line

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html:108`

- [ ] **Step 1: Insert cite styles after line 108**

Line 108 currently reads:
```css
    body.dark .ProseMirror blockquote { border-color: #555; color: #aaa; }
```

Insert immediately after it:

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

- [ ] **Step 2: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html
git commit -m "style: add subdued right-aligned cite line inside blockquote"
```

---

### Task 3: Destructure `TiptapNode` and `Blockquote` and define the `Cite` node

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` — the TiptapBundle destructure (~line 359) and the area just before `const editor = new Editor({...})` (~line 675)

- [ ] **Step 1: Add `TiptapNode` and `Blockquote` to the destructure**

Find this block (around line 359):
```javascript
    const {
      Editor, Extension,
      StarterKit, Underline,
      Table, TableRow, TableCell, TableHeader,
      TiptapImage, Link,
      TaskList, TaskItem,
      Placeholder,
      Plugin, PluginKey,
      DecorationSet, Decoration,
    } = TiptapBundle
```

Replace with:
```javascript
    const {
      Editor, Extension, TiptapNode,
      StarterKit, Underline,
      Table, TableRow, TableCell, TableHeader,
      TiptapImage, Blockquote, Link,
      TaskList, TaskItem,
      Placeholder,
      Plugin, PluginKey,
      DecorationSet, Decoration,
    } = TiptapBundle
```

- [ ] **Step 2: Define the `Cite` node just before `const SpellCheck = Extension.create({...})`**

Insert this block before the line `const SpellCheck = Extension.create({`:

```javascript
    // ── Cite node ─────────────────────────────────────────
    // Optional last child of blockquote. Maps to <cite> in WordPress/Gutenberg.
    // No 'group' — cannot be inserted anywhere block is accepted; only blockquote
    // schema allows it via 'block+ cite?'.
    const Cite = TiptapNode.create({
      name: 'cite',
      content: 'inline*',
      parseHTML() {
        return [{ tag: 'cite' }]
      },
      renderHTML({ HTMLAttributes }) {
        return ['cite', HTMLAttributes, 0]
      },
      addKeyboardShortcuts() {
        return {
          Enter: () => {
            const { state } = this.editor
            const { $from } = state.selection
            if ($from.node($from.depth).type.name !== 'cite') return false
            // Find blockquote ancestor depth
            let bqDepth = -1
            for (let d = $from.depth; d >= 0; d--) {
              if ($from.node(d).type.name === 'blockquote') { bqDepth = d; break }
            }
            if (bqDepth === -1) return false
            // Insert a paragraph immediately after the blockquote
            const after = $from.after(bqDepth)
            const para = state.schema.nodes.paragraph.create()
            const tr = state.tr.insert(after, para)
            const resolved = tr.doc.resolve(after + 1)
            tr.setSelection(state.selection.constructor.near(resolved))
            this.editor.view.dispatch(tr)
            return true
          },
          Backspace: () => {
            const { state } = this.editor
            const { $from, empty } = state.selection
            if (!empty) return false
            const node = $from.node($from.depth)
            if (node.type.name !== 'cite' || node.content.size > 0) return false
            return this.editor.commands.deleteNode('cite')
          },
        }
      },
    })
```

- [ ] **Step 3: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html
git commit -m "feat: define Cite Tiptap node with Enter/Backspace keyboard shortcuts"
```

---

### Task 4: Register `Cite` and the extended `Blockquote` in the editor

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` — just before `const editor = new Editor({...})` and the extensions array inside it

- [ ] **Step 1: Define `CustomBlockquote` just before `const editor = new Editor({`**

Insert after the `Cite` node definition (and before `const SpellCheck`):

```javascript
    // Extended blockquote: allows an optional cite as its last child.
    const CustomBlockquote = Blockquote.extend({
      content: 'block+ cite?',
    })
```

- [ ] **Step 2: Update the `extensions` array to disable StarterKit's blockquote and add `CustomBlockquote` and `Cite`**

Find the extensions array:
```javascript
      extensions: [
        StarterKit,
        Underline,
```

Replace with:
```javascript
      extensions: [
        StarterKit.configure({ blockquote: false }),
        CustomBlockquote,
        Cite,
        Underline,
```

- [ ] **Step 3: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html
git commit -m "feat: register Cite node and extended Blockquote with block+ cite? schema"
```

---

### Task 5: Update the blockquote toolbar command to auto-insert cite

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html:720`

- [ ] **Step 1: Replace the `blockquote` entry in `COMMANDS`**

Find:
```javascript
      blockquote:    () => editor.chain().focus().toggleBlockquote().run(),
```

Replace with:
```javascript
      blockquote: () => {
        if (editor.isActive('blockquote')) {
          editor.chain().focus().toggleBlockquote().run()
          return
        }
        // Toggle on: wrap in blockquote then append an empty cite
        editor.chain()
          .focus()
          .toggleBlockquote()
          .command(({ tr, state }) => {
            const { $head } = state.selection
            for (let d = $head.depth; d >= 0; d--) {
              const node = $head.node(d)
              if (node.type.name === 'blockquote') {
                const end = $head.after(d) - 1
                tr.insert(end, state.schema.nodes.cite.create())
                return true
              }
            }
            return false
          })
          .run()
      },
```

- [ ] **Step 2: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html
git commit -m "feat: auto-insert cite node when toggling blockquote on"
```

---

### Task 6: Strip empty cite elements in `toWordPressHTML`

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` — inside `toWordPressHTML()`, after the blockquote class block (~line 895)

- [ ] **Step 1: Add empty-cite stripping after the blockquote class block**

Find:
```javascript
      // Blockquotes → wp-block-quote class
      div.querySelectorAll('blockquote').forEach(el => {
        el.classList.add('wp-block-quote')
      })
```

Insert immediately after:
```javascript
      // Strip empty cite elements (user left attribution blank)
      div.querySelectorAll('blockquote cite').forEach(el => {
        if (!el.textContent.trim()) el.remove()
      })
```

- [ ] **Step 2: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html
git commit -m "feat: omit empty cite elements from saved WordPress HTML"
```

---

### Task 7: Build and verify

**Files:** none — verification only

- [ ] **Step 1: Build**

```bash
./build.sh
```

Expected: build succeeds, `Quill.app` assembled.

- [ ] **Step 2: Open the app and connect to a WordPress site**

```bash
open Quill.app
```

- [ ] **Step 3: Insert a blockquote — verify cite line appears**

Open any post or draft. Click the `"` toolbar button. Confirm:
- The cursor lands in the quote text (not the cite)
- A second, visually distinct line appears below the quote text — right-aligned, smaller, lighter gray

- [ ] **Step 4: Type attribution in the cite line — verify styling**

Click into the cite line and type `— Author Name`. Confirm:
- Text is right-aligned, non-italic, smaller than the quote body
- Dark mode (⌘⇧D or system toggle): cite text uses a darker gray

- [ ] **Step 5: Test Enter key exits the blockquote**

Place cursor inside the cite line. Press Enter. Confirm:
- A new paragraph is created after the blockquote
- Cursor is in that paragraph

- [ ] **Step 6: Test Backspace in empty cite removes it**

Insert a new blockquote (leave cite empty). Click into the empty cite line. Press Backspace. Confirm:
- The cite node is deleted
- Cursor moves back into the last paragraph of the blockquote

- [ ] **Step 7: Save with an empty cite — verify no `<cite>` in HTML**

Insert a blockquote, leave the cite blank, save the post. In a browser, inspect the saved post via WordPress REST API:
```
GET https://<your-site>/wp-json/wp/v2/posts/<id>?context=edit
```
Confirm `content.raw` contains `<blockquote class="wp-block-quote">` with no `<cite>` inside.

- [ ] **Step 8: Save with a filled cite — verify `<cite>` in HTML**

Same flow but type `— Test Source` in the cite. Confirm `content.raw` contains:
```html
<blockquote class="wp-block-quote"><p>…</p><cite>— Test Source</cite></blockquote>
```

- [ ] **Step 9: Load a post that already has `<cite>` — verify round-trip**

Open a post that was previously saved with a `<cite>` (step 8 works). Confirm:
- The cite text appears in the editor styled correctly
- Re-saving produces identical HTML
