import SwiftUI

extension Color {
    private static let draftAmber = Color(hue: 0.105, saturation: 0.82, brightness: 0.92)

    /// The editor's document surface. `editor.html` mirrors this colour's two resolved values; they must move together.
    static let wpContentSurface = Color(nsColor: .textBackgroundColor)

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

/// Shape carries the status alongside `Color.statusColor(_:)`, so colour is never the sole signal.
func statusSymbol(_ badge: String) -> String {
    switch badge {
    case "publish":    return "checkmark.circle.fill"
    case "draft":      return "pencil.circle.fill"
    case "future":     return "clock.circle.fill"
    case "pending":    return "exclamationmark.circle.fill"
    case "private":    return "lock.circle.fill"
    case "local-post", "local-page": return "tray.circle.fill"
    default:           return "circle.fill"
    }
}

// MARK: - Section label

/// The uppercase caption above an inspector or sheet section. One spelling for the whole app.
struct SectionLabel: View {
    private let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(1.0)
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
                .accessibilityHidden(true)
            Text(message)
                .font(.body)
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
                .font(.body)
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
