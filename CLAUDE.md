# WPWriter

Native macOS app for writing and managing WordPress content. Built with Swift Package Manager (no Xcode needed).

## Status

Implementation complete and running. Active polish/iteration phase.

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

## Docs

- Spec: `docs/superpowers/specs/2026-05-21-wp-mac-app-design.md`
- Plan: `docs/superpowers/plans/2026-05-21-wp-writer-implementation.md`
- Public docs: `docs/WPWriter.md`
