# Gallery Per-Image Alt Text & Captions — Design Spec

**Date:** 2026-08-13
**Status:** Approved, not yet implemented

## Problem

`GallerySheet` builds a WordPress gallery from selected media items, but exposes only gallery-wide settings: columns, crop, link-to, and size (`GallerySheet.swift:184-222`). There is no way to set per-image alt text or a per-image caption.

Alt text is half-supported today: `PostEditorView` already sends each image's `media.altText` in the insert payload (`PostEditorView.swift:185`) and `galleryBlock`'s reconstruction path writes it to the `<img alt>` (`editor.html:1731`). So a gallery inherits whatever alt the media library holds — but if that alt is wrong or missing, the sheet offers no way to fix it for this gallery.

Captions are entirely absent. `WPMedia` does not decode WordPress's `caption` field at all, the insert payload has no caption key, and `galleryBlock`'s `images[]` entries have no caption attribute. The only way to caption a gallery image in Quill today is to hand-edit the markup in Code View.

## Approach

Add per-image Alt and Caption fields to the gallery sheet's selection list, editable at insert time only. Values are seeded from the media library item (`alt_text`, `caption`) so the sheet reflects what WordPress already knows; edits apply to the gallery block's markup only and never write back to the media library.

This deliberately stays inside the existing insert-only design for galleries. It does not make an inserted gallery re-editable, and it does not touch the `sourceHTML` verbatim round-trip that preserves galleries loaded from existing posts.

### Rejected alternatives

- **Re-editable galleries** (reopen an inserted gallery in the sheet). Requires replacing the loaded-gallery `sourceHTML` verbatim render path with reconstruction, which would drop any markup Quill doesn't model, and requires first fixing the known per-image `sizeSlug` data loss documented in `Sources/QuillKit/Resources/CLAUDE.md`. Much larger change, and it destabilizes a path that currently guarantees byte-for-byte preservation.
- **Inline caption editing on the gallery card.** Would require `galleryBlock` to stop being an atom and gain editable content, touching the ProseMirror paths with the worst regression history in this codebase.
- **Write-back to the media library.** Editing alt in the sheet would also `PUT /media/{id}`, changing the image everywhere it is used. Rejected as surprising: gallery-block edits should be local to the block, matching Gutenberg's behavior. `WordPressClient.updateMediaAltText` remains available from `MediaDetailView` for genuine library edits.

## Data model

### `WPMedia` (`Sources/QuillKit/API/Models/WPMedia.swift`)

Add:

```swift
public var caption: RenderedString?
```

decoded with `decodeIfPresent` from the `caption` JSON key, plus a `captionText` computed property returning plain text for prefill. Both media fetches already request `context=edit` (`WordPressClient.swift:116,122`), so `caption.raw` is present and is plain text; `captionText` reuses `RenderedString.excerptText`, which reads `raw` only, strips HTML, and decodes entities. Media items returned by `uploadMedia` (no `context=edit`) have no `raw` and always have an empty caption anyway, so `excerptText`'s `""` fallback is correct there.

### `GallerySelection` (new, in `GallerySheet.swift`)

```swift
public struct GallerySelection: Identifiable {
    public let media: WPMedia
    public var alt: String
    public var caption: String
    public var id: Int { media.id }
}
```

`public` because `GallerySheet.init` is `public` and its `onInsert` closure signature references this type.

`GallerySheet.selected` changes from `[WPMedia]` to `[GallerySelection]` (`GallerySheet.swift:16`). A struct rather than side-tables keyed by media id, so the per-image text travels with the image through reorder and removal and cannot go stale.

Selecting an image in `toggle(_:)` seeds `alt` from `media.altText` and `caption` from `media.captionText`. Deselecting removes the entry and its text. Re-selecting a previously removed image re-seeds from the media item — typed text is not preserved across a remove/re-add cycle.

Call sites needing the shape change: the grid's `isSelected` check (`GallerySheet.swift:91`), `toggle(_:)`, the selection `List` and its `onMove` (`GallerySheet.swift:133-166`), the remove button, the upload path's `selected.append` (`GallerySheet.swift:251`), and the `onInsert` closure signature.

## UI

Each row in the selection list gains a chevron button on its trailing edge, beside the existing remove button. Clicking the chevron — and only the chevron, so the row body stays free for drag-to-reorder — toggles the image's id in a new `@State private var expandedIDs: Set<Int>`.

