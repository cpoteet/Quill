# Media Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the media browser into the left sidebar as a thumbnail grid with context menus, a detail view in the main panel, pagination, and delete/upload actions.

**Architecture:** `MediaSidebarSection` (new) owns all sidebar media UI and local pagination state; `AppState` gains four published media fields so `ContentView` and `MediaDetailView` (new) can react to selection. `MediaPickerView` is simplified to picker-only (browser mode removed). `WordPressClient` gains `deleteMedia(id:)`.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSPasteboard`, `NSWorkspace`, `NSOpenPanel`), WordPress REST API

**Note on testing:** This project has no unit test suite. Each task ends with a build step (`./build.sh`) and, where relevant, a manual smoke-test in the running app. Build commands are run from the project root `/Users/Chris/Documents/Claude/WP Mac App`.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `Sources/WPWriterKit/App/AppState.swift` | Modify | Add `mediaItems`, `selectedMedia`, `isLoadingMedia`, `mediaError` |
| `Sources/WPWriterKit/API/Models/WPMedia.swift` | Modify | Add `link` and `date` fields via `decodeIfPresent` |
| `Sources/WPWriterKit/API/WordPressClient.swift` | Modify | Add `deleteMedia(id:)` |
| `Sources/WPWriterKit/Views/Media/MediaPickerView.swift` | Modify | Remove browser mode; simplify to picker-only sheet |
| `Sources/WPWriterKit/Views/Editor/PostEditorView.swift` | Modify | Remove `mode: .picker` argument (no longer needed) |
| `Sources/WPWriterKit/Views/Media/MediaSidebarSection.swift` | **Create** | 2-col thumbnail grid, context menus, pagination, bottom toolbar |
| `Sources/WPWriterKit/Views/Media/MediaDetailView.swift` | **Create** | Large preview + metadata for selected media item |
| `Sources/WPWriterKit/Views/Sidebar/SidebarView.swift` | Modify | Replace `else { Spacer() }` with `MediaSidebarSection()` |
| `Sources/WPWriterKit/Views/ContentView.swift` | Modify | Replace `MediaPickerView(mode:.browser)` with `MediaDetailView`/placeholder |

---

## Task 1: Extend AppState and WPMedia model

**Files:**
- Modify: `Sources/WPWriterKit/App/AppState.swift`
- Modify: `Sources/WPWriterKit/API/Models/WPMedia.swift`

- [ ] **Step 1: Add four media fields to AppState**

Open `Sources/WPWriterKit/App/AppState.swift`. After the existing `@Published public var listError: String?` line, add:

```swift
    @Published public var mediaItems: [WPMedia] = []
    @Published public var selectedMedia: WPMedia?
    @Published public var isLoadingMedia: Bool = false
    @Published public var mediaError: String?
```

- [ ] **Step 2: Add `link` and `date` fields to WPMedia**

Open `Sources/WPWriterKit/API/Models/WPMedia.swift`. The struct currently has `id`, `title`, `sourceURL`, `mediaType`, `mimeType`, `mediaDetails`. Add two new stored properties and extend `CodingKeys` and the custom `init(from:)`:

Replace the entire `WPMedia` struct (lines 3–28) with:

```swift
public struct WPMedia: Identifiable, Codable, Sendable {
    public let id: Int
    public var title: RenderedString
    public var sourceURL: String
    public var mediaType: String  // "image", "file", etc.
    public var mimeType: String
    public var link: String       // WordPress attachment page URL
    public var date: String       // ISO8601, server local time
    public var mediaDetails: MediaDetails?

    enum CodingKeys: String, CodingKey {
        case id, title
        case sourceURL = "source_url"
        case mediaType = "media_type"
        case mimeType = "mime_type"
        case link, date
        case mediaDetails = "media_details"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(RenderedString.self, forKey: .title) ?? RenderedString(raw: "")
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType) ?? ""
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType) ?? ""
        link = try c.decodeIfPresent(String.self, forKey: .link) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        mediaDetails = try c.decodeIfPresent(MediaDetails.self, forKey: .mediaDetails)
    }
}
```

- [ ] **Step 3: Build to confirm no errors**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh 2>&1 | tail -8
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
git add Sources/WPWriterKit/App/AppState.swift Sources/WPWriterKit/API/Models/WPMedia.swift
git commit -m "feat: add media state to AppState and link/date fields to WPMedia"
```

