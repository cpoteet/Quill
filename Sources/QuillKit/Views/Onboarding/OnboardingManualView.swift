import SwiftUI

struct OnboardingManualView: View {
    @ObservedObject var model: OnboardingModel
    let automatic: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("Connect with an application password")
                .font(.title)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
            Text("Create one in WordPress, then paste it here.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            if automatic {
                OnboardingNote(message: "This site doesn't allow approving apps from the browser, so Quill needs a password you create yourself.")
                    .padding(.bottom, 14)
            }

            VStack(spacing: 12) {
                OnboardingField(label: "Site address") {
                    TextField("Site address", text: $model.address, prompt: Text(""))
                }
                OnboardingField(label: "Username") {
                    TextField("Username", text: $model.username, prompt: Text(""))
                }
                VStack(spacing: 6) {
                    OnboardingField(label: "Application password") {
                        SecureField("Application password", text: $model.appPassword, prompt: Text(""))
                    }
                    profileHelp
                }
            }

            OnboardingError(message: model.errorMessage)
                .padding(.top, 12)

            HStack {
                Button("Back") { model.back() }
                    .onboardingLink()
                    .disabled(model.isBusy)
                Spacer()
                OnboardingPrimaryButton(title: "Connect", isBusy: model.isBusy, isDisabled: !canConnect) {
                    Task { await model.connectManually() }
                }
            }
            .padding(.top, 14)
        }
    }

    private var canConnect: Bool {
        [model.address, model.username, model.appPassword].allSatisfy {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var profileHelp: some View {
        var link = AttributedString("Open Profile Page")
        if let url = model.profileURL {
            link.link = url
        } else {
            link.foregroundColor = .secondary
        }
        return Text(link + AttributedString(" to create one under Application Passwords."))
            .font(.callout)
            .foregroundStyle(.secondary)
            .tint(Color.accentColor)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { _ in
                model.openProfilePage()
                return .handled
            })
    }
}
