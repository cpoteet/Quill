import SwiftUI
import AppKit

// Makes the title bar match the app's warm panel color instead of the stock
// system material.
//
// Mechanics (verified by instrumenting the live window, 2026-07-24):
//   * `titlebarAppearsTransparent = true` hides `NSTitlebarBackgroundView`, and the
//     32pt strip then renders `window.backgroundColor` directly. Confirmed by
//     temporarily setting that color to red and watching the title bar turn red.
//   * SwiftUI's own `AppKitWindow` sets `titlebarAppearsTransparent` back to `false`
//     roughly 0.1s after `viewDidMoveToWindow` runs, during its window setup — which
//     is why applying the fix only once silently reverted to a white bar. The
//     `didUpdate` observer below re-asserts it, so any later reset self-heals.
//   * `.fullSizeContentView` must stay out of the style mask: with it, SwiftUI content
//     sits *under* the bar and shows through as separate sidebar/editor color zones.
//     macOS re-adds the flag on full-screen transitions, hence the exit observer.
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
                // Idempotent: only touches the window when something reset the flag,
                // so the frequent didUpdate notification stays cheap.
                if !window.titlebarAppearsTransparent { applyTitleBarFix(to: window) }
            })
        }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}

private func applyTitleBarFix(to window: NSWindow) {
    window.styleMask.remove(.fullSizeContentView)
    window.titlebarAppearsTransparent = true
    window.backgroundColor = .wpTitleBarBg
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
