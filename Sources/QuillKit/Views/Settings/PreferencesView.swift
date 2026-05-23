import SwiftUI

private extension View {
    func inputFieldStyle() -> some View {
        self
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
            )
    }
}

public struct PreferencesView: View {
    @EnvironmentObject private var appState: AppState

    // WordPress credentials
    @State private var siteURL: String = ""
    @State private var username: String = ""
    @State private var appPassword: String = ""
    @State private var isSaving: Bool = false
    @State private var saveError: String?
    @State private var saveSuccess: Bool = false

    // AI Writing settings
    @State private var aiAPIKey: String = ""
    @State private var aiSamplePostIDs: [Int] = []
    @State private var aiWebSearchEnabled: Bool = true
    @State private var isSamplePickerOpen: Bool = false
    @State private var aiSaveSuccess: Bool = false

    var onSave: (Credentials) -> Void

    public init(onSave: @escaping (Credentials) -> Void) {
        self.onSave = onSave
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingSection(title: "WordPress Site") {
                formRow(label: "Site URL") {
                    TextField("https://yoursite.com", text: $siteURL)
                        .textFieldStyle(.plain)
                        .inputFieldStyle()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Application Password")
                    .font(.headline)
                VStack(spacing: 0) {
                    formRow(label: "Username") {
                        TextField("", text: $username)
                            .textFieldStyle(.plain)
                            .inputFieldStyle()
                    }
                    Divider().padding(.leading, 12)
                    formRow(label: "Application Password") {
                        SecureField("", text: $appPassword)
                            .textFieldStyle(.plain)
                            .inputFieldStyle()
                    }
                }
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )

                Text("Generate one in WordPress Admin → Users → Profile → Application Passwords.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            HStack {
                if let error = saveError {
                    Text(error).foregroundStyle(.red).font(.caption)
                } else if saveSuccess {
                    Text("Saved successfully.").foregroundStyle(.green).font(.caption)
                }
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || siteURL.isEmpty || username.isEmpty || appPassword.isEmpty)
            }

            Divider()

            settingSection(title: "AI Writing") {
                formRow(label: "Anthropic API Key") {
                    SecureField("sk-ant-…", text: $aiAPIKey)
                        .textFieldStyle(.plain)
                        .inputFieldStyle()
                }
                Divider().padding(.leading, 12)
                formRow(label: "Writing Style") {
                    HStack(spacing: 8) {
                        Button("Choose Sample Posts…") { isSamplePickerOpen = true }
                            .buttonStyle(.bordered)
                            .disabled(appState.posts.isEmpty)
                        Text(aiSamplePostIDs.isEmpty
                             ? "No samples selected"
                             : "\(aiSamplePostIDs.count) post\(aiSamplePostIDs.count == 1 ? "" : "s") selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider().padding(.leading, 12)
                formRow(label: "Web Search") {
                    Toggle("Allow Claude to search the web", isOn: $aiWebSearchEnabled)
                        .toggleStyle(.switch)
                }
            }
            .sheet(isPresented: $isSamplePickerOpen) {
                SamplePostPickerSheet(
                    posts: appState.posts,
                    selectedIDs: $aiSamplePostIDs,
                    onDone: { isSamplePickerOpen = false }
                )
            }

            HStack {
                if aiSaveSuccess {
                    Text("AI settings saved.").foregroundStyle(.green).font(.caption)
                }
                Spacer()
                Button("Save AI Settings") { saveAISettings() }
                    .buttonStyle(.borderedProminent)
                    .disabled(aiAPIKey.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            loadExisting()
            loadExistingAI()
        }
    }

    @ViewBuilder
    private func settingSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            VStack(spacing: 0) {
                content()
            }
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
    }

    @ViewBuilder
    private func formRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(minWidth: 140, alignment: .leading)
                .foregroundStyle(.primary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    private func loadExistingAI() {
        guard let settings = try? AISettingsStore.load() else { return }
        aiAPIKey = settings.apiKey
        aiSamplePostIDs = settings.samplePostIDs
        aiWebSearchEnabled = settings.webSearchEnabled
    }

    private func saveAISettings() {
        let settings = AISettings(
            apiKey: aiAPIKey,
            samplePostIDs: aiSamplePostIDs,
            webSearchEnabled: aiWebSearchEnabled
        )
        try? AISettingsStore.save(settings)
        appState.aiSettings = settings
        aiSaveSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { aiSaveSuccess = false }
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
