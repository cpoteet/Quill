# Media Panel Native Conversion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert Quill's Media section to the same three-column native shape as Posts — a filter sidebar, an `NSCollectionView` gallery, and an inspector — and fix the five defects the previous native-ui branch left behind.

**Architecture:** The media list moves out of the sidebar and becomes a gallery in the content column, backed by `NSCollectionView` through an `NSViewRepresentable` bridge. The sidebar holds type filters that map to the WordPress `media_type` query parameter. `MediaDetailView` loses its image half and becomes the inspector.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSCollectionView`, `NSHostingView`), swift-testing, WordPress REST API.

**Spec:** `docs/superpowers/specs/2026-09-19-media-panel-native-design.md`

## Global Constraints

- Swift 6.3.1, macOS 27 only. Do not add `@available` gates.
- Build and run after every code change, exactly this:
  `osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app`
- No new files in `Sources/QuillKit/Resources/`. If that changes, `build.sh` needs its own `cp` line per file or the file 404s at runtime.
- Comments: default to none. One line maximum when naming cannot carry the meaning. Never restate what the code does.
- Use `Color.accentColor` for selection and focus. Never use it for a semantic colour.
- `.textFieldStyle(.plain)` is the house style for every text field.
- **Commits: the project rule is "do not commit unless the user explicitly asks."** Each task below ends with a commit step for completeness. The executor must ask before running it.

---

### Task 1: Client filter and search parameters

**Files:**
- Modify: `Sources/QuillKit/API/WordPressClient.swift:113-119`
- Test: `Tests/QuillTests/WordPressClientTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `WordPressClient.fetchMedia(page:perPage:mediaType:search:) async throws -> [WPMedia]`. All four parameters have defaults. `mediaType` and `search` are `String?` defaulting to `nil`.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/QuillTests/WordPressClientTests.swift`, inside the `WordPressClientTests` suite.

```swift
// MARK: - Media filters

@Test func fetchMediaOmitsFilterParamsByDefault() async throws {
    var capturedRequest: URLRequest?
    MockURLProtocol.requestHandler = { request in
        capturedRequest = request
        return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                httpVersion: nil, headerFields: nil)!,
                "[]".data(using: .utf8)!)
    }
    _ = try await client.fetchMedia()
    let query = capturedRequest?.url?.query ?? ""
    #expect(query.contains("context=edit"))
    #expect(query.contains("media_type=") == false)
    #expect(query.contains("search=") == false)
}

@Test func fetchMediaSendsMediaTypeAndSearch() async throws {
    var capturedRequest: URLRequest?
    MockURLProtocol.requestHandler = { request in
        capturedRequest = request
        return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                httpVersion: nil, headerFields: nil)!,
                "[]".data(using: .utf8)!)
    }
    _ = try await client.fetchMedia(mediaType: "image", search: "sunset")
    let query = capturedRequest?.url?.query ?? ""
    #expect(query.contains("media_type=image"))
    #expect(query.contains("search=sunset"))
}

@Test func fetchMediaTreatsEmptyFilterStringsAsAbsent() async throws {
    var capturedRequest: URLRequest?
    MockURLProtocol.requestHandler = { request in
        capturedRequest = request
        return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                httpVersion: nil, headerFields: nil)!,
                "[]".data(using: .utf8)!)
    }
    _ = try await client.fetchMedia(mediaType: "", search: "")
    let query = capturedRequest?.url?.query ?? ""
    #expect(query.contains("media_type=") == false)
    #expect(query.contains("search=") == false)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter WordPressClientTests`
Expected: FAIL. `fetchMedia` has no `mediaType` or `search` argument, so this is a compile error.

- [ ] **Step 3: Write the implementation**

Replace `fetchMedia` at `Sources/QuillKit/API/WordPressClient.swift:113`.

```swift
public func fetchMedia(
    page: Int = 1,
    perPage: Int = 50,
    mediaType: String? = nil,
    search: String? = nil
) async throws -> [WPMedia] {
    var query = ["per_page": "\(perPage)", "page": "\(page)", "context": "edit"]
    if let mediaType, !mediaType.isEmpty { query["media_type"] = mediaType }
    if let search, !search.isEmpty { query["search"] = search }
    let url = try endpoint("media", query: query)
    return try await get(url)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter WordPressClientTests`
Expected: PASS, 54 tests in this suite.

- [ ] **Step 5: Confirm the existing callers still compile**

Run: `swift build`
Expected: no errors. `MediaPickerView.swift:112`, `MediaPickerView.swift:126`, `GallerySheet.swift:367` and `GallerySheet.swift:381` call `fetchMedia(page:perPage:)` and must keep working unchanged.

- [ ] **Step 6: Commit** (ask the user first)

```bash
git add Sources/QuillKit/API/WordPressClient.swift Tests/QuillTests/WordPressClientTests.swift
git commit -m "feat: add media_type and search filters to fetchMedia"
```

---

### Task 2: MediaFilter type and AppState fields

