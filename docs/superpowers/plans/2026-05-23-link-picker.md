# Link Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bare NSAlert URL prompt with a WordPress-style popover that lets users search posts, pages, categories, tags, and media when inserting links in the Tiptap editor.

**Architecture:** Clicking the Link toolbar button sends a `showLinkPicker` message from JS to Swift with the current href and the button's bounding rect. Swift converts those coordinates and shows an `NSPopover` containing a SwiftUI `LinkPickerView`. The picker searches the WordPress API via a closure threaded down from `PostEditorView` → `EditorView` → `EditorCoordinator`, keeping each layer decoupled. On confirm/remove, Swift calls `applyLink(url)` or `removeLink()` back into the editor JS.

**Tech Stack:** Swift 6, SwiftUI, WKWebView, `NSPopover`+`NSHostingController`, WordPress REST API (`/wp/v2/search`, `/wp/v2/media`), Swift Testing + `MockURLProtocol` for unit tests.

---

### Task 1: `LinkSearchResult` model

**Files:**
- Create: `Sources/WPWriterKit/API/Models/LinkSearchResult.swift`

- [ ] **Step 1: Create the model file**

```swift
import Foundation

public enum LinkResultType: String, Sendable {
    case post, page, category, tag, media

    public var badge: String {
        switch self {
        case .post:     return "Post"
        case .page:     return "Page"
        case .category: return "Category"
        case .tag:      return "Tag"
        case .media:    return "Media"
        }
    }
}

public struct LinkSearchResult: Identifiable, Sendable {
    public let id: String   // e.g. "post-42", "category-7" — avoids collisions across types
    public let wpId: Int
    public let title: String
    public let url: String
    public let type: LinkResultType
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
./build.sh 2>&1 | tail -5
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/WPWriterKit/API/Models/LinkSearchResult.swift
git commit -m "feat: add LinkSearchResult model"
```

---

### Task 2: `WordPressClient.searchLinks`

**Files:**
- Modify: `Sources/WPWriterKit/API/WordPressClient.swift`
- Modify: `Tests/WPWriterTests/WordPressClientTests.swift`

The WordPress `/wp/v2/search` endpoint returns objects where `title` is a **plain string** (not a `{ rendered: "..." }` object like posts). The `/wp/v2/media` endpoint continues to use the existing `WPMedia` type.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/WPWriterTests/WordPressClientTests.swift`, inside the `WordPressClientTests` struct:

```swift
@Test func searchLinksReturnsMergedResults() async throws {
    MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        let path = request.url?.path ?? ""
        let query = request.url?.query ?? ""

        if path.contains("/search") && query.contains("type=post") {
            let json = """
            [{"id":1,"title":"Hello Post","url":"https://example.com/hello","type":"post","subtype":"post"},
             {"id":2,"title":"About Page","url":"https://example.com/about","type":"post","subtype":"page"}]
            """.data(using: .utf8)!
            return (response, json)
        } else if path.contains("/search") && query.contains("type=term") {
            let json = """
            [{"id":3,"title":"Tech","url":"https://example.com/category/tech","type":"term","subtype":"category"},
             {"id":4,"title":"swift","url":"https://example.com/tag/swift","type":"term","subtype":"tag"}]
            """.data(using: .utf8)!
            return (response, json)
        } else if path.contains("/media") {
            let json = """
            [{"id":5,"title":{"rendered":"photo.jpg"},"source_url":"https://example.com/wp-content/uploads/photo.jpg",
              "media_type":"image","mime_type":"image/jpeg","link":"https://example.com/?attachment_id=5","date":"2024-01-01T00:00:00"}]
            """.data(using: .utf8)!
            return (response, json)
        }
        return (response, "[]".data(using: .utf8)!)
    }

    let results = try await client.searchLinks(query: "hello")
    #expect(results.count == 5)
    #expect(results[0].type == .post)
    #expect(results[0].title == "Hello Post")
    #expect(results[0].id == "post-1")
    #expect(results[1].type == .page)
    #expect(results[2].type == .category)
    #expect(results[3].type == .tag)
    #expect(results[4].type == .media)
    #expect(results[4].url == "https://example.com/wp-content/uploads/photo.jpg")
}

