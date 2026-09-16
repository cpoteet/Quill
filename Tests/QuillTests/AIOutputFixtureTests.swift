import Foundation
import Testing
@testable import QuillKit

// Scripts/test-ai-output-validity.js loads each .html here, so it must stay what Swift sends the editor.
@Suite struct AIOutputFixtureTests {

    static let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Scripts/fixtures/ai")

    static var names: [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.filter { $0.hasSuffix(".raw.txt") }.map { String($0.dropLast(".raw.txt".count)) }.sorted()
    }

    private func read(_ file: String) throws -> String {
        try String(contentsOf: Self.dir.appendingPathComponent(file), encoding: .utf8)
    }

    @Test func corpusIsPresent() {
        #expect(Self.names.contains("generate-post"))
        #expect(Self.names.filter { $0.hasPrefix("operation-") }.count >= 3)
    }

    @Test(arguments: names)
    func cleanedFixtureMatchesSwiftCleanup(name: String) throws {
        let raw = try read("\(name).raw.txt")
        let expected = try read("\(name).html")
        let cleaned = name.hasPrefix("generate-")
            ? AIPromptBuilder.parseGenerateResponse(raw)?.html
            : AIPromptBuilder.cleanOperationResult(raw)
        #expect(cleaned == expected)
    }
}
