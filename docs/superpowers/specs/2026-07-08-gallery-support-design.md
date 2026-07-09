# Gallery Support — Design Spec

**Date:** 2026-07-08
**Status:** Approved, not yet implemented

## Problem

WordPress galleries (`wp:gallery` blocks) have no representation in Quill's Tiptap model today. They ride entirely on the `_rawHTML`/`_rawHTMLOnLoad` verbatim safety net (see `docs/future-architecture.md`, Approach E), which is nulled the instant the user makes *any* visual edit elsewhere in the post — at which point the gallery is silently dropped on next save. There is also no way to create a gallery from within Quill.

## Approach

Treat galleries the same way `EmbedBlock` treats embeds: an atomic Tiptap node that renders as a static, non-editable card in the editor. All actual authoring happens outside Tiptap, in a native SwiftUI sheet. This avoids building in-place multi-image drag/resize/reorder inside ProseMirror — the hardest part of "real" gallery support — by pushing that UX to SwiftUI, which the app already does well (`MediaPickerView`, `PostSettingsPanel`).

This is deliberately **insert-only for v1**: galleries created in Quill are fully editable there; galleries that already exist in a post (authored elsewhere) are recognized and displayed as a read-only card, but not yet editable via the sheet. This still fixes the silent-drop problem for existing galleries — an atomic node survives edits elsewhere in the document, unlike the `_rawHTML` fallback — without requiring a parser robust enough to round-trip arbitrary existing galleries back out for editing.

## Data model (node attrs)

`galleryBlock` (atomic Tiptap node):

- `images`: array of `{ id: Int, url: String, alt: String }` — `id`/`url`/`alt` sourced from `WPMedia` (`id`, `sourceURL`, `altText`)
- `columns`: Int, 1–8, default 3
- `cropped`: Bool, default true (matches Gutenberg's default "crop to square" behavior)
- `linkTo`: enum `none` / `media`, default `none` — gallery-wide setting (not per-image); `media` links each image to its full-resolution file

Explicitly out of scope for v1: per-image captions, per-image link override, "link to attachment page" option.

## WordPress markup format

Known-stable structure (unchanged since the WP 5.9 gallery block refactor to nested blocks): a `wp:gallery` block wrapping nested `wp:image` blocks, e.g.:

```html
<!-- wp:gallery {"linkTo":"none"} -->
<figure class="wp-block-gallery has-nested-images columns-3 is-cropped">
<!-- wp:image {"id":123,"sizeSlug":"large","linkDestination":"none"} -->
<figure class="wp-block-image size-large"><img src="https://.../photo1.jpg" alt="" class="wp-image-123"/></figure>
<!-- /wp:image -->
<!-- wp:image {"id":124,"sizeSlug":"large","linkDestination":"none"} -->
<figure class="wp-block-image size-large"><img src="https://.../photo2.jpg" alt="" class="wp-image-124"/></figure>
<!-- /wp:image -->
</figure>
<!-- /wp:gallery -->
```

**Not yet verified from memory alone:** whether attributes are omitted at default value, exact class ordering, and whether `columns-N` is always emitted or only on deviation from auto-layout. Per the existing documented process in `CLAUDE.md` ("How to update when WordPress changes its HTML format"), the implementation plan must include a step to fetch real gallery markup from the user's local WordPress site (`GET /wp-json/wp/v2/posts/{id}?context=edit`, `content.raw`) before writing the serializer, and use that as the ground truth for both the render template and the parse rule.

## Insert flow

1. New toolbar button ("Add Gallery") in the utility group, alongside the existing image "Add" button — kept as a separate, clearly-labeled button rather than merged with single-image insert (see Rationale below).
2. Opens `GallerySheet`, a new SwiftUI sheet (not a modification of `MediaPickerView` — that view is deliberately picker-only per existing `CLAUDE.md` guidance, and should stay that way).
3. `GallerySheet` fetches media via the existing `WordPressClient.fetchMedia`, presents a multi-select grid (tap toggles a checkmark), a reorderable strip of the current selection (drag to reorder, tap to remove), and controls for columns / crop / link-to.
4. "Insert Gallery" (disabled until ≥1 image selected) builds a payload (`images`, `columns`, `cropped`, `linkTo`) and posts it via `NotificationCenter`, following the same pattern as today's `.insertMediaURL`.
5. `EditorCoordinator` picks up the notification and calls a new `insertGallery(json)` JS function, which does `editor.chain().focus().insertContent({ type: 'galleryBlock', attrs: {...} }).run()`.

### Rationale: separate buttons, not a combined image/gallery picker

Considered and rejected: one button handling both single-image and gallery insertion based on selection count. Rejected because (a) there's no reliable threshold — Gutenberg itself permits a 1-image gallery, so "1 = image, 2+ = gallery" is not a safe inference; (b) it would reintroduce mode-branching into `MediaPickerView`, which was deliberately simplified away from a `mode:` parameter; (c) it doesn't actually reduce implementation work, since the post-selection flows (single insert vs. reorder+settings sheet) remain entirely different regardless of entry point.

## Load flow (existing galleries)

`galleryBlock`'s `parseHTML()` matches `figure.wp-block-gallery`, walks child `figure.wp-block-image > img` elements to extract `id` (from the `wp-image-{id}` class), `src`, and `alt` into the `images` array, and reads `columns`/`is-cropped` from the wrapper's class list. Gallery-level `linkTo` recovery from DOM alone may have fidelity gaps (comment JSON isn't visible to Tiptap's DOM parser) — acceptable for v1 since these are read-only cards, but the plan should confirm exact recoverability once real markup is available.

Malformed or plugin-modified gallery markup that doesn't match the parse rule falls through to today's `_rawHTML` passthrough behavior — no regression versus current behavior.

## Error handling / edge cases

- Empty selection: "Insert Gallery" disabled until ≥1 image chosen.
- Media fetch failure in the sheet: same retry-button pattern as `MediaPickerView`.
- Unrecognized existing gallery structure: falls through to `_rawHTML` safety net, unchanged from today.

## Testing

- Swift: decode a post containing real gallery HTML into node attrs (once sample markup is available), following the `WPPostDecodingTests` pattern.
- JS: `editor-transforms.js`-style parse/render tests for `galleryBlock`, plus a save round-trip test asserting generated HTML matches WordPress's format byte-for-byte.
- Manual: insert a gallery on a local draft, verify correct rendering on the live WordPress site.

## Open items for the implementation plan

1. Fetch real `wp:gallery` markup from the user's local WordPress site and finalize the exact serialization template and parse rule against it.
2. Confirm how much of `linkTo` can be recovered from DOM alone for the read-only load path (vs. requiring comment-JSON access).
