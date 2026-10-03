import SwiftUI

struct OnboardingWelcomeView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            QuillMark.view(.accentColor, size: 61)
                .accessibilityHidden(true)
                .padding(.bottom, 22)
            Text("Welcome to Quill")
                .font(.largeTitle)
                .fontWeight(.semibold)
                .padding(.bottom, 8)
            Text("Write and edit your WordPress posts and pages on your Mac. Connect your site to get started.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 26)

            if let notice = model.notice {
                OnboardingNote(title: notice.title, message: notice.detail)
                    .padding(.bottom, 14)
            }

            VStack(spacing: 6) {
                OnboardingField(label: "Site address") {
                    TextField("Site address", text: $model.address, prompt: Text(""))
                }
                OnboardingError(message: model.errorMessage)
            }

            HStack {
                Button("Use an application password instead") { model.useManualEntry() }
                    .onboardingLink()
                    .disabled(model.isBusy)
                Spacer()
                OnboardingPrimaryButton(
                    title: "Continue",
                    isBusy: model.isBusy,
                    isDisabled: model.address.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    Task { await model.continueTapped() }
                }
            }
            .padding(.top, 16)
        }
    }
}
