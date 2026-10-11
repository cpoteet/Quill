import Foundation
import Testing
@testable import QuillKit

private struct Unreachable: LocalizedError {
    var errorDescription: String? { "Couldn't reach your site." }
}

@MainActor
private func settle(_ model: LinkPickerModel) async {
    for _ in 0..<100 where model.isSearching || (model.searchError == nil && model.results.isEmpty) {
        try? await Task.sleep(for: .milliseconds(20))
    }
}

@MainActor
@Suite struct LinkPickerModelTests {

    @Test func aFailedSearchSaysWhy() async {
        let model = LinkPickerModel(currentHref: "", onApply: { _ in }, onRemove: {}, onSearch: { _ in throw Unreachable() })
        model.scheduleSearch("hello")
        await settle(model)
        #expect(model.searchError?.contains("Couldn't reach your site.") == true)
        #expect(!model.isSearching)
    }

    @Test func clearingTheFieldRemovesTheError() async {
        let model = LinkPickerModel(currentHref: "", onApply: { _ in }, onRemove: {}, onSearch: { _ in throw Unreachable() })
        model.scheduleSearch("hello")
        await settle(model)
        model.scheduleSearch("")
        #expect(model.searchError == nil)
    }

    private final class Replies: @unchecked Sendable {
        var fail = true
    }

    private let hit = LinkSearchResult(id: "post-1", title: "Hello", url: "https://example.com/hello", type: .post)

    @Test func aSearchThatWorksAgainClearsTheErrorAndListsTheResults() async {
        let replies = Replies()
        let hit = hit
        let model = LinkPickerModel(currentHref: "", onApply: { _ in }, onRemove: {}, onSearch: { _ in
            if replies.fail { throw Unreachable() }
            return [hit]
        })
        model.scheduleSearch("hello")
        await settle(model)
        #expect(model.searchError != nil)
        replies.fail = false
        model.scheduleSearch("hello again")
        for _ in 0..<100 where model.results.isEmpty { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(model.results.map(\.id) == ["post-1"])
        #expect(model.searchError == nil)
    }

    @Test func aFailedSearchEmptiesTheResultsTheLastOneListed() async {
        let replies = Replies()
        replies.fail = false
        let hit = hit
        let model = LinkPickerModel(currentHref: "", onApply: { _ in }, onRemove: {}, onSearch: { _ in
            if replies.fail { throw Unreachable() }
            return [hit]
        })
        model.scheduleSearch("hello")
        await settle(model)
        #expect(model.results.count == 1)
        replies.fail = true
        model.scheduleSearch("hello again")
        for _ in 0..<100 where model.searchError == nil { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(model.results.isEmpty)
        #expect(model.searchError != nil)
    }

    @Test func typingAURLRemovesTheErrorAndSearchesNothing() async {
        let model = LinkPickerModel(currentHref: "", onApply: { _ in }, onRemove: {}, onSearch: { _ in throw Unreachable() })
        model.scheduleSearch("hello")
        await settle(model)
        #expect(model.searchError != nil)
        model.fieldText = "https://example.com"
        model.scheduleSearch("https://example.com")
        #expect(model.searchError == nil)
        #expect(model.results.isEmpty)
    }
}
