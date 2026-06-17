# AI Buttons in Tiptap Toolbar

**Date:** 2026-06-17
**Status:** Approved

## Goal

Move the two AI action buttons — Generate Post (✦) and Evaluate Writing (✓) — from the SwiftUI top toolbar into the Tiptap HTML toolbar inside the WKWebView editor. This places them contextually next to the content they operate on and sets the stage for removing AI-specific logic from the SwiftUI toolbar layer.

## Placement

A new `tb-group` is appended at the far right of `#toolbar`, after the existing separator and Add image group:

```
… [spell | </>] [sep] [Add image] [sep] [✦ | ✓]
```

The AI buttons are document-level actions (not inline formatting), so they belong visually separated from the formatting groups. The rightmost slot is the correct home.

## HTML/CSS (editor.html)

Add after the Add image group:

```html
<span class="tb-sep"></span>
<span class="tb-group" id="ai-toolbar-group" style="display:none">
  <button id="btn-generate" title="Generate post with Claude">
    <svg viewBox="0 0 24 24"><path d="M17 3a2.828 2.828 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3z"/></svg>
  </button>
  <button id="btn-evaluate" title="Evaluate writing quality">
    <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/></svg>
  </button>
</span>
```

The group starts hidden. `setAIEnabled(true)` reveals it; `setAIEnabled(false)` hides it. Both buttons use inline SVG at `viewBox="0 0 24 24"` matching the existing toolbar icon pattern — no new CSS needed. The generate button uses a pencil/edit icon (not the generic sparkle); the evaluate button uses a checkmark-in-circle.

## JS Functions (editor.html)

```js
window.setAIEnabled = enabled => {
  document.getElementById('ai-toolbar-group').style.display = enabled ? '' : 'none'
}

window.setEvaluating = active => {
  document.getElementById('btn-evaluate').disabled = active
}
```

Both functions are called by Swift via `evaluateJavaScript`.

Button event listeners use `mousedown` + `e.preventDefault()` (matching the existing `btn-footnote` pattern) and post messages via the WKWebView bridge:

```js
document.getElementById('btn-generate').addEventListener('mousedown', e => {
  e.preventDefault()
  window.webkit.messageHandlers.triggerGenerate.postMessage({})
})
document.getElementById('btn-evaluate').addEventListener('mousedown', e => {
  e.preventDefault()
  window.webkit.messageHandlers.triggerEvaluate.postMessage({})
})
```

## Swift Bridge

### EditorView.makeNSView

Register two new handlers alongside existing ones:

```swift
config.userContentController.add(context.coordinator, name: "triggerGenerate")
config.userContentController.add(context.coordinator, name: "triggerEvaluate")
```

### EditorCoordinator

Add two optional callbacks and handle the new message names:

```swift
var onTriggerGenerate: (() -> Void)?
var onTriggerEvaluate: (() -> Void)?

// in userContentController(_:didReceive:):
case "triggerGenerate": onTriggerGenerate?()
case "triggerEvaluate": onTriggerEvaluate?()
```

### PostEditorView

Wire callbacks in the `EditorView` coordinator setup, containing the same logic as the removed SwiftUI buttons:

- `onTriggerGenerate`: checks if content is empty → opens sheet directly or shows replace-content alert
- `onTriggerEvaluate`: closes settings panel, shows evaluation panel, runs evaluation if no cached result

### State Sync — setAIEnabled

Add `var aiEnabled: Bool = false` to `EditorCoordinator`. `EditorView.updateNSView` already sets `nsView.aiEnabled`; also set `context.coordinator.aiEnabled = aiEnabled` there, and call `window.setAIEnabled` when the value changes:

```swift
if context.coordinator.aiEnabled != aiEnabled {
    context.coordinator.aiEnabled = aiEnabled
    nsView.evaluateJavaScript("window.setAIEnabled?.(\(aiEnabled))", completionHandler: nil)
}
```

Also call it from `applyColorScheme()` to handle the initial `editorReady` load:

```swift
wv.evaluateJavaScript("window.setAIEnabled?.(\(aiEnabled))", completionHandler: nil)
```

The `?.` guard makes both calls safe before the JS function is defined.

### State Sync — setEvaluating

Called from `PostEditorView.executeEvaluation()` at the two points where `isEvaluating` flips:

```swift
editorWebView?.evaluateJavaScript("window.setEvaluating?.(true)", completionHandler: nil)
// ... evaluation runs ...
editorWebView?.evaluateJavaScript("window.setEvaluating?.(false)", completionHandler: nil)
```

## Cleanup

After the Tiptap buttons are verified working:

- Remove the `if appState.aiEnabled { ... }` block from the SwiftUI toolbar (the `Divider`, `✦` button, and `checkmark.circle` button)
- The `showAIReplaceAlert` SwiftUI alert body stays; only its trigger moves from the SwiftUI button action to the `onTriggerGenerate` callback
- All evaluation state (`isEvaluating`, `evaluationResult`, `evaluationError`, `executeEvaluation()`) remains in `PostEditorView` — only the entry point changes

## Files Changed

- `Sources/QuillKit/Resources/editor.html` — new toolbar group, JS functions, event listeners
- `Sources/QuillKit/Views/Editor/EditorView.swift` — two new handler registrations
- `Sources/QuillKit/Views/Editor/EditorCoordinator.swift` — two callbacks, two message cases, `setAIEnabled` call in `applyColorScheme`
- `Sources/QuillKit/Views/Editor/PostEditorView.swift` — wire callbacks, add `setEvaluating` calls, remove SwiftUI AI buttons
