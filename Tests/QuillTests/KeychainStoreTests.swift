import Foundation
import Testing
@testable import QuillKit

// A `final class` (not a struct) so it can use `deinit` for teardown — swift-testing's
// idiomatic per-instance cleanup hook. Structs conform to `Copyable` and cannot declare
// a deinitializer.
@Suite(.serialized)
final class KeychainStoreTests {
    let testCredentials = Credentials(
        siteURL: URL(string: "https://example.com")!,
        username: "testuser",
        appPassword: "xxxx yyyy zzzz"
    )

    private let tempDir: URL

    init() throws {
        // Redirect all stores to a throwaway temp directory so the test suite never
        // reads, writes, or deletes the real user's credentials.json.
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillTests-\(UUID().uuidString)", isDirectory: true)
        AppSupportDirectory.override = tempDir
        try? KeychainStore.delete()
    }

    deinit {
        // Clear the global override so it can't leak into other (parallel) suites,
        // and remove the throwaway directory.
        AppSupportDirectory.override = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test func saveAndLoad() throws {
        try KeychainStore.save(testCredentials)
        let loaded = try KeychainStore.load()
        #expect(loaded?.siteURL == testCredentials.siteURL)
        #expect(loaded?.username == testCredentials.username)
        #expect(loaded?.appPassword == testCredentials.appPassword)
        try? KeychainStore.delete()
    }

    @Test func loadReturnsNilWhenEmpty() throws {
        let result = try KeychainStore.load()
        #expect(result == nil)
    }

    @Test func deleteRemovesCredentials() throws {
        try KeychainStore.save(testCredentials)
        try KeychainStore.delete()
        let result = try KeychainStore.load()
        #expect(result == nil)
    }

    // MARK: - AppSupportDirectory

    @Test func appSupportDirectoryCreatesDir() throws {
        let url = try AppSupportDirectory.directory()
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        #expect(exists && isDir.boolValue)
    }

    @Test func appSupportDirectoryIsIdempotent() throws {
        let url1 = try AppSupportDirectory.directory()
        let url2 = try AppSupportDirectory.directory()
        #expect(url1 == url2)
    }

    @Test func appSupportFileURLJoinsCorrectly() throws {
        let url = try AppSupportDirectory.fileURL("foo.json")
        let dir = try AppSupportDirectory.directory()
        #expect(url.lastPathComponent == "foo.json")
        #expect(url.deletingLastPathComponent() == dir)
    }

    @Test func appSupportOverrideKeepsFilesInTempDir() throws {
        let url = try AppSupportDirectory.fileURL("isolation.json")
        #expect(url.path.hasPrefix(tempDir.path))
    }

    // MARK: - AISettingsStore

    @Test func aiSettingsRoundTrip() throws {
        let settings = AISettings(
            apiKey: "sk-ant-test",
            samplePostIDs: [1, 2, 3],
            webSearchEnabled: true,
            styleGuide: "Write concisely."
        )
        try AISettingsStore.save(settings)
        let loaded = try AISettingsStore.load()
        #expect(loaded?.apiKey == "sk-ant-test")
        #expect(loaded?.samplePostIDs == [1, 2, 3])
        #expect(loaded?.webSearchEnabled == true)
        #expect(loaded?.styleGuide == "Write concisely.")
        try? AISettingsStore.delete()
    }

    @Test func aiSettingsLoadReturnsNilWhenAbsent() throws {
        #expect(try AISettingsStore.load() == nil)
    }

    @Test func aiSettingsDeleteRemovesSettings() throws {
        try AISettingsStore.save(AISettings(apiKey: "key"))
        try AISettingsStore.delete()
        #expect(try AISettingsStore.load() == nil)
    }
}
