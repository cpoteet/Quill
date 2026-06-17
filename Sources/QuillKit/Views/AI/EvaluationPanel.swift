import SwiftUI

public enum EvaluationPanelState {
    case shortContent
    case loading
    case result(EvaluationResult)
    case error(String)
}

public struct EvaluationPanel: View {
    let state: EvaluationPanelState
    let onClose: () -> Void
    let onReEvaluate: () -> Void
    let onFindingSelected: (String) -> Void

    public init(
        state: EvaluationPanelState,
        onClose: @escaping () -> Void,
        onReEvaluate: @escaping () -> Void,
        onFindingSelected: @escaping (String) -> Void
    ) {
        self.state = state
        self.onClose = onClose
        self.onReEvaluate = onReEvaluate
        self.onFindingSelected = onFindingSelected
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            SoftHorizontalDivider()
            content
        }
        .frame(width: 260)
        .background(WarmSidebarBackground())
        .overlay(alignment: .leading) { PanelInteriorFade(from: .leading) }
    }

    private var header: some View {
        HStack {
            Text("Post Evaluation")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button("Close") { onClose() }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(WarmPanelHeaderBackground())
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
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var shortContentView: some View {
        VStack(spacing: 8) {
            Text("Add more content before evaluating.")
                .font(.system(size: 12))
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
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .padding(16)

                SoftHorizontalDivider()

                let countLabel = result.findings.isEmpty
                    ? "No specific issues found"
                    : "\(result.findings.count) finding\(result.findings.count == 1 ? "" : "s") — click to jump"

                Text(countLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
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

                SoftHorizontalDivider()
                Button("↺  Re-evaluate") { onReEvaluate() }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text("Evaluation failed.")
                .font(.system(size: 12, weight: .medium))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { onReEvaluate() }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.wpAmber, in: RoundedRectangle(cornerRadius: 5))
                .buttonStyle(.plain)
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
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.wpAmber)
                    .tracking(0.5)
                Text("\"\(finding.quote)\"")
                    .font(.system(size: 11))
                    .italic()
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let suggestion = finding.suggestion {
                    Text("→ \(suggestion)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.wpAmber.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.wpAmber.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
