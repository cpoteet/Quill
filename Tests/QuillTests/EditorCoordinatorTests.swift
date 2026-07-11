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

    // MARK: - mediaSizesDict(for:)

    private func decodeMedia(_ json: String) throws -> WPMedia {
        try JSONDecoder().decode(WPMedia.self, from: json.data(using: .utf8)!)
    }

    @Test func mediaSizesDictAddsFullFallbackWhenSizesOmitsIt() throws {
        // WordPress commonly omits "full" from media_details.sizes even though it lists others.
        let json = """
        {"id":1,"source_url":"https://example.com/full.jpg",
         "media_details":{"width":2000,"height":1000,
           "sizes":{"medium":{"source_url":"https://example.com/medium.jpg","width":300,"height":150}}}}
        """
        let media = try decodeMedia(json)
        let dict = try #require(EditorCoordinator.mediaSizesDict(for: media))
        let full = try #require(dict["full"])
        #expect(full["url"] as? String == "https://example.com/full.jpg")
        #expect(full["width"] as? Int == 2000)
        #expect(full["height"] as? Int == 1000)
        // The pre-existing "medium" entry is left untouched.
        let medium = try #require(dict["medium"])
        #expect(medium["url"] as? String == "https://example.com/medium.jpg")
    }

    @Test func mediaSizesDictPreservesExistingFullEntry() throws {
        let json = """
        {"id":1,"source_url":"https://example.com/full.jpg",
         "media_details":{"sizes":{"full":{"source_url":"https://example.com/actual-full.jpg","width":4000,"height":2000}}}}
        """
        let media = try decodeMedia(json)
        let dict = try #require(EditorCoordinator.mediaSizesDict(for: media))
        // Does not overwrite a "full" entry the server already provided.
        #expect(dict["full"]?["url"] as? String == "https://example.com/actual-full.jpg")
    }

    @Test func mediaSizesDictFallsBackToSourceURLWhenNoSizesAtAll() throws {
        let json = """
        {"id":1,"source_url":"https://example.com/only.jpg"}
        """
        let media = try decodeMedia(json)
        let dict = try #require(EditorCoordinator.mediaSizesDict(for: media))
        #expect(dict.count == 1)
        #expect(dict["full"]?["url"] as? String == "https://example.com/only.jpg")
    }

    @Test func mediaSizesDictReturnsNilWhenSourceURLIsEmpty() throws {
        let json = """
        {"id":1}
        """
        let media = try decodeMedia(json)
        #expect(EditorCoordinator.mediaSizesDict(for: media) == nil)
    }
}
