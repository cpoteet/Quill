import SwiftUI

public enum EvaluationPanelState {
    case shortContent
    case loading
    case result(EvaluationResult)
    case error(String)
}

public struct EvaluationPanel: View {
    let state: EvaluationPanelState
    let onReEvaluate: () -> Void
    let onFindingSelected: (String) -> Void

    public init(
        state: EvaluationPanelState,
        onReEvaluate: @escaping () -> Void,
        onFindingSelected: @escaping (String) -> Void
    ) {
        self.state = state
        self.onReEvaluate = onReEvaluate
        self.onFindingSelected = onFindingSelected
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
            .font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .shortContent: shortContentView
        case .loading:      loadingView
        case .result(let r): resultView(r)
        case .error(let msg): errorView(msg)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Evaluating content…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var shortContentView: some View {
        VStack(spacing: 8) {
            Text("Add more content before evaluating.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func resultView(_ result: EvaluationResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(result.summary)
                    .font(.callout)
                    .lineSpacing(2)
                    .padding(16)

                Divider()

                let countLabel = result.findings.isEmpty
                    ? "No specific issues found"
                    : "\(result.findings.count) finding\(result.findings.count == 1 ? "" : "s") — click to jump"

                SectionLabel(countLabel)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, result.findings.isEmpty ? 12 : 8)

                if !result.findings.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(Array(result.findings.enumerated()), id: \.offset) { _, finding in
                            EvaluationFindingCard(
                                finding: finding,
                                onTap: { onFindingSelected(finding.anchor ?? finding.quote) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }

                Divider()
                Button("↺  Re-evaluate") { onReEvaluate() }
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text("Evaluation failed.")
                .font(.callout.weight(.medium))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { onReEvaluate() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct EvaluationFindingCard: View {
    let finding: EvaluationFinding
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(finding.issue.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .tracking(0.5)
                Text("\"\(finding.quote)\"")
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let suggestion = finding.suggestion {
                    Text("→ \(suggestion)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
