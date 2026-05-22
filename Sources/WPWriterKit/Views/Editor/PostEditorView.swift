import SwiftUI

public struct PostEditorView: View {
    @EnvironmentObject private var appState: AppState
    let item: PostItem

    @State private var title: String = ""
    @State private var htmlContent: String = ""
    @State private var settings = PostSettings()
    @State private var isSettingsOpen: Bool = false
    @State private var isSaving: Bool = false
    @State private var saveError: String?
    @State private var conflictAlert: ConflictInfo?
    @State private var autosaveTask: Task<Void, Never>?
    @State private var lastSavedServerModified: String = ""
    @State private var imageInsertIndex: Int? = nil

    public init(item: PostItem) {
        self.item = item
    }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                toolbar
                Divider()
                titleField
                Divider()
                EditorView(
                    html: $htmlContent,
                    onContentChange: { newHTML in
                        htmlContent = newHTML
                        scheduleAutosave()
                    },
                    onInsertImageAt: { index in
                        imageInsertIndex = index
                    }
                )
                .sheet(isPresented: Binding(
                    get: { imageInsertIndex != nil },
                    set: { if !$0 { imageInsertIndex = nil } }
                )) {
                    if let idx = imageInsertIndex {
                        MediaPickerView(mode: .picker) { selected in
                            NotificationCenter.default.post(
                                name: .insertMediaURL,
                                object: nil,
                                userInfo: ["url": selected.sourceURL, "index": idx]
                            )
                            imageInsertIndex = nil
                        }
                        .environmentObject(appState)
                        .frame(minWidth: 600, minHeight: 400)
                    }
                }
            }

            if isSettingsOpen {
                Divider()
                PostSettingsPanel(
                    settings: $settings,
                    categories: appState.categories,
                    tags: appState.tags
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSettingsOpen)
        .alert("Conflict Detected", isPresented: Binding(
            get: { conflictAlert != nil },
            set: { if !$0 { conflictAlert = nil } }
        )) {
            if conflictAlert != nil {
                Button("Keep Local") { saveToWordPress(force: true) }
                Button("Use Server") {
                    if case .remote(let post) = item {
                        loadFromServer(postID: post.id)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text("This post was modified on the server since you last fetched it.")
        }
        .task(id: item.id) { await loadItem() }
        .onDisappear { autosaveTask?.cancel() }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            if let error = saveError {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            Spacer()
            Button("Save Draft") { Task { await saveDraft() } }
                .disabled(isSaving)
            Button("Preview") { Task { await openPreview() } }
                .disabled(isSaving || !isRemote)
            Button(publishButtonTitle) { Task { await publish() } }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            Divider().frame(height: 20)
            Button {
                withAnimation { isSettingsOpen.toggle() }
            } label: {
                Image(systemName: "sidebar.right")
            }
            .help("Post Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var titleField: some View {
        TextField("Title", text: $title)
            .font(.system(size: 22, weight: .semibold))
            .textFieldStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .onChange(of: title) { _ in scheduleAutosave() }
    }

    private var publishButtonTitle: String {
        switch item {
        case .remote(let p): return p.status == "publish" ? "Update" : "Publish"
        case .local: return "Publish"
        }
    }

    private var isRemote: Bool {
        if case .remote = item { return true }
        return false
    }

    // MARK: - Load

    private func loadItem() async {
        switch item {
        case .remote(let post):
            title = post.title.rendered
            htmlContent = post.content.raw ?? post.content.rendered
            lastSavedServerModified = post.modified
            settings.status = post.status
            settings.categoryIDs = Set(post.categories)
            settings.tagIDs = Set(post.tags)
            settings.featuredMediaID = post.featuredMedia
        case .local(let draft):
            title = draft.title
            htmlContent = draft.content
            settings.excerpt = draft.excerpt
        }
    }

    // MARK: - Autosave

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(30))
            if !Task.isCancelled { await performAutosave() }
        }
    }

    private func performAutosave() async {
        guard let db = try? AppDatabase.production() else { return }
        switch item {
        case .remote(let post):
            let store = AutosaveStore(db: db)
            try? store.save(postID: post.id, title: title, content: htmlContent, serverModified: lastSavedServerModified)
        case .local(let draft):
            let store = DraftStore(db: db)
            try? store.update(id: draft.id, title: title, content: htmlContent, excerpt: settings.excerpt)
        }
    }

    // MARK: - Save / Publish

    private func saveDraft() async {
        await save(status: "draft")
    }

    private func publish() async {
        await save(status: settings.status == "future" ? "future" : "publish")
    }

    private func save(status: String, force: Bool = false) async {
        guard let creds = appState.credentials else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let client = WordPressClient(credentials: creds)
        let payload = PostPayload(
            title: title,
            content: htmlContent,
            excerpt: settings.excerpt,
            status: status,
            date: settings.publishDate.map { ISO8601DateFormatter().string(from: $0) },
            featuredMedia: settings.featuredMediaID > 0 ? settings.featuredMediaID : nil,
            categories: Array(settings.categoryIDs),
            tags: Array(settings.tagIDs)
        )

        do {
            switch item {
            case .remote(let post):
                if !force {
                    let current = try await client.fetchPost(id: post.id)
                    if current.modified != lastSavedServerModified {
                        conflictAlert = ConflictInfo(postID: post.id)
                        return
                    }
                }
                let updated = try await client.updatePost(id: post.id, payload: payload)
                lastSavedServerModified = updated.modified
            case .local(let draft):
                let created = try await client.createPost(payload)
                let db = try AppDatabase.production()
                try DraftStore(db: db).delete(id: draft.id)
                lastSavedServerModified = created.modified
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func saveToWordPress(force: Bool) {
        Task { await save(status: settings.status, force: true) }
    }

    private func loadFromServer(postID: Int) {
        Task {
            guard let creds = appState.credentials else { return }
            let client = WordPressClient(credentials: creds)
            if let post = try? await client.fetchPost(id: postID) {
                title = post.title.rendered
                htmlContent = post.content.raw ?? post.content.rendered
                lastSavedServerModified = post.modified
            }
        }
    }

    private func openPreview() async {
        guard let creds = appState.credentials,
              case .remote(let post) = item else { return }
        let client = WordPressClient(credentials: creds)
        let payload = PostPayload(title: title, content: htmlContent, excerpt: settings.excerpt, status: post.status)
        if let autosave = try? await client.createAutosave(postID: post.id, payload: payload),
           let url = URL(string: autosave.link + "?preview=true") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct ConflictInfo {
    let postID: Int
}
