# HTML Snippets Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user maintain a personal library of reusable raw-HTML snippets and insert them into any post/page from the editor toolbar, with each inserted instance surviving arbitrary further edits and round-tripping through WordPress save/load byte-for-byte, with no wrapper markup added to the published page.

**Architecture:** A new atomic Tiptap node (`snippetBlock`) holds an independent `{name, html}` copy per insertion and renders a static, non-editable card via a NodeView (mirrors the existing `embedBlock`/`EmbedNodeView` pattern). On save, `toWordPressHTML()` unwraps the node's intermediate DOM representation into a pair of inert HTML comment markers around the snippet's raw children — extracted to a detached scratch element before any other transform runs, so nothing in the transform pipeline can mutate the snippet's contents, then re-inserted last. On load, a symmetric `restoreSnippetMarkers()` pass converts comment-marker pairs back into the node's intermediate DOM shape before Tiptap parses the document. A toolbar button opens an `NSPopover` (SwiftUI `SnippetPickerView`, mirroring `LinkPickerView`) backed by `AppState.snippets`; picking a row inserts either a Tiptap node (visual mode) or spliced marker text (code view). A separate `SnippetManagerView` sheet edits the library itself (add/rename/edit/delete, Cancel-discards/Save-commits) and persists via a new `SnippetStore` (mirrors `AISettingsStore`).

**Tech Stack:** Swift 6 / SwiftUI / AppKit (`NSPopover`, `NSHostingController`) for the storage layer and native UI chrome; Tiptap 2.x / vanilla DOM transforms (`editor-transforms.js`) for the in-editor node and WordPress HTML round-trip; Swift Testing (`swift test`) and Node `node:test` + jsdom (`node --test`) for automated coverage.

## Global Constraints

