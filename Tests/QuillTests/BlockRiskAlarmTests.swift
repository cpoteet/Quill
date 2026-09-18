import Testing
@testable import QuillKit

@Suite struct BlockRiskAlarmTests {
    @Test func singleBlockUsesSingularWording() {
        let alarm = BlockRiskAlarm(names: ["calendar"], stage: .unacknowledged)
        #expect(alarm.title == "Saving this post would delete content")
        #expect(alarm.body.contains("A Calendar block didn't survive loading into Quill"))
        #expect(alarm.body.contains("would remove it from the published post"))
        #expect(alarm.blocksSaving)
    }

    @Test func multipleBlocksUsePluralWording() {
        let alarm = BlockRiskAlarm(names: ["calendar", "block"], stage: .unacknowledged)
        #expect(alarm.body.contains("would remove them from the published post"))
    }

    @Test func bodyNamesEveryAffectedBlock() {
        let alarm = BlockRiskAlarm(names: ["calendar", "block"], stage: .unacknowledged)
        #expect(alarm.body.contains("Calendar"))
        #expect(alarm.body.contains("Synced Pattern"))
    }

    @Test func bodyExplainsItIsNotTheAuthorsFault() {
        let alarm = BlockRiskAlarm(names: ["calendar"], stage: .unacknowledged)
        #expect(alarm.body.contains("This is a Quill limitation, not a problem with your post"))
    }

    @Test func acknowledgedStageUnblocksSavingAndChangesCopy() {
        let alarm = BlockRiskAlarm(names: ["calendar"], stage: .acknowledged)
        #expect(!alarm.blocksSaving)
        #expect(alarm.title == "Saving will delete a Calendar block")
        #expect(alarm.body == "You chose to save anyway. Quill won't ask again for this post.")
    }

    @Test func savedStageIsPastTenseAndPointsAtRevisions() {
        let alarm = BlockRiskAlarm(names: ["calendar"], stage: .saved)
        #expect(!alarm.blocksSaving)
        #expect(alarm.body.contains("was removed from this post"))
        #expect(alarm.body.contains("revision history"))
    }

    @Test func savedStagePluralisesCorrectly() {
        let alarm = BlockRiskAlarm(names: ["calendar", "navigation"], stage: .saved)
        #expect(alarm.body.contains("were removed from this post"))
    }

    @Test func noStringContainsAnEmDash() {
        for stage in [BlockRiskAlarm.Stage.unacknowledged, .acknowledged, .saved] {
            let alarm = BlockRiskAlarm(names: ["calendar", "block"], stage: stage)
            #expect(!alarm.title.contains("\u{2014}"))
            #expect(!alarm.body.contains("\u{2014}"))
        }
    }

    @Test func displayNamesAreHumanReadable() {
        #expect(BlockRiskAlarm.displayName(for: "calendar") == "Calendar")
        #expect(BlockRiskAlarm.displayName(for: "block") == "Synced Pattern")
        #expect(BlockRiskAlarm.displayName(for: "nextpage") == "Page Break")
        #expect(BlockRiskAlarm.displayName(for: "more") == "Read More")
        #expect(BlockRiskAlarm.displayName(for: "latest-posts") == "Latest Posts")
        #expect(BlockRiskAlarm.displayName(for: "acme/widget") == "Acme Widget")
    }

    @Test func onlyTheUnacknowledgedStageBlocksSaving() {
        #expect(BlockRiskAlarm(names: ["calendar"], stage: .unacknowledged).blocksSaving)
        #expect(!BlockRiskAlarm(names: ["calendar"], stage: .acknowledged).blocksSaving)
        #expect(!BlockRiskAlarm(names: ["calendar"], stage: .saved).blocksSaving)
    }

    @Test func acknowledgingKeepsTheBlockNames() {
        let first = BlockRiskAlarm(names: ["calendar", "block"], stage: .unacknowledged)
        let next = BlockRiskAlarm(names: first.names, stage: .acknowledged)
        #expect(next.names == ["calendar", "block"])
    }

    @Test func anEmptyReportClearsTheAlarm() {
        let current = BlockRiskAlarm(names: ["calendar"], stage: .unacknowledged)
        #expect(PostEditorView.nextAlarm(from: current, names: []) == nil)
        #expect(PostEditorView.nextAlarm(from: nil, names: []) == nil)
    }

    @Test func repeatingTheSameReportKeepsAnAcknowledgedStage() {
        let current = BlockRiskAlarm(names: ["calendar"], stage: .acknowledged)
        #expect(PostEditorView.nextAlarm(from: current, names: ["calendar"])?.stage == .acknowledged)
        let saved = BlockRiskAlarm(names: ["calendar"], stage: .saved)
        #expect(PostEditorView.nextAlarm(from: saved, names: ["calendar"])?.stage == .saved)
    }

    @Test func aDifferentReportRaisesTheAlarmAgain() {
        let current = BlockRiskAlarm(names: ["calendar"], stage: .acknowledged)
        let next = PostEditorView.nextAlarm(from: current, names: ["calendar", "verse"])
        #expect(next?.stage == .unacknowledged)
        #expect(next?.names == ["calendar", "verse"])
    }

    @Test func aFirstReportRaisesTheAlarm() {
        let next = PostEditorView.nextAlarm(from: nil, names: ["verse"])
        #expect(next?.stage == .unacknowledged)
        #expect(next?.names == ["verse"])
    }
}
