# Media panel — native conversion design

Date: 2026-09-19
Status: implemented 2026-09-19
Scope: the Media section only — its sidebar, its content column and its
metadata panel. `MediaPickerView` and `GallerySheet` are deliberately out of
scope and keep their own grids.

## Problem

The Media section is the only part of Quill that still carries pre-native UI.
It shows a bordered-prominent "+ New Media" button in a hand-drawn bottom strip
at `MediaSidebarSection.swift:90`, where every other section puts Refresh and
New in the window toolbar.

This was not an oversight. The native-ui spec froze the media branch on
purpose: "That branch survives the conversion unchanged in behaviour"
(`2026-09-18-native-ui-design.md:105`). Only a colour and token audit was
applied to it. This design reverses that scope decision.

Four concrete defects follow from the freeze.

### 1. Duplicate controls

`SidebarView` attaches its toolbar to the whole `Group`, so the toolbar's
Refresh and New buttons appear in the Media section too. The bottom strip
supplies a second pair. Both pairs bind Command-R and Command-N.

### 2. The toolbar's New Media button creates a post

`SidebarView.swift:33` shows the new-item button for every section except
`.localDrafts`, and its action is always `createNewDraft()`. In the Media
section it reads "New Media" and creates a post draft. Only the bottom strip's
button uploads a file.

### 3. The shared empty state is bypassed

`SidebarEmptyState` already carries a `.media` case that reads "Create one with
the new-media button in the toolbar" (`SidebarView.swift:333`). The media panel
never calls it. It hardcodes its own text that reads "Upload with the + button
below". After this change the empty state belongs to the content column, not
the sidebar: the sidebar always holds five filter rows and can never be
empty.

### 4. No native selection or keyboard navigation

The media list is a `LazyVGrid` inside a `ScrollView`, with selection driven by
`onTapGesture` and drawn as a hand-rolled accent stroke. Arrow keys do nothing.
`.searchable` is attached to the post list only, so the search field disappears
when the user switches to Media.

### 5. The toolbar's Refresh button does nothing in Media

`loadCurrentSection()` has `case .media: break` (`SidebarView.swift:230`). The
toolbar Refresh button is therefore inert in the Media section. Only the bottom
strip's button reloads. Deleting the strip without fixing this would remove
refresh from the section entirely.

## Goal

Media gets the same three-part shape as Posts: a sidebar list, a content
column, and an inspector. It browses as a gallery in the content column, the
way Photos and Finder's gallery view work.

## Layout

```
sidebar: filter list   |  content: media gallery  |  inspector: metadata
```

1. **Sidebar** — a `List(selection:)` of filters, with the search field above
   it. The section picker stays in the toolbar above that.
2. **Content column** — `MediaLibraryView`, holding the gallery and the empty
   state. It calls the shared
   `SidebarEmptyState(section:isSearching:)`, which already carries a `.media`
   case. Its hint text must change from "button in the toolbar" wording only if
   the toolbar wording changes; it is correct as written.
3. **Inspector** — the surviving half of `MediaDetailView`, presented with
   `.inspector(isPresented:)`, matching `PostEditorView.swift:287`. A
   `sidebar.right` toolbar button toggles it, matching the Post Settings button
   at `PostEditorView.swift:330`, and it is disabled when nothing is selected.

   **Visibility is its own state, not a function of the selection.** Closing the
   inspector must not deselect the image, and selecting another image must not
   reopen it. Binding visibility directly to `selectedMedia != nil` was the
   first implementation, and it left no way to close the panel at all except by
   clicking empty gallery space, which nobody would find. The rule is: once you
   close it, it stays closed until you press the button again.

### Interaction

| Input | Result |
| --- | --- |
| Single click | Selects the item; the inspector updates |
| Space | Opens the large preview overlay |
| Space or Escape, while open | Closes the overlay |
| Double-click | Opens the large preview overlay |
| Arrow keys | Move the selection |
| Scroll near the end | Loads the next page |