Collapsed rows are visually unchanged from today. An expanded row renders a `VStack` beneath the existing `HStack` containing two labeled `TextField`s — "Alt text" and "Caption" — using the existing `sectionLabel(_:)` styling for the labels and `.textFieldStyle(.roundedBorder)` at the list's 12pt text size, indented to align with the row's title text.

Multiple rows may be expanded at once. Expansion state is not persisted; it resets when the sheet closes.

Drag-to-reorder continues to use `List`'s `onMove`. Variable-height rows are supported by `List`; typing in a `TextField` must not initiate a drag — to be confirmed in manual verification.

## Bridge

`GallerySheet.onInsert`'s first parameter becomes `[GallerySelection]`. `PostEditorView`'s payload builder (`PostEditorView.swift:180-187`) becomes:

```swift
let imagePayload: [[String: Any]] = selections.map { sel in
    [
        "id": sel.media.id,
        "url": sel.media.sizedURL(for: sizeSlug),
        "fullUrl": sel.media.sourceURL,
        "alt": sel.alt,
        "caption": sel.caption,
    ]
}
```

`EditorCoordinator.insertGallery` serializes the image dictionaries generically (`EditorCoordinator.swift:262`), so it needs no change.

## Editor (`editor.html`, `galleryBlock`)

**Render** (`renderHTML` reconstruction path, `editor.html:1717-1744`): after the `<img>` (or the `<a>` wrapping it) is appended to the image figure, append a caption when `image.caption` is non-empty:

```js
if (image.caption) {
  const cap = document.createElement('figcaption')
  cap.className = 'wp-element-caption'
  cap.textContent = image.caption
  imgFigure.appendChild(cap)
}
```

`textContent`, not `innerHTML` — caption text comes from a plain `TextField` and must not be able to inject markup. An empty caption emits no `<figcaption>` at all.

The `sourceHTML` branch at the top of `renderHTML` is untouched: loaded galleries continue to re-emit their original markup verbatim.

**Parse** (`parseHTML`'s `getAttrs`, `editor.html:1690-1713`): each entry in the extracted `images` array gains

```js
caption: fig.querySelector('figcaption')?.textContent || '',
```

This value is not read back for loaded galleries (their `sourceHTML` governs rendering), but capturing it keeps `node.attrs` honest rather than adding a second instance of the per-image `sizeSlug` ground-truth loss already documented in `Sources/QuillKit/Resources/CLAUDE.md`.

**`wp:image` block comments require no change.** Gutenberg carries captions in the HTML, not in the comment attrs; the existing `{id, sizeSlug, linkDestination}` attrs are already correct.

## `toWordPressHTML` — no changes

The figure-normalization pass at `editor-transforms.js:173` selects `figure:not(.wp-block-table):not(.wp-block-embed):not(.wp-block-gallery)`. That excludes the gallery wrapper itself but still matches the nested `figure.wp-block-image` elements inside it, so it already adds `wp-element-caption` to non-empty figcaptions and removes empty ones (`editor-transforms.js:184-191`). Gallery captions are normalized for free. This is covered by a regression test rather than new code.

## Testing

**JS — `Scripts/test-editor-gallery.js`** (real `editor.html` in jsdom, existing `window.insertGallery` bridge pattern):

- A caption in the insert payload renders as `<figcaption class="wp-element-caption">` inside that image's figure, and only that image's figure.
- An empty or omitted caption emits no `<figcaption>`.
- Caption text containing markup (e.g. `<script>` or `<b>`) is escaped, not injected.
- An `alt` value overriding the media item's own alt lands on the `<img alt>`.
- `parseHTML` extracts captions from a loaded gallery's image figures into `node.attrs.images[].caption`.

**JS — `Scripts/test-editor.js`:**

- `toWordPressHTML` preserves gallery image captions, applies `wp-element-caption`, and remains idempotent across repeated saves (the comment-wrapping pass must not duplicate or strip captioned figures).

**Swift — `Tests/QuillTests`:**

- `WPMedia` decodes `caption` from a `context=edit` payload (`raw` present), from a `rendered`-only payload, and from a payload with the key absent.

## Non-goals

- Editing an already-inserted gallery (alt/caption are insert-time only; later fixes require Code View or re-inserting).
- Writing alt or caption back to the WordPress media library.
- Rich text, links, or line breaks in captions — plain text only.
- Per-image size, alignment, or link destination (per-gallery, as today).
- A gallery-wide caption on the `<figure class="wp-block-gallery">` itself.
