import Foundation

public struct AISettings: Codable {
    public var apiKey: String
    public var samplePostIDs: [Int]
    public var webSearchEnabled: Bool

    public init(apiKey: String = "", samplePostIDs: [Int] = [], webSearchEnabled: Bool = true) {
        self.apiKey = apiKey
        self.samplePostIDs = samplePostIDs
        self.webSearchEnabled = webSearchEnabled
    }
}

public struct AISettingsStore {
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
            return dir.appendingPathComponent("ai_settings.json")
        }
    }

    public static func save(_ settings: AISettings) throws {
        let url = try fileURL
        let data = try JSONEncoder().encode(settings)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }

    public static func load() throws -> AISettings? {
        let url = try fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AISettings.self, from: data)
    }

    public static func delete() throws {
        let url = try fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
