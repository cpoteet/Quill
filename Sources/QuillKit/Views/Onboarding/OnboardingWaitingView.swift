import SwiftUI

struct OnboardingWaitingView: View {
    @ObservedObject var model: OnboardingModel
    let site: DiscoveredSite
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                tile { QuillMark.view(.accentColor, size: 40) }
                dots
                siteTile
            }
            .accessibilityHidden(true)
            .padding(.bottom, 22)

            Text("Approve Quill in your browser")
                .font(.title)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
            Text("Log in to \(Text.siteName(site.name)) if asked, approve the connection, then let your browser open Quill.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)

            Button("Cancel") { model.cancelWaiting() }
                .disabled(model.isBusy)

            HStack(spacing: 4) {
                Text("Browser didn't open?")
                    .foregroundStyle(.secondary)
                Button("Open it again") { model.reopenBrowser() }
                    .onboardingLink()
            }
            .font(.callout)
            .padding(.top, 18)

            OnboardingError(message: model.errorMessage)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
        }
        .onAppear { pulsing = !reduceMotion }
    }

    private var dots: some View {
        HStack(spacing: 5) {
            Circle().fill(.quaternary)
            Circle()
                .fill(Color.accentColor)
                .opacity(pulsing ? 0.25 : 1)
                .animation(pulsing ? .easeInOut(duration: 0.8).repeatForever() : .default, value: pulsing)
            Circle().fill(.quaternary)
        }
        .frame(width: 25, height: 5)
    }

    @ViewBuilder
    private var siteTile: some View {
        if let icon = model.siteIcon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5))
        } else {
            Text(initial)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Color.accentColor, in: .rect(cornerRadius: 12))
        }
    }

    private var initial: String {
        let source = site.name ?? site.siteURL.host() ?? ""
        return source.first.map { String($0).uppercased() } ?? "W"
    }

    private func tile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: 52, height: 52)
            .background(Color.wpContentSurface, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
    }
}
