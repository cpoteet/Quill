import SwiftUI

/// One image queued for insertion, with the alt text and caption that will be
/// written into this gallery's markup. Seeded from the media library item;
/// edits here never write back to the library.
///
/// `public` because `GallerySheet.init` is public and its `onInsert` closure
/// references this type.
public struct GallerySelection: Identifiable {
    public let media: WPMedia
    public var alt: String
    public var caption: String
    public var id: Int { media.id }
}

public struct GallerySheet: View {
    var onInsert: (_ images: [GallerySelection], _ columns: Int, _ cropped: Bool, _ linkTo: String, _ sizeSlug: String) -> Void
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
    @State private var selected: [GallerySelection] = []
    @State private var expandedIDs: Set<Int> = []
    @State private var columns: Int = 3
    @State private var cropped: Bool = true
    @State private var linkTo: String = "none"
    @State private var sizeSlug: String = "large"

    public init(
        onInsert: @escaping (_ images: [GallerySelection], _ columns: Int, _ cropped: Bool, _ linkTo: String, _ sizeSlug: String) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.onInsert = onInsert
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text("Insert Gallery")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)
            Divider()
            HStack(spacing: 0) {
                mediaPane
                selectionPane
            }
            Divider()
            actionBar
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

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button("Upload…") { uploadFromDisk() }
                .disabled(isUploading)
            if isUploading {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Button("Cancel") { onCancel?() }
                .keyboardShortcut(.cancelAction)
            Button("Insert Gallery") {
                onInsert(selected, columns, cropped, linkTo, sizeSlug)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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
                        ForEach(imageItems) { media in
                            MediaThumbnail(media: media, isSelected: selected.contains(where: { $0.id == media.id }), size: 80)
                                .contentShape(Rectangle())
                                .onTapGesture { toggle(media) }
                                .onAppear {
                                    guard media.id == imageItems.last?.id else { return }
                                    Task { await loadMoreMedia() }
                                }
                        }
                    }
                    .padding(12)
                    if isLoadingMore {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 12)
                    }
                }
            }
        }
        .frame(minWidth: 340)
    }

    private var selectionPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Selected (\(selected.count))")
                    .padding(.top, 12)
                    .padding(.horizontal, 12)

                if selected.isEmpty {
                    Text("Select images to add them to the gallery.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                } else {
                    List {
                        ForEach($selected) { $sel in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Image(systemName: "line.3.horizontal")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 14, height: 22)
                                        .contentShape(Rectangle())
                                        .onHover { hovering in
                                            // Reaching for the grip means intent to drag, and an
                                            // expanded row is moveDisabled. Collapsing on hover —
                                            // rather than on press — means the click that follows
                                            // starts a real drag, instead of being spent collapsing
                                            // a row whose drag was already ruled out at mouse-down.
                                            guard hovering else { return }
                                            expandedIDs.remove(sel.id)
                                            NSCursor.openHand.set()
                                        }
                                    AsyncImage(url: URL(string: sel.media.thumbnailURL)) { phase in
                                        if case .success(let image) = phase {
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        } else {
                                            Rectangle().fill(.quaternary)
                                        }
                                    }
                                    .frame(width: 32, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    Text(sel.media.title.decodedTitle)
                                        .font(.callout)
                                        .lineLimit(1)
                                    Spacer()
                                    // Chevron only — the row body stays free for drag-to-reorder.
                                    // Both buttons get a padded hit area and sit far enough apart
                                    // that expanding a row can't be mistaken for removing it.
                                    HStack(spacing: 14) {
                                        Button {
                                            if expandedIDs.contains(sel.id) {
                                                expandedIDs.remove(sel.id)
                                            } else {
                                                expandedIDs.insert(sel.id)
                                            }
                                        } label: {
                                            Image(systemName: expandedIDs.contains(sel.id) ? "chevron.down" : "chevron.right")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 18, height: 22)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .help("Alt text and caption")
                                        Button {
                                            expandedIDs.remove(sel.id)
                                            selected.removeAll { $0.id == sel.id }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.secondary)
                                                .frame(width: 18, height: 22)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .help("Remove from gallery")
                                        .accessibilityLabel("Remove from gallery")
                                    }
                                    // Buttons are click targets, not drag surfaces — keep the
                                    // arrow over them, and hand the open hand back on the way out
                                    // (only if this row is actually draggable).
                                    .onHover { hovering in
                                        if hovering {
                                            NSCursor.arrow.set()
                                        } else if !expandedIDs.contains(sel.id) {
                                            NSCursor.openHand.set()
                                        }
                                    }
                                }
                                .onHover { hovering in
                                    // An expanded row is moveDisabled, so it must not advertise
                                    // itself as draggable.
                                    if hovering && !expandedIDs.contains(sel.id) {
                                        NSCursor.openHand.set()
                                    } else {
                                        NSCursor.arrow.set()
                                    }
                                }

                                if expandedIDs.contains(sel.id) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        SectionLabel("Alt Text")
                                        TextField("", text: $sel.alt)
                                            .textFieldStyle(.roundedBorder)
                                            .controlSize(.small)
                                        SectionLabel("Caption")
                                        TextField("", text: $sel.caption)
                                            .textFieldStyle(.roundedBorder)
                                            .controlSize(.small)
                                    }
                                    .padding(.leading, 19)
                                    .padding(.bottom, 4)
                                }
                            }
                            // A row in a List with .onMove is draggable, and the drag gesture
                            // claims mouse-down before a TextField inside it can take focus.
                            // Reorder is meaningless while typing anyway, so an expanded row
                            // opts out; collapsing it restores dragging.
                            .moveDisabled(expandedIDs.contains(sel.id))
                        }
                        .onMove { indices, newOffset in
                            selected.move(fromOffsets: indices, toOffset: newOffset)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 12)

            gallerySettings
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(minWidth: 260, maxWidth: 300)
    }

    private var gallerySettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Columns")
                Stepper("\(columns)", value: $columns, in: 1...8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Crop")
                Toggle("Square", isOn: $cropped)
                    .toggleStyle(.switch)
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Link To")
                Picker("", selection: $linkTo) {
                    Text("None").tag("none")
                    Text("Full Image").tag("media")
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Size")
                Picker("", selection: $sizeSlug) {
                    Text("Thumbnail").tag("thumbnail")
                    Text("Medium").tag("medium")
                    Text("Large").tag("large")
                    Text("Full Size").tag("full")
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func toggle(_ media: WPMedia) {
        if let idx = selected.firstIndex(where: { $0.id == media.id }) {
            // Drop the expanded state too, or re-selecting this image later brings
            // its row back already expanded (and moveDisabled) with no user action.
            expandedIDs.remove(media.id)
            selected.remove(at: idx)
        } else {
            selected.append(
                GallerySelection(media: media, alt: media.altText, caption: media.captionText)
            )
        }
    }

    private let perPage = 50

    private func uploadFromDisk() {
        guard let creds = appState.credentials else { return }
        guard let url = pickImageFromDisk() else { return }
        isUploading = true
        Task {
            defer { isUploading = false }
            do {
                let uploaded = try await uploadPickedImage(url, credentials: creds)
                mediaItems.insert(uploaded, at: 0)
                selected.append(
                    GallerySelection(media: uploaded, alt: uploaded.altText, caption: uploaded.captionText)
                )
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

    private var imageItems: [WPMedia] {
        mediaItems.filter { $0.mediaType == "image" }
    }

    /// Keeps fetching until a page yields at least one image, so a run of PDFs or
    /// audio can't strand the grid with an unchanged last cell and nothing to retrigger it.
    private func loadMoreMedia() async {
        guard hasMore, !isLoadingMore, let creds = appState.credentials else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        while hasMore {
            let nextPage = currentPage + 1
            do {
                let items = try await WordPressClient(credentials: creds).fetchMedia(page: nextPage, perPage: perPage)
                mediaItems.append(contentsOf: items)
                currentPage = nextPage
                hasMore = items.count == perPage
                if items.contains(where: { $0.mediaType == "image" }) { return }
            } catch {
                loadError = error.localizedDescription
                return
            }
        }
    }
}
