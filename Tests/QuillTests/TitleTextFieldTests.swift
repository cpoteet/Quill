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
