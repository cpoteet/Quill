# Editable Galleries — Design Spec

**Date:** 2026-09-11
**Status:** Draft, pending review
**Branch:** `gallery-editing`

## Problem

A gallery in the visual editor cannot be changed. To reorder images, swap one out, fix a caption, or change the column count, the user must delete the whole gallery and rebuild it from scratch in `GallerySheet`.

This is not a data problem. `galleryBlock` already carries a complete structured model — `images[]` (id, url, alt, caption), `columns`, `cropped`, `linkTo`, `sizeSlug` — and `parseHTML` already populates all of it from a loaded gallery ([editor.html:1684](../../Sources/QuillKit/Resources/editor.html)). What is missing is an affordance connecting a selected gallery back to the sheet that created it.

## The blocker: `sourceHTML`

`renderHTML` short-circuits. When `sourceHTML` is set, it re-emits the captured original figure and **ignores every structured attribute**:

```js
renderHTML({ node }) {
  if (node.attrs.sourceHTML) { /* re-emit verbatim, attrs ignored */ }
  /* …otherwise reconstruct from attrs… */
}
```

`sourceHTML` is set for every gallery loaded from WordPress and null only for sheet-inserted ones. So editing a loaded gallery's attributes produces **no visible change** unless `sourceHTML` is also cleared.

Clearing it is therefore mandatory — and that is where the real work is, because `sourceHTML` is currently the only thing protecting everything `parseHTML` does not capture.

## What reconstruction loses today

