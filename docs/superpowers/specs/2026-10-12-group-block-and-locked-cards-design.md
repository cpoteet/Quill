# Editing Groups, and clearer locked cards

_Design, 2026-10-12._

## Problem

Quill has no node for the Group block (`core/group`), so every Group loads as one locked card. Most patterns, including nearly all of Twenty Twenty-Five's, are wrapped in a Group, so an inserted pattern is usually locked even when everything inside it is a heading, paragraph, list, image or button that Quill edits everywhere else.

The locked cards themselves are hard to read. The preview is the first 120 characters of the block's source, which for a Cover or Media & Text is class names and inline styles. A synced pattern is stored in the post as `<!-- wp:block {"ref":123} /-->`, so its card reads "Block" with that line underneath and says nothing about what the pattern contains.

## Goals

1. **Edit existing Groups.** A Group opens for editing when every block inside it is one Quill already models. Its tag, colours, spacing, layout and other settings are saved back unchanged.
2. **Clearer locked cards.** A card's label uses the block's custom name when it has one, and its preview shows the block's text instead of its markup.
3. **Readable synced patterns.** A synced pattern's card shows the pattern's title and text, fetched from WordPress, with a link to edit it in WordPress.

Non-goals: inserting a Group, wrapping or unwrapping a selection in one, editing any Group setting, drawing Row or Grid layouts as rows or grids, opening a Group that holds a block Quill does not model, editing a synced pattern inside Quill, Cover and Media & Text as editable blocks, and caching synced-pattern data between post loads.

## Regression rule

A post that saves cleanly today must still save cleanly, and a post opened and left unedited still saves back byte for byte (`_rawHTML`, unchanged by this work). Anything Quill cannot fully represent stays a locked card exactly as it does today. Where a choice trades editability for safety, this design takes safety.

## 1. Editing Groups

### Which Groups open

A Group is **fully supported** when all of these hold:

