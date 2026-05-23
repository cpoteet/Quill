# Unsaved Changes — Preserve & Restore

**Date:** 2026-05-23  
**Status:** Approved

## Overview

When a user navigates away from a post or page with unsaved changes, the app silently flushes the current editor state to SQLite and restores it when the user returns. No blocking alert, no automatic push to WordPress. A subtle amber dot in the toolbar signals pending unsaved content.

## Dirty Tracking

`PostEditorView` adds two `@State` baselines: `cleanTitle: String` and `cleanContent: String`. These represent the last-known-clean state — either loaded from WordPress/SQLite at open time, or reset after a successful save/publish.

A computed `isDirty: Bool` returns `title != cleanTitle || htmlContent != cleanContent`.

`PostSettings` gains `Equatable` conformance so settings changes are also included in the flush on navigate (though the toolbar indicator is driven by `isDirty` for simplicity).

Baselines are updated at two moments:
1. After `loadItem()` populates the editor (including after a stash restore).
2. After a successful save or publish response from WordPress.

## Flush on Navigate

`PostEditorView` tracks a new `@State private var loadedItemID: String?` — the ID of the item whose content is currently live in the editor.

When `.task(id: item.id)` fires because the selected item changed, `loadItem()` first checks:

- `loadedItemID != nil`
- `loadedItemID != item.id`
- `isDirty`

If all three are true, it immediately flushes the current `title`, `htmlContent`, and `settings` to SQLite before overwriting the editor state:

- **Remote posts** → `AutosaveStore.save(postID:title:content:serverModified:)`
- **Local drafts** → `DraftStore.update(id:title:content:excerpt:)` + update the corresponding entry in `appState.localDrafts` in-place

After flushing, `loadedItemID` is updated to the new item's ID and `loadItem()` proceeds normally.

The existing 30-second debounced autosave is unchanged — it continues to run as a crash backstop.

## Restore on Return

After `loadItem()` sets the editor content from the post/draft data, it checks for a stash:

**Remote posts:**  
Calls `AutosaveStore.load(postID:)`. If a snapshot is found, its content replaces the just-loaded WP content in the editor, `cleanTitle`/`cleanContent` are updated to match the snapshot, and a toast fires: `"Unsaved changes restored"`.

**Local drafts:**  
`loadItem()` reads content directly from `DraftStore` (SQLite) rather than from the `LocalDraft` embedded in `appState.selectedItem`. This means the navigate-flush is automatically picked up on return. If the SQLite content differs from the appState copy, the toast fires.

**Stash cleanup:**  
`AutosaveStore.delete(postID:)` is called after a successful save or publish so stale content is never restored on a future visit to an already-saved post.

## Dirty Indicator

A small amber dot (`Color.wpAmber`, ~6pt circle) is shown in the editor toolbar immediately to the left of the "Save Draft" button when `isDirty` is true. It disappears when:
- The user saves or publishes successfully.
- The user navigates away (flush fires, editor reloads clean for the new item).

The dot is not shown in the sidebar row — that would require propagating dirty state to `AppState` for no meaningful gain, since only one item is edited at a time.

## Files Affected

| File | Change |
|------|--------|
| `Views/Editor/PostEditorView.swift` | Dirty tracking, flush-on-navigate, stash restore, toolbar dot |
| `Storage/AutosaveStore.swift` | Confirm `delete(postID:)` is called after save/publish (already exists) |
| `Storage/DraftStore.swift` | Add `load(id:) -> LocalDraft?` method for direct SQLite reads in `loadItem()` |
| `API/Models/PostSettings.swift` or inline | Add `Equatable` conformance to `PostSettings` |

## Behavior Matrix

| Scenario | Result |
|----------|--------|
| Edit remote post, navigate away, return | Content restored from AutosaveStore, toast shown |
| Edit local draft, navigate away, return | Content restored from DraftStore (SQLite), toast shown |
| Edit post, save, navigate away, return | No stash; loads fresh WP data, no toast |
| Edit post, navigate away, then save from sidebar (impossible) | N/A — can only save from editor |
| Edit post, quit app, reopen, navigate to post | AutosaveStore persists; content restored on load, toast shown |
| Edit local draft, quit app, reopen, click draft | DraftStore persists; content loaded directly from SQLite |

## Out of Scope

- Settings panel changes (categories, tags, slug, etc.) are flushed on navigate but do **not** drive the dirty indicator — title/content only for the dot.
- No restore UI for "which version do you want?" — stash silently wins over WP data on return.
- No per-field conflict resolution between stash and WP server state.
