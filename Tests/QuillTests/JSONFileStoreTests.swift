import Foundation
import Testing
@testable import QuillKit

private struct Fixture: Codable, Equatable {
    var value: String
    var count: Int
}

// Each test gets its own temp directory injected directly into JSONFileStore via the
// `in: baseDirectory` parameter — no global AppSupportDirectory.override needed, so
// this suite can safely run in parallel with other file-store suites.
@Suite struct JSONFileStoreTests {

    private func makeStore(_ filename: String) throws -> (JSONFileStore<Fixture>, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillJSONStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (JSONFileStore<Fixture>(filename, in: dir), dir)
    }

    @Test func roundTrip() throws {
        let (store, _) = try makeStore("fixture.json")
        let fixture = Fixture(value: "hello", count: 42)
        try store.save(fixture)
        let loaded = try store.load()
        #expect(loaded == fixture)
    }

    @Test func loadReturnsNilWhenAbsent() throws {
        let (store, _) = try makeStore("absent.json")
        let result = try store.load()
        #expect(result == nil)
    }

    @Test func deleteRemovesFile() throws {
        let (store, _) = try makeStore("todelete.json")
        try store.save(Fixture(value: "x", count: 1))
        try store.delete()
        #expect(try store.load() == nil)
    }

    @Test func deleteWhenAbsentDoesNotThrow() throws {
        let (store, _) = try makeStore("nonexistent.json")
        try store.delete()
    }

    @Test func overwriteKeepsLatestValue() throws {
        let (store, _) = try makeStore("overwrite.json")
        try store.save(Fixture(value: "first", count: 1))
        try store.save(Fixture(value: "second", count: 2))
        let loaded = try store.load()
        #expect(loaded?.value == "second")
        #expect(loaded?.count == 2)
    }

    @Test func savedFileHasChmod600() throws {
        let (store, dir) = try makeStore("perms.json")
        try store.save(Fixture(value: "secure", count: 0))
        let url = dir.appendingPathComponent("perms.json")
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perms = attrs[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }

    @Test func decodeFailureThrows() throws {
        let (store, dir) = try makeStore("bad.json")
        let url = dir.appendingPathComponent("bad.json")
        try Data("not valid json".utf8).write(to: url)
        #expect(throws: (any Error).self) {
            try store.load()
        }
    }

    @Test func distinctFilenamesDontCollide() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillJSONStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeA = JSONFileStore<Fixture>("a.json", in: dir)
        let storeB = JSONFileStore<Fixture>("b.json", in: dir)
        try storeA.save(Fixture(value: "A", count: 1))
        try storeB.save(Fixture(value: "B", count: 2))
        #expect(try storeA.load()?.value == "A")
        #expect(try storeB.load()?.value == "B")
    }
}
