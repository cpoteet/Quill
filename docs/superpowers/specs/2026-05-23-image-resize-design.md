# Image Resize in Editor — Design Spec

**Date:** 2026-05-23  
**Branch:** feature/wp-writer-implementation

## Overview

Two related improvements:
1. Preserve `width`/`height` attributes when loading existing WordPress posts
2. Let users resize images inline via drag handles and a size picker popover

## Goals

- Images inserted from the media library appear at their natural pixel dimensions
- Existing WordPress posts with `<img width="..." height="...">` load with those dimensions intact
- Users can resize images in the editor by dragging handles
- Users can snap to WordPress named sizes (Thumbnail, Medium, Large, Full) or type custom dimensions
- Saved HTML uses standard `<img width="..." height="...">` attributes — clean round-trip with WordPress

## Non-Goals

- Alignment (`alignleft`, `alignright`, `aligncenter`) — separate concern, out of scope
- Image cropping
- Uploading a resized version back to WordPress

---

## Section 1: Extended Image Node

Replace `Image.configure({ inline: false })` with a custom Tiptap extension that extends the base Image extension.

**Additional attributes:**

| Attribute | HTML | Type | Default |
|---|---|---|---|
| `width` | `width="300"` | Int or null | null |
| `height` | `height="200"` | Int or null | null |
| `mediaId` | `data-media-id="42"` | Int or null | null |

All three attributes are optional. `width`/`height` serialize to/from standard HTML `<img>` attributes. `mediaId` serializes to/from `data-media-id`. When loading existing WordPress posts, the extension also parses `class="wp-image-{id}"` as a fallback source for `mediaId`.

**Insertion behavior:** New images are inserted with all three set. Images without dimensions load unconstrained — CSS `max-width: 100%` still applies, so they never overflow the 720px editor column.

**Output HTML:** `<img src="..." width="300" height="200" data-media-id="42">`

---

## Section 2: NodeView and Resize Handles

Each image is rendered by a custom ProseMirror `NodeView` instead of Tiptap's default.

### DOM Structure

```html
<div class="image-wrapper" style="width: 300px; position: relative; display: inline-block;">
  <img src="..." width="300" height="200">
  <!-- 8 handles, hidden until selected -->
  <div class="resize-handle nw"></div>
  <div class="resize-handle n"></div>
  <div class="resize-handle ne"></div>
  <div class="resize-handle e"></div>
  <div class="resize-handle se"></div>
  <div class="resize-handle s"></div>
  <div class="resize-handle sw"></div>
  <div class="resize-handle w"></div>
</div>
```

### Handle Visibility

Handles are hidden by default (`opacity: 0`, `pointer-events: none`). The NodeView implements `selectNode()` and `deselectNode()` — selected state adds a CSS class `.selected` to the wrapper which makes handles visible.

### Drag Behavior

- `mousedown` on a handle: captures starting mouse X/Y, current image width/height, and which handle was hit. Sets `document.addEventListener` for `mousemove` and `mouseup`.
- `mousemove`: calculates delta from start position, applies to image dimensions live (direct DOM mutation for smooth feedback, no ProseMirror transaction yet).
- Corner handles (`nw`, `ne`, `sw`, `se`): maintain aspect ratio by default. Holding `Shift` during drag disables ratio lock and resizes only the relevant axis.
- Edge handles (`n`, `s`): resize height only. (`e`, `w`): resize width only. Always free (no ratio lock).
- `mouseup`: dispatches a ProseMirror transaction to commit the new `width`/`height` attributes. This triggers the existing debounced `contentChanged` → Swift flow, marking the document dirty.
- Minimum width: 50px. Minimum height: 50px. Enforced during mousemove clamping.

### CSS for Handles

Handles are 8×8px squares, positioned at their respective corners/edges with `position: absolute`. Corner handles show a diagonal resize cursor; N/S edge handles show a vertical resize cursor; E/W edge handles show a horizontal resize cursor.

---

## Section 3: Size Picker Popover

