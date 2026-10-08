import Foundation
@testable import QuillKit

// Models API values recorded on 2026-10-07.
let haiku45 = AIModelInfo(
    id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5",
    createdAt: ISO8601DateFormatter().date(from: "2025-10-15T00:00:00Z")!,
    maxTokens: 64000, line: "haiku",
    supportsAdaptiveThinking: false, supportsEnabledThinking: true,
    effortLevels: [], supportsWebSearch: true
)
let haiku55 = AIModelInfo(
    id: "claude-haiku-5-5", displayName: "Claude Haiku 5.5",
    createdAt: ISO8601DateFormatter().date(from: "2026-10-07T18:00:00Z")!,
    maxTokens: 128000, line: "haiku",
    supportsAdaptiveThinking: true, supportsEnabledThinking: false,
    effortLevels: ["low", "medium", "high", "xhigh", "max"], supportsWebSearch: true
)
let sonnet55 = AIModelInfo(
    id: "claude-sonnet-5-5", displayName: "Claude Sonnet 5.5",
    createdAt: ISO8601DateFormatter().date(from: "2026-09-28T00:00:00Z")!,
    maxTokens: 128000, line: "sonnet",
    supportsAdaptiveThinking: true, supportsEnabledThinking: false,
    effortLevels: ["low", "medium", "high", "xhigh", "max"], supportsWebSearch: true
)
