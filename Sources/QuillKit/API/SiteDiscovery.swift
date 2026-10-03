import AppKit
import Foundation

public struct DiscoveredSite: Equatable, Sendable {
    public let siteURL: URL
    public let name: String?
    public let iconURL: URL?
    public let authorizationURL: URL?
    public let installURL: URL?
}

public enum SiteDiscoveryError: Error, Equatable, LocalizedError {
    case insecure, invalidAddress, unreachable(host: String), notWordPress

    public var errorDescription: String? {
        switch self {
        case .insecure: return "Quill needs an HTTPS address."
        case .invalidAddress: return "Enter your site's address, like example.com."
        case .unreachable(let host): return "Couldn't reach \(host). Check the address and your connection."
        case .notWordPress: return "This doesn't look like a WordPress site, or its REST API is turned off."
        }
    }
}

public struct SiteDiscovery: Sendable {
    private let session: URLSession
    private static let sharedSession = URLSession(configuration: .ephemeral)
    private static let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

    public init(session: URLSession? = nil) {
        self.session = session ?? Self.sharedSession
    }

    public static func normalize(_ input: String) throws(SiteDiscoveryError) -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw .invalidAddress
        }
        let hasScheme = trimmed.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) != nil
        guard var components = URLComponents(string: hasScheme ? trimmed : "https://" + trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host?.lowercased(), !host.isEmpty else {
            throw .invalidAddress
        }
        if !isSecure(scheme: scheme, host: host) { throw .insecure }

        var path = components.path
        for marker in ["/wp-admin", "/wp-login.php"] {
            if let range = path.range(of: marker) { path = String(path[..<range.lowerBound]) }
        }
        while path.hasSuffix("/") { path.removeLast() }

        components.scheme = scheme
        components.host = host
        components.user = nil
        components.password = nil
        components.path = path
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw .invalidAddress }
        return url
    }

    public static func profileURL(site: URL, authorizationURL: URL?) -> URL {
        let admin = authorizationURL?.deletingLastPathComponent()
            ?? site.appending(path: "wp-admin", directoryHint: .isDirectory)
        var components = URLComponents(url: admin.appending(path: "profile.php"), resolvingAgainstBaseURL: false)!
        components.query = nil
        components.fragment = "application-passwords-section"
        return components.url!
    }

    public func discover(_ site: URL) async throws(SiteDiscoveryError) -> DiscoveredSite {
        let request = URLRequest(url: site.appending(path: "wp-json", directoryHint: .isDirectory))
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .unreachable(host: site.host() ?? site.absoluteString)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let index = try? JSONDecoder().decode(RESTIndex.self, from: data) else {
            throw .notWordPress
        }
        let address = Self.siteURL(fromIndex: http.url) ?? site
        return DiscoveredSite(
            siteURL: index.home.flatMap(URL.init(string:)).flatMap { Self.wwwVariant(of: address, home: $0) } ?? address,
            name: index.name.flatMap { $0.isEmpty ? nil : $0 },
            iconURL: index.siteIconURL.flatMap { $0.isEmpty ? nil : URL(string: $0) },
            authorizationURL: index.authorizationURL.flatMap(URL.init(string:)).flatMap(Self.secureOrNil),
            installURL: index.url.flatMap(URL.init(string:)).flatMap(Self.secureOrNil)
        )
    }

    public func loadIcon(_ url: URL) async -> NSImage? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return NSImage(data: data)
    }

    private static func secureOrNil(_ url: URL) -> URL? {
        isSecure(scheme: url.scheme?.lowercased() ?? "", host: url.host() ?? "") ? url : nil
    }

    private static func isSecure(scheme: String, host: String) -> Bool {
        scheme == "https" || (scheme == "http" && localHosts.contains(host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))))
    }

    private static func wwwVariant(of address: URL, home: URL) -> URL? {
        guard let typed = URLComponents(url: address, resolvingAgainstBaseURL: false),
              var canonical = URLComponents(url: home, resolvingAgainstBaseURL: false),
              let typedHost = typed.host?.lowercased(), let homeHost = canonical.host?.lowercased(),
              typedHost != homeHost,
              "www." + typedHost == homeHost || typedHost == "www." + homeHost,
              typed.scheme?.lowercased() == canonical.scheme?.lowercased(), typed.port == canonical.port else { return nil }
        var path = canonical.path
        while path.hasSuffix("/") { path.removeLast() }
        guard path == typed.path else { return nil }
        canonical.host = homeHost
        canonical.path = path
        canonical.query = nil
        canonical.fragment = nil
        return canonical.url
    }

    private static func siteURL(fromIndex indexURL: URL?) -> URL? {
        guard let indexURL,
              var components = URLComponents(url: indexURL, resolvingAgainstBaseURL: false) else { return nil }
        var path = components.path
        guard path.hasSuffix("/wp-json/") || path.hasSuffix("/wp-json") else { return nil }
        path = String(path[..<path.range(of: "/wp-json", options: .backwards)!.lowerBound])
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

private struct RESTIndex: Decodable {
    let name: String?
    let url: String?
    let home: String?
    let namespaces: [String]
    let siteIconURL: String?
    let authorizationURL: String?

    private enum CodingKeys: String, CodingKey {
        case name, url, home, namespaces, authentication
        case siteIconURL = "site_icon_url"
    }

    private struct Authentication: Decodable {
        struct Method: Decodable {
            struct Endpoints: Decodable { let authorization: String? }
            let endpoints: Endpoints?
        }
        let applicationPasswords: Method?

        private enum CodingKeys: String, CodingKey {
            case applicationPasswords = "application-passwords"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        url = try? container.decodeIfPresent(String.self, forKey: .url)
        home = try? container.decodeIfPresent(String.self, forKey: .home)
        namespaces = try container.decode([String].self, forKey: .namespaces)
        siteIconURL = try? container.decodeIfPresent(String.self, forKey: .siteIconURL)
        let authentication = try? container.decodeIfPresent(Authentication.self, forKey: .authentication)
        authorizationURL = authentication?.applicationPasswords?.endpoints?.authorization
    }
}
