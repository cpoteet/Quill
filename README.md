# Quill

A native macOS app for writing and managing WordPress content — built with Swift Package Manager, no Xcode required.

Quill connects to any self-hosted WordPress site using the built-in REST API and Application Passwords. No plugins, no third-party services, no subscription.

---

## Overview

Quill is a lightweight desktop writing environment for WordPress. It gives you a fast, distraction-free editor, full access to your posts and pages, a built-in media library browser, and an optional AI writing assistant — all without touching the WordPress admin UI.

It is built entirely with native macOS technologies: Swift 6, SwiftUI, and WKWebView. The editor inside the webview is [Tiptap 2.x](https://tiptap.dev), bundled locally so the app loads instantly from disk with no CDN dependency.

---

## Features

### Content management
- Browse and edit **posts** and **pages** across all statuses (published, draft, scheduled, private, pending)
- **Local drafts** — write offline in SQLite-backed local storage; publish to WordPress when ready
- **Media library** — two-column thumbnail grid with metadata panel, upload, and delete

### Rich text editor
- Full formatting toolbar: headings H1–H6, bold, italic, underline, strikethrough, blockquote, code, code block, bullet list, ordered list, links, tables
- **Image resizing** — click to select, drag handles to resize; W/H fields for exact dimensions; named-size buttons (Thumb / Medium / Large / Full) for images from the media library
- **Image alignment** — left, center, right with text wrap
- Drag images from Finder directly into the editor (auto-uploads to WordPress)
- Gutenberg HTML compatibility — round-trips cleanly with WordPress block editor

### Post settings panel
- Status, publish date/time, slug, excerpt, discussion
- Categories and tags with inline creation (type a new name, created on save)
- Parent page picker for pages

### AI writing assistant (optional)
- Powered by the Claude API (Anthropic API key required)
- Select text → pill button → Make Longer / Make Shorter / Convert to Table / Convert to List
- Generates a writing style guide from sample posts; embeds it in every request via system prompt caching
- Accept / Discard bar after each result; original text is always restorable

### Native fit
- Supports macOS light and dark mode
- Standard keyboard shortcuts (⌘S save, ⌘⇧P publish, ⌘N new, ⌘R refresh)
- File menu: New Post, New Page, New Media
- Context menus, confirmation alerts, toast notifications

---

## Requirements

- macOS 13 Ventura or later
- Swift 6.3 or later
- A self-hosted WordPress site running WordPress 5.6+ (Application Passwords)
- WordPress.com is not currently supported

---

## Build & Run

```bash
git clone <repo-url>
cd quill
./build.sh        # compiles, assembles Quill.app, ad-hoc signs
open Quill.app
```

The build script compiles the Swift package, assembles the app bundle, copies resources, and applies an ad-hoc code signature. It takes about 6 seconds on a clean build.

After every code change: quit the app, run `./build.sh`, reopen.

To install permanently:
```bash
cp -r Quill.app /Applications/
```

### First-run setup

1. In WordPress admin, go to **Users → Profile → Application Passwords**, generate a password for Quill
2. Launch Quill — the settings sheet opens automatically
3. Enter your site URL, WordPress username, and the Application Password
4. Click Save

Credentials are stored at `~/Library/Application Support/Quill/credentials.json` (chmod 600). They are never sent anywhere except your own WordPress site.

---

## Architecture

```
Sources/
  Quill/              Entry point (SwiftUI @main)
  QuillKit/
    App/              AppState (ObservableObject), AppServices, QuillApp (scene)
    Auth/             KeychainStore — file-based credential storage (not system keychain)
    API/              WordPressClient, models (WPPost, WPMedia, WPTaxonomy, WPCategory, WPTag)
    AI/               AnthropicClient, AISettings, AISettingsStore, AIPromptBuilder
    Storage/          Database (SQLite), DraftStore, AutosaveStore, TaxonomyCache
    Views/
      Editor/         PostEditorView, EditorView, EditorCoordinator, DroppableWebView
      Sidebar/        SidebarView, PostListRow, MediaSidebarSection
      Settings/       PreferencesView, PostSettingsPanel
      Media/          MediaPickerView
      AI/             GeneratePostSheet, SelectionPillPanel, AIResultPanel, SamplePostPickerSheet
    Resources/        editor.html (Tiptap editor + JS bridge)
    DesignSystem.swift
```

### Key design decisions

**No NavigationSplitView or HSplitView.** The three-column layout uses a plain `HStack(spacing: 0)` with `Divider()`. `NavigationSplitView` adds macOS Tahoe sidebar chrome; `HSplitView` renders a drag cursor on dividers.

**Sidebar list is ScrollView + LazyVStack, not List.** SwiftUI's `List` on macOS uses `NSTableRowView` which paints selection blue at the AppKit layer, bypassing SwiftUI modifiers. The scroll-based approach gives full control over selection appearance.

**Tiptap is bundled as an IIFE, not loaded from CDN.** `tiptap-bundle.js` is a local minified bundle (`window.TiptapBundle`) generated by `Scripts/bundle-tiptap.sh`. ES modules with `type="module"` silently fail under `file://` URLs in WKWebView. The bundle loads instantly from disk.

**Editor uses a WKWebView message handler bridge.** Swift ↔ JS communication goes through `window.webkit.messageHandlers.*` (JS→Swift) and `webView.evaluateJavaScript` (Swift→JS). The coordinator (`EditorCoordinator.swift`) handles all incoming messages.

**Ephemeral URLSession throughout.** `WordPressClient` always uses `URLSessionConfiguration.ephemeral` to prevent URLSession from touching the system keychain credential store and triggering password prompts.

**File-based credential storage.** Credentials are stored as JSON at `~/Library/Application Support/Quill/credentials.json` (chmod 600), not in the system keychain. This avoids keychain permission prompts on each rebuild (ad-hoc signed binaries get a new identity per build).

**Gutenberg HTML compatibility via post-processing.** `toWordPressHTML()` in `editor.html` transforms Tiptap's internal HTML into Gutenberg block format on every save. A complementary `parseHTML()` rule on the `ResizableImage` extension handles the reverse on load.

**AI style guide is pre-computed.** `AISettings.styleGuide` holds a ≤150-word style description generated once from sample posts. It is embedded in the system prompt with `cache_control: ephemeral` for prompt caching — no per-call token cost for style context.

**Floating panels use child window relationship, not `.floating` level.** `NSWindow.Level.floating` floats above all apps system-wide. `AIResultPanel` and `SelectionPillPanel` use `addChildWindow(_:ordered:)` to stay above Quill's window only.

### Data flow

```
AppState (ObservableObject)
  ├── selectedSection / selectedItem — drives sidebar selection
  ├── posts / pages / localDrafts / mediaItems — fetched lists
  ├── credentials — loaded from disk at startup
  └── aiSettings — loaded from disk at startup

AppServices (ObservableObject)
  ├── draftStore (DraftStore / SQLite)
  ├── autosaveStore (AutosaveStore / SQLite)
  └── taxonomyCache (TaxonomyCache / SQLite)

WordPressClient — stateless, created per-request from credentials
AnthropicClient — stateless, created per-request from API key
```

### External dependencies

| Package | Purpose |
|---|---|
| [SQLite.swift](https://github.com/stephencelis/SQLite.swift) | Type-safe SQLite wrapper for local drafts, autosaves, taxonomy cache |
| [swift-testing](https://github.com/apple/swift-testing) | Unit test framework |
| [Tiptap 2.x](https://tiptap.dev) | Rich text editor (bundled locally via Node build script) |

All networking uses URLSession. All UI uses SwiftUI (macOS 13+) with targeted AppKit interop where SwiftUI falls short.

---

## Local data

| Data | Location |
|---|---|
| Credentials | `~/Library/Application Support/Quill/credentials.json` |
| AI settings | `~/Library/Application Support/Quill/ai_settings.json` |
| Local drafts + autosaves + taxonomy cache | `~/Library/Application Support/Quill/drafts.db` |

To fully reset: `rm -rf ~/Library/Application\ Support/Quill/`

---

## Notes

- **Application Passwords require HTTPS.** WordPress disables them on non-HTTPS sites by default.
- **WordPress.com is not supported.** It uses a different authentication model.
- **Media deletion is permanent.** WordPress media items have no Trash state.
- **Distribution.** The build script produces an ad-hoc signed app for personal use. For distribution, replace `codesign --sign -` with a Developer ID certificate and add a notarization step via `xcrun notarytool`.
