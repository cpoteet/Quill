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
}
