import SwiftUI

struct SidebarStatusFilterButton: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let section = appState.selectedSection
        let current = appState.statusFilter
        let isFiltering = current != .all
        Menu {
            Picker("Filter by Status", selection: $appState.statusFilter) {
                ForEach(appState.availableStatusFilters, id: \.self) { filter in
                    Text(filter.title(in: section))
                        .badge(appState.statusCount(filter))
                        .tag(filter)
                    if filter == .all { Divider() }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            if isFiltering {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .font(.system(size: 18))
            } else {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 18))
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Filter by Status")
        .accessibilityLabel("Filter by Status")
        .accessibilityValue(current.title(in: section))
    }
}
