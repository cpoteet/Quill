import AppKit
import SwiftUI

struct MediaDetailView: View {
    let media: WPMedia
    var onSaveTitle: ((String) async throws -> Void)? = nil
    var onSaveAltText: ((String) async throws -> Void)? = nil

    var body: some View {
        metadataPanel
    }

    // MARK: - Metadata panel

    private var metadataPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SavingTextFieldRow(
                    label: "Title",
                    initialText: media.title.raw ?? media.title.decodedTitle,
                    lineLimit: 1...3,
                    onSave: onSaveTitle
                )
                if let filename = URL(string: media.sourceURL)?.lastPathComponent, !filename.isEmpty {
                    metadataRow(label: "Filename", value: filename)
                }
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

                if let bytes = media.mediaDetails?.filesize, bytes > 0 {
                    metadataRow(label: "File Size",
                                value: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                }

                if media.mediaType == "image" {
                    SavingTextFieldRow(
                        label: "Alt Text",
                        initialText: media.altText,
                        lineLimit: 2...4,
                        onSave: onSaveAltText
                    )
                }

                if !media.date.isEmpty {
                    metadataRow(label: "Uploaded", value: formattedDate(media.date))
                }

                urlRow
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func metadataRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(label)
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    private var urlRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("URL")
            HStack(alignment: .top, spacing: 8) {
                Text(media.sourceURL)
                    .font(.subheadline)
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

// MARK: - Editable field

private struct SavingTextFieldRow: View {
    let label: String
    let lineLimit: ClosedRange<Int>
    let onSave: ((String) async throws -> Void)?

    @State private var draft: String
    @State private var saveState: SaveState = .idle
    @FocusState private var focused: Bool

    private enum SaveState: Equatable { case idle, saving, saved, failed(String) }

    init(label: String, initialText: String, lineLimit: ClosedRange<Int>,
         onSave: ((String) async throws -> Void)?) {
        self.label = label
        self.lineLimit = lineLimit
        self.onSave = onSave
        self._draft = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(label)
            TextField("", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(lineLimit)
                .accessibilityLabel(label)
                .onSubmit { commit() }
                .focused($focused)
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
            HStack {
                switch saveState {
                case .saving:
                    ProgressView().scaleEffect(0.6)
                    Text("Saving\u{2026}").font(.subheadline).foregroundStyle(.secondary)
                case .saved:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline).foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("Saved").font(.subheadline).foregroundStyle(.secondary)
                case .failed(let message):
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.subheadline).foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text("Not saved: \(message)").font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail).help(message)
                case .idle:
                    EmptyView()
                }
            }
            .frame(height: 14)
        }
        .onChange(of: draft) {
            saveState = .idle
        }
    }

    private func commit() {
        guard saveState != .saving else { return }
        guard let save = onSave else { return }
        let text = draft
        saveState = .saving
        Task {
            do {
                try await save(text)
            } catch {
                await MainActor.run { saveState = .failed(error.localizedDescription) }
                return
            }
            await MainActor.run { saveState = .saved }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { if saveState == .saved { saveState = .idle } }
        }
    }
}