**What the user loses.** Today a single click shows a large image immediately.
After this change a single click selects, and Space opens the large view. This
is one extra action on the most common task in the panel. It is the deliberate
cost of giving the thumbnails room to breathe: the current cells are 80pt tall
in a 270pt column, which is too small to tell two photographs apart.

## The gallery control

SwiftUI has no selectable grid on macOS. `LazyVGrid` has no selection binding.
Only `List` and `Table` provide selection, keyboard navigation and focus, and
neither has the right form for a gallery.

**Decision: wrap `NSCollectionView` in an `NSViewRepresentable`.** It is the
control Photos and Finder use. Selection, arrow keys and rubber-band selection
all arrive with it.

This adds a third AppKit bridge to the codebase. Two already exist:
`EditorView.swift:4` wraps `WKWebView` and `TitleTextField.swift:4` wraps
`NSTextField`. The cost is therefore a known and already-accepted one, not a
new class of problem.

The rejected alternative was a `LazyVGrid` with hand-wired focus, arrow-key
index maths and a custom selection highlight. That is the same class of custom
code that let this panel drift out of line in the first place.

### Structure

`MediaGalleryView: NSViewRepresentable` builds an `NSCollectionView` inside an
`NSScrollView`. Its `Coordinator` is the data source and the delegate. It
reports the selected item to SwiftUI through a `@Binding`, and reports
"scrolled near the end" through a closure.

**Thumbnails need no new loading code.** Each collection view item hosts a
SwiftUI `AsyncImage` inside an `NSHostingView`. This reuses the loading code
already at `MediaSidebarSection.swift:321`. The alternative was writing an
`NSImage` cache by hand.

**Context menus must be rebuilt in AppKit.** Copy URL, Open in Browser and
Delete are a SwiftUI `.contextMenu` today. `NSCollectionView` needs
`menu(for:)`. The actions themselves are unchanged.

## The large preview

Space and double-click fade a large image in over the gallery. Space or Escape
dismisses it. It reuses `AsyncImage`, so it needs no download and no temporary
files. Non-image types show a file icon, matching today's "Preview
unavailable".

**Why not the system Quick Look panel.** `QLPreviewPanel` previews files on
disk, and Quill's media lives on a web server. Whether `QLPreviewPanel` accepts
a remote URL is unverified, and the reliable fallback — downloading every file
to a temporary folder before previewing — adds a wait and temporary-file
management for a feature that is a large image in a pane.

## Data and filters

### Client

`fetchMedia` at `WordPressClient.swift:113` gains two optional parameters,
`mediaType` and `search`. When both are nil the call behaves exactly as it does
today, so `MediaPickerView` and `GallerySheet` need no change.

The `/wp/v2/media` endpoint accepts `media_type`, `mime_type` and `search`.
Confirmed against the WordPress REST API reference.

### Filters

A new `MediaFilter` type holds the five sidebar rows.

| Row | `media_type` sent |
| --- | --- |
| All Media | none |
| Images | `image` |
| Documents | `application` |
| Audio | `audio` |
| Video | `video` |

**Accepted gap.** `application` covers PDFs, Word files and archives. It does
not cover plain text. A `.txt` upload appears under All Media but not under
Documents. The alternative is two requests per Documents view, and merging two
paginated result sets breaks the sort order.

**Verify the enum before relying on it.** The exact set of values WordPress
accepts for `media_type` must be confirmed against a live site with one
request during implementation. Do not assume it from this table.

**Date filters are out of scope.** The REST API gives no list of the months
that contain media. Building one means downloading every item's date before the
sidebar can draw. Revisit only if the type filters prove insufficient.

### Paging

Changing the filter or the search text clears the list, returns to page 1 and
issues a new request. The selected item clears if the new results do not
contain it; `MediaSidebarSection.swift:233` already does this.

The "Load more" button is removed. The gallery requests the next page when the
user scrolls near the end.

**Known inefficiency, deliberately kept.** The code infers that more items
exist when a page returns exactly `perPage` items. A library holding exactly 30
items therefore costs one extra empty request. Fixing this means reading the
`X-WP-TotalPages` response header, which means changing how `WordPressClient`
returns results. Not worth it here.

