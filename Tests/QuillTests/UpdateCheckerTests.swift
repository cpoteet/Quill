import Testing
@testable import QuillKit

@Suite("UpdateChecker version comparison")
struct UpdateCheckerTests {

    @Test func newerMajorVersion() {
        #expect(UpdateChecker.isNewer(remote: "2.0.0", local: "1.0.0"))
    }

    @Test func newerMinorVersion() {
        #expect(UpdateChecker.isNewer(remote: "1.1.0", local: "1.0.0"))
    }

    @Test func newerPatchVersion() {
        #expect(UpdateChecker.isNewer(remote: "1.0.1", local: "1.0.0"))
    }

    @Test func sameVersionIsNotNewer() {
        #expect(!UpdateChecker.isNewer(remote: "1.0.0", local: "1.0.0"))
    }

    @Test func olderVersionIsNotNewer() {
        #expect(!UpdateChecker.isNewer(remote: "1.0.0", local: "2.0.0"))
    }

    @Test func differentSegmentCounts() {
        #expect(UpdateChecker.isNewer(remote: "1.0.1", local: "1.0"))
        #expect(!UpdateChecker.isNewer(remote: "1.0", local: "1.0.1"))
    }

    @Test func largeVersionNumbers() {
        #expect(UpdateChecker.isNewer(remote: "10.20.30", local: "10.20.29"))
        #expect(!UpdateChecker.isNewer(remote: "10.20.30", local: "10.20.30"))
    }

    @Test func stripsLeadingVFromTag() {
        #expect(UpdateChecker.normalizeVersion("v2.0.0") == "2.0.0")
    }

    @Test func leavesBareVersionUnchanged() {
        #expect(UpdateChecker.normalizeVersion("2.0.0") == "2.0.0")
    }

    @Test func stripsOnlyTheFirstCharacter() {
        #expect(UpdateChecker.normalizeVersion("v1.11.0") == "1.11.0")
    }

    @Test func normalizedTagIsNewerThanCurrentBuild() {
        #expect(UpdateChecker.isNewer(remote: UpdateChecker.normalizeVersion("v2.0.0"), local: "1.11.0"))
    }

    @Test func unnormalizedTagSilentlyFailsToCompare() {
        #expect(!UpdateChecker.isNewer(remote: "v2.0.0", local: "1.11.0"))
    }
}
