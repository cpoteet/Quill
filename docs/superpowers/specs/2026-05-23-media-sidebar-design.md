# Media Sidebar Design

**Date:** 2026-05-23  
**Status:** Approved

## Problem

The Media tab currently shows a full-screen browser in the main content area, leaving the sidebar collapsed and empty. The media browser was non-interactive (thumbnails couldn't be clicked to do anything useful in browser mode). The feature felt broken and purposeless.

## Goal

Move media thumbnails into the left sidebar (consistent with the posts/pages/drafts pattern), add a detail view in the main area for selected images, and add a context menu with useful actions per thumbnail.

## Design

### State (AppState)

Four new published fields:

```swift
@Published var mediaItems: [WPMedia] = []
@Published var selectedMedia: WPMedia?
@Published var isLoadingMedia: Bool = false
@Published var mediaError: String?
```

These mirror the pattern used for `posts`, `pages`, and `localDrafts`.

### API (WordPressClient)

Add one new method:

```swift
public func deleteMedia(id: Int) async throws
// DELETE /wp/v2/media/{id}?force=true
// Uses performVoid — media has no trash state, deletion is permanent
```

### Sidebar — MediaSidebarSection

A new `MediaSidebarSection` view, embedded in `SidebarView` when `selectedSection == .media` (replacing the current `else { Spacer() }` branch).

Layout (top to bottom):
1. Loading indicator row (when `isLoadingMedia`)
2. Error row with message (when `mediaError != nil`)
3. `ScrollView` → `LazyVGrid` with 2 adaptive columns, spacing 4pt
4. `Divider`
5. Bottom toolbar: refresh button (left, ⌘R) + `+ Upload` button (right, ⌘N)

**Thumbnail cell:**
- `AsyncImage` at ~110×82pt, `.fill` content mode, `.clipped()`
- `RoundedRectangle(cornerRadius: 6)` clip shape + 0.5pt separator stroke overlay
- Selected state: 2pt amber border (matching the amber left-edge bar used on posts)
- `.onTapGesture` sets `appState.selectedMedia`

**Context menu per thumbnail:**
| Action | Detail |
|---|---|
| Copy URL | Copies `media.sourceURL` to `NSPasteboard` |
| Copy as Markdown | Copies `![title.rendered](sourceURL)` |
| Open in Browser | `NSWorkspace.shared.open(URL(string: media.link)!)` — requires adding `link: String` to `WPMedia` |
| *(separator)* | |
| Delete… | Destructive. Shows confirmation alert before calling `deleteMedia(id:)` |

**Note:** `WPMedia` needs two new optional fields added via `decodeIfPresent`:
- `link: String` — the WordPress attachment page URL (for Open in Browser)
- `date: String` — ISO8601 upload date (for the detail view)

**Data loading:** `MediaSidebarSection` has a `.task` that calls `loadMedia()` on appear, same pattern as `SidebarView.loadAllSections()`. Refresh button re-fires the same task. Upload button opens `NSOpenPanel` and uses the existing upload logic extracted from the old `MediaPickerView`.

**Delete flow:**
- Context menu "Delete…" → sets `mediaPendingDelete: WPMedia?` state
- Alert fires: "Delete permanently? This cannot be undone."
- Confirm → calls `WordPressClient.deleteMedia(id:)`, removes from `appState.mediaItems`, clears `appState.selectedMedia` if it was the deleted item

### Main Area — MediaDetailView + Placeholder

`ContentView` media branch:

```swift
if appState.selectedSection == .media {
    if let media = appState.selectedMedia {
        MediaDetailView(media: media)
    } else {
        MediaEmptyPlaceholder()
    }
}
```

**MediaDetailView layout:**
- Top: `AsyncImage` preview, `maxHeight: 320`, `.aspectRatio(contentMode: .fit)`, centered, subtle background
- Bottom: metadata list
  - **Filename** — `media.title.rendered`
  - **Type** — `media.mimeType`
  - **Dimensions** — `"\(media.mediaDetails?.width ?? 0) × \(media.mediaDetails?.height ?? 0) px"` (hidden if both zero)
  - **Uploaded** — formatted `media.date` (hidden if empty)
  - **URL** — truncated `media.sourceURL` with a copy-to-clipboard button

**MediaEmptyPlaceholder:** Same style as `EmptyEditorPlaceholder` — centered photo icon + "Select an image to preview".

### MediaPickerView Changes

- Remove `.browser` case and `MediaPickerMode` enum (no longer needed — browsing is now the sidebar)
- Keep all `.picker` mode logic intact — it is still used for editor image insertion via sheet
- Simplify: `MediaPickerView` becomes a picker-only sheet, removing the `mode` parameter

### Files Changed / Created

| File | Change |
|---|---|
| `AppState.swift` | Add `mediaItems`, `selectedMedia`, `isLoadingMedia`, `mediaError` |
| `WPMedia.swift` | Add `link` and `date` fields via `decodeIfPresent` |
| `WordPressClient.swift` | Add `deleteMedia(id:)` |
| `SidebarView.swift` | Replace `else { Spacer() }` with `MediaSidebarSection()` |
| `ContentView.swift` | Update media branch to show `MediaDetailView` / placeholder |
| `MediaPickerView.swift` | Remove browser mode, simplify to picker-only |
| `MediaSidebarSection.swift` | **New** — thumbnail grid, context menu, bottom toolbar |
| `MediaDetailView.swift` | **New** — large preview + metadata |

## Non-Goals

- Pagination (load more than 50 items) — not in scope
- Search/filter within media — not in scope
- Editing media metadata (alt text, caption) — not in scope
- Multi-select — not in scope
