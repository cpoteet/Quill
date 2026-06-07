import AppKit
import WebKit

/// WKWebView subclass that intercepts image file drops from Finder,
/// forwards the file URLs to Swift for upload, and shows a visual
/// drop overlay inside the web content while dragging.
public final class DroppableWebView: WKWebView {
    public var onImageFilesDropped: (([URL]) -> Void)?
    public var onAIOperation: ((AIWritingOperation) -> Void)?
    public var aiEnabled: Bool = false
    public var hasTextSelection: Bool = false

    // Covers the common image UTIs; "public.image" catches anything else
    private static let imageUTIs: [String] = [
        "public.png", "public.jpeg", "com.compuserve.gif",
        "org.webmproject.webp", "public.heic", "public.tiff", "public.image",
    ]

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    // MARK: - NSDraggingDestination

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasImageFiles(sender) else { return super.draggingEntered(sender) }
        showOverlay(true)
        return .copy
    }

    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasImageFiles(sender) else { return super.draggingUpdated(sender) }
        return .copy
    }

    public override func draggingExited(_ sender: NSDraggingInfo?) {
        showOverlay(false)
        super.draggingExited(sender)
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        showOverlay(false)
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingContentsConformToTypes: Self.imageUTIs
        ]
        guard
            let urls = sender.draggingPasteboard
                .readObjects(forClasses: [NSURL.self], options: options) as? [URL],
            !urls.isEmpty
        else { return super.performDragOperation(sender) }
        onImageFilesDropped?(urls)
        return true
    }

    // MARK: - Context menu

    // rightMouseDown pops up our own menu directly so that
    // allowsContextMenuPlugIns = false is respected. WebKit's own menu-show
    // path (via super.rightMouseDown) does not honour that flag, which caused
    // AutoFill/Services to leak through.
    public override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        evaluateJavaScript("window.spellContextAtPoint?.(\(point.x), \(point.y))") { [weak self] result, _ in
            guard let self else { return }
            NSMenu.popUpContextMenu(self.buildContextMenu(spellContext: SpellContext(result)), with: event, for: self)
        }
    }

    // willOpenMenu is kept as a fallback for non-rightMouseDown code paths
    // (e.g. accessibility). allowsContextMenuPlugIns = false is set here too.
    public override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.allowsContextMenuPlugIns = false
    }

    private func buildContextMenu(spellContext: SpellContext? = nil) -> NSMenu {
        let menu = NSMenu()
        menu.allowsContextMenuPlugIns = false

        if let sc = spellContext {
            let suggestions = spellingSuggestions(for: sc.word)
            for suggestion in suggestions {
                let item = NSMenuItem(title: suggestion, action: #selector(applySpellingSuggestion(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = SpellReplacement(from: sc.from, to: sc.to, suggestion: suggestion)
                menu.addItem(item)
            }
            if !suggestions.isEmpty { menu.addItem(.separator()) }
        }

        menu.items += [
            NSMenuItem(title: "Cut",   action: NSSelectorFromString("cut:"),   keyEquivalent: ""),
            NSMenuItem(title: "Copy",  action: NSSelectorFromString("copy:"),  keyEquivalent: ""),
            NSMenuItem(title: "Paste", action: NSSelectorFromString("paste:"), keyEquivalent: ""),
        ]
        if aiEnabled && hasTextSelection {
            menu.addItem(.separator())
            let aiActions: [(String, Selector)] = [
                ("Make Longer",  #selector(aiMakeLonger)),
                ("Make Shorter", #selector(aiMakeShorter)),
                ("Convert to Table", #selector(aiConvertToTable)),
                ("Convert to List",  #selector(aiConvertToList)),
            ]
            for (title, sel) in aiActions {
                let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
                item.target = self
                menu.addItem(item)
            }
        }
        return menu
    }

    // MARK: - AI menu actions

    @objc private func aiMakeLonger()      { onAIOperation?(.makeLonger) }
    @objc private func aiMakeShorter()     { onAIOperation?(.makeShorter) }
    @objc private func aiConvertToTable()  { onAIOperation?(.convertToTable) }
    @objc private func aiConvertToList()   { onAIOperation?(.convertToList) }
    @objc private func applySpellingSuggestion(_ sender: NSMenuItem) {
        guard let r = sender.representedObject as? SpellReplacement,
              let json = String(data: (try? JSONEncoder().encode(r.suggestion)) ?? Data(), encoding: .utf8)
        else { return }
        evaluateJavaScript("window.replaceSpellError?.(\(r.from), \(r.to), \(json))", completionHandler: nil)
    }

    // MARK: - Helpers

    private func spellingSuggestions(for word: String) -> [String] {
        let tag = NSSpellChecker.uniqueSpellDocumentTag()
        defer { NSSpellChecker.shared.closeSpellDocument(withTag: tag) }
        return Array(
            (NSSpellChecker.shared.guesses(
                forWordRange: NSRange(location: 0, length: (word as NSString).length),
                in: word, language: nil,
                inSpellDocumentWithTag: tag
            ) ?? []).prefix(8)
        )
    }

    private func hasImageFiles(_ sender: NSDraggingInfo) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingContentsConformToTypes: Self.imageUTIs
        ]
        return sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: options)
    }

    private func showOverlay(_ visible: Bool) {
        let js = visible ? "window.showDropOverlay?.()" : "window.hideDropOverlay?.()"
        evaluateJavaScript(js, completionHandler: nil)
    }
}

private struct SpellContext {
    let word: String
    let from: Int
    let to: Int

    init?(_ result: Any?) {
        guard
            let map = result as? [String: Any],
            let word = map["word"] as? String,
            let from = map["from"] as? NSNumber,
            let to   = map["to"]   as? NSNumber
        else { return nil }
        self.word = word
        self.from = from.intValue
        self.to   = to.intValue
    }
}

private final class SpellReplacement: NSObject {
    let from: Int
    let to: Int
    let suggestion: String
    init(from: Int, to: Int, suggestion: String) {
        self.from = from; self.to = to; self.suggestion = suggestion
    }
}
