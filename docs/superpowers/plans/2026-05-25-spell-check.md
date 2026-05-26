# Spell Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add on-demand spell checking via a toolbar button — clicking "ABC" runs macOS NSSpellChecker on the editor text, highlights misspelled words with red wavy underlines, and clears them on the first edit.

**Architecture:** JS posts the editor's plain text to Swift via a `checkSpelling` WKScriptMessage. Swift runs `NSSpellChecker.shared` in a loop to collect misspelled words, serializes them to JSON, and calls `window.applySpellErrors(json)` back into the webview. A ProseMirror plugin holds a `DecorationSet` of `.spell-error` spans; it clears automatically on any `tr.docChanged`.

**Tech Stack:** Swift `NSSpellChecker`, `WKWebView` message bridge, Tiptap `Extension`, ProseMirror `Plugin` / `DecorationSet` / `Decoration.inline`, esm.sh CDN imports.

---

## Files

| File | Change |
|---|---|
| `Sources/QuillKit/Resources/editor.html` | Cleanup stale code; add PM imports, SpellCheck extension, toolbar button, CSS, `applySpellErrors` |
| `Sources/QuillKit/Views/Editor/EditorView.swift` | Register `checkSpelling` message handler |
| `Sources/QuillKit/Views/Editor/EditorCoordinator.swift` | Handle `checkSpelling` message; NSSpellChecker loop; call back into webview |

---

### Task 1: Clean up failed spell-check attempt

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`

- [ ] **Remove the `editorProps` spellcheck attribute** from the `new Editor({...})` call (~line 644).

  Find and delete these three lines:
  ```js
      editorProps: {
        attributes: { spellcheck: 'true' },
      },
  ```

- [ ] **Remove the `::spelling-error` and `::grammar-error` CSS rules** (~line 88).

  Find and delete:
  ```css
      ::spelling-error { text-decoration: red wavy underline; }
      ::grammar-error  { text-decoration: gold wavy underline; }
  ```

- [ ] **Verify the file still builds cleanly**

  ```bash
  cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh
  ```
  Expected: `Build complete!` with only the usual warnings.

- [ ] **Commit**

  ```bash
  git add Sources/QuillKit/Resources/editor.html
  git commit -m "chore: remove failed native spell-check attempt"
  ```

---

### Task 2: Add ProseMirror imports and SpellCheck Tiptap extension

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`

- [ ] **Add PM imports** to the existing `import` block at the top of the `<script type="module">` section (after the existing Tiptap imports, ~line 356):

  ```js
  import { Extension }                from 'https://esm.sh/@tiptap/core@2'
  import { Plugin, PluginKey }        from 'https://esm.sh/@tiptap/pm@2/state'
  import { DecorationSet, Decoration } from 'https://esm.sh/@tiptap/pm@2/view'
  ```

  Note: `Editor` is already imported from `@tiptap/core@2` — add `Extension` to that same import line instead of duplicating the URL:
  ```js
  import { Editor, Extension } from 'https://esm.sh/@tiptap/core@2'
  ```
  Then add the two PM import lines separately.

- [ ] **Define the SpellCheck extension** just before the `const editor = new Editor({...})` call:

  ```js
  // ── Spell check ───────────────────────────────────────
  const spellCheckKey = new PluginKey('spellCheck')

  const SpellCheck = Extension.create({
    name: 'spellCheck',
    addProseMirrorPlugins() {
      return [
        new Plugin({
          key: spellCheckKey,
          state: {
            init() { return DecorationSet.empty },
            apply(tr, set) {
              const incoming = tr.getMeta(spellCheckKey)
              if (incoming !== undefined) return incoming
              if (tr.docChanged) return DecorationSet.empty
              return set.map(tr.mapping, tr.doc)
            }
          },
          props: {
            decorations(state) { return spellCheckKey.getState(state) }
          }
        })
      ]
    }
  })
  ```

- [ ] **Register the extension** by adding `SpellCheck` to the `extensions: [...]` array in the `new Editor({...})` call:

  ```js
  extensions: [
    StarterKit,
    Underline,
    // ... existing extensions ...
    SpellCheck,   // ← add this
  ],
  ```

- [ ] **Build and verify no import errors**

  ```bash
  cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh && open Quill.app
  ```
  Open any post/draft. The editor should load normally (no JS console errors from the new imports). The CDN will fetch `@tiptap/pm` modules on first load — allow a moment for the cold cache.

- [ ] **Commit**

  ```bash
  git add Sources/QuillKit/Resources/editor.html
  git commit -m "feat: add SpellCheck ProseMirror plugin (decoration holder)"
  ```

---

