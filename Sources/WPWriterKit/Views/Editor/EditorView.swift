import SwiftUI
import WebKit

public struct EditorView: NSViewRepresentable {
    @Binding var html: String
    var onContentChange: (String) -> Void
    var onInsertImageAt: ((Int) -> Void)?

    public init(html: Binding<String>, onContentChange: @escaping (String) -> Void, onInsertImageAt: ((Int) -> Void)? = nil) {
        self._html = html
        self.onContentChange = onContentChange
        self.onInsertImageAt = onInsertImageAt
    }

    public func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(onContentChange: onContentChange, onReady: {})
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "contentChanged")
        config.userContentController.add(context.coordinator, name: "editorReady")
        config.userContentController.add(context.coordinator, name: "insertImageAtIndex")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.onInsertImageAt = onInsertImageAt
        loadEditorHTML(in: webView)
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.setContent(html)
    }

    private func loadEditorHTML(in webView: WKWebView) {
        guard let htmlURL = Bundle.main.url(forResource: "editor", withExtension: "html") else {
            return
        }
        let resourceDir = htmlURL.deletingLastPathComponent()
        webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDir)
    }
}
