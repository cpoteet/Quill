# Streaming Media Uploads Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace whole-file RAM buffering with streaming uploads, fix the main-thread read in drag-drop, and remove video from the media picker.

**Architecture:** Change `WordPressClient.uploadMedia` to accept a `fileURL: URL` and use `URLSession.upload(for:fromFile:)`, which streams directly from disk. Both call sites (drag-drop in `PostEditorView`, toolbar upload in `MediaSidebarSection`) already have a file URL and can drop their in-memory read entirely.

**Tech Stack:** Swift 6, URLSession async/await, Swift Testing (`@Test`), `MockURLProtocol`

---

### Task 1: Update existing `uploadMedia` tests to use `fileURL:` parameter

All four existing tests currently call `uploadMedia(data:filename:mimeType:)`. This task rewrites them to call `uploadMedia(fileURL:filename:mimeType:)` so they compile-fail until the implementation changes in Task 2.

**Files:**
- Modify: `Tests/QuillTests/WordPressClientTests.swift` (lines ~301–337, ~745–755)

- [ ] **Step 1: Replace the four existing `uploadMedia` tests**

Open `Tests/QuillTests/WordPressClientTests.swift`. Replace the four tests below. Each now writes a tiny byte array to a temp file and passes the file URL. The `defer` removes the temp file after the test.

Replace `uploadMediaSetsContentTypeFromMimeType` (around line 301):
```swift
@Test func uploadMediaSetsContentTypeFromMimeType() async throws {
    var capturedRequest: URLRequest?
    MockURLProtocol.requestHandler = { request in
        capturedRequest = request
        return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                minimalMediaJSON.data(using: .utf8)!)
    }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
    try Data([0x89, 0x50]).write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }
    _ = try await client.uploadMedia(fileURL: tmp, filename: "photo.png", mimeType: "image/png")
    #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "image/png")
}
```

Replace `uploadMediaSetsContentDispositionWithFilename` (around line 312):
```swift
@Test func uploadMediaSetsContentDispositionWithFilename() async throws {
    var capturedRequest: URLRequest?
    MockURLProtocol.requestHandler = { request in
        capturedRequest = request
        return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                minimalMediaJSON.data(using: .utf8)!)
    }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
    try Data([0xFF, 0xD8]).write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }
    _ = try await client.uploadMedia(fileURL: tmp, filename: "photo.jpg", mimeType: "image/jpeg")
    let disposition = capturedRequest?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
    #expect(disposition.contains("filename=\"photo.jpg\""))
    #expect(disposition.contains("filename*=UTF-8''"))
}
```

Replace `uploadMediaSpacesInFilenameArePercentEncoded` (around line 325):
```swift
@Test func uploadMediaSpacesInFilenameArePercentEncoded() async throws {
    var capturedRequest: URLRequest?
    MockURLProtocol.requestHandler = { request in
        capturedRequest = request
        return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                minimalMediaJSON.data(using: .utf8)!)
    }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
    try Data([0xFF, 0xD8]).write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }
    _ = try await client.uploadMedia(fileURL: tmp, filename: "my photo.jpg", mimeType: "image/jpeg")
    let disposition = capturedRequest?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
    #expect(disposition.contains("filename=\"my photo.jpg\""))
    #expect(disposition.contains("my%20photo.jpg"))
}
```

Replace `uploadMediaEscapesQuotesInContentDispositionFilename` (around line 745):
```swift
@Test func uploadMediaEscapesQuotesInContentDispositionFilename() async throws {
    var capturedRequest: URLRequest?
    MockURLProtocol.requestHandler = { request in
        capturedRequest = request
        return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                minimalMediaJSON.data(using: .utf8)!)
    }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
    try Data([0xFF, 0xD8]).write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }
    _ = try await client.uploadMedia(fileURL: tmp, filename: "weird \"name\".jpg", mimeType: "image/jpeg")
    let disposition = capturedRequest?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
    #expect(disposition.contains("filename=\"weird \\\"name\\\".jpg\""))
}
```

- [ ] **Step 2: Add the new streaming test**

