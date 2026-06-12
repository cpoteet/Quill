# Discard Changes — Design Spec

**Date:** 2026-06-12

## Problem

For remote posts (server posts), the autosave writes every change to SQLite. Closing and reopening restores the autosaved state — there is no escape hatch to get back to the last-saved server version without manually undoing all changes.

## Solution

Add a "Revert" button to the editor toolbar that discards local changes and reloads the post from the server.

## Behavior

### Visibility

The button appears only when `isRemote && isDirty`. It is hidden for local drafts (nothing to revert to) and when the post is clean (no changes to discard). Works for both posts and pages.

### Placement

Plain-text button in the toolbar, left of the "Preview" button, styled with `.buttonStyle(.plain)` to match the "Save Draft" / "Preview" button aesthetics. No icon — text label "Revert" is clear and direct.

### Confirmation

Tapping "Revert" shows a destructive alert:
- **Title:** "Revert to Server Version?"
- **Message:** "Your unsaved changes will be lost."
- **Buttons:** "Revert" (destructive role) + "Cancel"

### Action

On confirm, `discardChanges()` runs:
1. `loadFromServer(postID:)` — fetches the server post, applies it to the editor, resets `cleanTitle`/`cleanContent` (making `isDirty = false`)
2. `services.autosaveStore.delete(postID:)` — purges the SQLite autosave snapshot so it is not restored on next open

## Implementation

### New state

```swift
@State private var showDiscardAlert: Bool = false
```

### Toolbar addition

In the `toolbar` computed property, inside the `if isRemote` branch, before the "Preview" button:

```swift
if isDirty {
    Button("Revert") { showDiscardAlert = true }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
}
```

### Alert

Added to the view body alongside existing alerts:

```swift
.alert("Revert to Server Version?", isPresented: $showDiscardAlert) {
    Button("Revert", role: .destructive) { discardChanges() }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("Your unsaved changes will be lost.")
}
```

### discardChanges()

```swift
private func discardChanges() {
    guard case .remote(let post) = item else { return }
    try? services.autosaveStore.delete(postID: post.id)
    loadFromServer(postID: post.id)
}
```

## Files changed

- `Sources/QuillKit/Views/Editor/PostEditorView.swift` — new state, toolbar button, alert, `discardChanges()`
