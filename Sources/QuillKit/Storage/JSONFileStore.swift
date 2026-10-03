import Foundation

/// Generic file-backed JSON store. Writes a 0600 temp file and renames it into place.
public struct JSONFileStore<T: Codable>: Sendable {
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

    // Created 0600 before any byte is written, then renamed over the old file.
    public func save(_ value: T) throws {
        let url = try fileURL
        let data = try JSONEncoder().encode(value)
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(filename).\(UUID().uuidString)")
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        do {
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            try handle.write(contentsOf: data)
            try handle.close()
            guard rename(temp.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } catch {
            unlink(temp.path)
            throw error
        }
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
