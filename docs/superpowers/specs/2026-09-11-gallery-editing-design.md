# Editable Galleries — Design Spec

**Date:** 2026-09-11, revised 2026-09-28
**Status:** Implemented 2026-09-28
**Plan:** [2026-09-28-gallery-editing.md](../plans/2026-09-28-gallery-editing.md)
**Issue:** cpoteet/Quill#5

## Problem

A gallery in the visual editor cannot be changed. To reorder images, swap one out, fix a caption or change the column count, the user deletes the gallery and rebuilds it in `GallerySheet`.

The feature: open an existing gallery in `GallerySheet`, already filled in, and have **Update Gallery** replace it in place. The gallery stays an atomic card in the editor; nothing is edited inline.

## Where things stand (after 1388257)

`galleryBlock` has two render paths:

- **Sheet-inserted** (`sourceHTML: null`): `renderHTML` builds the figure from `images[]` (`id`, `url`, `fullUrl`, `alt`, `caption`), `columns`, `cropped`, `linkTo`, `sizeSlug`.
- **Loaded from a post**: `sourceHTML` holds the original figure, and `renderHTML` re-emits it unchanged.

On save, the gallery pass in `toWordPressHTML` rebuilds every `wp:gallery`/`wp:image` comment. Since 1388257 it does so faithfully for a loaded gallery: each nested image's original comment rides on its figure as `data-quill-block-attrs`, goes through `imageBlockAttrs` like a standalone image, and the gallery keeps the `linkTo`/`sizeSlug` WordPress wrote. The gallery's own comment is carried on the node's `blockAttrs`.

Editing means clearing `sourceHTML` and rendering from the node, and the node holds much less than a real gallery does.

## What rebuilding from the node would lose today

| Lost | Where it lives | Why |
|---|---|---|
| Per-image size | `size-*` class on each image figure | `images[]` has no size; `parseHTML` takes one `sizeSlug` from the first image |
| Per-image link | `<a href>` around each image, `linkDestination` in its comment | `linkTo` is gallery-wide and only knows `none` / `media`; `parseHTML` reads no `href` |
| Per-image comment attributes | each image's `wp:image` comment | nothing on `images[]` holds them |
| Theme classes on an image, e.g. `image-plain` | the image figure's `class` | `parseHTML` reads no classes. Core recovers these from the HTML, so they are often not in the comment at all |
| Formatted captions | `figcaption` markup | `parseHTML` reads `textContent` |
| The gallery caption | `figcaption.blocks-gallery-caption` | not parsed, not rendered |
| Gallery alignment | `align` in the gallery's `blockAttrs` | `renderHTML` draws no `align*` class |
| The full-size link target | `href` of each image's `<a>` | `parseHTML` never sets `fullUrl` |

## Decisions

Made with the user on 2026-09-28.

1. **Opening.** Double-click the card, or press Return while it is selected. The card's hint line also shows an **Edit** link. A single click still only selects the card.
2. **Formatted captions.** A caption keeps its original markup unless the user changes its text in the sheet. A changed caption is saved as plain text.
3. **Mixed sizes.** When a gallery's images have different sizes, the Size menu shows **Mixed** and each image keeps its own size. Picking a size applies it to every image. An image added while the menu shows Mixed uses Large.
4. **Links.** The Link To menu keeps None and Full Image. When a gallery's links are anything else — attachment pages, per-image custom links, or a mix — the menu also shows **Keep Current Links**, selected by default, and every existing link is left exactly as it was. Picking None or Full Image replaces all of them. An image added under Keep Current Links follows the gallery's `linkTo`: attachment page (`WPMedia.link`) for `attachment`, the full-size file for `media`, no link otherwise.

## Approach

**Close the gap between parse and render first, then wire the sheet.** Wiring the sheet first ships the losses above.

### 1. The node holds everything it renders

Each `images[]` entry gains:

