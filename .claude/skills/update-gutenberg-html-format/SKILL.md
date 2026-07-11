---
name: update-gutenberg-html-format
description: Use when WordPress/Gutenberg changes the expected HTML format for a block element (headings, lists, images, tables, embeds, footnotes, galleries, etc.) and Quill's editor needs to match it — updating toWordPressHTML() or a Tiptap parseHTML() rule.
---

# Updating Gutenberg HTML compatibility

All WordPress/Gutenberg HTML compatibility lives in two files:

1. **`toWordPressHTML(html)`** in `Sources/QuillKit/Resources/editor-transforms.js` (line 16) — called on every save/content-change. Transforms Tiptap's internal HTML into Gutenberg-format HTML before sending to Swift.
2. **`ResizableImage.parseHTML()`** (~line 1079 in `Sources/QuillKit/Resources/editor.html`) — custom parse rule for `<figure class="wp-block-image">` that extracts image attrs (including alignment) from Gutenberg figure wrappers on load.

See `Sources/QuillKit/Resources/CLAUDE.md` for the current per-element output reference table.

## How to update when WordPress changes its HTML format

1. Check the new format by inspecting a post in a live WordPress site: open a post in the WordPress block editor, add the element in question, save, then view the post's source HTML (or fetch it via the REST API: `GET /wp-json/wp/v2/posts/{id}?context=edit` and look at `content.raw`).

2. Update `toWordPressHTML()` in `editor.html` to emit the new structure. All transforms are DOM operations (create element, add class, reparent) — no regex.

3. If WordPress also changes how it *stores* the format (what the API sends back on load), check whether Tiptap still parses it correctly by loading an existing post. If not, add or update a `parseHTML()` rule on the relevant Tiptap extension. For block elements wrapped in a `<figure>` (like images and tables), add a `getAttrs` rule that extracts the inner element's attrs.

4. Rebuild and test the round-trip: load a post with the affected element → verify it displays correctly in Quill → save → verify the API-stored HTML matches the new expected format.
