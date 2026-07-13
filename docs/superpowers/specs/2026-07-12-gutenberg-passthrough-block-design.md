# Generic Gutenberg Block Passthrough — Design Spec

**Date:** 2026-07-12
**Status:** Approved, not yet implemented

## Problem

Quill's Tiptap schema only models a fixed set of block types (heading, paragraph, lists, blockquote, table, image, embed, gallery, footnotes, code, hr). Any other Gutenberg block — Accordion, Columns, Group, Buttons, Media & Text, Cover, third-party plugin blocks, etc. — has no matching parse rule. When such content is loaded (or pasted into code view and the user exits back to visual mode), ProseMirror's default HTML parsing silently drops the unrecognized wrapper elements and merges their text content upward into whatever nearby element it does recognize.

Confirmed via reproduction: pasting a real WordPress core Accordion block's markup (`div.wp-block-accordion` containing `wp-block-accordion-item` > `h3`/`button` heading + `wp-block-accordion-panel`) into code view and exiting collapses two full accordion sections down to a single flattened `<h3>Features+</h3><ul>...</ul>` — every `<div>` wrapper, the `<button>`, and all `data-wp-*` Interactivity API attributes are lost, with both sections' content merged into one continuous run.

This was previously flagged as deferred work: `docs/future-architecture.md`'s "Approach E" describes a `GutenbergPassthrough` node keyed on `<!-- wp:name -->` comment pairs. That alone would not have caught the reproduction case above, since the pasted markup contains no such comments (it's the block's class-only rendered form, not comment-delimited `post_content` source).

## Approach

A new atomic Tiptap node, `GutenbergPassthrough`, modeled on `GalleryBlock`'s verbatim-preservation pattern (an unmodeled node is captured whole and re-emitted byte-for-byte on save) rather than `SnippetBlock`'s comment-marker pattern (no synthetic markers are needed — the block already self-identifies via its own `wp-block-*` class).

This is deliberately **read-only passthrough, not editing support**: the goal is to stop unsupported blocks from being silently destroyed on visual edits elsewhere in the post, not to make their internals editable in the visual editor. Editing the block's own content still requires code view.

## Detection

