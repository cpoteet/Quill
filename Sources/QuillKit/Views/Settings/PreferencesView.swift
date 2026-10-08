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
    @State private var ai = AISettings()
    @State private var isSamplePickerOpen: Bool = false
    @State private var isAnalyzing: Bool = false
    @State private var modelFetchError: String?
    @State private var modelNotice: String?
    @State private var fetchedKey: String?
    @FocusState private var apiKeyFocused: Bool
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
        VStack(spacing: 0) {
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
                    SecureField("Anthropic API Key", text: $ai.apiKey)
                        .focused($apiKeyFocused)
                        .onSubmit { Task { await fetchModels() } }
                    Picker(selection: modelSelection) {
                        ForEach(modelChoices, id: \.id) { Text($0.displayName).tag($0.id) }
                    } label: {
                        Text("Model")
                        if let caption = modelCaption { Text(caption) }
                    }
                    .disabled(hasNoKey || ai.models.isEmpty)
                    Picker(selection: reasoningSelection) {
                        ForEach(reasoningChoices, id: \.self) { Text(Self.label(for: $0)).tag($0) }
                    } label: {
                        Text("Reasoning")
                        Text("Higher levels think longer before answering. Responses take more time and cost more.")
                    }
                    .disabled(reasoningChoices.count < 2)
                    LabeledContent {
                        HStack(spacing: 8) {
                            Button("Choose Posts\u{2026}") { isSamplePickerOpen = true }
                                .disabled(posts.isEmpty)
                            Button("Regenerate") { Task { await regenerateStyleGuide() } }
                                .disabled(hasNoKey || ai.samplePostIDs.isEmpty || isAnalyzing || isSaving)
                        }
                    } label: {
                        Text("Writing Style")
                        Text(ai.samplePostIDs.isEmpty
                             ? "No samples selected"
                             : "\(ai.samplePostIDs.count) post\(ai.samplePostIDs.count == 1 ? "" : "s") selected")
                    }
                    Toggle(isOn: $ai.webSearchEnabled) {
                        Text("Web Search")
                        if !modelSearches { Text("This model can't search the web.") }
                    }
                    .disabled(!modelSearches)
                }

                if let error = saveError {
                    Section {
                        InlineError(message: error)
                            .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)

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
            .padding(.horizontal, 30)
            .padding(.bottom, 20)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $isSamplePickerOpen) {
            SamplePostPickerSheet(
                posts: posts,
                selectedIDs: $ai.samplePostIDs,
                onDone: { isSamplePickerOpen = false }
            )
        }
        .onAppear {
            loadExisting()
            loadExistingAI()
        }
        .task { await fetchModels() }
        .onChange(of: apiKeyFocused) { _, focused in
            if !focused { Task { await fetchModels() } }
        }
    }

    // MARK: - Model and reasoning

    private var hasNoKey: Bool { ai.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var modelChoices: [AIModelInfo] { ai.models }

    private var modelSelection: Binding<String> {
        Binding(
            get: { ai.resolvedModelID() },
            set: { id in
                ai.model = id
                ai.reasoning = ai.normalizedReasoning()
                modelNotice = nil
            }
        )
    }

    private var modelCaption: String? {
        if hasNoKey { return "Enter an API key to load models." }
        return modelFetchError ?? modelNotice
    }

    private var reasoningChoices: [AIReasoning] { AISettings.reasoningOptions(for: ai.resolvedModel()) }

    private var reasoningSelection: Binding<AIReasoning> {
        Binding(get: { ai.normalizedReasoning() }, set: { ai.reasoning = $0 })
    }

    private var modelSearches: Bool { ai.resolvedModel()?.supportsWebSearch ?? true }

    static func label(for reasoning: AIReasoning) -> String {
        switch reasoning {
        case .off: "Off"
        case .modelDefault: "Model default"
        case .level("xhigh"): "Extra High"
        case .level(let level): level.capitalized
        }
    }

    private func fetchModels() async {
        let key = currentKey
        guard !key.isEmpty, key != fetchedKey else { return }
        fetchedKey = key
        do {
            let models = try await AnthropicClient(apiKey: key).listModels()
            guard currentKey == key else { return }
            let (next, notice) = ai.applyingFetchedModels(models)
            ai.models = next.models
            ai.model = next.model
            ai.reasoning = next.reasoning
            modelNotice = notice
            modelFetchError = nil
            // The list is a cache for every AI call, so it's kept even if the author never presses Save.
            if var stored = try? AISettingsStore.load(), stored.apiKey == key {
                stored = stored.applyingFetchedModels(models).0
                try? AISettingsStore.save(stored)
                onSaveAISettings?(stored)
            }
        } catch {
            guard currentKey == key else { return }
            fetchedKey = nil
            modelFetchError = error.localizedDescription
        }
    }

    private var currentKey: String { ai.apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func loadExistingAI() {
        guard let settings = try? AISettingsStore.load() else { return }
        ai = settings
    }

    private func saveAll() async {
        saveError = nil
        saveSuccess = false

        // Detect site URL change before saving — stale sample IDs and style guide
        // from a previous site must be cleared when the user switches WordPress sites.
        let previousCreds = try? CredentialsStore.load()
        let siteURLChanged = previousCreds != nil && previousCreds?.siteURL.absoluteString != siteURL
        if siteURLChanged {
            ai.samplePostIDs = []
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
                saveError = "Site URL must use HTTPS (HTTP is allowed only for localhost)."
                return
            }
            isSaving = true
            let creds = Credentials(siteURL: url, username: username, appPassword: appPassword)

            do {
                try await ConnectSite.verifyAndSave(creds)
            } catch {
                saveError = error.localizedDescription
                isSaving = false
                return
            }

            onSave(creds)
            isSaving = false
        }

        // Determine whether the style guide needs regeneration:
        // - Empty sample IDs                                  → clear guide, no regen
        // - IDs unchanged + site unchanged + existing guide   → keep guide, skip regen
        // - IDs changed OR site changed OR no existing guide  → regen
        let previousSettings = try? AISettingsStore.load()
        let idsUnchanged = Set(ai.samplePostIDs) == Set(previousSettings?.samplePostIDs ?? [])

        let existingGuide: String?
        if ai.samplePostIDs.isEmpty {
            existingGuide = nil
        } else if idsUnchanged && !siteURLChanged {
            existingGuide = previousSettings?.styleGuide
        } else {
            existingGuide = nil
        }

        let shouldRegen = !hasNoKey && !ai.samplePostIDs.isEmpty && existingGuide == nil

        // Persist immediately with whatever guide is valid right now
        ai.styleGuide = existingGuide
        ai.reasoning = ai.normalizedReasoning()
        do {
            try AISettingsStore.save(ai)
        } catch {
            saveError = "Couldn't save the Claude settings: \(error.localizedDescription)"
            return
        }
        onSaveAISettings?(ai)

        if shouldRegen {
            guard await generateStyleGuide() else { return }
        }

        saveSuccess = true
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        saveSuccess = false
    }

    private func regenerateStyleGuide() async {
        saveError = nil
        ai.reasoning = ai.normalizedReasoning()
        guard await generateStyleGuide() else { return }
        saveSuccess = true
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        saveSuccess = false
    }

    /// Builds the guide from the sample posts with the selected model, then saves it. False when it failed.
    private func generateStyleGuide() async -> Bool {
        isAnalyzing = true
        defer { isAnalyzing = false }
        var samples: [(title: String, html: String)] = []
        if let creds = credentials {
            let wpClient = WordPressClient(credentials: creds)
            for id in ai.samplePostIDs {
                let postType = posts.first(where: { $0.id == id })?.type ?? "post"
                let fetched = try? await (postType == "page"
                    ? wpClient.fetchPage(id: id)
                    : wpClient.fetchPost(id: id))
                if let fetched, !AIPromptBuilder.reduceSample(html: fetched.content.rendered).isEmpty {
                    samples.append((fetched.title.rendered, fetched.content.rendered))
                }
            }
        }
        guard !samples.isEmpty else {
            saveError = "Couldn't load the sample posts from WordPress, so the style guide wasn't updated."
            return false
        }
        do {
            let prompt = AIPromptBuilder.styleGuideGenerationPrompt(samples: samples)
            let guide = try await AnthropicClient(apiKey: ai.apiKey).complete(
                userMessage: prompt,
                systemPrompt: "Return only the requested style guide with no preamble.",
                options: CompletionOptions(settings: ai)
            ).text
            ai.styleGuide = guide
            try AISettingsStore.save(ai)
            onSaveAISettings?(ai)
            return true
        } catch {
            saveError = "Style analysis failed: \(error.localizedDescription)"
            return false
        }
    }

    private func loadExisting() {
        guard let creds = try? CredentialsStore.load() else { return }
        siteURL = creds.siteURL.absoluteString
        username = creds.username
        appPassword = creds.appPassword
    }
}
