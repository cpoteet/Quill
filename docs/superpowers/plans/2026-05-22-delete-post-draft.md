# Delete Post / Draft Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add right-click context menu delete for remote WordPress posts/pages (trash) and local drafts (permanent) from the sidebar.

**Architecture:** Two files change — `WordPressClient` gets `trashPost`/`trashPage` methods backed by a new `performVoid` helper; `SidebarView` gets a `.contextMenu` on each row, confirmation alert, and an async `performDelete` function that updates `AppState` in-place on success.

**Tech Stack:** Swift 6, SwiftUI, swift-testing (`#expect`, `@Test`, `@Suite`), `MockURLProtocol` (already in `WordPressClientTests.swift`), WordPress REST API DELETE endpoint

---

## File Map

| File | Change |
|------|--------|
| `Sources/WPWriterKit/API/WordPressClient.swift` | Add `trashPost`, `trashPage` (public), `performVoid` (private) |
| `Views/Sidebar/SidebarView.swift` | Add `@State` vars, `.contextMenu`, confirmation alert, error alert, `performDelete` |
| `Tests/WPWriterTests/WordPressClientTests.swift` | Add three new `@Test` functions for trash methods |

---

## Task 1: Test and implement `trashPost` / `trashPage` in `WordPressClient`

**Files:**
- Modify: `Tests/WPWriterTests/WordPressClientTests.swift`
- Modify: `Sources/WPWriterKit/API/WordPressClient.swift`

- [ ] **Step 1: Add three failing tests to `WordPressClientTests.swift`**

Append inside `struct WordPressClientTests { ... }`, after the existing `fetchPostsThrowsOnHTTPError` test:

```swift
@Test func trashPostSendsDeleteRequest() async throws {
    var capturedRequest: URLRequest?
    MockURLProtocol.requestHandler = { request in
        capturedRequest = request
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        return (response, Data())
    }
    try await client.trashPost(id: 42)
    #expect(capturedRequest?.httpMethod == "DELETE")
    #expect(capturedRequest?.url?.path.contains("posts/42") == true)
    #expect(capturedRequest?.url?.query?.contains("force=false") == true)
}

@Test func trashPostThrowsOnHTTPError() async throws {
    MockURLProtocol.requestHandler = { _ in
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 403, httpVersion: nil, headerFields: nil
        )!
        return (response, Data())
    }
    await #expect(throws: APIError.self) {
        try await client.trashPost(id: 42)
    }
}

@Test func trashPageSendsDeleteRequest() async throws {
    var capturedRequest: URLRequest?
    MockURLProtocol.requestHandler = { request in
        capturedRequest = request
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        return (response, Data())
    }
    try await client.trashPage(id: 7)
    #expect(capturedRequest?.httpMethod == "DELETE")
    #expect(capturedRequest?.url?.path.contains("pages/7") == true)
    #expect(capturedRequest?.url?.query?.contains("force=false") == true)
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
swift test --filter WordPressClientTests 2>&1 | tail -15
```

Expected: compile error — `value of type 'WordPressClient' has no member 'trashPost'`

- [ ] **Step 3: Add `trashPost`, `trashPage`, and `performVoid` to `WordPressClient.swift`**

In `WordPressClient.swift`, after the `updatePage` method (line ~58) and before `// MARK: - Media`, add:

```swift
public func trashPost(id: Int) async throws {
    let url = try endpoint("posts/\(id)", query: ["force": "false"])
    let request = authorizedRequest(url: url, method: "DELETE")
    try await performVoid(request)
}

public func trashPage(id: Int) async throws {
    let url = try endpoint("pages/\(id)", query: ["force": "false"])
    let request = authorizedRequest(url: url, method: "DELETE")
    try await performVoid(request)
}
```

Then after the existing `private func perform<T: Decodable>` method (at the bottom of the file, before the closing `}`), add:

```swift
private func performVoid(_ request: URLRequest) async throws {
    let (data, response): (Data, URLResponse)
    do {
        (data, response) = try await session.data(for: request)
    } catch {
        throw APIError.networkError(error)
    }
    if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
        let body = String(data: data, encoding: .utf8) ?? ""
        throw APIError.httpError(statusCode: http.statusCode, body: body)
    }
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
swift test --filter WordPressClientTests 2>&1 | tail -15
```

Expected output:
```
✔ Test trashPostSendsDeleteRequest() passed
✔ Test trashPostThrowsOnHTTPError() passed
✔ Test trashPageSendsDeleteRequest() passed
✔ Suite WordPressClientTests passed after ...
✔ Test run with 5 tests passed
```

- [ ] **Step 5: Commit**

```bash
git add Sources/WPWriterKit/API/WordPressClient.swift Tests/WPWriterTests/WordPressClientTests.swift
git commit -m "feat: add trashPost/trashPage to WordPressClient"
```

---

## Task 2: Wire up delete UI in `SidebarView`

