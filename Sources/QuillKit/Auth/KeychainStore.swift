import Foundation

/// Stores credentials as a JSON file in ~/Library/Application Support/Quill/.
/// chmod 600 keeps it owner-read/write only — same effective security as the
/// system keychain for a non-sandboxed app, without any password prompts.
public struct KeychainStore {

    private static var fileURL: URL {
        get throws {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dir = base.appendingPathComponent("Quill", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("credentials.json")
        }
    }

    public static func save(_ credentials: Credentials) throws {
        let url = try fileURL
        let data = try JSONEncoder().encode(credentials)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }

    public static func load() throws -> Credentials? {
        let url = try fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Credentials.self, from: data)
    }

    public static func delete() throws {
        let url = try fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
