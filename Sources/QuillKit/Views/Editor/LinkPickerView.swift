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
    @FocusState private var fieldFocused: Bool

    private static let amber = Color(red: 0xb4 / 255.0, green: 0x53 / 255.0, blue: 0x09 / 255.0)

    var body: some View {
        VStack(spacing: 0) {
            // ── URL / search field + Apply button ────────
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    TextField("Search or paste URL", text: $model.fieldText)
                        .textFieldStyle(.plain)
                        .focused($fieldFocused)
                        .onSubmit { if !model.fieldText.isEmpty { model.onApply(model.fieldText) } }
                    if model.isSearching {
                        ProgressView().controlSize(.mini)
                    }
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
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            fieldFocused ? Self.amber : Color.primary.opacity(0.15),
                            lineWidth: 1
                        )
                )

                Button("Apply") { model.onApply(model.fieldText) }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Self.amber.opacity(model.fieldText.isEmpty ? 0.45 : 1))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .disabled(model.fieldText.isEmpty)
            }
            .padding(8)

            // ── Search results ────────────────────────────
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
                .frame(maxHeight: 200)
            }

            // ── Remove link (editing existing link only) ──
            if !model.currentHref.isEmpty {
                Divider()
                HStack {
                    Button("Remove link") { model.onRemove() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
        }
        .frame(width: 290)
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
