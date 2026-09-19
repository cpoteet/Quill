import SwiftUI

public struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            detailContent
                .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.wpContentSurface.ignoresSafeArea())
        }
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .windowToolbar)
        .frame(minWidth: 900, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Section", selection: sectionSelection) {
                    ForEach(SidebarSection.allCases, id: \.self) { section in
                        Text(section.shortTitle).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                .rebuildsOnAppearanceChange()
            }
        }
    }

    private var sectionSelection: Binding<SidebarSection> {
        Binding(
            get: { appState.selectedSection },
            set: { section in
                guard section != appState.selectedSection else { return }
                appState.selectedItem = nil
                appState.selectedMedia = nil
                appState.searchText = ""
                appState.selectedSection = section
            }
        )
    }

    @ViewBuilder
    private var detailContent: some View {
        if appState.selectedSection == .media {
            if let media = appState.selectedMedia {
                MediaDetailView(media: media) { [media] altText in
                    guard let creds = appState.credentials else { return }
                    guard let idx = appState.mediaItems.firstIndex(where: { $0.id == media.id }) else { return }
                    do {
                        let updated = try await WordPressClient(credentials: creds)
                            .updateMediaAltText(id: media.id, altText: altText)
                        appState.mediaItems[idx] = updated
                        if appState.selectedMedia?.id == updated.id {
                            appState.selectedMedia = updated
                        }
                    } catch {
                        // Save failed silently — field retains the edited value
                    }
                }
                .id(media.id)
            } else {
                EmptyEditorPlaceholder(section: .media, sectionIsEmpty: false)
            }
        } else if let item = appState.selectedItem {
            PostEditorView(item: item)
        } else if !appState.hasLoadedList || appState.isLoadingList {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyEditorPlaceholder(section: appState.selectedSection,
                                   sectionIsEmpty: appState.sectionIsEmpty)
        }
    }
}

struct EmptyEditorPlaceholder: View {
    let section: SidebarSection
    var sectionIsEmpty: Bool = false

    private var noun: String {
        switch section {
        case .posts: return "post"
        case .pages: return "page"
        case .localDrafts: return "draft"
        case .media: return "image"
        }
    }

    private var icon: String {
        switch section {
        case .posts: return "doc.text"
        case .pages: return "doc.plaintext"
        case .localDrafts: return "pencil"
        case .media: return "photo"
        }
    }

    private var message: String {
        if sectionIsEmpty {
            return "No \(noun)s yet"
        }
        return "Select a \(noun) to edit"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
