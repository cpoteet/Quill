# Local Draft Save — Design Spec

**Date:** 2026-05-25
**Status:** Approved

## Problem

The "Save Draft" button (⌘S) currently always calls the WordPress REST API, even for local drafts. Pressing it promotes the local SQLite draft to a WordPress draft post immediately. Users want to save work locally without touching WordPress until they are ready.

## Goal

- "Save Draft" for local drafts saves to SQLite only — no WordPress call.
- The right button ("Publish Draft" / "Publish" / "Schedule") remains the only path to WordPress for local drafts.
- When the right button sends a local draft to WordPress, the local copy is removed and the user is navigated to the live post/page list (existing behavior, unchanged).
- For remote posts/pages, "Save Draft" is hidden. ⌘S triggers the right button instead.

## Approach

Approach A — surgical split inside `PostEditorView`. No schema changes, no new files.

## Design

### Toolbar button visibility

| Item | "Save Draft" button | Right button |
|---|---|---|
| `.local` draft | Visible — saves to SQLite only | "Publish Draft" / "Publish" / "Schedule" — sends to WordPress |
| `.remote` post/page | Hidden | "Publish Draft" / "Update" / "Schedule" — updates WordPress |

### Keyboard shortcut

- When item is `.local`: ⌘S is on "Save Draft" (local save).
- When item is `.remote`: ⌘S moves to the right button (WordPress update), matching existing muscle memory.

### Local save path — `saveLocalOnly()`

New private function in `PostEditorView`:

1. Calls `DraftStore.update(id:title:content:excerpt:)` — no new schema fields needed.
2. Updates `appState.localDrafts[idx]` in place (same pattern as autosave).
3. Sets `cleanTitle` and `cleanContent` so `isDirty` clears.
4. Shows toast: `"Saved locally"`.

No credentials required. No taxonomy creation. No WordPress call.

### `saveDraft()` routing

```swift
private func saveDraft() async {
    switch item {
    case .local: await saveLocalOnly()
    case .remote: await save(status: "draft")  // unreachable — button hidden for remote
    }
}
```

The remote branch is dead code once the button is hidden, but kept for safety.

### Send to WordPress (local → remote)

The `.local` branch of `save()` is unchanged: creates the post/page on WordPress, deletes the local SQLite record, removes it from `appState.localDrafts`, inserts the returned `WPPost` into `appState.posts`/`appState.pages`, and navigates to the live section.

### Toast messages

| Action | Toast |
|---|---|
| Save Draft (local only) | "Saved locally" |
| Publish Draft → WordPress as draft | "Draft saved" |
| Publish | "Published" |
| Schedule | "Scheduled" |

## Out of scope

- Saving post settings (categories, tags, slug, featured image) on local save. `LocalDraft` does not store these fields today. See CLAUDE.md → Future architecture options for a full local draft settings design.
- Autosave behavior is unchanged.
- Remote post conflict detection is unchanged.