- Every block inside it, at every depth, is a block Quill models (`modelsBlockName`). A Spacer, Cover, shortcode, Custom HTML, synced pattern or third-party block anywhere inside fails this.
- Every block inside it saves markup. A modeled block with none, such as `<!-- wp:image /-->`, has nothing for the editor to parse and would be dropped. Today this guard runs only on top-level blocks; for Groups it runs at every depth.
- Its own markup, with its inner blocks removed (the parser's `innerHTML`), is exactly one element whose tag is one the node parses (below), with only whitespace beside it and only whitespace inside it. This rejects a `nav` Group or any other tag the node does not parse, the old `wp-block-group__inner-container` markup, and stray text or HTML before, between or after the inner blocks.
- It holds at least one block. An empty Group stays locked, because the editor would add an empty paragraph to it and change its saved markup.
- Every Group nested inside it is fully supported too.

The check runs on **top-level blocks** in `wrapUnsupportedBlocks`, the existing byte-exact path. A top-level block that contains a Group anywhere in its tree is wrapped whole as an unsupported card if any of those Groups is not fully supported. Two consequences:

- A top-level Group that fails stays one locked card, as today.
- Columns, Details or Accordion containing a failing Group is locked whole. Today the container is editable and only the Group inside it is a card. This case loses editability but never content, and it keeps every Group on the byte-exact path. It is the one deliberate step back.

The rule applies wherever `wrapUnsupportedBlocks` runs: `window.setContent` and `_exitCodeView`'s user-edited branch.

### The node

A `groupBlock` Tiptap node in `editor.html`, built the way `columnBlock` is:

- `group: 'block'`, `content: 'block+'`, priority 210 so the passthrough catch-all (200) never claims it.
- Parses `div`, `section`, `header`, `footer`, `main`, `aside` and `article` elements with the class `wp-block-group`, and renders the same tag it parsed. This list of tags is defined once and shared with the fully-supported check.
- Registered through `withBlockAttrs`, so every attribute on the element (`class`, `style`, `id`) is carried and replayed on save, the way columns keep `is-not-stacked-on-mobile`.
- A `groupBlock` entry in `block-descriptors.js`: `blockName: 'core/group'`, `shape: 'container'`. `tagName` is derived from the element, the way heading `level` is: `div` writes nothing, any other tag writes `{"tagName":"section"}` and so on, and `tagName` is an owned attribute.
- The delimiter's other attributes (`layout`, `style`, `backgroundColor`, `metadata`, …) are carried as they are today for every modeled block.
- `wp-block-group` joins `QUILL_MODELED_BLOCK_CLASSES`.
- `groupBlock` joins `DELETABLE_BLOCKS` as `'group'`, so ✕ and ⌘⇧⌫ remove the whole Group.

Paste needs no change, but its behaviour changes as a by-product. A copy of a Group made inside Quill, and a `<div class="wp-block-group">` pasted from outside, now parse as a `groupBlock`. `cleanPastedHTML` keeps only `div` wrappers for modeled blocks (`keepsPastedDiv`), so a Group with any other tag pasted from outside still flattens to its contents, as it does today. Both cases are covered by paste tests.

### What the author sees

- A light outline around the Group, using the container style Details and Accordion already use (`.ProseMirror .wp-block-details` in `editor.html`), in both themes.
- A small label at the top left inside the outline, in the editor's sans-serif at a small size and a secondary colour, not monospaced. It names the Group the way Gutenberg does:
  - the block's custom name (`metadata.name`) if it has one, otherwise
  - **Row** for `layout.type` `flex` with no vertical orientation,
  - **Stack** for `flex` with `orientation: "vertical"`,
  - **Grid** for `layout.type` `grid`,
  - **Group** for everything else.
- The label is drawn by a node view (`dom` holds the label, `contentDOM` holds the children), so it is never part of the document or the saved HTML and the caret cannot enter it.
- Row, Stack and Grid lay out as a plain vertical stack. Their `layout` is saved unchanged.
- No colours, padding or background from the Group are drawn in the editor.
- Editing inside works like Columns: Enter on an empty last line moves the caret out of the Group, and ⌘Z undoes any edit. No toolbar controls are added beyond delete.

## 2a. Clearer locked cards

This applies to every locked card: top-level unsupported cards (`unsupportedWrapper`) and nested catch-all cards (`parsePassthroughBlock`).

### Label

If the block's delimiter has a non-empty string `metadata.name`, the label is that name. Otherwise it is the block type, as today (`passthroughLabelFromBlockName` / `passthroughLabelFromClass`).

### Preview

The preview line shows the block's visible text instead of its markup:

- The source is parsed into `inertDocument()`, never the live page (see "Post markup is parsed only into `inertDocument()`" in `docs/gotchas.md`).
- Block comments and the contents of `script`, `style`, `template` and `noscript` are dropped.
- Text from separate block-level elements is joined with " · ", so a heading and a paragraph read "Become a member · Join today". Inline formatting does not split text.
- Whitespace is collapsed and the result is cut at 120 characters with "…", as today.
- A block with no text, such as a Spacer, shows its label and hint only, with no preview line.
- A Custom HTML card (`customHTMLBlock`) keeps today's markup preview, because its markup is its content.
- The preview is set with `textContent`, as today.

## 2b. Readable synced patterns

Applies to top-level cards whose source is one `core/block` block. A synced pattern nested in a container is outside this design: inside a Group it locks the Group, and inside Columns it follows today's path.

### What the author sees

The card's hint line reads "Shared across posts · " followed by an **Edit in WordPress** button, which opens the pattern in the browser. The label and preview depend on the fetch:

| State | Label | Preview | Edit button |
|---|---|---|---|
| Loading | Synced pattern | none | shown |
| Loaded | Synced pattern: {title} | the pattern's text, as in 2a | shown |
| Loaded, empty title | Synced pattern #{ref} | the pattern's text | shown |
| Not found (404 or 410), or in the trash | Synced pattern #{ref} (not found) | none | hidden |
| Any other failure, or offline | Synced pattern #{ref} | none | shown |

The card stays locked, and the post still saves the original `<!-- wp:block … /-->` line byte for byte.

### How it works

The flow follows `requestMediaSizes` / `window.setMediaSizes`.

**Editor → Swift.** After `window.setContent` and after `_exitCodeView`'s user-edited branch, the editor collects the `ref` of every top-level `core/block` card, removes duplicates, and posts `requestSyncedPatterns({ generation, refs: [123, 456] })`. `generation` is a counter the editor increments on every load, so a result from an earlier load can be recognised and dropped. Nothing is posted when there are none.

**Swift.** `EditorCoordinator` handles `requestSyncedPatterns` and calls a new `onRequestSyncedPattern: ((Int) async -> SyncedPatternResult)?` closure on `EditorView` once per ref, the way `onRequestMediaSizes` is wired. `PostEditorView` implements it with a new `WordPressClient.fetchSyncedPattern(id:)`:

- `GET /wp/v2/blocks/{id}?context=edit&_fields=id,status,title,content`, decoding `status`, `title.raw` and `content.raw`.
- A pattern with status `trash` counts as not found. An account that can edit it still gets it back from the REST API, but WordPress renders nothing for it.
- `requestSyncedPatterns` and `openSyncedPattern` are added to the handler list in `App/FixtureCheck.swift`.

**Swift → editor.** `window.setSyncedPattern(generation, ref, result)`, echoing the request's generation, where `result` is `{ title, content }`, `{ notFound: true }` or `{ failed: true }`.

**Editor.** Results go into a `Map` keyed by ref, held outside the ProseMirror document. Each synced-pattern node view registers itself on creation and unregisters on destroy; `setSyncedPattern` updates the DOM of every registered view with that ref. Because the document is never touched, a result never marks the post edited, adds an undo step or changes what is saved. A result whose generation is not the current one is ignored, so a late result for post A cannot overwrite post B's card even when both use the same pattern. A ref the editor no longer holds is also ignored. The map is cleared on every load.

**The button** posts `openSyncedPattern({ ref })`. Swift builds `{site}/wp-admin/post.php?post={ref}&action=edit`, which opens the pattern in the block editor on both block and classic themes, and opens it only if it passes `EditorCoordinator.isAllowedExternalURL`. The editor never holds the URL, so the button works before the fetch finishes.

The editor's existing push deduplication (`EditorPushState`) skips `setContent` when the next post's HTML and footnotes are identical to the current one. The cards then keep their data, which belongs to the same refs. This is accepted rather than worked around.

## Testing

### Groups

- Round-trip fixtures for each tag, for Group, Row, Stack and Grid, with and without colours, padding, border and a custom name, and for a Group nested in a Group and in a Column. Each is checked unedited (byte for byte) and after an edit inside it.
- Every saved Group from those fixtures passes WordPress's own block validator (`Scripts/wp-validator.js`).
- A Group holding each kind of unsupported child (Spacer, Cover, shortcode, Custom HTML, synced pattern, a third-party block, a self-closing dynamic block) stays one locked card and saves back byte for byte.
- An old `wp-block-group__inner-container` Group, a `nav` Group, a Group holding a markup-less modeled block, and a Group with stray text or elements inside its wrapper all stay locked.
- Columns containing a failing Group is locked whole and saves back byte for byte.
- The block-risk banner reports nothing for a Group that opens, before and after an edit.
- The label reads the custom name, Row, Stack, Grid or Group as specified, and never appears in `getContent()`.
- Enter on an empty last line inside a Group moves the caret out; ✕ removes the Group.
- Pasting Quill's own copy of a Group yields a `groupBlock`.
- `--check-fixtures` in real WebKit gets a Group fixture, and passes.

### Locked cards

- Label uses `metadata.name` for top-level and nested cards, and falls back to the block type.
- Preview shows joined text for a Cover and a Media & Text fixture, shows nothing for a Spacer, and keeps markup for Custom HTML.
- Text inside `script` and `style` never reaches the preview.

### Synced patterns

- JS: `requestSyncedPatterns` is posted once per load with deduplicated refs, and not at all without synced patterns. Each result state renders the label, preview and button in the table above. A result changes neither `getContent()` nor the edited state, and adds no undo step. A late result for a ref no longer present is ignored, and a result from an earlier load is ignored even when the new post uses the same pattern. The button works while the fetch is pending.
- Real WebKit: FixtureCheck's script-handler probes also pass each `script-sinks/` source through `setSyncedPattern` as fetched title and content, and fail if a handler runs.
- Swift: `fetchSyncedPattern(id:)` builds the request above and decodes `status`, `title.raw` and `content.raw`. A 404 or 410, or status `trash`, maps to not found. The edit URL is built correctly for a site at a domain root and in a subdirectory.
- Manual: a step in `docs/testing-plan.md` §7 inserts a synced pattern on the local Studio site, opens the post in Quill, checks the title and preview, opens the edit link, then trashes the pattern and permanently deletes it, checking "(not found)" after each.

## Docs to update

- `docs/block-model.md`: Group as a modeled container and the fully-supported rule; the card label and preview rules; synced-pattern cards.
- `Sources/QuillKit/Resources/CLAUDE.md`: the per-element output table gains `core/group`.
- `site/docs.html`: which Groups are editable, and what synced-pattern cards show.
- `docs/testing-plan.md`: new tests and counts.
- `CLAUDE.md`: test counts.
