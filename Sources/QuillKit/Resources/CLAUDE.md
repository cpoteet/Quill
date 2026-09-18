# Editor resources (editor.html / editor-transforms.js / tiptap-bundle.js)

Implementation gotchas specific to this directory, split out from the project root `CLAUDE.md` (2026-07-11) to keep the root file lazy-loaded. See the root `CLAUDE.md` for architecture, build/test commands, and cross-cutting conventions.

## Gutenberg HTML output reference

### What each element currently outputs (as of 2026-09-18)

| Tiptap internal | `toWordPressHTML()` output |
|---|---|
| `<h1>`–`<h6>` | `+ class="wp-block-heading"` |
| `<ul>` | `+ class="wp-block-list"`; a leading `<p>` inside `<li>` unwrapped to a text node when it is the item's only child **or** when every following sibling is a nested `<ul>`/`<ol>` (matching Gutenberg's `<li>text<ul>…`); items with a second paragraph are left alone |
| `<ol>` | `+ class="wp-block-list"`; a `start` other than 1 and `reversed` are written to the delimiter as well as the markup; a leading `<p>` inside `<li>` unwrapped to a text node when it is the item's only child **or** when every following sibling is a nested `<ul>`/`<ol>` (matching Gutenberg's `<li>text<ul>…`); items with a second paragraph are left alone |
| `<blockquote>` | `+ class="wp-block-quote"` |
| `<pre>` | `+ class="wp-block-code"`; a class on the inner `<code>` (Claude's `language-python`) moves to the `<pre>`, since core/code's `save()` draws none there |
| Any modeled block's root `id` / non-generated class | written to the delimiter as `anchor` / `className` unless the carrier already has that key (`supportAttrs`); "generated" is `GENERATED_CLASS` — `wp-block-*`, `has-*`, `is-*` except `is-style-*`, `are-*`, alignment. Four blocks without core's anchor support are marked `noAnchor` in `block-descriptors.js` |
| `<hr>` | `+ class="wp-block-separator has-alpha-channel-opacity"`, self-closed as `<hr/>` the way core writes it (as is `<img/>`; `<br>` is left alone) |
| `<figure><img class="alignXXX"><figcaption>…</figcaption></figure>` (Tiptap `renderHTML` output; a classic `<figure>` with no `wp-block-*` class and an `<img>` child parses the same way, caption included) | figure gets `class="wp-block-image alignXXX"`; alignment class moved from `img` to `figure`; `class="wp-image-{id}"` added to `img` when `data-media-id` is set, and the `data-media-id` attr then removed (editor-internal; `mediaId`'s parseHTML reads the id back off that class on load); the whole figure wrapped in a `<!-- wp:image {id,sizeSlug,align,linkDestination} -->` pair, each key omitted when not determinable — without it WordPress parses the figure as classic HTML, not a core/image block. Gallery-nested images are skipped here and wrapped by the gallery pass instead; non-empty `<figcaption>` gets `class="wp-element-caption"`; empty figcaption removed; a `role` on the source `<img>` (WP 7.1 emits `role="none"` for "mark as decorative") round-trips via the `imgRole` attr and adds `isDecorative` to the comment attrs; dimensions are rebuilt into core's shape — the `<img>`'s `width`/`height` attributes become `style="width:Npx;height:Npx"` (`height:auto` when only a width is known), the figure gains `is-resized`, and both land in the comment attrs as px strings |
| `<table>` | Tiptap artifacts stripped (`style`, `<colgroup>`, default `colspan="1"`/`rowspan="1"`, single-`<p>` cell unwrap); wrapped in `<figure class="wp-block-table">`; a classic `<caption>` parses into the caption attribute (and is ignored as content) so it saves as the figure's `<figcaption>`; first all-`<th>` row promoted from `<tbody>` to `<thead>` |
| `<figure class="wp-block-embed">` (EmbedBlock node) | passes through unchanged — classes emitted by `renderHTML` via `embedClassFor()` |
| Footnote marker `<sup data-fn class="fn">` | anchor text renumbered 1..n in document order by `toWordPressHTML` |
| `<ol class="wp-block-footnotes">` | excluded from `wp-block-list`; passes through unchanged |
| `<figure class="wp-block-gallery">` (galleryBlock node, atomic) | wrapped with `<!-- wp:gallery {ids,columns,linkTo[,imageCrop]} -->`/`<!-- wp:image {[id,]sizeSlug,linkDestination} -->` comments; existing galleries round-trip via a verbatim `sourceHTML` attr (captures anything the structured attrs don't model), not reconstructed — same pattern as `EmbedBlock`. Per-image `caption` **is** modeled: emitted on the reconstruction path as `figcaption.wp-element-caption` via `textContent` (never `innerHTML` — the text comes straight from a `TextField`), omitted when empty, and read back on parse — unlike `sizeSlug`, see its known-edge-case bullet below |
| Any top-level block Quill has no node for (`blockNeedsWrapping`) | wrapped on load into `div.wp-block-quill-unsupported` holding its exact source slice, and swapped back for those bytes verbatim on save. This is the byte-exact path and the one to reason about first |
| Any other `wp-block-*` classed element with no dedicated parse rule, **nested inside a modeled container** — including `<figure>`s outside `QUILL_MODELED_FIGURE_CLASSES` (audio, video, pullquote, WP 7.1's playlist) (gutenbergPassthrough node, atomic) | preserved via a verbatim `sourceHTML` attr — never reconstructed, never descended into. Not byte-exact: Tiptap's `elementFromString` strips inter-element whitespace before any parse rule sees it, so newlines between nested blocks are lost. Everything else about it *is* verbatim — its markup is stashed behind a nonce alongside the unsupported wrappers, so the style-compaction and void-element passes never reach it. If adjacent `<!-- wp:name -->`/`<!-- /wp:name -->` comments were present on load, fresh ones are regenerated around it on save; class-only markup (no original comments) gets none added |
| Bold, italic, strike, inline code, links, paragraphs | unchanged — already match Gutenberg |



## Attribute precedence

Six things can put an attribute on a saved element. When two disagree, this is the
order. Every function below has a one-line comment pointing here rather than
restating it.

**On parse** (most authoritative first):

1. The block comment — `blockCommentAttr(el, key)`. Gutenberg's own source of truth.
   A `sourced: true` registry setting skips this step: WordPress reads those back out
   of the markup, so the comment never holds them.
2. The markup — `readSettingFromElement`, a node's own `parseHTML`, the `rawAttrs`
   snapshot.
3. The attribute's declared `default`.

**On render** (first writer wins; later ones only fill gaps):

1. The node's own `renderHTML` — modelled attributes, and the classes it computes.
2. `withBlockSettings` — the registry's generated attributes and classes.
3. `withRawAttrs` — the snapshot, replayed in the source's own attribute order,
   skipping any name in `RAW_ATTRS_MODELED` (the node draws it) and any class in
   `RAW_CLASS_OWNED` or matching a registry class pattern. A snapshot `style`
   becomes `data-quill-style` so ProseMirror never re-serializes it.
4. `replayChildAttrs` — the same rule again for each child element named in
   `RAW_CHILD_ATTRS`, whose modelled names are that entry's list plus the registry's
   `attr` settings targeting that tag.
5. `withBlockAttrs` — the carried comment JSON, with its `className` merged into the
   rendered class list.
6. `toWordPressHTML` — the last word on figure blocks, which it rebuilds outright.

**On the way out to the delimiter:** `overlayCarried` walks the carried keys in the
order WordPress wrote them, replacing an owned key that the node still computes,
dropping an owned key it no longer does, then appending genuinely new keys.
`descriptor.ownedAttrs` is what makes absence meaningful — without it, a setting the
user switched off is indistinguishable from a block that never had it.

`RAW_ATTRS_EXEMPT` means "this node rebuilds its own root element, so replay nothing
onto it" — its children are still replayed.


## Gotchas

**Full text of every entry below: `docs/editor-gotchas.md`.** Read the entry before changing the code it describes — most of these are silent failures. This one applies to almost any change in this directory, so it stays here in full:

- **Any new `toWordPressHTML` pass is a whole-tree `div.querySelectorAll(...)` and will reach into `gutenbergPassthrough` subtrees unless explicitly shielded** — `gutenbergPassthrough` elements are stashed out into placeholder divs at the very top of `toWordPressHTML` (before any transform runs) and only spliced back in — completely untouched — right before the final `wp:name` comment-regeneration pass, after every other pass (comment-strip, media-id class, image/heading/list/blockquote/cite/table/footnote/embed/gallery normalization) has already run. This is deliberately a *wide* shielding window, not scoped to just the comment-strip regex: an earlier implementation spliced passthrough elements back in immediately after the comment-strip alone, which left them exposed to the later heading-class/empty-cite-removal/empty-figcaption-removal passes — a nested `<h3>` silently gained `wp-block-heading`, and intentionally-empty `<cite>`/`<figcaption>` elements were deleted, even though the whole point of passthrough is byte-for-byte preservation. If you add a new unconditional `div.querySelectorAll(...)` pass to `toWordPressHTML`, it automatically inherits this protection as long as it's placed between the stash and the splice-back — do not add passes after the splice-back point without auditing whether they should reach into passthrough content.

- Every attribute the carrier snapshots reaches the live contenteditable, so the snapshot is a security boundary
- The placeholder `toWordPressHTML` leaves where a preserved block was must be unguessable
- The trailing-paragraph strip must name the shapes it follows, or it eats a real block
- `/^\s+/` in JavaScript matches U+00A0, so a whitespace strip deletes deliberate `&nbsp;` indentation
- A passthrough card is only byte-for-byte if its markup is stashed out of the way, not just shielded from the comment-strip regex
- A `<li>` holding two or more paragraphs is left alone on purpose, even though core's rich-text `<li>` will flag it
- ProseMirror re-serializes any `style` it renders, so a style Quill did not author must never reach it
- Delimiter attributes must go through `serializeAttributes`, never `JSON.stringify`
- A regex over the final HTML string must treat `<` and `>` inside attribute values as data
- A node with its own node view never sees `renderHTML`, so a block setting can save correctly and still draw nothing
- A decoration that follows the caret cannot double as the display of a stored setting
- A leaf block in `DELETABLE_BLOCKS` needs `_deletableTarget`, not the ancestor walk
- Every `#toolbar-row2` group must carry `class="tb-group"`, and an icon-only group `tb-group-icons` too
- A widget decoration next to the caret makes WebKit drop every keystroke, and jsdom/Chromium never show it
- An empty title inside `.wp-block-accordion-heading__toggle` is zero-width, so a click can never seat a caret in it
- Gutenberg invalidates a block when the stored HTML carries anything its `save()` would not regenerate
- Known unfixed edge case: non-dimension `style` properties on an image are dropped
- Check Gutenberg's own `save.jsx` before treating a block attribute as editor-only
- Comment-only block attributes ride through Tiptap on `data-quill-block-attrs`, and `descriptor.ownedAttrs` is what lets a node turn one off
- `gutenbergPassthrough` must opt out of modeled figures by class, not by excluding `<figure>` wholesale
- A `describe()` whose first test calls `setContent` right after a block that leaves the doc as a single atom node needs a throwaway `setContent('<p></p>', false)` in `before()`
- ProseMirror's two clipboard branches have separate hooks, and `handlePaste` runs *after* the parse, not before
- Anything that inserts generated HTML must strip inter-block whitespace text nodes AND pass `parseOptions: { preserveWhitespace: false }`
- `formatHTML`'s `BLOCK` set changes affect ALL existing content wrapped in that tag, not just the new case motivating the change
- Gap-cursor styling, not doc-model surgery, for the caret next to atomic block nodes
- `marked` is a second, separate IIFE bundle — kept out of `bundle-tiptap.sh` so regenerating it can't drift the editor onto a newer Tiptap
- Tiptap is bundled locally as IIFE — `type="module"`/ES `import` silently fails under `file://` in WKWebView and `editorReady` never fires
- Known unfixed edge case: `galleryBlock.sizeSlug` is per-gallery, not per-image
- Known unfixed edge case: image link toggle collapses all WordPress link destinations to "media"
- Known unfixed edge case: `AIResultPanel`/`beginAIOperation` reentrancy
- Cmd+click opens links, and fragment-only `href`s must be skipped or footnote markers resolve to a blocked `file://` URL
- `ResizableImage` must import `Image` as a named import, or the default export shadows the name
- `ImageNodeView` is a plain JS class, not a React/Svelte component
- `.image-frame` wraps only the `<img>` and handles, so handles align to the image rather than to the wrapper's caption height
- Non-leaf NodeView + NodeSelection: must intercept `stopEvent`
- `window.insertImage` must move the cursor off the caption after `setImage`
- `ResizableImage` has `content: 'inline*'` for captions
- Tiptap node attrs: a per-attribute `parseHTML` stub must return `null`/`undefined` to be a true no-op, not a literal default value
- `ResizableImage`'s per-attribute `parseHTML` can double as a fallback for parse rules with no `getAttrs` of their own
- `<a>` wrapper detection for image links must check for a non-empty `href`, not just `tagName === 'A'`
- Use `state.tr.setNodeMarkup(pos, null, attrs)` to commit image attribute changes
- `#image-toolbar` is `position: fixed`, not an absolute child of the NodeView
- The active `ImageNodeView` lives on the toolbar element as `tb._activeNodeView` — always null-check it, `_hideImageToolbar()` clears it
- The 80 ms delay in `deselectNode()` is what lets a toolbar input take focus before the toolbar hides itself
- The image Reset button restores from the Full-size button's `_sizeData`, and must degrade to clearing constraints when sizes never loaded
- Per-image toolbar controls gated on `requestMediaSizes` data must degrade, not disappear, for images with no `mediaId`
- AI buttons are in the Tiptap toolbar, not the SwiftUI toolbar
- `showAIResult` inserts at block-node boundaries, not text positions
- AI operations detect list/table context
- Strip inter-block whitespace text nodes before inserting AI HTML
- Embeds render as static cards via `EmbedNodeView`, whose `renderHTML` returns a DOM node rather than an array spec
- `FootnotesList`/`FootnoteItem`/`FootnoteMarker` need `priority: 110` to beat the generic `ol`/`li` parse rules — do not remove it
- Footnote numbers in the editor come from CSS counters
- `FootnoteSync`'s `appendTransaction` rebuilds the list children, so deleting a marker deletes its entry and typed text by design
- The editor's footnote back-arrow is a NodeView artifact — it is in neither the ProseMirror doc nor the saved HTML, which has its own
- `_ancestorDepth($pos, typeName)` finds the nearest ancestor by node type name; the two cite paths use `_citeHostDepth($pos)` instead
- Blockquote's Enter must bail below its depth guard, or `tr.split` at depth > 1 corrupts tables and lists nested inside the quote
- Blockquote toggle-off strips cite before lifting
- The cite toggle serves blockquote *and* pullquote, though its group still carries the `blockquote-controls` id
- `DELETABLE_BLOCKS` is the single source for all three block-level gestures
- `ContainerExit` must keep `priority: 250`
- Esc reaches the editor keymap before the document-level listeners that close the menus
- A jsdom suite that dispatches into a container needs `editor.view.dom.blur()` in `before()`
- Image-caption Enter uses `handleKeyDown`, not `addKeyboardShortcuts`, so it fires before every keymap plugin
- `_fnPassthrough` allows Backspace/Delete through footnote keyboard guards
- Find & replace decorations use their own `PluginKey('findReplace')` and dispatch meta-only transactions, which do not re-fire `update`
- Stats freeze in code view
- `crypto.randomUUID()` is available in WKWebView on macOS 13+ even with `file://` URLs
- `updateToolbar()` caches its button references at init — never `document.querySelector` inside it, it runs on every keystroke
