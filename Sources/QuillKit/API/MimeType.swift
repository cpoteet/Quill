import Foundation
import UniformTypeIdentifiers

/// Single source of truth for file-extension → MIME type mapping, used wherever files are
/// uploaded to WordPress (image drops, media picker, media sidebar). Backed by the system's
/// UTType database instead of a hand-maintained list, so it can't silently drift between call sites.
enum MimeType {
    static func forFile(_ url: URL) -> String {
        forExtension(url.pathExtension)
    }

    static func forExtension(_ ext: String) -> String {
        UTType(filenameExtension: ext.lowercased())?.preferredMIMEType ?? "application/octet-stream"
    }
}
