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

Quill is a native macOS application for writing and publishing content on self-hosted WordPress sites. It replaces the browser-based Gutenberg editor for drafting, editing, and publishing, with support for posts, pages, media, scheduling, and AI-assisted writing.

Quill does not compete with the block editor on layout or site building. It handles the writing; you use the WordPress admin for everything else.

### What Quill does

- Create, edit, publish, and schedule posts and pages
- Manage media uploads and insert images into content
- Organize content with categories, tags, slugs, and excerpts
- Write with a rich text editor that produces clean Gutenberg-compatible HTML
- Optionally generate and refine content using the Anthropic Claude API

### What Quill is not

- A WordPress.com client. Quill requires a self-hosted WordPress installation
- A full site builder or theme editor
- A replacement for the WordPress admin dashboard

Quill is free (but not open source).

---

## Requirements & Installation

### Requirements

- **macOS:** macOS 27 or later. Quill is built against macOS 27 and will not launch on earlier versions.
- **WordPress:** A self-hosted WordPress site running WordPress 7.0 or later. Earlier versions may work but are not officially supported. Your site must be accessible over HTTPS.

### Downloading Quill

Quill is available for free at [quill.siolon.com](https://quill.siolon.com/). Download the latest release, unzip the file, and drag **Quill.app** into your `/Applications` folder.

### First Launch: macOS Security

Quill is not notarized by Apple, so macOS blocks it from opening the first time. This is expected. To allow it:

1. Attempt to open Quill. macOS displays a message saying the app cannot be opened.
2. Open **System Settings** and navigate to **Privacy & Security**.
3. Scroll down to the Security section. A message there says Quill was blocked.
4. Click **Open Anyway**.
5. A confirmation dialog appears. Click **Open**.

Quill opens normally from this point forward. This prompt only appears once per installation.

### Updates

Quill checks for new versions automatically on launch. When an update is available, a banner appears at the bottom of the sidebar with the new version number. Click **View Release** to open the release page in your browser. Click the **×** button to dismiss the banner; it does not reappear for the same version.

To update, download the new version from the release page, unzip it, and replace the existing **Quill.app** in your `/Applications` folder. Your credentials, drafts, and settings are stored separately and carry over automatically.

---

## Connecting to WordPress

Quill connects to your WordPress site using an **Application Password**, a credential type built into WordPress that grants API access without exposing your main account password. You need three pieces of information: your site URL, your WordPress username, and an Application Password you generate in the WordPress admin.

### Step 1: Generate an Application Password in WordPress

1. Log into your WordPress admin dashboard.
2. In the left sidebar, navigate to **Users → Profile**.
3. Scroll down to the **Application Passwords** section.
4. In the **New Application Password Name** field, enter a name to identify this connection, such as "Quill".
5. Click **Add New Application Password**.
6. WordPress displays the generated password. **Copy it now.** WordPress does not show it again.

### Step 2: Enter Your Credentials in Quill

1. Open Quill's settings via the **Quill** menu → **Settings**, or press **⌘,**.
2. In the **WordPress Credentials** section, fill in the following fields:
   - **Site URL:** Your site's full URL, including `https://` (for example, `https://yoursite.com`). Trailing slashes are handled automatically.
   - **Username:** Your WordPress username.
   - **Application Password:** The password you copied from step 1.
3. Click **Save**.

Quill stores your credentials locally and connects to your site. Your posts and pages then load in the sidebar.

---

## The Interface

Quill's window has three panels: the **Sidebar** on the left, the **Editor** in the center, and the **Settings Panel** on the right. You can show or hide the sidebar and the settings panel independently.

### The Sidebar

The sidebar organizes your content into four sections. A row of four icon buttons at the top switches between them, and the selected one is highlighted:

- **Posts:** Lists all posts on your site, most recently published first. A search field lets you filter by title.
- **Pages:** Lists all pages on your site, most recently published first, with the same search capability.
- **Drafts:** Lists local drafts saved only on your Mac, not yet published or synced to WordPress.
- **Media:** Switches the sidebar to a list of filters (All Media, Images, Documents, Audio, Video) and shows your library as a gallery in the main panel, most recently uploaded first.

Click any post, page, or draft to open it in the editor; click a media item to select it. Right-click a post or page for the option to move it to trash. The search field above the list filters the current section — including Media, which searches your library by filename and title.

To hide the sidebar and maximize writing space, click the **sidebar icon** at the left of the window toolbar. Click it again to bring the sidebar back.

### The Editor

The editor area has two parts:

- **Title field:** A large text field at the top for the post or page title.
- **Editor canvas:** The main writing area below, powered by a rich text editor that produces clean WordPress-compatible HTML.

The window **toolbar** runs across the top. Its left side belongs to the sidebar, its right side to the editor:

| Control | Where | Description |
|---|---|---|
| Sidebar toggle | Left | Shows or hides the left sidebar |
| Refresh | Left | Reloads the current section from WordPress (⌘R). Hidden while the sidebar is collapsed |
| + menu | Left | New Post, New Page, or Upload Media. Hidden while the sidebar is collapsed |
| Save Draft | Right | Saves a local draft (local drafts only) |
| Revert | Right | Discards unsaved changes and restores the last saved version (remote posts only) |
| Preview | Right | Opens the post's preview URL in your browser (remote posts only) |
| Publish | Right | Publishes or updates the post on your WordPress site |
| Post Settings | Right | Shows or hides the right-side settings panel |
| Media Info | Right | Replaces Post Settings while the Media section is open; shows or hides the details inspector |

The buttons are icons; hover any of them for a label. A status symbol beside the title field shows the current state (Draft, Published, Scheduled, and so on).

When you have unsaved changes, the window's close button shows the standard grey dot, the same way TextEdit and Pages mark an edited document. Saving clears it.

Every editor action also has a menu item: **File → Save** (⌘S), **Publish** (⇧⌘P), **Revert to Saved**, and **Preview in Browser**. **View → Refresh** (⌘R) reloads the current section.

### The Settings Panel

The settings panel opens as an inspector on the right when you click **Post Settings** in the window toolbar. It contains publishing options for the current post or page, including status, scheduling, categories, tags, slug, excerpt, discussion settings, and a word count summary. Page-specific options include parent page selection. See [Post & Page Settings](#post--page-settings) for full details.

### Empty State

If no post or page is selected, the editor area displays a placeholder prompting you to select an item from the sidebar. Use the **File** menu, the **+** menu at the left of the window toolbar, or the keyboard shortcuts below to create new content.

---

## Writing & Editing

### Creating Posts and Pages

Use the **File** menu, or the **+** menu at the left of the window toolbar:

- **New Post** (⌘N)
- **New Page** (⌘⇧N)
- **New Media upload** (⌘⌥N)

New posts and pages are created as **local drafts** and appear in the Drafts section of the sidebar immediately. They are saved only on your Mac until you publish them to WordPress.

### The Editor

The editor is a rich text environment that produces clean, Gutenberg-compatible HTML. What you see is what gets published: headings, lists, blockquotes, and all formatting render as they appear on your site.

The **title field** sits above the editor canvas. Click it to type or edit the post or page title.

### Formatting Toolbar

The formatting toolbar runs across the top of the editor.

#### Block formatting

| Button | Shortcut | Function |
|---|---|---|
| Paragraph / Heading | | Dropdown menu to set the current block as Paragraph or Heading 1 through 6 |
| Bullet list | ⌘⇧8 | Converts the current block to an unordered list |
| Number list | ⌘⇧7 | Converts the current block to an ordered list |
| Blockquote | ⌘⇧B | Wraps the current block in a blockquote. When inside a blockquote, a citation toggle button appears. See [Blockquotes](#blockquotes) in Content Elements. |
| Code block | ⌘⌥C | Converts the current block to a preformatted code block |

#### Inline formatting

| Button | Shortcut | Function |
|---|---|---|
| B | ⌘B | Bold |
| I | ⌘I | Italic |
| S | ⌘⇧X | Strikethrough |
| `A` | ⌘E | Inline code |

Underline has no button — WordPress treats it as a rarely-wanted format and it reads as a link on the published page — but **⌘U** still applies it if you need it.

Formatting Quill has no button for is still kept. Subscript, superscript, keyboard input, highlight, abbreviations and a dozen similar tags written in the WordPress editor survive an edit in Quill untouched, along with whatever the original markup put on them.

#### Insert and utilities

| Button | Function |
|---|---|
| Table | Opens a size grid — drag or arrow across it to choose how many columns and rows you want, then click or press Enter. When the cursor is inside a table, additional buttons appear to add or remove rows and columns, turn the header and footer sections on and off, or delete the table. See [Tables](#tables) for more details. |
| Link | Inserts or removes a hyperlink on the selected text. Opens the link picker, where you can type to search your WordPress posts, pages, and media by title, or paste any URL directly. Selecting a search result or pressing Enter applies the link. When editing an existing link, a Remove option is also available. To open a link in your default browser, hold ⌘ and click it. Links show a pointer cursor and underline while ⌘ is held. |
| * (Footnote) | Inserts a footnote marker at the cursor position. See [Footnotes](#footnotes) for more details. |
| Embed | Inserts an embed (video, social post, etc.) by URL. See [Embeds](#embeds) for more details. |
| ABC (Spell check) | Runs a spell check on the document. See [Spell Check](#spell-check) for more details. |
| </> (Code view) | Toggles between the rich text editor and a raw HTML view. See [Code View](#code-view) for more details. |
| Image | Opens the media library picker to insert an image. See [Images](#images) for more details. |
| Gallery | Opens the gallery picker to insert a multi-image gallery. See [Gallery](#gallery) for more details. |
| + (More blocks) | Dropdown for the blocks with no button of their own: Columns, Accordion, Tabs, Details, Buttons, Pullquote, Preformatted and Separator. |
| Pencil (Generate) | Opens the AI content generator. Visible only when an Anthropic API key is configured. See [AI Writing Features](#ai-writing-features) for more details. |
| Checkmark-circle (Evaluate) | Opens the AI writing evaluator. Visible only when an Anthropic API key is configured. See [AI Writing Features](#ai-writing-features) for more details. |

The image alignment buttons (left, center, right) appear in the toolbar only when an image is selected. See [Images](#images) for more details on resizing, captions, and alt text.

#### Block settings

A second toolbar row appears whenever the cursor is inside a block that has settings of its own. The controls there match the ones WordPress shows in its own sidebar, and what you choose is saved back to WordPress as a real block setting rather than as hand-written markup.

| Block | Control | What it does |
|---|---|---|
| Button, Quote, Separator, Image, Table | Style | Picks the block style WordPress registers for that block — Outline for a button, Plain for a quote, Wide Line or Dots for a separator, Rounded for an image, Stripes for a table |
| Button | New tab | Opens that button's link in a new tab |
| Accordion | Icon / Icon side | Shows or hides the toggle icon, and puts it on the left or the right. The change applies to every section in the accordion at once, and a single undo reverses the lot |
| Accordion section | Open | Opens that section by default when the page loads |
| Tab | Default | Makes that tab the one shown first |
| Table | Header / Footer | Adds or removes the table's header and footer rows |

A link in ordinary prose gets its own **New tab** toggle beside the link button.

### Markdown Shortcuts

The editor recognizes common Markdown syntax as you type and converts it into real formatting. You never have to reach for the toolbar for these.

#### Block shortcuts

Type these at the start of an empty line:

| Type this | Result |
|---|---|
| `# ` through `###### ` | Heading 1 through Heading 6 |
| `- ` or `* ` or `+ ` | Bullet list |
| `1. ` | Numbered list |
| `5. ` | Numbered list starting at 5 (any number works) |
| `> ` | Blockquote |
| ```` ``` ```` followed by a space | Code block |
| ```` ```js ```` followed by a space | Code block with a language set (`js`, `python`, etc.) |
| `---` | Horizontal rule |
| `*** ` or `___ ` | Horizontal rule |

`---` converts as soon as you type the third hyphen. `***` and `___` need a trailing space.

#### Inline shortcuts

These convert the moment you type the closing characters, with no trailing space needed:

| Type this | Result |
|---|---|
| `**bold**` or `__bold__` | **Bold** |
| `*italic*` or `_italic_` | *Italic* |
| `~~strikethrough~~` | Strikethrough |
| `` `code` `` | Inline code |

Underline has no Markdown equivalent. Use ⌘U or the toolbar.

#### Automatic links

Typing a URL followed by a space turns it into a link automatically. This works for full URLs (`https://example.com`), bare domains (`www.example.com`), and email addresses (`name@example.com`).

#### What is not converted

- `1)` for numbered lists — only `1.` works
- `- [ ]` task lists — Quill does not support checklists
- `==highlight==`
- Punctuation substitutions. Quill deliberately leaves your typing alone: `--` stays two hyphens, `...` stays three dots, and straight quotes stay straight. If you want typographic characters, type or paste them directly.

#### Undoing a conversion

If a shortcut converts something you meant to keep as literal text, press **Backspace immediately after** the conversion happens. The block reverts and your original characters come back — `# ` stays `# `, `**bold**` stays `**bold**`. (The code block shortcut is the exception: Backspace removes the block but not the backticks.)

This only works as the very next keystroke. Once you type anything else, Backspace behaves normally and ⌘Z undoes the surrounding typing along with the conversion.

### Pasting

What happens when you paste depends on what is on the clipboard. Content copied from a web page, word processor, or chat app carries HTML, and ⌘V handles it well. Plain-text Markdown does not, and needs its own command.

#### Formatted content (⌘V)

Quill rebuilds pasted HTML using its own formatting rather than accepting the original markup, so you never inherit another app's fonts, colors, or `<span>` scaffolding. Pasting from Word or Google Docs gives you clean content that matches the rest of your post.

Headings, paragraphs, lists (including nested ones), blockquotes, tables, images, links, and inline formatting all survive, as do classes and IDs already on your blocks. Gutenberg blocks copied from another WordPress site are preserved exactly, block comments and all.

A few things are dropped silently, which is the part worth watching:

| Pasted | Result |
|---|---|
| `<iframe>`, `<video>`, `<audio>` | Removed entirely; nothing is inserted |
| Definition lists | Flattened into ordinary paragraphs |

Highlight, superscript, subscript, keyboard input and abbreviations are kept.

The embed case is the likeliest to catch you out: copying a YouTube `<iframe>` from a page's source inserts nothing at all. Use the **Embed** toolbar button and paste the video's URL instead (see [Embeds](#embeds)). After any large paste, a quick look in [Code View](#code-view) confirms everything arrived.

#### Markdown (⌘⇧V)

The [Markdown shortcuts](#markdown-shortcuts) above apply to text you *type*. Pasting Markdown is different: an ordinary ⌘V inserts it literally, so `# Heading` arrives as the characters `# Heading`. (Confusingly, `**bold**` and `` `code` `` *do* convert on paste, so the result ends up half-formatted.)

Use **Edit ▸ Paste as Markdown** (**⌘⇧V**) instead. It converts the whole clipboard at once and inserts it at the cursor as finished content: headings, lists, blockquotes, tables, code blocks, horizontal rules, links, and inline formatting.

**Notes:**

- Ordinary ⌘V is unchanged. Paste as Markdown is a separate command.
- If your clipboard came from a web page or a chat app, plain ⌘V is usually better, since that content arrives as HTML and already converts correctly.
- Markdown images (`![alt](url)`) keep their original URL. That image is not in your media library, so publishing would load it from wherever it currently lives. Replace it with an uploaded image first.
- The command is refused, with an explanation, inside footnotes, code blocks, and code view. Nothing is inserted in those cases.
- Task list checkboxes (`- [ ]`) become plain list items, since Quill has no checklist block.

### Saving and Publishing

#### For local drafts

- Click **Save Draft** or press **⌘S** to save your work locally. The draft remains on your Mac and does not touch WordPress.
- Click **Publish** or press **⌘⇧P** to push the post to WordPress. After publishing, the post moves from Drafts to Posts or Pages in the sidebar.

#### For posts and pages already on WordPress

- Press **⌘S** or click **Publish** to sync your changes to WordPress immediately.
- The dot in the window's close button indicates you have unsaved changes; it clears when you save.
- Click **Revert** to discard unsaved changes and restore the last saved version. A confirmation alert appears; press **↩** to confirm or **Escape** to cancel.

**Autosave:** Quill automatically saves your work every 30 seconds after a change, so you don't lose progress if you close the app unexpectedly. For remote posts, autosaves are stored locally and applied if you reopen a post before manually saving.

### Preview

Click **Preview** in the toolbar to open the current post in your browser as it appears on your site. Preview is only available for posts and pages already on WordPress, not for local drafts.

When you preview a **published** post, Quill sends your unsaved changes to WordPress as a temporary revision. The live post is not affected; only the preview shows the changes.

When you preview a **draft** post, WordPress updates the draft itself with your current editor content. This is standard WordPress behavior: drafts do not have separate revision state, so previewing a draft is equivalent to saving it on WordPress.

### Find and Replace

Press **⌘F** to open the find and replace bar. Type in the **Find** field to highlight matches in the document. Use the arrow buttons or press **↩** (next) and **⇧↩** (previous) to navigate between matches. Toggle **Aa** to enable case-sensitive search.

To replace matches, type in the **Replace** field and click **Replace** to replace the current match or **All** to replace every match in the document. Press **Esc** or click **X** to close the find bar.

### Spell Check

Click the **ABC** button in the toolbar to check spelling. Right-clicking on any word in the editor while editing shows a context menu with spelling suggestions when a spelling error is detected under the cursor.

### Code View

Click the **</>** button in the toolbar to toggle between the visual editor and a raw HTML view of your post. Code view shows the exact WordPress block HTML Quill saves, including Gutenberg block comments such as `<!-- wp:paragraph -->`, formatted and indented for readability.

**Editing in code view.** You can type directly in the code view textarea. Changes are synced to Quill automatically as you type, so you do not need to exit code view before saving. Pressing **⌘S** saves whatever is in the textarea. When you exit code view, your changes appear in the visual editor.

**What survives visual edits.** CSS classes and IDs added to the following elements in code view persist even after you return to the visual editor and continue editing:

- Paragraphs, headings, blockquotes, citations
- Lists (`<ul>`, `<ol>`, `<li>`)
- Code blocks, horizontal rules
- Tables (`<table>`, `<tr>`, `<th>`, `<td>`)
- Image figures (`<figure>`) and image elements (`<img>`)
- Links (`<a>`)

For example, adding `class="intro"` to a `<p>` tag in code view, switching back to the visual editor, and typing more text does not remove your class. Editing a link's URL through the link picker also preserves any classes you added to the `<a>` tag. Classes are never copied to new elements when you press Enter to create a new block.

**What survives saving but not visual edits.** Any HTML change you make in code view (including inline styles, data attributes, or custom elements without a `wp-block-*` class) is preserved when you save directly from code view or without making visual edits first. The raw HTML you wrote is sent to WordPress exactly as-is. However, if you return to the visual editor and make changes, the editor reconstructs the HTML from its internal model, and anything outside the supported schema (see the list above) is lost.

**Unsupported Gutenberg blocks.** If your post contains a block Quill doesn't natively support (Audio, Video, Playlist, Cover, Group, Media & Text, Spacer, Custom HTML, or a third-party plugin block), it appears in the visual editor as a card labeled with the block's name and the hint "Not editable in the visual editor; use Code View." This card preserves the block's original markup exactly, including any nested content, and survives edits you make elsewhere in the post; it's only lost if you delete the card itself. To edit the block's own content, use code view.

**Tip: making your own custom HTML survive visual edits.** If you hand-write a custom element in code view, such as a disclosure box, callout, or other snippet with no `wp-block-*` class, it is stripped down to plain text the moment you touch the visual editor, per the rule above. To protect it, add any class starting with `wp-block-` (for example `wp-block-group`) alongside your own class. Quill then treats it the same as an unsupported Gutenberg block: it survives as a preserved card, and you can still edit its contents in code view.

The practical rule: if you need to make changes that go beyond CSS classes on supported elements, do your visual editing first, then switch to code view for your final HTML pass before saving.

---

## Content Elements

### Images

Click the **Image** button in the toolbar to open the media library picker and insert an image at the cursor position. See [Media Library](#media-library) for details on uploading and browsing media. You can also drag an image file directly from Finder onto the editor canvas; Quill uploads it to your WordPress media library and inserts it in one step. If the file is a HEIC photo (the format iPhones use by default), Quill converts it to JPEG before uploading, so WordPress can generate the usual thumbnail and preview sizes.

While a dropped file uploads, a small progress pill appears at the bottom of the window. If you drop several images at once, it counts through them ("Uploading image 2 of 3…") and the drop finishes with a single message such as "3 images inserted" rather than one message per file. If something goes wrong, the message names the problem for a single file, or reports how many of the batch failed. Dropping another batch while one is still uploading is fine: Quill finishes the first batch before starting the second.

**Where the cursor goes:** after an image is inserted, the cursor moves to a new empty paragraph below it, so you can keep typing straight away. Adding a caption is optional; see [Captions](#captions).

Once an image is inserted, click it to select it. A floating image toolbar appears above the image, and alignment controls become available in the main toolbar.

#### Resizing

Images can be resized in two ways:

- **Drag handles:** Eight handles appear around the selected image (corners and edges). Drag any handle to resize freely.
- **W and H fields:** Enter exact pixel dimensions in the width and height fields in the image toolbar.
- **Reset:** Click Reset to restore the image to its original full-resolution dimensions.

#### Preset sizes

If the image was inserted from your WordPress media library, the image toolbar shows preset size buttons (**Thumb**, **Medium**, **Large**, and **Full**) corresponding to the sizes WordPress has generated for that image. Click a size to jump directly to those dimensions. These buttons only appear for images with a known media ID; externally linked images show only the manual W/H fields.

#### Alt text

Enter a description in the **Alt** field in the image toolbar. This text is saved with the image and used for accessibility and SEO. Alt text set in the media library is pre-populated automatically when you insert an image.

If an image was marked as decorative in the WordPress block editor, that setting is preserved. Quill keeps the image marked decorative when you edit and save the post; it doesn't add or remove the setting on its own, and there's no control for it in Quill's image toolbar.

#### Alignment

Use the alignment buttons in the main toolbar (left, center, right) to float or center the image. These buttons are only visible when an image is selected.

#### Captions

Captions are optional. A newly inserted image has an empty caption and the cursor sits in a new paragraph below the image, so typing right after an insert adds body text, not a caption. To add one, click the caption area directly beneath the image to place the cursor there, then type. Captions are saved as part of the Gutenberg image block. Pressing **Enter** inside a caption exits the image and creates a new paragraph below it.

#### Linking to the full-size image

Click **Link to Full Image** in the image toolbar to wrap the image in a link to its original, full-resolution file. Clicking the image on your published site opens (or downloads) the full-size version, and you may click it again to remove the link. This is independent of the image's displayed size, so you can show a small or resized image in the post while still linking to the original.

### Gallery

Click the **Gallery** button in the toolbar to open the gallery picker. Click images in the media grid to select them: a checkmark appears on each selected image, and they're listed in the Selected panel in the order they'll appear. Drag a selected image by its grip handle to reorder it, or click the **X** next to it to remove it.

Click the chevron on a selected image to set its **Alt text** and **Caption**. Alt text is automatically loaded if set in the media library. Changes you make here apply only to this gallery, the media library item itself is untouched, so other posts using the same image are unaffected. Captions are plain text and appear alongside their image on your published site.

Click **Upload** in the gallery picker to add a new image from disk directly to your media library; it's added to the grid and automatically selected.

Gallery settings, available once you've selected at least one image:

- **Columns:** Number of images per row (1–8).
- **Crop:** Crops images to a square aspect ratio when enabled.
- **Link To:** Choose **None** or **Full Image** (each thumbnail links to its own full-resolution file).
- **Size:** The image size to use for each thumbnail: **Thumbnail**, **Medium**, **Large**, or **Full Size**.

> **A note on Size:** WordPress often automatically offers browsers a range of file sizes for each image (this is what makes photos look crisp on high-resolution displays like Retina screens), and the browser is free to pick whichever one it thinks looks best, regardless of the Size you chose here. On a modern high-density display, you may not notice a visual difference between Medium and Large for this reason. Size still reliably matters for older browsers, RSS feeds, email, and other places that don't support this automatic behavior, and it always affects file size/page weight, since it changes which image WordPress treats as the "base" file for the gallery.

Click **Insert Gallery** to add it to the editor as a single block. A gallery appears as a read-only thumbnail grid card in Quill; to change it — including alt text and captions — delete it and insert a new one, or edit the markup directly in Code View.

Galleries authored outside Quill (e.g. in the WordPress block editor) load the same way, as a read-only card, and any captions or other details not covered by the settings above are preserved even after you make unrelated edits elsewhere in the post.

### Blockquotes

Press **⌘⇧B** or click the **Blockquote** button in the toolbar to wrap the current block in a blockquote.

**Adding a citation:** When the cursor is inside a blockquote, a citation toggle button (bookmark icon) appears in the toolbar. Click it to add a citation line at the bottom of the blockquote, where you can type an author name or source. Click it again to remove the citation. Empty citations are automatically stripped when the post is saved.

**Enter key behavior:** Pressing **Enter** inside a blockquote creates a new paragraph within the blockquote. Pressing **Enter** on an empty line exits the blockquote and creates a new paragraph below it.

**Removing a blockquote:** Press **⌘⇧B** again or click the Blockquote button to unwrap the blockquote, returning its contents to normal paragraphs.

**Pullquote** is a separate block, for a quote meant to stand out from the text rather than sit in it. Insert it from the **+** menu. It takes a citation from the same **Cite** button.

### Container Blocks

Columns, Details, Buttons, Accordion, Tabs, Pullquote and Preformatted are blocks that hold other content. Insert any of them from the **+** button in the toolbar, then type into them the way you would type anywhere else.

| Block | What it is |
|---|---|
| Columns | Side-by-side columns of content |
| Details | A collapsible section with a summary line you click to open |
| Buttons | One or more link buttons |
| Accordion | A stack of collapsible sections, each with its own heading |
| Tabs | Tabbed panels, one shown at a time |
| Pullquote | A quote set apart from the body text |
| Preformatted | Text kept exactly as typed, spacing and line breaks included |

A fresh Accordion or Details starts without a title. Quill shows a greyed hint where the title goes so you can see it is there — clicking that row puts the cursor in the title rather than collapsing the section. The hint is only in the editor; it never appears on your site.

**Getting out of a block.** Press **Esc** and the cursor moves to the paragraph below the block, making one if there isn't one already. Pressing **Enter** twice does the same thing. Inside nested blocks, each press steps out one level. This is how you keep writing after a block that has nothing below it.

**Deleting a block.** With the cursor inside a block, a **✕** appears at the right-hand end of the second toolbar row, labelled with the block it will remove. Click it, or press **⌘⇧⌫**. The cursor lands in the block after the one you deleted — or the one before it, if nothing follows. Inside nested blocks, the innermost one goes first, so you can work outwards rather than losing the lot at once.

Settings for these blocks — a button's style and whether its link opens in a new tab, an accordion's icon, which tab opens first — are in the second toolbar row. See [Block settings](#block-settings).

### Separator

A horizontal rule between sections. Insert it from the **+** menu, or type `---` on an empty line. Click it to select it, and the **✕** or **⌘⇧⌫** removes it. Its style — a wide line or a row of dots — is in the block settings row.

### Footnotes

Quill has full support for WordPress-style footnotes. To insert a footnote, place the cursor where you want the marker to appear and click the **\*** button in the toolbar.

When you insert a footnote, two things happen automatically:

1. A numbered superscript marker appears inline at the cursor position.
2. A footnote entry is added to a numbered list at the bottom of the document, where you can type the footnote text.

- **Automatic numbering:** Footnote markers are always numbered sequentially from 1 based on their position in the document. If you insert a footnote between two existing ones, or delete one, all numbers update automatically; you never need to renumber manually.
- **Navigating between markers and entries:** Each footnote entry at the bottom of the document has a **↩** button. Clicking it jumps your cursor back to the corresponding marker in the body text.
- **Deleting footnotes:** Delete the inline marker in the body text and the corresponding footnote entry at the bottom of the document is removed automatically. You cannot delete entries from the list directly; they are always kept in sync with the markers.
- **Line breaks:** Press **Enter** inside a footnote entry to insert a line break within the entry. Unlike the main editor, Enter does not create a new block; it creates a soft break so you can write multi-line footnotes.
- **Content restrictions:** Footnotes support only inline content: bold, italic, strikethrough, inline code, and links. Block elements such as images, headings, lists, tables, and blockquotes cannot be inserted inside footnotes. The toolbar buttons for these elements are disabled when the cursor is inside a footnote entry. If you paste content containing block elements into a footnote, the block structure is stripped and only the text and inline formatting are kept.
- **On publish:** Quill saves footnotes the way current WordPress does — the post itself carries a footnotes marker, and the note text is stored in the post's own footnote field. The published page shows the notes and the back-arrows exactly as Gutenberg would; Quill does not write a second back-arrow of its own.
- **Older posts:** footnotes written by an earlier version of Quill were stored differently. Such a post is left exactly as it is until you edit it; the first edit moves the notes into the current format. Nothing is lost either way.

### Tables

Click the **Table** button in the toolbar to open a size grid. Move across it and the label above reads back the size you are on — "4×3 Table" is four columns by three rows — then click to insert. The arrow keys work too, with Enter to insert and Escape to close.

When the cursor is inside a table, these buttons appear in the toolbar:

| Button | Function |
|---|---|
| +Row | Inserts a row below the current row |
| +Col | Inserts a column to the right of the current column |
| −Row | Deletes the current row |
| −Col | Deletes the current column |
| Header | Adds or removes the table's header row |
| Footer | Adds or removes the table's footer row |

To delete the whole table, use the ✕ at the right-hand end of the block toolbar row, or press **⌘⇧⌫**. That is the same control every block uses — see [Container Blocks](#container-blocks).

Press **Tab** to move forward through cells, or **⇧Tab** to move backward. Pressing Tab from the last cell in a row moves to the first cell of the next row.

**Headers and footers:** A new table gets a header row, saved as a proper `<thead>` in the published HTML. Use the **Header** and **Footer** buttons to add or remove either section; a table opened from WordPress keeps whichever sections it arrived with.

**Captions:** A caption written in the WordPress editor is kept exactly as it was. Quill does not create or edit table captions — add one in WordPress if you need it.

### Embeds

Quill supports embedding content from external platforms (videos, social posts, audio, and more) directly in your posts and pages.

To insert an embed:

1. Click the **Embed** button in the toolbar.
2. A small input menu appears. Paste the URL of the content you want to embed.
3. Press **Enter** or click **Insert**.

The embed appears in the editor as a card showing the URL. It renders as a live embed on your published site; Quill does not preview the embedded content.

#### Supported providers

| Provider | Content type |
|---|---|
| YouTube | Video |
| Vimeo | Video |
| Twitter / X | Posts |
| Instagram | Posts |
| TikTok | Video |
| Spotify | Music / podcasts |
| SoundCloud | Audio |

URLs from providers not listed above are saved as generic embeds. WordPress attempts to render them with its own oEmbed support.

> Some embeds do not render correctly on your published site. Provider support depends on the platform's oEmbed implementation and can change without notice. X (formerly Twitter) is a known example where embed rendering is inconsistent.

---

## Post & Page Settings

Click **Post Settings** at the right end of the window toolbar to open the settings panel. It opens as an inspector on the right of the window and contains all publishing options for the current post or page. The same slot is shared with the Evaluation panel, so opening one replaces the other.

Changes made in the settings panel take effect when you next save or publish the post. They are not sent to WordPress automatically as you adjust them.

> Settings you configure for a local draft (categories, tags, slug, etc.) are sent to WordPress when you publish. However, they are not saved locally with the draft. If you close the app before publishing, you need to set them again.

### Status

The Status picker controls the publish state of the post or page:

| Status | Symbol | Color | Description |
|---|---|---|---|
| Draft | Pencil | Amber | Saved to WordPress but not publicly visible |
| Pending Review | Ellipsis | Orange | Flagged for editorial review before publishing |
| Published | Checkmark | Green | Live and publicly visible |
| Scheduled | Clock | Blue | Will publish automatically at the specified date and time |
| Private | Lock | Teal | Visible only to logged-in WordPress administrators and editors |
| Local draft | Tray | Violet | Saved only on your Mac, not yet sent to WordPress |

The symbol appears beside the title field in the editor; the sidebar shows the same status as a coloured dot next to each row's subtitle. Colour is never the only signal — the symbol carries the status too.

Local drafts (posts and pages not yet synced to WordPress) share one violet status colour; the sidebar row's subtitle says whether it is a post or a page, and the editor shows a violet tray symbol beside the title.

### Publish Date

The Publish Date section appears for all statuses except Private. It contains a **Schedule** toggle. When turned on, the status is set to Scheduled and a date and time picker appears. When turned off, the status reverts to Draft if it was previously set to Scheduled.

You can also set scheduling by selecting **Scheduled** directly in the Status picker; the date picker appears automatically with a default time one hour from now.

Once you have set the date and time, press **⌘⇧P** or click **Publish** to commit the scheduled post to WordPress. The post then publishes automatically at the chosen time.

### Categories (Posts only)

The categories section lists all categories on your site. Check a category to assign it to the post. Checked categories always sort to the top of the list (alphabetically), followed by unchecked categories (also alphabetically). Use the search field to filter categories by name.

To create a new category, type its name in the search field and press Enter. New categories are created on your WordPress site when the post is saved or published.

### Tags (Posts only)

Tags work similarly to categories. Selected tags appear as chips above the search field, sorted alphabetically. Type in the search field to find existing tags or press Enter to create a new one. New tags are created on your WordPress site when the post is saved or published.

### Slug

The slug is the URL-friendly identifier for the post or page, used in the permalink. Edit this field to customize the URL. Leave it blank to let WordPress generate one automatically from the title.

### Excerpt (Posts only)

The excerpt is a short summary of the post, shown by some themes on archive and search result pages. Type directly in the excerpt field. If you leave it blank, your theme may show the first few words of the post body instead. This happens on your site, not inside Quill.

### Parent Page (Pages only)

The Parent Page picker sets the hierarchy of the page. Select a parent page to nest this page beneath it in the URL structure, or leave it set to **None (top-level)** for a root-level page.

### Discussion

The Discussion section contains a single **Allow comments** toggle. Turn it off to disable comments on the post or page.

### Stats

The Stats section displays a live word count and character count for the current post, updated as you type. Once the post has enough content, Quill also estimates reading time at 238 words per minute, rounded up to the nearest minute.

---

## Media Library

The Media Library gives you access to all files uploaded to your WordPress site. Switch to the **Media** tab in the sidebar; the sidebar becomes a list of filters and the library fills the main panel as a gallery.

### Browsing

Images appear as thumbnails. Non-image files (PDFs, documents, etc.) show a generic file icon. Click any item to select it; press Space or double-click to open a large preview. Arrow keys move the selection.

The grid loads more items as you scroll. There is no button to press — keep scrolling and the next page appends at the bottom.

The sidebar filters narrow the grid to one kind of file. **Documents** covers PDFs and office files; plain-text files such as `.txt` and `.csv` are not listed there, and you'll find them under **All Media**. The search field above the filters searches within the active filter, so clear the search or switch to All Media if a file you expect is missing.

Right-click any item for:

| Item | Action |
|---|---|
| Show Details | Opens the inspector on that item |
| Copy URL | Copies the file's URL to the clipboard |
| Open in Browser | Opens the item's WordPress attachment page (hidden when the item has no link) |
| Delete… | Permanently deletes the file from WordPress — see [Deleting Media](#deleting-media) |

### Previewing

Press **Space** or double-click a selected item to open a large preview over the gallery. Press **Space** again, press **Escape**, or click the background to dismiss it. Previews are shown for images; other file types display a placeholder.

### Item Details

Selecting an item does not open its details on its own. To see them, click **Media Info** at the right of the window toolbar, or right-click the item and choose **Show Details**. Either opens an inspector on the right of the window, which tracks whatever is selected until you close it.

The inspector shows:

| Field | Description |
|---|---|
| Filename | The media item's title, or its filename if no title is set |
| Type | The file extension |
| Dimensions | Pixel dimensions (images only) |
| Alt Text | Editable alt text description (images only) |
| Uploaded | The date the file was uploaded |
| URL | The full URL of the file, with a copy button |

**Alt text** can be edited directly in the inspector. Press **Return** or click away from the field to save the change to WordPress.

### Uploading

To upload new media:

- Click **New Media** in the toolbar, or
- Use **File → New Media** (⌘⌥N) from anywhere in the app.

Both open a standard macOS file picker. Any file type supported by your WordPress installation can be uploaded. The new item appears at the top of the grid and is selected; open **Media Info** if you want to see its details.

If a filter is active that doesn't cover the file you just uploaded — uploading a PDF while **Images** is selected, say — the view switches to **All Media** so the new item is still in front of you.

HEIC photos are converted to JPEG automatically before they're sent to WordPress. WordPress accepts HEIC files but can't produce thumbnail and preview sizes from them, so an unconverted HEIC would appear in your media library with no dimensions and no resized versions. Conversion happens on your Mac, keeps the photo's full resolution and orientation, and leaves the original file on disk untouched. It applies wherever you upload: the Media sidebar, the image picker, the gallery picker, and drag-and-drop onto the editor. Other formats (JPEG, PNG, GIF, WebP, PDF, and so on) are uploaded as-is.

### Inserting Images into Posts

To insert an image from your media library into a post or page, click the **Image** button in the editor toolbar while editing. This opens a picker sheet showing your media library. Click an image to insert it at the cursor position.

You can also drag one or more image files directly from Finder onto the editor canvas to upload and insert them in one step. A progress pill at the bottom of the window tracks the upload, and a multi-file drop reports a single summary message when it's done.

### Deleting Media

Right-click any item in the media grid and select **Delete** to remove it. A confirmation prompt appears before the deletion proceeds.

> Deleting media is permanent. WordPress does not have a trash for media items; deletion cannot be undone.

---

## AI Writing Features

Quill includes an optional AI writing assistant powered by the Anthropic Claude API, using the Claude Haiku model. AI features are disabled by default and require your own Anthropic API key to use. Usage is billed directly by Anthropic based on your API consumption.

When configured, Quill's AI features let you generate complete posts and pages from a prompt, rewrite selected text, and evaluate the writing quality of your content.

### Setup

1. Create an API key at [platform.claude.com/dashboard](https://platform.claude.com/dashboard).
2. Open **Quill → Settings** (⌘,) and find the **AI Writing** section.
3. Paste your key into the **Anthropic API Key** field and click **Save**.

Once a valid key is saved, a **pencil** button (Generate) and a **checkmark-circle** button (Evaluate) appear in the editor toolbar.

### Writing Style

Quill can learn your writing style by analyzing posts from your blog. In the AI Writing section of Settings, click **Choose Posts** and select up to 5 posts that are representative of how you write. When you save, Quill sends those posts to Claude to generate a concise style guide, which is then used to inform all AI writing operations.

The style guide is regenerated automatically when you change your sample post selection. If you switch to a different WordPress site, Quill clears the sample selection and you need to set it again for the new site.

### Web Search

The **Web Search** toggle in Settings allows the Generate Content feature to search the web for current information when composing a post. Disable it to generate posts using only Claude's existing knowledge, which is faster and uses less API budget.

### Generating Content

Click the **pencil icon** in the editor toolbar to open the content generator. Type a topic, title idea, or detailed prompt describing what you want, then click **Generate**.

Quill writes a complete post or page, including a title and structured body, and loads it into the editor. If web search is enabled, Claude researches the topic before writing.

If the editor already contains content, a **Replace Content?** confirmation alert appears first. Press **↩** to proceed or **Escape** (or Cancel) to go back.

If the generated content is long and hits an initial length limit, a **Post may be cut off** alert appears. Choose **Get Full Version** (↩) to request a longer response, or **Use What I Have** to accept the draft as-is. Getting the full version uses additional API budget.

### Evaluating Writing Quality

Click the **checkmark-circle icon** in the editor toolbar to evaluate the current post or page. The editor must contain at least around 100 words for evaluation to be available.

Quill sends the full content to Claude and displays an **Evaluation panel** in the inspector on the right of the window. It shares that slot with Post Settings, so opening the evaluation replaces the settings panel. The panel shows:

- A short prose **summary** of the overall writing quality
- A list of specific **findings**, each tagged with a category (Grammar, Clarity, Readability, Wordiness, Passive Voice, or Tone) and an optional suggested rewrite

**Jumping to a finding:** Click any finding card to jump directly to that sentence in the editor. The full sentence is selected and scrolled into view so you can read the finding in context.

**Re-evaluating:** Click **↺ Re-evaluate** at the bottom of the panel to run another pass after making edits.

**Style awareness:** If you have configured a writing style guide using sample posts (see Writing Style above), Claude uses it during evaluation to distinguish your intentional voice from genuine issues. Stylistic choices consistent with your established writing are not flagged.

The checkmark-circle button is highlighted while the evaluation panel is open and is disabled while an evaluation is running. The panel has no close button of its own — click **Post Settings** in the window toolbar to close the inspector, and again to bring the settings back.

### In-Editor AI Operations

With text selected in the editor, right-click to access AI writing operations:

| Operation | What it does |
|---|---|
| Make Longer | Expands the selected content with more detail and depth |
| Make Shorter | Condenses the selected content while preserving the key points |
| To Table | Converts the selected content into an HTML table |
| To List | Converts the selected content into a bulleted or numbered list |

These operations work on the selected text only and do not use web search. The result appears inline in the editor with an **Accept** or **Discard** panel. Accept to keep the change, or discard to restore the original text.

**Lists and tables:** When your selection is inside a list or table, Make Longer and Make Shorter automatically detect the structure and apply changes that preserve the format, expanding or condensing individual list items or table cells rather than converting them to plain paragraphs.

---

## Keyboard Reference

The editor also converts Markdown syntax as you type — `# ` for a heading, `**bold**`, `---` for a horizontal rule, and more. See [Markdown Shortcuts](#markdown-shortcuts) for the full list.

### App

| Shortcut | Action |
|---|---|
| ⌘N | New Post |
| ⌘⇧N | New Page |
| ⌘⌥N | New Media upload |
| ⌘, | Open Settings |
| ⌘R | Refresh the current section |
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
| ⌘U | Underline (no toolbar button) |
| ⌘⇧X | Strikethrough |
| ⌘E | Inline code |
| ⌘⇧8 | Bullet list |
| ⌘⇧7 | Ordered list |
| ⌘⇧B | Blockquote |
| ⌘⌥C | Code block |
| ⌘⇧V | Paste as Markdown |
| Esc | Step out of the block the cursor is in |
| ⌘⇧⌫ | Delete the block the cursor is in |

### Media Library

| Shortcut | Action |
|---|---|
| ← → ↑ ↓ | Move the selection in the gallery |
| Space | Open or close the large preview |
| Esc | Close the preview |
| ⌘⌥N | Upload a new file |

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
| ⌘↩ | **Generate** in the Generate Content sheet |
| ↩ | Confirm the highlighted button in a confirmation alert (Replace Content?, Revert to Server Version?, Conflict Detected, Post may be cut off) |
| Esc | Dismiss any sheet or alert without acting |

---

## Limitations & Compatibility

### WordPress.com

Quill connects only to self-hosted WordPress installations. WordPress.com sites are not supported, regardless of plan. This is a deliberate scope decision; Quill is built specifically for users who run their own WordPress installations.

### One Site at a Time

Quill stores credentials for a single WordPress site. To switch sites, update your credentials in Settings. There is no multi-site management.

### When Quill can't preserve something

Quill checks, every time it loads a post and every time you leave code view, that every block in the post it received is still accounted for in the document it is showing you. If something has gone missing, a banner appears at the top of the editor naming the blocks affected, and **saving is blocked until you acknowledge it**. This is deliberate: saving at that moment would write the shortened content back over the real post.

What to do when you see it:

1. **Read which blocks it names.** The banner lists them by name.
2. **If you need them, don't save.** Close the post and open it in the WordPress editor instead. Nothing has been written yet.
3. **If you want to fix it in Quill,** open **Code View** (`</>`) and paste the missing block's markup back in. When you leave code view the banner clears itself and saving works again.
4. **If you're happy to lose them,** click to acknowledge the banner and save. After saving, the banner tells you the content is gone and points at WordPress's revision history, which still has the previous version.

Two things worth knowing:

- **A post you haven't edited always saves.** Quill writes the original content back unchanged in that case, so there is nothing to lose and nothing to warn about.
- **Reopening a post you already saved this way is quiet.** The loss is in the saved post now, so there is nothing left to warn about.

This banner should be rare. Blocks Quill has no editor for are normally preserved exactly — see below.

### Gutenberg Block Compatibility

Quill produces clean, Gutenberg-compatible HTML for the content types it supports: paragraphs, headings, lists, blockquotes, code blocks, separators, images, galleries, tables, embeds, footnotes, links, and the container blocks Columns, Details, Buttons, Accordion, Tabs, Pullquote and Preformatted. Posts you write in Quill round-trip correctly through the Gutenberg editor.

**Settings you apply in WordPress are kept.** A colour, a font size, a border radius, a block style, a link that opens in a new tab, a table's fixed layout — Quill carries these through an edit even where it offers no control for them, and writes them back the way WordPress wrote them. Editing a post in Quill should leave everything you set in Gutenberg exactly as you left it.

Blocks Quill doesn't support natively (Audio, Video, Playlist, Cover, Group, Media & Text, Spacer, Custom HTML, shortcodes, and third-party plugin blocks) are preserved rather than edited. Each appears in the visual editor as a labeled card marked "Not editable in the visual editor; use Code View," showing a short preview of its source. You can move or delete the card, and you can keep editing the rest of the post freely: the block's original markup is saved back to WordPress exactly as it arrived, byte for byte. To change what's inside one of these blocks, use **Code View** (`</>`) to edit the raw HTML, or make that edit in the WordPress editor.

**Classic posts are converted when you edit them.** A post written before the block editor has no block structure. Opening it and saving without changes leaves it untouched, but making any edit converts it to blocks — the same conversion WordPress's own "Convert to blocks" performs. Paragraphs, headings and lists come through fine; a plain wrapper `<div>` with a custom class does not survive the conversion. If a classic post depends on custom wrapper markup, edit it in the WordPress editor instead.

Galleries load as a read-only thumbnail-grid card: Quill cannot edit an existing gallery's images or settings, only insert new ones. To change an existing gallery, delete it and insert a replacement.

### Featured Image

Quill reads and preserves a post's featured image setting. If a featured image is already assigned in WordPress, Quill keeps it when you save. However, there is no UI in Quill to set or change the featured image. To assign a featured image for the first time, use the WordPress admin.

### Not a Full WordPress Admin

Quill is a writing tool, not a replacement for the WordPress dashboard. The following are outside its scope:

- Theme and site customization
- Plugin management
- Comment moderation
- User and role management
- Revision history
- Media editing (cropping, rotating, etc.)

### Apple Notarization

Quill is not notarized by Apple. macOS requires a one-time security bypass on first launch, as described in [Requirements & Installation](#requirements--installation). After that, the app opens normally.
