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
        NSMenu.popUpContextMenu(buildContextMenu(), with: event, for: self)
    }

    // willOpenMenu is kept as a fallback for non-rightMouseDown code paths
    // (e.g. accessibility). allowsContextMenuPlugIns = false is set here too.
    public override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.allowsContextMenuPlugIns = false
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.allowsContextMenuPlugIns = false
        menu.items = [
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

    // MARK: - Helpers

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
