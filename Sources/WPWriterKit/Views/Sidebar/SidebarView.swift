import SwiftUI

public struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $appState.selectedSection) {
                ForEach(SidebarSection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if appState.selectedSection != .media {
                SearchField(text: $appState.searchText)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)

                List(appState.filteredItems, selection: $appState.selectedItem) { item in
                    PostListRow(item: item)
                        .tag(item)
                }
                .listStyle(.sidebar)

                Divider()
                HStack {
                    Spacer()
                    Button {
                        createNewDraft()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .buttonStyle(.plain)
                    .help("New Local Draft")
                    .padding(8)
                }
            } else {
                Text("Media")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 220)
        .task(id: appState.selectedSection) {
            await loadCurrentSection()
        }
    }

    private func createNewDraft() {
        // Implemented in Task 17 when AppServices is wired up
    }

    private func loadCurrentSection() async {
        // Implemented in Task 17
    }
}

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.quinary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
