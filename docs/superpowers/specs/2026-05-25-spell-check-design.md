# Spell Check Design

**Date:** 2026-05-25  
**Status:** Approved

## Overview

Add on-demand spell checking to the Quill editor. The user clicks a toolbar button, misspelled words are highlighted with red wavy underlines, and highlights clear automatically on the first edit. Right-click on any highlighted word shows system spell suggestions (already functional via WebKit context menu).

No external API. Uses macOS `NSSpellChecker` — the same engine used by Pages, TextEdit, and every other Mac app. Works offline, no rate limits, respects the user's custom word list.

## Cleanup

Remove the earlier failed attempt at native spell checking:
- Remove `editorProps: { attributes: { spellcheck: 'true' } }` from the Tiptap `Editor` constructor in `editor.html`
- Remove `::spelling-error` and `::grammar-error` CSS rules from `editor.html`
- The `DroppableWebView` context menu changes (preserving spell suggestions before first separator) stay — they're still correct and useful

## Toolbar Button

Add an "ABC" button at the right end of the toolbar (before Undo/Redo), styled with a small red wavy underline beneath the text to make it self-referentially recognizable as a spell-check action. Uses the same `#toolbar button` styling as existing buttons.

## Data Flow

```
User clicks "ABC" button
  → JS: editor.getText() → postMessage({ type: 'checkSpelling', text })
  → Swift EditorCoordinator: NSSpellChecker loop over text
      collect misspelled word strings, deduplicate
  → Swift: evaluateJavaScript("window.applySpellErrors(JSON)")
  → JS: ProseMirror plugin receives word list
      walk doc.descendants(), regex-match each word in text nodes
      build DecorationSet of Decoration.inline nodes
  → CSS .spell-error: red wavy underline renders on matched spans
```

## Swift Side

### EditorView.makeNSView
Register a new `"checkSpelling"` message handler on `config.userContentController`.

### EditorCoordinator
Handle the `checkSpelling` WKScriptMessage:
1. Extract `text: String` from the message body
2. Run `NSSpellChecker.shared` in a loop:
   ```swift
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
   ```
3. Serialize to JSON array and call back into the webview:
   ```swift
   let json = try JSONSerialization.data(withJSONObject: Array(misspelled))
   let jsonString = String(data: json, encoding: .utf8)!
   webView?.evaluateJavaScript("window.applySpellErrors(\(jsonString))", completionHandler: nil)
   ```

## JS Side

### Imports
Add to the existing esm.sh import block at the top of `editor.html`:
```js
import { Plugin, PluginKey } from 'https://esm.sh/@tiptap/pm@2.11.5/state'
import { DecorationSet, Decoration } from 'https://esm.sh/@tiptap/pm@2.11.5/view'
```

### ProseMirror Plugin
A plugin that holds the current `DecorationSet`:
- **init**: `DecorationSet.empty`
- **apply**: if `tr.getMeta(spellCheckKey)` is set, use it; else if `tr.docChanged`, return `DecorationSet.empty` (auto-clear); else map existing set through `tr.mapping`
- **props.decorations**: return plugin state

### `window.applySpellErrors(words)`
Called by Swift with the array of misspelled word strings:
1. For each word, build a case-insensitive whole-word regex: `new RegExp('\\b' + escapeRegex(word) + '\\b', 'gi')`
2. Walk `state.doc.descendants((node, pos) => { ... })` — for text nodes only
3. For each match in the node's text, push `Decoration.inline(absStart, absEnd, { class: 'spell-error' })`
4. Create `DecorationSet.create(state.doc, decos)`
5. Dispatch `state.tr.setMeta(spellCheckKey, decoSet)`

### Toolbar Button
```html
<button id="btn-spell" title="Check Spelling">
  <span style="display:flex;flex-direction:column;align-items:center;line-height:1">
    <span>ABC</span>
    <span style="...red wavy underline SVG or CSS..."></span>
  </span>
</button>
```
On click: `window.webkit.messageHandlers.checkSpelling.postMessage(editor.getText())`

### CSS
```css
.spell-error {
  text-decoration: red wavy underline;
  text-decoration-skip-ink: none;
}
```

## Auto-Clear Behaviour

The ProseMirror plugin's `apply` method returns `DecorationSet.empty` whenever `tr.docChanged` is true. This means any insertion, deletion, or paste immediately clears all highlights. The user clicks the button again to re-check.

## Extension Registration

The spell-check plugin is registered as a Tiptap `Extension` (using `addProseMirrorPlugins()`) and added to the `extensions: [...]` array in the `Editor` constructor alongside `StarterKit`, `ResizableImage`, etc.

## Error Handling

- If the Swift serialization fails, no JS call is made (silent — no crash)
- If `applySpellErrors` receives an empty array (no misspellings found), it dispatches a clear (empty `DecorationSet`) — effectively a no-op visually but gives the user feedback that check ran (no red marks = all good)
- `escapeRegex` sanitizes word strings before building the regex to prevent injection from unusual characters

## Files Changed

- `Sources/QuillKit/Resources/editor.html` — cleanup, new CSS, new imports, toolbar button, JS plugin + handler
- `Sources/QuillKit/Views/Editor/EditorView.swift` — register `checkSpelling` message handler
- `Sources/QuillKit/Views/Editor/EditorCoordinator.swift` — handle `checkSpelling` message, NSSpellChecker loop, call back into webview