Add this test after `uploadMediaEscapesQuotesInContentDispositionFilename`:
```swift
@Test func uploadMediaStreamsFromFileNotHttpBody() async throws {
    var capturedRequest: URLRequest?
    MockURLProtocol.requestHandler = { request in
        capturedRequest = request
        return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                minimalMediaJSON.data(using: .utf8)!)
    }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let media = try await client.uploadMedia(fileURL: tmp, filename: "test.png", mimeType: "image/png")
    #expect(capturedRequest?.httpBody == nil)
    #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "image/png")
    #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Disposition")?.contains("filename=\"test.png\"") == true)
    #expect(media.id == 5)
}
```

- [ ] **Step 3: Run the affected tests — verify they fail**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && swift test --filter WordPressClientTests 2>&1 | grep -E "error:|FAIL|passed|failed"
```

Expected: compile errors — `type 'WordPressClient' has no member 'uploadMedia'` with a `fileURL:` label (since the current method still has `data:`).

---

### Task 2: Implement `uploadMedia(fileURL:)` and `sendUpload` in `WordPressClient`

**Files:**
- Modify: `Sources/QuillKit/API/WordPressClient.swift` (lines ~136–148, ~324–360)

- [ ] **Step 1: Replace `uploadMedia` and add `sendUpload`**

In `Sources/QuillKit/API/WordPressClient.swift`, replace the existing `uploadMedia` method:

```swift
// BEFORE (remove this):
public func uploadMedia(data: Data, filename: String, mimeType: String) async throws -> WPMedia {
    let url = try endpoint("media")
    var request = authorizedRequest(url: url, method: "POST")
    request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
    let fallback = WordPressClient.contentDispositionFilenameFallback(filename)
    let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fallback
    request.setValue(
        "attachment; filename=\"\(fallback)\"; filename*=UTF-8''\(encoded)",
        forHTTPHeaderField: "Content-Disposition"
    )
    request.httpBody = data
    return try await perform(request)
}
```

```swift
// AFTER (replace with):
public func uploadMedia(fileURL: URL, filename: String, mimeType: String) async throws -> WPMedia {
    let url = try endpoint("media")
    var request = authorizedRequest(url: url, method: "POST")
    request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
    let fallback = WordPressClient.contentDispositionFilenameFallback(filename)
    let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fallback
    request.setValue(
        "attachment; filename=\"\(fallback)\"; filename*=UTF-8''\(encoded)",
        forHTTPHeaderField: "Content-Disposition"
    )
    let (data, _) = try await sendUpload(request, fromFile: fileURL)
    do {
        return try JSONDecoder().decode(WPMedia.self, from: data)
    } catch {
        throw APIError.decodingError(error)
    }
}
```

Then add `sendUpload` directly below `send(_:)` (around line 347, just before `performVoid`):

```swift
private func sendUpload(_ request: URLRequest, fromFile fileURL: URL) async throws -> (data: Data, http: HTTPURLResponse?) {
    let (data, response): (Data, URLResponse)
    do {
        (data, response) = try await session.upload(for: request, fromFile: fileURL)
    } catch is CancellationError {
        throw CancellationError()
    } catch let urlError as URLError where urlError.code == .cancelled {
        throw CancellationError()
    } catch {
        throw APIError.networkError(error)
    }
    let http = response as? HTTPURLResponse
    if let http, http.statusCode >= 300 {
        let body = String(data: data, encoding: .utf8) ?? ""
        throw APIError.httpError(statusCode: http.statusCode, body: body)
    }
    let contentType = http?.value(forHTTPHeaderField: "Content-Type") ?? ""
    if contentType.contains("text/html") {
        throw APIError.unexpectedHTML
    }
    return (data, http)
}
```

- [ ] **Step 2: Run the `WordPressClientTests` — verify all pass**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && swift test --filter WordPressClientTests 2>&1 | tail -5
```

Expected: `✔ Test run with N tests passed`

- [ ] **Step 3: Run the full Swift test suite — verify no regressions**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && swift test 2>&1 | tail -5
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add Sources/QuillKit/API/WordPressClient.swift Tests/QuillTests/WordPressClientTests.swift && git commit -m "feat: stream media uploads from file instead of buffering in RAM"
```

---

### Task 3: Fix drag-drop upload in `PostEditorView`

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift` (~line 649)

- [ ] **Step 1: Remove the main-thread file read from `handleDroppedImages`**

In `Sources/QuillKit/Views/Editor/PostEditorView.swift`, find `handleDroppedImages` and update it:

