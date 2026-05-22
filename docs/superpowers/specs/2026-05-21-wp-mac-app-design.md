# WPWriter — macOS App Design Spec

**Date:** 2026-05-21  
**Status:** Approved

---

## Overview

WPWriter is a native macOS app for writing and managing content on a single self-hosted WordPress instance. It provides a local-first writing experience with a rich text editor, offline draft support, and full sync to WordPress via the REST API.

---

## Architecture

Three layers:

1. **SwiftUI layer** — all windows, navigation, panels, and toolbars. Targets macOS 13+. Built with Swift Package Manager; no Xcode required.
2. **Editor layer** — a `WKWebView` loading a locally-bundled `editor.html` containing Tiptap. Swift ↔ JS communication via `WKScriptMessageHandler` (JS → Swift) and `evaluateJavaScript` (Swift → JS). The editor outputs and accepts standard HTML.
3. **API layer** — a `WordPressClient` struct using `async/await` + `URLSession` against the WordPress REST API (v2). Authentication via WordPress Application Passwords (WP 5.6+), stored in the macOS Keychain.

Local persistence uses SQLite via `SQLite.swift`. No Core Data.

---

## UI Layout

Two-column layout:

**Column 1 — Content list (~280pt)**
- Source list at top to switch between: Posts, Pages, Local Drafts, Media
  - **Posts** — all posts on the WordPress server (any status: published, draft, scheduled)
  - **Pages** — all pages on the server
  - **Local Drafts** — posts created in the app but not yet pushed to WordPress
  - **Media** — WordPress media library browser
- Below: list of items for the selected section (title, date, status badge)
- Search field at top
- `+` button: immediately creates a new Local Draft with placeholder title "Untitled", selects it in the list, and focuses the editor — no modal

**Column 2 — Editor**
- Tiptap WYSIWYG editor fills remaining space
- Collapsible Post Settings drawer slides in from the right
- Toolbar above editor: Save Draft | Preview | Publish/Update

**Post Settings drawer contains:**
- Status (draft / scheduled / published)
- Publish date
- Categories (multi-select)
- Tags
- Featured image
- Excerpt

**Preferences window (`⌘,`):**
- Site URL, WordPress username, Application Password
- Credentials stored in macOS Keychain on save

Dark mode supported natively; Tiptap receives a matching dark theme.

---

## Editor & Data Flow

**Opening a post:** Swift fetches HTML from the REST API (or loads from local SQLite for drafts) and injects it into Tiptap via `evaluateJavaScript`.

**Autosave:** Every 30 seconds, and on window close / app quit, the editor HTML is read back via JavaScript and written to SQLite.

**Save Draft:** Writes to SQLite and PUTs to `/wp/v2/posts/{id}` with `status: draft`.

**Publish / Update:** PUTs with `status: publish` (or `status: future` if a scheduled date is set).

**Preview:** POSTs a temporary autosave to WordPress and opens the returned preview URL in the default browser.

**Media insertion:**
- Media Picker opens as a sheet
- Browse existing WordPress media library (`GET /wp/v2/media`)
- Or upload a file from disk (`POST /wp/v2/media`)
- On upload success, inserts `<img>` tag into Tiptap via JavaScript

**Post Settings:** Categories and tags fetched from API on first launch, cached locally with a timestamp. Selections are bundled into the REST payload on save.

**Conflict detection:** If the server post has been modified since the last local fetch, a banner appears before saving: "Keep local / Use server / View diff."

---

## Data Persistence

**Location:** `~/Library/Application Support/WPWriter/drafts.db`

**Schema:**
- `local_drafts` — posts not yet synced to WordPress
- `autosaves` — per-WP-post-ID autosave snapshots
- `taxonomies` — cached categories and tags with `fetched_at` timestamp
- `post_list_cache` — last-known post list per section for instant launch display

**Authentication:** Application Password entered once in Preferences, stored via `SecItemAdd` in Keychain. Never written to disk in plain text.

---

## Build System

**Stack:** Swift Package Manager. No Xcode required.

**Dependencies:**
- `SQLite.swift` — local database (fetched by SPM)
- Tiptap 2.x — loaded via `esm.sh` CDN at runtime inside WKWebView (no npm, no build step)

**Build script (`build.sh`):**
1. `swift build -c release`
2. Assembles `WPWriter.app/Contents/MacOS/` and `Contents/Resources/`
3. Copies compiled binary into `MacOS/`
4. Writes `Info.plist` (bundle ID, app name, minimum macOS version)
5. Copies `editor.html` into `Resources/`
6. Copies `AppIcon.icns` into `Resources/`

Running `./build.sh` produces `WPWriter.app` in the project root — double-click to run or drag to `/Applications`.

No code signing or notarization required for local use.

---

## Out of Scope

- Multi-site support
- Companion WordPress plugin
- Gutenberg block editor (app uses classic HTML output)
- iOS / iPadOS version
- Code signing / App Store distribution
