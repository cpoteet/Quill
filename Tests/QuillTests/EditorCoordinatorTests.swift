import Foundation
import Testing
@testable import QuillKit

@Suite struct EditorCoordinatorTests {

    // MARK: - isAllowedExternalURL (S2)

    @Test func httpURLIsAllowed() {
        let url = URL(string: "http://example.com/post")!
        #expect(EditorCoordinator.isAllowedExternalURL(url))
    }

    @Test func httpsURLIsAllowed() {
        let url = URL(string: "https://example.com/post")!
        #expect(EditorCoordinator.isAllowedExternalURL(url))
    }

    @Test func mailtoURLIsAllowed() {
        let url = URL(string: "mailto:user@example.com")!
        #expect(EditorCoordinator.isAllowedExternalURL(url))
    }

    @Test func fileURLIsNotAllowed() {
        let url = URL(string: "file:///etc/passwd")!
        #expect(!EditorCoordinator.isAllowedExternalURL(url))
    }

    @Test func javascriptURLIsNotAllowed() {
        let url = URL(string: "javascript:alert(1)")!
        #expect(!EditorCoordinator.isAllowedExternalURL(url))
    }

    @Test func ftpURLIsNotAllowed() {
        let url = URL(string: "ftp://example.com/file")!
        #expect(!EditorCoordinator.isAllowedExternalURL(url))
    }

    @Test func schemeCheckIsCaseInsensitive() {
        let url = URL(string: "HTTPS://example.com/post")!
        #expect(EditorCoordinator.isAllowedExternalURL(url))
    }
}
