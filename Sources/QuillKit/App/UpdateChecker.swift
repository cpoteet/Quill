import Foundation

public struct UpdateInfo: Equatable {
    public let version: String
    public let url: URL
}

public enum UpdateChecker {
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/cpoteet/Quill/releases/latest")!
    private static let dismissedKey = "UpdateCheckerDismissedVersion"

    public static func dismiss(_ version: String) {
        UserDefaults.standard.set(version, forKey: dismissedKey)
    }

    /// Throws on a transport/decode failure (so the caller knows to retry later, e.g. on the
    /// next sidebar remount) rather than conflating "check failed" with "no update available".
    /// Returns `nil` for the latter — a successful check that found nothing to report.
    public static func check() async throws -> UpdateInfo? {
        struct ReleasePayload: Decodable {
            let tagName: String
            let htmlURL: String

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case htmlURL = "html_url"
            }
        }

        guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return nil
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(ReleasePayload.self, from: data)
        let remoteVersion = normalizeVersion(payload.tagName)

        let dismissed = UserDefaults.standard.string(forKey: dismissedKey)
        guard isNewer(remote: remoteVersion, local: currentVersion),
              remoteVersion != dismissed,
              let releaseURL = URL(string: payload.htmlURL),
              releaseURL.scheme == "https", releaseURL.host == "github.com" else {
            return nil
        }

        return UpdateInfo(version: remoteVersion, url: releaseURL)
    }

    static func normalizeVersion(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
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
