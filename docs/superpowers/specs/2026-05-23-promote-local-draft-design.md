# Promote Local Draft to WordPress — Design

## Problem

When a user saves or publishes a local draft to WordPress, `PostEditorView.save()` correctly deletes the SQLite record but never updates `appState.localDrafts`. The draft stays visible in the sidebar until the user manually switches sections.

## Behavior After Fix

1. Local draft disappears immediately from the Drafts list.
2. The created remote post is prepended to `appState.posts` / `appState.pages`.
3. The sidebar navigates to Posts or Pages (matching the post type).
4. The editor transitions to the remote post (same content, now editable as a WP post).

## Implementation

One location: `PostEditorView.save()`, `.local(let draft)` case, after `DraftStore.delete`.

```swift
appState.localDrafts.removeAll { $0.id == draft.id }
if draft.type == "page" {
    appState.pages.insert(created, at: 0)
    appState.selectedSection = .pages
} else {
    appState.posts.insert(created, at: 0)
    appState.selectedSection = .posts
}
appState.selectedItem = .remote(created)
```

`ContentView` derives the editor from `appState.selectedItem`, so setting it to `.remote(created)` replaces the editor with a fresh `PostEditorView` bound to the new remote post.

## Edge Cases

- **Any status (draft / publish / future):** same promotion logic applies regardless of publish status.
- **Prepend vs append:** new posts go to the front to match the API's newest-first ordering.
- **No partial update:** the four state mutations happen only after both the WP create call and the SQLite delete succeed; a failure leaves the local draft intact.
