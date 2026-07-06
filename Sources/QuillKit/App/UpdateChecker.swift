import Foundation

public struct UpdateInfo: Equatable {
    public let version: String
    public let url: URL
}

public enum UpdateChecker {
    private static let versionURL = URL(string: "https://cpoteet.github.io/Quill-Releases/version.json")!
    private static let dismissedKey = "UpdateCheckerDismissedVersion"

    public static func dismiss(_ version: String) {
        UserDefaults.standard.set(version, forKey: dismissedKey)
    }

    /// Throws on a transport/decode failure (so the caller knows to retry later, e.g. on the
    /// next sidebar remount) rather than conflating "check failed" with "no update available".
    /// Returns `nil` for the latter — a successful check that found nothing to report.
    public static func check() async throws -> UpdateInfo? {
        struct VersionPayload: Decodable {
            let version: String
            let url: String
        }

        guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return nil
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: versionURL)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(VersionPayload.self, from: data)

        let dismissed = UserDefaults.standard.string(forKey: dismissedKey)
        guard isNewer(remote: payload.version, local: currentVersion),
              payload.version != dismissed,
              let changelogURL = URL(string: payload.url) else {
            return nil
        }

        return UpdateInfo(version: payload.version, url: changelogURL)
    }

    static func isNewer(remote: String, local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}
