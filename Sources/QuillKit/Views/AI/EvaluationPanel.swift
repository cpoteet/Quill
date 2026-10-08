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
    let onShowTab: () -> Void

    @State private var tab: EvaluationState.Tab = .review

    public init(
        state: EvaluationPanelState,
        onReEvaluate: @escaping () -> Void,
        onFindingSelected: @escaping (String) -> Void,
        onApply: @escaping ([UUID]) -> Void,
        onShowTab: @escaping () -> Void
    ) {
        self.state = state
        self.onReEvaluate = onReEvaluate
        self.onFindingSelected = onFindingSelected
        self.onApply = onApply
        self.onShowTab = onShowTab
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    private var header: some View {
        Text("Content Evaluation")
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            Picker("Show", selection: $tab) {
                ForEach(EvaluationState.Tab.allCases, id: \.self) { Text(evaluation.tabLabel($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch tab {
                    case .review: reviewTab(evaluation)
                    case .fixes: findingsTab(evaluation, title: "Corrections", applyAll: true) { $0.corrections }
                    case .ideas: findingsTab(evaluation, title: "Suggestions", applyAll: false) { $0.suggestions }
                    case .facts: factsTab(evaluation)
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
        .onChange(of: evaluation.id) { tab = .review }
        .onChange(of: tab) { onShowTab() }
    }

    // MARK: - Review

    @ViewBuilder
    private func reviewTab(_ evaluation: EvaluationState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !evaluation.countsLine.isEmpty {
                Text(evaluation.countsLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
    }

    // MARK: - Fixes and Ideas

    @ViewBuilder
    private func findingsTab(_ evaluation: EvaluationState, title: String, applyAll: Bool,
                             findings: (ReviewResult) -> [ReviewFinding]) -> some View {
        switch evaluation.review {
        case .loading, .unavailable:
            progress("Reviewing\u{2026}").padding(16)
        case .failed(let message):
            InlineError(message: message).padding(16)
        case .done(let result):
            let items = findings(result)
            HStack {
                SectionLabel(title)
                Spacer()
                if applyAll && !items.isEmpty {
                    Button("Apply All") { onApply(evaluation.applyAllTargets.map(\.id)) }
                        .controlSize(.small)
                        .disabled(evaluation.applyAllTargets.isEmpty)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
            if items.isEmpty {
                Text(applyAll ? "No corrections." : "No suggestions.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            ForEach(items) { finding in
                Divider()
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
    private func factsTab(_ evaluation: EvaluationState) -> some View {
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
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Check These")
                Spacer()
                Text("\(result.claimsChecked) claim\(result.claimsChecked == 1 ? "" : "s") checked")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
