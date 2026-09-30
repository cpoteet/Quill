import SwiftUI
import WebKit

/// Lets the view that owns an `EditorView` call into its coordinator.
@MainActor
public final class EditorHandle {
    weak var coordinator: EditorCoordinator?

    public init() {}

    func flushPendingContent() async {
        await coordinator?.flushPendingContent()
    }

    func insertImage(url: String, mediaId: Int, alt: String) {
        coordinator?.insertImage(url: url, mediaId: mediaId, alt: alt)
    }
}

public struct EditorView: NSViewRepresentable {
    var handle: EditorHandle?
    @Binding var html: String
    var footnotes: String
    @Binding var contentSyncPending: Bool
    var onContentChange: (String) -> Void
    var onEditorReady: (() -> Void)?
    var onInsertImage: (() -> Void)?
    var onInsertGallery: ((GalleryEdit?) -> Void)?
    var onImageFilesDropped: (([URL]) -> Void)?
    var onDropRejected: ((String) -> Void)?
    var onSearchLinks: ((String) async throws -> [LinkSearchResult])?
    var onRequestMediaSizes: ((Int) async -> WPMedia?)?
    var onSelectionChanged: ((CGRect?) -> Void)?
    var onStatsChanged: ((Int, Int) -> Void)?
    var onBlocksAtRisk: (([String]) -> Void)?
    var onFootnotesChange: ((String) -> Void)?
    var onWebViewCreated: ((WKWebView) -> Void)?
    var onAIOperation: ((AIWritingOperation) -> Void)?
    var onTriggerGenerate: (() -> Void)?
    var onTriggerEvaluate: (() -> Void)?
    var onImagesPasted: (([PastedImage]) -> Void)?
    var onGalleryUpdateDropped: (() -> Void)?
    var aiEnabled: Bool
    var hasTextSelection: Bool