@Test func searchLinksIgnoresSubrequestFailures() async throws {
    MockURLProtocol.requestHandler = { request in
        let path = request.url?.path ?? ""
        let query = request.url?.query ?? ""
        if path.contains("/search") && query.contains("type=post") {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let json = """
            [{"id":1,"title":"Hello","url":"https://example.com/hello","type":"post","subtype":"post"}]
            """.data(using: .utf8)!
            return (response, json)
        }
        // term and media endpoints fail
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil
        )!
        return (response, Data())
    }

    let results = try await client.searchLinks(query: "hello")
    #expect(results.count == 1)
    #expect(results[0].type == .post)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "searchLinks" 2>&1 | tail -10
```
Expected: errors about `searchLinks` not existing on `WordPressClient`.

- [ ] **Step 3: Add the private `WPSearchItem` decode type and `searchLinks` method**

Add a new `// MARK: - Search` section to `Sources/WPWriterKit/API/WordPressClient.swift`, just before `// MARK: - Helpers`:

```swift
// MARK: - Search

private struct WPSearchItem: Decodable {
    let id: Int
    let title: String   // plain string in /wp/v2/search (not a rendered object)
    let url: String
    let type: String    // "post" or "term"
    let subtype: String // "post", "page", "category", "tag"
}

public func searchLinks(query: String) async throws -> [LinkSearchResult] {
    let postsURL = try endpoint("search", query: [
        "search": query, "type": "post", "subtype": "post,page", "per_page": "5",
    ])
    let termsURL = try endpoint("search", query: [
        "search": query, "type": "term", "subtype": "category,tag", "per_page": "5",
    ])
    let mediaURL = try endpoint("media", query: [
        "search": query, "per_page": "3",
    ])

    async let postFetch: [WPSearchItem] = get(postsURL)
    async let termFetch: [WPSearchItem] = get(termsURL)
    async let mediaFetch: [WPMedia] = get(mediaURL)

    let posts  = (try? await postFetch)  ?? []
    let terms  = (try? await termFetch)  ?? []
    let medias = (try? await mediaFetch) ?? []

    var results: [LinkSearchResult] = []

    for item in posts {
        let type: LinkResultType = item.subtype == "page" ? .page : .post
        results.append(LinkSearchResult(
            id: "\(type.rawValue)-\(item.id)",
            wpId: item.id, title: item.title, url: item.url, type: type
        ))
    }
    for item in terms {
        let type: LinkResultType = item.subtype == "tag" ? .tag : .category
        results.append(LinkSearchResult(
            id: "\(type.rawValue)-\(item.id)",
            wpId: item.id, title: item.title, url: item.url, type: type
        ))
    }
    for item in medias {
        results.append(LinkSearchResult(
            id: "media-\(item.id)",
            wpId: item.id, title: item.title.rendered, url: item.sourceURL, type: .media
        ))
    }

    return results
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "searchLinks" 2>&1 | tail -10
```
Expected: `Test run with 2 tests passed.`

- [ ] **Step 5: Commit**

```bash
git add Sources/WPWriterKit/API/WordPressClient.swift Tests/WPWriterTests/WordPressClientTests.swift
git commit -m "feat: add WordPressClient.searchLinks"
```

---

### Task 3: `LinkPickerView`

**Files:**
- Create: `Sources/WPWriterKit/Views/Editor/LinkPickerView.swift`

The view has a single text field that doubles as URL entry and search trigger. Typing a URL-like string (starts with `http://`, `https://`, `/`, or `#`) skips search. Any other text triggers a debounced 300 ms search via the `onSearch` closure. Clicking a result fills the field; Apply confirms; Remove removes the link.

- [ ] **Step 1: Create `LinkPickerView.swift`**

