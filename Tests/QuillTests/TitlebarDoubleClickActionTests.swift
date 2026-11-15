import Foundation
import Testing
@testable import QuillKit

// The values are the ones System Settings' Desktop & Dock pane writes to AppleActionOnDoubleClick.
@Suite struct TitlebarDoubleClickActionTests {

    @Test func minimizeSettingMinimizes() {
        #expect(TitlebarDoubleClickAction(actionSetting: "Minimize", legacyMiniaturize: false) == .minimize)
    }

    @Test func zoomSettingZooms() {
        #expect(TitlebarDoubleClickAction(actionSetting: "Maximize", legacyMiniaturize: false) == .zoom)
    }

    @Test func fillZoomsBecauseFillHasNoPublicAPI() {
        #expect(TitlebarDoubleClickAction(actionSetting: "Fill", legacyMiniaturize: false) == .zoom)
    }

    @Test func doNothingDoesNothing() {
        #expect(TitlebarDoubleClickAction(actionSetting: "None", legacyMiniaturize: true) == .doNothing)
    }

    @Test func newSettingWinsOverTheLegacyFlag() {
        #expect(TitlebarDoubleClickAction(actionSetting: "Maximize", legacyMiniaturize: true) == .zoom)
    }

    @Test func noSettingFallsBackToTheLegacyFlag() {
        #expect(TitlebarDoubleClickAction(actionSetting: nil, legacyMiniaturize: true) == .minimize)
        #expect(TitlebarDoubleClickAction(actionSetting: nil, legacyMiniaturize: false) == .zoom)
    }

    @Test func unknownValueFallsBackLikeNoSetting() {
        #expect(TitlebarDoubleClickAction(actionSetting: "SomethingNew", legacyMiniaturize: false) == .zoom)
    }

    // A suite still falls back to NSGlobalDomain, so a key this test leaves unset would read the machine's own
    // Desktop & Dock setting. Every check sets AppleActionOnDoubleClick itself; the legacy fallback is covered above.
    @Test func currentReadsTheSettingFromTheDefaultsItIsGiven() throws {
        let suite = "TitlebarDoubleClickActionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: "AppleMiniaturizeOnDoubleClick")
        defaults.set("Maximize", forKey: "AppleActionOnDoubleClick")
        #expect(TitlebarDoubleClickAction.current(defaults) == .zoom)

        defaults.set("None", forKey: "AppleActionOnDoubleClick")
        #expect(TitlebarDoubleClickAction.current(defaults) == .doNothing)

        defaults.set("Minimize", forKey: "AppleActionOnDoubleClick")
        #expect(TitlebarDoubleClickAction.current(defaults) == .minimize)
    }
}
