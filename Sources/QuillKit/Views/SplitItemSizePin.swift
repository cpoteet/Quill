import SwiftUI

// SwiftUI leaves a split item's size free in the layout engine, so a window resize lays its content out at minimum size — see docs/gotchas.md.
struct SplitItemSizePin: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { SizePinView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class SizePinView: NSView {
    private weak var item: NSView?
    private var pins: [NSLayoutConstraint] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        unpin()
        guard window != nil, let item = enclosingSplitItem else { return }
        let width = item.widthAnchor.constraint(equalToConstant: item.frame.width)
        let height = item.heightAnchor.constraint(equalToConstant: item.frame.height)
        // One above NSSplitView's 250 preferred-size constraint, below anything AppKit sizes through the engine.
        width.priority = NSLayoutConstraint.Priority(251)
        height.priority = NSLayoutConstraint.Priority(251)
        NSLayoutConstraint.activate([width, height])
        pins = [width, height]
        self.item = item
        NotificationCenter.default.addObserver(
            self, selector: #selector(itemFrameDidChange), name: NSView.frameDidChangeNotification, object: item)
    }

    @objc private func itemFrameDidChange() {
        guard let item, pins.count == 2 else { return }
        pins[0].constant = item.frame.width
        pins[1].constant = item.frame.height
    }

    private func unpin() {
        NSLayoutConstraint.deactivate(pins)
        pins = []
        if let item { NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: item) }
        item = nil
    }

    private var enclosingSplitItem: NSView? {
        var candidate = superview
        while let view = candidate {
            if view.superview is NSSplitView { return view }
            candidate = view.superview
        }
        return nil
    }
}
