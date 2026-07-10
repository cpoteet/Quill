# Image Link-to-Full-Size — Design Spec

**Date:** 2026-07-10
**Status:** Approved, not yet implemented

## Problem

WordPress's own image block has a "Link To" control (None / Media File / Attachment Page / Custom URL) that wraps the `<img>` in an `<a>` pointing at the chosen destination. Quill's `ResizableImage` node has no equivalent — a single inserted image can never be made to link anywhere. The gallery feature (`galleryBlock`) already solved the same problem for gallery images (`editor-transforms.js:218-246`, `editor.html:1652`), but that logic is scoped entirely to galleries; standalone images have no link wrapping or toolbar affordance at all today.

## Approach

Add a binary "Link to Full Image" toggle to the existing per-image toolbar (`#image-toolbar`, `editor.html:957`), scoped to None / Media File only — matching the gallery picker's existing scope, not WordPress's full four-option control. Attachment Page and Custom URL are explicitly out of scope (see Non-goals).

The full-resolution URL is sourced from the same media-sizes round-trip (`requestMediaSizes` → `setMediaSizes` → `_sizeData`, `editor.html:2904-2910`) that already powers the Thumb/Medium/Large/Full size buttons — no new Swift↔JS bridge call is needed. Because that round-trip only fires for images with a `mediaId` (i.e. images backed by a WordPress media item), the toggle naturally only becomes available for such images, exactly like the existing size buttons.

The live editing canvas (`ImageNodeView`) is unchanged — a linked image looks identical to an unlinked one while editing. The toggle's own `.active` state is the only indicator that an image is linked; there is no on-canvas badge.

## Data model (node attrs)

Two new attrs on `ResizableImage` (`editor.html:1311`, alongside `width`/`height`/`mediaId`/`alignment`/etc.):

- `linkTo`: enum `'none'` / `'media'`, default `'none'`
- `linkHref`: string or `null`, default `null` — the resolved full-resolution URL. Set when the toggle is turned on (from the fetched `full` size's URL); read back from the wrapping `<a>`'s `href` when parsing existing content.

## UI

A third row in `#image-toolbar`, below the existing W/H/size-buttons row and the Alt row: a single button, `#img-tb-link`, labeled "Link to Full Image". Styled like the existing toggle-style buttons (the `.active` class pattern already used by `#btn-code-view`).

Visibility rule: hidden by default (`style="display:none"`, matching the four `data-size` buttons), revealed only when `setMediaSizes` delivers a `full` entry for the selected image — i.e. exactly the same condition that reveals the Full size button. This means:
- Images with a `mediaId` whose sizes have loaded: button appears.
- Pasted/dropped images with no `mediaId`, or images whose sizes haven't loaded yet: button stays hidden.

Click behavior: toggles `node.attrs.linkTo` between `'none'` and `'media'` via `setNodeMarkup` (same commit pattern as the size buttons and Reset button, `editor.html:2990-3003`). Turning the toggle on reads the URL from the existing `full`-size button's `_sizeData` — the same lookup the Reset button already does (`document.querySelector('#image-toolbar [data-size="full"]')?._sizeData`, `editor.html:2959`) — and sets it as `linkHref`. Turning the toggle off leaves `linkHref` in place (harmless, since `renderHTML` only reads it when `linkTo === 'media'`) rather than clearing it, so re-enabling doesn't require re-reading it.

## Parse/render round-trip

**Render** (`renderHTML`, `editor.html:1371`): when `linkTo === 'media'` and `linkHref` is set, wrap the `<img>` in an `<a>`:

```js
['figure', figureAttrs, ['a', { href: node.attrs.linkHref }, ['img', HTMLAttributes]], ['figcaption', 0]]
```

Otherwise, output is unchanged from today (`['figure', figureAttrs, ['img', HTMLAttributes], ['figcaption', 0]]`).

**Parse** (`parseHTML`'s `getAttrs`, `editor.html:1382`): detect an anchor wrapping the image — `img.parentElement.tagName === 'A'` — the same check the gallery code already uses (`editor-transforms.js:225`). When present, set `linkTo: 'media'` and `linkHref` from that anchor's `href` attribute. All other existing attribute extraction (`src`, `alt`, `width`, `mediaId`, `alignment`, custom classes) is unaffected, since those all read from the `<img>` element directly via `el.querySelector('img')`, which resolves correctly whether or not an `<a>` sits between the `<figure>` and the `<img>`.

**`toWordPressHTML` requires no changes.** Its `figure:not(.wp-block-table):not(.wp-block-embed):not(.wp-block-gallery)` handling (`editor-transforms.js:46`) reads `figure.querySelector('img')` and `figure.querySelector('figcaption')`, both of which still resolve correctly through an intervening `<a>`.

## Non-goals

- Attachment Page and Custom URL link destinations (WordPress's other two "Link To" options).
- Any change to `galleryBlock`'s existing, independent `linkTo` handling.
- Any visual indicator on the live editing canvas (`ImageNodeView`) for linked images.
- Per-image link overrides within a gallery (already out of scope per the gallery spec; unaffected by this feature).

## Testing

JS unit tests in `Scripts/test-editor.js` (render) and `Scripts/test-editor-keyboard.js` (parse/round-trip), using the existing `wp()` and `htmlRoundTrip()` helpers:

- Toggling link on produces the `<a href>` wrapper around `<img>` in the rendered output; unlinked images are unaffected (no wrapper).
- A loaded `<figure class="wp-block-image"><a href="..."><img ...></a><figcaption>...</figcaption></figure>` parses to `linkTo: 'media'` with `linkHref` matching the anchor's `href`.
- Existing alignment, caption, custom-class, and `mediaId` handling all still work correctly with the `<a>` wrapper present (i.e. no regression to the tests already covering those cases against plain `<img>`-in-`<figure>` structures).
- A round trip (parse → render) of a linked image reproduces the same `<a href>` wrapper it started with.

Manual: insert an image from the media library on a local draft, turn on "Link to Full Image," save, and verify on the live WordPress site that the image links to its full-resolution file.
