import SwiftUI

/// What System Settings → Desktop & Dock → "Double-click a window's title bar to" asks for.
enum TitlebarDoubleClickAction: Equatable {
    case minimize
    case zoom
    case doNothing

    /// `AppleActionOnDoubleClick` holds "Minimize", "Maximize" (Zoom), "Fill" or "None" (Do Nothing).
    /// Older systems wrote only the Bool `AppleMiniaturizeOnDoubleClick`. Fill has no public API, so it zooms.
    init(actionSetting: String?, legacyMiniaturize: Bool) {
        switch actionSetting {
        case "Minimize": self = .minimize
        case "None": self = .doNothing
        case "Maximize", "Fill": self = .zoom
        default: self = legacyMiniaturize ? .minimize : .zoom
        }
    }

    static func current(_ defaults: UserDefaults = .standard) -> TitlebarDoubleClickAction {
        TitlebarDoubleClickAction(
            actionSetting: defaults.string(forKey: "AppleActionOnDoubleClick"),
            legacyMiniaturize: defaults.bool(forKey: "AppleMiniaturizeOnDoubleClick"))
    }
}

// `.toolbarBackgroundVisibility(.hidden)` makes SwiftUI set `titlebarAppearsTransparent`, and a transparent title bar
// never runs the title-bar double-click action: empty space passes the click through to the content, and the toolbar's
// flexible spaces take it and do nothing. This performs the user's chosen action instead — see
// docs/platform-workarounds.md.
struct TitlebarDoubleClick: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { TitlebarDoubleClickView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class TitlebarDoubleClickView: NSView {
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return handled ? nil : event
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    /// Returns whether the click was used, so the content underneath does not also get it.
    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, isTitlebarDoubleClick(event, in: window) else { return false }
        switch TitlebarDoubleClickAction.current() {
        case .minimize: window.performMiniaturize(nil)
        case .zoom: window.performZoom(nil)
        case .doNothing: return false
        }
        return true
    }

    /// A double-click on empty space in the toolbar strip. Toolbar items (each SwiftUI toolbar button is an item's
    /// `view`; spaces have none) and controls such as the window buttons keep their own double-click. Once the title
    /// bar is no longer transparent, AppKit handles the double-click natively and this stands aside.
    private func isTitlebarDoubleClick(_ event: NSEvent, in window: NSWindow) -> Bool {
        guard event.clickCount == 2,
              window.titlebarAppearsTransparent,
              !window.styleMask.contains(.fullScreen),
              event.locationInWindow.y >= window.contentLayoutRect.maxY,
              let hit = window.contentView?.superview?.hitTest(event.locationInWindow)
        else { return false }
        let itemViews = window.toolbar?.items.compactMap(\.view) ?? []
        var view: NSView? = hit
        while let current = view {
            if current is NSControl || itemViews.contains(where: { $0 === current }) { return false }
            view = current.superview
        }
        return true
    }
}