```swift
import SwiftUI
import AppKit

struct LinkPickerView: View {
    let currentHref: String
    let onApply: (String) -> Void
    let onRemove: () -> Void
    let onSearch: (String) async throws -> [LinkSearchResult]

    @State private var fieldText: String
    @State private var results: [LinkSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    init(
        currentHref: String,
        onApply: @escaping (String) -> Void,
        onRemove: @escaping () -> Void,
        onSearch: @escaping (String) async throws -> [LinkSearchResult]
    ) {
        self.currentHref = currentHref
        self.onApply = onApply
        self.onRemove = onRemove
        self.onSearch = onSearch
        self._fieldText = State(initialValue: currentHref)
    }

    private var looksLikeURL: Bool {
        fieldText.hasPrefix("http://") || fieldText.hasPrefix("https://")
            || fieldText.hasPrefix("/") || fieldText.hasPrefix("#")
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── URL / search field ────────────────────────
            HStack(spacing: 6) {
                TextField("Search or paste URL", text: $fieldText)
                    .textFieldStyle(.plain)
                    .onSubmit { if !fieldText.isEmpty { onApply(fieldText) } }
                if !fieldText.isEmpty {
                    Button {
                        fieldText = ""
                        results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                if isSearching {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            // ── Results ───────────────────────────────────
            if !results.isEmpty {
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { result in
                            ResultRow(result: result) {
                                fieldText = result.url
                                results = []
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            // ── Bottom buttons ────────────────────────────
            Divider()
            HStack {
                if !currentHref.isEmpty {
                    Button("Remove Link") { onRemove() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Apply Link") { onApply(fieldText) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(fieldText.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
        .onChange(of: fieldText, perform: scheduleSearch)
    }

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        if text.isEmpty || looksLikeURL {
            results = []
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await MainActor.run { isSearching = true }
            let found = (try? await onSearch(text)) ?? []
            guard !Task.isCancelled else { return }
            await MainActor.run {
                results = found
                isSearching = false
            }
        }
    }
}

private struct ResultRow: View {
    let result: LinkSearchResult
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(result.title)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer()
                Text(result.type.badge)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
./build.sh 2>&1 | tail -5
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/WPWriterKit/Views/Editor/LinkPickerView.swift
git commit -m "feat: add LinkPickerView"
```

---

### Task 4: Update `editor.html`

**Files:**
- Modify: `Sources/WPWriterKit/Resources/editor.html`

Replace the `prompt()` link command with a `showLinkPicker` message. Add `applyLink` and `removeLink` as window globals for Swift to call back.

- [ ] **Step 1: Replace the `link` command in the `COMMANDS` object**

Find this block (around line 285):
```js
      link: () => {
        const prev = editor.getAttributes('link').href || ''
        const url  = prompt('URL (leave empty to remove):', prev)
        if (url === null) return
        if (url === '') { editor.chain().focus().unsetLink().run() }
        else { editor.chain().focus().setLink({ href: url }).run() }
      },
```

Replace with:
```js
      link: () => {
        const href = editor.getAttributes('link').href || ''
        const btn  = document.querySelector('[data-cmd="link"]').getBoundingClientRect()
        const rect = { x: btn.x, y: btn.y, width: btn.width, height: btn.height }
        if (window.webkit?.messageHandlers?.showLinkPicker) {
          window.webkit.messageHandlers.showLinkPicker.postMessage({ href, rect })
        }
      },
```

- [ ] **Step 2: Add `applyLink` and `removeLink` globals**

In the `// ── Swift → JS bridge (globals) ───────────────────` section at the bottom of the `<script>` block, add after the last existing global (`window.hideDropOverlay`):

```js
    window.applyLink = url => {
      editor.chain().focus().setLink({ href: url }).run()
    }
    window.removeLink = () => {
      editor.chain().focus().unsetLink().run()
    }
```

- [ ] **Step 3: Commit**

```bash
git add Sources/WPWriterKit/Resources/editor.html
git commit -m "feat: replace link prompt with showLinkPicker message"
```