---

## Task 2: Add deleteMedia to WordPressClient

**Files:**
- Modify: `Sources/WPWriterKit/API/WordPressClient.swift`

- [ ] **Step 1: Add `deleteMedia(id:)` after `uploadMedia`**

Open `Sources/WPWriterKit/API/WordPressClient.swift`. After the closing `}` of `uploadMedia(data:filename:mimeType:)` (around line 101), insert:

```swift
    public func deleteMedia(id: Int) async throws {
        let url = try endpoint("media/\(id)", query: ["force": "true"])
        let request = authorizedRequest(url: url, method: "DELETE")
        try await performVoid(request)
    }
```

- [ ] **Step 2: Build**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh 2>&1 | tail -8
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
git add Sources/WPWriterKit/API/WordPressClient.swift
git commit -m "feat: add deleteMedia to WordPressClient"
```

---

## Task 3: Simplify MediaPickerView to picker-only

**Files:**
- Modify: `Sources/WPWriterKit/Views/Media/MediaPickerView.swift`
- Modify: `Sources/WPWriterKit/Views/Editor/PostEditorView.swift`

- [ ] **Step 1: Rewrite MediaPickerView**

Replace the entire contents of `Sources/WPWriterKit/Views/Media/MediaPickerView.swift` with the following. The `MediaPickerMode` enum and `mode` parameter are removed; `onSelect` is now required (non-optional) since this is only ever a picker sheet:

```swift
import SwiftUI
import UniformTypeIdentifiers

public struct MediaPickerView: View {
    var onSelect: (WPMedia) -> Void

    @EnvironmentObject private var appState: AppState
    @State private var mediaItems: [WPMedia] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var isUploading = false
    @State private var uploadError: String?

