import Foundation
import Testing
@testable import QuillKit

struct AppAuthorizationTests {
    private let base = URL(string: "https://example.com/wp-admin/authorize-application.php")!

    private func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    private func parse(_ string: String) -> AppAuthorization.CallbackResult {
        AppAuthorization.parseCallback(URL(string: string)!, expectedNonce: "abc", scheme: "quill")
    }

    // MARK: - Nonce

    @Test func nonceIs64LowercaseHexCharacters() {
        let nonce = AppAuthorization.makeNonce()
        #expect(nonce.count == 64)
        #expect(nonce.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test func noncesDiffer() {
        #expect(AppAuthorization.makeNonce() != AppAuthorization.makeNonce())
    }

    // MARK: - approvalURL

    @Test func approvalURLCarriesEveryParameter() {
        let url = AppAuthorization.approvalURL(base: base, nonce: "abc", deviceName: "Chris's MacBook", scheme: "quill")
        #expect(url.host() == "example.com")
        #expect(url.path() == "/wp-admin/authorize-application.php")
        #expect(queryValue("app_name", in: url) == "Quill on Chris's MacBook")
        #expect(queryValue("app_id", in: url) == AppAuthorization.appID)
        #expect(queryValue("success_url", in: url) == "quill://authorize?nonce=abc")
        #expect(queryValue("reject_url", in: url) == "quill://authorize?nonce=abc")
    }

    @Test func approvalURLEncodesReservedCharactersInValues() {
        let url = AppAuthorization.approvalURL(base: base, nonce: "abc", deviceName: "Chris's MacBook", scheme: "quill")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? ""
        #expect(query.contains("success_url=quill%3A%2F%2Fauthorize%3Fnonce%3Dabc"))
    }

    @Test func approvalURLEncodesNonASCIIDeviceName() {
        let url = AppAuthorization.approvalURL(base: base, nonce: "abc", deviceName: "José\u{2019}s Mac", scheme: "quill")
        #expect(queryValue("app_name", in: url) == "Quill on José\u{2019}s Mac")
    }

    // MARK: - parseCallback

    @Test func approvedCallbackDecodesPlusAsSpace() {
        #expect(parse("quill://authorize?nonce=abc&site_url=x&user_login=John+Doe&password=p1")
            == .approved(username: "John Doe", password: "p1"))
    }

    @Test func approvedCallbackKeepsEncodedPlus() {
        #expect(parse("quill://authorize?nonce=abc&user_login=a%2Bb&password=p1")
            == .approved(username: "a+b", password: "p1"))
    }

    @Test func declinedCallbackIsRejected() {
        #expect(parse("quill://authorize?nonce=abc&success=false") == .rejected)
    }

    @Test(arguments: [
        "quill://authorize?nonce=xyz&user_login=a&password=p1",
        "quill://authorize?user_login=a&password=p1",
        "quill://authorize?nonce=abc&user_login=a",
        "quill://authorize?nonce=abc&user_login=&password=p1",
        "quill-dev://authorize?nonce=abc&user_login=a&password=p1",
        "quill://other?nonce=abc&user_login=a&password=p1",
    ])
    func unmatchedCallbackIsIgnored(_ string: String) {
        #expect(parse(string) == .ignored)
    }
}
