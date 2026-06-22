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
            if let error = appState.mediaError {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.top, 1)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Open Blog Settings") {
                        appState.isShowingPreferences = true
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
            }

            if !appState.mediaItems.isEmpty {
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
                            .contentShape(Rectangle())
                            .onTapGesture { appState.selectedMedia = media }
                            .contextMenu { contextMenuItems(for: media) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                    if hasMore {
                        Button("Load more") {
                            Task { await loadMoreMedia() }
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 7))
                        .buttonStyle(.plain)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                    }
                }
            } else if appState.hasLoadedMedia && !appState.isLoadingMedia {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.quaternary)
                    Text("No media yet")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text("Upload with the + button below")
                        .font(.system(size: 11))
                        .foregroundStyle(.quaternary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            SoftHorizontalDivider()
            bottomToolbar
        }
        .task {
            await loadMedia()
        }
        .onAppear {
            if appState.triggerMediaUpload {
                appState.triggerMediaUpload = false
                uploadFromDisk()
            }
        }
        .onChange(of: appState.triggerMediaUpload) { newValue in
            if newValue {
                appState.triggerMediaUpload = false
                uploadFromDisk()
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
            let name = media.title.rendered.isEmpty ? "This item" : "\"\(media.title.decodedTitle)\""
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
                    .padding(6)
                    .background(Color.primary.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh (⌘R)")
            .padding(.leading, 10)
            .padding(.vertical, 8)

            Spacer()

            if isUploading {
                ProgressView().scaleEffect(0.65).padding(.trailing, 4)
            }

            Button {
                uploadFromDisk()
            } label: {
                Label("New Media", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.wpAmber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.wpAmber.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .disabled(isUploading)
            .keyboardShortcut("n", modifiers: .command)
            .help("Upload Media (⌘N)")
            .padding(.trailing, 10)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Data loading

    private func loadMedia() async {
        guard let creds = appState.credentials else {
            appState.isLoadingMedia = false
            appState.hasLoadedMedia = true
            return
        }
        if appState.mediaItems.isEmpty {
            appState.isLoadingMedia = true
        }
        appState.mediaError = nil
        currentPage = 1
        do {
            let items = try await WordPressClient(credentials: creds)
                .fetchMedia(page: 1, perPage: perPage)
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
        panel.allowedContentTypes = [UTType.image, UTType.pdf]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let creds = appState.credentials else { return }
        isUploading = true
        Task {
            defer { isUploading = false }
            do {
                let mime = mimeType(for: url)
                let uploaded = try await WordPressClient(credentials: creds)
                    .uploadMedia(fileURL: url, filename: url.lastPathComponent, mimeType: mime)
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
        Color.clear
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 80, maxHeight: 80)
            .overlay {
                if media.mediaType == "image" {
                    AsyncImage(url: URL(string: media.thumbnailURL)) { phase in
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
                    .clipped()
                } else {
                    Rectangle().fill(.quaternary)
                        .overlay(
                            Image(systemName: media.mimeType == "application/pdf" ? "doc.richtext.fill" : "doc.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.tertiary)
                        )
                }
            }
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
