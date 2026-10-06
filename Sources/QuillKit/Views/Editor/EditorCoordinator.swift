import AppKit
import SwiftUI
import WebKit

// Footnote bodies live in post meta, so the HTML alone does not identify a post.
struct EditorPushState {
    private var html: String = ""
    private var footnotes: String = ""

    func shouldPush(html candidate: String, footnotes notes: String?) -> Bool {
        candidate != html || (notes ?? "") != footnotes
    }

    mutating func record(html candidate: String, footnotes notes: String?) {
        html = candidate
        footnotes = notes ?? ""
    }

    mutating func recordHTML(_ candidate: String) {
        html = candidate
    }

    mutating func recordFootnotes(_ notes: String) {
        footnotes = notes
    }
}

/// A pasted image the site does not host yet; a `token` means it is already in the document.
public struct PastedImage: Sendable {
    public let token: String?
    public let data: Data
    public let mimeType: String

    static func decode(_ entry: [String: Any]) -> PastedImage? {
        guard
            let dataURL = entry["dataURL"] as? String,
            let comma = dataURL.firstIndex(of: ","),
            dataURL.hasPrefix("data:image/")
        else { return nil }
        let header = dataURL[dataURL.index(dataURL.startIndex, offsetBy: 5)..<comma]
        guard header.hasSuffix(";base64"),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]))
        else { return nil }
        let mimeType = String(header.dropLast(";base64".count))
        return PastedImage(token: entry["token"] as? String, data: data, mimeType: mimeType)
    }

    /// Frees the editor to send these images again on a later paste; a no-op for any already resolved.
    static func forgetScript(_ tokens: [String]) -> String? {
        guard !tokens.isEmpty,
              let data = try? JSONEncoder().encode(tokens),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return "\(json).forEach(t => window.forgetPastedImage?.(t))"
    }
}

