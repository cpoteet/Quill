import SwiftUI

public enum EvaluationPanelState {
    case shortContent
    case error(String)
    case evaluation(EvaluationState)
}

public struct EvaluationPanel: View {
    let state: EvaluationPanelState
    let onReEvaluate: () -> Void
    let onFindingSelected: (String) -> Void
    let onApply: ([UUID]) -> Void
    let onShowPage: () -> Void

    @State private var page: EvaluationState.Page?

    public init(
        state: EvaluationPanelState,
        onReEvaluate: @escaping () -> Void,
        onFindingSelected: @escaping (String) -> Void,
        onApply: @escaping ([UUID]) -> Void,
        onShowPage: @escaping () -> Void
    ) {
        self.state = state
        self.onReEvaluate = onReEvaluate
        self.onFindingSelected = onFindingSelected
        self.onApply = onApply
        self.onShowPage = onShowPage
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .onChange(of: evaluationID) { page = nil }
        .onChange(of: page) { onShowPage() }
    }

    private var evaluationID: UUID? {
        if case .evaluation(let evaluation) = state { return evaluation.id }
        return nil
    }

    private static func title(_ page: EvaluationState.Page) -> String {
        switch page {
        case .fixes: "Fixes"
        case .ideas: "Ideas"
        case .facts: "Facts to Check"
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let page, case .evaluation(let evaluation) = state {
                Button { self.page = nil } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                    .help("Back")
                    .accessibilityLabel("Back")
                Text(Self.title(page)).font(.headline)
                Spacer()
                if page == .fixes, let corrections = evaluation.review.value?.corrections, !corrections.isEmpty {
                    Button("Apply All") { onApply(evaluation.applyAllTargets.map(\.id)) }
                        .controlSize(.small)
                        .disabled(evaluation.applyAllTargets.isEmpty)
                }
            } else {
                Text("Content Evaluation").font(.headline)
                Spacer()
            }
        }
        .frame(minHeight: 20)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .shortContent:
            Text("Add more content before evaluating.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
        case .error(let message):
            PaneError(title: "Evaluation failed", message: message, retry: onReEvaluate)
        case .evaluation(let evaluation):
            evaluationView(evaluation)
        }
    }

    private func evaluationView(_ evaluation: EvaluationState) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch page {
                    case nil: overview(evaluation)
                    case .fixes: findingsPage(evaluation, empty: "No corrections.") { $0.corrections }
                    case .ideas: findingsPage(evaluation, empty: "No suggestions.") { $0.suggestions }
                    case .facts: factsPage(evaluation)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            Button(action: onReEvaluate) { Label("Re-evaluate", systemImage: "arrow.clockwise") }
                .controlSize(.small)
                .disabled(evaluation.isRunning)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }

    // MARK: - Overview

