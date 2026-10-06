# Custom HTML Block Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Insert a new Custom HTML (`core/html`) block from the insert menu, and edit an existing one from its card, through a native sheet with a plain-text box.

**Architecture:** The editor side adds two pure helpers to `editor-transforms.js` (read a block's inner HTML, build a block's source) and two bridge functions to `editor.html` (`window.editCustomHTML`, `window.insertCustomHTML`), reusing the read-only `gutenbergPassthrough` card and its `unsupportedSource` save path unchanged. The Swift side copies the gallery's round trip: a `customHTML` script message opens `CustomHTMLSheet`, and committing posts a notification that `EditorCoordinator` forwards to `window.insertCustomHTML`.

**Tech Stack:** Tiptap 2 / ProseMirror in WKWebView, plain JS (`editor-transforms.js` is a classic script), SwiftUI + AppKit (`NSTextView`), Node's test runner + jsdom, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-05-custom-html-block-design.md`

## Global Constraints

- macOS 27 only, Swift 6, no availability gates.
- Anything in `editor-transforms.js` that `editor.html` calls must be a `function` declaration, never a top-level `const` (root `CLAUDE.md` gotcha).
- Post markup is only ever parsed into `inertDocument()`; the user's HTML is never assigned to `innerHTML` of an element in the live page (`docs/gotchas.md`).
- Block source for a new block is exactly `<!-- wp:html -->\n` + html + `\n<!-- /wp:html -->`.
- Card label: `Custom HTML`. Card hint: `Renders as Custom HTML in WordPress · ` followed by an `Edit…` button. Sheet titles: `Custom HTML` (insert), `Edit Custom HTML` (edit). Default action: `Insert` / `Save`, ⌘↩, `.borderedProminent`; `Cancel` beside it; both in a bottom bar, trailing.
- Sheet text box: monospaced, 520pt wide, min 240pt tall; smart quotes, smart dashes, text replacement, spelling and autocorrect all off.
- Comments: one line maximum, none that restate the code or narrate the change (user `CLAUDE.md`).
- No commits. Each task ends with a checkpoint report; Chris commits on request, after a Codex review.
- After any code change, rebuild with the root `CLAUDE.md` build command; if the build fails, report the error instead of opening the app.

## Review Focus

1. **Caret inside a container (column, quote, list item, accordion panel) when inserting.** A nested `core/html` block has no card on reload (the wrap is top-level only) and would raise the blocks-at-risk banner, so the block must land after the enclosing top-level block. Test in Task 2.
2. **An HTML comment, blank lines or leading/trailing whitespace inside the snippet.** Edit must hand back exactly what was inserted. Test in Task 1.
3. **`</script>`, emoji, quotes, backslashes and U+2028 crossing the Swift → JS bridge.** The JSON payload must arrive unchanged. Swift-side encoding tested in Task 4, JS-side parsing in Task 2.
4. **Undo right after a Save from the edit sheet.** ⌘Z must restore the previous HTML in one step. Test in Task 2.
5. **A Custom HTML block whose comment carries attributes, or is self-closing (`<!-- wp:html /-->`), or whose HTML itself contains Gutenberg block delimiters.** Edit must keep the original opening comment byte for byte, produce a well-formed open/close pair, and never drop nested delimited content. Test in Task 1.

---

