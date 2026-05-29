# Quill

A native macOS app for writing and managing WordPress content — built entirely with Swift Package Manager, no Xcode required.

Quill connects directly to any self-hosted WordPress site using the built-in REST API and Application Passwords. No plugins, no third-party services, no subscription.

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
cd quill
./build.sh
```

This produces `Quill.app` in the project directory. Move it to `/Applications` if you like:

```bash
cp -r Quill.app /Applications/
```

The build script compiles the Swift package, assembles the app bundle, copies resources, and applies an ad-hoc code signature. No Xcode project file is needed.

---

## Setup

### 1. Generate an Application Password in WordPress

1. Log in to your WordPress admin panel
2. Go to **Users → Profile**
3. Scroll down to **Application Passwords**
4. Enter a name (e.g. "Quill Mac") and click **Add New Application Password**
5. Copy the generated password — you won't be able to see it again

### 2. Connect Quill to your site

1. Launch Quill
2. The preferences sheet opens automatically on first run
3. Enter:
   - **Site URL** — e.g. `https://yoursite.com`
   - **Username** — your WordPress username
   - **Application Password** — the password generated in step 1
4. Click **Save**

Your credentials are stored locally at `~/Library/Application Support/Quill/credentials.json` with owner-only read permissions. They are never sent anywhere except your own WordPress site.

---

## Features

### Content browsing

- **Posts** — browse all posts across all statuses (published, draft, private, scheduled, pending)
- **Pages** — browse all pages with the same status visibility
- **Local Drafts** — write offline without a connection; publish when ready
- **Media** — browse your WordPress media library as a thumbnail grid

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
| Headings H1–H6 | Via the heading dropdown |
| Blockquote | |
| Code (inline) | |
| Code block | |
| Bullet list | |
| Ordered list | |
| Tables | Insert 3×3; add/remove rows and columns |
| Links | Insert or remove |
| Images | From media library or drag from Finder; inline resize via drag handles |

The editor adapts to macOS light and dark mode automatically.

### Image resizing

Click any image in the editor to select it. A blue outline and eight resize handles appear at the corners and edges.

- **Drag a corner handle** to resize proportionally (aspect ratio is maintained by default). Hold **Shift** while dragging to resize width and height independently.
- **Drag an edge handle** (top, bottom, left, right) to resize only that axis.
- A small toolbar appears just below the selected image with **W** and **H** number fields. Type a new value and press Return — the other dimension adjusts automatically to preserve the ratio.
- Click **Reset** to clear any explicit dimensions and return the image to its natural CSS size.
- If the image was inserted from the WordPress media library, **Thumb**, **Medium**, **Large**, and **Full** buttons appear in the toolbar. Clicking one swaps the image source and dimensions to that WordPress-generated size.

When a post is loaded from WordPress, any `<img width="..." height="...">` attributes are respected and the image renders at those exact dimensions. On save, dimensions are written back as standard `width`/`height` attributes for a clean round-trip with WordPress.

### Saving and publishing

- **Save Draft (⌘S)** — saves to WordPress as a draft without publishing
- **Publish / Update (⌘⇧P)** — publishes a new post or updates an existing one
- **Autosave** — changes are autosaved locally every 30 seconds while you write
- **Conflict detection** — if the post was modified on the server since you opened it, you'll be prompted to keep your local version or pull from the server

A toast notification confirms every successful save, publish, or schedule action.

### Unsaved changes

An amber dot appears in the editor toolbar whenever the current post or page has changes that haven't been saved to WordPress yet. If you navigate to a different item before saving, Quill silently preserves your unsaved work to local storage. When you return, your changes are restored automatically and a brief "Unsaved changes restored" toast confirms the restore. Changes persist across app restarts.

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

### AI writing assistant

Quill includes an optional AI writing assistant powered by the Claude API. It works directly on selected text in the editor.

#### Setup