---

### Task 5: Update `EditorCoordinator` to handle `showLinkPicker`

**Files:**
- Modify: `Sources/WPWriterKit/Views/Editor/EditorCoordinator.swift`

The coordinator needs to:
1. Store an `onSearchLinks` closure  
2. Handle the new `showLinkPicker` message — convert JS viewport coordinates to WKWebView `NSRect`, create `LinkPickerView`, show it in an `NSPopover`
3. Remove `WKUIDelegate` conformance (no longer needed)

JS viewport coordinates have `(0,0)` at top-left. `NSView` coordinates have `(0,0)` at bottom-left. Conversion: `y_nsview = webView.bounds.height - y_js - button_height`.

- [ ] **Step 1: Replace the full contents of `EditorCoordinator.swift`**

```swift
import AppKit
import SwiftUI
import WebKit

public final class EditorCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var isReady: Bool = false
    var pendingHTML: String?
    private var lastPushedHTML: String = ""
    var onContentChange: (String) -> Void
    var onReady: () -> Void
    weak var webView: WKWebView?
    var onInsertImageAt: ((Int) -> Void)?
    var onSearchLinks: ((String) async throws -> [LinkSearchResult])?
    private var linkPopover: NSPopover?

    init(onContentChange: @escaping (String) -> Void, onReady: @escaping () -> Void) {
        self.onContentChange = onContentChange
        self.onReady = onReady
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInsertMedia(_:)),
            name: .insertMediaURL,
            object: nil
        )
    }

    @objc private func handleInsertMedia(_ note: Notification) {
        guard let url = note.userInfo?["url"] as? String,
            let index = note.userInfo?["index"] as? Int
        else { return }
        insertImage(url: url, at: index)
    }

    // WKScriptMessageHandler
    public func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case "contentChanged":
            if let html = message.body as? String {
                DispatchQueue.main.async {
                    self.lastPushedHTML = html
                    self.onContentChange(html)
                }
            }
        case "editorReady":
            DispatchQueue.main.async {
                self.isReady = true
                if let html = self.pendingHTML {
                    self.setContent(html)
                    self.pendingHTML = nil
                }
                self.onReady()
            }
        case "insertImageAtIndex":
            if let index = message.body as? Int {
                DispatchQueue.main.async { self.onInsertImageAt?(index) }
            }
        case "showLinkPicker":
            guard
                let body    = message.body as? [String: Any],
                let href    = body["href"] as? String,
                let rectMap = body["rect"] as? [String: Any],
                let x = rectMap["x"] as? Double,
                let y = rectMap["y"] as? Double,
                let w = rectMap["width"] as? Double,
                let h = rectMap["height"] as? Double,
                let wv = webView
            else { return }
            DispatchQueue.main.async { self.showLinkPicker(href: href, jsRect: (x, y, w, h), in: wv) }
        default:
            break
        }
    }

    private func showLinkPicker(href: String, jsRect: (x: Double, y: Double, w: Double, h: Double), in wv: WKWebView) {
        linkPopover?.close()

        // WKWebView is flipped (isFlipped == true): origin is top-left, Y increases downward —
        // same as JS getBoundingClientRect(), so no coordinate conversion is needed.
        let nsRect = NSRect(x: jsRect.x, y: jsRect.y, width: jsRect.w, height: jsRect.h)

        let pickerView = LinkPickerView(
            currentHref: href,
            onApply: { [weak self] url in
                self?.linkPopover?.close()
                guard
                    let jsonData = try? JSONEncoder().encode(url),
                    let jsonStr  = String(data: jsonData, encoding: .utf8)
                else { return }
                self?.webView?.evaluateJavaScript("applyLink(\(jsonStr))", completionHandler: nil)
            },
            onRemove: { [weak self] in
                self?.linkPopover?.close()
                self?.webView?.evaluateJavaScript("removeLink()", completionHandler: nil)
            },
            onSearch: { [weak self] query in
                guard let search = self?.onSearchLinks else { return [] }
                return try await search(query)
            }
        )

        let hosting = NSHostingController(rootView: pickerView)
        let popover = NSPopover()
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.show(relativeTo: nsRect, of: wv, preferredEdge: .maxY)
        linkPopover = popover
    }

    func insertImage(url: String, at index: Int) {
        guard let wv = webView else { return }
        guard let jsonURL = try? JSONEncoder().encode(url),
            let urlStr = String(data: jsonURL, encoding: .utf8)
        else { return }
        wv.evaluateJavaScript("insertImageAt(\(index), \(urlStr))", completionHandler: nil)
    }

    // WKNavigationDelegate
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyColorScheme()
    }

    func setContent(_ html: String) {
        guard let wv = webView else { return }
        if isReady {
            guard html != lastPushedHTML else { return }
            lastPushedHTML = html
            guard let jsonHTML = try? JSONEncoder().encode(html),
                let htmlStr = String(data: jsonHTML, encoding: .utf8)
            else { return }
            wv.evaluateJavaScript("setContent(\(htmlStr))", completionHandler: nil)
        } else {
            pendingHTML = html
        }
    }

    func applyColorScheme() {
        guard let wv = webView else { return }
        let isDark = wv.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        wv.evaluateJavaScript("setDarkMode(\(isDark))", completionHandler: nil)
    }
}

extension Notification.Name {
    static let insertMediaURL = Notification.Name("WPWriter.insertMediaURL")
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/WPWriterKit/Views/Editor/EditorCoordinator.swift
git commit -m "feat: handle showLinkPicker in EditorCoordinator"
```