```swift
// BEFORE:
private func handleDroppedImages(_ urls: [URL]) async {
    guard let creds = appState.credentials else { return }
    let client = WordPressClient(credentials: creds)
    for url in urls {
        guard url.isFileURL else { continue }
        do {
            let data = try Data(contentsOf: url)
            let mime = imageMimeType(for: url.pathExtension.lowercased())
            let media = try await client.uploadMedia(
                data: data, filename: url.lastPathComponent, mimeType: mime
            )
```

```swift
// AFTER:
private func handleDroppedImages(_ urls: [URL]) async {
    guard let creds = appState.credentials else { return }
    let client = WordPressClient(credentials: creds)
    for url in urls {
        guard url.isFileURL else { continue }
        do {
            let mime = imageMimeType(for: url.pathExtension.lowercased())
            let media = try await client.uploadMedia(
                fileURL: url, filename: url.lastPathComponent, mimeType: mime
            )
```

Everything else in the function stays the same.

- [ ] **Step 2: Run the full Swift test suite — verify no regressions**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && swift test 2>&1 | tail -5
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add Sources/QuillKit/Views/Editor/PostEditorView.swift && git commit -m "fix: remove main-thread file read from drag-drop upload path"
```

---

### Task 4: Fix sidebar upload in `MediaSidebarSection` and remove video from picker

**Files:**
- Modify: `Sources/QuillKit/Views/Media/MediaSidebarSection.swift` (~lines 267–299)

- [ ] **Step 1: Remove the `Task.detached` data read and pass file URL directly**

In `Sources/QuillKit/Views/Media/MediaSidebarSection.swift`, find `uploadFromDisk` and update it:

```swift
// BEFORE:
guard panel.runModal() == .OK, let url = panel.url else { return }
guard let creds = appState.credentials else { return }
isUploading = true
Task {
    defer { isUploading = false }
    do {
        let data = try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: url)
        }.value
        let mime = mimeType(for: url)
        let uploaded = try await WordPressClient(credentials: creds)
            .uploadMedia(data: data, filename: url.lastPathComponent, mimeType: mime)
```

```swift
// AFTER:
guard panel.runModal() == .OK, let url = panel.url else { return }
guard let creds = appState.credentials else { return }
isUploading = true
Task {
    defer { isUploading = false }
    do {
        let mime = mimeType(for: url)
        let uploaded = try await WordPressClient(credentials: creds)
            .uploadMedia(fileURL: url, filename: url.lastPathComponent, mimeType: mime)
```

Everything else in the function stays the same.

- [ ] **Step 2: Remove `UTType.movie` from the file picker**

In the same file, find the `allowedContentTypes` line and update it:

```swift
// BEFORE:
panel.allowedContentTypes = [UTType.image, UTType.pdf, UTType.movie]
```

```swift
// AFTER:
panel.allowedContentTypes = [UTType.image, UTType.pdf]
```

- [ ] **Step 3: Run the full Swift test suite — verify no regressions**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && swift test 2>&1 | tail -5
```

Expected: all tests pass.

- [ ] **Step 4: Build and smoke-test**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && pkill -x "Quill" 2>/dev/null || true && ./build.sh 2>&1 | tail -5
```

Open the app (`open Quill.app`). Verify:
- Media sidebar → upload button opens picker showing images and PDFs only (no "Movies" in the allowed types)
- Drag an image from Finder into the editor — image uploads and inserts without freezing the UI

- [ ] **Step 5: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add Sources/QuillKit/Views/Media/MediaSidebarSection.swift && git commit -m "fix: remove Task.detached data read from sidebar upload; drop video from picker"
```

---

### Task 5: Update the code review doc

**Files:**
- Modify: `docs/code-review-2026-06-10.md`

- [ ] **Step 1: Mark H4 as fixed**

In `docs/code-review-2026-06-10.md`, update the status table row for H4:

```markdown
// BEFORE:
| 7 | [H4](#h4-whole-file-buffering-for-media-uploads-main-thread-reads-for-drops) — Upload buffering / main-thread reads | Medium | Medium | ⬜ Todo |
```

```markdown
// AFTER:
| 7 | [H4](#h4-whole-file-buffering-for-media-uploads-main-thread-reads-for-drops) — Upload buffering / main-thread reads | Medium | Medium | ✅ Fixed |
```

- [ ] **Step 2: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add docs/code-review-2026-06-10.md && git commit -m "docs: mark H4 fixed in code review"
```
