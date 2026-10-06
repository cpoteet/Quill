import AppKit
import SwiftUI

/// A plain-text box for markup: SwiftUI's `TextEditor` follows the system's smart-quote and dash substitution, which breaks HTML.
struct CodeTextView: NSViewRepresentable {
    @Binding var text: String
    /// Changing it swaps in `text` as a new document: fresh undo history, and the box takes focus.
    var document: AnyHashable = 0

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSTextView.scrollableTextView()
        sv.drawsBackground = false
        guard let tv = sv.documentView as? NSTextView else { return sv }
        tv.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.string = text
        tv.delegate = context.coordinator
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.text = $text
        guard let tv = sv.documentView as? NSTextView else { return }
        if coordinator.document != document {
            coordinator.document = document
            tv.string = text
            coordinator.undo.removeAllActions()
            tv.window?.makeFirstResponder(tv)
        } else if tv.string != text {
            tv.string = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, document: document) }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var document: AnyHashable
        // Its own history, so undo never carries one document's edits into another.
        let undo = UndoManager()
        init(text: Binding<String>, document: AnyHashable) {
            self.text = text
            self.document = document
        }
        func undoManager(for view: NSTextView) -> UndoManager? { undo }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text.wrappedValue = tv.string
        }
    }
}
