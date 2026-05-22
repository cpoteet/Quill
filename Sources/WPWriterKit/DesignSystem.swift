import SwiftUI

extension Color {
    static let wpAmber = Color(hue: 0.105, saturation: 0.82, brightness: 0.92)
}

// MARK: - Toast

struct ToastView: View {
    let message: String
    var systemImage: String = "checkmark.circle.fill"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.green)
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
    func toast(message: Binding<String?>) -> some View {
        ZStack(alignment: .bottom) {
            self
            if let msg = message.wrappedValue {
                ToastView(message: msg)
                    .padding(.bottom, 20)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .opacity.combined(with: .scale(scale: 0.92))
                    ))
                    .zIndex(1)
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            message.wrappedValue = nil
                        }
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: message.wrappedValue != nil)
    }
}
