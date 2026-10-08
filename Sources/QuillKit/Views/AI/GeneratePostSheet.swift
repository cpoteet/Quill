import SwiftUI

struct GeneratePostSheet: View {
    let aiSettings: AISettings
    var onResult: (String, String, String) -> Void   // (title, html, excerpt)
    var onCancel: () -> Void
    /// The web search tool version that worked, and the model it worked for.
    var onWebSearchTool: (String, String) -> Void = { _, _ in }

    @State private var prompt: String = ""
    @State private var isGenerating: Bool = false
    @State private var statusText: String = ""
    @State private var errorText: String? = nil
    @State private var showTruncationAlert: Bool = false
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Generate Content with Claude")
                .font(.headline)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $prompt)
                    .font(.body)
                    .frame(minHeight: 80, maxHeight: 160)
                    .scrollContentBackground(.hidden)
                    .focused($promptFocused)
                    .disabled(isGenerating)
            }
            .padding(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
            )

            if isGenerating {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.75)
                    Text(statusText.isEmpty ? "Writing…" : statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = errorText {
                InlineError(message: error)
                    .font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .disabled(isGenerating)
                Button("Generate") {
                    Task { await generate() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || isGenerating)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(20)
        .frame(width: 480)
        .alert("Post was cut off", isPresented: $showTruncationAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Get Full Version") {
                Task { await generate(maxTokens: 16384) }
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text("The generated post hit the initial length limit before it was finished. Get the full version? (Uses more API budget)")
        }
    }

    @MainActor
    private func generate(maxTokens: Int = 4096) async {
        isGenerating = true
        promptFocused = false
        errorText = nil
        let modelID = aiSettings.resolvedModelID()
        let webSearch = aiSettings.webSearchEnabled && aiSettings.resolvedModel()?.supportsWebSearch != false
        statusText = webSearch ? "Searching the web…" : "Writing…"
        do {
            let client = AnthropicClient(apiKey: aiSettings.apiKey)
            let result = try await client.complete(
                userMessage: AIPromptBuilder.generatePrompt(description: prompt, webSearch: webSearch),
                systemPrompt: AIPromptBuilder.generateSystem(styleGuide: aiSettings.styleGuide, today: Date(), webSearch: webSearch),
                options: CompletionOptions(
                    settings: aiSettings,
                    baseMaxTokens: maxTokens,
                    webSearch: webSearch ? WebSearchUse(maxUses: 10, knownTool: aiSettings.knownWebSearchTool(for: modelID)) : nil,
                    jsonSchema: AIPromptBuilder.generateSchema
                )
            )
            if let tool = result.webSearchTool { onWebSearchTool(tool, modelID) }
            isGenerating = false
            guard let parsed = try? AIPromptBuilder.parseGenerated(result.text) else {
                errorText = "Claude's reply came back in a form Quill couldn't read. Try again."
                return
            }
            onResult(parsed.title, parsed.html, parsed.excerpt)
        } catch AnthropicError.cutOff(let tool, _) {
            // A cut-off JSON reply can't be read, so the only way forward is the longer budget.
            if let tool { onWebSearchTool(tool, modelID) }
            isGenerating = false
            if maxTokens < 16384 {
                showTruncationAlert = true
            } else {
                errorText = "The post was too long to finish. Try a shorter description."
            }
        } catch {
            errorText = error.localizedDescription
            isGenerating = false
        }
    }
}