1. Open **Quill → Settings** (⌘,) and go to the **AI** tab
2. Paste your [Anthropic API key](https://console.anthropic.com/)
3. Click **Save**

The AI features activate immediately — no restart required. If no API key is saved, the AI controls stay hidden.

Optionally, select one or more of your existing posts as **style samples**. When you save with samples selected, Quill sends them to Claude once to generate a compact writing style guide, then stores it locally. Claude uses that guide on every subsequent request to match your tone, rhythm, and vocabulary — no extra cost per call. If you change your sample selection and save again, the guide is regenerated automatically.

#### Using the writing assistant

Select at least 10 characters of text in the editor. A small pill button (✦) appears near the selection. Click it to choose an operation:

| Operation | What it does |
|---|---|
| **Make longer** | Expands the selected content to roughly 2–3× its current length, adding detail and examples |
| **Make shorter** | Condenses to the essential points while preserving meaning |
| **Convert to table** | Restructures the content as an HTML table |
| **Convert to list** | Restructures the content as a bullet list |

While Claude processes the request, the selected text is replaced with a brief loading indicator. When the result arrives, it is inserted in place of your selection and highlighted.

An **Accept / Discard** bar appears below the result:

- Click **Accept** (or press **Return**) to keep the change
- Click **Discard** (or press **Escape**) to restore your original text
- Click anywhere outside the bar to discard

If you navigate away or close the editor before accepting, the original text is restored automatically.

### Drag and drop

Drag any image file from Finder directly into the editor. Quill will:

1. Upload the file to your WordPress media library
2. Insert the image into the document at the current cursor position
3. Confirm with an "Image inserted" toast

Supported formats: JPEG, PNG, GIF, WebP, HEIC, TIFF.

A blue dashed overlay appears in the editor while you're dragging to confirm the drop zone is active.

### Media library

The Media tab shows a two-column thumbnail grid of your WordPress media library. Click any thumbnail to see a large preview in the main panel alongside metadata: filename, MIME type, dimensions, upload date, and source URL (with a one-click copy button).

Right-click any thumbnail for quick actions:

| Action | Result |
|---|---|
| Copy URL | Copies the direct file URL to the clipboard |
| Copy as Markdown | Copies `![title](url)` ready to paste into a post |
| Open in Browser | Opens the WordPress attachment page in your default browser |
| Delete… | Permanently deletes the file from WordPress (with confirmation) |

Use **⌘N** to upload a new file from disk, or **⌘R** to refresh the grid. If your library has more than 30 items, a "Load more…" button appears at the bottom of the grid.

**Note:** Media deletion is permanent — WordPress media items have no Trash state.

### Deleting content

Right-click any item in the sidebar to reveal the delete option.

- **Posts and pages** — "Move to Trash" sends the post to the WordPress Trash (reversible from WP Admin → Trash)
- **Local drafts** — "Delete Draft" permanently removes the draft from local storage
- **Media** — "Delete…" permanently removes the file from WordPress (no Trash; cannot be undone)

A confirmation prompt appears before any delete action is executed. If a network error occurs while trashing a remote post, an error alert is shown and the item remains in the list.

### Local drafts

Create drafts that live only on your Mac — useful for writing in progress that you're not ready to push to WordPress yet.

- Press **⌘N** in the sidebar, or use **File → New Post** / **File → New Page** to create a new local draft
- **File → New Media…** switches to the Media tab and opens the upload panel immediately
- Local drafts autosave to a SQLite database in `~/Library/Application Support/Quill/`
- When you publish a local draft, it is uploaded to WordPress and removed from local storage

---

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| **⌘S** | Save Draft |
| **⌘⇧P** | Publish / Update |
| **⌘N** | New Local Draft (Posts/Pages/Drafts tabs) or Upload Media (Media tab) |
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

Open **Quill → Settings** (⌘,) and update any field, then click Save. If you change the site URL, your writing style sample selections are cleared automatically — sample posts from one site have no meaning on another, and a fresh style guide will be generated the next time you choose samples on the new site.

### Data locations

| Data | Location |
|---|---|
| Credentials | `~/Library/Application Support/Quill/credentials.json` |
| AI settings | `~/Library/Application Support/Quill/ai_settings.json` |
| Local drafts | `~/Library/Application Support/Quill/drafts.db` |
| Autosaves | Same SQLite database |
| Taxonomy cache | Same SQLite database |

To fully reset Quill, delete the `~/Library/Application Support/Quill/` directory.

---

## Notes and gotchas

**WordPress.com is not supported.** The WordPress REST API used here is the self-hosted version. WordPress.com uses a different authentication model.

**Application Passwords require HTTPS.** WordPress disables Application Passwords on sites not served over HTTPS (unless you've explicitly enabled them via a filter). Make sure your site uses `https://`.

**Pages have different metadata than posts.** The pages REST endpoint does not support categories, tags, or excerpts. Quill shows a page-specific settings panel with Parent Page, Slug, and Discussion in place of those fields.

**Private posts.** Quill fetches posts and pages with `context=edit`, which requires authentication. Private posts are visible to authenticated users with edit permissions.

**Conflict detection.** Quill tracks the `modified` timestamp from WordPress. If you open a post, someone else edits it on the server, and you then try to save, Quill will warn you. You can choose to overwrite the server version or discard your local changes.

---

## Building for distribution

The included `build.sh` produces an ad-hoc signed app suitable for personal use. Ad-hoc signing means the app runs on your machine without Gatekeeper issues, but cannot be distributed to others via the Mac App Store or standard drag-install without triggering "unidentified developer" warnings.

To distribute Quill:

1. Obtain an **Apple Developer ID** certificate (requires the Apple Developer Program, $99/year)
2. Replace `codesign --sign -` in `build.sh` with `codesign --sign "Developer ID Application: Your Name (TEAMID)"`
3. Add a notarization step via `xcrun notarytool`

---

## Contributing

Quill is built with:

- **Swift 6** with strict concurrency
- **SwiftUI** (macOS 13+) for all native UI
- **WKWebView** hosting a [Tiptap](https://tiptap.dev) editor loaded from a local bundle (no CDN dependency)
- **SQLite.swift** for local storage
- **WordPress REST API** — no plugins required

The project has no external Swift dependencies beyond SQLite.swift. Everything else is system frameworks or loaded from CDN at runtime.
