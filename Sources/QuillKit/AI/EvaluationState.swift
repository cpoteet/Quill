import Foundation

/// What the Evaluate panel shows: two requests that land independently, and which findings have been applied.
public struct EvaluationState {
    public enum Half<T> {
        case loading
        case done(T)
        case failed(String)
        case unavailable

        public var value: T? {
            if case .done(let value) = self { return value }
            return nil
        }
    }

    public enum Tab: Hashable, CaseIterable {
        case review, fixes, ideas, facts
    }


    /// One evaluation run; a re-evaluate gets a new one.
    public let id = UUID()
    public var review: Half<ReviewResult> = .loading
    public var facts: Half<FactCheckResult>
    public var applied: Set<UUID> = []
    /// `ok`, `missing` or `ambiguous` from the editor's `findingStatus`, by finding ID.
    public var statuses: [UUID: String] = [:]

    public let factsUnavailableMessage: String

    public init(searchAvailable: Bool, modelCanSearch: Bool = true) {
        facts = searchAvailable ? .loading : .unavailable
        factsUnavailableMessage = modelCanSearch
            ? "Turn on Web Search in Settings to check facts."
            : "This model can't search the web. Choose another model in Settings to check facts."
    }

    public var isRunning: Bool {
        if case .loading = review { return true }
        if case .loading = facts { return true }
        return false
    }

    /// Every finding Apply can act on, in panel order: corrections, suggestions, then fact checks with a wording.
    public var applicable: [(id: UUID, original: String, replacement: String)] {
        let findings = (review.value?.corrections ?? []) + (review.value?.suggestions ?? [])
        let checks = (facts.value?.checks ?? []).filter { !$0.replacement.isEmpty }
        return findings.map { ($0.id, $0.original, $0.replacement) } + checks.map { ($0.id, $0.original, $0.replacement) }
    }

    public var applicableIDs: [UUID] { applicable.map(\.id) }

    public mutating func updateStatuses(ids: [UUID], statuses: [String]) {
        for (id, status) in zip(ids, statuses) { self.statuses[id] = status }
    }

    public mutating func markApplied(_ id: UUID) {
        applied.insert(id)
    }

    public func isApplied(_ id: UUID) -> Bool { applied.contains(id) }

    public func canApply(_ id: UUID) -> Bool { !applied.contains(id) && statuses[id] == "ok" }

    /// Why Apply isn't offered for an unapplied finding the editor has checked; nil when it is, or not yet checked.
    public func applyNote(_ id: UUID) -> String? {
        guard !applied.contains(id) else { return nil }
        switch statuses[id] {
        case "missing": return "Text has changed"
        case "ambiguous": return "Appears more than once"
        default: return nil
        }
    }

    public var applyAllTargets: [ReviewFinding] {
        (review.value?.corrections ?? []).filter { canApply($0.id) }
    }

    public var countsLine: String {
        func count(_ n: Int, _ one: String, _ many: String) -> String {
            n == 0 ? "no \(many)" : n == 1 ? "1 \(one)" : "\(n) \(many)"
        }
        var parts: [String] = []
        if let result = review.value {
            parts.append(count(result.corrections.count, "fix", "fixes"))
            parts.append(count(result.suggestions.count, "idea", "ideas"))
        }
        switch facts {
        case .loading: parts.append("checking facts…")
        case .done(let result): parts.append(count(result.checks.count, "fact to check", "facts to check"))
        case .failed, .unavailable: break
        }
        return parts.joined(separator: ", ")
    }

    public func tabLabel(_ tab: Tab) -> String {
        func labelled(_ name: String, _ n: Int?) -> String {
            guard let n, n > 0 else { return name }
            return "\(name) \(n)"
        }
        switch tab {
        case .review: return "Review"
        case .fixes: return labelled("Fixes", review.value?.corrections.count)
        case .ideas: return labelled("Ideas", review.value?.suggestions.count)
        case .facts:
            if case .loading = facts { return "Facts …" }
            return labelled("Facts", facts.value?.checks.count)
        }
    }
}

extension EvaluationState.Half: Equatable where T: Equatable {}
