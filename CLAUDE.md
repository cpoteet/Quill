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
- **Credential store** — `WordPressClient` must use ephemeral URLSession; switching to `.shared` will re-introduce keychain prompts during network calls
- **Ad-hoc signing** — `build.sh` signs with `-`; "Always Allow" on keychain prompts won't persist across rebuilds (irrelevant now that credentials use file storage, but WKWebView may still prompt once per binary for its own internal keychain use)

## Docs

- Spec: `docs/superpowers/specs/2026-05-21-wp-mac-app-design.md`
- Plan: `docs/superpowers/plans/2026-05-21-wp-writer-implementation.md`
- Public docs: `docs/WPWriter.md`
