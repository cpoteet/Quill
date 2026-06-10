import Foundation

/// Stores credentials as a JSON file in ~/Library/Application Support/Quill/.
/// chmod 600 keeps it owner-read/write only — same effective security as the
/// system keychain for a non-sandboxed app, without any password prompts.
public struct CredentialsStore {
    private static let store = JSONFileStore<Credentials>("credentials.json")

    public static func save(_ credentials: Credentials) throws { try store.save(credentials) }
    public static func load() throws -> Credentials? { try store.load() }
    public static func delete() throws { try store.delete() }
}
