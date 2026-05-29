import AppKit
import SwiftUI

struct MediaDetailView: View {
    let media: WPMedia

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
        AsyncImage(url: URL(string: media.sourceURL)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(32)
            case .failure:
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Image unavailable")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            default:
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.wpPanelBg)
    }

    // MARK: - Metadata panel

    private var metadataPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                let name = media.title.rendered.isEmpty
                    ? (URL(string: media.sourceURL)?.lastPathComponent ?? "")
                    : media.title.rendered
                metadataRow(label: "Filename", value: name)
                metadataRow(label: "Type", value: media.mimeType)

                if let details = media.mediaDetails,
                   let w = details.width, let h = details.height,
                   w > 0, h > 0 {
                    metadataRow(label: "Dimensions", value: "\(w) × \(h) px")
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
