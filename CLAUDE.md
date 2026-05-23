# WPWriter

Native macOS app for writing and managing WordPress content. Built with Swift Package Manager (no Xcode needed).

## Status

Implementation complete and running. Active polish/iteration phase.

## TODO

- [ ] Update the side panel for pages to reflect page-specific options (no categories/tags)
- [ ] Media capability is completely broken — investigate and fix
- [ ] Link button in Tiptap toolbar does not work
- [ ] Post/page title and breadcrumb bars should be white in dark mode
- [ ] App title bar changes color when entering/exiting full screen

## Build & run

```bash
./build.sh        # compiles, assembles WPWriter.app, ad-hoc signs
open WPWriter.app
```

**After every code change:** quit the app, run `./build.sh`, reopen. Always.

Requirements: Swift 6.3.1 (already installed), macOS 13+.

## Key decisions

- **Stack:** Swift 6, SwiftUI (macOS 13+), WKWebView, URLSession async/await
- **Editor:** Tiptap 2.x inside WKWebView, loaded from esm.sh CDN (no npm needed)
- **API:** WordPress REST API with Application Passwords (no plugin required)
- **Storage:** SQLite.swift for local drafts/autosaves; credentials stored as JSON in `~/Library/Application Support/WPWriter/credentials.json` (chmod 600, not the system keychain — avoids password prompts)
- **URLSession:** Always use `URLSessionConfiguration.ephemeral` (default in `WordPressClient`) — prevents URLSession from touching the system keychain credential store

## Architecture

```
Sources/WPWriterKit/
  App/              AppState, AppServices, WPWriterApp
  Auth/             KeychainStore (file-based, not system keychain)
  API/              WordPressClient, Models (WPPost, WPMedia, WPTaxonomy)
  Storage/          Database, DraftStore, AutosaveStore, TaxonomyCache
  Views/
    Editor/         PostEditorView, EditorView, EditorCoordinator, DroppableWebView
    Sidebar/        SidebarView, PostListRow
    Settings/       PreferencesView, PostSettingsPanel
    Media/          MediaPickerView
  Resources/        editor.html (Tiptap)
  DesignSystem.swift
```

## Key files to know

- `Sources/WPWriterKit/Resources/editor.html` — entire Tiptap editor; JS↔Swift bridge via `window.webkit.messageHandlers.*` and `window.*` globals
- `Sources/WPWriterKit/Views/Editor/EditorCoordinator.swift` — WKWebView delegate + message handler; handles insert-image notification
- `Sources/WPWriterKit/Views/Editor/DroppableWebView.swift` — WKWebView subclass intercepting Finder image drops
- `Sources/WPWriterKit/API/WordPressClient.swift` — all REST API calls

## Known gotchas

