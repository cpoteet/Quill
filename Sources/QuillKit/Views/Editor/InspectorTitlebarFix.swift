import SwiftUI

// Re-expanding the inspector leaves the content pane's titlebar background at full window
// width, painting over the inspector's first 52pt — see docs/gotchas.md.
struct InspectorTitlebarFix: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { TitlebarOrderView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class TitlebarOrderView: NSView {
    private weak var observedTitlebar: NSView?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let split = enclosingSplitView else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(trimContentTitlebar),
            name: NSSplitView.didResizeSubviewsNotification,
            object: split
        )
        trimContentTitlebar()
    }

    private var enclosingSplitView: NSSplitView? {
        var candidate = superview
        while let view = candidate {
            if let split = view as? NSSplitView { return split }
            candidate = view.superview
        }
        return nil
    }

    @objc private func trimContentTitlebar() {
        guard let split = enclosingSplitView else { return }
        let titlebars = split.subviews
            .filter { $0.className == "NSTitlebarBackgroundView" }
            .sorted { $0.frame.minX < $1.frame.minX }
        guard titlebars.count == 2 else { return }
        let content = titlebars[0]
        let inspector = titlebars[1]
        if observedTitlebar !== content {
            if let previous = observedTitlebar {
                NotificationCenter.default.removeObserver(
                    self, name: NSView.frameDidChangeNotification, object: previous)
            }
            content.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(trimContentTitlebar),
                name: NSView.frameDidChangeNotification,
                object: content
            )
            observedTitlebar = content
        }
        guard content.frame.maxX > inspector.frame.minX else { return }
        content.frame.size.width = inspector.frame.minX - content.frame.minX
    }
}