### Effect on the editor's cache

`appState.mediaItems` is not only this panel's list. `PostEditorView.swift:116`
reads it as a cache to find image sizes for the Thumb, Medium, Large and Full
buttons. Once filters apply, that array holds the filtered list, so a filtered
view can miss an image the editor wants.

The editor already falls back to `fetchMediaItem` for exactly this case, and
`Views/Editor/CLAUDE.md` documents that the fallback is essential. The size
buttons still appear. The cost is one network request.

## Toolbar

The new-item button in `SidebarView` branches on the section. In Media it
uploads a file, reusing the shared `pickImageFromDisk()` and
`uploadPickedImage(_:credentials:)` helpers in `MediaPickerView.swift`. This
fixes defect 2.

The bottom strip and its duplicate Refresh button are deleted, fixing defect 1.

`loadCurrentSection()` replaces its `case .media: break` with a real reload,
fixing defect 5. That reload must honour the active filter and the current
search text, not fetch the unfiltered first page.

**Search sits in the sidebar, as it does for Posts.** `.searchable(placement:
.sidebar)` attaches to `MediaSidebarSection`, so the field appears above the
filter list, in the same place and with the same treatment as the post list's.

This reverses an earlier decision in this document, which put the field above
the gallery because search filters media rather than filters. That reasoning was
sound but lost to consistency: with the field on the right it read as detached
from the rest of the window, and every other section of Quill puts search in the
sidebar. The sidebar is also where macOS apps put a field that filters the
content list.

## Out of scope

`MediaPickerView` and `GallerySheet` keep their own grids. They are separate
flows with separate needs. They will look different from the new gallery, which
is an accepted consequence.

## Files

| File | Change |
| --- | --- |
| `API/WordPressClient.swift` | `fetchMedia` gains `mediaType` and `search` |
| `App/AppState.swift` | new `MediaFilter`, selected filter, search text |
| `Views/Media/MediaGalleryView.swift` | new — the AppKit bridge |
| `Views/Media/MediaLibraryView.swift` | new — the content column |
| `Views/Media/MediaSidebarSection.swift` | becomes the filter list; most of it deleted |
| `Views/Media/MediaDetailView.swift` | trimmed to the metadata panel |
| `Views/ContentView.swift` | new content column and inspector |
| `Views/Sidebar/SidebarView.swift` | toolbar branch for upload; media refresh |
| `Tests/QuillTests/WordPressClientTests.swift` | new URL tests |

## Testing

**Automated.** Swift tests cover the new query parameters and the
`MediaFilter` mapping, using the existing URL-stub pattern in
`WordPressClientTests.swift`. No JavaScript changes, so `./test.sh` and
`--check-fixtures` should hold at their current counts. Run both regardless.

**By hand.** The AppKit bridge cannot be unit tested.

1. Arrow keys move the selection in both directions and across rows.
2. The inspector follows the selection.
3. Deleting the selected item clears the selection and removes the thumbnail.
4. Uploading adds a thumbnail without leaving a stale selection.
5. Scrolling to the end loads the next page.
6. Each filter returns the right items.
7. Search filters, and clearing search restores the full list.
8. Space opens and closes the overlay, and does not fire while the search
   field has focus.
9. The toolbar Refresh button reloads the gallery and keeps the active filter.
10. The gallery renders correctly in light and dark appearance.

Follow the project rule for computer-use testing: start a new local draft, and
never test on a published post or page.

## Risks

1. **Appearance.** `NSCollectionView` does not follow dark mode or the accent
   colour on its own. Quill has been hurt by AppKit appearance mismatches
   before; see the `Picker` workaround removed in commit 4bc933a. Check both
   appearances, and judge colour from a native-resolution pixel scan rather
   than a downsampled screenshot.
2. **Selection synchronisation.** The binding must stay correct in both
   directions. Delete and upload are the cases most likely to leave a stale
   selection.
3. **Key handling.** The overlay must not take the Space key while the search
   field has focus.
