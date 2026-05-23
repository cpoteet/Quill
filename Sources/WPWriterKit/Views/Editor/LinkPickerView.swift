import SwiftUI
import AppKit

struct LinkPickerView: View {
    let currentHref: String
    let onApply: (String) -> Void
    let onRemove: () -> Void
    let onSearch: (String) async throws -> [LinkSearchResult]

    @State private var fieldText: String
    @State private var results: [LinkSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    init(
        currentHref: String,
        onApply: @escaping (String) -> Void,
        onRemove: @escaping () -> Void,
        onSearch: @escaping (String) async throws -> [LinkSearchResult]
    ) {
        self.currentHref = currentHref
        self.onApply = onApply
        self.onRemove = onRemove
        self.onSearch = onSearch
        self._fieldText = State(initialValue: currentHref)
    }

    private var looksLikeURL: Bool {
        fieldText.hasPrefix("http://") || fieldText.hasPrefix("https://")
            || fieldText.hasPrefix("/") || fieldText.hasPrefix("#")
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── URL / search field ────────────────────────
            HStack(spacing: 6) {
                TextField("Search or paste URL", text: $fieldText)
                    .textFieldStyle(.plain)
                    .onSubmit { if !fieldText.isEmpty { onApply(fieldText) } }
                if !fieldText.isEmpty {
                    Button {
                        fieldText = ""
                        results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                if isSearching {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            // ── Results ───────────────────────────────────
            if !results.isEmpty {
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { result in
                            ResultRow(result: result) {
                                fieldText = result.url
                                results = []
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            // ── Bottom buttons ────────────────────────────
            Divider()
            HStack {
                if !currentHref.isEmpty {
                    Button("Remove Link") { onRemove() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Apply Link") { onApply(fieldText) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(fieldText.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
        .onChange(of: fieldText, perform: scheduleSearch)
    }

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        if text.isEmpty || looksLikeURL {
            results = []
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await MainActor.run { isSearching = true }
            let found = (try? await onSearch(text)) ?? []
            guard !Task.isCancelled else { return }
            await MainActor.run {
                results = found
                isSearching = false
            }
        }
    }
}

private struct ResultRow: View {
    let result: LinkSearchResult
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(result.title)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer()
                Text(result.type.badge)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
