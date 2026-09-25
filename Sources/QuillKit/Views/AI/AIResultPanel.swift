import AppKit
import SwiftUI

/// Non-activating floating bar, fixed at the bottom of the editor, with Accept / Discard buttons for an AI result.
/// Return accepts, Escape discards, clicking outside the panel discards.
final class AIResultPanel: NSPanel {

    private var onAccept: (() -> Void)?
    private var onDiscard: (() -> Void)?
    private var eventMonitor: Any?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 40),
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

    /// Show the bar centred along the bottom edge of the editor.
    func show(
        in webView: NSView,
        onAccept: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.onAccept = onAccept
        self.onDiscard = onDiscard

        let barView = AIResultBarView(
            onAccept: { [weak self] in self?.finish(accepted: true) },
            onDiscard: { [weak self] in self?.finish(accepted: false) }
        )
        let hc = NSHostingController(rootView: barView)
        contentViewController = hc

        let size = hc.view.fittingSize
        setContentSize(size)
        position(in: webView)

        // Child window keeps the panel above the main window but NOT above other apps.
        // Using level = .floating would float over every app system-wide.
        if parent == nil, let mainWindow = webView.window {
            mainWindow.addChildWindow(self, ordered: .above)
        }
        orderFront(nil)

        // A second AI operation can call show() again before dismiss() runs (e.g. via the
        // right-click menu, which bypasses the left-mouse-down discard path) — remove any
        // existing monitor first so they don't stack and double-fire on keypress.
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        // Local event monitor: Return = accept, Escape = discard, click outside = discard
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                switch event.keyCode {
                case 36: // Return
                    self.finish(accepted: true)
                    return nil
                case 53: // Escape
                    self.finish(accepted: false)
                    return nil
                default:
                    break
                }
            } else if event.type == .leftMouseDown, event.window !== self {
                // Click outside this panel → discard
                self.finish(accepted: false)
            }
            return event
        }
    }

    func dismiss() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        parent?.removeChildWindow(self)
        orderOut(nil)
    }

    private func finish(accepted: Bool) {
        dismiss()
        if accepted { onAccept?() } else { onDiscard?() }
    }

    // MARK: - Positioning

    private func position(in webView: NSView) {
        guard let window = webView.window else { return }
        let webViewOnScreen = window.convertToScreen(webView.convert(webView.bounds, to: nil))
        setFrameOrigin(NSPoint(
            x: webViewOnScreen.midX - frame.width / 2,
            y: webViewOnScreen.minY + 16
        ))
    }
}

// MARK: - SwiftUI bar content

private struct AIResultBarView: View {
    let onAccept: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onAccept) {
                Label("Accept", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)

            Button(action: onDiscard) {
                Label("Discard", systemImage: "xmark")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(6)
    }
}