---

### Task 6: Update `EditorView` and `PostEditorView`

**Files:**
- Modify: `Sources/WPWriterKit/Views/Editor/EditorView.swift`
- Modify: `Sources/WPWriterKit/Views/Editor/PostEditorView.swift`

Add `onSearchLinks` to `EditorView`, remove `uiDelegate`, and wire the closure from `PostEditorView`.

- [ ] **Step 1: Replace the full contents of `EditorView.swift`**

```swift
import SwiftUI
import WebKit

public struct EditorView: NSViewRepresentable {
    @Binding var html: String
    var onContentChange: (String) -> Void
    var onInsertImageAt: ((Int) -> Void)?
    var onImageFilesDropped: (([URL]) -> Void)?
    var onSearchLinks: ((String) async throws -> [LinkSearchResult])?

    public init(
        html: Binding<String>,
        onContentChange: @escaping (String) -> Void,
        onInsertImageAt: ((Int) -> Void)? = nil,
        onImageFilesDropped: (([URL]) -> Void)? = nil,
        onSearchLinks: ((String) async throws -> [LinkSearchResult])? = nil
    ) {
        self._html = html
        self.onContentChange = onContentChange
        self.onInsertImageAt = onInsertImageAt
        self.onImageFilesDropped = onImageFilesDropped
        self.onSearchLinks = onSearchLinks
    }

    public func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(onContentChange: onContentChange, onReady: {})
    }

    public func makeNSView(context: Context) -> DroppableWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "contentChanged")
        config.userContentController.add(context.coordinator, name: "editorReady")
        config.userContentController.add(context.coordinator, name: "insertImageAtIndex")
        config.userContentController.add(context.coordinator, name: "showLinkPicker")

        let webView = DroppableWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.onImageFilesDropped = onImageFilesDropped
        context.coordinator.webView = webView
        context.coordinator.onInsertImageAt = onInsertImageAt
        context.coordinator.onSearchLinks = onSearchLinks
        loadEditorHTML(in: webView)
        return webView
    }

    public func updateNSView(_ nsView: DroppableWebView, context: Context) {
        context.coordinator.setContent(html)
        context.coordinator.onSearchLinks = onSearchLinks
        nsView.onImageFilesDropped = onImageFilesDropped
    }

    private func loadEditorHTML(in webView: WKWebView) {
        guard let htmlURL = Bundle.main.url(forResource: "editor", withExtension: "html"),
            let html = try? String(contentsOf: htmlURL, encoding: .utf8)
        else { return }
        // Use an https base URL so the page has a non-null origin, allowing
        // CORS-enabled ES module imports from esm.sh to succeed (file:// is
        // treated as a null origin and is blocked by WebKit's cross-origin policy).
        webView.loadHTMLString(html, baseURL: URL(string: "https://app.wpwriter/"))
    }
}
```

