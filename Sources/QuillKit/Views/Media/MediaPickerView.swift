import SwiftUI
import UniformTypeIdentifiers

public struct MediaPickerView: View {
    var onSelect: (WPMedia) -> Void
    var onCancel: (() -> Void)?

    @EnvironmentObject private var appState: AppState
    @State private var mediaItems: [WPMedia] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var currentPage: Int = 1
    @State private var hasMore: Bool = false
    @State private var isLoadingMore = false

    public init(onSelect: @escaping (WPMedia) -> Void, onCancel: (() -> Void)? = nil) {
        self.onSelect = onSelect
        self.onCancel = onCancel
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
            Button("Cancel") { onCancel?() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Text("Media Library")
                .font(.headline)
            Spacer()
            if isUploading {
                ProgressView().scaleEffect(0.7)
            }
            Button("Upload") { uploadFromDisk() }
                .disabled(isUploading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var mediaGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(mediaItems.filter { $0.mediaType == "image" }) { media in
                    MediaThumbnail(media: media)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(media) }
                }
            }
            .padding(12)
            if hasMore {
                Button {
                    Task { await loadMoreMedia() }
                } label: {
                    if isLoadingMore {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Text("Load More")
                    }
                }
                .disabled(isLoadingMore)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)
            }
        }
    }

    private let perPage = 50

    private func loadMedia() async {
        guard let creds = appState.credentials else { return }
        isLoading = true
        loadError = nil
        currentPage = 1
        defer { isLoading = false }
        do {
            let items = try await WordPressClient(credentials: creds).fetchMedia(page: 1, perPage: perPage)
            mediaItems = items
            hasMore = items.count == perPage
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadMoreMedia() async {
        guard let creds = appState.credentials else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let nextPage = currentPage + 1
        do {
            let items = try await WordPressClient(credentials: creds).fetchMedia(page: nextPage, perPage: perPage)
            mediaItems.append(contentsOf: items)
            currentPage = nextPage
            hasMore = items.count == perPage
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func uploadFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.image]
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
        Color.clear
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 90, maxHeight: 90)
            .overlay {
                AsyncImage(url: URL(string: media.thumbnailURL)) { phase in
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
                .clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 0.5)
            )
    }
}
