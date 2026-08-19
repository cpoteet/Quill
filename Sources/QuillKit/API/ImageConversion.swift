import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Converts HEIC/HEIF images to JPEG before upload.
///
/// WordPress 7.1 accepts HEIC over the REST API but cannot generate sub-sizes for it,
/// so the attachment lands with no dimensions and no sizes. Converting locally keeps the
/// server on a format it can resize. See `docs/wordpress-release-audit.md`.
enum ImageConversion {

    static let jpegQuality: CGFloat = 0.9

    struct Prepared {
        let fileURL: URL
        let filename: String
        let mimeType: String
        let didConvert: Bool

        /// Removes the converted temp file. No-op when the original was passed through.
        func cleanup() {
            guard didConvert else { return }
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }
    }

    /// Returns the file to upload, converting HEIC/HEIF to JPEG. Any failure falls back to
    /// the original file, which is the pre-conversion behavior.
    static func prepareForUpload(_ url: URL) -> Prepared {
        let original = Prepared(
            fileURL: url,
            filename: url.lastPathComponent,
            mimeType: MimeType.forFile(url),
            didConvert: false
        )
        guard needsConversion(url), let converted = convertToJPEG(url) else { return original }
        return converted
    }

    private static func needsConversion(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .heic) || type.conforms(to: .heif)
    }

    private static func convertToJPEG(_ url: URL) -> Prepared? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-upload-\(UUID().uuidString)")
        guard (try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )) != nil else { return nil }

        let filename = url.deletingPathExtension().lastPathComponent + ".jpg"
        let output = directory.appendingPathComponent(filename)

        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            try? FileManager.default.removeItem(at: directory)
            return nil
        }

        // Carry the source metadata across, notably EXIF orientation — WordPress applies
        // the rotation server-side, so dropping the tag publishes the photo sideways.
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        properties[kCGImageDestinationLossyCompressionQuality] = jpegQuality
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: directory)
            return nil
        }

        return Prepared(
            fileURL: output, filename: filename, mimeType: "image/jpeg", didConvert: true
        )
    }
}
