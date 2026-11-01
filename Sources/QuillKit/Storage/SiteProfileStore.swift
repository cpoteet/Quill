import Foundation

public struct SiteProfile: Codable, Equatable, Sendable {
    public var name: String?
    public var iconURL: URL?
    public var iconData: Data?

    public init(name: String? = nil, iconURL: URL? = nil, iconData: Data? = nil) {
        self.name = name
        self.iconURL = iconURL
        self.iconData = iconData
    }
}

/// Site names and icons keyed by `siteKey`, kept out of `Credentials` because credential equality triggers a reload.
public struct SiteProfileStore: Sendable {
    private let store: JSONFileStore<[String: SiteProfile]>

    public init(in baseDirectory: URL? = nil) {
        store = JSONFileStore("site_profiles.json", in: baseDirectory)
    }

    public func profile(for siteKey: String) -> SiteProfile? {
        (try? store.load())??[siteKey]
    }

    public func setProfile(_ profile: SiteProfile?, for siteKey: String) throws {
        var profiles = (try? store.load()) ?? [:]
        profiles[siteKey] = profile
        try store.save(profiles)
    }
}
