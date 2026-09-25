import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MediaLibraryView: View {
    @EnvironmentObject private var appState: AppState

    @State private var hasMore = false
    @State private var isLoadingMore = false
    @State private var uploadTask: Task<Void, Never>?
    @State private var isUploading = false
    @State private var previewedMedia: WPMedia?
    @State private var mediaPendingDelete: WPMedia?
    @State private var deleteError: String?
    @State private var uploadError: String?

    private let perPage = 30

    var body: some View {
        galleryWithAlerts
            .navigationTitle(appState.selectedMedia?.title.decodedTitle ?? "Media")
            .toolbar {
                ToolbarSpacer(.flexible)
                ToolbarItem {
                    Button {
                        withAnimation { appState.isMediaInspectorOpen.toggle() }
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .help("Media Info")
                    .accessibilityLabel("Media Info")
                }
            }
            .inspector(isPresented: $appState.isMediaInspectorOpen) {
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
                } else {
                    Text("No Selection")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
                }
            }
            .task(id: reloadKey) { await loadMedia() }
            .onAppear {
                guard appState.triggerMediaUpload else { return }
                appState.triggerMediaUpload = false
                startUpload()
            }
            .onChange(of: appState.triggerMediaUpload) { _, newValue in
                guard newValue else { return }
                appState.triggerMediaUpload = false
                startUpload()
            }
            .onChange(of: appState.triggerShowMediaDetails) { _, newValue in
                guard newValue else { return }
                appState.triggerShowMediaDetails = false
                withAnimation { appState.isMediaInspectorOpen = true }
            }
    }

    private var galleryWithOverlays: some View {
        gallery
            .overlay {
                if isUploading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .overlay {
                if let previewedMedia {
                    MediaPreviewOverlay(media: previewedMedia) {
                        self.previewedMedia = nil
                    }
                }
            }
            .onExitCommand { previewedMedia = nil }
    }

    private var galleryWithAlerts: some View {
        galleryWithOverlays
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

    private var reloadKey: String {
        "\(appState.mediaFilter.rawValue)|\(appState.mediaSearchText)|\(appState.mediaRefreshToken)"
    }

    @ViewBuilder
    private var gallery: some View {
        if !appState.mediaItems.isEmpty {
            MediaGalleryView(
                items: appState.mediaItems,
                selection: $appState.selectedMedia,
                onNeedMore: { Task { await loadMoreMedia() } },
                onActivate: { media in previewedMedia = media },
                onContextAction: { action, media in handleContextAction(action, media) },
                onSpace: { togglePreview() }
            )
        } else if appState.mediaError != nil && !appState.isLoadingMedia {
            EmptyEditorPlaceholder(section: .media, loadFailed: true)
        } else if appState.hasLoadedMedia && !appState.isLoadingMedia {
            SectionEmptyState(section: .media,
                              isSearching: !appState.mediaSearchText.isEmpty)
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension MediaLibraryView {
    func loadMedia() async {
        guard let creds = appState.credentials else {
            appState.isLoadingMedia = false
            appState.hasLoadedMedia = true
            return
        }
        // The search field sends on every keystroke; .task(id:) cancels the previous
        // run, so sleeping here collapses a burst of typing into one request.
        if !appState.mediaSearchText.isEmpty {
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        }
        if appState.mediaItems.isEmpty { appState.isLoadingMedia = true }
        appState.mediaError = nil
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
        // Offset, not a page: a local insert or delete makes a page cursor skip or repeat one.
        let offset = appState.mediaItems.count
        do {
            let items = try await WordPressClient(credentials: creds)
                .fetchMedia(perPage: perPage,
                            mediaType: appState.mediaFilter.mediaTypeParameter,
                            search: appState.mediaSearchText,
                            offset: offset)
            appState.mediaItems.append(contentsOf: items)
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

    func handleContextAction(_ action: MediaContextAction, _ media: WPMedia) {
        switch action {
        case .showDetails:
            appState.selectedMedia = media
            appState.triggerShowMediaDetails = true
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

    func togglePreview() {
        if previewedMedia != nil {
            previewedMedia = nil
        } else {
            previewedMedia = appState.selectedMedia
        }
    }

    // NSOpenPanel.runModal() bails if called during a SwiftUI view update.
    func startUpload() {
        DispatchQueue.main.async { uploadFromDisk() }
    }

    func uploadFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.image, UTType.pdf]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let creds = appState.credentials else { return }
        isUploading = true
        // Serialized: overlapping uploads share `isUploading` — see the drop queue in PostEditorView.
        let previous = uploadTask
        uploadTask = Task {
            await previous?.value
            defer { isUploading = false }
            do {
                // Off the main actor — see the same call in PostEditorView.
                let prepared = await Task.detached(priority: .userInitiated) {
                    ImageConversion.prepareForUpload(url)
                }.value
                defer { prepared.cleanup() }
                let uploaded = try await WordPressClient(credentials: creds)
                    .uploadMedia(
                        fileURL: prepared.fileURL,
                        filename: prepared.filename,
                        mimeType: prepared.mimeType
                    )
                // An item the filter excludes would also desync the count the offset paging uses.
                if appState.mediaFilter.matches(uploaded) {
                    appState.mediaItems.insert(uploaded, at: 0)
                } else {
                    appState.mediaFilter = .all
                }
                appState.selectedMedia = uploaded
            } catch {
                uploadError = error.localizedDescription
            }
        }
    }
}
