import AppKit
import SwiftUI

struct SidebarSectionPicker: NSViewRepresentable {
    @Binding var selection: SidebarSection

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: SidebarSection.allCases.map(\.shortTitle),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.selectionChanged(_:))
        )
        control.segmentDistribution = .fillEqually
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        guard let index = SidebarSection.allCases.firstIndex(of: selection) else { return }
        if control.selectedSegment != index { control.selectedSegment = index }
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    final class Coordinator: NSObject {
        var selection: Binding<SidebarSection>

        init(selection: Binding<SidebarSection>) { self.selection = selection }

        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            let sections = SidebarSection.allCases
            guard sections.indices.contains(sender.selectedSegment) else { return }
            selection.wrappedValue = sections[sender.selectedSegment]
        }
    }
}
