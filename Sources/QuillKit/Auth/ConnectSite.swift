import Foundation

public enum ConnectSite {
    public static func verifyAndSave(
        _ credentials: Credentials,
        session: URLSession? = nil,
        save: (Credentials) throws -> Void = CredentialsStore.save
    ) async throws {
        _ = try await WordPressClient(credentials: credentials, session: session).fetchPosts(page: 1, perPage: 1)
        try save(credentials)
    }
}
