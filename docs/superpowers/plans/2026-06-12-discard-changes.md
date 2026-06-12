# Discard Changes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Revert" button to the editor toolbar for remote posts that discards local changes and reloads the server version.

**Architecture:** All changes are in `PostEditorView.swift`. A new `showDiscardAlert` state triggers a confirmation alert; on confirm, `discardChanges()` deletes the autosave snapshot and calls the existing `loadFromServer(postID:)` to reload and reset dirty state.

**Tech Stack:** Swift 6, SwiftUI

---

### Task 1: Add state, toolbar button, alert, and discardChanges()

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift`

This is a UI-only change with no separately testable logic (the underlying `loadFromServer` and `autosaveStore.delete` are already exercised by existing paths). No new test file needed.

- [ ] **Step 1: Add the new state variable**

In `PostEditorView`, with the other `@State` declarations (around line 26), add:

```swift
@State private var showDiscardAlert: Bool = false
```

- [ ] **Step 2: Add the Revert button to the toolbar**

In the `toolbar` computed property, inside the `if isRemote {` block (around line 247), add the Revert button before the Preview button:

Replace:
```swift
            if isRemote {
                Button("Preview") { Task { await openPreview() } }
                    .buttonStyle(.bordered)
                    .disabled(isSaving)
            }
```

With:
```swift
            if isRemote {
                if isDirty {
                    Button("Revert") { showDiscardAlert = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Button("Preview") { Task { await openPreview() } }
                    .buttonStyle(.bordered)
                    .disabled(isSaving)
            }
```

- [ ] **Step 3: Add the confirmation alert**

In the view body's modifier chain, after the existing `.alert("Replace Content?", ...)` block (around line 153), add:

```swift
        .alert("Revert to Server Version?", isPresented: $showDiscardAlert) {
            Button("Revert", role: .destructive) { discardChanges() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your unsaved changes will be lost.")
        }
```

- [ ] **Step 4: Add the discardChanges() function**

In the `// MARK: - Load` section, after `loadFromServer(postID:)` (around line 658), add:

```swift
    private func discardChanges() {
        guard case .remote(let post) = item else { return }
        try? services.autosaveStore.delete(postID: post.id)
        loadFromServer(postID: post.id)
    }
```

- [ ] **Step 5: Build and verify**

```bash
./build.sh
```

Expected: build succeeds with no errors or warnings.

- [ ] **Step 6: Manual test**

1. Open the app and open a remote post
2. Make an edit — confirm "Revert" button appears in the toolbar left of "Preview"
3. Click "Revert" — confirm alert appears with "Revert to Server Version?" title
4. Click "Cancel" — confirm changes are preserved and alert dismisses
5. Make another edit, click "Revert", click "Revert" in the alert — confirm editor reloads server content and "Revert" button disappears (post is now clean)
6. Quit and reopen the app, open the same post — confirm the reverted (server) content loads, not the discarded edits

- [ ] **Step 7: Commit**

```bash
git add Sources/QuillKit/Views/Editor/PostEditorView.swift
git commit -m "feat: add Revert button to discard local changes on remote posts"
```
