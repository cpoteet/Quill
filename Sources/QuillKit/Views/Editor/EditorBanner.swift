import Foundation

/// The error shown above the editor, and the operation that reported it.
struct EditorBanner: Equatable {
    enum Source {
        case load, save, autosave, preview, upload, featuredImage, gallery, revert, ai
    }

    let message: String
    let source: Source

    func clearing(_ operation: Source) -> EditorBanner? {
        source == operation ? nil : self
    }
}