Verified against a real published post — ["Learning to Build with Codex"](https://www.siolon.com/blog/learning-to-build-with-codex/) (post 17780), whose gallery was written by Quill:

```html
<!-- wp:gallery {"ids":[17810,17811,17812],"columns":3,"linkTo":"media"} -->
<figure class="wp-block-gallery has-nested-images columns-3 is-cropped">
<!-- wp:image {"id":17810,"sizeSlug":"large","linkDestination":"media"} -->
  <figure class="wp-block-image size-large image-plain"><a href="…/cigarreview.png"><img src="…/cigarreview.png" alt="…" class="wp-image-17810"></a></figure>
<!-- /wp:image -->
…
</figure>
<!-- /wp:gallery -->
```

Three concrete losses if `sourceHTML` is dropped and the node reconstructs:

| Lost | Why | Impact |
|---|---|---|
| **`image-plain` class** | `parseHTML` reads no per-image classes; `renderHTML` writes only `wp-block-image size-${sizeSlug}` | **Confirmed present in live content.** Every image in an edited gallery silently loses its styling class |
| **`fullUrl`** | `renderHTML` uses `image.fullUrl \|\| image.url`, but `parseHTML` never sets `fullUrl` | With `linkTo: 'media'`, links silently downgrade from the full-resolution original to the display-size image |
| **Gallery alignment** | `extractAlignment` exists but the gallery parse rule does not call it | An aligned gallery loses its alignment |

All three are silent degradations of already-published content. The `fullUrl` gap is latent *today* — it cannot bite while galleries are uneditable — and becomes live the moment this feature ships.

In the sampled post `src` and the link `href` happen to be identical (the images are already full-size), so `fullUrl` would not visibly regress *there*. It regresses on any gallery where WordPress generated sub-sizes and the display size is smaller than the original.

## Approach

**Close the parse/render gap first, then wire the sheet.** The ordering matters: wiring the sheet first ships the data loss.

### 1. Parity between `parseHTML` and `renderHTML`

Add to the per-image model:

- `fullUrl` — read from the wrapping `<a href>` when `linkTo` is `media`, falling back to the `img src`
- `extraClasses` — per-image classes on the `figure.wp-block-image` beyond `wp-block-image` and `size-*`, re-emitted verbatim on render (this is what preserves `image-plain`)

Add to the gallery model:

- `align` — via the existing `extractAlignment`, re-emitted on render

**Invariant:** for any gallery Quill can load, reconstructing from attrs with `sourceHTML` cleared must produce markup semantically equivalent to the original. This is the spec's central test.

### 2. Edit affordance

- **Double-click** a selected `galleryBlock`, plus an **Edit gallery** button in a `#gallery-controls` contextual toolbar group, following the existing `#table-controls` / `#image-align-controls` pattern (`display:none`, revealed on selection).
- Both call a new `window.editGallery()`, which posts the node's current attrs to Swift via the existing message-handler bridge.
- `EditorCoordinator` opens `GallerySheet` **pre-populated** from that payload rather than empty.
- On save, the sheet posts back through the existing `.insertGalleryData` path with an added node position, and `window.insertGallery` updates the existing node in place instead of inserting a new one.

### 3. Clearing `sourceHTML`

`updateAttributes` on save sets `sourceHTML: null` unconditionally. After step 1 this is safe, and it is what makes the edit visible.

## Migration

Galleries in already-published posts are **not** a data-format problem — Quill's gallery output has always carried correct `wp:gallery` / `wp:image` delimiters, confirmed above. They parse correctly today.

The migration concern is **fidelity on first edit**, and it is fully handled by step 1: once `parseHTML` captures everything `renderHTML` needs, an old gallery survives its first edit intact. No conversion pass, no data rewrite, no one-time script.

**Verification requirement:** before this ships, run every gallery currently on the site through parse → clear `sourceHTML` → render and diff against the original. The site has one gallery today (post 17780), so this is cheap and should be an actual test fixture, not a manual check.

### Out of scope: the classic-post migration

The same post confirms the separate, larger problem: its paragraphs, headings, lists and footnotes carry `wp-block-*` classes but **no delimiters**, so WordPress parses them as one `core/freeform` Classic block. Its standalone images are also un-delimited, and still carry `data-media-id` attributes that current Quill strips on save.

That is the subject of [2026-09-11-gutenberg-block-model-design.md](2026-09-11-gutenberg-block-model-design.md) and is explicitly **not** addressed here. This spec neither fixes nor worsens it.

## Testing

Extends `Scripts/test-editor-gallery.js`, which already covers insert / parse / render / round-trip against the real `editor.html` in jsdom.

1. **Round-trip with `sourceHTML` cleared** — the central test. Parse a real gallery fixture, clear `sourceHTML`, render, assert semantic equivalence to the original. Fixture taken verbatim from post 17780.
2. **`image-plain` preservation** — per-image extra classes survive parse → clear → render.
3. **`fullUrl` extraction** — parsed from the `<a href>`; a `linkTo: 'media'` gallery still links to the original after an edit, including when `src` and `href` differ.
4. **Alignment preservation** — an aligned gallery keeps its alignment.
5. **Edit round-trip** — load → `editGallery` → modify (reorder, change a caption, change columns) → save → re-parse yields the expected attrs, with one `wp:image` comment pair per image in the new order.
6. **Idempotency** — editing and saving twice does not stack comments or duplicate captions (the regression class documented in the root `CLAUDE.md`).
7. **Insert path unaffected** — sheet-inserted galleries (`sourceHTML: null`) behave exactly as today.

## Risks

- **`extraClasses` is an open-ended capture.** It preserves whatever it finds, which is correct for round-tripping but means malformed source classes are faithfully preserved too. Acceptable — the alternative is an allowlist that silently drops theme classes, which is the bug being fixed.
- **`GallerySheet` was written for creation, not editing.** Pre-populating it may surface ordering or selection-state assumptions. This is the least predictable part of the work and should be tackled after step 1 is green.
- **Scope creep toward standalone images.** The same `image-plain` and `fullUrl` gaps likely affect the standalone image node. Out of scope here; worth a follow-up once this pattern is proven.

## Rejected alternatives

**Keep `sourceHTML` and patch it with string edits on save.** Would avoid the parity work, but it is exactly the regex-over-HTML approach that produced three silent data-loss bugs in this codebase. Rejected.

**Make the gallery non-atomic so images are edited inline.** A larger change to the node's content schema, and it would not give access to `columns`, `crop`, `linkTo` or `sizeSlug`, which are gallery-level settings the sheet already handles well. Rejected as both more work and worse UX.
