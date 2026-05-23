# WPWriter

A native macOS app for writing and managing WordPress content — built entirely with Swift Package Manager, no Xcode required.

WPWriter connects directly to any self-hosted WordPress site using the built-in REST API and Application Passwords. No plugins, no third-party services, no subscription.

---

## Requirements

- macOS 13 Ventura or later
- Swift 6.3 or later (included with Xcode Command Line Tools, or installed standalone)
- A self-hosted WordPress site (WordPress.com is not currently supported)
- WordPress 5.6 or later (when Application Passwords were introduced)

---

## Installation

### Build from source

```bash
git clone <repo-url>
cd wp-mac-app
./build.sh
```

This produces `WPWriter.app` in the project directory. Move it to `/Applications` if you like:

```bash
cp -r WPWriter.app /Applications/
```

The build script compiles the Swift package, assembles the app bundle, copies resources, and applies an ad-hoc code signature. No Xcode project file is needed.

---

## Setup

### 1. Generate an Application Password in WordPress

1. Log in to your WordPress admin panel
2. Go to **Users → Profile**
3. Scroll down to **Application Passwords**
4. Enter a name (e.g. "WPWriter Mac") and click **Add New Application Password**
5. Copy the generated password — you won't be able to see it again

### 2. Connect WPWriter to your site

1. Launch WPWriter
2. The preferences sheet opens automatically on first run
3. Enter:
   - **Site URL** — e.g. `https://yoursite.com`
   - **Username** — your WordPress username
   - **Application Password** — the password generated in step 1
4. Click **Save**

Your credentials are stored locally at `~/Library/Application Support/WPWriter/credentials.json` with owner-only read permissions. They are never sent anywhere except your own WordPress site.

---

## Features

### Content browsing

- **Posts** — browse all posts across all statuses (published, draft, private, scheduled, pending)
- **Pages** — browse all pages with the same status visibility
- **Local Drafts** — write offline without a connection; publish when ready
- **Media** — browse your WordPress media library

Switch between sections using the tab strip at the top of the sidebar. A loading indicator appears while content is fetching; errors surface inline with a warning banner.

Each item in the sidebar shows a small colored dot indicating its status:

| Dot | Status |
|---|---|
| Green | Published |
| Amber | Draft |
| Blue | Scheduled (future publish date) |
| Purple | Local post draft (not yet on WordPress) |
| Indigo | Local page draft (not yet on WordPress) |
| Gray | Other / unknown status |

### Rich text editor

