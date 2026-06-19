import AppKit
import SwiftUI

struct MediaDetailView: View {
    let media: WPMedia
    var onSaveAltText: ((String) async -> Void)? = nil

    @State private var altTextDraft = ""
    @State private var altSaveState: AltSaveState = .idle
    @FocusState private var altFieldFocused: Bool

    private enum AltSaveState { case idle, saving, saved }

    init(media: WPMedia, onSaveAltText: ((String) async -> Void)? = nil) {
        self.media = media
        self.onSaveAltText = onSaveAltText
        self._altTextDraft = State(initialValue: media.altText)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: large image preview fills remaining space
            imagePreview

            Divider()

            // Right: fixed-width metadata panel
            metadataPanel
                .frame(width: 260)
        }
        .background(Color.wpPanelBg)
    }

    // MARK: - Image preview

    private var imagePreview: some View {
        Group {
            if media.mediaType == "image" {
                AsyncImage(url: URL(string: media.sourceURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(32)
                    case .failure:
                        previewUnavailable
                    default:
                        ProgressView()
                    }
                }
            } else {
                previewUnavailable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.wpPanelBg)
    }

    private var previewUnavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Preview unavailable")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Metadata panel

    private var metadataPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                let name = media.title.rendered.isEmpty
                    ? (URL(string: media.sourceURL)?.lastPathComponent ?? "")
                    : media.title.decodedTitle
                metadataRow(label: "Filename", value: name)
                metadataRow(label: "Type", value: {
                    if let ext = URL(string: media.sourceURL)?.pathExtension, !ext.isEmpty {
                        return ext.uppercased()
                    }
                    return media.mimeType.split(separator: "/").last.map(String.init)?.uppercased() ?? media.mimeType
                }())

                if let details = media.mediaDetails,
                   let w = details.width, let h = details.height,
                   w > 0, h > 0 {
                    metadataRow(label: "Dimensions", value: "\(w) × \(h) px")
                }

                if media.mediaType == "image" {
                    altTextRow
                }

                if !media.date.isEmpty {
                    metadataRow(label: "Uploaded", value: formattedDate(media.date))
                }

                urlRow
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder
    private var altTextRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("ALT TEXT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("", text: $altTextDraft, axis: .vertical)
                .font(.system(size: 13))
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.secondary.opacity(0.3))
                )
                .onSubmit { commitAltText() }
                .focused($altFieldFocused)
                .onChange(of: altFieldFocused) { focused in
                    if !focused { commitAltText() }
                }
            HStack {
                switch altSaveState {
                case .saving:
                    ProgressView().scaleEffect(0.6)
                    Text("Saving\u{2026}").font(.system(size: 10)).foregroundStyle(.secondary)
                case .saved:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10)).foregroundStyle(.green)
                    Text("Saved").font(.system(size: 10)).foregroundStyle(.secondary)
                case .idle:
                    EmptyView()
                }
            }
            .frame(height: 14)
        }
        .onChange(of: altTextDraft) { _ in
            altSaveState = .idle
        }
    }

    private func commitAltText() {
        guard altSaveState != .saving else { return }
        guard let save = onSaveAltText else { return }
        let text = altTextDraft
        altSaveState = .saving
        Task {
            await save(text)
            await MainActor.run { altSaveState = .saved }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { if altSaveState == .saved { altSaveState = .idle } }
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
