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
    @State private var previewError: String?
    @State private var conflictAlert: ConflictInfo?
    @State private var autosaveTask: Task<Void, Never>?
    @State private var lastSavedServerModified: String = ""
    @State private var imageInsertIndex: Int? = nil
    @State private var toastMessage: String? = nil

    public init(item: PostItem) {
        self.item = item
    }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                toolbar
                Divider()
                if saveError != nil { errorBanner }
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
                    },
                    onImageFilesDropped: { urls in
                        Task { await handleDroppedImages(urls) }
                    }
                )
                .sheet(
                    isPresented: Binding(
                        get: { imageInsertIndex != nil },
                        set: { if !$0 { imageInsertIndex = nil } }
                    )
                ) {
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
                    postType: postType,
                    categories: appState.categories,
                    tags: appState.tags,
                    pages: availableParentPages
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSettingsOpen)
        .toast(message: $toastMessage)
        .alert(
            "Conflict Detected",
            isPresented: Binding(
                get: { conflictAlert != nil },
                set: { if !$0 { conflictAlert = nil } }
            )
        ) {
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
        .alert(
            "Preview Failed",
            isPresented: Binding(
                get: { previewError != nil },
                set: { if !$0 { previewError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(previewError ?? "")
        }
        .task(id: item.id) { await loadItem() }
        .onDisappear { autosaveTask?.cancel() }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            // #5 Breadcrumb
            HStack(spacing: 4) {
                Text(breadcrumbSection)
                    .foregroundStyle(.tertiary)
                Text("›")
                    .foregroundStyle(.tertiary)
                Text(title.isEmpty ? "Untitled" : title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.system(size: 12))
            Spacer()
            // #2 Button hierarchy
            Button("Save Draft") { Task { await saveDraft() } }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.plain)
                .disabled(isSaving)
            if isRemote {
                Button("Preview") { Task { await openPreview() } }
                    .buttonStyle(.bordered)
                    .disabled(isSaving)
            }
            Button(publishButtonTitle) { Task { await publish() } }
                .keyboardShortcut("p", modifiers: [.command, .shift])
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

    // #5 Breadcrumb section label
    private var breadcrumbSection: String {
        switch item {
        case .remote(let post): return post.type == "page" ? "Pages" : "Posts"
        case .local(let draft): return draft.type == "page" ? "Pages" : "Posts"
        }
    }

    // #1 Dismissible amber error banner
    private var errorBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.wpAmber)
                .font(.system(size: 13))
            Text(saveError ?? "")
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
            Button {
                saveError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.wpAmber.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var titleField: some View {
        TitleTextField(
            placeholder: "Title",
            text: $title,
            nsFont: .systemFont(ofSize: 22, weight: .semibold)
        )
        .frame(height: 44)
        .padding(.horizontal, 24)
        .onChange(of: title) { _ in scheduleAutosave() }
    }

    private var publishButtonTitle: String {
        switch settings.status {
        case "draft": return "Publish Draft"
        case "future": return "Schedule"
        case "publish":
            if case .remote(let p) = item, p.status == "publish" { return "Update" }
            return "Publish"
        default: return "Publish"
        }
    }

    private var isRemote: Bool {
        if case .remote = item { return true }
        return false
    }

    private var postType: String {
        switch item {
        case .remote(let post): return post.type
        case .local(let draft): return draft.type
        }
    }

    private var availableParentPages: [WPPost] {
        guard case .remote(let post) = item else { return appState.pages }
        return appState.pages.filter { $0.id != post.id }
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
            settings.slug = post.slug
            settings.commentStatus = post.commentStatus
            settings.parentID = post.parent
            if post.status == "future" {
                settings.publishDate = parseWPDate(post.dateGmt.isEmpty ? post.date : post.dateGmt)
            }
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
            try? store.save(
                postID: post.id, title: title, content: htmlContent, serverModified: lastSavedServerModified)
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
        await save(status: settings.status)
    }

    private func save(status: String, force: Bool = false) async {
        guard let creds = appState.credentials else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let client = WordPressClient(credentials: creds)

        // Create any pending new categories/tags before building the payload
        do {
            for name in settings.newCategoryNames {
                let cat = try await client.createCategory(name: name)
                settings.categoryIDs.insert(cat.id)
                appState.categories.append(cat)
            }
            settings.newCategoryNames = []

            for name in settings.newTagNames {
                let tag = try await client.createTag(name: name)
                settings.tagIDs.insert(tag.id)
                appState.tags.append(tag)
            }
            settings.newTagNames = []
        } catch {
            saveError = "Failed to create taxonomy: \(error.localizedDescription)"
            return
        }

        let payload = PostPayload(
            title: title,
            content: htmlContent,
            excerpt: settings.excerpt,
            status: status,
            dateGmt: settings.publishDate.map { ISO8601DateFormatter().string(from: $0) },
            featuredMedia: settings.featuredMediaID > 0 ? settings.featuredMediaID : nil,
            categories: Array(settings.categoryIDs),
            tags: Array(settings.tagIDs),
            slug: settings.slug.isEmpty ? nil : settings.slug,
            commentStatus: settings.commentStatus,
            parent: postType == "page" ? settings.parentID : nil
        )

        do {
            switch item {
            case .remote(let post):
                if !force {
                    let current =
                        post.type == "page"
                        ? try await client.fetchPage(id: post.id)
                        : try await client.fetchPost(id: post.id)
                    if current.modified != lastSavedServerModified {
                        conflictAlert = ConflictInfo(postID: post.id)
                        return
                    }
                }
                let updated =
                    post.type == "page"
                    ? try await client.updatePage(id: post.id, payload: payload)
                    : try await client.updatePost(id: post.id, payload: payload)
                lastSavedServerModified = updated.modified
                // Keep appState cache fresh so reopening the post loads the latest date/status
                if post.type == "page" {
                    if let idx = appState.pages.firstIndex(where: { $0.id == updated.id }) {
                        appState.pages[idx] = updated
                    }
                } else {
                    if let idx = appState.posts.firstIndex(where: { $0.id == updated.id }) {
                        appState.posts[idx] = updated
                    }
                }
            case .local(let draft):
                let created =
                    draft.type == "page"
                    ? try await client.createPage(payload)
                    : try await client.createPost(payload)
                let db = try AppDatabase.production()
                try DraftStore(db: db).delete(id: draft.id)
                lastSavedServerModified = created.modified
            }
            settings.status = status
            if status != "future" { settings.publishDate = nil }
            toastMessage = status == "publish" ? "Published" : status == "future" ? "Scheduled" : "Draft saved"
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func saveToWordPress(force: Bool) {
        Task { await save(status: settings.status, force: true) }
    }

    private func loadFromServer(postID: Int) {
        Task {
            guard let creds = appState.credentials,
                case .remote(let current) = item
            else { return }
            let client = WordPressClient(credentials: creds)
            let fetched =
                current.type == "page"
                ? try? await client.fetchPage(id: postID)
                : try? await client.fetchPost(id: postID)
            if let post = fetched {
                title = post.title.rendered
                htmlContent = post.content.raw ?? post.content.rendered
                lastSavedServerModified = post.modified
            }
        }
    }

    // MARK: - Drag & Drop

    private func handleDroppedImages(_ urls: [URL]) async {
        guard let creds = appState.credentials else { return }
        let client = WordPressClient(credentials: creds)
        for url in urls {
            guard url.isFileURL else { continue }
            do {
                let data = try Data(contentsOf: url)
                let mime = imageMimeType(for: url.pathExtension.lowercased())
                let media = try await client.uploadMedia(
                    data: data, filename: url.lastPathComponent, mimeType: mime
                )
                NotificationCenter.default.post(
                    name: .insertMediaURL,
                    object: nil,
                    userInfo: ["url": media.sourceURL, "index": 0]
                )
                toastMessage = "Image inserted"
            } catch {
                saveError = "Upload failed: \(error.localizedDescription)"
            }
        }
    }

    private func imageMimeType(for ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "tiff", "tif": return "image/tiff"
        default: return "image/jpeg"
        }
    }

    private func openPreview() async {
        guard let creds = appState.credentials,
            case .remote(let post) = item
        else { return }
        let client = WordPressClient(credentials: creds)
        let payload = PostPayload(title: title, content: htmlContent, excerpt: settings.excerpt, status: post.status)
        do {
            let autosave =
                post.type == "page"
                ? try await client.createPageAutosave(postID: post.id, payload: payload)
                : try await client.createAutosave(postID: post.id, payload: payload)
            let linkBase = autosave.link ?? post.link
            guard let url = URL(string: linkBase + "?preview=true") else {
                previewError = "WordPress returned an invalid preview URL: \(linkBase)"
                return
            }
            NSWorkspace.shared.open(url)
        } catch {
            previewError = error.localizedDescription
        }
    }

    private func parseWPDate(_ iso: String) -> Date? {
        // Try ISO8601 with timezone first (handles date_gmt "2026-05-30T14:00:00Z")
        let iso8601 = ISO8601DateFormatter()
        if let date = iso8601.date(from: iso) { return date }
        // Fallback: no timezone suffix — treat as UTC (date_gmt format on some WP versions)
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return df.date(from: iso)
    }
}

private struct ConflictInfo {
    let postID: Int
}
