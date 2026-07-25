import SwiftUI
import AppKit

// Makes the title bar match the app's warm panel color instead of the stock
// system material.
//
// Mechanics (verified by instrumenting the live window, 2026-07-24 and 2026-07-25):
//   * `titlebarAppearsTransparent = true` hides `NSTitlebarBackgroundView`, and the
//     32pt strip then renders whatever the theme frame draws beneath it — which is
//     `window.backgroundColor` only as long as no vibrant backdrop view sits in between
//     (that caveat is the whole subject of `titleBarColor(for:)` below).
//   * SwiftUI's own `AppKitWindow` sets `titlebarAppearsTransparent` back to `false`
//     roughly 0.1s after `viewDidMoveToWindow` runs, during its window setup — which
//     is why applying the fix only once silently reverted to a white bar. The
//     `didUpdate` observer below re-asserts it, so any later reset self-heals.
//   * `.fullSizeContentView` must stay out of the style mask: with it, SwiftUI content
//     sits *under* the bar and shows through as separate sidebar/editor color zones.
//     macOS re-adds the flag on full-screen transitions, hence the exit observer.
//   * `backgroundColor` must be assigned an *already-resolved* color, never the dynamic
//     `wpTitleBarBg` token — see `titleBarColor(for:)`.
private final class WindowObservingView: NSView {
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        applyTitleBarFix(to: window)
        guard observers.isEmpty else { return }
        for name in [NSWindow.didExitFullScreenNotification, NSWindow.didUpdateNotification] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak window] _ in
                guard let window else { return }
                // Idempotent: only touches the window when the state has actually drifted,
                // so the frequent didUpdate notification stays cheap. The color comparison
                // is exact — two colors resolved from the same appearance are `==`, and
                // resolutions from different appearances never are.
                if titleBarFixNeeded(for: window) { applyTitleBarFix(to: window) }
            })
        }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}

/// The title-bar color resolved for a specific appearance.
///
/// `window.backgroundColor` must be given a resolved color, not the dynamic
/// `wpTitleBarBg` token, and the difference is not cosmetic. Assigning a *catalog*
/// (dynamic) color leaves the window on AppKit's vibrant-backdrop path: the theme frame
/// then carries a behind-window `NSVisualEffectView` sized to the whole frame —
/// including the 32pt title-bar strip — which paints blurred desktop *over*
/// `backgroundColor` and hides it completely. Assigning a resolved opaque color drops
/// that backdrop view entirely (verified 2026-07-25: the theme frame's subviews go from
/// `["NSVisualEffectView", hostingView, titlebarContainer]` to just the latter two), and
/// the transparent strip then renders `backgroundColor` as intended.
///
/// Whether the window got a vibrant backdrop was decided once, at window creation, from
/// the appearance in effect at that moment — which is why this bug only showed up when
/// the app *launched* in dark mode, and why no later light/dark toggle recovered from it.
///
/// The cost of resolving is that the color no longer tracks appearance changes on its
/// own, so it has to be re-applied on every switch: `WindowTitleBarFix.updateNSView`
/// reads `colorScheme` for exactly that, and `titleBarFixNeeded(for:)` catches any
/// window that drifted.
private func titleBarColor(for appearance: NSAppearance) -> NSColor {
    var resolved: NSColor = .wpTitleBarBg
    appearance.performAsCurrentDrawingAppearance {
        resolved = NSColor.wpTitleBarBg.usingColorSpace(.sRGB) ?? .wpTitleBarBg
    }
    return resolved
}

private func titleBarFixNeeded(for window: NSWindow) -> Bool {
    !window.titlebarAppearsTransparent
        || window.styleMask.contains(.fullSizeContentView)
        || window.backgroundColor != titleBarColor(for: window.effectiveAppearance)
}

private func applyTitleBarFix(to window: NSWindow) {
    window.styleMask.remove(.fullSizeContentView)
    window.titlebarAppearsTransparent = true
    window.backgroundColor = titleBarColor(for: window.effectiveAppearance)
}

private struct WindowTitleBarFix: NSViewRepresentable {
    // Switching between light and dark resets `titlebarAppearsTransparent` the same way
    // SwiftUI's initial window setup does, and the notification observers only catch it
    // once the window next updates — until then the bar shows the stock system material.
    // Reading colorScheme here makes SwiftUI re-run updateNSView on every appearance
    // change, so the fix re-applies immediately instead of on the next stray update.
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> WindowObservingView { WindowObservingView() }

    func updateNSView(_ nsView: WindowObservingView, context: Context) {
        guard let window = nsView.window else { return }
        applyTitleBarFix(to: window)
    }
}

public struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            if appState.isSidebarVisible {
                SidebarView()
                    .frame(width: 240)
                    .transition(.move(edge: .leading))
                SoftPanelBoundary()
                    .transition(.move(edge: .leading))
            }
            Group {
                if appState.selectedSection == .media {
                    if let media = appState.selectedMedia {
                        MediaDetailView(media: media) { [media] altText in
                            guard let creds = appState.credentials else { return }
                            guard let idx = appState.mediaItems.firstIndex(where: { $0.id == media.id }) else { return }
                            do {
                                let updated = try await WordPressClient(credentials: creds)
                                    .updateMediaAltText(id: media.id, altText: altText)
                                appState.mediaItems[idx] = updated
                                if appState.selectedMedia?.id == updated.id {
                                    appState.selectedMedia = updated
                                }
                            } catch {
                                // Save failed silently — field retains the edited value
                            }
                        }
                        .id(media.id)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "photo")
                                .font(.system(size: 38, weight: .light))
                                .foregroundStyle(Color.wpAmber.opacity(0.5))
                            Text("Select an image to preview")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.wpPanelBg)
                    }
                } else if let item = appState.selectedItem {
                    PostEditorView(item: item)
                } else if !appState.hasLoadedList || appState.isLoadingList {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.wpPanelBg)
                } else {
                    EmptyEditorPlaceholder(section: appState.selectedSection,
                                          sectionIsEmpty: appState.sectionIsEmpty)
                }
            }
            .frame(minWidth: 500, maxWidth: .infinity)
        }
        .animation(.easeInOut(duration: 0.2), value: appState.isSidebarVisible)
        .frame(minWidth: 900, minHeight: 600)
        .background(Color.wpPanelBg)
        .background(WindowTitleBarFix())
    }
}

struct EmptyEditorPlaceholder: View {
    let section: SidebarSection
    var sectionIsEmpty: Bool = false

    private var noun: String {
        switch section {
        case .posts: return "post"
        case .pages: return "page"
        case .localDrafts: return "draft"
        default: return "post"
        }
    }

    private var icon: String {
        switch section {
        case .posts: return "doc.text"
        case .pages: return "doc.plaintext"
        case .localDrafts: return "pencil"
        case .media: return "photo"
        }
    }

    private var message: String {
        if sectionIsEmpty {
            return "No \(noun)s yet"
        }
        return "Select a \(noun) to edit"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Color.wpAmber.opacity(0.5))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
