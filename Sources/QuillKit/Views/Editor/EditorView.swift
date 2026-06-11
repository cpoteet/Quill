import SwiftUI
import WebKit

public struct EditorView: NSViewRepresentable {
    @Binding var html: String
    var onContentChange: (String) -> Void
    var onEditorReady: (() -> Void)?
    var onInsertImage: (() -> Void)?
    var onImageFilesDropped: (([URL]) -> Void)?
    var onSearchLinks: ((String) async throws -> [LinkSearchResult])?
    var onRequestMediaSizes: ((Int) async -> WPMedia?)?
    var onSelectionChanged: ((CGRect?) -> Void)?
    var onStatsChanged: ((Int, Int) -> Void)?
    var onWebViewCreated: ((WKWebView) -> Void)?
    var onAIOperation: ((AIWritingOperation) -> Void)?
    var aiEnabled: Bool
    var hasTextSelection: Bool

    public init(
        html: Binding<String>,
        onContentChange: @escaping (String) -> Void,
        onEditorReady: (() -> Void)? = nil,
        onInsertImage: (() -> Void)? = nil,
        onImageFilesDropped: (([URL]) -> Void)? = nil,
        onSearchLinks: ((String) async throws -> [LinkSearchResult])? = nil,
        onRequestMediaSizes: ((Int) async -> WPMedia?)? = nil,
        onSelectionChanged: ((CGRect?) -> Void)? = nil,
        onStatsChanged: ((Int, Int) -> Void)? = nil,
        onWebViewCreated: ((WKWebView) -> Void)? = nil,
        onAIOperation: ((AIWritingOperation) -> Void)? = nil,
        aiEnabled: Bool = false,
        hasTextSelection: Bool = false
    ) {
        self._html = html
        self.onContentChange = onContentChange
        self.onEditorReady = onEditorReady
        self.onInsertImage = onInsertImage
        self.onImageFilesDropped = onImageFilesDropped
        self.onSearchLinks = onSearchLinks
        self.onRequestMediaSizes = onRequestMediaSizes
        self.onSelectionChanged = onSelectionChanged
        self.onStatsChanged = onStatsChanged
        self.onWebViewCreated = onWebViewCreated
        self.onAIOperation = onAIOperation
        self.aiEnabled = aiEnabled
        self.hasTextSelection = hasTextSelection
    }

    public func makeCoordinator() -> EditorCoordinator {
        let ready = onEditorReady
        return EditorCoordinator(onContentChange: onContentChange, onReady: { ready?() })
    }

    public func makeNSView(context: Context) -> DroppableWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "contentChanged")
        config.userContentController.add(context.coordinator, name: "editorReady")
        config.userContentController.add(context.coordinator, name: "insertImage")
        config.userContentController.add(context.coordinator, name: "showLinkPicker")
        config.userContentController.add(context.coordinator, name: "requestMediaSizes")
        config.userContentController.add(context.coordinator, name: "selectionChanged")
        config.userContentController.add(context.coordinator, name: "statsChanged")
        config.userContentController.add(context.coordinator, name: "checkSpelling")

        let webView = DroppableWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.onImageFilesDropped = onImageFilesDropped
        webView.onAIOperation = onAIOperation
        webView.aiEnabled = aiEnabled
        webView.hasTextSelection = hasTextSelection
        context.coordinator.webView = webView
        let onCreate = onWebViewCreated
        Task { @MainActor in onCreate?(webView) }
        context.coordinator.onInsertImage = onInsertImage
        context.coordinator.onSearchLinks = onSearchLinks
        context.coordinator.onRequestMediaSizes = onRequestMediaSizes
        context.coordinator.onSelectionChanged = onSelectionChanged
        context.coordinator.onStatsChanged = onStatsChanged
        loadEditorHTML(in: webView)
        return webView
    }

    public func updateNSView(_ nsView: DroppableWebView, context: Context) {
        let ready = onEditorReady
        context.coordinator.onContentChange = onContentChange
        context.coordinator.onReady = { ready?() }
        context.coordinator.setContent(html)
        context.coordinator.onInsertImage = onInsertImage
        context.coordinator.onSearchLinks = onSearchLinks
        context.coordinator.onRequestMediaSizes = onRequestMediaSizes
        context.coordinator.onSelectionChanged = onSelectionChanged
        context.coordinator.onStatsChanged = onStatsChanged
        nsView.onImageFilesDropped = onImageFilesDropped
        nsView.onAIOperation = onAIOperation
        nsView.aiEnabled = aiEnabled
        nsView.hasTextSelection = hasTextSelection
    }

    public static func dismantleNSView(_ nsView: DroppableWebView, coordinator: EditorCoordinator) {
        nsView.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    private func loadEditorHTML(in webView: WKWebView) {
        guard let htmlURL = Bundle.main.url(forResource: "editor", withExtension: "html") else { return }
        // loadFileURL with allowingReadAccessTo grants the page access to the whole Resources
        // directory, so the relative ./tiptap-bundle.js import resolves to the bundled file.
        // All imports are same-origin (file://), so no cross-origin restrictions apply.
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
    }
}
