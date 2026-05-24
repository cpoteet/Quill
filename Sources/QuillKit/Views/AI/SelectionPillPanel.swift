import AppKit
import SwiftUI
import WebKit

/// Non-activating floating pill that appears above a text selection with four AI operation buttons.
/// Clicking a button does not steal focus from the editor.
final class SelectionPillPanel: NSPanel {

    private var onOperation: ((AIWritingOperation) -> Void)?
    private var hostingController: NSHostingController<SelectionPillView>?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 44),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        animationBehavior = .none
    }

    /// Show the pill above the given JS selection rect, anchored to `webView`.
    func show(
        selectionRect jsRect: CGRect,
        in webView: NSView,
        onOperation: @escaping (AIWritingOperation) -> Void
    ) {
        self.onOperation = onOperation

        let pillView = SelectionPillView { [weak self] op in
            self?.orderOut(nil)
            onOperation(op)
        }
        let hc = NSHostingController(rootView: pillView)
        hc.sizingOptions = .preferredContentSize
        contentViewController = hc
        hostingController = hc

        // Size panel to fit SwiftUI content
        let size = hc.view.fittingSize
        setContentSize(size)

        position(jsRect: jsRect, in: webView)

        // Child window keeps the pill above the main window but NOT above other apps.
        if parent == nil, let mainWindow = webView.window {
            mainWindow.addChildWindow(self, ordered: .above)
        }

        alphaValue = 0
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 1
        }
    }

    func hide() {
        parent?.removeChildWindow(self)
        orderOut(nil)
    }

    // MARK: - Coordinate conversion

    /// WKWebView is flipped: jsRect.y is distance from the top-left of the web view,
    /// Y increasing downward — same as the JS DOM. Convert to screen coordinates
    /// (AppKit: Y increases upward from screen bottom) for NSPanel placement.
    private func position(jsRect: CGRect, in webView: NSView) {
        guard let window = webView.window else { return }

        // Convert the JS rect (flipped) to an AppKit rect in the webView's coordinate space
        let flippedY = webView.bounds.height - jsRect.origin.y  // top edge in AppKit coords
        let rectInWebView = NSRect(
            x: jsRect.origin.x,
            y: flippedY - jsRect.height,   // bottom edge in AppKit coords
            width: jsRect.width,
            height: jsRect.height
        )
        let rectInWindow = webView.convert(rectInWebView, to: nil)
        let rectOnScreen = window.convertToScreen(rectInWindow)

        // Place pill 8 pt above the top edge of the selection
        let panelW = frame.size.width
        let x = rectOnScreen.midX - panelW / 2
        let y = rectOnScreen.maxY + 8
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - SwiftUI pill content

struct SelectionPillView: View {
    let onOperation: (AIWritingOperation) -> Void

    var body: some View {
        HStack(spacing: 1) {
            pillButton("Make Longer",      op: .makeLonger)
            pillDivider
            pillButton("Make Shorter",     op: .makeShorter)
            pillDivider
            pillButton("To Table",         op: .convertToTable)
            pillDivider
            pillButton("To List",          op: .convertToList)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                )
        )
        .padding(6) // room for shadow clipping
    }

    private var pillDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 1, height: 16)
    }

    private func pillButton(_ label: String, op: AIWritingOperation) -> some View {
        Button(label) { onOperation(op) }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
    }
}