**Files:**
- Create: `Sources/QuillKit/App/MediaFilter.swift`
- Modify: `Sources/QuillKit/App/AppState.swift:76-83`
- Test: `Tests/QuillTests/MediaFilterTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `MediaFilter`, a `public enum` with cases `all`, `images`, `documents`, `audio`, `video`. Members: `title: String`, `icon: String`, `mediaTypeParameter: String?`. Also `AppState.mediaFilter: MediaFilter` and `AppState.mediaSearchText: String`.

- [ ] **Step 1: Write the failing test**

Create `Tests/QuillTests/MediaFilterTests.swift`.

```swift
import Testing
@testable import QuillKit

@Suite struct MediaFilterTests {
    @Test func allSendsNoMediaTypeParameter() {
        #expect(MediaFilter.all.mediaTypeParameter == nil)
    }

    @Test func eachFilterMapsToItsWordPressMediaType() {
        #expect(MediaFilter.images.mediaTypeParameter == "image")
        #expect(MediaFilter.documents.mediaTypeParameter == "application")
        #expect(MediaFilter.audio.mediaTypeParameter == "audio")
        #expect(MediaFilter.video.mediaTypeParameter == "video")
    }

    @Test func everyFilterHasATitleAndAnIcon() {
        for filter in MediaFilter.allCases {
            #expect(filter.title.isEmpty == false)
            #expect(filter.icon.isEmpty == false)
        }
    }

