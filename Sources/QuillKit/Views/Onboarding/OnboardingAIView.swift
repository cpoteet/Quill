import SwiftUI

struct OnboardingAIView: View {
    @ObservedObject var model: OnboardingModel
    let siteName: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.statusColor("publish"))
                    .accessibilityHidden(true)
                Text("Connected to \(Text.siteName(siteName))")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.bottom, 18)

            Text("Add AI writing help")
                .font(.title)
                .fontWeight(.semibold)
                .padding(.bottom, 8)
            Text("Quill can draft posts, review your writing and rewrite selections with Claude. It uses your own Anthropic API key, and Anthropic bills you for what you use.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)

            VStack(spacing: 6) {
                OnboardingField(label: "Anthropic API key") {
                    SecureField("Anthropic API key", text: $model.apiKey, prompt: Text(""))
                }
                OnboardingError(message: model.errorMessage)
                Text("Get a key from the [Claude Platform](https://platform.claude.com/settings/keys). After setup, teach Quill your writing style in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .tint(Color.accentColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.openURL, OpenURLAction { _ in
                        model.openAPIKeysPage()
                        return .handled
                    })
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Skip for Now") { model.skipAI() }
                    .disabled(model.isBusy)
                OnboardingPrimaryButton(
                    title: "Save",
                    isBusy: model.isBusy,
                    isDisabled: model.apiKey.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    Task { await model.saveAIKey() }
                }
            }
            .padding(.top, 14)
        }
    }
}