- Each inserted snippet instance is an independent copy — never linked back to the library entry (editing one never affects the other). This is explicitly out of scope to build.
- The saved HTML must not add any wrapper element, class, or attribute around the snippet's content — only inert HTML comment markers, and the content between them must be preserved byte-for-byte (including any elements a naive transform pass would otherwise mutate, e.g. a stray `<h2>`).
- No generic Gutenberg block passthrough — the marker grammar stays flat and private (no JSON attrs, no nesting), deliberately out of scope.
- Follow the existing `JSONFileStore<T>` / `AISettingsStore` pattern for persistence (`~/Library/Application Support/Quill/snippets.json`, chmod 600).
- Follow the existing `EmbedBlock`/`EmbedNodeView` pattern for the new Tiptap node (atomic, block group, custom NodeView, `renderHTML` returns a raw DOM node).
- Follow the existing `LinkPickerView`/`EditorCoordinator.showLinkPicker` pattern for the toolbar insert popover (`NSHostingController` + `ObservableObject` model + `NSPopover`).
- All DOM transforms in `editor-transforms.js` are pure DOM operations (create element/comment, reparent) — no regex on raw HTML strings (regex is fine only on an individual comment node's `nodeValue`, matching existing convention).
- After every code change: quit the app, run `./build.sh`, reopen (per project convention).

---

### Task 1: Snippet data model, storage, and AppState wiring

**Files:**
- Create: `Sources/QuillKit/Storage/Snippet.swift`
- Modify: `Sources/QuillKit/App/AppState.swift`
- Modify: `Tests/QuillTests/CredentialsStoreTests.swift`

**Interfaces:**
- Produces: `public struct Snippet: Codable, Identifiable, Equatable { public var id: UUID; public var name: String; public var html: String; public var createdAt: Date; public var updatedAt: Date }` and `public struct SnippetStore { static func save(_ snippets: [Snippet]) throws; static func load() throws -> [Snippet]?; static func delete() throws }`. Later tasks read/write `AppState.snippets: [Snippet]`.

- [ ] **Step 1: Write the failing test**

Add this new section to the end of `Tests/QuillTests/CredentialsStoreTests.swift` (inside the existing `final class CredentialsStoreTests { ... }` body, after the `AISettingsStore` section). This file already owns a single `AppSupportDirectory.override` tempdir for its whole class lifetime (see the `init()`/`deinit` at the top of the file) — reuse it rather than introducing a second suite that would race on the same global static.

```swift
    // MARK: - SnippetStore

    @Test func snippetRoundTrip() throws {
        let now = Date()
        let snippets = [
            Snippet(id: UUID(), name: "Newsletter CTA", html: "<p>Subscribe!</p>", createdAt: now, updatedAt: now),
            Snippet(id: UUID(), name: "Ad Code", html: "<div>ad</div>", createdAt: now, updatedAt: now),
        ]
        try SnippetStore.save(snippets)
        let loaded = try SnippetStore.load()
        #expect(loaded?.count == 2)
        #expect(loaded?[0].name == "Newsletter CTA")
        #expect(loaded?[0].html == "<p>Subscribe!</p>")
        #expect(loaded?[1].name == "Ad Code")
        try? SnippetStore.delete()
    }

    @Test func snippetLoadReturnsNilWhenAbsent() throws {
        #expect(try SnippetStore.load() == nil)
    }

    @Test func snippetDeleteRemovesFile() throws {
        try SnippetStore.save([Snippet(id: UUID(), name: "x", html: "y", createdAt: Date(), updatedAt: Date())])
        try SnippetStore.delete()
        #expect(try SnippetStore.load() == nil)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CredentialsStoreTests`
Expected: FAIL to compile — `cannot find type 'Snippet' in scope` / `cannot find 'SnippetStore' in scope`.

- [ ] **Step 3: Write the model and store**

Create `Sources/QuillKit/Storage/Snippet.swift`:

```swift
import Foundation

public struct Snippet: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var html: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, html: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.html = html
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct SnippetStore {
    private static let store = JSONFileStore<[Snippet]>("snippets.json")

    public static func save(_ snippets: [Snippet]) throws { try store.save(snippets) }
    public static func load() throws -> [Snippet]? { try store.load() }
    public static func delete() throws { try store.delete() }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CredentialsStoreTests`
Expected: PASS (all tests in the suite, including the three new ones).

- [ ] **Step 5: Wire `AppState.snippets`**

In `Sources/QuillKit/App/AppState.swift`, add the published property next to `aiSettings` (line 79):

```swift
    @Published public var aiSettings: AISettings?
    @Published public var snippets: [Snippet] = []
```

And load it in `init()` next to the existing `aiSettings` load (line 89-91):

```swift
    public init() {
        aiSettings = try? AISettingsStore.load()
        snippets = (try? SnippetStore.load()) ?? []
    }
```

- [ ] **Step 6: Verify the whole project still builds**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 7: Commit**

```bash
git add Sources/QuillKit/Storage/Snippet.swift Sources/QuillKit/App/AppState.swift Tests/QuillTests/CredentialsStoreTests.swift
git commit -m "feat: add Snippet model, SnippetStore, and AppState wiring"
```

---

### Task 2: JS transform functions — comment-marker round-trip

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js`
- Modify: `Scripts/test-editor.js`

**Interfaces:**
- Consumes: nothing new from Task 1 (pure JS, no Swift dependency).
- Produces: `escapeSnippetName(name)`, `buildSnippetMarkerHTML(name, html)`, `restoreSnippetMarkers(html, doc)` — all exported from `editor-transforms.js`. `toWordPressHTML()` gains an isolation/unwrap step for `div.quill-snippet` elements. Task 3 (`editor.html`) calls `buildSnippetMarkerHTML` and relies on `toWordPressHTML`'s new unwrap step; loading code calls `restoreSnippetMarkers` before `setContent`.

- [ ] **Step 1: Write the failing tests**

Append to `Scripts/test-editor.js` (update the import line at the top first, then add new `describe` blocks at the end of the file).

Change the import line (line 6) from:

```js
const { extractAlignment, toWordPressHTML, formatHTML, countStats, findMatches, findMatchesLoose, fuzzyAnchorRegex, detectEmbedProvider, embedClassFor } = require('../Sources/QuillKit/Resources/editor-transforms.js')
```

to:

```js
const { extractAlignment, toWordPressHTML, formatHTML, countStats, findMatches, findMatchesLoose, fuzzyAnchorRegex, detectEmbedProvider, embedClassFor, escapeSnippetName, buildSnippetMarkerHTML, restoreSnippetMarkers } = require('../Sources/QuillKit/Resources/editor-transforms.js')
```

Append at the end of the file:

```js
// ---------------------------------------------------------------------------
// escapeSnippetName
// ---------------------------------------------------------------------------

describe('escapeSnippetName', () => {
  test('escapes double quotes', () => {
    assert.equal(escapeSnippetName('Say "Hi"'), 'Say &quot;Hi&quot;')
  })

  test('collapses runs of two or more dashes to one', () => {
    assert.equal(escapeSnippetName('Before -- After --- End'), 'Before - After - End')
  })

  test('leaves a single dash untouched', () => {
    assert.equal(escapeSnippetName('pre-order'), 'pre-order')
  })

  test('handles null/undefined gracefully', () => {
    assert.equal(escapeSnippetName(null), '')
    assert.equal(escapeSnippetName(undefined), '')
  })
})

// ---------------------------------------------------------------------------
// buildSnippetMarkerHTML
// ---------------------------------------------------------------------------

describe('buildSnippetMarkerHTML', () => {
  test('wraps content in open/close markers with the escaped name', () => {
    const out = buildSnippetMarkerHTML('Newsletter CTA', '<p>Subscribe!</p>')
    assert.equal(out, '<!-- quill:snippet name="Newsletter CTA" -->\n<p>Subscribe!</p>\n<!-- /quill:snippet -->')
  })

  test('escapes quotes and collapses dashes in the name', () => {
    const out = buildSnippetMarkerHTML('Say "Hi" -- Bye', '<p>x</p>')
    assert.match(out, /name="Say &quot;Hi&quot; - Bye"/)
  })
})

// ---------------------------------------------------------------------------
// toWordPressHTML — snippet blocks
// ---------------------------------------------------------------------------

describe('toWordPressHTML — snippet blocks', () => {
  test('unwraps a single-element snippet into comment markers with no wrapper', () => {
    const html = '<div class="quill-snippet" data-snippet-name="Newsletter CTA"><p>Subscribe!</p></div>'
    const out = wp(html)
    assert.equal(out, '<!-- quill:snippet name="Newsletter CTA" -->\n<p>Subscribe!</p>\n<!-- /quill:snippet -->')
    assert.doesNotMatch(out, /quill-snippet/)
  })

  test('preserves multiple top-level elements between the markers', () => {
    const html = '<div class="quill-snippet" data-snippet-name="Details">' +
      '<details><summary>A</summary>1</details>' +
      '<details><summary>B</summary>2</details>' +
      '<details><summary>C</summary>3</details>' +
      '</div>'
    const out = wp(html)
    assert.equal(
      out,
      '<!-- quill:snippet name="Details" -->\n' +
      '<details><summary>A</summary>1</details><details><summary>B</summary>2</details><details><summary>C</summary>3</details>\n' +
      '<!-- /quill:snippet -->'
    )
  })

  test('escapes a name containing quotes and double-dashes', () => {
    const html = '<div class="quill-snippet" data-snippet-name=\'Say "Hi" -- Bye\'><p>x</p></div>'
    const out = wp(html)
    assert.match(out, /name="Say &quot;Hi&quot; - Bye"/)
  })

  test('content inside the snippet is not mutated by other transforms (byte-for-byte)', () => {
    const html = '<div class="quill-snippet" data-snippet-name="Weird"><h2>Raw heading</h2><ul><li>x</li></ul></div>'
    const out = wp(html)
    assert.equal(
      out,
      '<!-- quill:snippet name="Weird" -->\n<h2>Raw heading</h2><ul><li>x</li></ul>\n<!-- /quill:snippet -->'
    )
    // Neither the heading nor the list gained the classes the rest of the
    // pipeline would normally add to real document headings/lists.
    assert.doesNotMatch(out, /wp-block-heading/)
    assert.doesNotMatch(out, /wp-block-list/)
  })

  test('multiple snippets in one document are each unwrapped independently', () => {
    const html = '<div class="quill-snippet" data-snippet-name="One"><p>1</p></div>' +
      '<p>middle</p>' +
      '<div class="quill-snippet" data-snippet-name="Two"><p>2</p></div>'
    const out = wp(html)
    assert.match(out, /name="One"[\s\S]*<p>1<\/p>[\s\S]*\/quill:snippet/)
    assert.match(out, /name="Two"[\s\S]*<p>2<\/p>[\s\S]*\/quill:snippet/)
    assert.match(out, /<p>middle<\/p>/)
  })
})

// ---------------------------------------------------------------------------
// restoreSnippetMarkers
// ---------------------------------------------------------------------------

describe('restoreSnippetMarkers', () => {
  function restore(html) {
    return restoreSnippetMarkers(html, document)
  }

  test('converts a comment-marker pair back into a div.quill-snippet wrapper', () => {
    const html = '<!-- quill:snippet name="Newsletter CTA" -->\n<p>Subscribe!</p>\n<!-- /quill:snippet -->'
    const out = restore(html)
    const dom = new JSDOM(out).window.document
    const el = dom.querySelector('div.quill-snippet')
    assert.ok(el)
    assert.equal(el.getAttribute('data-snippet-name'), 'Newsletter CTA')
    assert.match(el.innerHTML, /<p>Subscribe!<\/p>/)
  })

  test('preserves multiple top-level elements inside the reconstructed wrapper', () => {
    const html = '<!-- quill:snippet name="Details" -->\n' +
      '<details><summary>A</summary>1</details><details><summary>B</summary>2</details>\n' +
      '<!-- /quill:snippet -->'
    const out = restore(html)
    const dom = new JSDOM(out).window.document
    const el = dom.querySelector('div.quill-snippet')
    assert.equal(el.querySelectorAll('details').length, 2)
  })

  test('unescapes &quot; back to a literal quote in the name (dash collapsing is intentionally lossy)', () => {
    const html = '<!-- quill:snippet name="Say &quot;Hi&quot; - Bye" -->\n<p>x</p>\n<!-- /quill:snippet -->'
    const out = restore(html)
    const dom = new JSDOM(out).window.document
    const el = dom.querySelector('div.quill-snippet')
    assert.equal(el.getAttribute('data-snippet-name'), 'Say "Hi" - Bye')
  })

  test('content outside the markers is left untouched', () => {
    const html = '<p>before</p>\n<!-- quill:snippet name="X" -->\n<p>mid</p>\n<!-- /quill:snippet -->\n<p>after</p>'
    const out = restore(html)
    assert.match(out, /<p>before<\/p>/)
    assert.match(out, /<p>after<\/p>/)
  })

  test('is a no-op when there are no snippet markers', () => {
    const html = '<p>hello</p>'
    assert.equal(restore(html), '<p>hello</p>')
  })

  test('handles empty/null input without throwing', () => {
    assert.equal(restore(''), '')
    assert.equal(restoreSnippetMarkers(null, document), null)
  })
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test Scripts/test-editor.js`
Expected: FAIL — `escapeSnippetName is not a function` (and similar) for the new describe blocks; all pre-existing tests still pass.

- [ ] **Step 3: Implement the transform functions**

In `Sources/QuillKit/Resources/editor-transforms.js`, add these three functions right after `extractAlignment` (before `toWordPressHTML`, around line 15):

```js
function escapeSnippetName(name) {
  return (name || '').replace(/"/g, '&quot;').replace(/-{2,}/g, '-')
}

function buildSnippetMarkerHTML(name, html) {
  return `<!-- quill:snippet name="${escapeSnippetName(name)}" -->\n${html}\n<!-- /quill:snippet -->`
}

// Symmetric to the snippet-unwrap step in toWordPressHTML: walks the DOM for
// <!-- quill:snippet name="..." --> ... <!-- /quill:snippet --> comment pairs
// (which may appear at any depth, e.g. inside a blockquote) and reconstructs
// each one as a <div class="quill-snippet" data-snippet-name="..."> wrapper
// around the gathered sibling nodes, matching SnippetBlock's parseHTML rule.
// Run before editor.commands.setContent() at both initial load and code-view exit.
function restoreSnippetMarkers(html, doc) {
  if (!doc && typeof document !== 'undefined') doc = document
  if (!html) return html

  const container = doc.createElement('div')
  container.innerHTML = html

  function openName(node) {
    if (node.nodeType !== 8) return null
    const m = /^\s*quill:snippet name="([\s\S]*)"\s*$/.exec(node.nodeValue)
    return m ? m[1] : null
  }
  function isClose(node) {
    return node.nodeType === 8 && /^\s*\/quill:snippet\s*$/.test(node.nodeValue)
  }

  function walk(parent) {
    let node = parent.firstChild
    while (node) {
      const rawName = openName(node)
      if (rawName !== null) {
        const openMarker = node
        const collected = []
        let cursor = node.nextSibling
        let closeMarker = null
        while (cursor) {
          if (isClose(cursor)) { closeMarker = cursor; break }
          collected.push(cursor)
          cursor = cursor.nextSibling
        }
        if (closeMarker) {
          const wrapper = doc.createElement('div')
          wrapper.className = 'quill-snippet'
          wrapper.setAttribute('data-snippet-name', rawName.replace(/&quot;/g, '"'))
          const after = closeMarker.nextSibling
          collected.forEach(n => wrapper.appendChild(n))
          parent.insertBefore(wrapper, openMarker)
          parent.removeChild(openMarker)
          parent.removeChild(closeMarker)
          node = after
          continue
        }
      }
      if (node.nodeType === 1) walk(node)
      node = node.nextSibling
    }
  }

  walk(container)
  return container.innerHTML
}
```

- [ ] **Step 4: Add the isolation/unwrap step to `toWordPressHTML`**

Still in `editor-transforms.js`, immediately after the `div.innerHTML = html...` block at the top of `toWordPressHTML` (right after line 22's closing, before the `data-media-id` step), add the extraction:

```js
  // Snippet blocks: pull the raw content out of the live tree before any other
  // transform runs, so nothing downstream (heading/list/image classing, table
  // restructuring, embed wrapping, etc.) can touch it. Restored as inert
  // comment markers wrapping the untouched content at the very end of this
  // function — see the matching step just before `return`.
  const snippetRestores = []
  div.querySelectorAll('div.quill-snippet').forEach(el => {
    const name = escapeSnippetName(el.getAttribute('data-snippet-name'))
    const rawHTML = el.innerHTML
    const placeholder = doc.createComment('quill-snippet-placeholder')
    el.parentNode.replaceChild(placeholder, el)
    snippetRestores.push({ placeholder, name, rawHTML })
  })
```

Then, immediately before the final `return div.innerHTML` (end of the function), add the restoration:

```js
  // Restore snippet blocks as inert comment markers around their preserved,
  // untouched raw HTML. Must run last — see extraction step above.
  snippetRestores.forEach(({ placeholder, name, rawHTML }) => {
    const open = doc.createComment(` quill:snippet name="${name}" `)
    const close = doc.createComment(' /quill:snippet ')
    const parent = placeholder.parentNode
    const temp = doc.createElement('div')
    temp.innerHTML = rawHTML
    parent.insertBefore(open, placeholder)
    parent.insertBefore(doc.createTextNode('\n'), placeholder)
    while (temp.firstChild) parent.insertBefore(temp.firstChild, placeholder)
    parent.insertBefore(doc.createTextNode('\n'), placeholder)
    parent.insertBefore(close, placeholder)
    placeholder.remove()
  })

  return div.innerHTML
```

- [ ] **Step 5: Update the CommonJS export list**

At the bottom of `editor-transforms.js`, change:

```js
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { extractAlignment, toWordPressHTML, formatHTML, countStats, findMatches, findMatchesLoose, fuzzyAnchorRegex, detectEmbedProvider, embedClassFor }
}
```

to:

```js
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { extractAlignment, toWordPressHTML, formatHTML, countStats, findMatches, findMatchesLoose, fuzzyAnchorRegex, detectEmbedProvider, embedClassFor, escapeSnippetName, buildSnippetMarkerHTML, restoreSnippetMarkers }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `node --test Scripts/test-editor.js`
Expected: PASS — all tests, including every pre-existing describe block (this confirms the new snippet-extraction step didn't disturb unrelated transforms since it operates on a disjoint, unmatched selector for documents with no snippets).

- [ ] **Step 7: Commit**

```bash
git add Sources/QuillKit/Resources/editor-transforms.js Scripts/test-editor.js
git commit -m "feat: add snippet comment-marker round-trip transforms"
```

---

### Task 3: SnippetBlock Tiptap node, toolbar insertion, code view splicing

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`
- Modify: `Scripts/test-editor-keyboard.js`

**Interfaces:**
- Consumes: `escapeSnippetName`, `buildSnippetMarkerHTML`, `restoreSnippetMarkers` from Task 2 (already global inside `editor.html` since `editor-transforms.js` loads first).
- Produces: `window.insertSnippet(name, html)` global function; `snippetBlock` Tiptap node registered in the schema; `#btn-snippets` toolbar button posting `showSnippetPicker` to `window.webkit.messageHandlers`. Task 4 (Swift) calls `insertSnippet(...)` via `evaluateJavaScript` and listens for the `showSnippetPicker` message.

- [ ] **Step 1: Write the failing regression test**

Append to `Scripts/test-editor-keyboard.js` (after the last existing `describe` block, following the `doc()`/`key()`/`editor` helpers already defined in that file):

```js
describe('snippet round-trip', () => {
  test('inserted snippet survives an unrelated edit elsewhere in the document', () => {
    editor.commands.setContent('<p>Intro paragraph.</p>')
    editor.commands.focus('end')
    win.insertSnippet('Newsletter CTA', '<p>Subscribe!</p>')

    // Edit something unrelated: append text to the first paragraph.
    editor.commands.setTextSelection(1)
    editor.commands.insertContent('EDITED ')

    const html = win.getContent()
    assert.match(html, /<!-- quill:snippet name="Newsletter CTA" -->/)
    assert.match(html, /<p>Subscribe!<\/p>/)
    assert.match(html, /<!-- \/quill:snippet -->/)
    assert.match(html, /EDITED Intro paragraph\./)
  })

  test('snippet card is a genuine atomic node — selecting and deleting it removes exactly one node', () => {
    editor.commands.setContent('<p>before</p>')
    editor.commands.focus('end')
    win.insertSnippet('Ad Code', '<div>ad</div>')
    assert.equal(doc(), 'paragraph("before") | snippetBlock()')
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test Scripts/test-editor-keyboard.js`
Expected: FAIL — `win.insertSnippet is not a function` (or the `doc()` assertion finds no `snippetBlock`).

- [ ] **Step 3: Add the `SnippetBlock` node and its NodeView**

In `Sources/QuillKit/Resources/editor.html`, immediately after the `EmbedBlock` node definition's closing `})` (after line 1532, before the `// ── Footnotes ─────` comment at line 1534), insert:

```js
    // ── Snippet blocks ─────────────────────────────────
    // Atomic node holding an independent {name, html} copy of a library
    // snippet. Renders a static, non-editable card; the only way to change
    // its content is via code view (the card itself is not editable inline).
    class SnippetNodeView {
      constructor(node) {
        this.dom = document.createElement('div')
        this.dom.className = 'snippet-card'
        this.dom.contentEditable = 'false'
        const title = document.createElement('div')
        title.className = 'snippet-card-name'
        title.textContent = node.attrs.name || 'Untitled snippet'
        const preview = document.createElement('div')
        preview.className = 'snippet-card-preview'
        preview.textContent = _snippetPreviewText(node.attrs.html)
        const hint = document.createElement('div')
        hint.className = 'snippet-card-hint'
        hint.textContent = 'Edit in code view'
        this.dom.append(title, preview, hint)
      }
      selectNode()   { this.dom.classList.add('selected') }
      deselectNode() { this.dom.classList.remove('selected') }
    }

    function _snippetPreviewText(html) {
      const t = (html || '').replace(/\s+/g, ' ').trim()
      return t.length > 140 ? t.slice(0, 140) + '…' : t
    }

    const SnippetBlock = TiptapNode.create({
      name: 'snippetBlock',
      group: 'block',
      atom: true,
      draggable: true,
      priority: 110,

      addAttributes() {
        return {
          name: { default: '' },
          html: { default: '' },
        }
      },

      parseHTML() {
        return [{
          tag: 'div.quill-snippet',
          getAttrs: el => ({
            name: el.getAttribute('data-snippet-name') || '',
            html: el.innerHTML,
          }),
        }]
      },

      renderHTML({ node }) {
        const wrapper = document.createElement('div')
        wrapper.className = 'quill-snippet'
        wrapper.setAttribute('data-snippet-name', node.attrs.name)
        wrapper.innerHTML = node.attrs.html
        return wrapper
      },

      addNodeView() {
        return ({ node }) => new SnippetNodeView(node)
      },
    })
```

- [ ] **Step 4: Register the node in the extensions array**

In the `extensions: [` array (line 1817), add `SnippetBlock,` right after `EmbedBlock,` (line 1849):

```js
        ResizableImage.configure({ inline: false }),
        EmbedBlock,
        SnippetBlock,
        FootnoteMarker,
```

- [ ] **Step 5: Add the card CSS**

In the `<style>` block, immediately after the existing `.embed-card` rules (after line 744, before `#embed-menu {`), add:

```css
    /* ── Snippet card ───────────────────────────────── */
    .snippet-card {
      margin: 1em 0;
      padding: 14px 16px;
      border: 1px solid rgba(0,0,0,0.14);
      border-radius: 8px;
      background: rgba(0,0,0,0.025);
      cursor: default;
      user-select: none;
    }
    .snippet-card.selected { outline: 2px solid #b45309; outline-offset: 1px; }
    .snippet-card-name { font-weight: 600; font-size: 13px; margin-bottom: 3px; }
    .snippet-card-preview {
      font-family: ui-monospace, monospace;
      font-size: 12px;
      color: #777;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .snippet-card-hint { font-size: 11px; color: #999; margin-top: 6px; font-style: italic; }
    body.dark .snippet-card { border-color: rgba(255,255,255,0.18); background: rgba(255,255,255,0.04); }
    body.dark .snippet-card-preview { color: #999; }
    body.dark .snippet-card-hint { color: #777; }
```

- [ ] **Step 6: Add the toolbar button**

In the toolbar markup, change (line 892-894):

```html
      <button id="btn-spell" title="Check spelling"><span class="tb-spell-icon">ABC</span></button>
      <button id="btn-code-view" title="Toggle code view"><span class="tb-code-text">&lt;/&gt;</span></button>
    </span>
```

to:

```html
      <button id="btn-spell" title="Check spelling"><span class="tb-spell-icon">ABC</span></button>
      <button id="btn-code-view" title="Toggle code view"><span class="tb-code-text">&lt;/&gt;</span></button>
      <button id="btn-snippets" title="Insert snippet">
        <svg viewBox="0 0 24 24"><rect x="3" y="3" width="12" height="12" rx="2"></rect><rect x="9" y="9" width="12" height="12" rx="2"></rect></svg>
      </button>
    </span>
```

- [ ] **Step 7: Exempt the button from the code-view disable pass**

Change line 2605 from:

```js
      document.getElementById('toolbar').querySelectorAll('button:not(#btn-code-view), select').forEach(el => { el.disabled = true })
```

to:

```js
      document.getElementById('toolbar').querySelectorAll('button:not(#btn-code-view):not(#btn-snippets), select').forEach(el => { el.disabled = true })
```

- [ ] **Step 8: Add the click handler and `window.insertSnippet`**

Immediately after the existing `document.getElementById('btn-code-view').addEventListener(...)` block (after line 2644), add:

```js
    document.getElementById('btn-snippets').addEventListener('mousedown', e => {
      e.preventDefault()
      const rect = document.getElementById('btn-snippets').getBoundingClientRect()
      if (window.webkit?.messageHandlers?.showSnippetPicker) {
        window.webkit.messageHandlers.showSnippetPicker.postMessage({
          rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
        })
      }
    })
```

Immediately after the existing `window.removeLink = ...` block (after line 2746), add:

```js
    window.insertSnippet = (name, html) => {
      if (codeViewActive) {
        const ta = document.getElementById('code-editor')
        const start = ta.selectionStart
        const end = ta.selectionEnd
        const marker = buildSnippetMarkerHTML(name, html)
        ta.value = ta.value.slice(0, start) + marker + ta.value.slice(end)
        const newPos = start + marker.length
        ta.selectionStart = ta.selectionEnd = newPos
        ta.focus()
        _codeViewChanged()
      } else {
        if (_isInFootnote()) return
        editor.chain().focus().insertContent({ type: 'snippetBlock', attrs: { name, html } }).run()
      }
    }
```

- [ ] **Step 9: Run test to verify it passes**

Run: `node --test Scripts/test-editor-keyboard.js`
Expected: PASS — all tests, including the two new ones.

- [ ] **Step 10: Run the full JS suite**

Run: `node --test Scripts/test-editor.js Scripts/test-editor-keyboard.js`
Expected: PASS — 111+ transform tests and 16+ keyboard tests, no regressions.

- [ ] **Step 11: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Scripts/test-editor-keyboard.js
git commit -m "feat: add SnippetBlock Tiptap node, toolbar button, and insertSnippet"
```

---

### Task 4: Toolbar insert popover (Swift)

**Files:**
- Create: `Sources/QuillKit/Views/Editor/SnippetPickerView.swift`
- Modify: `Sources/QuillKit/Views/Editor/EditorCoordinator.swift`
- Modify: `Sources/QuillKit/Views/Editor/EditorView.swift`
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift`

**Interfaces:**
- Consumes: `Snippet` (Task 1), `window.insertSnippet(name, html)` and the `showSnippetPicker` WKWebView message (Task 3).
- Produces: `EditorCoordinator.onLoadSnippets: (() -> [Snippet])?` and `EditorCoordinator.onManageSnippets: (() -> Void)?`, consumed by Task 5's manage-sheet wiring in `PostEditorView`.

No automated test for this task — `NSPopover`/`WKWebView` message-handler glue has no unit test harness in this project (per `docs/testing-plan.md`, AppKit chrome is verified manually). Verify via manual build-and-run at the end of this task.

- [ ] **Step 1: Create `SnippetPickerView.swift`**

Create `Sources/QuillKit/Views/Editor/SnippetPickerView.swift`:

```swift
import SwiftUI

final class SnippetPickerModel: ObservableObject {
    @Published var searchText: String = ""
    let snippets: [Snippet]
    let onInsert: (Snippet) -> Void
    let onManage: () -> Void

    init(snippets: [Snippet], onInsert: @escaping (Snippet) -> Void, onManage: @escaping () -> Void) {
        self.snippets = snippets
        self.onInsert = onInsert
        self.onManage = onManage
    }

    var filtered: [Snippet] {
        guard !searchText.isEmpty else { return snippets }
        return snippets.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}

struct SnippetPickerView: View {
    @ObservedObject var model: SnippetPickerModel
    @FocusState private var fieldFocused: Bool

    private static let amber = Color(red: 0xb4 / 255.0, green: 0x53 / 255.0, blue: 0x09 / 255.0)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                TextField("Search snippets", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(fieldFocused ? Self.amber : Color.primary.opacity(0.15), lineWidth: 1)
            )
            .padding(8)

            Divider()

            if model.filtered.isEmpty {
                Text(model.snippets.isEmpty ? "No snippets yet" : "No matching snippets")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.filtered) { snippet in
                            SnippetPickerRow(snippet: snippet) {
                                model.onInsert(snippet)
                            }
                        }
                    }
                }
                .frame(maxHeight: 240)
            }

            Divider()

            Button {
                model.onManage()
            } label: {
                HStack {
                    Text("Manage snippets…")
                        .font(.system(size: 12))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .foregroundStyle(.secondary)
        }
        .frame(width: 280)
    }
}

private struct SnippetPickerRow: View {
    let snippet: Snippet
    let onTap: () -> Void

    private var previewText: String {
        snippet.html
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.name.isEmpty ? "Untitled" : snippet.name)
                    .foregroundStyle(.primary)
                Text(previewText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Wire the message handler and popover in `EditorCoordinator`**

In `Sources/QuillKit/Views/Editor/EditorCoordinator.swift`, add two new properties next to `onSearchLinks` (line 13):

```swift
    var onSearchLinks: ((String) async throws -> [LinkSearchResult])?
    var onLoadSnippets: (() -> [Snippet])?
    var onManageSnippets: (() -> Void)?
```

Add a new popover property next to `linkPopover` (line 21):

```swift
    private var linkPopover: NSPopover?
    private var snippetPopover: NSPopover?
```

Add a new case in `userContentController(_:didReceive:)`, right after the existing `case "showLinkPicker":` block (after line 80, before `case "requestMediaSizes":`):

```swift
        case "showSnippetPicker":
            guard
                let body    = message.body as? [String: Any],
                let rectMap = body["rect"] as? [String: Any],
                let x = rectMap["x"] as? Double,
                let y = rectMap["y"] as? Double,
                let w = rectMap["width"] as? Double,
                let h = rectMap["height"] as? Double,
                let wv = webView
            else { return }
            DispatchQueue.main.async { self.showSnippetPicker(jsRect: (x, y, w, h), in: wv) }
```

Add the popover-building method right after `showLinkPicker(href:jsRect:in:)` (after line 175, before `handleRequestMediaSizes`):

```swift
    private func showSnippetPicker(jsRect: (x: Double, y: Double, w: Double, h: Double), in wv: WKWebView) {
        snippetPopover?.close()
        let nsRect = NSRect(x: jsRect.x, y: jsRect.y, width: jsRect.w, height: jsRect.h)

        let model = SnippetPickerModel(
            snippets: onLoadSnippets?() ?? [],
            onInsert: { [weak self] snippet in
                self?.snippetPopover?.close()
                guard
                    let nameData = try? JSONEncoder().encode(snippet.name),
                    let nameJSON = String(data: nameData, encoding: .utf8),
                    let htmlData = try? JSONEncoder().encode(snippet.html),
                    let htmlJSON = String(data: htmlData, encoding: .utf8)
                else { return }
                self?.webView?.evaluateJavaScript("insertSnippet(\(nameJSON), \(htmlJSON))", completionHandler: nil)
            },
            onManage: { [weak self] in
                self?.snippetPopover?.close()
                self?.onManageSnippets?()
            }
        )

        let hosting = NSHostingController(rootView: SnippetPickerView(model: model))
        let popover = NSPopover()
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.show(relativeTo: nsRect, of: wv, preferredEdge: .maxY)
        snippetPopover = popover
    }
```

- [ ] **Step 3: Thread the callbacks through `EditorView`**

In `Sources/QuillKit/Views/Editor/EditorView.swift`, add two new properties next to `onSearchLinks` (line 12) and to the initializer (line 31, 49):

```swift
    var onSearchLinks: ((String) async throws -> [LinkSearchResult])?
    var onLoadSnippets: (() -> [Snippet])?
    var onManageSnippets: (() -> Void)?
```

```swift
        onSearchLinks: ((String) async throws -> [LinkSearchResult])? = nil,
        onLoadSnippets: (() -> [Snippet])? = nil,
        onManageSnippets: (() -> Void)? = nil,
```

```swift
        self.onSearchLinks = onSearchLinks
        self.onLoadSnippets = onLoadSnippets
        self.onManageSnippets = onManageSnippets
```

Register the new message handler in `makeNSView` next to `showLinkPicker` (line 71):

```swift
        config.userContentController.add(context.coordinator, name: "showLinkPicker")
        config.userContentController.add(context.coordinator, name: "showSnippetPicker")
```

And wire the coordinator properties in both `makeNSView` (after line 91) and `updateNSView` (after line 111):

```swift
        context.coordinator.onSearchLinks = onSearchLinks
        context.coordinator.onLoadSnippets = onLoadSnippets
        context.coordinator.onManageSnippets = onManageSnippets
```

- [ ] **Step 4: Wire `PostEditorView`**

In `Sources/QuillKit/Views/Editor/PostEditorView.swift`, in the `EditorView(...)` call, add two new arguments right after `onSearchLinks` (after line 90):

```swift
                        onSearchLinks: { query in
                            guard let creds = appState.credentials else { return [] }
                            return try await WordPressClient(credentials: creds).searchLinks(query: query)
                        },
                        onLoadSnippets: {
                            appState.snippets
                        },
                        onManageSnippets: {
                            showSnippetManager = true
                        },
```

Add the new `@State` property next to `showImagePicker` (line 20):

```swift
    @State private var showImagePicker = false
    @State private var showSnippetManager = false
```

(The `.sheet(isPresented: $showSnippetManager)` itself is added in Task 5, once `SnippetManagerView` exists — leave `showSnippetManager` unused by a sheet for now; it will compile fine as a plain `@State` toggle in the meantime.)

- [ ] **Step 5: Build**

Run: `swift build`
Expected: Build succeeds with no errors (no test to run for this task — see note above).

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/Views/Editor/SnippetPickerView.swift Sources/QuillKit/Views/Editor/EditorCoordinator.swift Sources/QuillKit/Views/Editor/EditorView.swift Sources/QuillKit/Views/Editor/PostEditorView.swift
git commit -m "feat: add snippet insert popover wiring"
```

---

### Task 5: Manage Snippets window

**Files:**
- Create: `Sources/QuillKit/Views/Editor/SnippetManagerView.swift`
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift`

**Interfaces:**
- Consumes: `Snippet` (Task 1), `AppState.snippets` (Task 1), `showSnippetManager` state and `onManageSnippets` closure (Task 4).
- Produces: nothing consumed by later tasks — this is the last piece of the feature.

No automated test for this task (SwiftUI sheet with no business logic beyond array mutation already covered by Task 1's `SnippetStore` tests). Verify via manual build-and-run at the end of this task.

- [ ] **Step 1: Create `SnippetManagerView.swift`**

Create `Sources/QuillKit/Views/Editor/SnippetManagerView.swift`:

```swift
import SwiftUI

struct SnippetManagerView: View {
    var onSave: ([Snippet]) -> Void
    var onCancel: () -> Void

    @State private var workingSnippets: [Snippet]
    @State private var selectedID: UUID?

    init(initialSnippets: [Snippet], onSave: @escaping ([Snippet]) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
        _workingSnippets = State(initialValue: initialSnippets)
        _selectedID = State(initialValue: initialSnippets.first?.id)
    }

    private var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return workingSnippets.firstIndex(where: { $0.id == selectedID })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                list
                    .frame(width: 180)
                Divider()
                detail
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minHeight: 320)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Save") { onSave(workingSnippets) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(12)
        }
        .frame(width: 560, height: 420)
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Snippets")
                    .font(.headline)
                Spacer()
                Button(action: addSnippet) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding(10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(workingSnippets) { snippet in
                        Button {
                            selectedID = snippet.id
                        } label: {
                            HStack {
                                Text(snippet.name.isEmpty ? "Untitled" : snippet.name)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selectedID == snippet.id ? Color.accentColor.opacity(0.15) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let index = selectedIndex {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: $workingSnippets[index].name)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $workingSnippets[index].html)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                    )
                HStack {
                    Spacer()
                    Button("Delete", role: .destructive, action: deleteSelected)
                }
            }
        } else {
            VStack {
                Spacer()
                Text("No snippet selected")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func addSnippet() {
        let new = Snippet(name: "New snippet", html: "")
        workingSnippets.append(new)
        selectedID = new.id
    }

    private func deleteSelected() {
        guard let index = selectedIndex else { return }
        workingSnippets.remove(at: index)
        selectedID = workingSnippets.first?.id
    }
}
```

- [ ] **Step 2: Wire the sheet in `PostEditorView`**

In `Sources/QuillKit/Views/Editor/PostEditorView.swift`, add a new `.sheet` modifier next to the existing `.sheet(isPresented: $showImagePicker)` block (after its closing `}` around line 169):

```swift
                .sheet(isPresented: $showSnippetManager) {
                    SnippetManagerView(
                        initialSnippets: appState.snippets,
                        onSave: { updated in
                            try? SnippetStore.save(updated)
                            appState.snippets = updated
                            showSnippetManager = false
                        },
                        onCancel: {
                            showSnippetManager = false
                        }
                    )
                }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/QuillKit/Views/Editor/SnippetManagerView.swift Sources/QuillKit/Views/Editor/PostEditorView.swift
git commit -m "feat: add Manage Snippets window"
```

---

### Task 6: Full verification pass

**Files:** none (verification only).

- [ ] **Step 1: Run the full automated test suite**

Run: `./test.sh`
Expected: All Swift tests (307+, three new from Task 1) and all JS tests (111+ transform tests with ~15 new snippet tests, 16+ keyboard tests with 2 new snippet tests) pass.

- [ ] **Step 2: Build and launch the app**

Run: `./build.sh && open Quill.app`
Expected: App builds and launches with no errors.

- [ ] **Step 3: Manual test — create a snippet and insert it (visual mode)**

1. Create a new local draft post.
2. Open Settings/whatever surfaces the toolbar; click the new snippet icon (two overlapping squares, next to the `</>` code-view button).
3. Click "Manage snippets…", click "+", name it "Test CTA", enter `<p>Subscribe to my newsletter!</p>` as the HTML, click Save.
4. Click the snippet button again — "Test CTA" should now appear in the list with a preview of its HTML.
5. Click it. A static card should appear in the editor showing the name and a truncated preview.
6. Type a sentence in a paragraph elsewhere in the post.
7. Toggle code view (`</>`). Confirm the raw HTML shows exactly:
   ```
   <!-- quill:snippet name="Test CTA" -->
   <p>Subscribe to my newsletter!</p>
   <!-- /quill:snippet -->
   ```
   with no wrapping `<div>` and no extra classes/attributes.
8. Toggle back to visual mode — the card should still be there, unchanged.

- [ ] **Step 4: Manual test — multi-element snippet and code-view insertion**

1. In Manage Snippets, create a second snippet named `Details Group` with HTML: `<details><summary>A</summary>1</details><details><summary>B</summary>2</details>`.
2. Toggle code view on the post from Step 3. Place the cursor at the end of the text. Click the snippet button, then click "Details Group" — the marker-wrapped text should be spliced directly into the textarea at the cursor.
3. Exit code view. A new card for "Details Group" should appear.
4. Re-enter code view and confirm both `<details>` elements are present verbatim between the markers.

- [ ] **Step 5: Manual test — name escaping**

1. Create a snippet named `Say "Hi" -- Bye` with HTML `<p>x</p>`.
2. Insert it, switch to code view, and confirm the marker reads `name="Say &quot;Hi&quot; - Bye"` (quotes escaped, double-dash collapsed to single).

- [ ] **Step 6: Manual test — save/reload round-trip**

1. Save the post (⌘S) or publish it as a draft.
2. Close and reopen the post (switch to another post/page, then back).
3. Confirm the snippet card(s) reappear with the correct name and content.
4. Confirm no wrapper `<div class="quill-snippet">` ever appears in code view — only the comment markers.

- [ ] **Step 7: Manual test — Cancel discards library edits**

1. Open Manage Snippets, rename a snippet, delete another, click Cancel.
2. Reopen Manage Snippets — confirm the previous rename/delete did not persist.
3. Repeat but click Save instead — confirm changes persist after quitting and relaunching Quill.

- [ ] **Step 8: Update CLAUDE.md**

Run the `claude-md-management:revise-claude-md` skill to document the new `SnippetBlock` node, the comment-marker round-trip mechanism, and the toolbar/manage-window wiring, per this project's "after major changes" convention.
