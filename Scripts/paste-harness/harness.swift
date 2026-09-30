import AppKit
import WebKit

// Real-WebKit paste harness; usage and case format in Scripts/fixtures/paste/README.md.

let args = CommandLine.arguments
let editorURL = URL(fileURLWithPath: args[1])
let cases = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as! [[String: Any]]
let outURL = URL(fileURLWithPath: args[3])

final class Harness: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var editor: WKWebView!
    var source: WKWebView!
    var window: NSWindow!
    var sourceWindow: NSWindow!
    var results: [[String: Any]] = []
    var index = 0
    var sourceLoaded: (() -> Void)?

    func start() {
        let config = WKWebViewConfiguration()
        for name in ["contentChanged", "editorReady", "insertImage", "insertGallery",
                     "showLinkPicker", "requestMediaSizes", "selectionChanged", "statsChanged",
                     "blocksAtRisk", "footnotesChanged", "checkSpelling", "triggerGenerate",
                     "triggerEvaluate", "openLink", "uploadPastedImages"] {
            config.userContentController.add(self, name: name)
        }
        editor = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 800), configuration: config)
        editor.navigationDelegate = self
        window = NSWindow(contentRect: NSRect(x: -12000, y: -12000, width: 1000, height: 800),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = editor

        source = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
        source.navigationDelegate = self
        sourceWindow = NSWindow(contentRect: NSRect(x: -12000, y: -10000, width: 1000, height: 800),
                                styleMask: [.titled], backing: .buffered, defer: false)
        sourceWindow.contentView = source
        sourceWindow.orderBack(nil)
        window.orderBack(nil)

        editor.loadFileURL(editorURL, allowingReadAccessTo: editorURL.deletingLastPathComponent())
    }

    var uploadMessages: [[String: Any]] = []
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "uploadPastedImages", let body = message.body as? [String: Any],
              let images = body["images"] as? [[String: Any]] else { return }
        for image in images {
            let url = image["dataURL"] as? String ?? ""
            uploadMessages.append(["token": image["token"] ?? NSNull(), "prefix": String(url.prefix(30)), "bytes": url.count])
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === editor {
            waitForEditor(0)
        } else {
            sourceLoaded?()
        }
    }

    func waitForEditor(_ attempt: Int) {
        if attempt > 200 { fatal("editor never ready") }
        editor.evaluateJavaScript("!!window._tiptapEditor") { v, _ in
            if v as? Bool == true {
                let install = """
                document.addEventListener('paste', e => {
                  const d = e.clipboardData
                  window.__lastPaste = { types: Array.from(d.types), html: d.getData('text/html'), text: d.getData('text/plain') }
                }, true); true
                """
                self.editor.evaluateJavaScript(install) { _, _ in self.next() }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.waitForEditor(attempt + 1) }
            }
        }
    }

    func next() {
        guard index < cases.count else { finish(); return }
        let c = cases[index]
        index += 1
        let mode = c["mode"] as! String
        let pb = NSPasteboard.general
        let before = pb.changeCount
        switch mode {
        case "web":
            let css = (c["css"] as? String) ?? ""
            let page = "<!doctype html><html><head><meta charset=utf-8><style>\(css)</style></head><body>\(c["html"] as! String)</body></html>"
            sourceLoaded = {
                self.sourceLoaded = nil
                let sel = (c["select"] as? String) ?? "body"
                let js = "(() => { const r = document.createRange(); r.selectNodeContents(document.querySelector('\(sel)')); const s = getSelection(); s.removeAllRanges(); s.addRange(r); return true })()"
                self.source.evaluateJavaScript(js) { _, _ in
                    self.sourceWindow.makeFirstResponder(self.source)
                    self.source.perform(#selector(NSText.copy(_:)), with: nil)
                    self.waitForPasteboard(before, 0) { self.pasteInto(c) }
                }
            }
            source.loadHTMLString(page, baseURL: URL(string: "https://example.com/post/"))
            return
        case "url":
            sourceLoaded = {
                self.sourceLoaded = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    let sel = (c["select"] as? String) ?? "body"
                    let js = "(() => { const el = document.querySelector('\(sel)') || document.body; const r = document.createRange(); r.selectNodeContents(el); const s = getSelection(); s.removeAllRanges(); s.addRange(r); return !!el })()"
                    self.source.evaluateJavaScript(js) { _, _ in
                        self.sourceWindow.makeFirstResponder(self.source)
                        self.source.perform(#selector(NSText.copy(_:)), with: nil)
                        self.waitForPasteboard(before, 0) { self.pasteInto(c) }
                    }
                }
            }
            source.load(URLRequest(url: URL(string: c["url"] as! String)!))
            return
        case "html":
            pb.clearContents()
            pb.setString(c["html"] as! String, forType: .html)
            pb.setString((c["text"] as? String) ?? plainText(c["html"] as! String), forType: .string)
        case "rtf":
            pb.clearContents()
            let data = (c["html"] as! String).data(using: .utf8)!
            let attr = try! NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
            let rtf = try! attr.data(from: NSRange(location: 0, length: attr.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            pb.setData(rtf, forType: .rtf)
            pb.setString(attr.string, forType: .string)
        case "snapshot":
            let dir = URL(fileURLWithPath: c["dir"] as! String)
            let order = try! JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("types.json"))) as! [String]
            pb.clearContents()
            pb.declareTypes(order.map { NSPasteboard.PasteboardType($0) }, owner: nil)
            for (i, t) in order.enumerated() {
                pb.setData(try! Data(contentsOf: dir.appendingPathComponent(String(i))), forType: NSPasteboard.PasteboardType(t))
            }
        case "png":
            pb.clearContents()
            let img = NSImage(size: NSSize(width: 8, height: 8))
            img.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 8, height: 8).fill(); img.unlockFocus()
            let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
            pb.setData(rep.representation(using: .png, properties: [:])!, forType: .png)
        case "file":
            pb.clearContents()
            let url = URL(fileURLWithPath: c["text"] as! String)
            pb.writeObjects([url as NSURL])
        case "plain":
            pb.clearContents()
            pb.setString(c["text"] as! String, forType: .string)
        case "quill":
            let setup = """
            window.setContent(\(jsString(c["html"] as! String)));
            window.__baseline = extractFootnotes(toWordPressHTML(_tiptapEditor.getHTML())).content;
            _tiptapEditor.commands.focus();
            (\((c["select"] as? String) ?? "() => _tiptapEditor.commands.selectAll()"))(); true
            """
            editor.evaluateJavaScript(setup) { _, err in
                if let err { print("setup error \(err)") }
                self.window.makeFirstResponder(self.editor)
                self.editor.perform(#selector(NSText.copy(_:)), with: nil)
                self.waitForPasteboard(before, 0) { self.pasteInto(c) }
            }
            return
        default: fatal("bad mode \(mode)")
        }
        pasteInto(c)
    }

    func waitForPasteboard(_ before: Int, _ attempt: Int, then: @escaping () -> Void) {
        if NSPasteboard.general.changeCount != before { then(); return }
        if attempt > 60 { print("  copy never reached the pasteboard"); then(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.waitForPasteboard(before, attempt + 1, then: then) }
    }

    func pasteInto(_ c: [String: Any]) {
        let types = NSPasteboard.general.types?.map(\.rawValue) ?? []
        let target = (c["target"] as? String) ?? "<!-- wp:paragraph -->\n<p></p>\n<!-- /wp:paragraph -->"
        uploadMessages = []
        let prep = "window.__lastPaste = null; if (\(c["mode"] as! String == "quill" ? "false" : "true")) window.__baseline = null; window.setContent(\(jsString(target))); _tiptapEditor.commands.focus('end'); true"
        editor.evaluateJavaScript(prep) { _, _ in
            self.window.makeFirstResponder(self.editor)
            self.editor.perform(#selector(NSText.paste(_:)), with: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                // Stand in for Swift's upload: answer every token with a hosted URL.
                let resolves = self.uploadMessages.enumerated().compactMap { i, m -> String? in
                    guard let token = m["token"] as? String else { return nil }
                    return "window.resolvePastedImage('\(token)', 'https://example.com/wp-content/uploads/pasted-\(i).png', \(9000 + i));"
                }.joined()
                self.editor.evaluateJavaScript(resolves + "true") { _, _ in
                let read = """
                JSON.stringify({
                  paste: window.__lastPaste,
                  baseline: window.__baseline || null,
                  saved: extractFootnotes(toWordPressHTML(_tiptapEditor.getHTML())).content,
                  doc: _tiptapEditor.getJSON()
                })
                """
                self.editor.evaluateJavaScript(read) { v, err in
                    var row: [String: Any] = ["name": c["name"] as! String, "mode": c["mode"] as! String, "pasteboardTypes": types, "uploads": self.uploadMessages]
                    if let s = v as? String, let d = s.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                        row.merge(o) { a, _ in a }
                    } else {
                        row["error"] = err?.localizedDescription ?? "no result"
                    }
                    self.results.append(row)
                    print("  done \(c["name"] as! String)")
                    self.next()
                }
                }
            }
        }
    }

    func finish() {
        let data = try! JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: outURL)
        print("wrote \(results.count) results")
        exit(0)
    }

    func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }

    func jsString(_ s: String) -> String {
        let d = try! JSONSerialization.data(withJSONObject: [s])
        return String(String(data: d, encoding: .utf8)!.dropFirst().dropLast())
    }

    func fatal(_ m: String) -> Never { print("harness: " + m); exit(2) }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let h = Harness()
h.start()
app.run()
