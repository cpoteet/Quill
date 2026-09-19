import SwiftUI

struct MediaPreviewOverlay: View {
    let media: WPMedia
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
            content
                .padding(40)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var content: some View {
        if media.mediaType == "image" {
            AsyncImage(url: URL(string: media.sourceURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                case .failure:
                    unavailable
                default:
                    ProgressView()
                }
            }
        } else {
            unavailable
        }
    }

    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("Preview unavailable")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }
}
