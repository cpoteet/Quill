# Streaming Media Uploads — Design Spec

**Date:** 2026-06-10
**Status:** Approved

## Problem

Three related bugs in the media upload path:

1. **`handleDroppedImages` reads files on the main thread.** `Data(contentsOf: url)` blocks the UI for the duration of the read. Large drops freeze all interaction.
2. **`uploadMedia(data:)` buffers the entire file in RAM.** `request.httpBody = data` requires the whole file to exist in memory simultaneously. The file picker allows any size; a large file could exhaust memory before the upload starts.
3. **`UTType.movie` is allowed in the picker but has no MIME mapping.** Videos upload as `application/octet-stream`, which WordPress rejects or mishandles. Video upload is not a desired feature.

## Solution

Change `uploadMedia` to accept a file `URL` and use `URLSession.upload(for:fromFile:)`, which streams directly from disk. Update both call sites to pass the URL directly, eliminating all in-memory file reads.

## Changes

### `WordPressClient`

Replace:
```swift
public func uploadMedia(data: Data, filename: String, mimeType: String) async throws -> WPMedia
```
With:
```swift
public func uploadMedia(fileURL: URL, filename: String, mimeType: String) async throws -> WPMedia
```

Add a private `sendUpload(_:fromFile:)` alongside the existing `send(_:)`. The two methods are identical except `sendUpload` calls `session.upload(for:fromFile:)` instead of `session.data(for:)`. Error handling (cancellation, HTTP errors, HTML responses) is the same.

`uploadMedia` builds the request headers (`Content-Type`, `Content-Disposition`) as before, then calls `sendUpload` instead of setting `request.httpBody` and calling `perform`.

### `PostEditorView.handleDroppedImages`

Remove:
```swift
let data = try Data(contentsOf: url)
```

Change call to:
```swift
let media = try await client.uploadMedia(fileURL: url, filename: url.lastPathComponent, mimeType: mime)
```

The main-thread read bug is eliminated because there is no read — `URLSession` streams from disk on a background thread internally.

### `MediaSidebarSection.uploadFromDisk`

Remove the `Task.detached { try Data(contentsOf: url) }` block.

Change call to:
```swift
let uploaded = try await WordPressClient(credentials: creds)
    .uploadMedia(fileURL: url, filename: url.lastPathComponent, mimeType: mime)
```

Remove `UTType.movie` from `panel.allowedContentTypes`. Picker becomes `[UTType.image, UTType.pdf]`.

### MIME helpers unchanged

`imageMimeType` in `PostEditorView` (images-only drop path) and `mimeType` in `MediaSidebarSection` (images + PDF for sidebar) stay separate — they cover different allowed-type sets for their respective contexts.

## Testing

One new test in `WordPressClientTests`:

- `uploadMediaStreamsFromFileNotHttpBody` — creates a temp file with known content, calls `uploadMedia(fileURL:)` through `MockURLProtocol`, verifies:
  - `request.httpBody == nil` (nothing buffered into the request object)
  - `Content-Type` header matches the supplied MIME type
  - `Content-Disposition` header contains the filename
  - Response decodes to the expected `WPMedia`

Existing `uploadMedia` tests updated to use the new `fileURL:` parameter.

## Out of scope

- Progress reporting for uploads
- Chunked / multipart uploads
- Paste-from-clipboard image upload (no file URL available; uses `Data` path separately)