The editor is powered by [Tiptap](https://tiptap.dev) running inside a WebView. It supports:

| Feature | Notes |
|---|---|
| Bold, italic, underline, strikethrough | Standard inline marks |
| Headings H1–H3 | Via the heading dropdown |
| Blockquote | |
| Code (inline) | |
| Code block | |
| Bullet list | |
| Ordered list | |
| Task list | Checkable items |
| Tables | Insert 3×3; add/remove rows and columns |
| Links | Insert or remove |
| Images | From media library or drag from Finder |

The editor adapts to macOS light and dark mode automatically.

### Saving and publishing

- **Save Draft (⌘S)** — saves to WordPress as a draft without publishing
- **Publish / Update (⌘⇧P)** — publishes a new post or updates an existing one
- **Autosave** — changes are autosaved locally every 30 seconds while you write
- **Conflict detection** — if the post was modified on the server since you opened it, you'll be prompted to keep your local version or pull from the server

A toast notification confirms every successful save, publish, or schedule action.

### Post settings

Click the sidebar-right icon in the editor toolbar to open the settings panel. Available fields differ by content type.

**Posts:**
- **Status** — Draft, Published, or Scheduled
- **Publish Date** — schedule a future publish with a date/time picker
- **Categories** — filter existing categories with the search box, or type a new name and press Return to create it on your site when the post is saved
- **Tags** — selected tags appear as chips at the top; search to add from existing tags, or type a new name and press Return to create it on your site when the post is saved
- **Slug** — the URL-friendly identifier for the post
- **Excerpt** — custom post excerpt
- **Discussion** — toggle whether comments are allowed on the post

**Pages:**
- **Status** — Draft, Published, or Scheduled
- **Publish Date** — schedule a future publish with a date/time picker
- **Parent Page** — nest this page under another; defaults to top-level
- **Slug** — the URL-friendly identifier for the page
- **Discussion** — toggle whether comments are allowed on the page

### Drag and drop

Drag any image file from Finder directly into the editor. WPWriter will:

1. Upload the file to your WordPress media library
2. Insert the image into the document at the current cursor position
3. Confirm with an "Image inserted" toast

Supported formats: JPEG, PNG, GIF, WebP, HEIC, TIFF.

A blue dashed overlay appears in the editor while you're dragging to confirm the drop zone is active.

### Deleting content

Right-click any item in the sidebar to reveal the delete option.

- **Posts and pages** — "Move to Trash" sends the post to the WordPress Trash (reversible from WP Admin → Trash)
- **Local drafts** — "Delete Draft" permanently removes the draft from local storage

A confirmation prompt appears before any delete action is executed. If a network error occurs while trashing a remote post, an error alert is shown and the item remains in the list.

### Local drafts

Create drafts that live only on your Mac — useful for writing in progress that you're not ready to push to WordPress yet.

- Press **⌘N** or click the pencil icon in the sidebar to create a new local draft
- Local drafts autosave to a SQLite database in `~/Library/Application Support/WPWriter/`
- When you publish a local draft, it is uploaded to WordPress and removed from local storage

---

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| **⌘S** | Save Draft |
| **⌘⇧P** | Publish / Update |
| **⌘N** | New Local Draft |
| **⌘R** | Refresh current section |
| **⌘,** | Open Preferences |
| **⌘B** | Bold |
| **⌘I** | Italic |
| **⌘U** | Underline |
| **⌘Z** | Undo |
| **⌘⇧Z** | Redo |

---

## Configuration

### Changing your site or credentials

Open **WPWriter → Settings** (⌘,) and update any field, then click Save.

### Data locations

| Data | Location |
|---|---|
| Credentials | `~/Library/Application Support/WPWriter/credentials.json` |
| Local drafts | `~/Library/Application Support/WPWriter/wpwriter.sqlite` |
| Autosaves | Same SQLite database |
| Taxonomy cache | Same SQLite database |

To fully reset WPWriter, delete the `~/Library/Application Support/WPWriter/` directory.

---

## Notes and gotchas

**WordPress.com is not supported.** The WordPress REST API used here is the self-hosted version. WordPress.com uses a different authentication model.

**Application Passwords require HTTPS.** WordPress disables Application Passwords on sites not served over HTTPS (unless you've explicitly enabled them via a filter). Make sure your site uses `https://`.

**The editor requires an internet connection on first launch.** Tiptap is loaded from [esm.sh](https://esm.sh) at startup. The first launch after installing (or after a system update clears WebKit's cache) requires an internet connection. Subsequent launches use cached resources and work offline.

**Pages have different metadata than posts.** The pages REST endpoint does not support categories, tags, or excerpts. WPWriter shows a page-specific settings panel with Parent Page, Slug, and Discussion in place of those fields.

**Private posts.** WPWriter fetches posts and pages with `context=edit`, which requires authentication. Private posts are visible to authenticated users with edit permissions.

**Conflict detection.** WPWriter tracks the `modified` timestamp from WordPress. If you open a post, someone else edits it on the server, and you then try to save, WPWriter will warn you. You can choose to overwrite the server version or discard your local changes.

---

## Building for distribution

The included `build.sh` produces an ad-hoc signed app suitable for personal use. Ad-hoc signing means the app runs on your machine without Gatekeeper issues, but cannot be distributed to others via the Mac App Store or standard drag-install without triggering "unidentified developer" warnings.

To distribute WPWriter:

1. Obtain an **Apple Developer ID** certificate (requires the Apple Developer Program, $99/year)
2. Replace `codesign --sign -` in `build.sh` with `codesign --sign "Developer ID Application: Your Name (TEAMID)"`
3. Add a notarization step via `xcrun notarytool`

---

## Contributing

WPWriter is built with:

- **Swift 6** with strict concurrency
- **SwiftUI** (macOS 13+) for all native UI
- **WKWebView** hosting a [Tiptap](https://tiptap.dev) editor loaded from [esm.sh](https://esm.sh)
- **SQLite.swift** for local storage
- **WordPress REST API** — no plugins required

The project has no external Swift dependencies beyond SQLite.swift. Everything else is system frameworks or loaded from CDN at runtime.