    public init(onSelect: @escaping (WPMedia) -> Void) {
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if isLoading {
                ProgressView("Loading media…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                VStack(spacing: 8) {
                    Text(error).foregroundStyle(.secondary)
                    Button("Retry") { Task { await loadMedia() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if mediaItems.isEmpty {
                Text("No media uploaded yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                mediaGrid
            }
        }
        .task { await loadMedia() }
        .alert(
            "Upload Failed",
            isPresented: Binding(
                get: { uploadError != nil },
                set: { if !$0 { uploadError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { uploadError = nil }
        } message: {
            Text(uploadError ?? "")
        }
    }

    private var toolbar: some View {
        HStack {
            Text("Media Library")
                .font(.headline)
            Spacer()
            Button("Upload…") { uploadFromDisk() }
                .disabled(isUploading)
            if isUploading {
                ProgressView().scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var mediaGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                ForEach(mediaItems.filter { $0.mediaType == "image" }) { media in
                    MediaThumbnail(media: media)
                        .onTapGesture { onSelect(media) }
                }
            }
            .padding(12)
        }
    }

    private func loadMedia() async {
        guard let creds = appState.credentials else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            mediaItems = try await WordPressClient(credentials: creds).fetchMedia()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func uploadFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.image, UTType.pdf, UTType.movie]
        panel.allowsMultipleSelection = false
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
                mediaItems.insert(uploaded, at: 0)
            } catch {
                uploadError = error.localizedDescription
            }
        }
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
}

struct MediaThumbnail: View {
    let media: WPMedia

    var body: some View {
        AsyncImage(url: URL(string: media.sourceURL)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .failure, .empty:
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
            @unknown default:
                Rectangle().fill(.quaternary)
            }
        }
        .frame(width: 120, height: 90)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 0.5)
        )
    }
}
```

- [ ] **Step 2: Update PostEditorView to remove `mode:` argument**

Open `Sources/WPWriterKit/Views/Editor/PostEditorView.swift`. Find the line:

```swift
                        MediaPickerView(mode: .picker) { selected in
```

Change it to:

```swift
                        MediaPickerView { selected in
```

- [ ] **Step 3: Build**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh 2>&1 | tail -8
```

Expected: `Build complete!`

- [ ] **Step 4: Smoke-test picker still works**

```bash
pkill -x WPWriter 2>/dev/null; sleep 1; open "/Users/Chris/Documents/Claude/WP Mac App/WPWriter.app"
```

Open a post, click the Image toolbar button, confirm the media picker sheet opens and selecting an image still inserts it into the editor.

- [ ] **Step 5: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
git add Sources/WPWriterKit/Views/Media/MediaPickerView.swift \
        Sources/WPWriterKit/Views/Editor/PostEditorView.swift
git commit -m "refactor: simplify MediaPickerView to picker-only, remove browser mode"
```

---

## Task 4: Create MediaSidebarSection

**Files:**
- Create: `Sources/WPWriterKit/Views/Media/MediaSidebarSection.swift`

- [ ] **Step 1: Create the file**

Create `Sources/WPWriterKit/Views/Media/MediaSidebarSection.swift` with the following content:

```swift
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MediaSidebarSection: View {
    @EnvironmentObject private var appState: AppState

    @State private var currentPage: Int = 1
    @State private var hasMore: Bool = false
    @State private var mediaPendingDelete: WPMedia?
    @State private var deleteError: String?
    @State private var isUploading: Bool = false
    @State private var uploadError: String?

    private let perPage = 30

    var body: some View {
        VStack(spacing: 0) {
            if appState.isLoadingMedia && appState.mediaItems.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.65)
                    Text("Loading…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }

            if let error = appState.mediaError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
            }

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 4
                ) {
                    ForEach(appState.mediaItems) { media in
                        MediaSidebarCell(
                            media: media,
                            isSelected: appState.selectedMedia?.id == media.id
                        )
                        .onTapGesture { appState.selectedMedia = media }
                        .contextMenu { contextMenuItems(for: media) }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)

                if hasMore {
                    Button("Load more…") {
                        Task { await loadMoreMedia() }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                }
            }

            Divider()
            bottomToolbar
        }
        .task {
            if appState.mediaItems.isEmpty {
                await loadMedia()
            }
        }
        // Confirmation alert for delete
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
            let name = media.title.rendered.isEmpty ? "This item" : "\"\(media.title.rendered)\""
            Text("\(name) will be permanently deleted from WordPress. This cannot be undone.")
        }
        // Delete error alert
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
        // Upload error alert
        .alert(
            "Upload Failed",
            isPresented: Binding(
                get: { uploadError != nil },
                set: { if !$0 { uploadError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { uploadError = nil }
        } message: {
            Text(uploadError ?? "")
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenuItems(for media: WPMedia) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(media.sourceURL, forType: .string)
        } label: {
            Label("Copy URL", systemImage: "link")
        }

        Button {
            let name = media.title.rendered.isEmpty ? "image" : media.title.rendered
            let md = "![\(name)](\(media.sourceURL))"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(md, forType: .string)
        } label: {
            Label("Copy as Markdown", systemImage: "doc.plaintext")
        }

        if !media.link.isEmpty, let linkURL = URL(string: media.link) {
            Button {
                NSWorkspace.shared.open(linkURL)
            } label: {
                Label("Open in Browser", systemImage: "safari")
            }
        }

        Divider()

        Button(role: .destructive) {
            mediaPendingDelete = media
        } label: {
            Label("Delete…", systemImage: "trash")
        }
    }

    // MARK: - Bottom toolbar

    private var bottomToolbar: some View {
        HStack {
            Button {
                Task { await loadMedia() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh (⌘R)")
            .padding(10)

            Spacer()

            if isUploading {
                ProgressView().scaleEffect(0.65).padding(.trailing, 4)
            }

            Button {
                uploadFromDisk()
            } label: {
                Label("Upload", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.wpAmber)
            }
            .buttonStyle(.plain)
            .disabled(isUploading)
            .keyboardShortcut("n", modifiers: .command)
            .help("Upload Media (⌘N)")
            .padding(10)
        }
    }

    // MARK: - Data loading

    private func loadMedia() async {
        guard let creds = appState.credentials else { return }
        appState.isLoadingMedia = true
        appState.mediaError = nil
        currentPage = 1
        defer { appState.isLoadingMedia = false }
        do {
            let items = try await WordPressClient(credentials: creds)
                .fetchMedia(page: 1, perPage: perPage)
            appState.mediaItems = items
            hasMore = items.count == perPage
            if let sel = appState.selectedMedia, !items.contains(where: { $0.id == sel.id }) {
                appState.selectedMedia = nil
            }
        } catch is CancellationError {
        } catch {
            appState.mediaError = error.localizedDescription
        }
    }

    private func loadMoreMedia() async {
        guard let creds = appState.credentials else { return }
        let nextPage = currentPage + 1
        do {
            let items = try await WordPressClient(credentials: creds)
                .fetchMedia(page: nextPage, perPage: perPage)
            appState.mediaItems.append(contentsOf: items)
            currentPage = nextPage
            hasMore = items.count == perPage
        } catch is CancellationError {
        } catch {
            appState.mediaError = error.localizedDescription
        }
    }

    // MARK: - Delete

    private func performDelete(_ media: WPMedia) async {
        guard let creds = appState.credentials else { return }
        do {
            try await WordPressClient(credentials: creds).deleteMedia(id: media.id)
            appState.mediaItems.removeAll { $0.id == media.id }
            if appState.selectedMedia?.id == media.id {
                appState.selectedMedia = nil
            }
        } catch {
            deleteError = error.localizedDescription
        }
    }

    // MARK: - Upload

    private func uploadFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.image, UTType.pdf, UTType.movie]
        panel.allowsMultipleSelection = false
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
                appState.mediaItems.insert(uploaded, at: 0)
                appState.selectedMedia = uploaded
            } catch {
                uploadError = error.localizedDescription
            }
        }
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Thumbnail cell

private struct MediaSidebarCell: View {
    let media: WPMedia
    let isSelected: Bool

    var body: some View {
        AsyncImage(url: URL(string: media.sourceURL)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .failure, .empty:
                Rectangle().fill(.quaternary)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                    )
            @unknown default:
                Rectangle().fill(.quaternary)
            }
        }
        .frame(height: 80)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isSelected ? Color.wpAmber : Color(.separatorColor),
                    lineWidth: isSelected ? 2 : 0.5
                )
        )
    }
}
```

- [ ] **Step 2: Build**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh 2>&1 | tail -8
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
git add Sources/WPWriterKit/Views/Media/MediaSidebarSection.swift
git commit -m "feat: add MediaSidebarSection with grid, context menus, pagination, upload"
```

---

## Task 5: Create MediaDetailView

**Files:**
- Create: `Sources/WPWriterKit/Views/Media/MediaDetailView.swift`

- [ ] **Step 1: Create the file**

Create `Sources/WPWriterKit/Views/Media/MediaDetailView.swift`:

```swift
import AppKit
import SwiftUI

struct MediaDetailView: View {
    let media: WPMedia

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Large preview
                AsyncImage(url: URL(string: media.sourceURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit)
                    case .failure:
                        Rectangle().fill(.quaternary)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 40, weight: .light))
                                    .foregroundStyle(.tertiary)
                            )
                    default:
                        Rectangle().fill(.quaternary)
                            .overlay(ProgressView())
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 320)
                .background(Color.wpPanelBg)

                Divider()

                // Metadata
                VStack(alignment: .leading, spacing: 16) {
                    let name = media.title.rendered.isEmpty
                        ? (URL(string: media.sourceURL)?.lastPathComponent ?? "")
                        : media.title.rendered
                    metadataRow(label: "Filename", value: name)
                    metadataRow(label: "Type", value: media.mimeType)

                    if let details = media.mediaDetails,
                       let w = details.width, let h = details.height,
                       w > 0, h > 0 {
                        metadataRow(label: "Dimensions", value: "\(w) × \(h) px")
                    }

                    if !media.date.isEmpty {
                        metadataRow(label: "Uploaded", value: formattedDate(media.date))
                    }

                    urlRow
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.wpPanelBg)
    }

    @ViewBuilder
    private func metadataRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    private var urlRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("URL")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            HStack(alignment: .top, spacing: 8) {
                Text(media.sourceURL)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(media.sourceURL, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy URL")
            }
        }
    }

    private func formattedDate(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime,
                                .withDashSeparatorInDate]
        if let date = parser.date(from: iso) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        return iso
    }
}
```

- [ ] **Step 2: Build**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh 2>&1 | tail -8
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
git add Sources/WPWriterKit/Views/Media/MediaDetailView.swift
git commit -m "feat: add MediaDetailView with preview and metadata"
```

---

## Task 6: Wire MediaSidebarSection into SidebarView

**Files:**
- Modify: `Sources/WPWriterKit/Views/Sidebar/SidebarView.swift`

- [ ] **Step 1: Replace the `else { Spacer() }` branch**

Open `Sources/WPWriterKit/Views/Sidebar/SidebarView.swift`. Find (near line 112):

```swift
            } else {
                Spacer()
            }
