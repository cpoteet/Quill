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
        metadataPanel
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
    }

    @ViewBuilder
    private func metadataRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(label)
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    private var urlRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel("URL")
            HStack(alignment: .top, spacing: 8) {
                Text(media.sourceURL)
                    .font(.callout)
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
                }
                .buttonStyle(.borderless)
                .help("Copy URL")
                .accessibilityLabel("Copy URL")
            }
        }
    }

    @ViewBuilder
    private var altTextRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel("Alt text")
            TextField("", text: $altTextDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(2...4)
                .padding(7)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.separator, lineWidth: 1))
                .onSubmit { commitAltText() }
                .focused($altFieldFocused)
                .onChange(of: altFieldFocused) { focused in
                    if !focused { commitAltText() }
                }
            HStack {
                switch altSaveState {
                case .saving:
                    ProgressView().scaleEffect(0.6)
                    Text("Saving\u{2026}").font(.footnote).foregroundStyle(.secondary)
                case .saved:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10)).foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("Saved").font(.footnote).foregroundStyle(.secondary)
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
