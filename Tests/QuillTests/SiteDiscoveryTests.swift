import Foundation
import Testing
@testable import QuillKit

@Suite(.serialized) struct SiteDiscoveryTests {
    let discovery: SiteDiscovery
    let site = URL(string: "https://example.com")!

    init() {
        DiscoveryMockURLProtocol.requestHandler = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DiscoveryMockURLProtocol.self]
        discovery = SiteDiscovery(session: URLSession(configuration: config))
    }

    private static let fullIndex = """
    {"name":"Lantern & Ink","namespaces":["wp/v2"],"site_icon_url":"https://example.com/icon.png",
     "authentication":{"application-passwords":{"endpoints":{"authorization":"https://example.com/wp-admin/authorize-application.php"}}}}
    """

    private func serve(_ body: String, status: Int = 200, url: URL? = nil) {
        DiscoveryMockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: url ?? request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
    }

    // MARK: - normalize

    @Test func normalizeAddsHTTPSToBareHost() throws {
        #expect(try SiteDiscovery.normalize("lanternandink.com") == URL(string: "https://lanternandink.com"))
    }

    @Test func normalizeTrimsLowercasesAndDropsTrailingSlash() throws {
        #expect(try SiteDiscovery.normalize("  https://Example.COM/ \n") == URL(string: "https://example.com"))
    }

    @Test func normalizeKeepsSubdirectory() throws {
        #expect(try SiteDiscovery.normalize("https://example.com/blog/") == URL(string: "https://example.com/blog"))
    }

    @Test func normalizeStripsWPAdmin() throws {
        #expect(try SiteDiscovery.normalize("https://example.com/wp-admin/") == URL(string: "https://example.com"))
    }

    @Test func normalizeStripsWPLoginAndQuery() throws {
        #expect(try SiteDiscovery.normalize("https://example.com/wp/wp-login.php?redirect_to=x") == URL(string: "https://example.com/wp"))
    }

    @Test func normalizeAddsHTTPSWhenQueryHoldsAURL() throws {
        #expect(try SiteDiscovery.normalize("example.com/wp-login.php?redirect_to=https://example.com/wp-admin/") == URL(string: "https://example.com"))
    }

    @Test func normalizeAllowsHTTPOnLocalhost() throws {
        #expect(try SiteDiscovery.normalize("http://localhost:8080") == URL(string: "http://localhost:8080"))
    }

    @Test func normalizeAllowsHTTPOnIPv6Loopback() throws {
        #expect(try SiteDiscovery.normalize("http://[::1]:8080/") == URL(string: "http://[::1]:8080"))
    }

    @Test func normalizeRefusesHTTPElsewhere() {
        #expect(throws: SiteDiscoveryError.insecure) { try SiteDiscovery.normalize("http://example.com") }
    }

    @Test func normalizeRefusesEmptyInput() {
        #expect(throws: SiteDiscoveryError.invalidAddress) { try SiteDiscovery.normalize("") }
    }

    @Test func normalizeRefusesGarbage() {
        #expect(throws: SiteDiscoveryError.invalidAddress) { try SiteDiscovery.normalize("not a site") }
    }

    // MARK: - profileURL

    @Test func profileURLFollowsAuthorizationURLAdminPath() {
        let auth = URL(string: "https://example.com/wp/wp-admin/authorize-application.php")!
        #expect(SiteDiscovery.profileURL(site: site, authorizationURL: auth)
            == URL(string: "https://example.com/wp/wp-admin/profile.php#application-passwords-section"))
    }

    @Test func profileURLFallsBackToSiteAdmin() {
        #expect(SiteDiscovery.profileURL(site: URL(string: "https://example.com/blog")!, authorizationURL: nil)
            == URL(string: "https://example.com/blog/wp-admin/profile.php#application-passwords-section"))
    }

    // MARK: - discover

    @Test func discoverMapsEveryField() async throws {
        serve(Self.fullIndex)
        let found = try await discovery.discover(site)
        #expect(found == DiscoveredSite(
            siteURL: site,
            name: "Lantern & Ink",
            iconURL: URL(string: "https://example.com/icon.png"),
            authorizationURL: URL(string: "https://example.com/wp-admin/authorize-application.php")
        ))
    }

    @Test func discoverRequestsRESTIndex() async throws {
        var requested: URL?
        DiscoveryMockURLProtocol.requestHandler = { request in
            requested = request.url
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(Self.fullIndex.utf8))
        }
        _ = try await discovery.discover(site)
        #expect(requested == URL(string: "https://example.com/wp-json/"))
    }

    @Test func discoverTreatsEmptyAuthenticationArrayAsNoApproval() async throws {
        serve(#"{"name":"Lantern & Ink","namespaces":["wp/v2"],"site_icon_url":"","authentication":[]}"#)
        let found = try await discovery.discover(site)
        #expect(found.authorizationURL == nil)
    }

    @Test func discoverDropsInsecureAuthorizationURL() async throws {
        serve(#"{"namespaces":["wp/v2"],"authentication":{"application-passwords":{"endpoints":{"authorization":"http://example.com/wp-admin/authorize-application.php"}}}}"#)
        let found = try await discovery.discover(site)
        #expect(found.authorizationURL == nil)
    }

    @Test func discoverTreatsEmptyStringsAsNil() async throws {
        serve(#"{"name":"","namespaces":["wp/v2"],"site_icon_url":"","authentication":[]}"#)
        let found = try await discovery.discover(site)
        #expect(found.name == nil)
        #expect(found.iconURL == nil)
    }

    @Test func discoverRejectsHTML() async {
        serve("<!doctype html><html><body>Hello</body></html>")
        await #expect(throws: SiteDiscoveryError.notWordPress) { try await discovery.discover(site) }
    }

    @Test(arguments: [404, 401, 403])
    func discoverRejectsErrorStatus(_ status: Int) async {
        serve(Self.fullIndex, status: status)
        await #expect(throws: SiteDiscoveryError.notWordPress) { try await discovery.discover(site) }
    }

    @Test func discoverRejectsJSONWithoutNamespaces() async {
        serve(#"{"name":"Lantern & Ink"}"#)
        await #expect(throws: SiteDiscoveryError.notWordPress) { try await discovery.discover(site) }
    }

    @Test func discoverReportsTransportFailureAsUnreachable() async {
        DiscoveryMockURLProtocol.requestHandler = { _ in throw URLError(.cannotFindHost) }
        await #expect(throws: SiteDiscoveryError.unreachable(host: "example.com")) { try await discovery.discover(site) }
    }

    @Test func discoverKeepsRedirectedAddress() async throws {
        serve(Self.fullIndex, url: URL(string: "https://www.example.com/wp-json/"))
        let found = try await discovery.discover(site)
        #expect(found.siteURL == URL(string: "https://www.example.com"))
    }

    @Test func discoverSendsNoAuthorizationHeader() async throws {
        var captured: URLRequest?
        DiscoveryMockURLProtocol.requestHandler = { request in
            captured = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(Self.fullIndex.utf8))
        }
        _ = try await discovery.discover(site)
        #expect(captured != nil)
        #expect(captured?.value(forHTTPHeaderField: "Authorization") == nil)
    }
}
