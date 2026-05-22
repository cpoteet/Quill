import WebKit

public final class EditorCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var isReady: Bool = false
    var pendingHTML: String?
    var onContentChange: (String) -> Void
    var onReady: () -> Void
    weak var webView: WKWebView?

    var onInsertImageAt: ((Int) -> Void)?

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
              let index = note.userInfo?["index"] as? Int else { return }
        insertImage(url: url, at: index)
    }

    // WKScriptMessageHandler
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "contentChanged":
            if let html = message.body as? String {
                DispatchQueue.main.async { self.onContentChange(html) }
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
        default:
            break
        }
    }

    func insertImage(url: String, at index: Int) {
        guard let wv = webView else { return }
        let escaped = url.replacingOccurrences(of: "\"", with: "\\\"")
        wv.evaluateJavaScript("insertImageAt(\(index), \"\(escaped)\")", completionHandler: nil)
    }

    // WKNavigationDelegate
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyColorScheme()
    }

    func setContent(_ html: String) {
        guard let wv = webView else { return }
        if isReady {
            let escaped = html
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
            wv.evaluateJavaScript("setContent(`\(escaped)`)", completionHandler: nil)
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
    static let insertMediaURL = Notification.Name("WPWriter.insertMediaURL")
}
