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

    public enum Page: Hashable, CaseIterable {
        case fixes, ideas, facts
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

    /// How many findings a page holds once its request is done; nil while it runs, or if it failed or is unavailable.
    public func count(_ page: Page) -> Int? {
        switch page {
        case .fixes: review.value?.corrections.count
        case .ideas: review.value?.suggestions.count
        case .facts: facts.value?.checks.count
        }
    }

    public func isLoading(_ page: Page) -> Bool {
        switch page {
        case .fixes, .ideas: if case .loading = review { return true }
        case .facts: if case .loading = facts { return true }
        }
        return false
    }
}

extension EvaluationState.Half: Equatable where T: Equatable {}