A floating toolbar appears just below the selected image. It is a plain `<div>` appended to `#editor-wrap` (not inside the NodeView's own DOM, to avoid overflow clipping). It is shown/hidden and repositioned by the NodeView using the image wrapper's `getBoundingClientRect()` relative to `#editor-wrap`. Not a system popover.

### Contents

1. **Dimension editor:** `300 × 200` — each number is an `<input type="number">`. Changing width recalculates height to maintain aspect ratio (and vice versa). Pressing Enter or blurring commits via ProseMirror transaction.

2. **Named size buttons** (shown only if `mediaId` resolves): **Thumb**, **Medium**, **Large**, **Full** — clicking one swaps `src` to that size's URL and sets `width`/`height` to match. Buttons are disabled if the named size isn't available for this image.

3. **Reset button:** clears `width` and `height` attributes (sets to null), returning the image to CSS `max-width: 100%` behavior.

### Media Size Resolution

Named sizes are resolved via a Swift↔JS round-trip:

1. When an image is selected and has a `mediaId`, JS posts `requestMediaSizes` message with `{ mediaId }` to Swift.
2. Swift looks up the media item in `appState.mediaItems`. If found, calls `window.setMediaSizes(mediaId, sizesJSON)` into the webview. `sizesJSON` is an object: `{ thumbnail: { url, width, height }, medium: { … }, large: { … }, full: { … } }`.
3. JS receives `setMediaSizes`, caches the result keyed by `mediaId`, and updates the popover buttons.
4. If the media item is not in `appState.mediaItems` (not yet loaded), named size buttons are hidden.

No pre-serialization of the full media library into the webview.

---

## Section 4: Swift-side Changes

### `insertMediaURL` Notification

`userInfo` gains three optional keys:
- `width: Int` — natural pixel width from `WPMedia.mediaDetails?.width`
- `height: Int` — natural pixel height from `WPMedia.mediaDetails?.height`
- `mediaId: Int` — the `WPMedia.id`

Existing call sites that lack this info omit the keys; JS treats missing values as null.

### `EditorCoordinator`

`insertImage(url:at:)` expands to `insertImage(url:at:width:height:mediaId:)` with optional Int parameters.

JS call: `insertImageAt(index, url, width, height, mediaId)` — all values JSON-encoded.

New message handler: `requestMediaSizes` — receives `{ mediaId: Int }`, looks up in `appState.mediaItems`, responds via `window.setMediaSizes(id, sizesJSON)`.

`EditorCoordinator` gains a closure `onRequestMediaSizes: ((Int) -> WPMedia?)?`. When `requestMediaSizes` fires, the coordinator calls this closure with the `mediaId`, receives a `WPMedia?`, serializes its `mediaDetails.sizes` dictionary into JSON, and calls `window.setMediaSizes(id, sizesJSON)` into the webview. The closure is wired up in `PostEditorView` / `EditorView` to look up `appState.mediaItems`.

### `PostEditorView`

**Media picker sheet** call site: include `selected.mediaDetails?.width`, `selected.mediaDetails?.height`, `selected.id` in `userInfo`.

**Drag-and-drop upload** call site: include `media.mediaDetails?.width`, `media.mediaDetails?.height`, `media.id` after upload completes.

### `window.insertImageAt` JS Function

Updated signature: `(index, url, width, height, mediaId)`. Sets all five on the inserted image node. Width/height may be `null` (JS null, encoded as JSON `null`).

---

## Data Flow Summary

```
Insert (media picker / drag-drop)
  Swift: WPMedia → userInfo {url, width, height, mediaId}
  → EditorCoordinator.insertImage(url:at:width:height:mediaId:)
  → window.insertImageAt(index, url, width, height, mediaId)
  → Tiptap: setImage({ src, width, height, mediaId })
  → NodeView renders with handles

Load existing post
  WordPress HTML: <img src="..." width="300" height="200" class="wp-image-42">
  → Custom Image extension parses width, height, mediaId (from class)
  → NodeView renders at 300×200 with handles

Resize via drag
  NodeView mouseup → ProseMirror transaction { width, height }
  → editor.on('update') → contentChanged → Swift (dirty state)

Named size swap
  JS: requestMediaSizes { mediaId }
  → Swift: appState.mediaItems lookup → window.setMediaSizes(id, JSON)
  → JS: popover buttons enabled, user clicks "Large"
  → ProseMirror transaction { src: largeURL, width: largeW, height: largeH }
  → contentChanged → Swift

Save
  editor.getHTML() → <img src="..." width="300" height="200" data-media-id="42">
  → WordPress REST API PUT
```

---

## Files Changed

| File | Change |
|---|---|
| `Sources/QuillKit/Resources/editor.html` | Custom Image extension, NodeView, size picker popover, `insertImageAt` update, `setMediaSizes` global, `requestMediaSizes` handler |
| `Sources/QuillKit/Views/Editor/EditorCoordinator.swift` | `insertImage` signature, `requestMediaSizes` message handler, `onRequestMediaSizes` closure |
| `Sources/QuillKit/Views/Editor/EditorView.swift` | Register `requestMediaSizes` message handler |
| `Sources/QuillKit/Views/Editor/PostEditorView.swift` | Pass dimensions and mediaId in both `insertMediaURL` post sites |
