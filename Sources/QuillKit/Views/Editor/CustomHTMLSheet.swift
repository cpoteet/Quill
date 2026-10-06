import SwiftUI

/// The `customHTML` message body: `{}` inserts a new block, `{ html }` edits the card it came from.
public struct CustomHTMLRequest: Identifiable {
    public let id = UUID()
    public let html: String?

    public init?(body: Any) {
        guard let dict = body as? [String: Any] else { return nil }
        if let value = dict["html"] {
            guard let html = value as? String else { return nil }
            self.html = html
        } else {
            self.html = nil
        }
    }

    public var isEditing: Bool { html != nil }
}

/// A Custom HTML block's content split the way Gutenberg's editor splits it: a marked `<style>`, a marked `<script>`, then the HTML.
struct CustomHTMLParts: Equatable {
    private static let styleOpen = "<style data-wp-block-html=\"css\">"
    private static let scriptOpen = "<script data-wp-block-html=\"js\">"

    var html: String
    var css: String
    var js: String

    init(html: String, css: String, js: String) {
        self.html = html
        self.css = css
        self.js = js
    }

    // Only where Gutenberg writes them, ahead of the HTML: a marker in a comment or a script stays HTML, never revived.
    init(content: String) {
        var rest = Substring(content)
        let css = Self.extract(&rest, open: Self.styleOpen, close: "</style>")
        let js = Self.extract(&rest, open: Self.scriptOpen, close: "</script>")
        self.css = css ?? ""
        self.js = js ?? ""
        html = css == nil && js == nil ? content : rest.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extract(_ text: inout Substring, open: String, close: String) -> String? {
        let start = text.drop(while: \.isWhitespace)
        guard start.hasPrefix(open), let end = start.range(of: close) else { return nil }
        let inner = start[start.index(start.startIndex, offsetBy: open.count)..<end.lowerBound]
        text = start[end.upperBound...]
        return inner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var content: String {
        guard hasCode else { return html }
        var parts: [String] = []
        if !css.isBlank { parts.append("\(Self.styleOpen)\n\(css)\n</style>") }
        if !js.isBlank { parts.append("\(Self.scriptOpen)\n\(js)\n</script>") }
        if !html.isBlank { parts.append(html) }
        return parts.joined(separator: "\n\n")
    }

    var hasCode: Bool { !css.isBlank || !js.isBlank }
    var isEmpty: Bool { html.isBlank && !hasCode }
}

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct CustomHTMLSheet: View {
    enum Tab: String, CaseIterable {
        case html = "HTML", css = "CSS", js = "JavaScript"
    }

    let request: CustomHTMLRequest
    let canPostUnfilteredHTML: Bool?
    var onCommit: (String) -> Void
    var onCancel: () -> Void

    @State private var parts: CustomHTMLParts
    @State private var tab: Tab = .html
    private let openedWithCode: Bool

    init(request: CustomHTMLRequest, canPostUnfilteredHTML: Bool?,
         onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.request = request
        self.canPostUnfilteredHTML = canPostUnfilteredHTML
        self.onCommit = onCommit
        self.onCancel = onCancel
        let parts = CustomHTMLParts(content: request.html ?? "")
        _parts = State(initialValue: parts)
        openedWithCode = parts.hasCode
    }

    // A block that already holds CSS or JavaScript always shows it, so nothing in it is hidden while editing.
    private var showsCodeTabs: Bool { canPostUnfilteredHTML == true || openedWithCode }

    private var text: Binding<String> {
        switch tab {
        case .html: return $parts.html
        case .css: return $parts.css
        case .js: return $parts.js
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.isEditing ? "Edit Custom HTML" : "Custom HTML")
                .font(.headline)

            if showsCodeTabs {
                Picker("Language", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            CodeTextView(text: text, document: tab)
                .frame(minWidth: 520, minHeight: 240)
                .padding(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                )

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button(request.isEditing ? "Save" : "Insert") { onCommit(parts.content) }
                    .buttonStyle(.borderedProminent)
                    .disabled(parts.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(20)
    }
}
