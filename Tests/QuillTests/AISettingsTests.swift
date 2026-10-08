import Foundation
import Testing
@testable import QuillKit

@Suite struct AISettingsTests {

    @Test func decodesSettingsWrittenBeforeModelSelection() throws {
        let old = #"{"apiKey":"k","samplePostIDs":[1],"webSearchEnabled":true,"styleGuide":"g"}"#
        let s = try JSONDecoder().decode(AISettings.self, from: Data(old.utf8))
        #expect(s.model == nil && s.reasoning == .modelDefault && s.models.isEmpty && s.webSearchToolByModel.isEmpty)
        #expect(s.apiKey == "k" && s.samplePostIDs == [1] && s.styleGuide == "g")
    }

    @Test func roundTripsNewFields() throws {
        var s = AISettings(apiKey: "k")
        s.model = "claude-sonnet-5-5"; s.reasoning = .level("high"); s.models = [haiku55]
        s.webSearchToolByModel = ["claude-haiku-5-5": "web_search_20260318"]
        let back = try JSONDecoder().decode(AISettings.self, from: JSONEncoder().encode(s))
        #expect(back.model == s.model && back.reasoning == s.reasoning && back.models == s.models)
        #expect(back.webSearchToolByModel == s.webSearchToolByModel)
    }

    @Test func defaultModelIsNewestHaiku() {
        var s = AISettings(); s.models = [haiku45, haiku55, sonnet55]
        #expect(s.resolvedModelID() == "claude-haiku-5-5")
    }

    @Test func defaultModelFallsBackWithoutAList() { #expect(AISettings().resolvedModelID() == "claude-haiku-5-5") }

    @Test func defaultModelFallsBackWithoutAHaiku() {
        var s = AISettings(); s.models = [sonnet55]
        #expect(s.resolvedModelID() == "claude-haiku-5-5")
        #expect(s.resolvedModel() == nil)
    }

    @Test func pinnedModelWins() {
        var s = AISettings(); s.models = [haiku55, sonnet55]; s.model = "claude-sonnet-5-5"
        #expect(s.resolvedModelID() == "claude-sonnet-5-5")
        #expect(s.resolvedModel() == sonnet55)
    }

    @Test func adaptiveOptionsHaveNoOff() {
        #expect(AISettings.reasoningOptions(for: haiku55) == [.modelDefault, .level("low"), .level("medium"), .level("high"), .level("xhigh"), .level("max")])
    }

    @Test func adaptiveOptionsListOnlyTheModelsLevelsInOrder() {
        var limited = haiku55; limited.effortLevels = ["max", "low", "high"]
        #expect(AISettings.reasoningOptions(for: limited) == [.modelDefault, .level("low"), .level("high"), .level("max")])
    }

    @Test func enabledOnlyOptions() { #expect(AISettings.reasoningOptions(for: haiku45) == [.off, .level("low"), .level("medium"), .level("high")]) }

    @Test func unknownModelOnlyOff() { #expect(AISettings.reasoningOptions(for: nil) == [.off]) }

    @Test func switchingToEnabledOnlyResetsModelDefaultToOff() {
        var s = AISettings(); s.models = [haiku45]; s.model = "claude-haiku-4-5"; s.reasoning = .modelDefault
        #expect(s.normalizedReasoning() == .off)
    }

    @Test func switchingToAdaptiveResetsOffToModelDefault() {
        var s = AISettings(); s.models = [haiku55]; s.reasoning = .off
        #expect(s.normalizedReasoning() == .modelDefault)
    }

    @Test func offeredReasoningIsKept() {
        var s = AISettings(); s.models = [haiku55]; s.reasoning = .level("xhigh")
        #expect(s.normalizedReasoning() == .level("xhigh"))
    }

    @MainActor @Test func reasoningLabelsReadAsWords() {
        #expect(PreferencesView.label(for: .off) == "Off")
        #expect(PreferencesView.label(for: .modelDefault) == "Model default")
        #expect(PreferencesView.label(for: .level("xhigh")) == "Extra High")
        #expect(["low", "medium", "high", "max"].map { PreferencesView.label(for: .level($0)) } == ["Low", "Medium", "High", "Max"])
    }

    // MARK: - applyingFetchedModels

    @Test func fetchKeepsPinnedModelThatStillExists() {
        var s = AISettings(); s.model = "claude-sonnet-5-5"; s.reasoning = .level("high")
        let (next, notice) = s.applyingFetchedModels([haiku55, sonnet55])
        #expect(next.model == "claude-sonnet-5-5" && next.reasoning == .level("high") && notice == nil)
        #expect(next.models == [haiku55, sonnet55])
    }

    @Test func fetchDropsMissingPinnedModelWithNotice() {
        var s = AISettings(); s.model = "claude-opus-3"
        let (next, notice) = s.applyingFetchedModels([haiku45, haiku55, sonnet55])
        #expect(next.model == nil)
        #expect(next.resolvedModelID() == "claude-haiku-5-5")
        #expect(notice == "Your saved model is no longer available. Switched to Claude Haiku 5.5.")
    }

    @Test func fetchWithoutPinnedModelHasNoNotice() {
        let (next, notice) = AISettings().applyingFetchedModels([haiku55])
        #expect(next.model == nil && notice == nil && next.models == [haiku55])
    }

    @Test func fetchNormalizesReasoningForTheResolvedModel() {
        var s = AISettings(); s.model = "claude-haiku-4-5"; s.reasoning = .level("xhigh")
        let (next, _) = s.applyingFetchedModels([haiku45])
        #expect(next.reasoning == .off)
    }

    @Test func rememberedWebSearchToolIsUsedWhileTheVersionListIsUnchanged() {
        var s = AISettings()
        s.rememberWebSearchTool("web_search_20260209", for: "claude-haiku-5-5")
        #expect(s.knownWebSearchTool(for: "claude-haiku-5-5") == "web_search_20260209")
    }

    @Test func rememberedWebSearchToolIsIgnoredOnceANewerVersionShips() throws {
        let old = #"{"apiKey":"k","samplePostIDs":[],"webSearchEnabled":true,"webSearchToolByModel":{"claude-haiku-5-5":"web_search_20260209"},"webSearchVersionsHead":"web_search_20250305"}"#
        let s = try JSONDecoder().decode(AISettings.self, from: Data(old.utf8))
        #expect(s.knownWebSearchTool(for: "claude-haiku-5-5") == nil)
    }

    @Test func settingsWithoutAVersionsHeadReprobe() throws {
        let old = #"{"apiKey":"k","samplePostIDs":[],"webSearchEnabled":true,"webSearchToolByModel":{"claude-haiku-5-5":"web_search_20260209"}}"#
        let s = try JSONDecoder().decode(AISettings.self, from: Data(old.utf8))
        #expect(s.knownWebSearchTool(for: "claude-haiku-5-5") == nil)
    }

    @Test func rememberingAfterANewerVersionShipsDropsToolsProbedAgainstTheOldList() throws {
        let old = #"{"apiKey":"k","samplePostIDs":[],"webSearchEnabled":true,"webSearchToolByModel":{"claude-sonnet-5-5":"web_search_20260209"},"webSearchVersionsHead":"web_search_20250305"}"#
        var s = try JSONDecoder().decode(AISettings.self, from: Data(old.utf8))
        s.rememberWebSearchTool("web_search_20260318", for: "claude-haiku-5-5")
        #expect(s.webSearchToolByModel == ["claude-haiku-5-5": "web_search_20260318"])
        #expect(s.knownWebSearchTool(for: "claude-haiku-5-5") == "web_search_20260318")
    }
}
