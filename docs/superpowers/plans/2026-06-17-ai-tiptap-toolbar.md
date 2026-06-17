# AI Buttons in Tiptap Toolbar — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Generate Post (pencil) and Evaluate Writing (checkmark-circle) buttons from the SwiftUI toolbar into the Tiptap HTML toolbar, wired via the existing WKWebView JS↔Swift message bridge.

**Architecture:** New `tb-group` HTML added to `editor.html`'s toolbar; two new JS window functions (`setAIEnabled`, `setEvaluating`) let Swift toggle visibility/state; two new message handlers (`triggerGenerate`, `triggerEvaluate`) fire Swift callbacks; SwiftUI toolbar block removed after verification.

**Tech Stack:** Swift 6, SwiftUI/AppKit, WKWebView message bridge, Tiptap HTML toolbar (vanilla JS + inline SVG)

---

## File Map

| File | Change |
|------|--------|
| `Sources/QuillKit/Resources/editor.html` | Add toolbar HTML group, JS window functions, mousedown listeners |
| `Sources/QuillKit/Views/Editor/EditorCoordinator.swift` | Add `aiEnabled` property, two callbacks, two message cases, `setAIEnabled` in `applyColorScheme` |
| `Sources/QuillKit/Views/Editor/EditorView.swift` | Add two callback parameters, register two message handlers, sync `aiEnabled` to coordinator in `updateNSView` |
| `Sources/QuillKit/Views/Editor/PostEditorView.swift` | Pass closures to EditorView, add `setEvaluating` calls in `executeEvaluation`, remove old SwiftUI AI button block |

---

### Task 1: Add AI toolbar group and JS to editor.html

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`

- [ ] **Step 1: Add the HTML toolbar group**

In `editor.html`, find the end of the Add image group (around line 876):

```html
      </button>
    </span>
  </div>
```

Insert the new AI group immediately before `</div>`:

```html
      </button>
    </span>
    <span class="tb-sep"></span>
    <span class="tb-group" id="ai-toolbar-group" style="display:none">
      <button id="btn-generate" title="Generate post with Claude">
        <svg viewBox="0 0 24 24"><path d="M17 3a2.828 2.828 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3z"/></svg>
      </button>
      <button id="btn-evaluate" title="Evaluate writing quality">
        <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/></svg>
      </button>
    </span>
  </div>
```

- [ ] **Step 2: Add JS window functions and event listeners**

In `editor.html`, find the block where `btn-code-view` and `btn-footnote` listeners are set up (search for `btn-code-view').addEventListener`). After those listeners, add:

```js
    // AI toolbar buttons
    window.setAIEnabled = enabled => {
      document.getElementById('ai-toolbar-group').style.display = enabled ? '' : 'none'
    }
    window.setEvaluating = active => {
      document.getElementById('btn-evaluate').disabled = active
    }
    window.setEvaluationPanelOpen = open => {
      document.getElementById('btn-evaluate').classList.toggle('active', open)
    }
    document.getElementById('btn-generate').addEventListener('mousedown', e => {
      e.preventDefault()
      window.webkit.messageHandlers.triggerGenerate.postMessage({})
    })
    document.getElementById('btn-evaluate').addEventListener('mousedown', e => {
      e.preventDefault()
      window.webkit.messageHandlers.triggerEvaluate.postMessage({})
    })
```

- [ ] **Step 3: Build to verify no syntax errors**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html
git commit -m "feat: add AI buttons to Tiptap toolbar (HTML + JS)"
```

---

### Task 2: Wire message handlers in EditorCoordinator and EditorView

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/EditorCoordinator.swift`
- Modify: `Sources/QuillKit/Views/Editor/EditorView.swift`

- [ ] **Step 1: Add properties to EditorCoordinator**

In `EditorCoordinator.swift`, after the existing callback properties (after `var onStatsChanged: ((Int, Int) -> Void)?`), add:

```swift
var onTriggerGenerate: (() -> Void)?
var onTriggerEvaluate: (() -> Void)?
var aiEnabled: Bool = false
```

- [ ] **Step 2: Add message cases to EditorCoordinator**

