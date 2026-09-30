import Foundation

/// An owner-only (0600) JSON file: other users cannot read it, but unlike the keychain any process of this user can.
public struct CredentialsStore {
    private static let store = JSONFileStore<Credentials>("credentials.json")

    public static func save(_ credentials: Credentials) throws { try store.save(credentials) }
    public static func load() throws -> Credentials? { try store.load() }
    public static func delete() throws { try store.delete() }
}
