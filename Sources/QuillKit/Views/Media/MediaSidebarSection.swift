import SwiftUI

struct MediaSidebarSection: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(selection: $appState.mediaFilter) {
            ForEach(MediaFilter.allCases) { filter in
                Label(filter.title, systemImage: filter.icon)
                    .tag(filter)
            }
            if let error = appState.mediaError {
                SidebarErrorRow(message: error)
            }
        }
        .listStyle(.sidebar)
    }
}
