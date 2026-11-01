import AppKit
import Foundation
import Testing
@testable import QuillKit

func makeSiteProfileStore() throws -> SiteProfileStore {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("QuillSiteProfileTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return SiteProfileStore(in: dir)
}

func tinyPNG() -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    return rep.representation(using: .png, properties: [:])!
}

@Suite struct SiteProfileStoreTests {
    @Test func storesProfilesPerSiteKey() throws {
        let store = try makeSiteProfileStore()
        let profile = SiteProfile(name: "Siolon", iconURL: URL(string: "https://a.test/icon.png"), iconData: tinyPNG())
        try store.setProfile(profile, for: "a")
        #expect(store.profile(for: "a") == profile)
        #expect(store.profile(for: "b") == nil)
    }

    @Test func nilProfileRemovesTheEntry() throws {
        let store = try makeSiteProfileStore()
        try store.setProfile(SiteProfile(name: "Siolon"), for: "a")
        try store.setProfile(SiteProfile(name: "Other"), for: "b")
        try store.setProfile(nil, for: "a")
        #expect(store.profile(for: "a") == nil)
        #expect(store.profile(for: "b")?.name == "Other")
    }
}
