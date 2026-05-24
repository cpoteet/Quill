import SwiftUI

struct GeneratePostSheet: View {
    let aiSettings: AISettings
    var onResult: (String, String) -> Void   // (title, html)
    var onCancel: () -> Void

    @State private var prompt: String = ""
    @State private var isGenerating: Bool = false
    @State private var statusText: String = ""
    @State private var errorText: String? = nil

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
    }

    @MainActor
    private func generate() async {
        isGenerating = true
        errorText = nil
        statusText = aiSettings.webSearchEnabled ? "Searching the web…" : "Writing…"

        do {
            let client = AnthropicClient(apiKey: aiSettings.apiKey)
            let system = AIPromptBuilder.systemPrompt(styleGuide: aiSettings.styleGuide)
            let userMsg = AIPromptBuilder.generatePostPrompt(userPrompt: prompt)
            let response = try await client.complete(
                userMessage: userMsg,
                systemPrompt: system,
                useWebSearch: aiSettings.webSearchEnabled
            )

            guard let parsed = AIPromptBuilder.parseGenerateResponse(response) else {
                errorText = "Claude returned an unexpected format. Please try again."
                isGenerating = false
                return
            }

            isGenerating = false
            onResult(parsed.title, parsed.html)
        } catch {
            errorText = error.localizedDescription
            isGenerating = false
        }
    }
}