### Task 1: Pure helpers for Custom HTML source

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js` (next to `wrapFreeformHTML`; add both names to `module.exports`)
- Test: `Scripts/test-block-serializer.js` (new `describe('Custom HTML source')`)

**Interfaces:**
- Consumes: `parseBlocks` from `block-parser.js`, passed in as `parse`, the way `wrapUnsupportedBlocks(html, parse, doc)` takes it.
- Produces:
  - `customHTMLBlock(source, parse) -> { html: string, opener: string } | null` — non-null only when `source` is exactly one top-level `core/html` block (whitespace-only freeform around it allowed). `parse` only identifies the block and its `start`/`end` offsets; `html` is sliced from `source` itself, from the end of the opening comment to the start of the last `<!-- /wp:html` comment, with one leading `\n` and one trailing `\n` removed if present. Never use the parser's `innerHTML`: it omits nested blocks. `opener` is the original opening comment, byte for byte; a self-closing one has its `/-->` rewritten to `-->` and `html` is `''`.
  - `customHTMLSource(html, opener = '<!-- wp:html -->') -> string` — `opener` + `\n` + html + `\n<!-- /wp:html -->`.

- [ ] **Step 1: Write the failing tests**

```js
describe('Custom HTML source', () => {
  const { customHTMLBlock, customHTMLSource } = loadTransforms()
  const parse = loadParser().parseBlocks
  const roundTrip = html => customHTMLBlock(customHTMLSource(html), parse).html

  test('a new block is wrapped in bare wp:html delimiters', () => {
    assert.equal(customHTMLSource('<div>x</div>'), '<!-- wp:html -->\n<div>x</div>\n<!-- /wp:html -->')
  })
  test('the inner HTML comes back without the delimiters or their newlines', () => {
    assert.deepEqual(customHTMLBlock('<!-- wp:html -->\n<div>x</div>\n<!-- /wp:html -->', parse), { html: '<div>x</div>', opener: '<!-- wp:html -->' })
  })
  test('nested block delimiters inside the HTML are kept', () => {
    const html = '<div><!-- wp:paragraph --><p>a</p><!-- /wp:paragraph --></div>'
    assert.equal(roundTrip(html), html)
  })
  test('comments, blank lines and edge whitespace survive a round trip', () => {
    const html = '\n\n<!-- note -->\n<p>a</p>  \n'
    assert.equal(roundTrip(html), html)
  })
  test('the opening comment is kept byte for byte', () => {
    const src = '<!-- wp:html {"metadata":{"name":"Disclosure"},"n":33.0} -->\n<p>a</p>\n<!-- /wp:html -->'
    const block = customHTMLBlock(src, parse)
    assert.equal(block.opener, '<!-- wp:html {"metadata":{"name":"Disclosure"},"n":33.0} -->')
    assert.equal(customHTMLSource(block.html, block.opener), src)
  })
  test('a self-closing block reads as empty and is written as a pair', () => {
    const block = customHTMLBlock('<!-- wp:html {"n":1} /-->', parse)
    assert.deepEqual(block, { html: '', opener: '<!-- wp:html {"n":1} -->' })
    assert.equal(customHTMLSource('<p>a</p>', block.opener), '<!-- wp:html {"n":1} -->\n<p>a</p>\n<!-- /wp:html -->')
  })
  test('anything but a single Custom HTML block is null', () => {
    assert.equal(customHTMLBlock('<!-- wp:shortcode -->[x]<!-- /wp:shortcode -->', parse), null)
    assert.equal(customHTMLBlock('<!-- wp:html --><p>a</p><!-- /wp:html --><!-- wp:html --><p>b</p><!-- /wp:html -->', parse), null)
    assert.equal(customHTMLBlock('<p>loose</p><!-- wp:html --><p>a</p><!-- /wp:html -->', parse), null)
  })
})
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd Scripts && node --test test-block-serializer.js`
Expected: the seven new tests fail, each with `customHTMLBlock is not a function` or `customHTMLSource is not a function`.

- [ ] **Step 3: Implement `customHTMLBlock` and `customHTMLSource` in `editor-transforms.js`**, as `function` declarations, and export both.

- [ ] **Step 4: Run to verify they pass**

Run: `cd Scripts && node --test test-block-serializer.js`
Expected: all pass, 108 tests.

- [ ] **Step 5: Checkpoint** — report to Chris; do not commit.

---

### Task 2: Editor bridge — `window.insertCustomHTML` and `window.editCustomHTML`

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` (beside `window.editGallery` / `window.insertGallery`; and `window.__runScriptSinkProbes`)
- Test: `Scripts/test-editor-preservation.js` (new `describe('Custom HTML insert and edit')`)

**Interfaces:**
- Consumes: Task 1's `customHTMLBlock(source, parseBlocks)`, `customHTMLSource(html, opener)`; `unsupportedWrapper(doc, source, blockName)` and `inertDocument()` from `editor-transforms.js`; `_isInFootnote()`.
- Produces:
  - `window.editCustomHTML(pos: number) -> void` — when the node at `pos` is a `gutenbergPassthrough` whose `unsupportedSource` gives a non-null `customHTMLBlock`, stores the node in `let _customHTMLEdit` and posts `window.webkit.messageHandlers.customHTML.postMessage({ html })`. Otherwise does nothing.
  - `window.insertCustomHTML(json: string) -> void` — `json` is `{ "html": string, "replace": boolean }`. Builds the node `{ type: 'gutenbergPassthrough', attrs: { blockLabel: 'Custom HTML', unsupportedSource: source, sourceHTML: unsupportedWrapper(inertDocument(), source, 'core/html').outerHTML } }`. Replace: finds `_customHTMLEdit` by identity (as `replaceEditedGallery` does), uses `customHTMLSource(html, customHTMLBlock(old.attrs.unsupportedSource, parseBlocks).opener)` and replaces that node in one transaction; if not found, does nothing. Insert: `customHTMLSource(html)`; returns early inside a footnote; when the selection's `$from.depth > 1` it inserts at `$from.after(1)`, otherwise like `insertGallery` (after a selected node, else at the selection). Clears `_customHTMLEdit` in every case.

