import Foundation

public struct Credentials: Codable, Sendable, Equatable {
    public var siteURL: URL
    public var username: String
    public var appPassword: String

    public init(siteURL: URL, username: String, appPassword: String) {
        self.siteURL = siteURL
        self.username = username
        self.appPassword = appPassword
    }

    var basicAuthHeader: String {
        let raw = "\(username):\(appPassword)"
        return "Basic " + Data(raw.utf8).base64EncodedString()
    }

    // Keys per-site storage; a trailing slash or a capitalised host is the same site.
    var siteKey: String {
        var key = siteURL.absoluteString
        if var components = URLComponents(url: siteURL, resolvingAgainstBaseURL: false) {
            components.host = components.host?.lowercased()
            key = components.string ?? key
        }
        while key.hasSuffix("/") { key.removeLast() }
        return key
    }
}