A catch-all parse rule at the **lowest priority** of any block-level rule in the schema (`priority: 1`, versus Tiptap's default extension priority of 100 and the footnote nodes' elevated 110 — confirmed from `tiptap-bundle.js`'s extension-sort implementation, `priority || 100`), matching any non-`<figure>` element whose `class` contains a `wp-block-` prefixed token: `tag: '[class*="wp-block-"]:not(figure)'`. Tiptap/ProseMirror tries parse rules in priority order and stops at the first match, so every existing specific rule (`figure.wp-block-image`, `figure.wp-block-gallery`, `figure.wp-block-embed`, bare-tag rules for headings/lists/blockquote/code/hr, `ol.wp-block-footnotes`) keeps claiming its own elements first, unchanged from today. `GutenbergPassthrough` only ever catches what nothing else claims.

**Why `<figure>` is excluded entirely:** traced precedence confirms `figure.wp-block-table` (the table wrapper) has **no dedicated parse rule today** — Tiptap's stock Table extension only matches the bare `<table>` tag, so the figure wrapper is currently passed through transparently by ProseMirror's default "no rule matched, recurse into children" behavior. A class-based catch-all with no exclusion would newly claim that figure as an opaque blob, silently breaking existing table loading. Excluding all `<figure>` elements sidesteps this for every currently-modeled figure-wrapped block (image, gallery, embed, table) in one rule, at the cost of not yet protecting a hypothetical figure-wrapped unsupported block (e.g. Pullquote) — acceptable for v1 per the same "simpler, likely sufficient" reasoning as the no-recursion decision below, and noted under Out of Scope.

**Atomicity:** the node has no content schema, so ProseMirror never descends into its children looking for further matches. Nested `wp-block-*`-classed elements inside a matched block (e.g. `wp-block-accordion-item`, `wp-block-accordion-heading`) are simply part of the captured `outerHTML`, not separately parsed — the same way `GalleryBlock` already swallows nested `<img>`s without turning them into `ResizableImage` nodes.

**Comment adjacency (upgrade over the original Approach E idea):** `getAttrs` also checks for immediately-adjacent `<!-- wp:name -->` / `<!-- /wp:name -->` comment siblings around the matched element (skipping whitespace-only text-node siblings, since real Gutenberg source has a newline between a comment and its element):
- **Found:** these are real block-editor `post_content` source. `blockName` and `attrsJSON` capture the comment's block name and raw JSON-attrs text verbatim; `blockLabel` is derived from the block name (e.g. `wp:accordion` → "Accordion"). Preserving the comment's exact name/attrs text matters because WordPress's own block editor uses them to recognize the content as a real, editable block — dropping them would silently degrade the content to anonymous HTML from Gutenberg's perspective if the post is ever reopened there.
- **Not found:** this is class-only markup (e.g. copied from a live rendered page, as in the reproduction case). `blockName`/`attrsJSON` stay `null`; `blockLabel` is derived from the CSS class instead (`wp-block-accordion` → strip prefix, split on `-`, title-case → "Accordion").

`sourceHTML` always captures just the element's own `outerHTML` — never the surrounding comments. Nothing is fabricated in either direction — if the pasted markup has no comments, `blockName`/`attrsJSON` stay null and none are added on save; the node just records whatever was actually there.

## Data model (node attrs)

`GutenbergPassthrough` (atomic Tiptap node):

- `blockLabel`: string — display name for the card, derived at parse time (see Detection above)
- `blockName`: string | null — the block name from an adjacent `<!-- wp:name -->` comment, if one was present at parse time
- `attrsJSON`: string | null — the raw JSON-attrs text from that comment, verbatim (not reparsed/re-stringified, to avoid reformatting drift), if present
- `sourceHTML`: string — the matched element's own `outerHTML`, verbatim (comments never included here)

## Round-trip

**Load** (`setContent` — initial post load and code-view exit): the parse rule fires during Tiptap's HTML→ProseMirror conversion, as described under Detection.

**Save** (`toWordPressHTML` — every debounced save and explicit save): mirrors how `GalleryBlock` already regenerates its `wp:gallery`/`wp:image` comments fresh from structured attrs rather than trying to preserve original comment text. `renderHTML` re-emits `sourceHTML` for the element itself, and — only when `blockName` is set — adds temporary `data-quill-passthrough-name`/`data-quill-passthrough-attrs` attributes to it (the same "smuggle node attrs through the HTML string" technique `data-media-id` already uses for image IDs). A new `toWordPressHTML` pass finds elements carrying `data-quill-passthrough-name`, wraps them in freshly-built `<!-- wp:{name} {attrs} -->` / `<!-- /wp:{name} -->` comments via DOM sibling insertion (identical mechanism to the existing embed/gallery comment-wrapping code), and strips the temporary attributes so they never appear in the saved HTML. When `blockName` is null (no original comments), this pass simply doesn't apply — the element saves as-is, no comments added.

**Surviving edits elsewhere in the doc:** because it's a real node in the ProseMirror schema (not raw unparsed text riding on the `_rawHTML` safety net), it's included in `editor.getHTML()`'s output regardless of what else changed in the post — the same guarantee images, embeds, galleries, and snippets already have today.

**Code view:** entering code view shows the raw `sourceHTML` inline via the existing `formatHTML` pretty-printer, which already preserves HTML comment nodes (nodeType 8) verbatim — no changes needed there. Editing inside it and exiting code view re-parses through the same rule, producing a fresh node with updated `sourceHTML`.

## Editor card UI

A static, non-editable `NodeView`, visually modeled on `SnippetBlock`'s card (the closest existing "opaque, unsupported content" precedent) — same card border/icon/label visual language as the embed and gallery cards. Shows only:

> **{blockLabel}**
> *Unsupported block — edit via Code View (`</>`)*

No content preview, no rendered attempt. Selecting, moving, and deleting the card works like any other atomic block (same NodeView selection pattern as `EmbedBlock`/`GalleryBlock`). It cannot be typed into — there is no in-card edit affordance, only the hint pointing at code view.

## Testing

**JS transforms** (additions to `Scripts/test-editor.js`):
- Class-only match (no comments) → correct `blockLabel`, `blockName`/`attrsJSON` both null, `sourceHTML` = element only
- Comment-wrapped match → correct `blockLabel` derived from the comment's block name, `blockName`/`attrsJSON` populated verbatim from the comment
- `toWordPressHTML`'s comment-regeneration pass: an element carrying `data-quill-passthrough-name`/`data-quill-passthrough-attrs` gets wrapped in matching fresh `<!-- wp:name {attrs} -->`/`<!-- /wp:name -->` comments, with the temporary attributes stripped from the output

**JS editor keyboard** (new suite, `Scripts/test-editor-passthrough.js`, following the `test-editor-gallery.js` real-editor-in-jsdom pattern — parse/render for a custom node can't be exercised through the pure `editor-transforms.js` helpers alone):
- Load the reproduction accordion HTML from this investigation, make an unrelated edit elsewhere in the document (e.g. type in a paragraph), call `getContent()`, and assert the accordion's essential markup — classes, `data-wp-*` attributes, nested structure — is unchanged. This is the specific round-trip guarantee this feature exists to provide.
- Specificity guards: real `figure.wp-block-gallery` / `figure.wp-block-image` / `figure.wp-block-table > table` / `figure.wp-block-embed` markup still parses into their own existing node types (`galleryBlock`/`image`/`table`/`embedBlock`), not `gutenbergPassthrough` — the regression this rule's `:not(figure)` exclusion exists to prevent.

**No Swift tests needed** — this is purely a Tiptap/JS-side feature; no new Swift models or storage.

## Out of scope

- Editing block internals visually (heading text, panel content, etc.) — code view only, as decided
- Recursing into nested foreign blocks to convert them individually (e.g. a Columns block containing an unsupported block) — the whole matched subtree is captured as one opaque unit, consistent with `future-architecture.md`'s original Approach E note that this is "simpler, likely sufficient"
- Figure-wrapped unsupported blocks (e.g. a hypothetical Pullquote-style block) — excluded by the `:not(figure)` precedence rule (see Detection); these keep today's existing transparent-recursion behavior rather than gaining passthrough protection
- A toolbar button to *insert* one of these manually — it only ever arises from parsing existing content, never authored fresh in Quill (unlike Snippets)
- Synthesizing `<!-- wp:name -->` comments for content that didn't originally have them
- Rendering a live/approximate preview of the block's actual appearance