    public init(
        handle: EditorHandle? = nil,
        html: Binding<String>,
        footnotes: String = "",
        contentSyncPending: Binding<Bool> = .constant(false),
        onContentChange: @escaping (String) -> Void,
        onEditorReady: (() -> Void)? = nil,
        onInsertImage: (() -> Void)? = nil,
        onInsertGallery: ((GalleryEdit?) -> Void)? = nil,
        onImageFilesDropped: (([URL]) -> Void)? = nil,
        onDropRejected: ((String) -> Void)? = nil,
        onSearchLinks: ((String) async throws -> [LinkSearchResult])? = nil,
        onRequestMediaSizes: ((Int) async -> WPMedia?)? = nil,
        onSelectionChanged: ((CGRect?) -> Void)? = nil,
        onStatsChanged: ((Int, Int) -> Void)? = nil,
        onBlocksAtRisk: (([String]) -> Void)? = nil,
        onFootnotesChange: ((String) -> Void)? = nil,
        onWebViewCreated: ((WKWebView) -> Void)? = nil,
        onAIOperation: ((AIWritingOperation) -> Void)? = nil,
        onTriggerGenerate: (() -> Void)? = nil,
        onTriggerEvaluate: (() -> Void)? = nil,
        onImagesPasted: (([PastedImage]) -> Void)? = nil,
        onGalleryUpdateDropped: (() -> Void)? = nil,
        aiEnabled: Bool = false,
        hasTextSelection: Bool = false
    ) {
        self.handle = handle
        self._html = html
        self.footnotes = footnotes
        self._contentSyncPending = contentSyncPending
        self.onContentChange = onContentChange
        self.onEditorReady = onEditorReady
        self.onInsertImage = onInsertImage
        self.onInsertGallery = onInsertGallery
        self.onImageFilesDropped = onImageFilesDropped
        self.onDropRejected = onDropRejected
        self.onSearchLinks = onSearchLinks
        self.onRequestMediaSizes = onRequestMediaSizes
        self.onSelectionChanged = onSelectionChanged
        self.onStatsChanged = onStatsChanged
        self.onBlocksAtRisk = onBlocksAtRisk
        self.onFootnotesChange = onFootnotesChange
        self.onWebViewCreated = onWebViewCreated
        self.onAIOperation = onAIOperation
        self.onTriggerGenerate = onTriggerGenerate
        self.onTriggerEvaluate = onTriggerEvaluate
        self.onImagesPasted = onImagesPasted
        self.onGalleryUpdateDropped = onGalleryUpdateDropped
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
        config.userContentController.add(context.coordinator, name: "insertGallery")
        config.userContentController.add(context.coordinator, name: "showLinkPicker")
        config.userContentController.add(context.coordinator, name: "requestMediaSizes")
        config.userContentController.add(context.coordinator, name: "selectionChanged")
        config.userContentController.add(context.coordinator, name: "statsChanged")
        config.userContentController.add(context.coordinator, name: "blocksAtRisk")
        config.userContentController.add(context.coordinator, name: "footnotesChanged")
        config.userContentController.add(context.coordinator, name: "checkSpelling")
        config.userContentController.add(context.coordinator, name: "triggerGenerate")
        config.userContentController.add(context.coordinator, name: "triggerEvaluate")
        config.userContentController.add(context.coordinator, name: "openLink")
        config.userContentController.add(context.coordinator, name: "uploadPastedImages")

        let webView = DroppableWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.onImageFilesDropped = onImageFilesDropped
        webView.onDropRejected = onDropRejected
        webView.onAIOperation = onAIOperation
        webView.aiEnabled = aiEnabled
        webView.hasTextSelection = hasTextSelection
        context.coordinator.webView = webView
        handle?.coordinator = context.coordinator
        let onCreate = onWebViewCreated
        Task { @MainActor in onCreate?(webView) }
        context.coordinator.onInsertImage = onInsertImage
        context.coordinator.onInsertGallery = onInsertGallery
        context.coordinator.onSearchLinks = onSearchLinks
        context.coordinator.onRequestMediaSizes = onRequestMediaSizes
        context.coordinator.onSelectionChanged = onSelectionChanged
        context.coordinator.onStatsChanged = onStatsChanged
        context.coordinator.onBlocksAtRisk = onBlocksAtRisk
        context.coordinator.onFootnotesChange = onFootnotesChange
        context.coordinator.onTriggerGenerate = onTriggerGenerate
        context.coordinator.onTriggerEvaluate = onTriggerEvaluate
        context.coordinator.onImagesPasted = onImagesPasted
        context.coordinator.onGalleryUpdateDropped = onGalleryUpdateDropped
        loadEditorHTML(in: webView)
        return webView
    }

    public func updateNSView(_ nsView: DroppableWebView, context: Context) {
        let ready = onEditorReady
        context.coordinator.onContentChange = onContentChange
        context.coordinator.onReady = { ready?() }
        if contentSyncPending {
            context.coordinator.syncAfterNextSetContent = true
            DispatchQueue.main.async { contentSyncPending = false }
        }
        context.coordinator.setContent(html, footnotes: footnotes)
        context.coordinator.onInsertImage = onInsertImage
        context.coordinator.onInsertGallery = onInsertGallery
        context.coordinator.onSearchLinks = onSearchLinks
        context.coordinator.onRequestMediaSizes = onRequestMediaSizes
        context.coordinator.onSelectionChanged = onSelectionChanged
        context.coordinator.onStatsChanged = onStatsChanged
        context.coordinator.onBlocksAtRisk = onBlocksAtRisk
        context.coordinator.onFootnotesChange = onFootnotesChange
        context.coordinator.onTriggerGenerate = onTriggerGenerate
        context.coordinator.onTriggerEvaluate = onTriggerEvaluate
        context.coordinator.onImagesPasted = onImagesPasted
        context.coordinator.onGalleryUpdateDropped = onGalleryUpdateDropped
        if context.coordinator.aiEnabled != aiEnabled {
            context.coordinator.aiEnabled = aiEnabled
            nsView.evaluateJavaScript("window.setAIEnabled?.(\(aiEnabled))", completionHandler: nil)
        }
        nsView.onImageFilesDropped = onImageFilesDropped
        nsView.onDropRejected = onDropRejected
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
