import SwiftUI
import WebKit

public struct EditorView: NSViewRepresentable {
    @Binding var html: String
    var onContentChange: (String) -> Void
    var onInsertImageAt: ((Int) -> Void)?
    var onImageFilesDropped: (([URL]) -> Void)?

    public init(
        html: Binding<String>,
        onContentChange: @escaping (String) -> Void,
        onInsertImageAt: ((Int) -> Void)? = nil,
        onImageFilesDropped: (([URL]) -> Void)? = nil
    ) {
        self._html = html
        self.onContentChange = onContentChange
        self.onInsertImageAt = onInsertImageAt
        self.onImageFilesDropped = onImageFilesDropped
    }

    public func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(onContentChange: onContentChange, onReady: {})
    }

    public func makeNSView(context: Context) -> DroppableWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "contentChanged")
        config.userContentController.add(context.coordinator, name: "editorReady")
        config.userContentController.add(context.coordinator, name: "insertImageAtIndex")

        let webView = DroppableWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.onImageFilesDropped = onImageFilesDropped
        context.coordinator.webView = webView
        context.coordinator.onInsertImageAt = onInsertImageAt
        loadEditorHTML(in: webView)
        return webView
    }

    public func updateNSView(_ nsView: DroppableWebView, context: Context) {
        context.coordinator.setContent(html)
        nsView.onImageFilesDropped = onImageFilesDropped
    }

    private func loadEditorHTML(in webView: WKWebView) {
        guard let htmlURL = Bundle.main.url(forResource: "editor", withExtension: "html") else {
            return
        }
        let resourceDir = htmlURL.deletingLastPathComponent()
        webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDir)
    }
}
