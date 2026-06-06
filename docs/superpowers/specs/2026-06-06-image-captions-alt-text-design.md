# Image Captions and Alt Text

**Date:** 2026-06-06  
**Status:** Approved

## Overview

Add inline caption editing (click below the image to type, like Gutenberg) and alt text editing (image toolbar + media detail panel + pre-populated from the WordPress media library) to Quill's post editor.

## Decisions

- **Captions:** inline, always-visible placeholder ("Add a caption…") Gutenberg-style — not a toolbar field
- **Alt text in toolbar:** second row below W/H/Reset — not same row, not expand-on-click
- **Alt text in media detail:** editable field after the Dimensions row, save on commit (Return or blur)
- **Approach:** targeted extension of existing `ResizableImage` node (not a full figure-first rewrite)

## Section 1: Caption in the editor

### Schema

`ResizableImage` in `editor.html` gets `content: 'inline*'` added to its Tiptap extension definition. This makes it a non-atomic node with ProseMirror-managed caption content instead of a leaf node.

### NodeView (`ImageNodeView`)

A `<figcaption>` element is appended inside the figure wrapper. The NodeView returns `{ dom: wrapperDiv, contentDOM: figcaptionEl }` instead of setting only `this.dom`. ProseMirror renders and manages caption text directly inside the figcaption element.

`ignoreMutation()` is tightened: returns `false` for mutations inside `contentDOM` (so ProseMirror tracks caption edits), and continues to return `true` for resize-handle and wrapper-class mutations only.

### Parsing

The `parseHTML` rule for `figure.wp-block-image` gets `contentElement: 'figcaption'` added, so existing WordPress captions load into the node's content slot correctly on post load.

### `renderHTML`

`ResizableImage` gets an explicit `renderHTML` override that outputs the full figure structure with the figcaption content slot:

```js
renderHTML({ HTMLAttributes }) {
  return ['figure', {}, ['img', mergeAttributes(HTMLAttributes)], ['figcaption', 0]]
}
```

The `0` is ProseMirror's content hole — without this, `editor.getHTML()` silently drops all caption text. With it, Tiptap serialises caption content into `<figcaption>` automatically.

### Serialising

`toWordPressHTML()` is updated for the new format. `editor.getHTML()` now produces `<figure><img ...><figcaption>caption</figcaption></figure>`, so `toWordPressHTML()` no longer needs to wrap bare `<img>` elements. Instead it finds `<figure>` elements and:

1. Adds `wp-block-image` class (and alignment class if set) to the figure
2. Adds `wp-image-{id}` class to the inner `<img>` when `data-media-id` is present
3. Adds `class="wp-element-caption"` to the `<figcaption>` when non-empty; removes the figcaption element entirely when empty (to avoid emitting `<figcaption></figcaption>` in WordPress HTML)

### CSS

Figcaption is styled with centre-aligned italic text, appropriate padding, and a dark-mode variant matching the existing editor dark theme.

Always-visible placeholder via:
```css
figcaption.wp-caption-placeholder:empty::before {
  content: "Add a caption…";
  color: #aaa;
  pointer-events: none;
}
```

`ImageNodeView` toggles the `wp-caption-placeholder` class on the figcaption based on whether the node has content (empty → class present, has text → class absent).

## Section 2: Alt text in the image toolbar

### Toolbar layout

A second row is added to `#image-toolbar` below the existing W/H/Reset row:

```
Row 1: [ W: [___] H: [___]  |  Reset ]
Row 2: [ Alt  [_______________________________] ]
```

The alt text row is always visible when the toolbar is shown — not conditional on media size data.

### Populating on select

`_showImageToolbar(nodeView)` already runs on image selection and populates the W/H inputs. It will also set the alt input's value from `nodeView.node.attrs.alt ?? ''`.

### Saving

On `blur` (and `input` with a short debounce), the alt input handler calls:
```js
state.tr.setNodeMarkup(pos, null, { ...node.attrs, alt: value })
```
`pos` comes from `tb._activeNodeView.getPos()` — the same pattern used for W/H changes.

### Clearing

`_hideImageToolbar()` clears the alt input alongside the W/H inputs.

## Section 3: Alt text in the media detail panel and pre-population

### `WPMedia` model (`WPMedia.swift`)

Add `altText: String` decoded from the `alt_text` JSON key (default `""`).

### `WordPressClient` (`WordPressClient.swift`)

New method:
```swift
public func updateMediaAltText(id: Int, altText: String) async throws -> WPMedia
```
Sends `PATCH /media/{id}` with body `{"alt_text": "..."}` and decodes the returned `WPMedia`.

### `MediaDetailView` (`MediaDetailView.swift`)

An editable text field is inserted after the Dimensions row using `@State var altTextDraft: String` initialised from `media.altText`.

On commit (Return or blur), fires `onSaveAltText: (String) async -> Void` — a callback passed in from `ContentView`.

`ContentView` wires `onSaveAltText` to call `updateMediaAltText`, then replaces the matching entry in `appState.mediaItems`.

On save success, a brief "Saved" confirmation flash (`.secondary` label text, fades after 1.5 s) replaces the hint text beneath the field.

### Pre-population on insert

`EditorCoordinator.insertImage` gains an `alt: String?` parameter (default `nil`). The JS `window.insertImageAt` gains a 6th argument: `alt`.

```js
window.insertImageAt = (_index, url, width, height, mediaId, alt) => {
  const attrs = { src: url }
  if (width   != null) attrs.width   = width
  if (height  != null) attrs.height  = height
  if (mediaId != null) attrs.mediaId = mediaId
  if (alt)             attrs.alt     = alt
  editor.chain().focus().setImage(attrs).run()
}
```

`MediaPickerView` passes `media.altText` when calling `insertImage`, so images inserted from the picker pre-fill `alt` from the WordPress attachment's stored alt text.

## Files changed

| File | Change |
|---|---|
| `Sources/QuillKit/Resources/editor.html` | Caption schema + `renderHTML`, NodeView `contentDOM`, `parseHTML` `contentElement`, `toWordPressHTML` figure-class logic, toolbar second row, alt input logic, figcaption CSS |
| `Sources/QuillKit/API/Models/WPMedia.swift` | Add `altText` field |
| `Sources/QuillKit/API/WordPressClient.swift` | Add `updateMediaAltText` |
| `Sources/QuillKit/Views/Editor/EditorCoordinator.swift` | Add `alt` param to `insertImage` |
| `Sources/QuillKit/Views/Media/MediaPickerView.swift` | Pass `media.altText` on insert |
| `Sources/QuillKit/Views/Media/MediaDetailView.swift` | Add editable alt text field + save callback |
| `Sources/QuillKit/Views/ContentView.swift` | Wire `onSaveAltText` callback |
| `Scripts/test-editor.js` | Update image test fixtures (bare `<img>` → `<figure><img>`) and add caption round-trip tests |

## Out of scope

- Caption editing in the media detail panel (captions are per-post, not per-attachment)
- Full figure-first rewrite (Approach C in CLAUDE.md) — that remains documented as a future option
- Grammar/spell checking within captions (handled by the existing spell-check system)
