import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        ZStack {
            Color.wpContentSurface.ignoresSafeArea()
            content.frame(width: 330)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .welcome:
            OnboardingWelcomeView(model: model)
        case .waiting(let site, _):
            OnboardingWaitingView(model: model, site: site)
        case .manual(let automatic):
            OnboardingManualView(model: model, automatic: automatic)
        case .aiSetup(let siteName):
            OnboardingAIView(model: model, siteName: siteName)
        case .finished:
            EmptyView()
        }
    }
}

// MARK: - Shared pieces

struct OnboardingField<Field: View>: View {
    let label: String
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.callout)
                .fontWeight(.medium)
            field
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OnboardingError: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct OnboardingPrimaryButton: View {
    let title: String
    let isBusy: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .opacity(isBusy ? 0 : 1)
                .overlay {
                    if isBusy { ProgressView().controlSize(.small) }
                }
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(isDisabled || isBusy)
    }
}

extension View {
    func onboardingLink() -> some View {
        buttonStyle(.link)
            .font(.callout)
            .foregroundStyle(Color.accentColor)
    }
}

extension Text {
    static func siteName(_ name: String?) -> Text {
        Text(name ?? "your site")
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
    }
}