### Task 3: Add CSS, toolbar button, and `applySpellErrors` function

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`

- [ ] **Add the `.spell-error` CSS rule** in the `<style>` block, after the `.ProseMirror` block (around line 88):

  ```css
  .spell-error {
    text-decoration: red wavy underline;
    text-decoration-skip-ink: none;
  }
  ```

- [ ] **Add the toolbar button** in `<div id="toolbar">`, before the Undo/Redo separator at the end:

  Find:
  ```html
      <span class="tb-sep"></span>
      <button data-cmd="undo" title="Undo (⌘Z)">&#8617; Undo</button>
  ```

  Insert before it:
  ```html
      <span class="tb-sep"></span>
      <button id="btn-spell" title="Check Spelling"><span style="text-decoration: red wavy underline; text-underline-offset: 3px; text-decoration-skip-ink: none;">ABC</span></button>
  ```

- [ ] **Wire up the button click** in the JS setup block (after the `data-cmd` forEach listener, around line 747):

  ```js
  document.getElementById('btn-spell').addEventListener('mousedown', e => {
    e.preventDefault()
    window.webkit.messageHandlers.checkSpelling.postMessage(editor.getText())
  })
  ```

- [ ] **Add the `window.applySpellErrors` function** anywhere after the `editor` variable is defined (e.g., after `updateToolbar()` definition):

  ```js
  window.applySpellErrors = function(words) {
    function escapeRegex(s) {
      return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    }
    const { state, dispatch } = editor.view
    const decos = []
    if (Array.isArray(words) && words.length > 0) {
      state.doc.descendants((node, pos) => {
        if (!node.isText) return
        const text = node.text
        words.forEach(word => {
          const re = new RegExp('\\b' + escapeRegex(word) + '\\b', 'gi')
          let match
          while ((match = re.exec(text)) !== null) {
            decos.push(
              Decoration.inline(
                pos + match.index,
                pos + match.index + match[0].length,
                { class: 'spell-error' }
              )
            )
          }
        })
      })
    }
    const decoSet = DecorationSet.create(state.doc, decos)
    dispatch(state.tr.setMeta(spellCheckKey, decoSet))
  }
  ```

- [ ] **Build and verify the button appears**

  ```bash
  cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh && open Quill.app
  ```
  The "ABC" button with a red wavy underline should appear in the toolbar before Undo. Clicking it will silently fail for now (Swift handler not wired yet) — that's expected.

- [ ] **Commit**

  ```bash
  git add Sources/QuillKit/Resources/editor.html
  git commit -m "feat: add spell-check toolbar button, CSS, and applySpellErrors handler"
  ```

---

### Task 4: Register message handler in EditorView

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/EditorView.swift`

- [ ] **Add the `checkSpelling` handler registration** alongside the existing handlers in `makeNSView`:

  Find:
  ```swift
  config.userContentController.add(context.coordinator, name: "selectionChanged")
  ```

  Add after it:
  ```swift
  config.userContentController.add(context.coordinator, name: "checkSpelling")
  ```

- [ ] **Build to verify it compiles**

  ```bash
  cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh
  ```
  Expected: `Build complete!`

- [ ] **Commit**

  ```bash
  git add Sources/QuillKit/Views/Editor/EditorView.swift
  git commit -m "feat: register checkSpelling WKScriptMessage handler"
  ```

---

### Task 5: Handle checkSpelling in EditorCoordinator

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/EditorCoordinator.swift`

- [ ] **Add the `checkSpelling` case** to the `switch message.name` block in `userContentController(_:didReceive:)`.

  Find:
  ```swift
  default:
      break
  }
  ```

  Insert before it:
  ```swift
  case "checkSpelling":
      guard let text = message.body as? String else { return }
      DispatchQueue.global(qos: .userInitiated).async {
          var misspelled = Set<String>()
          var offset = 0
          let tag = NSSpellChecker.shared.uniqueSpellDocumentTag()
          while true {
              let range = NSSpellChecker.shared.checkSpelling(
                  of: text, startingAt: offset,
                  language: nil, wrap: false,
                  inSpellDocumentWithTag: tag, wordCount: nil)
              if range.length == 0 { break }
              misspelled.insert((text as NSString).substring(with: range))
              offset = range.upperBound
          }
          NSSpellChecker.shared.closeSpellDocument(withTag: tag)
          guard
              let data = try? JSONSerialization.data(withJSONObject: Array(misspelled)),
              let json = String(data: data, encoding: .utf8)
          else { return }
          DispatchQueue.main.async {
              self.webView?.evaluateJavaScript(
                  "window.applySpellErrors(\(json))",
                  completionHandler: nil
              )
          }
      }
  ```

- [ ] **Build**

  ```bash
  cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh
  ```
  Expected: `Build complete!`

- [ ] **Commit**

  ```bash
  git add Sources/QuillKit/Views/Editor/EditorCoordinator.swift
  git commit -m "feat: handle checkSpelling message with NSSpellChecker"
  ```

---

### Task 6: End-to-end test and verify

- [ ] **Launch and test the happy path**

  ```bash
  pkill -x Quill 2>/dev/null || true
  cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh && open Quill.app
  ```

  1. Open any post or local draft
  2. Type some deliberately misspelled words: `teh quikc brwon fox`
  3. Click the "ABC" button in the toolbar
  4. Verify: misspelled words get red wavy underlines
  5. Right-click an underlined word — verify spell suggestions appear in the context menu
  6. Type a character anywhere — verify all underlines disappear immediately

- [ ] **Test the "nothing misspelled" case**

  1. Type `The quick brown fox`
  2. Click the "ABC" button
  3. Verify: no underlines appear (all words spelled correctly)

- [ ] **Test with a remote post**

  1. Open a published post fetched from WordPress
  2. Click "ABC"
  3. Verify: misspelled words in the post content get underlines

- [ ] **Final commit if any adjustments were needed**

  ```bash
  git add -p
  git commit -m "fix: spell check adjustments from manual testing"
  ```