    @Test func allCasesAreInSidebarOrder() {
        #expect(MediaFilter.allCases == [.all, .images, .documents, .audio, .video])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter MediaFilterTests`
Expected: FAIL. `MediaFilter` does not exist, so this is a compile error.

- [ ] **Step 3: Write the implementation**

Create `Sources/QuillKit/App/MediaFilter.swift`.

```swift
import Foundation

public enum MediaFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case images
    case documents
    case audio
    case video

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "All Media"
        case .images: return "Images"
        case .documents: return "Documents"
        case .audio: return "Audio"
        case .video: return "Video"
        }
    }

    public var icon: String {
        switch self {
        case .all: return "photo.on.rectangle.angled"
        case .images: return "photo"
        case .documents: return "doc"
        case .audio: return "waveform"
        case .video: return "film"
        }
    }

    /// nil means the request sends no media_type parameter at all.
    public var mediaTypeParameter: String? {
        switch self {
        case .all: return nil
        case .images: return "image"
        case .documents: return "application"
        case .audio: return "audio"
        case .video: return "video"
        }
    }
}
```

- [ ] **Step 4: Add the AppState fields**

In `Sources/QuillKit/App/AppState.swift`, beside the existing media properties at line 76.

```swift
@Published public var mediaFilter: MediaFilter = .all
@Published public var mediaSearchText: String = ""
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter MediaFilterTests`
Expected: PASS, 4 tests.

- [ ] **Step 6: Verify the media_type values against a live site**

The spec requires this. Do not skip it. Run each of these against the user's WordPress site and confirm a 200 response rather than a 400.

```bash
curl -s -o /dev/null -w "%{http_code}\n" -u "USER:APP_PASSWORD" \
  "https://SITE/wp-json/wp/v2/media?per_page=1&media_type=application"
```

Repeat for `image`, `audio` and `video`. A 400 response means WordPress rejects that value and the table in `MediaFilter` is wrong. Report the result before continuing.

- [ ] **Step 7: Commit** (ask the user first)

```bash
git add Sources/QuillKit/App/MediaFilter.swift Sources/QuillKit/App/AppState.swift Tests/QuillTests/MediaFilterTests.swift
git commit -m "feat: add MediaFilter and its AppState fields"
```

---

### Task 3: The AppKit gallery bridge

**Files:**
- Create: `Sources/QuillKit/Views/Media/MediaGalleryView.swift`
- Test: none. An `NSViewRepresentable` cannot be unit tested. Verification is by build and by hand in Task 6.

**Interfaces:**
- Consumes: `WPMedia` from `API/Models/WPMedia.swift`.
- Produces:
  - `MediaGalleryView: NSViewRepresentable` with the initialiser
    `MediaGalleryView(items: [WPMedia], selection: Binding<WPMedia?>, onNeedMore: @escaping () -> Void, onActivate: @escaping (WPMedia) -> Void)`.
  - `MediaCollectionView: NSCollectionView`, a subclass exposing
    `var onContextMenu: ((WPMedia) -> NSMenu?)?`. Task 7 fills this in.
  - `MediaGalleryItem: NSCollectionViewItem` with
    `static let identifier: NSUserInterfaceItemIdentifier` and
    `func configure(with media: WPMedia)`.

This task creates the file but nothing uses it yet. The app is unchanged after it.

- [ ] **Step 1: Write the thumbnail view**

Create `Sources/QuillKit/Views/Media/MediaGalleryView.swift` with this first.

```swift
import AppKit
import SwiftUI

struct MediaThumbnail: View {
    let media: WPMedia
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { content }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color(.separatorColor),
                                lineWidth: isSelected ? 3 : 0.5)
                }
            Text(displayName)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(4)
    }

    private var displayName: String {
        if !media.title.rendered.isEmpty { return media.title.decodedTitle }
        return URL(string: media.sourceURL)?.lastPathComponent ?? ""
    }

    @ViewBuilder
    private var content: some View {
        if media.mediaType == "image" {
            AsyncImage(url: URL(string: media.thumbnailURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    placeholder(symbol: "photo")
                @unknown default:
                    placeholder(symbol: "photo")
                }
            }
            .clipped()
        } else {
            placeholder(symbol: media.mimeType == "application/pdf" ? "doc.richtext.fill" : "doc.fill")
        }
    }

    private func placeholder(symbol: String) -> some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 24))
                    .foregroundStyle(.tertiary)
            }
    }
}
```

- [ ] **Step 2: Write the collection view item**

Append to the same file.

```swift
final class MediaGalleryItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("MediaGalleryItem")

    private var media: WPMedia?
    private var host: NSHostingView<MediaThumbnail>?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override var isSelected: Bool {
        didSet { refresh() }
    }

    func configure(with media: WPMedia) {
        self.media = media
        refresh()
    }

    private func refresh() {
        guard let media else { return }
        let root = MediaThumbnail(media: media, isSelected: isSelected)
        if let host {
            host.rootView = root
            return
        }
        let newHost = NSHostingView(rootView: root)
        newHost.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(newHost)
        NSLayoutConstraint.activate([
            newHost.topAnchor.constraint(equalTo: view.topAnchor),
            newHost.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            newHost.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            newHost.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host = newHost
    }
}
```

- [ ] **Step 3: Write the collection view subclass**

Append to the same file. The subclass exists so a right-click can resolve which item sits under the pointer. Task 7 supplies `onContextMenu`.

```swift
final class MediaCollectionView: NSCollectionView {
    var itemAt: ((NSPoint) -> WPMedia?)?
    var onContextMenu: ((WPMedia) -> NSMenu?)?
    var onActivate: ((WPMedia) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let media = itemAt?(point) else { return nil }
        if let indexPath = indexPathForItem(at: point) {
            selectItems(at: [indexPath], scrollPosition: [])
            delegate?.collectionView?(self, didSelectItemsAt: [indexPath])
        }
        return onContextMenu?(media)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard event.clickCount == 2 else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let media = itemAt?(point) { onActivate?(media) }
    }
}
```

- [ ] **Step 4: Write the representable and its coordinator**

Append to the same file.

```swift
struct MediaGalleryView: NSViewRepresentable {
    let items: [WPMedia]
    @Binding var selection: WPMedia?
    var onNeedMore: () -> Void
    var onActivate: (WPMedia) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 150, height: 172)
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let collectionView = MediaCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(MediaGalleryItem.self,
                                forItemWithIdentifier: MediaGalleryItem.identifier)
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.itemAt = { [weak collectionView] point in
            guard let collectionView,
                  let indexPath = collectionView.indexPathForItem(at: point) else { return nil }
            return context.coordinator.items[safe: indexPath.item]
        }
        collectionView.onActivate = { media in context.coordinator.parent.onActivate(media) }

        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true

        context.coordinator.collectionView = collectionView
        context.coordinator.scrollView = scrollView
        context.coordinator.observeScrolling()
        context.coordinator.items = items
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(items: items, selection: selection)
    }

    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var parent: MediaGalleryView
        var items: [WPMedia] = []
        weak var collectionView: MediaCollectionView?
        weak var scrollView: NSScrollView?
        private var isApplyingSelection = false

        init(_ parent: MediaGalleryView) {
            self.parent = parent
        }

        func observeScrolling() {
            guard let contentView = scrollView?.contentView else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: contentView
            )
        }

        @objc private func boundsDidChange() {
            guard let scrollView, let documentView = scrollView.documentView else { return }
            let visibleMaxY = scrollView.contentView.bounds.maxY
            let threshold = documentView.bounds.height - scrollView.contentView.bounds.height * 1.5
            guard visibleMaxY >= threshold else { return }
            parent.onNeedMore()
        }

        func apply(items newItems: [WPMedia], selection: WPMedia?) {
            guard let collectionView else { return }
            if newItems.map(\.id) != items.map(\.id) {
                items = newItems
                collectionView.reloadData()
            } else {
                items = newItems
            }
            isApplyingSelection = true
            defer { isApplyingSelection = false }
            if let selection, let index = items.firstIndex(where: { $0.id == selection.id }) {
                let path = IndexPath(item: index, section: 0)
                if collectionView.selectionIndexPaths != [path] {
                    collectionView.selectItems(at: [path], scrollPosition: [])
                }
            } else if !collectionView.selectionIndexPaths.isEmpty {
                collectionView.deselectAll(nil)
            }
        }

        func collectionView(_ collectionView: NSCollectionView,
                            numberOfItemsInSection section: Int) -> Int {
            items.count
        }

        func collectionView(_ collectionView: NSCollectionView,
                            itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: MediaGalleryItem.identifier,
                                               for: indexPath)
            if let galleryItem = item as? MediaGalleryItem, let media = items[safe: indexPath.item] {
                galleryItem.configure(with: media)
            }
            return item
        }

        func collectionView(_ collectionView: NSCollectionView,
                            didSelectItemsAt indexPaths: Set<IndexPath>) {
            guard !isApplyingSelection, let first = indexPaths.first else { return }
            parent.selection = items[safe: first.item]
        }

        func collectionView(_ collectionView: NSCollectionView,
                            didDeselectItemsAt indexPaths: Set<IndexPath>) {
            guard !isApplyingSelection else { return }
            if collectionView.selectionIndexPaths.isEmpty { parent.selection = nil }
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
```

- [ ] **Step 5: Check the safe subscript does not already exist**

Run: `grep -rn "subscript(safe" Sources/QuillKit/`
Expected: one match, the one you just wrote. If there is a second, delete yours and use the existing one.

- [ ] **Step 6: Build**

Run: `swift build`
Expected: no errors. The app is unchanged, because nothing references `MediaGalleryView` yet.

- [ ] **Step 7: Commit** (ask the user first)

```bash
git add Sources/QuillKit/Views/Media/MediaGalleryView.swift
git commit -m "feat: add NSCollectionView gallery bridge for media"
```

---

### Task 4: The content column

> **Changed after execution (2026-09-19):** the search field moved to the
> sidebar. `.searchable` is no longer on `MediaLibraryView`; it is
> `.searchable(text:placement:.sidebar,prompt:)` on `MediaSidebarSection`,
> matching the post list. The spec records why.

**Files:**
- Create: `Sources/QuillKit/Views/Media/MediaLibraryView.swift`
- Test: none. Verified by hand in Task 6.

**Interfaces:**
- Consumes: `MediaGalleryView` from Task 3, `MediaFilter` from Task 2, `fetchMedia(page:perPage:mediaType:search:)` from Task 1.
- Produces: `MediaLibraryView: View`, taking no arguments and reading `AppState` from the environment. It owns paging state and the load, delete and upload actions that `MediaSidebarSection` owns today.

This task creates the file but nothing uses it yet.

- [ ] **Step 1: Write the view**

Create `Sources/QuillKit/Views/Media/MediaLibraryView.swift`. Move `loadMedia`, `loadMoreMedia`, `performDelete` and `uploadFromDisk` here from `MediaSidebarSection.swift:225-310`, changing `loadMedia` to pass the filter and search text.

```swift
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MediaLibraryView: View {
    @EnvironmentObject private var appState: AppState

    @State private var currentPage = 1
    @State private var hasMore = false
    @State private var isLoadingMore = false
    @State private var mediaPendingDelete: WPMedia?
    @State private var deleteError: String?

    private let perPage = 30

    var body: some View {
        gallery
            .searchable(text: $appState.mediaSearchText, prompt: "Search Media")
            .task(id: reloadKey) { await loadMedia() }
            .alert(
                "Delete Permanently?",
                isPresented: Binding(
                    get: { mediaPendingDelete != nil },
                    set: { if !$0 { mediaPendingDelete = nil } }
                ),
                presenting: mediaPendingDelete
            ) { media in
                Button("Cancel", role: .cancel) { mediaPendingDelete = nil }
                Button("Delete", role: .destructive) {
                    let target = media
                    mediaPendingDelete = nil
                    Task { await performDelete(target) }
                }
            } message: { media in
                let name = media.title.rendered.isEmpty ? "This item" : "\"\(media.title.decodedTitle)\""
                Text("\(name) will be permanently deleted from WordPress. This cannot be undone.")
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
    }

    private var reloadKey: String {
        "\(appState.mediaFilter.rawValue)|\(appState.mediaSearchText)"
    }

    @ViewBuilder
    private var gallery: some View {
        if !appState.mediaItems.isEmpty {
            MediaGalleryView(
                items: appState.mediaItems,
                selection: $appState.selectedMedia,
                onNeedMore: { Task { await loadMoreMedia() } },
                onActivate: { _ in }
            )
        } else if appState.hasLoadedMedia && !appState.isLoadingMedia {
            SidebarEmptyState(section: .media,
                              isSearching: !appState.mediaSearchText.isEmpty)
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
```

- [ ] **Step 2: Add the loading functions**

Append inside `MediaLibraryView`. Note the two new arguments on each `fetchMedia` call.

```swift
extension MediaLibraryView {
    func loadMedia() async {
        guard let creds = appState.credentials else {
            appState.isLoadingMedia = false
            appState.hasLoadedMedia = true
            return
        }
        if appState.mediaItems.isEmpty { appState.isLoadingMedia = true }
        appState.mediaError = nil
        currentPage = 1
        do {
            let items = try await WordPressClient(credentials: creds)
                .fetchMedia(page: 1,
                            perPage: perPage,
                            mediaType: appState.mediaFilter.mediaTypeParameter,
                            search: appState.mediaSearchText)
            appState.mediaItems = items
            hasMore = items.count == perPage
            if let sel = appState.selectedMedia, !items.contains(where: { $0.id == sel.id }) {
                appState.selectedMedia = nil
            }
            appState.hasLoadedMedia = true
            appState.isLoadingMedia = false
        } catch is CancellationError {
            appState.isLoadingMedia = false
        } catch {
            appState.mediaError = error.localizedDescription
            appState.hasLoadedMedia = true
            appState.isLoadingMedia = false
        }
    }

    func loadMoreMedia() async {
        guard hasMore, !isLoadingMore, let creds = appState.credentials else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let nextPage = currentPage + 1
        do {
            let items = try await WordPressClient(credentials: creds)
                .fetchMedia(page: nextPage,
                            perPage: perPage,
                            mediaType: appState.mediaFilter.mediaTypeParameter,
                            search: appState.mediaSearchText)
            appState.mediaItems.append(contentsOf: items)
            currentPage = nextPage
            hasMore = items.count == perPage
        } catch is CancellationError {
        } catch {
            appState.mediaError = error.localizedDescription
        }
    }

    func performDelete(_ media: WPMedia) async {
        guard let creds = appState.credentials else { return }
        do {
            try await WordPressClient(credentials: creds).deleteMedia(id: media.id)
            appState.mediaItems.removeAll { $0.id == media.id }
            if appState.selectedMedia?.id == media.id { appState.selectedMedia = nil }
        } catch {
            deleteError = error.localizedDescription
        }
    }
}
```

The `hasMore` and `isLoadingMore` guards matter. `onNeedMore` fires on every scroll notification, so without them the view issues a request per scroll event.

- [ ] **Step 3: Build**

Run: `swift build`
Expected: no errors.

- [ ] **Step 4: Commit** (ask the user first)

```bash
git add Sources/QuillKit/Views/Media/MediaLibraryView.swift
git commit -m "feat: add media library content column"
```

---

### Task 5: The large preview overlay

**Files:**
- Modify: `Sources/QuillKit/Views/Media/MediaLibraryView.swift`
- Create: `Sources/QuillKit/Views/Media/MediaPreviewOverlay.swift`
- Test: none. Verified by hand in Task 6.

**Interfaces:**
- Consumes: `MediaLibraryView` from Task 4.
- Produces: `MediaPreviewOverlay: View`, initialised as `MediaPreviewOverlay(media: WPMedia, onClose: () -> Void)`.

- [ ] **Step 1: Write the overlay**

Create `Sources/QuillKit/Views/Media/MediaPreviewOverlay.swift`.

```swift
import SwiftUI

struct MediaPreviewOverlay: View {
    let media: WPMedia
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
            content
                .padding(40)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var content: some View {
        if media.mediaType == "image" {
            AsyncImage(url: URL(string: media.sourceURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                case .failure:
                    unavailable
                default:
                    ProgressView()
                }
            }
        } else {
            unavailable
        }
    }

    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("Preview unavailable")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }
}
```

- [ ] **Step 2: Add the overlay state to MediaLibraryView**

Add this property beside the other `@State` properties.

```swift
@State private var previewedMedia: WPMedia?
```

- [ ] **Step 3: Wire the overlay into the body**

Replace `gallery` in the `body` with this, keeping every modifier that follows it unchanged.

```swift
gallery
    .overlay {
        if let previewedMedia {
            MediaPreviewOverlay(media: previewedMedia) {
                self.previewedMedia = nil
            }
        }
    }
    .onExitCommand { previewedMedia = nil }
```

- [ ] **Step 4: Wire double-click and Space**

Change `onActivate` in the `MediaGalleryView` initialiser.

```swift
onActivate: { media in previewedMedia = media }
```

Then add the Space key handler after `.onExitCommand`.

```swift
.background {
    Button("") { togglePreview() }
        .keyboardShortcut(.space, modifiers: [])
        .opacity(0)
        .accessibilityHidden(true)
}
```

And add the function to the extension.

```swift
func togglePreview() {
    if previewedMedia != nil {
        previewedMedia = nil
    } else {
        previewedMedia = appState.selectedMedia
    }
}
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: no errors.

- [ ] **Step 6: Note the risk for Task 6 testing**

The spec names this risk: the Space shortcut must not fire while the search field has focus. A `keyboardShortcut` on a hidden button is application-wide within this view. If Task 6 testing shows that typing a space in the search field opens the overlay, replace the hidden button with an `NSEvent` local monitor in `MediaCollectionView.keyDown(with:)` instead, which only fires when the collection view has focus. Report which approach ended up being used.

- [ ] **Step 7: Commit** (ask the user first)

```bash
git add Sources/QuillKit/Views/Media/MediaPreviewOverlay.swift Sources/QuillKit/Views/Media/MediaLibraryView.swift
git commit -m "feat: add large media preview overlay"
```

---

### Task 6: Switch the content column and the inspector

**Files:**
- Modify: `Sources/QuillKit/Views/Media/MediaDetailView.swift:20-30` and `:33-66`
- Modify: `Sources/QuillKit/Views/ContentView.swift:44-66`
- Test: by hand, in the running app.

**Interfaces:**
- Consumes: `MediaLibraryView` from Task 4, `MediaPreviewOverlay` from Task 5.
- Produces: `MediaDetailView` becomes the metadata panel only. Its initialiser is unchanged: `MediaDetailView(media: WPMedia, onSaveAltText: ((String) async -> Void)?)`.

After this task the app shows the new gallery. The old sidebar grid is still present and still works. That redundancy is deliberate and Task 8 removes it.

- [ ] **Step 1: Trim MediaDetailView to the metadata panel**

Replace the `body` at `MediaDetailView.swift:20`.

```swift
var body: some View {
    metadataPanel
}
```

Then delete `imagePreview` and `previewUnavailable` at `MediaDetailView.swift:33-66`. Delete the `.frame(width: 260)` from `metadataPanel`, because `.inspectorColumnWidth` now sets the width.

- [ ] **Step 2: Verify nothing else used the deleted parts**

Run: `grep -rn "imagePreview\|previewUnavailable" Sources/QuillKit/`
Expected: matches only inside `MediaPreviewOverlay.swift`, which has its own private copy. If `MediaDetailView.swift` still matches, the deletion is incomplete.

- [ ] **Step 3: Rewrite the media branch of detailContent**

Replace `ContentView.swift:46-66` with this.

```swift
if appState.selectedSection == .media {
    MediaLibraryView()
        .navigationTitle(appState.selectedMedia?.title.decodedTitle ?? "Media")
        .inspector(isPresented: Binding(
            get: { appState.selectedMedia != nil },
            set: { if !$0 { appState.selectedMedia = nil } }
        )) {
            if let media = appState.selectedMedia {
                MediaDetailView(media: media) { [media] altText in
                    guard let creds = appState.credentials else { return }
                    guard let idx = appState.mediaItems.firstIndex(where: { $0.id == media.id }) else { return }
                    do {
                        let updated = try await WordPressClient(credentials: creds)
                            .updateMediaAltText(id: media.id, altText: altText)
                        appState.mediaItems[idx] = updated
                        if appState.selectedMedia?.id == updated.id {
                            appState.selectedMedia = updated
                        }
                    } catch {
                        // Save failed silently — field retains the edited value
                    }
                }
                .id(media.id)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
            }
        }
} else if let item = appState.selectedItem {
```

Keep the existing comment on the empty `catch`. It documents a deliberate silence, which the comment policy allows.

- [ ] **Step 4: Build and run**

Run: `osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app`
Expected: the app opens. Switching to Media shows the gallery in the middle column.

- [ ] **Step 5: Test by hand**

Work through each of these in the running app. Record any failure before continuing.

1. Arrow keys move the selection left, right, up and down.
2. The inspector appears on selection and shows the right filename.
3. Editing alt text and clicking away saves, and shows "Saved".
4. Space opens the overlay. Space closes it. Escape closes it.
5. Double-clicking a thumbnail opens the overlay.
6. Typing a space in the search field does NOT open the overlay. If it does, apply the fallback in Task 5 step 6.
7. Scrolling to the bottom loads more items.
8. Deleting from the old sidebar grid removes the thumbnail from the new gallery too.
9. The gallery renders correctly in light appearance and in dark appearance. Judge colour from a native-resolution screenshot, not a downsampled one.

- [ ] **Step 6: Commit** (ask the user first)

```bash
git add Sources/QuillKit/Views/Media/MediaDetailView.swift Sources/QuillKit/Views/ContentView.swift
git commit -m "feat: show the media gallery in the content column with an inspector"
```

---

### Task 7: AppKit context menus

**Files:**
- Modify: `Sources/QuillKit/Views/Media/MediaGalleryView.swift`
- Modify: `Sources/QuillKit/Views/Media/MediaLibraryView.swift`
- Test: by hand.

**Interfaces:**
- Consumes: `MediaCollectionView.onContextMenu` from Task 3.
- Produces: `MediaGalleryView` gains one more initialiser argument,
  `onContextAction: @escaping (MediaContextAction, WPMedia) -> Void`, and a new
  `enum MediaContextAction { case copyURL, openInBrowser, delete }`.

- [ ] **Step 1: Add the action type and the menu builder**

Add to `MediaGalleryView.swift`, above `struct MediaGalleryView`.

```swift
enum MediaContextAction {
    case copyURL
    case openInBrowser
    case delete
}

final class MediaMenuTarget: NSObject {
    var media: WPMedia?
    var handler: ((MediaContextAction, WPMedia) -> Void)?

    @objc func copyURL() { fire(.copyURL) }
    @objc func openInBrowser() { fire(.openInBrowser) }
    @objc func delete(_ sender: Any?) { fire(.delete) }

    private func fire(_ action: MediaContextAction) {
        guard let media else { return }
        handler?(action, media)
    }
}
```

- [ ] **Step 2: Add the argument and build the menu**

Add the stored property to `MediaGalleryView`.

```swift
var onContextAction: (MediaContextAction, WPMedia) -> Void
```

Add the target to `Coordinator`.

```swift
let menuTarget = MediaMenuTarget()
```

In `makeNSView`, after `collectionView.onActivate` is set, add this.

```swift
context.coordinator.menuTarget.handler = { action, media in
    context.coordinator.parent.onContextAction(action, media)
}
collectionView.onContextMenu = { [weak coordinator = context.coordinator] media in
    guard let coordinator else { return nil }
    coordinator.menuTarget.media = media
    let menu = NSMenu()
    let copyItem = NSMenuItem(title: "Copy URL",
                              action: #selector(MediaMenuTarget.copyURL),
                              keyEquivalent: "")
    copyItem.target = coordinator.menuTarget
    menu.addItem(copyItem)

    if !media.link.isEmpty, URL(string: media.link) != nil {
        let openItem = NSMenuItem(title: "Open in Browser",
                                  action: #selector(MediaMenuTarget.openInBrowser),
                                  keyEquivalent: "")
        openItem.target = coordinator.menuTarget
        menu.addItem(openItem)
    }

    menu.addItem(.separator())
    let deleteItem = NSMenuItem(title: "Delete\u{2026}",
                                action: #selector(MediaMenuTarget.delete(_:)),
                                keyEquivalent: "")
    deleteItem.target = coordinator.menuTarget
    menu.addItem(deleteItem)
    return menu
}
```

- [ ] **Step 3: Handle the actions in MediaLibraryView**

Add the argument to the `MediaGalleryView` initialiser call.

```swift
onContextAction: { action, media in handleContextAction(action, media) }
```

And add the function to the extension.

```swift
func handleContextAction(_ action: MediaContextAction, _ media: WPMedia) {
    switch action {
    case .copyURL:
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(media.sourceURL, forType: .string)
    case .openInBrowser:
        guard let url = URL(string: media.link) else { return }
        NSWorkspace.shared.open(url)
    case .delete:
        mediaPendingDelete = media
    }
}
```

- [ ] **Step 4: Build and run**

Run: `osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app`
Expected: the app opens.

- [ ] **Step 5: Test by hand**

1. Right-clicking a thumbnail shows Copy URL, Open in Browser and Delete.
2. Right-clicking also selects that thumbnail.
3. Copy URL puts the source URL on the clipboard.
4. Delete shows the confirmation alert, and confirming removes the thumbnail.
5. Right-clicking empty space in the gallery shows no menu.

- [ ] **Step 6: Commit** (ask the user first)

```bash
git add Sources/QuillKit/Views/Media/MediaGalleryView.swift Sources/QuillKit/Views/Media/MediaLibraryView.swift
git commit -m "feat: add gallery context menu"
```

---

### Task 8: The filter sidebar, the toolbar and the strip removal

**Files:**
- Modify: `Sources/QuillKit/Views/Media/MediaSidebarSection.swift` — most of the file is deleted
- Modify: `Sources/QuillKit/Views/Sidebar/SidebarView.swift:20-41`, `:165-172`, `:230`
- Test: by hand.

**Interfaces:**
- Consumes: `MediaFilter` from Task 2, `MediaLibraryView` from Task 4.
- Produces: `MediaSidebarSection` becomes a filter list only.

This task fixes defects 1, 2, 3 and 5 from the spec.

- [ ] **Step 1: Replace MediaSidebarSection with the filter list**

Replace the whole of `Sources/QuillKit/Views/Media/MediaSidebarSection.swift`.

```swift
import SwiftUI

struct MediaSidebarSection: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(selection: $appState.mediaFilter) {
            ForEach(MediaFilter.allCases) { filter in
                Label(filter.title, systemImage: filter.icon)
                    .tag(filter)
            }
            if let error = appState.mediaError {
                errorRow(error)
            }
        }
        .listStyle(.sidebar)
    }

    private func errorRow(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Blog Settings") { appState.isShowingPreferences = true }
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}
```

The deleted code included `loadMedia`, `loadMoreMedia`, `performDelete` and `uploadFromDisk`. The first three now live in `MediaLibraryView`. The upload moves to the toolbar in step 3.

- [ ] **Step 2: Move the upload trigger handling**

`MediaSidebarSection` owned `appState.triggerMediaUpload`, which `QuillApp.swift:90` sets from the File menu. Add this to `MediaLibraryView`'s `body`, after `.task(id: reloadKey)`.

```swift
.onChange(of: appState.triggerMediaUpload) { newValue in
    guard newValue else { return }
    appState.triggerMediaUpload = false
    uploadFromDisk()
}
.onAppear {
    guard appState.triggerMediaUpload else { return }
    appState.triggerMediaUpload = false
    uploadFromDisk()
}
```

And add `uploadFromDisk` to the `MediaLibraryView` extension, moved from the deleted `MediaSidebarSection.swift:279-310`.

```swift
func uploadFromDisk() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [UTType.image, UTType.pdf]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    guard let creds = appState.credentials else { return }
    Task {
        do {
            // Off the main actor — see the same call in PostEditorView.
            let prepared = await Task.detached(priority: .userInitiated) {
                ImageConversion.prepareForUpload(url)
            }.value
            defer { prepared.cleanup() }
            let uploaded = try await WordPressClient(credentials: creds)
                .uploadMedia(fileURL: prepared.fileURL,
                             filename: prepared.filename,
                             mimeType: prepared.mimeType)
            appState.mediaItems.insert(uploaded, at: 0)
            appState.selectedMedia = uploaded
        } catch {
            appState.mediaError = error.localizedDescription
        }
    }
}
```

Read the original at `git show HEAD:Sources/QuillKit/Views/Media/MediaSidebarSection.swift` before writing this, and keep whatever error handling it had. Do not invent behaviour.

**One behaviour is lost here and must be restored.** The deleted strip had an
`isUploading` flag. It disabled the New Media button and showed a spinner while
an upload ran. The toolbar button has neither. Add an `@State private var
isUploading = false` to `MediaLibraryView`, set it around the upload `Task`, and
show a `ProgressView().controlSize(.small)` overlaid on the gallery while it is
true. Without this the user gets no feedback at all during an upload.

- [ ] **Step 3: Branch the toolbar's new-item button**

Replace `SidebarView.swift:30-40`.

```swift
Button {
    if appState.selectedSection == .media {
        appState.triggerMediaUpload = true
    } else {
        createNewDraft()
    }
} label: {
    Image(systemName: appState.selectedSection == .media ? "arrow.up.doc" : "square.and.pencil")
}
.keyboardShortcut("n", modifiers: .command)
.help("\(newButtonTitle) (\u{2318}N)")
.accessibilityLabel(newButtonTitle)
```

Keep the surrounding `if appState.selectedSection != .localDrafts` condition exactly as it is. This routes the button through the existing `triggerMediaUpload` flag rather than duplicating the upload code, which fixes defect 2.

- [ ] **Step 4: Fix the inert Refresh button**

Refresh must re-run the load without changing the filter. `MediaLibraryView`
reloads on `.task(id: reloadKey)`, and that key holds the filter and the search
text. Neither changes when the user presses Refresh, so the key needs a third
component that Refresh can bump.

Add this to `AppState.swift`, beside the other media properties.

```swift
@Published public var mediaRefreshToken: Int = 0
```

Replace `case .media: break` at `SidebarView.swift:230`.

```swift
case .media:
    appState.mediaRefreshToken += 1
```

Change `reloadKey` in `MediaLibraryView`.

```swift
private var reloadKey: String {
    "\(appState.mediaFilter.rawValue)|\(appState.mediaSearchText)|\(appState.mediaRefreshToken)"
}
```

This satisfies the spec requirement that Refresh keeps the active filter, because `loadMedia` always reads the current filter.

- [ ] **Step 5: Build and run**

Run: `osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app`
Expected: the app opens, and the Media sidebar shows five filter rows.

- [ ] **Step 6: Test by hand**

1. The bottom strip is gone. No duplicate Refresh or New button remains.
2. Each of the five filters returns the right items.
3. The toolbar Refresh button reloads, and keeps the selected filter.
4. The toolbar New Media button opens the file picker. It does NOT create a post.
5. The File menu's media upload item still works.
6. A filter with no results shows the shared empty state, reading "No media yet".
7. Searching with no matches shows "No matches found".
8. Switching from Media to Posts and back keeps the app working.

- [ ] **Step 7: Commit** (ask the user first)

```bash
git add Sources/QuillKit/Views/Media/MediaSidebarSection.swift Sources/QuillKit/Views/Media/MediaLibraryView.swift Sources/QuillKit/Views/Sidebar/SidebarView.swift Sources/QuillKit/App/AppState.swift
git commit -m "feat: replace the media sidebar grid with type filters"
```

---

### Task 9: Full verification and documentation

**Files:**
- Modify: `Sources/QuillKit/Views/Media/CLAUDE.md`
- Modify: `CLAUDE.md`
- Modify: `docs/testing-plan.md`
- Modify: `docs/superpowers/specs/2026-09-19-media-panel-native-design.md` (status line only)

- [ ] **Step 1: Run the full test suite**

Run: `./test.sh`
Expected: all suites pass. The Swift count rises from 428 by the number of tests added in Tasks 1 and 2, which is 7. The JS count must stay at 1,202, because no JavaScript changed.

- [ ] **Step 2: Run the WebKit fixture check**

Run: `./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"`
Expected: unchanged from before this work. No JavaScript changed, so any difference here is a real regression and must be investigated.

- [ ] **Step 3: Update the media directory notes**

In `Sources/QuillKit/Views/Media/CLAUDE.md`, replace the entry describing the shared upload helpers so it records where `uploadFromDisk` now lives. Add one entry for the new AppKit bridge. Keep each entry to the file's existing style.

Record these two facts, because both are non-obvious and fail silently:

- `MediaGalleryView` syncs selection in both directions, and `Coordinator.isApplyingSelection` is the guard that stops a SwiftUI-driven selection from echoing back as a user selection. Removing it causes an update loop.
- `onNeedMore` fires on every scroll notification. The `hasMore` and `isLoadingMore` guards in `loadMoreMedia` are what stop one request per scroll event.
- `appState.mediaItems` now holds the *filtered* list, and the editor reads it as a size cache at `PostEditorView.swift:116`. A filtered view can miss an image the editor wants, and the editor then falls back to `fetchMediaItem`. The size buttons still work. Do not "fix" the fallback away.

- [ ] **Step 4: Update the root CLAUDE.md**

In the Architecture tree, add `MediaGalleryView`, `MediaLibraryView` and `MediaPreviewOverlay` to the `Media/` line. Update the "Key files to know" entry for `GallerySheet.swift` only if it moved, which it did not.

- [ ] **Step 5: Update the testing plan**

In `docs/testing-plan.md`, correct the Swift test count and add the manual media checklist from Tasks 6, 7 and 8.

- [ ] **Step 6: Mark the spec implemented**

Change the spec's `Status:` line to `implemented 2026-09-19`.

- [ ] **Step 7: Commit** (ask the user first)

```bash
git add Sources/QuillKit/Views/Media/CLAUDE.md CLAUDE.md docs/testing-plan.md docs/superpowers/specs/2026-09-19-media-panel-native-design.md
git commit -m "docs: record the media panel native conversion"
```
