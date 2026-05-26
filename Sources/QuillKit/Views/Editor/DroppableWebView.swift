import AppKit
import WebKit

/// WKWebView subclass that intercepts image file drops from Finder,
/// forwards the file URLs to Swift for upload, and shows a visual
/// drop overlay inside the web content while dragging.
public final class DroppableWebView: WKWebView {
    public var onImageFilesDropped: (([URL]) -> Void)?

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

    private let menuFilter = WebViewMenuFilter()

    public override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        // Items before the first separator are spell-check suggestions WebKit adds
        // for misspelled words (using standard selectors like changeSpelling:,
        // ignoreSpelling:, learnSpelling:). Preserve those and rebuild the standard
        // edit commands — WebKit's own Cut/Copy/Paste use private internal selectors
        // that get filtered away along with browser-specific items.
        var spellItems: [NSMenuItem] = []
        for item in menu.items {
            if item.isSeparatorItem { break }
            spellItems.append(item)
        }
        var newItems = spellItems
        if !spellItems.isEmpty { newItems.append(.separator()) }
        newItems += [
            NSMenuItem(title: "Cut", action: NSSelectorFromString("cut:"), keyEquivalent: ""),
            NSMenuItem(title: "Copy", action: NSSelectorFromString("copy:"), keyEquivalent: ""),
            NSMenuItem(title: "Paste", action: NSSelectorFromString("paste:"), keyEquivalent: ""),
        ]
        menu.items = newItems
        // macOS may still append Services/AutoFill after this; re-filter in menuWillOpen.
        menu.delegate = menuFilter
    }

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

final class WebViewMenuFilter: NSObject, NSMenuDelegate {
    private static let allowed: Set<String> = [
        "cut:", "copy:", "paste:",
        "changeSpelling:", "ignoreSpelling:", "learnSpelling:",
    ]

    static func apply(to menu: NSMenu) {
        menu.items = menu.items.filter { item in
            if item.isSeparatorItem { return true }
            guard let action = item.action else { return false }
            return allowed.contains(NSStringFromSelector(action))
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        Self.apply(to: menu)
    }
}
