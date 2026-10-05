import Foundation
import Testing
@testable import QuillKit

@Suite struct FeaturedImageSectionTests {

    private static func writeFile(named name: String, bytes: [UInt8]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-featured-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    @Test func droppedImageIsCopiedAloneIntoAFreshTempFolder() async throws {
        let bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 1, 2, 3]
        let original = try Self.writeFile(named: "photo.png", bytes: bytes)
        defer { try? FileManager.default.removeItem(at: original.deletingLastPathComponent()) }
        let provider = try #require(NSItemProvider(contentsOf: original))

        let copy = try #require(await FeaturedImageSection.copyDroppedImage(from: provider))
        let folder = copy.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(copy.lastPathComponent == "photo.png")
        #expect(folder.deletingLastPathComponent().standardizedFileURL.path
                == FileManager.default.temporaryDirectory.standardizedFileURL.path)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [copy.lastPathComponent])
        #expect(try Data(contentsOf: copy) == Data(bytes))
        #expect(FileManager.default.fileExists(atPath: original.path))
    }

    @Test func twoDropsOfTheSameFileGetSeparateFolders() async throws {
        let original = try Self.writeFile(named: "photo.png", bytes: [0x89, 0x50, 0x4E, 0x47])
        defer { try? FileManager.default.removeItem(at: original.deletingLastPathComponent()) }

        let firstProvider = try #require(NSItemProvider(contentsOf: original))
        let secondProvider = try #require(NSItemProvider(contentsOf: original))
        let first = try #require(await FeaturedImageSection.copyDroppedImage(from: firstProvider))
        let second = try #require(await FeaturedImageSection.copyDroppedImage(from: secondProvider))
        defer {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
        }

        #expect(first.deletingLastPathComponent() != second.deletingLastPathComponent())
    }

    @Test func providerWithoutAnImageYieldsNil() async {
        let provider = NSItemProvider(object: "not an image" as NSString)
        #expect(await FeaturedImageSection.copyDroppedImage(from: provider) == nil)
    }
}
