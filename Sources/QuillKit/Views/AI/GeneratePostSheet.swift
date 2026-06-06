import SwiftUI

struct GeneratePostSheet: View {
    let aiSettings: AISettings
    var onResult: (String, String) -> Void   // (title, html)
    var onCancel: () -> Void

    @State private var prompt: String = ""
    @State private var isGenerating: Bool = false
    @State private var statusText: String = ""
    @State private var errorText: String? = nil
    @State private var showTruncationAlert: Bool = false
    @State private var truncatedParsed: (title: String, html: String)? = nil
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Generate Post with Claude")
                .font(.headline)

            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text("Describe the post you want to write…")
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
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
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
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
        .alert("Post may be cut off", isPresented: $showTruncationAlert) {
            Button("Get Full Version") {
                Task { await generate(maxTokens: 16384) }
            }
            Button("Use What I Have") {
                if let parsed = truncatedParsed { onResult(parsed.title, parsed.html) }
            }
        } message: {
            Text("The generated post hit the initial length limit and may be incomplete. Get the full version? (Uses more API budget)")
        }
    }

    @MainActor
    private func generate(maxTokens: Int = 4096) async {
        isGenerating = true
        promptFocused = false
        errorText = nil
        truncatedParsed = nil
        statusText = aiSettings.webSearchEnabled ? "Searching the web…" : "Writing…"

        do {
            let client = AnthropicClient(apiKey: aiSettings.apiKey)
            let system = AIPromptBuilder.systemPrompt(styleGuide: aiSettings.styleGuide)
            let userMsg = AIPromptBuilder.generatePostPrompt(userPrompt: prompt)
            let result = try await client.complete(
                userMessage: userMsg,
                systemPrompt: system,
                useWebSearch: aiSettings.webSearchEnabled,
                maxTokens: maxTokens
            )

            guard let parsed = AIPromptBuilder.parseGenerateResponse(result.text) else {
                errorText = "Claude returned an unexpected format. Please try again."
                isGenerating = false
                return
            }

            isGenerating = false

            // Only prompt for the full version on the first (budget) pass.
            // If the high-budget pass also truncates, just use what we got.
            if result.truncated && maxTokens < 16384 {
                truncatedParsed = (parsed.title, parsed.html)
                showTruncationAlert = true
            } else {
                onResult(parsed.title, parsed.html)
            }
        } catch {
            errorText = error.localizedDescription
            isGenerating = false
        }
    }
}
