import SwiftUI

public struct PreferencesView: View {
    @State private var siteURL: String = ""
    @State private var username: String = ""
    @State private var appPassword: String = ""
    @State private var isSaving: Bool = false
    @State private var saveError: String?
    @State private var saveSuccess: Bool = false

    var onSave: (Credentials) -> Void

    public init(onSave: @escaping (Credentials) -> Void) {
        self.onSave = onSave
    }

    public var body: some View {
        Form {
            Section("WordPress Site") {
                TextField("Site URL", text: $siteURL, prompt: Text("https://yoursite.com"))
                    .textFieldStyle(.roundedBorder)
            }
            Section("Application Password") {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField("Application Password", text: $appPassword, prompt: Text("xxxx xxxx xxxx xxxx xxxx xxxx"))
                    .textFieldStyle(.roundedBorder)
                Text("Generate one in WordPress Admin → Users → Profile → Application Passwords.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = saveError {
                Text(error).foregroundStyle(.red).font(.caption)
            }
            if saveSuccess {
                Text("Saved successfully.").foregroundStyle(.green).font(.caption)
            }
            HStack {
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || siteURL.isEmpty || username.isEmpty || appPassword.isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding()
        .onAppear(perform: loadExisting)
    }

    private func loadExisting() {
        guard let creds = try? KeychainStore.load() else { return }
        siteURL = creds.siteURL.absoluteString
        username = creds.username
        appPassword = creds.appPassword
    }

    private func save() {
        saveError = nil
        saveSuccess = false
        guard let url = URL(string: siteURL), url.scheme != nil else {
            saveError = "Invalid URL. Include https://"
            return
        }
        isSaving = true
        let creds = Credentials(siteURL: url, username: username, appPassword: appPassword)
        do {
            try KeychainStore.save(creds)
            onSave(creds)
            saveSuccess = true
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
