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
    @State private var isAnalyzing: Bool = false
    var onSave: (Credentials) -> Void
    var posts: [WPPost]
    var credentials: Credentials?
    var onSaveAISettings: ((AISettings) -> Void)?

    public init(
        posts: [WPPost] = [],
        credentials: Credentials? = nil,
        onSave: @escaping (Credentials) -> Void,
        onSaveAISettings: ((AISettings) -> Void)? = nil
    ) {
        self.posts = posts
        self.credentials = credentials
        self.onSave = onSave
        self.onSaveAISettings = onSaveAISettings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("WordPress Credentials")
                    .font(.headline)
                VStack(spacing: 0) {
                    formRow(label: "Site URL") {
                        TextField("", text: $siteURL)
                            .textFieldStyle(.plain)
                            .inputFieldStyle()
                    }
                    Divider().padding(.leading, 12)
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

                Text("Generate an application password in WordPress Admin → Users → Profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            settingSection(title: "AI Writing") {
                formRow(label: "Anthropic API Key") {
                    SecureField("", text: $aiAPIKey)
                        .textFieldStyle(.plain)
                        .inputFieldStyle()
                }
                Divider().padding(.leading, 12)
                formRow(label: "Writing Style") {
                    HStack(spacing: 8) {
                        Button("Choose Posts") { isSamplePickerOpen = true }
                            .buttonStyle(.bordered)
                            .tint(Color.wpAmber)
                            .disabled(posts.isEmpty)
                        Text(aiSamplePostIDs.isEmpty
                             ? "No samples selected"
                             : "\(aiSamplePostIDs.count) post\(aiSamplePostIDs.count == 1 ? "" : "s") selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider().padding(.leading, 12)
                formRow(label: "Web Search") {
                    Toggle("", isOn: $aiWebSearchEnabled)
                        .toggleStyle(.switch)
                        .tint(Color.wpAmber)
                }
            }
            .sheet(isPresented: $isSamplePickerOpen) {
                SamplePostPickerSheet(
                    posts: posts,
                    selectedIDs: $aiSamplePostIDs,
                    onDone: { isSamplePickerOpen = false }
                )
            }

            if let error = saveError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isAnalyzing {
                    Text("Analyzing writing style…").foregroundStyle(.secondary).font(.caption)
                } else if saveSuccess {
                    Text("Saved.").foregroundStyle(Color.wpAmber).font(.caption)
                }
                Spacer()
                Button("Save") { Task { await saveAll() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.wpAmber)
                    .disabled(isSaving || isAnalyzing)
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

    private func saveAll() async {
        saveError = nil
        saveSuccess = false

        // Detect site URL change before saving — stale sample IDs and style guide
        // from a previous site must be cleared when the user switches WordPress sites.
        let previousCreds = try? CredentialsStore.load()
        let siteURLChanged = previousCreds != nil && previousCreds?.siteURL.absoluteString != siteURL
        if siteURLChanged {
            aiSamplePostIDs = []
        }

        // Save WordPress credentials if any field is filled
        if !siteURL.isEmpty || !username.isEmpty || !appPassword.isEmpty {
            guard let url = URL(string: siteURL), let scheme = url.scheme?.lowercased() else {
                saveError = "Invalid URL. Include https://"
                return
            }
            let host = url.host?.lowercased() ?? ""
            let isLocalHost = host == "localhost" || host == "127.0.0.1" || host == "::1"
            guard scheme == "https" || (scheme == "http" && isLocalHost) else {
                saveError = "Site URL must use https:// (http is allowed only for localhost)."
                return
            }
            isSaving = true
            let creds = Credentials(siteURL: url, username: username, appPassword: appPassword)
            do {
                try CredentialsStore.save(creds)
            } catch {
                saveError = error.localizedDescription
                isSaving = false
                return
            }

            // Validate credentials with a lightweight API call before dismissing
            do {
                let client = WordPressClient(credentials: creds)
                _ = try await client.fetchPosts(page: 1, perPage: 1)
            } catch {
                saveError = error.localizedDescription
                isSaving = false
                return
            }

            onSave(creds)
            isSaving = false
        }

        guard !aiAPIKey.isEmpty else {
            saveSuccess = true
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            saveSuccess = false
            return
        }

        // Determine whether the style guide needs regeneration:
        // - Empty sample IDs                                  → clear guide, no regen
        // - IDs unchanged + site unchanged + existing guide   → keep guide, skip regen
        // - IDs changed OR site changed OR no existing guide  → regen
        let previousSettings = try? AISettingsStore.load()
        let idsUnchanged = Set(aiSamplePostIDs) == Set(previousSettings?.samplePostIDs ?? [])

        let existingGuide: String?
        if aiSamplePostIDs.isEmpty {
            existingGuide = nil
        } else if idsUnchanged && !siteURLChanged {
            existingGuide = previousSettings?.styleGuide
        } else {
            existingGuide = nil
        }

        let shouldRegen = !aiSamplePostIDs.isEmpty && existingGuide == nil

        // Persist immediately with whatever guide is valid right now
        var current = AISettings(
            apiKey: aiAPIKey,
            samplePostIDs: aiSamplePostIDs,
            webSearchEnabled: aiWebSearchEnabled,
            styleGuide: existingGuide
        )
        try? AISettingsStore.save(current)
        onSaveAISettings?(current)

        // Optionally regenerate the style guide
        if shouldRegen {
            isAnalyzing = true
            var sampleContents: [String] = []
            if let creds = credentials {
                let wpClient = WordPressClient(credentials: creds)
                for id in aiSamplePostIDs {
                    let postType = posts.first(where: { $0.id == id })?.type ?? "post"
                    let fetched = try? await (postType == "page"
                        ? wpClient.fetchPage(id: id)
                        : wpClient.fetchPost(id: id))
                    if let fetched {
                        let stripped = fetched.content.rendered
                            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !stripped.isEmpty { sampleContents.append(stripped) }
                    }
                }
            }

            if !sampleContents.isEmpty {
                do {
                    let client = AnthropicClient(apiKey: aiAPIKey)
                    let prompt = AIPromptBuilder.styleGuideGenerationPrompt(sampleContents: sampleContents)
                    let guide = try await client.complete(
                        userMessage: prompt,
                        systemPrompt: "Return only the requested style guide with no preamble.",
                        useWebSearch: false
                    ).text
                    current.styleGuide = guide
                    try? AISettingsStore.save(current)
                    onSaveAISettings?(current)
                } catch {
                    saveError = "Style analysis failed: \(error.localizedDescription)"
                    isAnalyzing = false
                    return
                }
            }
            isAnalyzing = false
        }

        saveSuccess = true
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        saveSuccess = false
    }

    private func loadExisting() {
        guard let creds = try? CredentialsStore.load() else { return }
        siteURL = creds.siteURL.absoluteString
        username = creds.username
        appPassword = creds.appPassword
    }
}
