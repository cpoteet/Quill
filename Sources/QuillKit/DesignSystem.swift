import SwiftUI

extension NSColor {
    static let wpSidebarBg = NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
        case .darkAqua: return .underPageBackgroundColor
        default: return NSColor(red: 242 / 255, green: 241 / 255, blue: 239 / 255, alpha: 1)
        }
    }

    /// Window background, which is what the transparent title bar renders.
    ///
    /// The panels below paint `wpSidebarBg` *plus* the `WarmPanelBackground` shimmer
    /// — a diagonal gradient, white at 10–14% from the top-left, fading to amber and
    /// then clear toward the bottom-right. So the panel edge meeting the title bar is
    /// not one color: it runs lightest at the left and settles toward the raw token
    /// across the width. A flat bar can only match the average, which lands on the
    /// token itself. (Tuned against the live window, 2026-07-24.)
    static let wpTitleBarBg = wpSidebarBg
}

extension Color {
    static let wpAmber = Color(hue: 0.105, saturation: 0.82, brightness: 0.92)

    /// Warm off-white sidebar background (#F2F1EF in light, system in dark)
    static let wpSidebarBg = Color(NSColor.wpSidebarBg)

    /// Same as wpSidebarBg — kept as a separate token so call sites don't need updating
    static let wpPanelBg = wpSidebarBg

    /// Maps a PostItem.statusBadge string to a display color.
    static func statusColor(_ badge: String) -> Color {
        switch badge {
        case "publish":    return .green
        case "draft":      return .wpAmber
        case "future":     return .blue
        case "pending":    return .orange
        case "private":    return .teal
        case "local-post": return .purple
        case "local-page": return Color(nsColor: .systemIndigo)
        default:           return Color(.tertiaryLabelColor)
        }
    }
}

// MARK: - Surfaces

private struct WarmPanelBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var color: Color
    var shimmerOpacity: Double
    var accentOpacity: Double

    var body: some View {
        ZStack {
            color
            LinearGradient(
                colors: [
                    // The white stop is light-mode only. Over the near-black dark
                    // background it reads as haze rather than shimmer, and it lifts the
                    // panels away from the flat title bar (which paints wpTitleBarBg with
                    // no gradient), opening a visible seam under the window chrome.
                    colorScheme == .dark ? .clear : Color.white.opacity(shimmerOpacity),
                    Color.wpAmber.opacity(accentOpacity),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct WarmSidebarBackground: View {
    var body: some View {
        WarmPanelBackground(color: .wpSidebarBg, shimmerOpacity: 0.14, accentOpacity: 0.018)
    }
}

struct WarmPanelHeaderBackground: View {
    var body: some View {
        WarmPanelBackground(color: .wpPanelBg, shimmerOpacity: 0.10, accentOpacity: 0.014)
    }
}

struct SoftPanelBoundary: View {
    var body: some View {
        Color.clear
            .frame(width: 1)
            .overlay(alignment: .leading) {
                ZStack(alignment: .leading) {
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.035),
                            Color.primary.opacity(0.012),
                            Color.clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )

                    Rectangle()
                        .fill(Color.primary.opacity(0.055))
                        .frame(width: 0.5)
                }
                .frame(width: 8)
            }
            .allowsHitTesting(false)
        }
}

struct SoftHorizontalDivider: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.primary.opacity(0.04),
                        Color.primary.opacity(0.095),
                        Color.primary.opacity(0.04),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 0.5)
            .allowsHitTesting(false)
    }
}

struct PanelInteriorFade: View {
    var from: UnitPoint
    private var to: UnitPoint { from == .leading ? .trailing : .leading }
    var body: some View {
        LinearGradient(
            colors: [
                Color.primary.opacity(0.028),
                Color.primary.opacity(0.010),
                Color.clear,
            ],
            startPoint: from,
            endPoint: to
        )
        .frame(width: 18)
        .allowsHitTesting(false)
    }
}

// MARK: - Appearance-change workaround

/// Rebuilds the wrapped view whenever the light/dark appearance changes.
///
/// SwiftUI backs `Picker` with a real AppKit `NSPopUpButton` (`SwiftUIPopupButton`), and
/// it stamps an *explicit* `NSAppearance` on that button when it configures it. That
/// stamp is never refreshed: on a light/dark switch the button's own host container
/// updates (`AppKitPlatformViewHost` goes to the new appearance) while the button keeps
/// the old one, so it goes on drawing its previous bezel and label color — a light pill
/// with dark text sitting in a dark panel, or pale text on the light panel. Verified
/// 2026-07-25 by dumping the live ancestor chain: `SwiftUIPopupButton explicit=DarkAqua`
/// under `AppKitPlatformViewHost explicit=Aqua` under an all-`Aqua` window.
///
/// Nothing in a plain `Picker` subtree depends on `colorScheme`, so SwiftUI has no reason
/// to re-evaluate it and the stale stamp survives indefinitely. Reading `colorScheme`
/// here and feeding it to `.id()` gives the subtree a new identity on every switch, which
/// forces SwiftUI to build a fresh control that gets stamped with the current appearance.
private struct RebuildOnAppearanceChange: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.id(colorScheme)
    }
}

extension View {
    /// Apply to AppKit-backed controls that don't repaint on a light/dark switch —
    /// `Picker` most notably. See `RebuildOnAppearanceChange` for why this is needed.
    func rebuildsOnAppearanceChange() -> some View {
        modifier(RebuildOnAppearanceChange())
    }
}

// MARK: - Toast

struct ToastView: View {
    let message: String
    var isError: Bool = false

    private var systemImage: String { isError ? "xmark.circle.fill" : "checkmark.circle.fill" }
    private var iconColor: Color { isError ? .red : .green }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
                .font(.system(size: 13, weight: .medium))
            Text(message)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 0)
    }
}

/// Shown while a dropped image is converted and uploaded, before it is inserted.
/// Matches `ToastView`'s surface so the two read as one family.
struct UploadStatusPill: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 0)
    }
}

extension View {
    /// Bottom-center progress pill. Uses the same slot as `toast(message:isError:token:)`;
    /// callers must clear the status before presenting a toast so the two never overlap.
    func uploadStatus(_ message: Binding<String?>) -> some View {
        ZStack(alignment: .bottom) {
            self
            if let msg = message.wrappedValue {
                UploadStatusPill(message: msg)
                    .padding(.bottom, 20)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity.combined(with: .scale(scale: 0.92))
                        )
                    )
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: message.wrappedValue != nil)
    }
}

extension View {
    /// `token` should be bumped by the caller on every toast presentation (even when the
    /// message text is unchanged from the previous toast) — keying the dismiss timer on the
    /// message string alone can't distinguish "still showing the first toast" from "a second,
    /// textually-identical toast just replaced it", so an unchanged string would inherit
    /// whatever time was left on the first toast's timer instead of a fresh 2 seconds.
    func toast(message: Binding<String?>, isError: Binding<Bool> = .constant(false), token: Int = 0) -> some View {
        ZStack(alignment: .bottom) {
            self
            if let msg = message.wrappedValue {
                ToastView(message: msg, isError: isError.wrappedValue)
                    .padding(.bottom, 20)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity.combined(with: .scale(scale: 0.92))
                        )
                    )
                    .zIndex(1)
                    .task(id: token) {
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        message.wrappedValue = nil
                        isError.wrappedValue = false
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: message.wrappedValue != nil)
    }
}
