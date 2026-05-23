# Link Picker Design

**Date:** 2026-05-23
**Status:** Approved

## Overview

Replace the current bare `NSAlert` prompt for inserting links with a WordPress-style popover that supports both manual URL entry and live search across WordPress content (posts, pages, categories, tags, and media).

## User Experience

### Trigger

Clicking the **Link** toolbar button inside the Tiptap editor opens a popover anchored directly below the button.

### Two states

**Adding a link** (cursor is on plain text):
- URL field is empty
- Search results area is empty until the user types
- Single "Apply Link" button

**Editing an existing link** (cursor is inside a linked span):
- URL field is pre-filled with the current `href`
- Search results populate immediately with a search for the current URL text (optional) or wait for input
- Both "Apply Link" and "Remove Link" buttons visible

### Interaction flow

1. User types in the URL/search field
2. If the text looks like a URL (starts with `http://`, `https://`, `/`, or `#`) — no search is triggered; the field is treated as a direct URL entry
3. Otherwise — after a 300 ms debounce, a search fires against the WordPress API
4. Results appear below the field: title on the left, a type badge (Post / Page / Category / Tag / Media) on the right
5. Clicking a result **fills the URL field** with that item's URL — it does not immediately apply the link
6. User reviews/edits the URL, then presses Enter or clicks **Apply Link**
7. Clicking **Remove Link** unsets the link and closes the popover
8. Clicking outside or pressing Escape closes without changes

### Popover dimensions

Width: 320 pt. Height: expands with results, max ~360 pt with scroll if needed.

## Architecture

### 1. `editor.html` — JS side

- Remove the `prompt()` call in the `link` command
- On link button `mousedown`, gather:
  - `editor.getAttributes('link').href` (current href or empty string)
  - `document.querySelector('[data-cmd="link"]').getBoundingClientRect()` (button position in viewport)
- Send `showLinkPicker` message: `{ href, rect: { x, y, width, height } }`
- Add two new global functions Swift will call:
  - `window.applyLink(url)` — calls `editor.chain().focus().setLink({ href: url }).run()`
  - `window.removeLink()` — calls `editor.chain().focus().unsetLink().run()`

### 2. `LinkPickerView.swift` — new file

SwiftUI view used as the `NSPopover` content view controller.

**Props (passed in at construction):**
- `currentHref: String` — pre-fills the URL field
- `onApply: (String) -> Void`
- `onRemove: () -> Void`
- `onSearch: (String) async throws -> [LinkSearchResult]` — search closure; keeps the view decoupled from `WordPressClient`

**State:**
- `@State fieldText: String` — bound to the URL/search field
- `@State results: [LinkSearchResult]` — current search results
- `@State isSearching: Bool` — shows loading indicator
- `@State searchTask: Task<Void, Never>?` — debounce handle

**Layout (top to bottom):**
```
[ URL / search field                  × ]
──────────────────────────────────────────
  Result title                    Post
  Result title                    Page
  Result title                   Categ.
  ...
──────────────────────────────────────────
[ Remove Link ]           [ Apply Link ]
```
- "Remove Link" button is hidden when `currentHref` is empty
- "Apply Link" is disabled when `fieldText` is empty
- Results area hidden when `fieldText` is empty and no results
- Clicking a result sets `fieldText` to that result's URL (does not apply)

### 3. `EditorCoordinator.swift` — changes

- Store a new `onSearchLinks: ((String) async throws -> [LinkSearchResult])?` closure (passed in from `EditorView`)
- Register `showLinkPicker` as a WKUserContentController message name
- Handle `showLinkPicker` message:
  - Parse `href` and `rect` from the message body dictionary
  - Convert rect from JS viewport coordinates to WKWebView `NSRect`:
    - `NSRect(x: rect.x, y: webView.bounds.height - rect.y - rect.height, width: rect.width, height: rect.height)`
  - Create `LinkPickerView` with `onApply`, `onRemove`, and `onSearch` closures; `onApply`/`onRemove` call `applyLink(url)` / `removeLink()` via `evaluateJavaScript`
  - Wrap in `NSHostingController`, attach to a new `NSPopover`, show relative to the converted rect on the WKWebView with `preferredEdge: .maxY`
- Remove the `WKUIDelegate` `runJavaScriptTextInputPanelWithPrompt` method (no longer needed)
- Remove `WKUIDelegate` conformance
- Remove `webView.uiDelegate` assignment in `EditorView`

### 4. `WordPressClient.swift` — additions

New method: `searchLinks(query: String) async throws -> [LinkSearchResult]`

Fires up to three parallel requests:
1. `/wp/v2/search?search={query}&type=post&subtype=post,page&per_page=5` → posts and pages
2. `/wp/v2/search?search={query}&type=term&subtype=category,tag&per_page=5` → categories and tags
3. `/wp/v2/media?search={query}&per_page=3` → media items

Results are merged in that order (posts/pages first, then terms, then media) and returned as `[LinkSearchResult]`.

### 5. `LinkSearchResult.swift` — new model

```swift
struct LinkSearchResult: Identifiable {
    let id: String          // "\(type)-\(wpId)" to avoid collisions across types
    let wpId: Int
    let title: String
    let url: String
    let type: LinkResultType
}

enum LinkResultType: String {
    case post, page, category, tag, media
    var badge: String {
        switch self {
        case .post:     return "Post"
        case .page:     return "Page"
        case .category: return "Category"
        case .tag:      return "Tag"
        case .media:    return "Media"
        }
    }
}
```

The WordPress `/wp/v2/search` endpoint returns `{ id, title: { rendered }, url, type, subtype }`.
The `/wp/v2/media` endpoint returns `{ id, title: { rendered }, source_url }` — `source_url` is used as the link URL for media.

## Error Handling

- Search errors are silently ignored (results list stays empty / shows previous results) — the user can still type a URL manually
- If the API is unreachable, the field still works as a plain URL entry box

## Files Changed

| File | Change |
|------|--------|
| `Sources/WPWriterKit/Resources/editor.html` | Replace `prompt()` with `showLinkPicker` message; add `applyLink`/`removeLink` globals |
| `Sources/WPWriterKit/Views/Editor/EditorCoordinator.swift` | Handle `showLinkPicker`; show NSPopover; remove WKUIDelegate |
| `Sources/WPWriterKit/Views/Editor/EditorView.swift` | Add `onSearchLinks` parameter; remove `uiDelegate` assignment |
| `Sources/WPWriterKit/Views/Editor/LinkPickerView.swift` | New file — popover SwiftUI content |
| `Sources/WPWriterKit/API/WordPressClient.swift` | Add `searchLinks(query:)` method |
| `Sources/WPWriterKit/API/Models/LinkSearchResult.swift` | New model file |