- **Pages endpoint** omits `categories` and `tags` fields — `WPPost` uses `decodeIfPresent` with `[]` defaults; do not make those fields required again
- **`WPPost.type` field** — set to `"post"` or `"page"` by the API; used throughout `PostEditorView` and `WordPressClient` to route to the correct endpoint (`/posts/` vs `/pages/`). Do not remove this field.
- **`WPPost.dateGmt` field** — decoded from `date_gmt` JSON key (UTC). Used in `PostEditorView.loadItem()` for scheduling round-trips. `PostPayload` sends scheduled dates as `dateGmt` (JSON key `date_gmt`) — never use `date` for scheduling; WordPress interprets `date` as site-local time and ignores timezone suffix.
- **WKWebView editor loading** — `editor.html` must be loaded via `loadHTMLString(html, baseURL: URL(string: "https://app.wpwriter/"))`, NOT `loadFileURL`. The `file://` scheme gives the page a null origin; WebKit then blocks cross-origin ES module imports from esm.sh even with `Access-Control-Allow-Origin: *`. The fake HTTPS base URL gives a real origin so CDN imports succeed.
- **WKWebView CDN cache clears on every binary rebuild** — Tiptap loads 12+ modules from esm.sh; after each rebuild the cache is cold. First launch after a rebuild needs a moment to re-fetch. This is expected, not a bug.
- **Credential store** — `WordPressClient` must use ephemeral URLSession; switching to `.shared` will re-introduce keychain prompts during network calls
- **Ad-hoc signing** — `build.sh` signs with `-`; "Always Allow" on keychain prompts won't persist across rebuilds (irrelevant now that credentials use file storage, but WKWebView may still prompt once per binary for its own internal keychain use)
- **Layout uses `HStack + Divider`, not `NavigationSplitView` or `HSplitView`** — `ContentView` uses a plain `HStack(spacing: 0)` with `Divider()` between panels. `NavigationSplitView` reinstates macOS Tahoe sidebar chrome (drop shadows, raised layer). `HSplitView` renders a draggable resize cursor on panel dividers even when frames are fixed. Do NOT switch to either.
- **Sidebar post list is `ScrollView+LazyVStack`, NOT `List`** — SwiftUI's `List` on macOS uses `NSTableRowView` which paints selection blue at the AppKit layer, overriding any SwiftUI modifier. `SidebarView` uses `ScrollView { LazyVStack { ForEach { Button } } }` for full control over selection appearance. Do NOT revert to `List` with a selection binding.
- **Color tokens** — `Color.wpSidebarBg` (#F2F1EF light) and `Color.wpPanelBg` (#F4F3F1 light) are in `DesignSystem.swift` with `NSColor` dynamic providers for dark mode fallback. Use these instead of `NSColor.windowBackgroundColor` in sidebars/panels.
- **Inline taxonomy creation** — `PostSettings.newCategoryNames` / `newTagNames` hold names typed in the panel that don't exist on the server yet. On save/publish, `PostEditorView` calls `createCategory`/`createTag` for each pending name before building the payload, inserts the returned ID into `categoryIDs`/`tagIDs`, and appends the new item to `appState.categories`/`appState.tags`. Do not remove `newCategoryNames`/`newTagNames` — they are the mechanism for deferred creation.
- **`AutosaveResponse` type** — the WordPress autosave endpoint (`/posts/{id}/autosaves`, `/pages/{id}/autosaves`) returns a partial object, not a full `WPPost`. Only `link?` and `parent?` are decoded into `AutosaveResponse`. The preview URL is built as `autosave.link ?? post.link` to handle sites that omit `link` from the autosave response.
- **Trash vs. force-delete** — `WordPressClient.trashPost/trashPage` call `DELETE /posts/{id}?force=false`, which moves to WordPress Trash (recoverable). `force=true` would permanently delete. Do not change the `force` parameter unless permanent deletion is explicitly intended.
- **`performVoid` helper** — `WordPressClient` has a private `performVoid(_:)` alongside `perform<T>(_:)`. Use `performVoid` for DELETE (and any future) calls that don't need to decode a response body. Do not use `perform<T>` with a dummy decodable type just to discard the result.
- **Unicode curly quotes in Swift strings** — Swift treats `"` (U+201C) and `"` (U+201D) as string delimiters, identical to ASCII `"`. Do not use curly quotes inside string literals with interpolation — use escaped ASCII quotes `\"...\(value)...\"` instead.
- **Delete state in SidebarView** — `itemPendingDelete: PostItem?` drives the confirmation alert; `deleteError: String?` drives the error alert. Both are `@State` locals in `SidebarView`. Setting `itemPendingDelete` non-nil triggers the alert; the confirm button clears it and calls `performDelete` in a `Task`.
- **Context menu — WKWebView (`DroppableWebView`)** — WebKit's Cut/Copy/Paste items use private internal selectors, so filtering by `["cut:", "copy:", "paste:"]` removes them too. In `willOpenMenu`, replace `menu.items` entirely with fresh `NSMenuItem`s using `NSSelectorFromString("cut:")` etc. WKWebView handles these standard selectors through the responder chain with automatic enable/disable. Set `menu.delegate` to an `NSMenuDelegate` that re-filters in `menuWillOpen` to catch AutoFill/Services that macOS appends after `willOpenMenu` returns.
- **Context menu — title field (`TitleTextField`)** — `NSTextField` uses a shared field editor (`NSTextView`); overriding `menu(for:)` on the NSTextField subclass is never called during editing. Use `NSTextView` directly via `NSViewRepresentable` (`RestrictedTextView`) — `menu(for:)` on the NSTextView subclass IS called on right-click. Build a fresh menu with only Cut/Copy/Paste items and set an `NSMenuDelegate` to catch late-appended items. Do NOT try the NSTextField field editor delegate wrapping approach — it is fragile and AutoFill leaks through regardless.

## Docs

- Spec: `docs/superpowers/specs/2026-05-21-wp-mac-app-design.md`
- Plan: `docs/superpowers/plans/2026-05-21-wp-writer-implementation.md`
- Spec (delete): `docs/superpowers/specs/2026-05-22-delete-post-draft-design.md`
- Plan (delete): `docs/superpowers/plans/2026-05-22-delete-post-draft.md`
- Public docs: `docs/WPWriter.md`
