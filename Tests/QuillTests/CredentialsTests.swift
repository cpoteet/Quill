import Foundation
import Testing
@testable import QuillKit

@Suite struct CredentialsTests {

    @Test func basicAuthHeaderKnownVector() {
        let creds = Credentials(siteURL: URL(string: "https://example.com")!,
                                username: "user", appPassword: "pass")
        // base64("user:pass") = "dXNlcjpwYXNz"
        #expect(creds.basicAuthHeader == "Basic dXNlcjpwYXNz")
    }

    @Test func appPasswordWithSpacesEncodedVerbatim() {
        // WordPress app passwords are space-grouped (e.g. "xxxx yyyy zzzz").
        // Spaces are part of the credential and must not be stripped.
        let creds = Credentials(siteURL: URL(string: "https://example.com")!,
                                username: "testuser", appPassword: "xxxx yyyy zzzz")
        let expected = "Basic " + Data("testuser:xxxx yyyy zzzz".utf8).base64EncodedString()
        #expect(creds.basicAuthHeader == expected)
    }

    @Test func basicAuthHeaderHasCorrectPrefix() {
        let creds = Credentials(siteURL: URL(string: "https://example.com")!,
                                username: "a", appPassword: "b")
        #expect(creds.basicAuthHeader.hasPrefix("Basic "))
    }

    @Test func unicodeUsernameEncodedAsUTF8() {
        let creds = Credentials(siteURL: URL(string: "https://example.com")!,
                                username: "héros", appPassword: "pass")
        let expected = "Basic " + Data("héros:pass".utf8).base64EncodedString()
        #expect(creds.basicAuthHeader == expected)
    }

    @Test func siteKeyIgnoresATrailingSlashAndHostCase() {
        let bare = Credentials(siteURL: URL(string: "https://Example.com/blog")!, username: "u", appPassword: "p")
        let slashed = Credentials(siteURL: URL(string: "https://example.com/blog/")!, username: "v", appPassword: "q")
        #expect(bare.siteKey == slashed.siteKey)
        #expect(bare.siteKey == "https://example.com/blog")
    }
}
