import SwiftUI

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
        Form {
            Section {
                TextField("Site URL", text: $siteURL)
                TextField("Username", text: $username)
                SecureField("Application Password", text: $appPassword)
            } header: {
                Text("WordPress Credentials")
            } footer: {
                Text("Generate an application password in WordPress Admin \u{2192} Users \u{2192} Profile.")
            }

            Section("AI Writing") {
                SecureField("Anthropic API Key", text: $aiAPIKey)
                LabeledContent("Writing Style") {
                    HStack(spacing: 8) {
                        Button("Choose Posts") { isSamplePickerOpen = true }
                            .disabled(posts.isEmpty)
                        Text(aiSamplePostIDs.isEmpty
                             ? "No samples selected"
                             : "\(aiSamplePostIDs.count) post\(aiSamplePostIDs.count == 1 ? "" : "s") selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Web Search", isOn: $aiWebSearchEnabled)
            }

            if let error = saveError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                HStack {
                    if isAnalyzing {
                        Text("Analyzing writing style\u{2026}").foregroundStyle(.secondary).font(.caption)
                    } else if saveSuccess {
                        Text("Saved.").foregroundStyle(.secondary).font(.caption)
                    }
                    Spacer()
                    Button("Save") { Task { await saveAll() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving || isAnalyzing)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $isSamplePickerOpen) {
            SamplePostPickerSheet(
                posts: posts,
                selectedIDs: $aiSamplePostIDs,
                onDone: { isSamplePickerOpen = false }
            )
        }
        .onAppear {
            loadExisting()
            loadExistingAI()
        }
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

            // Validate credentials with a lightweight API call before persisting them —
            // saving first would leave bad credentials on disk (loaded again on next launch).
            do {
                let client = WordPressClient(credentials: creds)
                _ = try await client.fetchPosts(page: 1, perPage: 1)
            } catch {
                saveError = error.localizedDescription
                isSaving = false
                return
            }

            do {
                try CredentialsStore.save(creds)
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
