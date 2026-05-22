import SwiftUI
import UniformTypeIdentifiers

public enum MediaPickerMode { case browser, picker }

public struct MediaPickerView: View {
    let mode: MediaPickerMode
    var onSelect: ((WPMedia) -> Void)?

    @EnvironmentObject private var appState: AppState
    @State private var mediaItems: [WPMedia] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var isUploading = false

    public init(mode: MediaPickerMode, onSelect: ((WPMedia) -> Void)? = nil) {
        self.mode = mode
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
                        .onTapGesture {
                            if let handler = onSelect { handler(media) }
                        }
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
                let data = try Data(contentsOf: url)
                let mime = mimeType(for: url)
                let uploaded = try await WordPressClient(credentials: creds)
                    .uploadMedia(data: data, filename: url.lastPathComponent, mimeType: mime)
                mediaItems.insert(uploaded, at: 0)
            } catch {
                // silently show nothing — production would surface this
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
