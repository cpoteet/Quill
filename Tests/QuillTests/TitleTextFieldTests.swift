import AppKit
import SwiftUI
import Testing
@testable import QuillKit

@Suite struct TitleTextFieldTests {
    @Test func pastedLinesBecomeOneLine() {
        #expect(TitleTextField.singleLine("First line\n\nSecond line\nThird") == "First line Second line Third")
    }

    @Test func spacesAroundBreaksAndBlankEdgesGo() {
        #expect(TitleTextField.singleLine("\n  Lead  \r\n  trail \n\n") == "Lead trail")
    }

    @Test func otherLineSeparatorsCountToo() {
        #expect(TitleTextField.singleLine("a\u{2028}b\u{2029}c") == "a b c")
    }
}

// The delegate check that applies singleLine, driven through a real text view: what lands in the
// field and in the binding, and where the joined text goes.
@MainActor @Suite struct TitleTextFieldCoordinatorTests {
    final class Box { var value = "" }

    private func field(_ initial: String) -> (RestrictedTextView, TitleTextField.Coordinator, Box) {
        let box = Box()
        box.value = initial
        let coordinator = TitleTextField.Coordinator(text: Binding(get: { box.value }, set: { box.value = $0 }))
        let tv = RestrictedTextView()
        tv.isRichText = false
        tv.string = initial
        tv.delegate = coordinator
        return (tv, coordinator, box)
    }

    @Test func textWithLineBreaksGoesInAsOneLineAtTheSelection() {
        let (tv, coordinator, box) = field("Title: ")
        tv.setSelectedRange(NSRange(location: 7, length: 0))
        tv.insertText("First\n\n  Second\nThird", replacementRange: tv.selectedRange())
        #expect(tv.string == "Title: First Second Third")
        #expect(box.value == "Title: First Second Third")
        #expect(tv.selectedRange() == NSRange(location: 25, length: 0))
        withExtendedLifetime(coordinator) {}
    }

    @Test func aPasteReplacingASelectionIsJoinedToo() {
        let (tv, coordinator, box) = field("Old title here")
        let board = NSPasteboard(name: NSPasteboard.Name("quill-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("New\ntitle", forType: .string)
        tv.setSelectedRange(NSRange(location: 0, length: 9))
        #expect(tv.readSelection(from: board, type: .string))
        #expect(tv.string == "New title here")
        #expect(box.value == "New title here")
        withExtendedLifetime(coordinator) {}
    }

    @Test func textWithoutLineBreaksIsLeftToTheTextView() {
        let (tv, coordinator, _) = field("Title")
        #expect(coordinator.textView(tv, shouldChangeTextIn: NSRange(location: 5, length: 0), replacementString: " more"))
        #expect(coordinator.textView(tv, shouldChangeTextIn: NSRange(location: 0, length: 5), replacementString: nil))
        #expect(tv.string == "Title")
    }
}
