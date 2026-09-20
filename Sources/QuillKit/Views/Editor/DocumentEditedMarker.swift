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
        nsView.window?.isDocumentEdited = false
    }
}

private final class MarkerView: NSView {
    var isEdited = false {
        didSet { apply() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    private func apply() {
        guard let window, window.isDocumentEdited != isEdited else { return }
        window.isDocumentEdited = isEdited
    }
}
