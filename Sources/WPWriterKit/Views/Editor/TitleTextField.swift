import AppKit
import SwiftUI

struct TitleTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var nsFont: NSFont

    func makeNSView(context: Context) -> RestrictedTextView {
        let tv = RestrictedTextView()
        tv.font = nsFont
        tv.placeholder = placeholder
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.focusRingType = .none
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.maximumNumberOfLines = 1
        tv.textContainer?.lineBreakMode = .byClipping
        tv.textContainer?.widthTracksTextView = true
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.delegate = context.coordinator
        return tv
    }

    func updateNSView(_ tv: RestrictedTextView, context: Context) {
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

    private let menuRefilter = TextMenuRefilter()

    // menu(for:) is called directly on NSTextView — no shared field editor.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.items = [
            NSMenuItem(title: "Cut", action: NSSelectorFromString("cut:"), keyEquivalent: ""),
            NSMenuItem(title: "Copy", action: NSSelectorFromString("copy:"), keyEquivalent: ""),
            NSMenuItem(title: "Paste", action: NSSelectorFromString("paste:"), keyEquivalent: ""),
        ]
        // Catch any items macOS appends (AutoFill, Services) before the menu shows.
        menu.delegate = menuRefilter
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
        placeholder.draw(at: NSPoint(x: 0, y: 0), withAttributes: attrs)
    }
}

private final class TextMenuRefilter: NSObject, NSMenuDelegate {
    private static let allowed: Set<String> = ["cut:", "copy:", "paste:"]

    func menuWillOpen(_ menu: NSMenu) {
        menu.items = menu.items.filter { item in
            guard let action = item.action else { return false }
            return Self.allowed.contains(NSStringFromSelector(action))
        }
    }
}