```

Replace it with:

```swift
            } else {
                MediaSidebarSection()
            }
```

- [ ] **Step 2: Build**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh 2>&1 | tail -8
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
git add Sources/WPWriterKit/Views/Sidebar/SidebarView.swift
git commit -m "feat: embed MediaSidebarSection in sidebar for media tab"
```

---

## Task 7: Wire MediaDetailView into ContentView

**Files:**
- Modify: `Sources/WPWriterKit/Views/ContentView.swift`

- [ ] **Step 1: Replace the media branch in ContentView**

Open `Sources/WPWriterKit/Views/ContentView.swift`. The current media branch is:

```swift
                if appState.selectedSection == .media {
                    MediaPickerView(mode: .browser)
                } else if let item = appState.selectedItem {
```

Replace just the media branch (keep the rest identical):

```swift
                if appState.selectedSection == .media {
                    if let media = appState.selectedMedia {
                        MediaDetailView(media: media)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "photo")
                                .font(.system(size: 38, weight: .light))
                                .foregroundStyle(Color.wpAmber.opacity(0.5))
                            Text("Select an image to preview")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.wpPanelBg)
                    }
                } else if let item = appState.selectedItem {
```

- [ ] **Step 2: Build**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh 2>&1 | tail -8
```

Expected: `Build complete!`

- [ ] **Step 3: Full smoke-test**

```bash
pkill -x WPWriter 2>/dev/null; sleep 1; open "/Users/Chris/Documents/Claude/WP Mac App/WPWriter.app"
```

Verify:
1. Click Media tab → sidebar shows thumbnail grid loading, main area shows placeholder
2. Thumbnails load and display correctly in 2-column grid
3. Click a thumbnail → main area shows large preview + metadata (filename, type, dimensions, URL)
4. Right-click thumbnail → context menu shows Copy URL, Copy as Markdown, Open in Browser, Delete…
5. Copy URL → paste confirms the correct URL
6. Copy as Markdown → paste confirms `![title](url)` format
7. Open in Browser → opens the WordPress attachment page
8. ⌘R → refreshes the grid
9. ⌘N / Upload button → opens file picker
10. Delete… → confirmation alert appears; confirming removes the item from the grid and clears detail view
11. "Load more…" button appears only when page is full (30 items)
12. Switch to Posts → editor works normally
13. Click Image button in editor → media picker sheet opens, selecting an image inserts it

- [ ] **Step 4: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
git add Sources/WPWriterKit/Views/ContentView.swift
git commit -m "feat: show MediaDetailView / placeholder in main panel for media tab"
```
