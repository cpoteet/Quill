import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import QuillKit

/// WordPress 7.1 accepts HEIC uploads but cannot process them server-side, leaving
/// attachments with no dimensions and no sub-sizes. `ImageConversion` converts HEIC/HEIF
/// to JPEG locally so the server always receives a format it can resize.
@Suite struct ImageConversionTests {

    // MARK: - Fixtures

    /// Writes a real image file of the given type, so the tests exercise ImageIO rather
    /// than a stubbed conversion.
    private static func writeImage(
        type: UTType,
        orientation: Int? = nil,
        pixel: (r: UInt8, g: UInt8, b: UInt8) = (200, 80, 40)
    ) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-conv-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = type.preferredFilenameExtension ?? "img"
        let url = dir.appendingPathComponent("photo.\(ext)")

        let width = 64, height = 32
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = pixel.r; bytes[i + 1] = pixel.g; bytes[i + 2] = pixel.b; bytes[i + 3] = 255
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = ctx.makeImage()!

        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, type.identifier as CFString, 1, nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var props: [CFString: Any] = [:]
        if let orientation { props[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    private static func writeRawFile(named name: String, bytes: [UInt8]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-conv-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    private static func imageType(of url: URL) -> String? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceGetType(src) as String?
    }

    // MARK: - HEIC conversion

    @Test func heicIsConvertedToJPEG() throws {
        let heic = try Self.writeImage(type: .heic)
        let prepared = ImageConversion.prepareForUpload(heic)
        defer { prepared.cleanup() }

        #expect(prepared.didConvert)
        #expect(prepared.mimeType == "image/jpeg")
        #expect(Self.imageType(of: prepared.fileURL) == UTType.jpeg.identifier)
    }

    @Test func convertedFilenameUsesJPGExtension() throws {
        let heic = try Self.writeImage(type: .heic)
        let prepared = ImageConversion.prepareForUpload(heic)
        defer { prepared.cleanup() }

        #expect(prepared.filename == "photo.jpg")
    }

    @Test func conversionWritesToADifferentFileAndLeavesTheOriginalInPlace() throws {
        let heic = try Self.writeImage(type: .heic)
        let prepared = ImageConversion.prepareForUpload(heic)
        defer { prepared.cleanup() }

        #expect(prepared.fileURL != heic)
        #expect(FileManager.default.fileExists(atPath: heic.path))
    }

    @Test func conversionPreservesEXIFOrientation() throws {
        // 6 = rotate 90° CW. WordPress applies the rotation server-side, so the tag
        // must survive the conversion or the photo publishes sideways.
        let heic = try Self.writeImage(type: .heic, orientation: 6)
        let prepared = ImageConversion.prepareForUpload(heic)
        defer { prepared.cleanup() }

        let src = CGImageSourceCreateWithURL(prepared.fileURL as CFURL, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        #expect(props?[kCGImagePropertyOrientation] as? Int == 6)
    }

    @Test func cleanupRemovesTheConvertedTempFile() throws {
        let heic = try Self.writeImage(type: .heic)
        let prepared = ImageConversion.prepareForUpload(heic)
        let converted = prepared.fileURL

        prepared.cleanup()

        #expect(!FileManager.default.fileExists(atPath: converted.path))
    }

    // MARK: - Pass-through

    @Test func jpegPassesThroughUntouched() throws {
        let jpeg = try Self.writeImage(type: .jpeg)
        let prepared = ImageConversion.prepareForUpload(jpeg)
        defer { prepared.cleanup() }

        #expect(!prepared.didConvert)
        #expect(prepared.fileURL == jpeg)
        #expect(prepared.filename == "photo.jpeg")
        #expect(prepared.mimeType == "image/jpeg")
    }

    @Test func pngPassesThroughUntouched() throws {
        let png = try Self.writeImage(type: .png)
        let prepared = ImageConversion.prepareForUpload(png)
        defer { prepared.cleanup() }

        #expect(!prepared.didConvert)
        #expect(prepared.fileURL == png)
        #expect(prepared.mimeType == "image/png")
    }

    @Test func pdfPassesThroughUntouched() throws {
        // The media sidebar allows PDF uploads; conversion must not touch them.
        let pdf = try Self.writeRawFile(named: "doc.pdf", bytes: Array("%PDF-1.4\n".utf8))
        let prepared = ImageConversion.prepareForUpload(pdf)
        defer { prepared.cleanup() }

        #expect(!prepared.didConvert)
        #expect(prepared.fileURL == pdf)
        #expect(prepared.mimeType == "application/pdf")
    }

    @Test func cleanupOnAPassedThroughFileDoesNotDeleteIt() throws {
        let jpeg = try Self.writeImage(type: .jpeg)
        let prepared = ImageConversion.prepareForUpload(jpeg)

        prepared.cleanup()

        #expect(FileManager.default.fileExists(atPath: jpeg.path))
    }

    // MARK: - Failure handling

    @Test func unreadableHEICFallsBackToTheOriginalFile() throws {
        // A .heic extension on bytes ImageIO cannot decode. Uploading the original is
        // today's behavior, so a conversion failure must not make things worse.
        let broken = try Self.writeRawFile(named: "broken.heic", bytes: [0x00, 0x01, 0x02, 0x03])
        let prepared = ImageConversion.prepareForUpload(broken)
        defer { prepared.cleanup() }

        #expect(!prepared.didConvert)
        #expect(prepared.fileURL == broken)
        #expect(prepared.filename == "broken.heic")
        #expect(prepared.mimeType == "image/heic")
    }

    @Test func heifExtensionIsConvertedToJPEG() throws {
        // ImageIO on macOS can decode HEIF but can only *write* HEIC, so the fixture uses
        // HEIC bytes under a .heif name. `needsConversion` keys off the extension, which
        // is what this asserts; ImageIO decodes by content regardless of the name.
        let heic = try Self.writeImage(type: .heic)
        let heif = heic.deletingPathExtension().appendingPathExtension("heif")
        try FileManager.default.moveItem(at: heic, to: heif)

        let prepared = ImageConversion.prepareForUpload(heif)
        defer { prepared.cleanup() }

        #expect(prepared.didConvert)
        #expect(prepared.filename == "photo.jpg")
        #expect(prepared.mimeType == "image/jpeg")
        #expect(Self.imageType(of: prepared.fileURL) == UTType.jpeg.identifier)
    }
}
