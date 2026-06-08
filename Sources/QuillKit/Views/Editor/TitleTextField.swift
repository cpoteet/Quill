import AppKit
import SwiftUI

struct TitleTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var nsFont: NSFont

    func makeNSView(context: Context) -> NSScrollView {
        let tv = RestrictedTextView()
        tv.font = nsFont
        tv.placeholder = placeholder
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.focusRingType = .none
        tv.textContainerInset = NSSize(width: 0, height: 1)
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.maximumNumberOfLines = 1
        tv.textContainer?.lineBreakMode = .byClipping
        // Decouple container width from view so all text is laid out and navigable.
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = true
        tv.delegate = context.coordinator

        let sv = NSScrollView()
        sv.hasVerticalScroller = false
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.borderType = .noBorder
        sv.drawsBackground = false
        sv.documentView = tv
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let tv = sv.documentView as? RestrictedTextView else { return }
        guard tv.string != text else { return }
        tv.string = text
        tv.font = nsFont  // restoring font after string replacement
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text.wrappedValue = tv.string
        }
    }
}

final class RestrictedTextView: NSTextView {
    var placeholder: String = "" { didSet { needsDisplay = true } }

    // rightMouseDown pops up our own menu directly so that
    // allowsContextMenuPlugIns = false is respected, preventing AutoFill
    // from being injected. NSTextView's own rightMouseDown path does not
    // honour that flag, so we bypass it by not calling super.
    override func rightMouseDown(with event: NSEvent) {
        NSMenu.popUpContextMenu(buildMenu(), with: event, for: self)
    }

    // menu(for:) is kept as a fallback for any code path that calls it directly.
    override func menu(for event: NSEvent) -> NSMenu? { buildMenu() }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.allowsContextMenuPlugIns = false
        menu.items = [
            NSMenuItem(title: "Cut",   action: NSSelectorFromString("cut:"),   keyEquivalent: ""),
            NSMenuItem(title: "Copy",  action: NSSelectorFromString("copy:"),  keyEquivalent: ""),
            NSMenuItem(title: "Paste", action: NSSelectorFromString("paste:"), keyEquivalent: ""),
        ]
        return menu
    }

    override func insertNewline(_ sender: Any?) {
        window?.selectNextKeyView(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let f = font ?? NSFont.systemFont(ofSize: 17)
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.placeholderTextColor,
            .font: f,
        ]
        placeholder.draw(at: NSPoint(x: 0, y: 1), withAttributes: attrs)
    }
}
