import SwiftUI

struct SidebarSectionPicker: View {
    @Binding var selection: SidebarSection
    @State private var hoveredSection: SidebarSection?

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(SidebarSection.allCases, id: \.self) { section in
                    segment(for: section)
                }
            }
        }
    }

    private func segment(for section: SidebarSection) -> some View {
        let isSelected = selection == section
        let isHovered = hoveredSection == section && !isSelected
        return Button {
            selection = section
        } label: {
            VStack(spacing: 3) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(height: 18)
                Text(section.shortTitle)
                    .font(.system(size: 10.5, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(isHovered ? 0.07 : 0))
            )
            .contentShape(Rectangle())
            .foregroundStyle(isSelected || isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .glassEffect(isSelected ? .regular.interactive() : .identity, in: .rect(cornerRadius: 8))
        .onHover { inside in
            if inside {
                hoveredSection = section
            } else if hoveredSection == section {
                hoveredSection = nil
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel(section.rawValue)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
