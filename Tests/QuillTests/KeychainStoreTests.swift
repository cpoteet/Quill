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
}
