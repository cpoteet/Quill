import SwiftUI

// Drives the standard unsaved-changes dot in the window's close button from the
// editor's dirty state. Quill has no dirty indicator of its own.
struct DocumentEditedMarker: NSViewRepresentable {
    let isEdited: Bool

    func makeNSView(context: Context) -> NSView { MarkerView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let marker = nsView as? MarkerView else { return }
        marker.isEdited = isEdited
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? MarkerView)?.clearMark()
    }
}

private final class MarkerView: NSView {
    // Dismantle can run after SwiftUI has detached the view, when `window` is already nil.
    private weak var markedWindow: NSWindow?

    var isEdited = false {
        didSet { apply() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    func clearMark() {
        guard let target = window ?? markedWindow, target.isDocumentEdited else { return }
        target.isDocumentEdited = false
    }

    private func apply() {
        guard let window else { return }
        markedWindow = window
        guard window.isDocumentEdited != isEdited else { return }
        window.isDocumentEdited = isEdited
    }
}
