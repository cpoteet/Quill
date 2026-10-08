import Foundation
import Testing
@testable import QuillKit

@Suite struct EvaluationStateTests {

    private func review(corrections: Int = 2, suggestions: Int = 1) throws -> ReviewResult {
        func items(_ n: Int, _ category: String, _ prefix: String) -> String {
            (0..<n).map { #"{"category":"\#(category)","original":"\#(prefix)\#($0)","replacement":"new\#(prefix)\#($0)","explanation":"x"}"# }
                .joined(separator: ",")
        }
        return try EvaluationPrompts.parseReview(#"""
        {"review":{"strengths":"Good.","priorities":["One."]},
         "corrections":[\#(items(corrections, "Spelling", "c"))],"suggestions":[\#(items(suggestions, "Clarity", "s"))]}
        """#)
    }

    private func facts(_ n: Int = 1, claims: Int = 4) throws -> FactCheckResult {
        let checks = (0..<n).map { #"{"original":"f\#($0)","explanation":"e","source_quote":"q","source_url":"https://learn.microsoft.com/a","replacement":""}"# }
        let claimList = (0..<claims).map { #"{"claim":"c\#($0)","verdict":"confirmed"}"# }
        return try EvaluationPrompts.parseFactCheck(#"{"claims":[\#(claimList.joined(separator: ","))],"fact_checks":[\#(checks.joined(separator: ","))]}"#)
    }

    @Test func startsLoadingBothHalves() {
        let state = EvaluationState(searchAvailable: true)
        #expect(state.review == .loading && state.facts == .loading && state.isRunning)
    }

    @Test func unavailableFactsWhenSearchOff() {
        let state = EvaluationState(searchAvailable: false)
        #expect(state.facts == .unavailable)
        #expect(state.factsUnavailableMessage == "Turn on Web Search in Settings to check facts.")
    }

    @Test func factsNoticeNamesTheModelWhenItCantSearch() {
        let state = EvaluationState(searchAvailable: false, modelCanSearch: false)
        #expect(state.facts == .unavailable)
        #expect(state.factsUnavailableMessage == "This model can't search the web. Choose another model in Settings to check facts.")
    }

    @Test func factsFailureKeepsReview() throws {
        var state = EvaluationState(searchAvailable: true)
        let result = try review()
        state.review = .done(result)
        state.facts = .failed("Claude declined this request.")
        #expect(state.review.value?.corrections.count == 2)
        #expect(state.facts == .failed("Claude declined this request."))
        #expect(!state.isRunning)
    }

    @Test func reviewFailureKeepsFacts() throws {
        var state = EvaluationState(searchAvailable: true)
        state.facts = .done(try facts())
        state.review = .failed("You've hit Anthropic's rate limit.")
        #expect(state.facts.value?.checks.count == 1)
        #expect(state.review == .failed("You've hit Anthropic's rate limit."))
    }

    @Test func appliedFindingIsMarked() throws {
        var state = EvaluationState(searchAvailable: false)
        let result = try review()
        state.review = .done(result)
        let finding = result.corrections[0]
        state.markApplied(finding.id)
        #expect(state.isApplied(finding.id))
        #expect(!state.canApply(finding.id))
        #expect(!state.isApplied(result.corrections[1].id))
    }

    @Test func statusesComeBackInOrder() throws {
        var state = EvaluationState(searchAvailable: true)
        let result = try review()
        state.review = .done(result)
        state.facts = .done(try facts(2))
        let ids = state.applicableIDs
        #expect(ids.count == 3)
        state.updateStatuses(ids: ids, statuses: ["ok", "missing", "ambiguous"])
        #expect(state.canApply(ids[0]) && !state.canApply(ids[1]) && !state.canApply(ids[2]))
        #expect(state.applyNote(ids[1]) == "Text has changed")
        #expect(state.applyNote(ids[2]) == "Appears more than once")
        #expect(state.applyNote(ids[0]) == nil)
    }

    @Test func factChecksWithoutReplacementAreNotApplicable() throws {
        var state = EvaluationState(searchAvailable: true)
        state.review = .done(try review(corrections: 0, suggestions: 0))
        state.facts = .done(try facts(2))
        #expect(state.applicableIDs.isEmpty)
    }

    @Test func applyAllSkipsMissingAndAmbiguous() throws {
        var state = EvaluationState(searchAvailable: false)
        let result = try review(corrections: 4)
        state.review = .done(result)
        let ids = result.corrections.map(\.id)
        state.updateStatuses(ids: ids + result.suggestions.map(\.id), statuses: ["ok", "missing", "ambiguous", "ok", "ok"])
        state.markApplied(ids[3])
        #expect(state.applyAllTargets.map(\.id) == [ids[0]])
    }

    @Test func unknownStatusMeansNotYetChecked() throws {
        var state = EvaluationState(searchAvailable: false)
        let result = try review()
        state.review = .done(result)
        #expect(!state.canApply(result.corrections[0].id))
        #expect(state.applyNote(result.corrections[0].id) == nil)
    }

    @Test func pageCountsWaitForTheirOwnRequest() throws {
        var state = EvaluationState(searchAvailable: true)
        #expect(state.isLoading(.fixes) && state.isLoading(.ideas) && state.isLoading(.facts))
        #expect(state.count(.fixes) == nil)
        state.review = .done(try review(corrections: 7, suggestions: 0))
        #expect(!state.isLoading(.fixes) && !state.isLoading(.ideas) && state.isLoading(.facts))
        #expect(state.count(.fixes) == 7)
        #expect(state.count(.ideas) == 0)
        #expect(state.count(.facts) == nil)
        state.facts = .done(try facts(3))
        #expect(!state.isLoading(.facts))
        #expect(state.count(.facts) == 3)
    }

    @Test func failedOrUnavailablePagesHaveNoCount() throws {
        var state = EvaluationState(searchAvailable: false)
        state.review = .failed("Overloaded")
        #expect(!state.isLoading(.fixes) && !state.isLoading(.facts))
        #expect(state.count(.fixes) == nil)
        #expect(state.count(.facts) == nil)
    }
}
