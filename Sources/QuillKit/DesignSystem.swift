import SwiftUI

extension Color {
    private static let draftAmber = Color(hue: 0.105, saturation: 0.82, brightness: 0.92)

    /// Maps a PostItem.statusBadge string to a display color.
    static func statusColor(_ badge: String) -> Color {
        switch badge {
        case "publish":    return .green
        case "draft":      return .draftAmber
        case "future":     return .blue
        case "pending":    return .orange
        case "private":    return .teal
        case "local-post": return .purple
        case "local-page": return Color(nsColor: .systemIndigo)
        default:           return Color(.tertiaryLabelColor)
        }
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
