import Foundation

public struct AISettings: Codable {
    public var apiKey: String
    public var samplePostIDs: [Int]
    public var webSearchEnabled: Bool
    public var styleGuide: String?

    public init(apiKey: String = "", samplePostIDs: [Int] = [], webSearchEnabled: Bool = true, styleGuide: String? = nil) {
        self.apiKey = apiKey
        self.samplePostIDs = samplePostIDs
        self.webSearchEnabled = webSearchEnabled
        self.styleGuide = styleGuide
    }
}

public struct AISettingsStore {
    private static let store = JSONFileStore<AISettings>("ai_settings.json")

    public static func save(_ settings: AISettings) throws { try store.save(settings) }
    public static func load() throws -> AISettings? { try store.load() }
    public static func delete() throws { try store.delete() }
}
