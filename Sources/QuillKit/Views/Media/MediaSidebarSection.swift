import SwiftUI

struct MediaSidebarSection: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(selection: filterSelection) {
            ForEach(MediaFilter.allCases) { filter in
                Label(filter.title, systemImage: filter.icon)
                    .tag(filter)
            }
            if let error = appState.mediaError {
                SidebarErrorRow(failure: error)
            }
        }
        .listStyle(.sidebar)
    }

    private var filterSelection: Binding<MediaFilter> {
        Binding(
            get: { appState.mediaFilter },
            set: { filter in
                guard filter != appState.mediaFilter else { return }
                appState.selectedMedia = nil
                appState.mediaFilter = filter
            }
        )
    }
}
