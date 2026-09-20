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

// AppKit hands first responder to the only focusable control in a SwiftUI window, so the
// field must refuse it for exactly as long as that automatic assignment lasts -- see
// Sources/QuillKit/Views/Sidebar/CLAUDE.md.
final class ClickToFocusSearchField: NSSearchField {
    private var hasReleasedGuard = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        refusesFirstResponder = true
        if window.isKeyWindow {
            releaseGuardAfterInitialAssignment()
        } else {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidBecomeKey),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
        }
    }

    @objc private func windowDidBecomeKey() {
        releaseGuardAfterInitialAssignment()
    }

    // The automatic assignment happens as the window becomes key; releasing on the next
    // runloop turn lands after it, leaving the field reachable by Tab and VoiceOver.
    private func releaseGuardAfterInitialAssignment() {
        guard !hasReleasedGuard else { return }
        hasReleasedGuard = true
        DispatchQueue.main.async { [weak self] in
            self?.refusesFirstResponder = false
        }
    }

    override func mouseDown(with event: NSEvent) {
        refusesFirstResponder = false
        hasReleasedGuard = true
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}
