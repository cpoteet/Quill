# Quill User Guide

A reference manual for Quill, the native macOS WordPress editor.

---

## Table of Contents

1. [Introduction](#introduction)
2. [Requirements & Installation](#requirements--installation)
3. [Connecting to WordPress](#connecting-to-wordpress)
4. [The Interface](#the-interface)
5. [Writing & Editing](#writing--editing)
6. [Content Elements](#content-elements)
7. [Post & Page Settings](#post--page-settings)
8. [Media Library](#media-library)
9. [AI Writing Features](#ai-writing-features)
10. [Keyboard Reference](#keyboard-reference)
11. [Limitations & Compatibility](#limitations--compatibility)

---

## Introduction

Quill is a native macOS application for writing and publishing content on self-hosted WordPress sites. It replaces the browser-based Gutenberg editor with a focused, distraction-free writing environment built for the Mac, with full support for posts, pages, media, taxonomies, scheduling, and AI-assisted writing.

Quill is built around a simple premise: the act of writing deserves a dedicated tool. Rather than competing with WordPress's block editor for layout and site-building tasks, Quill concentrates on what most WordPress authors actually spend their time doing: drafting, editing, and publishing content. The result is an interface that stays out of your way and lets you focus on the work.

**What Quill does:**
- Create, edit, publish, and schedule posts and pages
- Manage media uploads and insert images into content
- Organize content with categories, tags, slugs, and excerpts
- Write with a rich text editor that produces clean Gutenberg-compatible HTML
- Optionally generate and refine content using the Anthropic Claude API

**What Quill is not:**
- A WordPress.com client — Quill requires a self-hosted WordPress installation
- A full site builder or theme editor
- A replacement for the WordPress admin dashboard

Quill is free.

---

## Requirements & Installation

### Requirements

- **macOS:** macOS 26 (Tahoe) or later. Earlier versions of macOS may work but are not officially supported.
- **WordPress:** A self-hosted WordPress site running WordPress 7.0 or later. Earlier versions may work but are not officially supported. Your site must be accessible over HTTPS.
- **WordPress.com:** Not supported. Quill connects only to self-hosted WordPress installations.

### Downloading Quill

Quill is available for free at [cpoteet.github.io/Quill-Releases](https://cpoteet.github.io/Quill-Releases/). Download the latest release, unzip the file, and drag **Quill.app** into your `/Applications` folder.

### First Launch: macOS Security

Quill is not notarized by Apple, so macOS will block it from opening the first time. This is expected. To allow it:

1. Attempt to open Quill. macOS will display a message saying the app cannot be opened.
2. Open **System Settings** and navigate to **Privacy & Security**.
3. Scroll down to the Security section. You will see a message that Quill was blocked.
4. Click **Open Anyway**.
5. A confirmation dialog will appear. Click **Open**.

Quill will open normally from this point forward. This prompt only appears once per installation.

---

## Connecting to WordPress

Quill connects to your WordPress site using an **Application Password**, a credential type built into WordPress that grants API access without exposing your main account password. You will need three pieces of information: your site URL, your WordPress username, and an Application Password you generate in the WordPress admin.

### Step 1: Generate an Application Password in WordPress

1. Log into your WordPress admin dashboard.
2. In the left sidebar, navigate to **Users → Profile**.
3. Scroll down to the **Application Passwords** section.
4. In the **New Application Password Name** field, enter a name to identify this connection, such as "Quill".
5. Click **Add New Application Password**.
6. WordPress will display the generated password. **Copy it now.** It will not be shown again.

> Application Passwords require WordPress 7.0 or later (officially), and your site must use HTTPS.

### Step 2: Enter Your Credentials in Quill

1. Open Quill's settings via the **Quill** menu → **Settings**, or press **⌘,**.
2. In the **WordPress Credentials** section, fill in the following fields:
   - **Site URL:** Your site's full URL, including `https://` (for example, `https://yoursite.com`). Trailing slashes are handled automatically.
   - **Username:** Your WordPress username.
   - **Application Password:** The password you copied from step 1.
3. Click **Save**.

Quill will store your credentials locally and connect to your site. Once saved, your posts and pages will begin loading in the sidebar.

---

## The Interface

Quill's window is divided into three panels: the **Sidebar** on the left, the **Editor** in the center, and the **Settings Panel** on the right. The sidebar and settings panel can each be shown or hidden independently, giving you full control over how much screen space is dedicated to writing.

### The Sidebar

The sidebar organizes your content into four sections, selectable via tabs at the top:

- **Posts** — Lists all posts on your site, most recently published first. A search field lets you filter by title.
- **Pages** — Lists all pages on your site, most recently published first, with the same search capability.
- **Drafts** — Lists local drafts saved only on your Mac, not yet published or synced to WordPress.
- **Media** — Displays your site's media library as a thumbnail grid for browsing and uploading files.

Click any post, page, draft, or media item to open it in the editor or detail view. Right-click a post or page for the option to move it to trash.

To hide the sidebar and maximize writing space, click the **sidebar icon** at the left of the editor toolbar. Click it again to bring the sidebar back.

### The Editor

The editor area has two parts:

- **Title field** — A large text field at the top for the post or page title.
- **Editor canvas** — The main writing area below, powered by a rich text editor that produces clean WordPress-compatible HTML.

Above the title field is the **toolbar**, which contains:

| Control | Description |
|---|---|
| Sidebar toggle | Shows or hides the left sidebar |
| Status badge | Displays the current post status (Draft, Published, Scheduled, etc.) |
| Save Draft / ⌘S | Saves the current post as a local draft or syncs changes to WordPress |
| Revert | Discards unsaved changes and restores the last saved version |
| Preview | Opens the current post's preview URL in your browser |
| Publish / ⌘⇧P | Publishes or updates the post on your WordPress site |
| Settings toggle | Shows or hides the right-side settings panel |
| ✦ | Opens the AI writing assistant (visible only when an Anthropic API key is configured) |
| Image | Opens the media library to insert an image at the cursor position |

A small amber dot appears next to Save Draft when you have unsaved local changes.

### The Settings Panel

The settings panel slides in from the right when you click the settings toggle in the toolbar. It contains publishing options for the current post or page, including status, scheduling, categories, tags, slug, excerpt, discussion settings, and a word count summary. Page-specific options include parent page selection. See [Post & Page Settings](#post--page-settings) for full details.

### Empty State

If no post or page is selected, the editor area displays a placeholder prompting you to select an item from the sidebar. Use the **File** menu or keyboard shortcuts to create new content.

---

## Writing & Editing

### Creating Posts and Pages

Use the **File** menu to create new content:

| Action | Shortcut |
|---|---|
| New Post | ⌘N |
| New Page | ⌘⇧N |
| New Media upload | ⌘⌥N |

New posts and pages are created as **local drafts** and appear in the Drafts section of the sidebar immediately. They are saved only on your Mac until you publish them to WordPress.

### The Editor

The editor is a rich text environment that produces clean, Gutenberg-compatible HTML. What you see is what gets published: headings, lists, blockquotes, and all formatting render as they will appear on your site.

The **title field** sits above the editor canvas. Click it to type or edit the post or page title.

### Formatting Toolbar

The formatting toolbar runs across the top of the editor and provides access to all block and inline formatting tools.

**Block formatting:**

| Button | Function |
|---|---|
| Paragraph / Heading | Dropdown menu to set the current block as Paragraph or Heading 1 through 6 |
| Bullet list | Converts the current block to an unordered list |
| Number list | Converts the current block to an ordered list |
| Blockquote | Wraps the current block in a blockquote |
| Code block | Converts the current block to a preformatted code block |

**Inline formatting:**

| Button | Shortcut | Function |
|---|---|---|
| B | ⌘B | Bold |
| I | ⌘I | Italic |
| U | ⌘U | Underline |
| S | | Strikethrough |
| `A` | | Inline code |

**Insert and utilities:**

| Button | Function |
|---|---|
| Table | Inserts a table. When the cursor is inside a table, additional buttons appear to add/remove rows and columns or delete the table. See [Tables](#tables) in Content Elements. |
| Link | Inserts or removes a hyperlink on the selected text. Opens the link picker, where you can type to search your WordPress posts, pages, and media by title, or paste any URL directly. Selecting a search result or pressing Enter applies the link. When editing an existing link, a Remove option is also available. |
| * (Footnote) | Inserts a footnote marker at the cursor position. See [Footnotes](#footnotes) in Content Elements. |
| Embed | Inserts an embed (video, social post, etc.) by URL. See [Embeds](#embeds) in Content Elements. |
| ABC (Spell check) | Runs a spell check on the document |
| </> (Code view) | Toggles between the rich text editor and a raw HTML view |
| Image | Opens the media library picker to insert an image. See [Images](#images) in Content Elements. |

The image alignment buttons (left, center, right) appear in the toolbar only when an image is selected. See [Images](#images) in Content Elements for full detail on resizing, captions, and alt text.

### Saving and Publishing

**For local drafts:**
- Click **Save Draft** or press **⌘S** to save your work locally. The draft remains on your Mac and does not touch WordPress.
- Click **Publish** or press **⌘⇧P** to push the post to WordPress. After publishing, the post moves from Drafts to Posts or Pages in the sidebar.

**For posts and pages already on WordPress:**
- Press **⌘S** or click **Publish** to sync your changes to WordPress immediately.
- An amber dot in the toolbar indicates you have unsaved changes.
- Click **Revert** to discard unsaved changes and restore the last saved version.

**Autosave:** Quill automatically saves your work every 30 seconds after a change, so you don't lose progress if you close the app unexpectedly. For remote posts, autosaves are stored locally and applied if you reopen a post before manually saving.

### Find and Replace

Press **⌘F** to open the find and replace bar. Type in the **Find** field to highlight matches in the document. Use the arrow buttons or press **↩** (next) and **⇧↩** (previous) to navigate between matches. Toggle **Aa** to enable case-sensitive search.

To replace matches, type in the **Replace** field and click **Replace** to replace the current match or **All** to replace every match in the document. Press **Esc** to close the find bar.

### Spell Check

Click the **ABC** button in the toolbar to check spelling. Right-clicking on any word in the editor while editing shows a context menu with spelling suggestions when a spelling error is detected under the cursor.

---

## Content Elements

### Images

Click the **Image** button in the toolbar to open the media library picker and insert an image at the cursor position. See [Media Library](#media-library) for details on uploading and browsing media. You can also drag an image file directly from Finder onto the editor canvas; Quill will upload it to your WordPress media library and insert it in one step.

Once an image is inserted, click it to select it. A floating image toolbar appears above the image, and alignment controls become available in the main toolbar.

**Resizing:**

Images can be resized in two ways:

- **Drag handles** — Eight handles appear around the selected image (corners and edges). Drag any handle to resize freely.
- **W and H fields** — Enter exact pixel dimensions in the width and height fields in the image toolbar.
- **Reset** — Click Reset to restore the image to its original full-resolution dimensions.

**Preset sizes:**

If the image was inserted from your WordPress media library, the image toolbar shows preset size buttons (**Thumb**, **Medium**, **Large**, and **Full**) corresponding to the sizes WordPress has generated for that image. Click a size to jump directly to those dimensions. These buttons only appear for images with a known media ID; externally linked images show only the manual W/H fields.

**Alt text:**

Enter a description in the **Alt** field in the image toolbar. This text is saved with the image and used for accessibility and SEO. Alt text set in the media library is pre-populated automatically when you insert an image.

**Alignment:**

Use the alignment buttons in the main toolbar (left, center, right) to float or center the image. These buttons are only visible when an image is selected.

**Captions:**

Click below an image to place the cursor in the caption field and type a caption. Captions are saved as part of the Gutenberg image block.

### Footnotes

Quill has full support for WordPress-style footnotes. To insert a footnote, place the cursor where you want the marker to appear and click the **\*** button in the toolbar, or right-click and choose **Insert Footnote** from the context menu.

When you insert a footnote, two things happen automatically:

1. A numbered superscript marker appears inline at the cursor position.
2. A footnote entry is added to a numbered list at the bottom of the document, where you can type the footnote text.

**Automatic numbering:** Footnote markers are always numbered sequentially from 1 based on their position in the document. If you insert a footnote between two existing ones, or delete one, all numbers update automatically; you never need to renumber manually.

**Navigating between markers and entries:** Each footnote entry at the bottom of the document has a **↩** button. Clicking it jumps your cursor back to the corresponding marker in the body text.

**Deleting footnotes:** Delete the inline marker in the body text and the corresponding footnote entry at the bottom of the document is removed automatically. You cannot delete entries from the list directly; they are always kept in sync with the markers.

**On publish:** Quill saves footnotes as standard WordPress block footnotes (`wp-block-footnotes`), fully compatible with the Gutenberg editor.

### Tables

Click the **Table** button in the toolbar to insert a table at the cursor position. A new table is created with a default set of rows and columns.

When the cursor is inside a table, four additional buttons appear in the toolbar:

| Button | Function |
|---|---|
| +Row | Inserts a row below the current row |
| +Col | Inserts a column to the right of the current column |
| −Row | Deletes the current row |
| −Col | Deletes the current column |
| ✕ | Deletes the entire table |

Press **Tab** to move forward through cells, or **⇧Tab** to move backward. Pressing Tab from the last cell in a row moves to the first cell of the next row.

**Headers:** The first row of the table is treated as a header row. Quill saves it as a proper `<thead>` element in the published HTML, consistent with how WordPress formats table blocks.

### Embeds

Quill supports embedding content from external platforms (videos, social posts, audio, and more) directly in your posts and pages.

To insert an embed:

1. Click the **Embed** button in the toolbar.
2. A small input menu appears. Paste the URL of the content you want to embed.
3. Press **Enter** or click **Insert**.

The embed appears in the editor as a card showing the URL. It will render as a live embed on your published site; Quill does not preview the embedded content.

**Supported providers:**

| Provider | Content type |
|---|---|
| YouTube | Video |
| Vimeo | Video |
| Twitter / X | Posts |
| Instagram | Posts |
| TikTok | Video |
| Spotify | Music / podcasts |
| SoundCloud | Audio |

URLs from providers not listed above are saved as generic embeds. WordPress will attempt to render them using its own oEmbed support.

> Not all embeds may work as expected on your published site. Provider support depends on the platform's oEmbed implementation and can change without notice. X (formerly Twitter) is a known example where embed rendering is inconsistent.

---

## Post & Page Settings

The settings panel is accessed by clicking the settings toggle button at the right end of the editor toolbar. It slides in from the right and contains all publishing options for the current post or page.

Changes made in the settings panel take effect when you next save or publish the post. They are not sent to WordPress automatically as you adjust them.

> Settings are not saved for local drafts. The panel is visible but values will not be applied until you publish the post or page to WordPress.

### Status

The Status picker controls the publish state of the post or page:

| Status | Color | Description |
|---|---|---|
| Draft | Amber | Saved to WordPress but not publicly visible |
| Pending Review | Orange | Flagged for editorial review before publishing |
| Published | Green | Live and publicly visible |
| Scheduled | Blue | Will publish automatically at the specified date and time |
| Private | Teal | Visible only to logged-in WordPress administrators and editors |

Local drafts (posts and pages not yet synced to WordPress) show a **Purple** badge (posts) or **Indigo** badge (pages) in the toolbar and sidebar.

### Publish Date

The Publish Date section appears for all statuses except Private. It contains a **Schedule** toggle. When turned on, the status is set to Scheduled and a date and time picker appears. When turned off, the status reverts to Draft if it was previously set to Scheduled.

You can also set scheduling by selecting **Scheduled** directly in the Status picker; the date picker will appear automatically with a default time one hour from now.

Once you have set the date and time, press **⌘⇧P** or click **Publish** to commit the scheduled post to WordPress. The post will publish automatically at the chosen time.

### Categories (Posts only)

The categories section lists all categories on your site. Check a category to assign it to the post. Use the search field to filter categories by name.

To create a new category, type its name in the search field and press Enter. New categories are created on your WordPress site when the post is saved or published.

### Tags (Posts only)

Tags work the same way as categories. Type in the search field to find existing tags or press Enter to create a new one. New tags are created on your WordPress site when the post is saved or published.

### Slug

The slug is the URL-friendly identifier for the post or page, used in the permalink. Edit this field to customize the URL. Leave it blank to let WordPress generate one automatically from the title.

### Excerpt (Posts only)

The excerpt is a short summary of the post, used by themes in archive and search result views. Type directly in the excerpt field. If left blank, WordPress will generate an automatic excerpt from the post body.

### Parent Page (Pages only)

The Parent Page picker sets the hierarchy of the page. Select a parent page to nest this page beneath it in the URL structure, or leave it set to **None (top-level)** for a root-level page.

### Discussion

The Discussion section contains a single **Allow comments** toggle. Turn it off to disable comments on the post or page.

### Stats

The Stats section displays a live word count and character count for the current post, updated as you type. An estimated reading time is shown once the post has enough content, calculated at 238 words per minute and rounded up to the nearest minute.

---

## Media Library

The Media Library gives you access to all files uploaded to your WordPress site. Switch to the **Media** tab in the sidebar to browse your library as a thumbnail grid.

### Browsing

Media items are displayed as thumbnails for images. Non-image files (PDFs, documents, etc.) show a generic file icon. Click any item to open its detail view in the main panel.

If your library has more items than the current view, a **Load More** button appears at the bottom of the grid. Click it to fetch the next page of results.

### Detail View

Clicking a media item opens a two-panel detail view: a large preview on the left and a metadata panel on the right.

The metadata panel shows:

| Field | Description |
|---|---|
| Filename | The media item's title, or its filename if no title is set |
| Type | The file extension |
| Dimensions | Pixel dimensions (images only) |
| Alt Text | Editable alt text description (images only) |
| Uploaded | The date the file was uploaded |
| URL | The full URL of the file, with a copy button |

**Alt text** can be edited directly in the detail panel. Press **Return** or click away from the field to save the change to WordPress.

### Uploading

To upload new media:

- Click the **upload button** at the top of the Media sidebar, or
- Use **File → New Media** (⌘⌥N) from anywhere in the app.

Both open a standard macOS file picker. Any file type supported by your WordPress installation can be uploaded. The new item appears at the top of the grid and its detail view opens automatically.

### Inserting Images into Posts

To insert an image from your media library into a post or page, click the **Image** button in the editor toolbar while editing. This opens a picker sheet showing your media library. Click an image to insert it at the cursor position.

You can also drag an image file directly from Finder onto the editor canvas to upload and insert it in one step.

### Deleting Media

Right-click any item in the media grid and select **Delete** to remove it. A confirmation prompt will appear before the deletion proceeds.

> Deleting media is permanent. WordPress does not have a trash for media items; deletion cannot be undone.

---

## AI Writing Features

Quill includes an optional AI writing assistant powered by the Anthropic Claude API, using the Claude Haiku model. AI features are disabled by default and require your own Anthropic API key to use. Usage is billed directly by Anthropic based on your API consumption.

### Setup

1. Create an API key at [platform.claude.com/dashboard](https://platform.claude.com/dashboard).
2. Open **Quill → Settings** (⌘,) and find the **AI Writing** section.
3. Paste your key into the **Anthropic API Key** field and click **Save**.

Once a valid key is saved, the **✦** button appears in the editor toolbar.

### Writing Style

Quill can learn your writing style by analyzing posts from your blog. In the AI Writing section of Settings, click **Choose Sample Posts** and select up to 5 posts that are representative of how you write. When you save, Quill sends those posts to Claude to generate a concise style guide, which is then used to inform all AI writing operations.

The style guide is regenerated automatically when you change your sample post selection. If you switch to a different WordPress site, the sample selection is cleared and you will need to set it again for the new site.

### Web Search

The **Web Search** toggle in Settings allows the Generate Post feature to search the web for current information when composing a post. Disable it to generate posts using only Claude's existing knowledge, which is faster and uses less API budget.

### Generating a Post

Click the **✦** button in the editor toolbar to open the post generator. Type a topic, title idea, or detailed prompt describing what you want, then click **Generate**.

Quill will write a complete post, including a title and structured body, and load it into the editor. If web search is enabled, Claude will research the topic before writing.

If the editor already contains content, you will be asked to confirm before the existing content is replaced.

If the generated post is long and hits an initial length limit, Quill will offer to continue generating for the full version. Choosing to continue uses additional API budget.

### In-Editor AI Operations

With text selected in the editor, right-click to access AI writing operations:

| Operation | What it does |
|---|---|
| Make Longer | Expands the selected content with more detail and depth |
| Make Shorter | Condenses the selected content while preserving the key points |
| To Table | Converts the selected content into an HTML table |
| To List | Converts the selected content into a bulleted or numbered list |

These operations work on the selected text only and do not use web search. The result appears inline in the editor with an **Accept** or **Discard** panel. Accept to keep the change, or discard to restore the original text.

---

## Keyboard Reference

### App

| Shortcut | Action |
|---|---|
| ⌘N | New Post |
| ⌘⇧N | New Page |
| ⌘⌥N | New Media upload |
| ⌘, | Open Settings |
| ⌘F | Open Find & Replace |

### Editor

| Shortcut | Action |
|---|---|
| ⌘S | Save Draft (local drafts) / Update post on WordPress |
| ⌘⇧P | Publish / Update |
| ⌘Z | Undo |
| ⌘⇧Z | Redo |
| ⌘B | Bold |
| ⌘I | Italic |
| ⌘U | Underline |

### Find & Replace

| Shortcut | Action |
|---|---|
| ↩ | Next match |
| ⇧↩ | Previous match |
| Esc | Close find bar |

### Tables

| Shortcut | Action |
|---|---|
| Tab | Move to next cell |
| ⇧Tab | Move to previous cell |

### AI

| Shortcut | Action |
|---|---|
| ⌘↩ | Generate post (in the Generate Post sheet) |

---

## Limitations & Compatibility

### WordPress.com

Quill connects only to self-hosted WordPress installations. WordPress.com sites are not supported, regardless of plan. This is a deliberate scope decision; Quill is built specifically for users who run their own WordPress installations.

### One Site at a Time

Quill stores credentials for a single WordPress site. To switch sites, update your credentials in Settings. There is no multi-site management.

### Gutenberg Block Compatibility

Quill produces clean, Gutenberg-compatible HTML for the content types it supports: paragraphs, headings, lists, blockquotes, code blocks, images, tables, embeds, footnotes, and links. Posts you write in Quill will round-trip correctly through the Gutenberg editor.

However, if you open a post that was created in Gutenberg using block types Quill does not support (such as galleries, columns, cover blocks, or custom blocks) those blocks will be visible in the **Code View** (`</>`) but will not render in the visual editor. If you make visual edits to the post and save, unsupported block markup may be lost.

To edit posts that contain unsupported blocks, use Code View to work with the raw HTML directly, or make your edits in the WordPress Gutenberg editor instead.

### Featured Image

Quill reads and preserves a post's featured image setting. If a featured image is already assigned in WordPress, it will be maintained when you save from Quill. However, there is no UI in Quill to set or change the featured image. To assign a featured image for the first time, use the WordPress admin.

### Not a Full WordPress Admin

Quill is a writing tool, not a replacement for the WordPress dashboard. The following are outside its scope:

- Theme and site customization
- Plugin management
- Comment moderation
- User and role management
- Revision history
- Media editing (cropping, rotating, etc.)

### Apple Notarization

Quill is not notarized by Apple. macOS will require a one-time security bypass on first launch, as described in [Requirements & Installation](#requirements--installation). After that, the app opens normally.
