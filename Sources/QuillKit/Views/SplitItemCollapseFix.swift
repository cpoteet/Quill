import SwiftUI

// A split item's default uncollapse grows the split view instead of its siblings — see docs/gotchas.md.
struct SplitItemCollapseFix: NSViewRepresentable {
    let behavior: NSSplitViewItem.Behavior

    func makeNSView(context: Context) -> NSView { CollapseBehaviorView(behavior: behavior) }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class CollapseBehaviorView: NSView {
    private let behavior: NSSplitViewItem.Behavior

    init(behavior: NSSplitViewItem.Behavior) {
        self.behavior = behavior
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let controller = enclosingSplitView?.delegate as? NSSplitViewController else { return }
        for item in controller.splitViewItems where item.behavior == behavior {
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
