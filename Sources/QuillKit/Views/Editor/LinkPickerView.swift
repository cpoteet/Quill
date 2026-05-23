import SwiftUI
import AppKit

final class LinkPickerModel: ObservableObject {
    @Published var fieldText: String
    @Published var results: [LinkSearchResult] = []
    @Published var isSearching = false

    let currentHref: String
    let onApply: (String) -> Void
    let onRemove: () -> Void
    let onSearch: (String) async throws -> [LinkSearchResult]

    private var searchTask: Task<Void, Never>?

    var looksLikeURL: Bool {
        fieldText.hasPrefix("http://") || fieldText.hasPrefix("https://")
            || fieldText.hasPrefix("/") || fieldText.hasPrefix("#")
    }

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
        self.fieldText = currentHref
    }

    func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        if text.isEmpty || looksLikeURL {
            results = []
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await MainActor.run { self.isSearching = true }
            let found = (try? await onSearch(text)) ?? []
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.results = found
                self.isSearching = false
            }
        }
    }
}

struct LinkPickerView: View {
    @ObservedObject var model: LinkPickerModel

    var body: some View {
        VStack(spacing: 0) {
            // ── URL / search field ────────────────────────
            HStack(spacing: 6) {
                TextField("Search or paste URL", text: $model.fieldText)
                    .textFieldStyle(.plain)
                    .onSubmit { if !model.fieldText.isEmpty { model.onApply(model.fieldText) } }
                if !model.fieldText.isEmpty {
                    Button {
                        model.fieldText = ""
                        model.results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                if model.isSearching {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // ── Results ───────────────────────────────────
            if !model.results.isEmpty {
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.results) { result in
                            ResultRow(result: result) {
                                model.fieldText = result.url
                                model.results = []
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            // ── Bottom buttons ────────────────────────────
            Divider()
            HStack {
                if !model.currentHref.isEmpty {
                    Button("Remove Link") { model.onRemove() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Apply Link") { model.onApply(model.fieldText) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.fieldText.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 320)
        .onChange(of: model.fieldText, perform: model.scheduleSearch)
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