- [ ] **Step 1: Write the failing tests**

Stub the bridge in the describe's `before`: `win.webkit = { messageHandlers: { customHTML: { postMessage: m => posted.push(m) } } }`, with `posted.length = 0` before each test. `posted` holds jsdom-realm objects, so assert on `posted.length` and fields (`posted[0].html`), never `deepEqual` against a Node literal. `const editSave = () => { editor.commands.setTextSelection(1); editor.commands.insertContent('X'); return win.getContent() }`.

| Test | Assertions |
|---|---|
| `insert adds one Custom HTML card at the selection` | after `setContent('<p>Intro</p>')`, caret at 6 (end of `Intro`), `insertCustomHTML(JSON.stringify({ html: '<div class="box">Hi</div>', replace: false }))`: one `.passthrough-card` whose label is `Custom HTML`; `editSave()` contains `<!-- wp:html -->\n<div class="box">Hi</div>\n<!-- /wp:html -->` after `Intro</p>` |
| `editCustomHTML posts the inner HTML` | load `<!-- wp:html -->\n<p>a</p>\n<!-- /wp:html -->`, find the card's pos, call `editCustomHTML(pos)`: `posted.length === 1` and `posted[0].html === '<p>a</p>'` |
| `a replace changes only that card and keeps its comment attributes` | load two Custom HTML blocks, the second `{"metadata":{"name":"N"}}`; edit the second, `insertCustomHTML({ html: '<p>new</p>', replace: true })`: first block unchanged in `editSave()`, second is `<!-- wp:html {"metadata":{"name":"N"}} -->\n<p>new</p>\n<!-- /wp:html -->` |
| `a replace after the card was deleted changes nothing` | edit a card, delete it (`deleteRange` over it), replace: doc text and card count unchanged from after the delete |
| `undo after a replace restores the old HTML in one step` | load, wait 600 ms (past prosemirror-history's `newGroupDelay`, as the gallery's undo test does), edit, replace with `<p>new</p>`, `editor.commands.undo()`: card's `unsupportedSource` is the original |
| `editCustomHTML ignores other cards` | load a `wp:shortcode` block, call `editCustomHTML(pos)`: `posted` is empty |
| `inserting inside a column puts the block after the columns` | load the nested-columns source from the existing `an unmodeled block nested in a modeled container` test with a paragraph in the column; caret in that paragraph; insert: `editor.state.doc.childCount` grew by one and the new card is a top-level child right after `columnsBlock` |
| `inserting in a footnote does nothing` | caret inside a footnote item (reuse a footnote fixture from `test-editor-footnotes.js`): doc unchanged |
| `special characters survive the JSON payload` | html `'<script>"\\</script>😀\u2028'`; after insert, the card's `unsupportedSource` equals `customHTMLSource(html)` |
| `inserted HTML never runs a handler` | `win.__ran = 0`; insert `<img src="x" onerror="window.__ran++">`; `editSave()`; await 50 ms: `win.__ran === 0` |

- [ ] **Step 2: Run to verify they fail**

Run: `cd Scripts && node --test test-editor-preservation.js`
Expected: the ten new tests fail (`win.insertCustomHTML is not a function`).

- [ ] **Step 3: Implement both functions in `editor.html`**, and in `window.__runScriptSinkProbes` call `window.insertCustomHTML(JSON.stringify({ html: source, replace: false }))` after `window.setContent('<p></p>')`, so `--check-fixtures` covers the insert path in WebKit.

- [ ] **Step 4: Run to verify they pass**

Run: `cd Scripts && node --test test-editor-preservation.js`
Expected: all pass, 61 tests.

- [ ] **Step 5: Checkpoint** — report to Chris; do not commit.

---

### Task 3: Editor UI — the card's Edit… button and the insert-menu item

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` — `PassthroughNodeView` (around the `// ── Generic Gutenberg block passthrough` section), `GutenbergPassthrough.addNodeView`, the card CSS next to `.passthrough-card-hint`, `#insert-menu` markup, `INSERT_ACTIONS`
- Test: `Scripts/test-editor-preservation.js` (same describe as Task 2)

**Interfaces:**
- Consumes: Task 2's `window.editCustomHTML(pos)`; Task 1's `customHTMLBlock`.
- Produces: insert-menu item `data-insert="customHTML"`, whose action is `window.webkit?.messageHandlers?.customHTML?.postMessage({})`. `PassthroughNodeView` constructor becomes `(node, getPos)`.