- [ ] **Step 2: Add `onSearchLinks` to the `EditorView(...)` call in `PostEditorView.swift`**

Find the `EditorView(` call (around line 32) in `PostEditorView.swift`. It currently ends with:
```swift
                    onImageFilesDropped: { urls in
                        Task { await handleDroppedImages(urls) }
                    }
```

Add the new parameter after `onImageFilesDropped`:
```swift
                    onImageFilesDropped: { urls in
                        Task { await handleDroppedImages(urls) }
                    },
                    onSearchLinks: { query in
                        guard let creds = appState.credentials else { return [] }
                        return try await WordPressClient(credentials: creds).searchLinks(query: query)
                    }
```

- [ ] **Step 3: Build to verify everything compiles**

```bash
./build.sh 2>&1 | tail -5
```
Expected: `Build complete!`

- [ ] **Step 4: Run the full test suite**

```bash
swift test 2>&1 | tail -10
```
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/WPWriterKit/Views/Editor/EditorView.swift Sources/WPWriterKit/Views/Editor/PostEditorView.swift
git commit -m "feat: wire onSearchLinks through EditorView to coordinator"
```

---

### Task 7: Manual verification

**Files:** None — build, run, test.

- [ ] **Step 1: Rebuild and reopen**

```bash
pkill -x WPWriter 2>/dev/null; sleep 1; ./build.sh && open WPWriter.app
```

- [ ] **Step 2: Verify — adding a new link**

1. Open a post/page and type some text
2. Select some words
3. Click the **Link** toolbar button
4. Confirm a popover appears anchored below the button
5. Type a search term (not a URL) — confirm results appear after ~300ms
6. Click a result — confirm the URL field fills (popover stays open)
7. Click **Apply Link** — confirm the selected text becomes a link and the popover closes
8. Confirm no "Remove Link" button is visible when opening with no existing link

- [ ] **Step 3: Verify — editing an existing link**

1. Place cursor inside the link you just created
2. Click the **Link** button
3. Confirm the popover opens with the existing URL pre-filled
4. Confirm **Remove Link** button is visible
5. Click **Remove Link** — confirm the link is removed and popover closes

- [ ] **Step 4: Verify — direct URL entry**

1. Select text, click Link
2. Paste `https://apple.com` — confirm no search fires (no results list)
3. Click **Apply Link** — confirm the link is set

- [ ] **Step 5: Verify — escape / click outside**

1. Open the link picker
2. Press Escape or click somewhere in the editor
3. Confirm the popover closes without changing anything

- [ ] **Step 6: Commit if any tweaks were needed**

```bash
git add -p && git commit -m "fix: link picker polish"
```

---

### Task 8: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Remove the completed TODO and add a gotcha entry**

In `CLAUDE.md`, in the `## TODO` section, remove:
```
- [ ] Link button in Tiptap toolbar does not work
```

In the `## Known gotchas` section, add:

```
- **Link picker popover** — The Link toolbar button sends a `showLinkPicker` WKScriptMessage with `{ href, rect }` (JS viewport coords). `EditorCoordinator` converts the rect to NSView coords and shows an `NSPopover` containing `LinkPickerView`. On confirm/remove, Swift calls `window.applyLink(url)` / `window.removeLink()` back into the editor. `onSearchLinks` is a closure threaded from `PostEditorView` → `EditorView` → `EditorCoordinator` so the editor layer stays decoupled from `WordPressClient`.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: mark link picker done, add gotcha note"
```
