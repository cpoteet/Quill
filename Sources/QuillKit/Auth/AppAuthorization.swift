import Foundation
import Security

public enum AppAuthorization {
    public static let appID = "9c21c21a-4ed4-4f29-8b5d-99fe76d9e9ab"

    public static var callbackScheme: String {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        let schemes = types?.first?["CFBundleURLSchemes"] as? [String]
        return schemes?.first ?? "quill"
    }

    private static let callbackHost = "authorize"
    private static let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    public static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    public static func approvalURL(base: URL, nonce: String, deviceName: String, scheme: String = callbackScheme) -> URL {
        let callback = "\(scheme)://\(callbackHost)?nonce=\(nonce)"
        let parameters = [
            ("app_name", "Quill on \(deviceName)"),
            ("app_id", appID),
            ("success_url", callback),
            ("reject_url", callback),
        ]
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.percentEncodedQueryItems = (components.percentEncodedQueryItems ?? []) + parameters.map {
            URLQueryItem(name: $0.0, value: $0.1.addingPercentEncoding(withAllowedCharacters: unreserved))
        }
        return components.url!
    }

    public enum CallbackResult: Equatable {
        case approved(username: String, password: String), rejected, ignored
    }

    public static func parseCallback(_ url: URL, expectedNonce: String, scheme: String = callbackScheme) -> CallbackResult {
        guard url.scheme?.lowercased() == scheme.lowercased(),
              url.host()?.lowercased() == callbackHost else { return .ignored }
        let query = formDecodedQuery(url)
        guard query["nonce"] == expectedNonce else { return .ignored }
        if query["success"] == "false" { return .rejected }
        guard let username = query["user_login"], !username.isEmpty,
              let password = query["password"], !password.isEmpty else { return .ignored }
        return .approved(username: username, password: password)
    }

    private static func formDecodedQuery(_ url: URL) -> [String: String] {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? ""
        var values: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = decode(parts[0]) else { continue }
            values[name] = parts.count > 1 ? decode(parts[1]) : ""
        }
        return values
    }

    private static func decode(_ component: Substring) -> String? {
        component.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }
}