- [ ] **Step 1: Write the failing tests**

| Test | Assertions |
|---|---|
| `a Custom HTML card offers Edit…` | load a `wp:html` block: `.passthrough-card-hint` text starts with `Renders as Custom HTML in WordPress · ` and holds a `button` with text `Edit…`; clicking it (`detail: 1`) posts `{ html }` |
| `double-clicking a Custom HTML card opens the editor` | dispatch `dblclick` on the card: one message posted |
| `other cards keep the Code View hint` | load `wp:calendar`: hint is `Not editable in the visual editor; use Code View (</>)`, no button |
| `the insert menu offers Custom HTML` | `#insert-menu [data-insert="customHTML"]` exists with label `Custom HTML`, directly after the Preformatted item; clicking it posts `{}` |

- [ ] **Step 2: Run to verify they fail**

Run: `cd Scripts && node --test test-editor-preservation.js`
Expected: the four new tests fail.

- [ ] **Step 3: Implement.** The button and double-click follow the gallery card's exactly (`event.detail < 2` guard on the button; double-click ignores the button). Style `.passthrough-card-hint button` like `.gallery-card-hint button`, dark mode included.

- [ ] **Step 4: Run to verify they pass**

Run: `cd Scripts && node --test test-editor-preservation.js`
Expected: all pass, 65 tests.

- [ ] **Step 5: Checkpoint** — report to Chris; do not commit.

---

### Task 4: Swift plumbing — `CustomHTMLRequest`, the message handler, the notification

**Files:**
- Create: `Sources/QuillKit/Views/Editor/CustomHTMLSheet.swift` (holds `CustomHTMLRequest` now, the sheet in Task 5)
- Modify: `Sources/QuillKit/Views/Editor/EditorView.swift` (register `customHTML`; `onCustomHTML` property, init parameter, both coordinator assignments, mirroring `onInsertGallery`)
- Modify: `Sources/QuillKit/Views/Editor/EditorCoordinator.swift` (`case "customHTML"`; observer for the new notification; `insertCustomHTML(html:replace:)`)
- Test: `Tests/QuillTests/PostEditorHelpersTests.swift`

