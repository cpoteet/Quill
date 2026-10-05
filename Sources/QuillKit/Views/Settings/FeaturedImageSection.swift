import SwiftUI
import UniformTypeIdentifiers

struct FeaturedImageSection: View {
    @Binding var mediaID: Int
    let isUploading: Bool
    let onDropImage: (NSItemProvider) -> Void

    @EnvironmentObject private var appState: AppState
    @State private var media: WPMedia?
    @State private var loadFailed = false
    @State private var showPicker = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Featured Image")
            slot
                .onDrop(of: [.image], isTargeted: $isDropTargeted) { providers in
                    guard !isUploading, let provider = providers.first else { return false }
                    onDropImage(provider)
                    return true
                }
            if mediaID > 0 && !isUploading {
                altTextLine
                HStack(spacing: 8) {
                    Button("Replace…") { showPicker = true }
                    Button("Remove") { mediaID = 0 }
                }
            }
        }
        .task(id: mediaID) { await loadMedia() }
        .sheet(isPresented: $showPicker) {
            MediaPickerView(onSelect: { selected in
                media = selected
                mediaID = selected.id
                showPicker = false
            }, onCancel: {
                showPicker = false
            })
            .environmentObject(appState)
            .frame(minWidth: 600, minHeight: 400)
        }
    }

    @ViewBuilder
    private var slot: some View {
        if isUploading {
            placeholder { ProgressView("Uploading…").controlSize(.small) }
        } else if mediaID == 0 {
            emptySlot
        } else if let media {
            Button { showPicker = true } label: { thumbnail(media) }
                .buttonStyle(.plain)
                .accessibilityLabel("Replace featured image")
        } else if loadFailed {
            placeholder {
                Text("Couldn't load image")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            placeholder { ProgressView().controlSize(.small) }
        }
    }

    private var emptySlot: some View {
        VStack(spacing: 6) {
            Button("Choose…") { showPicker = true }
            Text("or drop an image here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [4, 3])
                )
        }
    }

    private func thumbnail(_ media: WPMedia) -> some View {
        AsyncImage(url: URL(string: media.sizedURL(for: "medium"))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            default:
                Rectangle().fill(.quaternary)
            }
        }
        .aspectRatio(Self.aspectRatio(of: media), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isDropTargeted ? Color.accentColor : .clear, lineWidth: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: 240, alignment: .leading)
    }

    private func placeholder(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var altTextLine: some View {
        if let media {
            Text(media.altText.isEmpty ? "No alt text" : "Alt text: \(media.altText)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }

    private func loadMedia() async {
        loadFailed = false
        guard mediaID > 0 else { media = nil; return }
        if media?.id == mediaID { return }
        media = nil
        if let cached = appState.mediaItems.first(where: { $0.id == mediaID }) {
            media = cached
            return
        }
        guard let creds = appState.credentials else { return }
        do {
            let fetched = try await WordPressClient(credentials: creds).fetchMediaItem(id: mediaID)
            guard !Task.isCancelled, fetched.id == mediaID else { return }
            media = fetched
        } catch {
            if !Task.isCancelled { loadFailed = true }
        }
    }

    private static func aspectRatio(of media: WPMedia) -> CGFloat? {
        guard let w = media.mediaDetails?.width, let h = media.mediaDetails?.height, w > 0, h > 0 else { return nil }
        return CGFloat(w) / CGFloat(h)
    }

    // The provider's file is deleted when its handler returns, so the caller gets a copy in its own folder to remove.
    static func copyDroppedImage(from provider: NSItemProvider) async -> URL? {
        let originalName = await droppedFileBaseName(provider)
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(for: .image) { url, _, _ in
                guard let url else { return continuation.resume(returning: nil) }
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                let name = originalName.map { "\($0).\(url.pathExtension)" } ?? url.lastPathComponent
                let copy = folder.appendingPathComponent(name)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: copy)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // loadFileRepresentation names its copy after the type ("PNG image.png"), so a Finder drop reads the name here.
    private static func droppedFileBaseName(_ provider: NSItemProvider) async -> String? {
        guard provider.canLoadObject(ofClass: URL.self) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                let name = url.flatMap { $0.isFileURL ? $0.deletingPathExtension().lastPathComponent : nil }
                continuation.resume(returning: name?.isEmpty == false ? name : nil)
            }
        }
    }
}
