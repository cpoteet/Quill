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
}