**Interfaces:**
- Produces:
  - `public struct CustomHTMLRequest: Identifiable { public let id: UUID; public let html: String?; public init?(body: Any) }` — public, like `GalleryEdit`, because it appears in `EditorView`'s public init; `{}` gives `html == nil` (insert); `{ "html": String }` gives an edit; a non-dictionary body, or an `html` that is present but not a `String`, gives `nil`.
  - `public var isEditing: Bool { html != nil }`
  - `Notification.Name.insertCustomHTML` (`"Quill.insertCustomHTML"`), `userInfo: ["html": String, "replace": Bool]`.
  - `EditorCoordinator.onCustomHTML: ((CustomHTMLRequest) -> Void)?`, called on the main queue.
  - `static func EditorCoordinator.customHTMLScript(html: String, replace: Bool) -> String?` — encodes `["html": html, "replace": replace]` with `JSONSerialization`, then that string again with `JSONEncoder`, exactly as `insertGallery(payload:)` does, and returns `"insertCustomHTML(<escaped>)"`.
  - `EditorCoordinator.insertCustomHTML(html: String, replace: Bool)` — evaluates `customHTMLScript(html:replace:)` in the web view.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func customHTMLRequestReadsAnInsertBody() {
    #expect(CustomHTMLRequest(body: [String: Any]())?.html == nil)
    #expect(CustomHTMLRequest(body: [String: Any]())?.isEditing == false)
}
@Test func customHTMLRequestReadsAnEditBody() {
    #expect(CustomHTMLRequest(body: ["html": "<p>a</p>"])?.html == "<p>a</p>")
}
@Test func customHTMLRequestRejectsAMalformedBody() {
    #expect(CustomHTMLRequest(body: "x") == nil)
    #expect(CustomHTMLRequest(body: ["html": 3]) == nil)
}
@Test func customHTMLScriptCarriesSpecialCharactersIntact() throws {
    let html = "<script>\"\\</script>😀\u{2028}"
    let script = try #require(EditorCoordinator.customHTMLScript(html: html, replace: true))
    #expect(script.hasPrefix("insertCustomHTML(") && script.hasSuffix(")"))
    let argument = String(script.dropFirst("insertCustomHTML(".count).dropLast())
    let json = try JSONDecoder().decode(String.self, from: Data(argument.utf8))
    let payload = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    #expect(payload["html"] as? String == html)
    #expect(payload["replace"] as? Bool == true)
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter PostEditorHelpersTests`
Expected: build error, `cannot find 'CustomHTMLRequest' in scope`.

- [ ] **Step 3: Implement** `CustomHTMLRequest`, the handler registration, the coordinator case and observer, and `insertCustomHTML(html:replace:)`.

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --filter PostEditorHelpersTests`
Expected: all pass.

- [ ] **Step 5: Checkpoint** — report to Chris; do not commit.

---

### Task 5: The sheet and its text box

**Files:**
- Create: `Sources/QuillKit/Views/Editor/CodeTextView.swift`
- Modify: `Sources/QuillKit/Views/Editor/CustomHTMLSheet.swift` (add the view)
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift` (`@State private var customHTMLSheet: CustomHTMLRequest?`; `onCustomHTML: { customHTMLSheet = $0 }` on `EditorView`; `.sheet(item: $customHTMLSheet)` beside the gallery sheet)

**Interfaces:**
- Consumes: Task 4's `CustomHTMLRequest`, `Notification.Name.insertCustomHTML`.
- Produces:
  - `struct CodeTextView: NSViewRepresentable { @Binding var text: String }` — an `NSTextView` in an `NSScrollView`, monospaced system font at body size, `isRichText = false`, `allowsUndo = true`, and `isAutomaticQuoteSubstitutionEnabled`, `isAutomaticDashSubstitutionEnabled`, `isAutomaticTextReplacementEnabled`, `isAutomaticSpellingCorrectionEnabled`, `isContinuousSpellCheckingEnabled` all `false`. Becomes first responder when it appears. Coordinator writes `text` on `textDidChange`, as `TitleTextField` does.
  - `struct CustomHTMLSheet: View { init(request: CustomHTMLRequest, onCommit: (String) -> Void, onCancel: () -> Void) }` — title and buttons per Global Constraints; `.padding(20)`; text box 520 wide, min 240 tall, inside the same 0.5pt rounded outline `GeneratePostSheet` draws around its `TextEditor`; default action disabled when the text is whitespace-only; starts with `request.html ?? ""`.
  - `PostEditorView`: `onCommit` posts `.insertCustomHTML` with `["html": text, "replace": request.isEditing]` and sets `customHTMLSheet = nil`; `onCancel` sets it to `nil`.

- [ ] **Step 1: Build**

Run: `pkill -f "^$PWD/Quill.app/Contents/MacOS/Quill"; sleep 2 && ./build.sh 2>&1 && open Quill.app`
Expected: `✓ Built: Quill.app`, the app opens.

- [ ] **Step 2: Verify in the app** (computer use with full control, on a new local draft — "+ New Post", discarded afterwards)

1. Insert menu → Custom HTML: the sheet opens titled `Custom HTML`, box focused, Insert disabled.
2. Type `<div class="box">"Hi" -- there</div>`: the quotes and `--` stay straight.
3. ⌘↩: a `Custom HTML` card appears with the preview and `Edit…`.
4. Save Locally, then `sqlite3 ~/Library/Application\ Support/Quill/drafts.db "select content from local_drafts order by updated_at desc limit 1;"`: holds `<!-- wp:html -->\n<div class="box">"Hi" -- there</div>\n<!-- /wp:html -->`.
5. Double-click the card: `Edit Custom HTML` with the HTML filled in; change it; Save: the preview updates. ⌘Z: the old HTML is back.
6. Cancel from the edit sheet: nothing changes.

- [ ] **Step 3: Checkpoint** — report to Chris with what was seen; do not commit.

---

### Task 6: Docs and full verification

**Files:**
- Modify: `docs/block-model.md` (the `gutenbergPassthrough` entry: Custom HTML cards are editable through `CustomHTMLSheet`)
- Modify: `Sources/QuillKit/Resources/CLAUDE.md` (output-table row for the unsupported wrapper: inserted and edited `core/html` blocks take the same path)
- Modify: `docs/testing-plan.md` (suite counts, the new describe tables, the header totals)
- Modify: `CLAUDE.md` (test totals; add `CustomHTMLSheet` to `Views/Editor/` in the Architecture block)
- Modify: `site/docs.html` (a short "Custom HTML" section beside the other block descriptions: what it is, insert from the menu, Edit… or double-click to change, not previewed in Quill)

- [ ] **Step 1: Run everything**

Run: `./test.sh`
Expected: `✓ All test suites passed (18/18)`.

Run: `./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"`
Expected: `23/23 passed` and `ok    no script handler ran`.

- [ ] **Step 2: Update the docs** with the counts the run printed.

- [ ] **Step 3: Checkpoint** — summarise the whole feature for Chris; do not commit.