**Files:**
- Modify: `Sources/WPWriterKit/Views/Sidebar/SidebarView.swift`

No automated tests for SwiftUI views — verified by running the app.

- [ ] **Step 1: Add two `@State` properties to `SidebarView`**

In `SidebarView.swift`, after the existing `@EnvironmentObject private var services: AppServices` line, add:

```swift
@State private var itemPendingDelete: PostItem? = nil
@State private var deleteError: String? = nil
```

- [ ] **Step 2: Add `.contextMenu` to each row button**

In `SidebarView.swift`, locate the `Button { appState.selectedItem = item }` inside `ForEach`. It currently ends with `.buttonStyle(.plain)`. Add `.contextMenu` after `.buttonStyle(.plain)`:

```swift
.buttonStyle(.plain)
.contextMenu {
    Button(role: .destructive) {
        itemPendingDelete = item
    } label: {
        switch item {
        case .remote: Label("Move to Trash", systemImage: "trash")
        case .local:  Label("Delete Draft", systemImage: "trash")
        }
    }
}
```

- [ ] **Step 3: Add confirmation and error alerts to the outer `VStack`**

In `SidebarView.swift`, locate `VStack(spacing: 0) {` — this is the outermost `VStack` in `body`. Find its closing `.background(Color.wpSidebarBg.ignoresSafeArea())` modifier and append the two alerts after it:

```swift
.alert(
    "Confirm Delete",
    isPresented: Binding(
        get: { itemPendingDelete != nil },
        set: { if !$0 { itemPendingDelete = nil } }
    ),
    presenting: itemPendingDelete
) { item in
    Button("Cancel", role: .cancel) { itemPendingDelete = nil }
    Button(deleteActionLabel(for: item), role: .destructive) {
        let target = item
        itemPendingDelete = nil
        Task { await performDelete(target) }
    }
} message: { item in
    Text(deleteMessage(for: item))
}
.alert(
    "Delete Failed",
    isPresented: Binding(
        get: { deleteError != nil },
        set: { if !$0 { deleteError = nil } }
    )
) {
    Button("OK", role: .cancel) { deleteError = nil }
} message: {
    Text(deleteError ?? "")
}
```

- [ ] **Step 4: Add helper methods and `performDelete` to `SidebarView`**

At the bottom of `SidebarView`, before the closing `}` of the struct, add:

```swift
private func deleteActionLabel(for item: PostItem) -> String {
    switch item {
    case .remote: return "Move to Trash"
    case .local:  return "Delete"
    }
}

private func deleteMessage(for item: PostItem) -> String {
    switch item {
    case .remote: return ""\(item.title)" will be moved to the WordPress Trash."
    case .local:  return ""\(item.title)" will be permanently deleted."
    }
}

private func performDelete(_ item: PostItem) async {
    do {
        switch item {
        case .remote(let post):
            guard let creds = appState.credentials else { return }
            let client = WordPressClient(credentials: creds)
            if post.type == "page" {
                try await client.trashPage(id: post.id)
                appState.pages.removeAll { $0.id == post.id }
            } else {
                try await client.trashPost(id: post.id)
                appState.posts.removeAll { $0.id == post.id }
            }
        case .local(let draft):
            try services.draftStore.delete(id: draft.id)
            appState.localDrafts.removeAll { $0.id == draft.id }
        }
        if appState.selectedItem == item {
            appState.selectedItem = nil
        }
    } catch {
        deleteError = error.localizedDescription
    }
}
```

- [ ] **Step 5: Build and verify**

```bash
./build.sh 2>&1 | tail -5
```

Expected: `Build complete!` (no errors or warnings)

- [ ] **Step 6: Manual test — local draft delete**
  1. `open WPWriter.app`
  2. Switch to the **Drafts** section in the sidebar
  3. Create a new draft with **⌘N**
  4. Right-click the new draft row → "Delete Draft" appears in context menu
  5. Click it → confirmation alert appears: "Confirm Delete" with message naming the draft
  6. Click "Delete" → draft disappears from the list, editor goes blank
  7. Right-click a different draft → click "Cancel" → draft remains in list

- [ ] **Step 7: Manual test — remote post trash**
  1. Switch to the **Posts** section
  2. Right-click any post → "Move to Trash" appears
  3. Click it → confirmation alert: message says "will be moved to the WordPress Trash."
  4. Click "Move to Trash" → post disappears from sidebar
  5. Open WordPress admin → Trash — confirm the post is there

- [ ] **Step 8: Manual test — error handling**
  1. Disconnect from network (or temporarily change credentials to an invalid password in Preferences)
  2. Right-click a post → "Move to Trash" → confirm
  3. An error alert should appear with the failure message; the post remains in the list

- [ ] **Step 9: Commit**

```bash
git add Sources/WPWriterKit/Views/Sidebar/SidebarView.swift
git commit -m "feat: add right-click delete for posts, pages, and local drafts"
```