| Key | Read on parse from | Rendered as |
|---|---|---|
| `sizeSlug` | the image figure's `size-*` class | that class |
| `href` | the `<a>` around the `<img>`, or `null` | the `<a>` |
| `blockAttrs` | the image's preceding `wp:image` comment, as a JSON string, or `null` | `data-quill-block-attrs` on the image figure (the save pass already reads it) |
| `extraClasses` | the image figure's classes except `wp-block-image` and `size-*` | appended to the figure's class list, in source order |
| `captionHTML` | the `figcaption`'s inner HTML, or `null` | the caption, when set |

`caption` stays the caption's plain text, for the sheet. The gallery gains `captionHTML` (the gallery caption's inner HTML), and `renderHTML` draws `align{value}` from `blockAttrs.align`.

The gallery-wide `sizeSlug` and `linkTo` attributes stay for the sheet's insert path, but rendering reads the per-image values when present.

**Invariant, and the central test:** for every gallery fixture, loading it, clearing `sourceHTML` and saving must reproduce it. `settings-gallery.html` is canonical core output, so it must come back byte for byte. `gallery-block.html` was written by an older Quill with different indentation, so it must come back with the same comment attributes (`commentAttributes`) and no new validator findings.

**Caption markup is a script sink.** Loaded caption HTML reaches `renderHTML`, whose output is serialized by the live document. Parse it through an inert `<template>` element, never `innerHTML` on an element owned by the page, and test that an `<img onerror>` in a loaded caption never runs. This is the same boundary `docs/editor-gotchas.md` describes for the attribute carrier.

### 2. Replace in place

- `GalleryNodeView` handles `dblclick`, Return on a selected card, and a click on its **Edit** link, all by calling `window.editGallery(pos)`.
- `window.editGallery(pos)` remembers `{ pos, node }` and posts the existing `insertGallery` message with body `{ edit: <the node's attrs> }`. The toolbar button's body stays `{}`, which means insert. Reusing the message avoids registering a new handler in `EditorView` and `FixtureCheck`.
- `window.insertGallery(json)` with `payload.replace === true` replaces the remembered node — one transaction, so one undo step — only if `editor.state.doc.nodeAt(pos)` is still that exact node. Otherwise it does nothing: the post changed while the sheet was open, and inserting a copy would be worse.
- The replaced node has `sourceHTML: null`. Its `blockAttrs` loses `ids` and `sizeSlug`, and loses `linkTo` when the user picked None or Full Image. Under those two choices each image's `blockAttrs` also loses `linkDestination`, or the save pass would keep the old destination.

### 3. The sheet in edit mode

- `GallerySheet` gains an optional `editing: GalleryEdit` input. Title **Edit Gallery**, primary button **Update Gallery**.
- It fetches every image's `WPMedia` in one request: `fetchMedia(include:)` sends `include=1,2,3` and `per_page` equal to the count (WordPress caps it at 100). An image with no id, or one the request did not return, becomes a selection with no `WPMedia`: it keeps its URL, shows its own thumbnail, and cannot change size.
- A selection remembers the image it came from, so `PostEditorView` can send back every key the sheet does not edit (`href`, `blockAttrs`, `extraClasses`, and `captionHTML` when the caption text is unchanged).

## Out of scope

- Editing captions with formatting, per-image size controls, per-image link controls.
- Standalone images, which have the same kind of gaps.

## Testing

- `test-editor-gallery.js`: the rebuild invariant on both gallery fixtures; each new `images[]` key parsed and rendered; the caption script-sink test; `editGallery` posting the node's attrs; replace, stale-position no-op, single undo step, `blockAttrs` pruning.
- Swift: `fetchMedia(include:)` builds the right query; the payload builder keeps untouched keys, drops `captionHTML` for a changed caption, and applies Mixed and Keep Current Links as the Decisions describe.
- The real-WebKit fixture check, and a manual pass in the app on a new local draft.

## Rejected alternatives

- **Patch `sourceHTML` with string edits on save.** The regex-over-HTML approach behind three past silent data-loss bugs.
- **Make the gallery non-atomic and edit inline.** Touches the ProseMirror paths with the worst regression history, and gives no access to the gallery-wide settings.
- **Formatting controls or per-image size and link controls in the sheet.** Declined on 2026-09-28 in favour of leaving what the sheet cannot show untouched.
