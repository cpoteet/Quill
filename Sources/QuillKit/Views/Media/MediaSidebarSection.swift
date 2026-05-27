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
            if appState.isLoadingMedia {
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
                        .contentShape(Rectangle())
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
                Label("New Media", systemImage: "plus")
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
        Color.clear
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 80, maxHeight: 80)
            .overlay {
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
                .clipped()
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
