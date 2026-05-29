import Foundation
import Testing
@testable import QuillKit

@Suite(.serialized)
struct KeychainStoreTests {
    let testCredentials = Credentials(
        siteURL: URL(string: "https://example.com")!,
        username: "testuser",
        appPassword: "xxxx yyyy zzzz"
    )

    init() throws {
        // Redirect all stores to a throwaway temp directory so the test suite never
        // reads, writes, or deletes the real user's credentials.json.
        AppSupportDirectory.override = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillTests-\(UUID().uuidString)", isDirectory: true)
        try? KeychainStore.delete()
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
