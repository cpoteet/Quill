import AppKit
import SwiftUI
import WebKit

public final class EditorCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var isReady: Bool = false
    var pendingHTML: String?
    private var lastPushedHTML: String = ""
    var onContentChange: (String) -> Void
    var onReady: () -> Void
    weak var webView: WKWebView?
    var onInsertImageAt: ((Int) -> Void)?
    var onSearchLinks: ((String) async throws -> [LinkSearchResult])?
    private var linkPopover: NSPopover?

    init(onContentChange: @escaping (String) -> Void, onReady: @escaping () -> Void) {
        self.onContentChange = onContentChange
        self.onReady = onReady
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInsertMedia(_:)),
            name: .insertMediaURL,
            object: nil
        )
    }

    @objc private func handleInsertMedia(_ note: Notification) {
        guard let url = note.userInfo?["url"] as? String,
            let index = note.userInfo?["index"] as? Int
        else { return }
        insertImage(url: url, at: index)
    }

    // WKScriptMessageHandler
    public func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case "contentChanged":
            if let html = message.body as? String {
                DispatchQueue.main.async {
                    self.lastPushedHTML = html
                    self.onContentChange(html)
                }
            }
        case "editorReady":
            DispatchQueue.main.async {
                self.isReady = true
                if let html = self.pendingHTML {
                    self.setContent(html)
                    self.pendingHTML = nil
                }
                self.onReady()
            }
        case "insertImageAtIndex":
            if let index = message.body as? Int {
                DispatchQueue.main.async { self.onInsertImageAt?(index) }
            }
        case "showLinkPicker":
            guard
                let body    = message.body as? [String: Any],
                let href    = body["href"] as? String,
                let rectMap = body["rect"] as? [String: Any],
                let x = rectMap["x"] as? Double,
                let y = rectMap["y"] as? Double,
                let w = rectMap["width"] as? Double,
                let h = rectMap["height"] as? Double,
                let wv = webView
            else { return }
            DispatchQueue.main.async { self.showLinkPicker(href: href, jsRect: (x, y, w, h), in: wv) }
        default:
            break
        }
    }

    private func showLinkPicker(href: String, jsRect: (x: Double, y: Double, w: Double, h: Double), in wv: WKWebView) {
        linkPopover?.close()

        // WKWebView is flipped (isFlipped == true): origin is top-left, Y increases downward —
        // same as JS getBoundingClientRect(), so no coordinate conversion is needed.
        let nsRect = NSRect(x: jsRect.x, y: jsRect.y, width: jsRect.w, height: jsRect.h)

        let model = LinkPickerModel(
            currentHref: href,
            onApply: { [weak self] url in
                self?.linkPopover?.close()
                guard
                    let jsonData = try? JSONEncoder().encode(url),
                    let jsonStr  = String(data: jsonData, encoding: .utf8)
                else { return }
                self?.webView?.evaluateJavaScript("applyLink(\(jsonStr))", completionHandler: nil)
            },
            onRemove: { [weak self] in
                self?.linkPopover?.close()
                self?.webView?.evaluateJavaScript("removeLink()", completionHandler: nil)
            },
            onSearch: { [weak self] query in
                guard let search = self?.onSearchLinks else { return [] }
                return try await search(query)
            }
        )

        let hosting = NSHostingController(rootView: LinkPickerView(model: model))
        hosting.sizingOptions = .preferredContentSize  // update size dynamically as results appear
        let popover = NSPopover()
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.show(relativeTo: nsRect, of: wv, preferredEdge: .maxY)
        linkPopover = popover
    }

    func insertImage(url: String, at index: Int) {
        guard let wv = webView else { return }
        guard let jsonURL = try? JSONEncoder().encode(url),
            let urlStr = String(data: jsonURL, encoding: .utf8)
        else { return }
        wv.evaluateJavaScript("insertImageAt(\(index), \(urlStr))", completionHandler: nil)
    }

    // WKNavigationDelegate
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyColorScheme()
    }

    func setContent(_ html: String) {
        guard let wv = webView else { return }
        if isReady {
            guard html != lastPushedHTML else { return }
            lastPushedHTML = html
            guard let jsonHTML = try? JSONEncoder().encode(html),
                let htmlStr = String(data: jsonHTML, encoding: .utf8)
            else { return }
            wv.evaluateJavaScript("setContent(\(htmlStr))", completionHandler: nil)
        } else {
            pendingHTML = html
        }
    }

    func applyColorScheme() {
        guard let wv = webView else { return }
        let isDark = wv.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        wv.evaluateJavaScript("setDarkMode(\(isDark))", completionHandler: nil)
    }
}

extension Notification.Name {
    static let insertMediaURL = Notification.Name("Quill.insertMediaURL")
}
