import SwiftUI
import UniformTypeIdentifiers

public struct GallerySheet: View {
    var onInsert: (_ images: [WPMedia], _ columns: Int, _ cropped: Bool, _ linkTo: String) -> Void
    var onCancel: (() -> Void)?

    @EnvironmentObject private var appState: AppState
    @State private var mediaItems: [WPMedia] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var currentPage: Int = 1
    @State private var hasMore: Bool = false
    @State private var isLoadingMore = false
    @State private var selected: [WPMedia] = []
    @State private var columns: Int = 3
    @State private var cropped: Bool = true
    @State private var linkTo: String = "none"

    public init(
        onInsert: @escaping (_ images: [WPMedia], _ columns: Int, _ cropped: Bool, _ linkTo: String) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.onInsert = onInsert
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                mediaPane
                SoftPanelBoundary()
                selectionPane
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
            Text("Insert Gallery").font(.headline)
            Spacer()
            if isUploading {
                ProgressView().scaleEffect(0.7)
            }
            Button("Upload") { uploadFromDisk() }
                .disabled(isUploading)
            Button("Insert Gallery") {
                onInsert(selected, columns, cropped, linkTo)
            }
            .disabled(selected.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var mediaPane: some View {
        Group {
            if isLoading {
                ProgressView("Loading media…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                VStack(spacing: 8) {
                    Text(error).foregroundStyle(.secondary)
                    Button("Retry") { Task { await loadMedia() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(mediaItems.filter { $0.mediaType == "image" }) { media in
                            GalleryMediaThumbnail(media: media, isSelected: selected.contains(where: { $0.id == media.id }))
                                .contentShape(Rectangle())
                                .onTapGesture { toggle(media) }
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
        }
        .frame(minWidth: 340)
    }

    private var selectionPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selected (\(selected.count))")
                .font(.subheadline.weight(.semibold))
                .padding(.top, 12)
                .padding(.horizontal, 12)

            if selected.isEmpty {
                Text("Tap images to add them to the gallery.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            } else {
                List {
                    ForEach(selected) { media in
                        HStack {
                            AsyncImage(url: URL(string: media.thumbnailURL)) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    Rectangle().fill(.quaternary)
                                }
                            }
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(media.title.decodedTitle)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer()
                            Button {
                                selected.removeAll { $0.id == media.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onMove { indices, newOffset in
                        selected.move(fromOffsets: indices, toOffset: newOffset)
                    }
                }
                .listStyle(.plain)
            }

            Divider().padding(.horizontal, 12)

            Stepper("Columns: \(columns)", value: $columns, in: 1...8)
                .padding(.horizontal, 12)
            Toggle("Crop images to square", isOn: $cropped)
                .padding(.horizontal, 12)
            Picker("Link to", selection: $linkTo) {
                Text("None").tag("none")
                Text("Full Image").tag("media")
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 12)

            Spacer()
        }
        .frame(minWidth: 260, maxWidth: 300)
    }

    private func toggle(_ media: WPMedia) {
        if let idx = selected.firstIndex(where: { $0.id == media.id }) {
            selected.remove(at: idx)
        } else {
            selected.append(media)
        }
    }

    private let perPage = 50

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
                let mime = MimeType.forFile(url)
                let uploaded = try await WordPressClient(credentials: creds)
                    .uploadMedia(fileURL: url, filename: url.lastPathComponent, mimeType: mime)
                mediaItems.insert(uploaded, at: 0)
            } catch {
                uploadError = error.localizedDescription
            }
        }
    }

    private func loadMedia() async {
        guard let creds = appState.credentials else {
            isLoading = false
            loadError = "No WordPress site configured."
            return
        }
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
}

private struct GalleryMediaThumbnail: View {
    let media: WPMedia
    let isSelected: Bool

    var body: some View {
        Color.clear
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 80, maxHeight: 80)
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
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2 : 0.5)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(4)
                }
            }
    }
}
