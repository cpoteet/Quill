# Delete Post / Draft — Design Spec

**Date:** 2026-05-22  
**Status:** Approved

## Overview

Add the ability to delete items from the sidebar:
- Remote WordPress posts and pages → moved to WordPress Trash (reversible via WP admin)
- Local drafts → permanently deleted from SQLite

## API Layer

Two new public methods on `WordPressClient`:

```swift
func trashPost(id: Int) async throws
func trashPage(id: Int) async throws
```

Both call `DELETE /wp-json/wp/v2/{posts|pages}/{id}?force=false`, which moves the post to WordPress Trash without permanent removal. A private `delete(_:)` helper handles the HTTP verb; the response body is discarded (WordPress returns a partial post object with `status: "trash"` — not needed).

## UI Trigger

A `.contextMenu` modifier is added to each row button in `SidebarView`'s `ForEach`. Menu items:

- Remote post/page: **"Move to Trash"** — `trash` system image, `.destructive` role
- Local draft: **"Delete Draft"** — `trash` system image, `.destructive` role

## Confirmation

Before executing either delete, a SwiftUI `.confirmationDialog` (or `.alert`) asks:
- Title: `"Move to Trash?"` / `"Delete Draft?"`
- Message: identifies the item by title
- Buttons: **Cancel** (default) and **Move to Trash** / **Delete** (destructive)

The pending-delete item is stored as `@State var itemPendingDelete: PostItem?` in `SidebarView`. Setting it non-nil triggers the confirmation sheet; confirming executes the action.

## State Management

After successful deletion:

1. Remove from the relevant `AppState` array in-place:
   - `appState.posts.removeAll { $0.id == id }`
   - `appState.pages.removeAll { $0.id == id }`
   - `appState.localDrafts.removeAll { $0.id == id }`
2. If `appState.selectedItem` matches the deleted item, set it to `nil` (clears the editor)
3. No full list refresh — local mutation is sufficient

For local drafts, `DraftStore.delete(id:)` already exists and is called before the array mutation.

## Error Handling

If the network call throws (remote delete), show an alert with the error message. The item remains in the list. Local draft deletion has no network call and failure is unlikely, but errors are silently ignored (SQLite delete failure is non-recoverable without user action).

## Files Changed

| File | Change |
|------|--------|
| `API/WordPressClient.swift` | Add `trashPost`, `trashPage`, private `delete` helper |
| `Views/Sidebar/SidebarView.swift` | Add `.contextMenu`, `@State itemPendingDelete`, confirmation alert, delete logic |

No new files needed. `DraftStore.delete(id:)` already exists — no storage changes required.
