import AppKit
import SwiftUI

struct SidebarSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String

    func makeNSView(context: Context) -> ClickToFocusSearchField {
        let field = ClickToFocusSearchField()
        field.delegate = context.coordinator
        field.placeholderString = prompt
        field.sendsSearchStringImmediately = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: ClickToFocusSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        if field.placeholderString != prompt { field.placeholderString = prompt }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

// AppKit hands first responder to the only focusable control in a SwiftUI window; .searchable never did
final class ClickToFocusSearchField: NSSearchField {
    private var wasClicked = false

    override var acceptsFirstResponder: Bool { wasClicked }

    override func mouseDown(with event: NSEvent) {
        wasClicked = true
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}
