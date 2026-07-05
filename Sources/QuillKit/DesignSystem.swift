import SwiftUI

extension NSColor {
    static let wpSidebarBg = NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
        case .darkAqua: return .underPageBackgroundColor
        default: return NSColor(red: 242 / 255, green: 241 / 255, blue: 239 / 255, alpha: 1)
        }
    }
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
    var color: Color
    var shimmerOpacity: Double
    var accentOpacity: Double

    var body: some View {
        ZStack {
            color
            LinearGradient(
                colors: [
                    Color.white.opacity(shimmerOpacity),
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

extension View {
    func toast(message: Binding<String?>, isError: Binding<Bool> = .constant(false)) -> some View {
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
                    .task(id: msg) {
                        // Keyed on the message text so a new toast shown while one is
                        // already visible cancels the old dismissal timer and starts its own,
                        // instead of the old timer clearing the new toast early.
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