public final class EditorCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var isReady: Bool = false
    var pendingHTML: String?
    var pendingFootnotes: String?
    private var pushState = EditorPushState()
    // Content messages that arrive while a setContent is unanswered were posted by the replaced document.
    private var unansweredSetContents = 0
    var onContentChange: (String) -> Void
    var onReady: () -> Void
    weak var webView: WKWebView?
    var onInsertImage: (() -> Void)?
    var onInsertGallery: ((GalleryEdit?) -> Void)?
    var onCustomHTML: ((CustomHTMLRequest) -> Void)?
    var onSearchLinks: ((String) async throws -> [LinkSearchResult])?
    var onRequestMediaSizes: ((Int) async -> WPMedia?)?
    var onSelectionChanged: ((CGRect?) -> Void)?
    var onStatsChanged: ((Int, Int) -> Void)?
    var onBlocksAtRisk: (([String]) -> Void)?
    var onFootnotesChange: ((String) -> Void)?
    var onTriggerGenerate: (() -> Void)?
    var onTriggerEvaluate: (() -> Void)?
    var onImagesPasted: (([PastedImage]) -> Void)?
    var onGalleryUpdateDropped: (() -> Void)?
    var aiEnabled: Bool = false
    var syncAfterNextSetContent: Bool = false
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInsertGallery(_:)),
            name: .insertGalleryData,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInsertCustomHTML(_:)),
            name: .insertCustomHTML,
            object: nil
        )
    }

    @objc private func handleInsertMedia(_ note: Notification) {
        guard let url = note.userInfo?["url"] as? String else { return }
        let mediaId = note.userInfo?["mediaId"] as? Int
        let alt     = note.userInfo?["alt"]     as? String
        insertImage(url: url, mediaId: mediaId, alt: alt)
    }

    @objc private func handleInsertGallery(_ note: Notification) {
        guard let payload = note.userInfo as? [String: Any], payload["images"] is [[String: Any]] else { return }
        insertGallery(payload: payload)
    }

    @objc private func handleInsertCustomHTML(_ note: Notification) {
        guard let html = note.userInfo?["html"] as? String, let replace = note.userInfo?["replace"] as? Bool else { return }
        insertCustomHTML(html: html, replace: replace)
    }

    // WKScriptMessageHandler
    public func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case "contentChanged":
            if let html = message.body as? String, unansweredSetContents == 0 {
                DispatchQueue.main.async {
                    self.pushState.recordHTML(html)
                    self.onContentChange(html)
                }
            }
        case "editorReady":
            DispatchQueue.main.async {
                self.cancelReadyWatchdog()
                self.isReady = true
                if let html = self.pendingHTML {
                    self.setContent(html, footnotes: self.pendingFootnotes)
                    self.pendingHTML = nil
                    self.pendingFootnotes = nil
                }
                self.onReady()
            }
        case "insertImage":
            DispatchQueue.main.async { self.onInsertImage?() }
        case "insertGallery":
            let edit = GalleryEdit(body: message.body)
            DispatchQueue.main.async { self.onInsertGallery?(edit) }
        case "customHTML":
            guard let request = CustomHTMLRequest(body: message.body) else { return }
            DispatchQueue.main.async { self.onCustomHTML?(request) }
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
        case "statsChanged":
            if let body = message.body as? [String: Any],
               let words = body["words"] as? Int,
               let characters = body["characters"] as? Int {
                DispatchQueue.main.async { self.onStatsChanged?(words, characters) }
            }
        case "footnotesChanged":
            if let json = message.body as? String, unansweredSetContents == 0 {
                DispatchQueue.main.async {
                    self.pushState.recordFootnotes(json)
                    self.onFootnotesChange?(json)
                }
            }
        case "blocksAtRisk":
            if let body = message.body as? [String: Any],
               let names = body["names"] as? [String] {
                DispatchQueue.main.async { self.onBlocksAtRisk?(names) }
            }
        case "checkSpelling":
            guard let text = message.body as? String else { return }
            Self.misspelledWords(in: text) { misspelled in
                guard
                    let data = try? JSONSerialization.data(withJSONObject: misspelled),
                    let json = String(data: data, encoding: .utf8)
                else { return }
                self.webView?.evaluateJavaScript(
                    "window.applySpellErrors(\(json))",
                    completionHandler: nil
                )
            }
        case "triggerGenerate":
            DispatchQueue.main.async { self.onTriggerGenerate?() }
        case "triggerEvaluate":
            DispatchQueue.main.async { self.onTriggerEvaluate?() }
        case "uploadPastedImages":
            guard let bodies = (message.body as? [String: Any])?["images"] as? [[String: Any]] else { return }
            let entries = bodies.map { $0.compactMapValues { $0 as? String } }
            // Base64 decoding a screenshot is real work; keep it off the main thread.
            DispatchQueue.global(qos: .userInitiated).async {
                var images: [PastedImage] = []
                var rejected: [String] = []
                for entry in entries {
                    if let image = PastedImage.decode(entry) {
                        images.append(image)
                    } else if let token = entry["token"] {
                        rejected.append(token)
                    }
                }
                DispatchQueue.main.async {
                    if let script = PastedImage.forgetScript(rejected) {
                        self.webView?.evaluateJavaScript(script, completionHandler: nil)
                    }
                    if !images.isEmpty { self.onImagesPasted?(images) }
                }
            }
        case "openLink":
            if let urlString = message.body as? String,
               let url = URL(string: urlString),
               EditorCoordinator.isAllowedExternalURL(url) {
                DispatchQueue.main.async { NSWorkspace.shared.open(url) }
            }
        default:
            break
        }
    }

    // NSSpellChecker calls back on its own queue; a main-actor closure here traps at entry.
    static func misspelledWords(in text: String, completion: @escaping @MainActor ([String]) -> Void) {
        let tag = NSSpellChecker.uniqueSpellDocumentTag()
        NSSpellChecker.shared.requestChecking(
            of: text,
            range: NSRange(text.startIndex..., in: text),
            types: NSTextCheckingResult.CheckingType.spelling.rawValue,
            options: nil,
            inSpellDocumentWithTag: tag
        ) { @Sendable _, results, _, _ in
            NSSpellChecker.shared.closeSpellDocument(withTag: tag)
            let words = results.map { (text as NSString).substring(with: $0.range) }
            DispatchQueue.main.async { completion(words) }
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

    /// Builds the size-name → {url,width,height} dict sent to `setMediaSizes` in the JS editor.
    /// WordPress's `media_details.sizes` frequently omits a "full" entry (the full-resolution
    /// URL lives at the top-level `source_url` instead) — mirrors the fallback
    /// `WPMedia.sizedURL(for:)` already applies for the same quirk. Returns nil when there is no
    /// usable source URL at all.
    nonisolated static func mediaSizesDict(for media: WPMedia) -> [String: [String: Any]]? {
        guard !media.sourceURL.isEmpty else { return nil }
        var dict: [String: [String: Any]] = [:]
        for (name, size) in media.mediaDetails?.sizes ?? [:] {
            dict[name] = ["url": size.sourceURL, "width": size.width, "height": size.height]
        }
        if dict["full"] == nil {
            dict["full"] = [
                "url": media.sourceURL,
                "width": media.mediaDetails?.width as Any? ?? NSNull(),
                "height": media.mediaDetails?.height as Any? ?? NSNull(),
            ]
        }
        return dict
    }

    private func handleRequestMediaSizes(mediaId: Int) {
        guard let wv = webView, let fetch = onRequestMediaSizes else { return }
        Task {
            guard let media = await fetch(mediaId),
                  let dict = Self.mediaSizesDict(for: media)
            else {
                wv.evaluateJavaScript("setMediaSizes(\(mediaId), null)", completionHandler: nil)
                return
            }
            guard let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                  let jsonStr  = String(data: jsonData, encoding: .utf8)
            else { return }
            wv.evaluateJavaScript("setMediaSizes(\(mediaId), \(jsonStr))", completionHandler: nil)
        }
    }

    func insertImage(url: String, mediaId: Int? = nil, alt: String? = nil) {
        guard let wv = webView else { return }
        guard let jsonURL = try? JSONEncoder().encode(url),
            let urlStr = String(data: jsonURL, encoding: .utf8)
        else { return }
        let idStr  = mediaId.map { String($0) } ?? "null"
        let altStr: String
        if let alt, !alt.isEmpty,
           let jsonAlt = try? JSONEncoder().encode(alt),
           let s = String(data: jsonAlt, encoding: .utf8) {
            altStr = s
        } else {
            altStr = "null"
        }
        wv.evaluateJavaScript("insertImage(\(urlStr), \(idStr), \(altStr))", completionHandler: nil)
    }

    func insertGallery(payload: [String: Any]) {
        guard let wv = webView else { return }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: jsonData, encoding: .utf8),
              let escapedData = try? JSONEncoder().encode(jsonStr),
              let escapedStr = String(data: escapedData, encoding: .utf8)
        else { return }
        wv.evaluateJavaScript("insertGallery(\(escapedStr))") { result, _ in
            if result as? String == "gallery-gone" { self.onGalleryUpdateDropped?() }
        }
    }

    static func customHTMLScript(html: String, replace: Bool) -> String? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: ["html": html, "replace": replace] as [String: Any]),
              let jsonStr = String(data: jsonData, encoding: .utf8),
              let escapedData = try? JSONEncoder().encode(jsonStr),
              let escapedStr = String(data: escapedData, encoding: .utf8)
        else { return nil }
        return "insertCustomHTML(\(escapedStr))"
    }

    func insertCustomHTML(html: String, replace: Bool) {
        guard let wv = webView, let script = Self.customHTMLScript(html: html, replace: replace) else { return }
        wv.evaluateJavaScript(script, completionHandler: nil)
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
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if let editorURL = Bundle.main.url(forResource: "editor", withExtension: "html"),
           Self.isEditorPage(url, editorURL: editorURL) {
            decisionHandler(.allow)
            return
        }
        if navigationAction.navigationType == .linkActivated,
           EditorCoordinator.isAllowedExternalURL(url) {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    // Any other file: URL, a local page or a path out of the bundle, is cancelled.
    nonisolated static func isEditorPage(_ url: URL, editorURL: URL) -> Bool {
        url.isFileURL && url.standardizedFileURL.path == editorURL.standardizedFileURL.path
    }

    /// Returns true for URL schemes that are safe to open in the system browser.
    /// Restricts to http, https, and mailto — blocks file://, javascript:, ftp:, etc.
    nonisolated static func isAllowedExternalURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "mailto"
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

    func setContent(_ html: String, footnotes: String?) {
        guard let wv = webView else { return }
        if isReady {
            let needsSync = syncAfterNextSetContent
            guard pushState.shouldPush(html: html, footnotes: footnotes) else {
                if needsSync {
                    syncAfterNextSetContent = false
                    wv.evaluateJavaScript("window.syncContentToSwift?.()", completionHandler: nil)
                }
                return
            }
            syncAfterNextSetContent = false
            pushState.record(html: html, footnotes: footnotes)
            guard let jsonHTML = try? JSONEncoder().encode(html),
                let htmlStr = String(data: jsonHTML, encoding: .utf8),
                let jsonFN = try? JSONEncoder().encode(footnotes ?? ""),
                let fnStr = String(data: jsonFN, encoding: .utf8)
            else { return }
            unansweredSetContents += 1
            wv.evaluateJavaScript("setContent(\(htmlStr), \(fnStr))") { _, _ in
                self.unansweredSetContents -= 1
            }
            if needsSync {
                wv.evaluateJavaScript("window.syncContentToSwift?.()", completionHandler: nil)
            }
        } else {
            pendingHTML = html
            pendingFootnotes = footnotes
        }
    }

    /// Brings Swift's copy of the content up to date with typing the editor has not posted yet.
    @MainActor func flushPendingContent() async {
        guard isReady, let wv = webView else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            wv.evaluateJavaScript("window.flushContent?.() ?? null") { result, _ in
                // Queued behind any content message already received, so an older one cannot land after this.
                DispatchQueue.main.async {
                    if let snapshot = result as? [String: Any],
                       let html = snapshot["html"] as? String,
                       let footnotes = snapshot["footnotes"] as? String {
                        self.pushState.recordHTML(html)
                        self.pushState.recordFootnotes(footnotes)
                        self.onContentChange(html)
                        self.onFootnotesChange?(footnotes)
                    }
                    continuation.resume()
                }
            }
        }
    }

    func applyColorScheme() {
        guard let wv = webView else { return }
        let isDark = wv.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        wv.evaluateJavaScript("setDarkMode(\(isDark))", completionHandler: nil)
        wv.evaluateJavaScript("window.setAIEnabled?.(\(aiEnabled))", completionHandler: nil)
    }
}

extension Notification.Name {
    static let insertMediaURL = Notification.Name("Quill.insertMediaURL")
    static let insertGalleryData = Notification.Name("Quill.insertGalleryData")
    static let insertCustomHTML = Notification.Name("Quill.insertCustomHTML")
}
