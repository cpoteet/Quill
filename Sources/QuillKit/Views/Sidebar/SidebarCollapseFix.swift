import SwiftUI

// Dragging the sidebar back out after a drag-collapse grows the window — see Views/Sidebar/CLAUDE.md.
struct SidebarCollapseFix: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { CollapseBehaviorView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class CollapseBehaviorView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let controller = enclosingSplitView?.delegate as? NSSplitViewController else { return }
        for item in controller.splitViewItems where item.behavior == .sidebar {
            item.collapseBehavior = .useConstraints
        }
    }

    private var enclosingSplitView: NSSplitView? {
        var candidate = superview
        while let view = candidate {
            if let split = view as? NSSplitView { return split }
            candidate = view.superview
        }
        return nil
    }
}
