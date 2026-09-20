import SwiftUI
import Testing
@testable import QuillKit

// statusSymbol and statusColor are parallel switches over the same badge set; these
// stop one gaining a case the other does not.
@Suite struct StatusBadgeTests {

    private static let badges = ["publish", "draft", "future", "pending", "private", "local-post", "local-page"]

    @Test func everyBadgeHasItsOwnSymbol() {
        for badge in Self.badges {
            #expect(statusSymbol(badge) != statusSymbol("an-unknown-status"), "\(badge) fell through to the default symbol")
        }
    }

    @Test func everyBadgeHasItsOwnColor() {
        for badge in Self.badges {
            #expect(Color.statusColor(badge) != Color.statusColor("an-unknown-status"), "\(badge) fell through to the default colour")
        }
    }

    @Test func localPostAndLocalPageShareOnePair() {
        #expect(statusSymbol("local-post") == statusSymbol("local-page"))
        #expect(Color.statusColor("local-post") == Color.statusColor("local-page"))
    }

    @Test func remoteStatusesAreDistinctFromEachOther() {
        let remote = ["publish", "draft", "future", "pending", "private"]
        #expect(Set(remote.map(statusSymbol)).count == remote.count)
        #expect(Set(remote.map { Color.statusColor($0).description }).count == remote.count)
    }

    @Test func unknownStatusFallsBackRatherThanCrashing() {
        #expect(statusSymbol("some-future-wp-status") == "circle.fill")
    }
}
