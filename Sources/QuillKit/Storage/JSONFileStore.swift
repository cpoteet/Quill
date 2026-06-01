import Foundation

/// Generic file-backed JSON store. Writes atomically; chmod 600 after every save.
public struct JSONFileStore<T: Codable> {
    private let filename: String
    private let baseDirectory: URL?

    /// - Parameters:
    ///   - filename: Name of the JSON file (e.g. `"credentials.json"`).
    ///   - baseDirectory: When provided, files are stored here instead of the default
    ///     Application Support directory. Intended for tests that need isolation without
    ///     touching the global `AppSupportDirectory.override`.
    public init(_ filename: String, in baseDirectory: URL? = nil) {
        self.filename = filename
        self.baseDirectory = baseDirectory
    }

    private var fileURL: URL {
        get throws {
            if let baseDirectory {
                return baseDirectory.appendingPathComponent(filename)
            }
            return try AppSupportDirectory.fileURL(filename)
        }
    }

    public func save(_ value: T) throws {
        let url = try fileURL
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }

    public func load() throws -> T? {
        let url = try fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    public func delete() throws {
        let url = try fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
