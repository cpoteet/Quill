import Foundation

public struct AIModelInfo: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var createdAt: Date
    public var maxTokens: Int
    public var line: String?
    public var supportsAdaptiveThinking: Bool
    public var supportsEnabledThinking: Bool
    public var effortLevels: [String]
    public var supportsWebSearch: Bool

    public init(id: String, displayName: String, createdAt: Date, maxTokens: Int, line: String?,
                supportsAdaptiveThinking: Bool, supportsEnabledThinking: Bool,
                effortLevels: [String], supportsWebSearch: Bool) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
        self.maxTokens = maxTokens
        self.line = line
        self.supportsAdaptiveThinking = supportsAdaptiveThinking
        self.supportsEnabledThinking = supportsEnabledThinking
        self.effortLevels = effortLevels
        self.supportsWebSearch = supportsWebSearch
    }
}

public enum AIReasoning: Codable, Equatable, Hashable, Sendable {
    case off
    case modelDefault
    /// An API effort name (`low` … `max`); for an enabled-only model, Quill's label for a thinking budget.
    case level(String)
}

public struct AISettings: Codable {
    public static let fallbackModelID = "claude-haiku-5-5"

    public var apiKey: String
    public var samplePostIDs: [Int]
    public var webSearchEnabled: Bool
    public var styleGuide: String?
    /// nil follows the default model.
    public var model: String?
    public var reasoning: AIReasoning = .modelDefault
    public var models: [AIModelInfo] = []
    public var webSearchToolByModel: [String: String] = [:]
    /// The newest web search version when `webSearchToolByModel` was probed; a newer one means probing again.
    public var webSearchVersionsHead: String?

    public init(apiKey: String = "", samplePostIDs: [Int] = [], webSearchEnabled: Bool = true, styleGuide: String? = nil) {
        self.apiKey = apiKey
        self.samplePostIDs = samplePostIDs
        self.webSearchEnabled = webSearchEnabled
        self.styleGuide = styleGuide
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try c.decode(String.self, forKey: .apiKey)
        samplePostIDs = try c.decode([Int].self, forKey: .samplePostIDs)
        webSearchEnabled = try c.decode(Bool.self, forKey: .webSearchEnabled)
        styleGuide = try c.decodeIfPresent(String.self, forKey: .styleGuide)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        reasoning = try c.decodeIfPresent(AIReasoning.self, forKey: .reasoning) ?? .modelDefault
        models = try c.decodeIfPresent([AIModelInfo].self, forKey: .models) ?? []
        webSearchToolByModel = try c.decodeIfPresent([String: String].self, forKey: .webSearchToolByModel) ?? [:]
        webSearchVersionsHead = try c.decodeIfPresent(String.self, forKey: .webSearchVersionsHead)
    }

    public func knownWebSearchTool(for modelID: String) -> String? {
        webSearchVersionsHead == AnthropicClient.webSearchVersions.first ? webSearchToolByModel[modelID] : nil
    }

    public mutating func rememberWebSearchTool(_ tool: String, for modelID: String) {
        if webSearchVersionsHead != AnthropicClient.webSearchVersions.first {
            webSearchToolByModel = [:]
            webSearchVersionsHead = AnthropicClient.webSearchVersions.first
        }
        webSearchToolByModel[modelID] = tool
    }

    public func resolvedModelID() -> String {
        if let model { return model }
        return models.filter { $0.line == "haiku" }.max { $0.createdAt < $1.createdAt }?.id ?? Self.fallbackModelID
    }

    public func resolvedModel() -> AIModelInfo? {
        let id = resolvedModelID()
        return models.first { $0.id == id }
    }

    public static func reasoningOptions(for model: AIModelInfo?) -> [AIReasoning] {
        guard let model else { return [.off] }
        if model.supportsAdaptiveThinking {
            let levels = ["low", "medium", "high", "xhigh", "max"].filter(model.effortLevels.contains)
            return [.modelDefault] + levels.map(AIReasoning.level)
        }
        if model.supportsEnabledThinking { return [.off, .level("low"), .level("medium"), .level("high")] }
        return [.off]
    }

    public func normalizedReasoning() -> AIReasoning {
        let options = Self.reasoningOptions(for: resolvedModel())
        return options.contains(reasoning) ? reasoning : options[0]
    }

    public func applyingFetchedModels(_ fetched: [AIModelInfo]) -> (AISettings, notice: String?) {
        var next = self
        next.models = fetched
        var notice: String?
        if let pinned = model, !fetched.contains(where: { $0.id == pinned }) {
            next.model = nil
            let name = next.resolvedModel()?.displayName ?? next.resolvedModelID()
            notice = "Your saved model is no longer available. Switched to \(name)."
        }
        next.reasoning = next.normalizedReasoning()
        return (next, notice)
    }
}

public struct AISettingsStore {
    private static let store = JSONFileStore<AISettings>("ai_settings.json")

    public static func save(_ settings: AISettings) throws { try store.save(settings) }
    public static func load() throws -> AISettings? { try store.load() }
    public static func delete() throws { try store.delete() }
}
