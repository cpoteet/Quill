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
    var onRequestMediaSizes: ((Int) async -> WPMedia?)?
    var onSelectionChanged: ((CGRect?) -> Void)?
    private var linkPopover: NSPopover?
    private var readyWatchdogItem: DispatchWorkItem?

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
        let width   = note.userInfo?["width"]   as? Int
        let height  = note.userInfo?["height"]  as? Int
        let mediaId = note.userInfo?["mediaId"] as? Int
        let alt     = note.userInfo?["alt"]     as? String
        insertImage(url: url, at: index, width: width, height: height, mediaId: mediaId, alt: alt)
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
                self.cancelReadyWatchdog()
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
        case "requestMediaSizes":
            if let body = message.body as? [String: Any],
               let mediaId = body["mediaId"] as? Int {
                DispatchQueue.main.async { self.handleRequestMediaSizes(mediaId: mediaId) }
            }
        case "selectionChanged":
            DispatchQueue.main.async {
                if let body = message.body as? [String: Any],
                   let rectMap = body["rect"] as? [String: Any],
                   let x = rectMap["x"] as? Double,
                   let y = rectMap["y"] as? Double,
                   let w = rectMap["width"] as? Double,
                   let h = rectMap["height"] as? Double {
                    self.onSelectionChanged?(CGRect(x: x, y: y, width: w, height: h))
                } else {
                    self.onSelectionChanged?(nil)
                }
            }
        case "checkSpelling":
            guard let text = message.body as? String else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                var misspelled = Set<String>()
                var offset = 0
                let tag = NSSpellChecker.uniqueSpellDocumentTag()
                while true {
                    let range = NSSpellChecker.shared.checkSpelling(
                        of: text, startingAt: offset,
                        language: nil, wrap: false,
                        inSpellDocumentWithTag: tag, wordCount: nil)
                    if range.length == 0 { break }
                    misspelled.insert((text as NSString).substring(with: range))
                    offset = range.upperBound
                }
                NSSpellChecker.shared.closeSpellDocument(withTag: tag)
                guard
                    let data = try? JSONSerialization.data(withJSONObject: Array(misspelled)),
                    let json = String(data: data, encoding: .utf8)
                else { return }
                DispatchQueue.main.async {
                    self.webView?.evaluateJavaScript(
                        "window.applySpellErrors(\(json))",
                        completionHandler: nil
                    )
                }
            }
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

    private func handleRequestMediaSizes(mediaId: Int) {
        guard let wv = webView, let fetch = onRequestMediaSizes else { return }
        Task {
            guard let media = await fetch(mediaId),
                  let sizes = media.mediaDetails?.sizes,
                  !sizes.isEmpty
            else {
                wv.evaluateJavaScript("setMediaSizes(\(mediaId), null)", completionHandler: nil)
                return
            }
            var dict: [String: Any] = [:]
            for (name, size) in sizes {
                dict[name] = ["url": size.sourceURL, "width": size.width, "height": size.height]
            }
            guard let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                  let jsonStr  = String(data: jsonData, encoding: .utf8)
            else { return }
            wv.evaluateJavaScript("setMediaSizes(\(mediaId), \(jsonStr))", completionHandler: nil)
        }
    }

    func insertImage(url: String, at index: Int, width: Int? = nil, height: Int? = nil, mediaId: Int? = nil, alt: String? = nil) {
        guard let wv = webView else { return }
        guard let jsonURL = try? JSONEncoder().encode(url),
            let urlStr = String(data: jsonURL, encoding: .utf8)
        else { return }
        let wStr   = width.map   { String($0) } ?? "null"
        let hStr   = height.map  { String($0) } ?? "null"
        let idStr  = mediaId.map { String($0) } ?? "null"
        let altStr: String
        if let alt, !alt.isEmpty,
           let jsonAlt = try? JSONEncoder().encode(alt),
           let s = String(data: jsonAlt, encoding: .utf8) {
            altStr = s
        } else {
            altStr = "null"
        }
        wv.evaluateJavaScript("insertImageAt(\(index), \(urlStr), \(wStr), \(hStr), \(idStr), \(altStr))", completionHandler: nil)
    }

    // WKNavigationDelegate
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyColorScheme()
        startReadyWatchdog()
    }

    /// The editor must never navigate away from the bundled `editor.html`. Only allow
    /// `file://` loads (the initial editor load, its local bundle, and any watchdog
    /// reload). Any other navigation — a clicked link, a `location` assignment, a
    /// meta-refresh in pasted content — would replace the editor and break it until
    /// relaunch, so cancel it. User-activated external links open in the default browser.
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if url.isFileURL {
            decisionHandler(.allow)
            return
        }
        if navigationAction.navigationType == .linkActivated {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    private func startReadyWatchdog() {
        cancelReadyWatchdog()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.isReady else { return }
            // editorReady never fired — local bundle may have failed to load. Reload and retry.
            self.isReady = false
            self.reloadEditor()
        }
        readyWatchdogItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: item)
    }

    private func cancelReadyWatchdog() {
        readyWatchdogItem?.cancel()
        readyWatchdogItem = nil
    }

    private func reloadEditor() {
        guard let wv = webView,
              let htmlURL = Bundle.main.url(forResource: "editor", withExtension: "html")
        else { return }
        wv.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
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