    @ViewBuilder
    private func overview(_ evaluation: EvaluationState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch evaluation.review {
            case .loading, .unavailable:
                progress("Reviewing\u{2026}")
            case .failed(let message):
                InlineError(message: message)
            case .done(let result):
                Text(result.review.strengths)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(result.review.priorities.enumerated()), id: \.offset) { index, priority in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                        Text(priority).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        ForEach(EvaluationState.Page.allCases, id: \.self) { page in
            Divider()
            PageRow(title: Self.title(page), count: evaluation.count(page), isLoading: evaluation.isLoading(page)) {
                self.page = page
            }
        }
        Divider()
    }

    // MARK: - Fixes and Ideas

    @ViewBuilder
    private func findingsPage(_ evaluation: EvaluationState, empty: String,
                              findings: (ReviewResult) -> [ReviewFinding]) -> some View {
        switch evaluation.review {
        case .loading, .unavailable:
            progress("Reviewing\u{2026}").padding(16)
        case .failed(let message):
            InlineError(message: message).padding(16)
        case .done(let result):
            let items = findings(result)
            if items.isEmpty {
                Text(empty)
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, finding in
                if index > 0 { Divider() }
                FindingRow(
                    finding: finding,
                    applied: evaluation.isApplied(finding.id),
                    note: evaluation.applyNote(finding.id),
                    canApply: evaluation.canApply(finding.id),
                    onJump: { onFindingSelected(finding.original) },
                    onApply: { onApply([finding.id]) }
                )
            }
        }
    }

    // MARK: - Facts

    @ViewBuilder
    private func factsPage(_ evaluation: EvaluationState) -> some View {
        switch evaluation.facts {
        case .loading:
            progress("Checking facts\u{2026}").padding(16)
        case .unavailable:
            Text(evaluation.factsUnavailableMessage)
                .foregroundStyle(.secondary)
                .padding(16)
        case .failed(let message):
            InlineError(message: message).padding(16)
        case .done(let result):
            Text("\(result.claimsChecked) claim\(result.claimsChecked == 1 ? "" : "s") checked")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            if result.checks.isEmpty {
                Text("Nothing to check.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            ForEach(result.checks) { check in
                Divider()
                FactCheckRow(
                    check: check,
                    applied: evaluation.isApplied(check.id),
                    note: evaluation.applyNote(check.id),
                    canApply: evaluation.canApply(check.id),
                    onJump: { onFindingSelected(check.original) },
                    onApply: { onApply([check.id]) }
                )
            }
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

private struct PageRow: View {
    let title: String
    let count: Int?
    let isLoading: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.mini)
                } else if let count {
                    Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isHovering ? Color.primary.opacity(0.06) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityValue(isLoading ? "Loading" : count.map(String.init) ?? "")
    }
}

/// Apply, Applied, or why Apply isn't offered.
private struct ApplyControl: View {
    let title: String
    let applied: Bool
    let note: String?
    let canApply: Bool
    let help: String?
    let onApply: () -> Void

    var body: some View {
        if applied {
            Label("Applied", systemImage: "checkmark")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if let note {
            Text(note)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Button(title, action: onApply)
                .controlSize(.small)
                .disabled(!canApply)
                .help(help ?? "")
        }
    }
}

private struct FindingRow: View {
    let finding: ReviewFinding
    let applied: Bool
    let note: String?
    let canApply: Bool
    let onJump: () -> Void
    let onApply: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(finding.category)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                ApplyControl(title: "Apply", applied: applied, note: note, canApply: canApply, help: nil, onApply: onApply)
            }
            change.fixedSize(horizontal: false, vertical: true)
            Text(finding.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHovering ? Color.primary.opacity(0.06) : .clear)
        .opacity(applied ? 0.5 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onJump)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Show in Post", onJump)
    }

    private var change: Text {
        let old = Text(finding.original).strikethrough().foregroundStyle(.secondary)
        if finding.replacement.isEmpty { return old }
        return Text("\(old) \u{2192} \(finding.replacement)")
    }
}

private struct FactCheckRow: View {
    let check: FactCheck
    let applied: Bool
    let note: String?
    let canApply: Bool
    let onJump: () -> Void
    let onApply: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("\u{201C}\(check.original)\u{201D}")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if !check.replacement.isEmpty {
                    ApplyControl(title: "Use Wording", applied: applied, note: note, canApply: canApply,
                                 help: check.replacement, onApply: onApply)
                }
            }
            Text(check.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !check.sourceQuote.isEmpty {
                Text("\u{201C}\(check.sourceQuote)\u{201D}")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(.quaternary).frame(width: 2)
                    }
            }
            if let url = URL(string: check.sourceURL), let host = url.host() {
                Link("\(host.hasPrefix("www.") ? String(host.dropFirst(4)) : host) \u{2197}", destination: url)
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHovering ? Color.primary.opacity(0.06) : .clear)
        .opacity(applied ? 0.5 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onJump)
        .onHover { isHovering = $0 }
    }
}