In `userContentController(_:didReceive:)`, after the `checkSpelling` case (before the closing `default:` or end of switch), add:

```swift
case "triggerGenerate":
    DispatchQueue.main.async { self.onTriggerGenerate?() }
case "triggerEvaluate":
    DispatchQueue.main.async { self.onTriggerEvaluate?() }
```

- [ ] **Step 3: Update applyColorScheme to sync AI state**

In `EditorCoordinator.applyColorScheme()`, after the `setDarkMode` call:

```swift
func applyColorScheme() {
    guard let wv = webView else { return }
    let isDark = wv.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    wv.evaluateJavaScript("setDarkMode(\(isDark))", completionHandler: nil)
    wv.evaluateJavaScript("window.setAIEnabled?.(\(aiEnabled))", completionHandler: nil)
}
```

- [ ] **Step 4: Register new message handlers in EditorView.makeNSView**

In `EditorView.makeNSView`, after the existing handler registrations:

```swift
config.userContentController.add(context.coordinator, name: "triggerGenerate")
config.userContentController.add(context.coordinator, name: "triggerEvaluate")
```

- [ ] **Step 5: Add callback properties to EditorView**

In `EditorView`, after `var onAIOperation: ((AIWritingOperation) -> Void)?`, add:

```swift
var onTriggerGenerate: (() -> Void)?
var onTriggerEvaluate: (() -> Void)?
```

- [ ] **Step 6: Add init parameters to EditorView**

In `EditorView.init`, after `onAIOperation: ((AIWritingOperation) -> Void)? = nil`, add:

```swift
onTriggerGenerate: (() -> Void)? = nil,
onTriggerEvaluate: (() -> Void)? = nil,
```

And in the init body after `self.onAIOperation = onAIOperation`:

```swift
self.onTriggerGenerate = onTriggerGenerate
self.onTriggerEvaluate = onTriggerEvaluate
```

- [ ] **Step 7: Wire callbacks in EditorView.makeNSView**

After `context.coordinator.onStatsChanged = onStatsChanged`, add:

```swift
context.coordinator.onTriggerGenerate = onTriggerGenerate
context.coordinator.onTriggerEvaluate = onTriggerEvaluate
```

- [ ] **Step 8: Wire callbacks in EditorView.updateNSView**

After `context.coordinator.onStatsChanged = onStatsChanged`, add:

```swift
context.coordinator.onTriggerGenerate = onTriggerGenerate
context.coordinator.onTriggerEvaluate = onTriggerEvaluate
if context.coordinator.aiEnabled != aiEnabled {
    context.coordinator.aiEnabled = aiEnabled
    nsView.evaluateJavaScript("window.setAIEnabled?.(\(aiEnabled))", completionHandler: nil)
}
```

- [ ] **Step 9: Build**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 10: Commit**

```bash
git add Sources/QuillKit/Views/Editor/EditorCoordinator.swift \
        Sources/QuillKit/Views/Editor/EditorView.swift
git commit -m "feat: add triggerGenerate/triggerEvaluate bridge handlers and aiEnabled sync"
```

---

