import AppKit
import WebKit

/// Runs the jsdom fixture corpus inside the real WKWebView, so a WebKit/jsdom
/// divergence fails somewhere other than a user's post. See docs/testing-plan.md.
public enum FixtureCheck {
    public static func run(directory: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let runner = Runner(directory: directory)
        runner.start()
        app.run()
    }
}

private final class Runner: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private let directory: String
    private var webView: WKWebView!
    private var window: NSWindow!

    init(directory: String) {
        self.directory = directory
    }

    func start() {
        let config = WKWebViewConfiguration()
        for name in ["contentChanged", "editorReady", "insertImage", "insertGallery",
                     "showLinkPicker", "requestMediaSizes", "selectionChanged", "statsChanged",
                     "blocksAtRisk", "footnotesChanged", "checkSpelling", "triggerGenerate",
                     "triggerEvaluate", "openLink"] {
            config.userContentController.add(self, name: name)
        }
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: config)
        webView.navigationDelegate = self

        window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1200, height: 900),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = webView
        window.orderBack(nil)

        guard let htmlURL = Bundle.main.url(forResource: "editor", withExtension: "html") else {
            fail("editor.html is not in the bundle")
        }
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {}

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        waitForEditor(attempt: 0)
    }

    private func waitForEditor(attempt: Int) {
        if attempt > 200 { fail("the editor never became ready") }
        webView.evaluateJavaScript("!!window._tiptapEditor && !!window.__runFixtureCorpus") { value, _ in
            if value as? Bool == true {
                self.runCorpus()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.waitForEditor(attempt: attempt + 1) }
            }
        }
    }

    private func runCorpus() {
        let dir = URL(fileURLWithPath: directory)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [])
            .filter { $0.hasPrefix("settings-") && $0.hasSuffix(".html") }
            .sorted()
        guard !names.isEmpty else { fail("no settings-*.html fixtures in \(directory)") }

        let fixtures: [[String: String]] = names.compactMap { name in
            guard let source = try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) else { return nil }
            return ["name": name, "source": source]
        }
        guard let payload = try? JSONSerialization.data(withJSONObject: fixtures),
              let json = String(data: payload, encoding: .utf8) else { fail("could not encode the fixtures") }

        let script = "JSON.stringify(window.__runFixtureCorpus(\(jsStringLiteral(json))))"
        webView.evaluateJavaScript(script) { value, error in
            if let error { self.fail("the corpus threw: \(error.localizedDescription)") }
            guard let text = value as? String,
                  let data = text.data(using: .utf8),
                  let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { self.fail("the corpus returned nothing usable") }
            self.report(rows, in: dir)
        }
    }

    private func report(_ rows: [[String: Any]], in dir: URL) {
        var failures = 0
        print("WebKit fixture corpus — \(rows.count) fixtures\n")
        for row in rows {
            let name = row["name"] as? String ?? "?"
            let checks = [("untouched", row["untouched"] as? Bool ?? false),
                          ("identical", row["identical"] as? Bool ?? false),
                          ("idempotent", row["idempotent"] as? Bool ?? false)]
            let bad = checks.filter { !$0.1 }.map(\.0)
            if bad.isEmpty {
                print("  ok    \(name)")
            } else {
                failures += 1
                print("  FAIL  \(name) — \(bad.joined(separator: ", "))")
                if let saved = row["saved"] as? String,
                   let source = try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) {
                    print(firstDifference(source, saved).split(separator: "\n").map { "          \($0)" }.joined(separator: "\n"))
                }
            }
        }
        print("\n\(rows.count - failures)/\(rows.count) passed")
        exit(failures == 0 ? 0 : 1)
    }

    private func firstDifference(_ expected: String, _ actual: String) -> String {
        let e = Array(expected), a = Array(actual)
        var i = 0
        while i < e.count, i < a.count, e[i] == a[i] { i += 1 }
        let from = max(0, i - 40)
        return "expected: …\(String(e[from..<min(e.count, i + 60)]))\n  actual: …\(String(a[from..<min(a.count, i + 60)]))"
    }

    private func jsStringLiteral(_ value: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [value])
        let array = String(data: data, encoding: .utf8)!
        return String(array.dropFirst().dropLast())
    }

    private func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data(("fixture check: " + message + "\n").utf8))
        exit(2)
    }
}