### Task 3: Wire callbacks in PostEditorView and add setEvaluating calls

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift`

- [ ] **Step 1: Pass onTriggerGenerate closure to EditorView**

In `PostEditorView`, in the `EditorView(...)` constructor (around the `hasTextSelection:` line), add before the closing `)`:

```swift
onTriggerGenerate: {
    let trimmed = htmlContent.trimmingCharacters(in: .whitespacesAndNewlines)
    let titleIsEmpty = title.isEmpty || title == "Untitled"
    let contentIsEmpty = titleIsEmpty && (trimmed.isEmpty || trimmed == "<p></p>")
    if contentIsEmpty {
        isAISheetOpen = true
    } else {
        showAIReplaceAlert = true
    }
},
onTriggerEvaluate: {
    if !isEvaluating {
        isSettingsOpen = false
        showEvaluationPanel = true
        if evaluationResult == nil && evaluationError == nil {
            Task { await executeEvaluation() }
        }
    }
},
```

- [ ] **Step 2: Add setEvaluating calls in executeEvaluation**

In `PostEditorView.executeEvaluation()`, wrap the `isEvaluating` flips with JS calls. Replace:

```swift
isEvaluating = true
evaluationResult = nil
evaluationError = nil
```

with:

```swift
isEvaluating = true
evaluationResult = nil
evaluationError = nil
editorWebView?.evaluateJavaScript("window.setEvaluating?.(true)", completionHandler: nil)
```

And replace the final `isEvaluating = false` with:

```swift
isEvaluating = false
editorWebView?.evaluateJavaScript("window.setEvaluating?.(false)", completionHandler: nil)
```

- [ ] **Step 3: Add .onChange to sync panel-open state to the evaluate button**

In `PostEditorView`, add this modifier on the outermost view (alongside the existing `.onChange(of: item.id)` modifier):

```swift
.onChange(of: showEvaluationPanel) { open in
    editorWebView?.evaluateJavaScript("window.setEvaluationPanelOpen?.(\(open))", completionHandler: nil)
}
```

This covers every code path that toggles the panel (the close button, opening from the toolbar, post switching, and the settings button dismissal) without needing inline calls at each site.

- [ ] **Step 4: Build**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 5: Smoke test the new buttons**

```bash
open "/Users/Chris/Documents/Claude/WP Mac App/Quill.app"
```

Verify:
- If AI key is configured, pencil and checkmark-circle appear at the far right of the Tiptap toolbar
- If no AI key, the group is hidden
- Clicking the pencil (with empty post) opens the Generate sheet
- Clicking the pencil (with existing content) shows the "Replace Content?" alert
- Clicking the checkmark-circle opens the Evaluation panel and runs evaluation
- Evaluate button appears highlighted/active while the panel is open
- Closing the panel removes the highlight from the evaluate button
- Evaluate button is disabled (greyed) while evaluation is in flight

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/Views/Editor/PostEditorView.swift
git commit -m "feat: wire onTriggerGenerate/onTriggerEvaluate callbacks and setEvaluating sync"
```

---

### Task 4: Remove old SwiftUI AI buttons

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift`

- [ ] **Step 1: Remove the SwiftUI AI button block**

In `PostEditorView`, find and delete the entire `if appState.aiEnabled { ... }` block in the toolbar. It starts with `if appState.aiEnabled {` and ends with the closing `}` after `.disabled(isEvaluating)`. The block to remove:

```swift
if appState.aiEnabled {
    Divider().frame(height: 20)
    Button {
        let trimmed = htmlContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleIsEmpty = title.isEmpty || title == "Untitled"
        let contentIsEmpty = titleIsEmpty && (trimmed.isEmpty || trimmed == "<p></p>")
        if contentIsEmpty {
            isAISheetOpen = true
        } else {
            showAIReplaceAlert = true
        }
    } label: {
        Text("✦")
            .font(.system(size: 13))
    }
    .help("Generate post with Claude")
    Button {
        if !isEvaluating {
            isSettingsOpen = false
            showEvaluationPanel = true
            if evaluationResult == nil && evaluationError == nil {
                Task { await executeEvaluation() }
            }
        }
    } label: {
        Image(systemName: "checkmark.circle")
            .font(.system(size: 13))
    }
    .help("Evaluate writing quality")
    .disabled(isEvaluating)
}
```

- [ ] **Step 2: Build**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Final verification**

```bash
open "/Users/Chris/Documents/Claude/WP Mac App/Quill.app"
```

Verify:
- SwiftUI toolbar no longer shows AI buttons
- Tiptap toolbar shows pencil + checkmark-circle at far right (when AI enabled)
- Both buttons work as before
- Buttons hidden when no API key configured
- Evaluate button disables during evaluation
- Switching posts clears evaluation state (existing behavior, no regression)
- Dark mode: toolbar buttons render correctly in both appearances

- [ ] **Step 4: Commit and push**

```bash
git add Sources/QuillKit/Views/Editor/PostEditorView.swift
git commit -m "feat: remove SwiftUI AI toolbar buttons — now live in Tiptap toolbar"
git push
```
