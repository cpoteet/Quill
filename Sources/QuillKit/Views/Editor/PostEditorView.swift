import SwiftUI
import WebKit

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
    @State private var cleanTitle: String = ""
    @State private var cleanContent: String = ""
    @State private var loadedItem: PostItem? = nil

    // AI state
    @State private var isAISheetOpen: Bool = false
    @State private var showAIReplaceAlert: Bool = false
    @State private var currentSelectionRect: CGRect? = nil
    private var selectionPill: SelectionPillPanel = SelectionPillPanel()
    private var resultPanel: AIResultPanel = AIResultPanel()

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
                    },
                    onSearchLinks: { query in
                        guard let creds = appState.credentials else { return [] }
                        return try await WordPressClient(credentials: creds).searchLinks(query: query)
                    },
                    onRequestMediaSizes: { mediaId in
                        appState.mediaItems.first(where: { $0.id == mediaId })
                    },
                    onSelectionChanged: { rect in
                        currentSelectionRect = rect
                        handleSelectionChange(rect: rect)
                    }
                )
                .sheet(
                    isPresented: Binding(
                        get: { imageInsertIndex != nil },
                        set: { if !$0 { imageInsertIndex = nil } }
                    )
                ) {
                    if let idx = imageInsertIndex {
                        MediaPickerView { selected in
                            var info: [String: Any] = [
                                "url":     selected.sourceURL,
                                "index":   idx,
                                "mediaId": selected.id,
                            ]
                            if let w = selected.mediaDetails?.width  { info["width"]  = w }
                            if let h = selected.mediaDetails?.height { info["height"] = h }
                            NotificationCenter.default.post(name: .insertMediaURL, object: nil, userInfo: info)
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
        .alert("Replace Content?", isPresented: $showAIReplaceAlert) {
            Button("Continue") { isAISheetOpen = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace your current title and content. Continue?")
        }
        .sheet(isPresented: $isAISheetOpen) {
            if let settings = appState.aiSettings {
                GeneratePostSheet(
                    aiSettings: settings
                ) { generatedTitle, generatedHTML in
                    title = generatedTitle
                    htmlContent = generatedHTML
                    isAISheetOpen = false
                    scheduleAutosave()
                } onCancel: {
                    isAISheetOpen = false
                }
            }
        }
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
            if isDirty {
                Circle()
                    .fill(Color.wpAmber)
                    .frame(width: 6, height: 6)
            }
            if !isRemote {
                Button("Save Draft") { Task { await saveDraft() } }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.plain)
                    .disabled(isSaving)
            } else {
                // ⌘S updates WordPress when editing a remote post/page
                Button("") { Task { await publish() } }
                    .keyboardShortcut("s", modifiers: .command)
                    .hidden()
            }
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
            if appState.aiEnabled {
                Divider().frame(height: 20)
                Button {
                    if title.isEmpty && htmlContent.isEmpty {
                        isAISheetOpen = true
                    } else {
                        showAIReplaceAlert = true
                    }
                } label: {
                    Text("✦")
                        .font(.system(size: 13))
                }
                .help("Generate post with Claude")
            }
        }
        .padding(.horizontal, 16)
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
        .frame(height: 28)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

    private var isDirty: Bool {
        title != cleanTitle || htmlContent != cleanContent
    }

    // MARK: - Load

    private func loadItem() async {
        // Cancel any pending autosave for the old item — flushToDB handles persistence
        autosaveTask?.cancel()

        // Flush dirty state for the previously-loaded item before overwriting editor state
        if let prev = loadedItem, prev.id != item.id, isDirty {
            await flushToDB(for: prev)
        }
        loadedItem = item

        switch item {
        case .remote(let post):
            let wpTitle = post.title.rendered
            let wpContent = post.content.raw ?? post.content.rendered
            title = wpTitle
            htmlContent = wpContent
            lastSavedServerModified = post.modified  // initial value; refreshed below
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
            // Set clean baselines from WP data before checking for a stash
            cleanTitle = wpTitle
            cleanContent = wpContent
            // Restore from stash if one exists (stash content differs from WP → isDirty stays true)
            if let db = try? AppDatabase.production(),
               let snap = try? AutosaveStore(db: db).load(postID: post.id) {
                title = snap.title
                htmlContent = snap.content
                toastMessage = "Unsaved changes restored"
            }
            // Refresh the conflict-detection baseline from the server. The sidebar cache can
            // be stale (WordPress updates modified via plugins, cron, or other clients), which
            // causes false conflicts on the first save. Setting lastSavedServerModified to the
            // live value means the conflict check only fires when the post genuinely changed
            // between when the user opened it and when they saved.
            if let creds = appState.credentials {
                let client = WordPressClient(credentials: creds)
                if let fresh = try? await (post.type == "page"
                    ? client.fetchPage(id: post.id)
                    : client.fetchPost(id: post.id)) {
                    lastSavedServerModified = fresh.modified
                }
            }

        case .local(let draft):
            // Read directly from SQLite to pick up any navigate-flush that updated the draft
            if let db = try? AppDatabase.production(),
               let fresh = try? DraftStore(db: db).load(id: draft.id) {
                let showToast = fresh.title != draft.title || fresh.content != draft.content
                title = fresh.title
                htmlContent = fresh.content
                settings = PostSettings()
                settings.excerpt = fresh.excerpt
                if showToast { toastMessage = "Unsaved changes restored" }
            } else {
                title = draft.title
                htmlContent = draft.content
                settings = PostSettings()
                settings.excerpt = draft.excerpt
            }
            cleanTitle = title
            cleanContent = htmlContent
        }
    }

    // MARK: - Autosave

    private func flushToDB(for oldItem: PostItem) async {
        guard let db = try? AppDatabase.production() else { return }
        switch oldItem {
        case .remote(let post):
            try? AutosaveStore(db: db).save(
                postID: post.id, title: title, content: htmlContent,
                serverModified: lastSavedServerModified)
        case .local(let draft):
            let store = DraftStore(db: db)
            try? store.update(id: draft.id, title: title, content: htmlContent, excerpt: settings.excerpt)
            if let updated = try? store.load(id: draft.id),
               let idx = appState.localDrafts.firstIndex(where: { $0.id == draft.id }) {
                appState.localDrafts[idx] = updated
            }
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(30))
            if !Task.isCancelled && isDirty { await performAutosave() }
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
        switch item {
        case .local: await saveLocalOnly()
        case .remote: await save(status: "draft")
        }
    }

    private func saveLocalOnly() async {
        guard case .local(let draft) = item else { return }
        guard let db = try? AppDatabase.production() else { return }
        isSaving = true
        defer { isSaving = false }
        let store = DraftStore(db: db)
        try? store.update(id: draft.id, title: title, content: htmlContent, excerpt: settings.excerpt)
        if let updated = try? store.load(id: draft.id),
           let idx = appState.localDrafts.firstIndex(where: { $0.id == draft.id }) {
            appState.localDrafts[idx] = updated
        }
        cleanTitle = title
        cleanContent = htmlContent
        toastMessage = "Saved locally"
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
                cleanTitle = title
                cleanContent = htmlContent
                if let db = try? AppDatabase.production() {
                    try? AutosaveStore(db: db).delete(postID: post.id)
                }
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
                appState.localDrafts.removeAll { $0.id == draft.id }
                if draft.type == "page" {
                    appState.pages.insert(created, at: 0)
                    appState.selectedSection = .pages
                } else {
                    appState.posts.insert(created, at: 0)
                    appState.selectedSection = .posts
                }
                appState.selectedItem = .remote(created)
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
                cleanTitle = title
                cleanContent = htmlContent
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
                var info: [String: Any] = ["url": media.sourceURL, "index": 0, "mediaId": media.id]
                if let w = media.mediaDetails?.width  { info["width"]  = w }
                if let h = media.mediaDetails?.height { info["height"] = h }
                NotificationCenter.default.post(name: .insertMediaURL, object: nil, userInfo: info)
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
            // For draft posts, WordPress may update the parent post's modified date when
            // creating an autosave (drafts have no separate revision state). Refresh the
            // baseline so a subsequent save doesn't trigger a false conflict alert.
            if post.status == "draft" || post.status == "pending" {
                if let fresh = try? await (post.type == "page"
                    ? client.fetchPage(id: post.id)
                    : client.fetchPost(id: post.id)) {
                    lastSavedServerModified = fresh.modified
                }
            }
        } catch {
            previewError = error.localizedDescription
        }
    }

    // MARK: - AI selection handling

    private func handleSelectionChange(rect: CGRect?) {
        guard appState.aiEnabled else { return }
        if let rect = rect {
            guard let webView = findWKWebView() else { return }
            selectionPill.show(selectionRect: rect, in: webView) { operation in
                Task { await executeAIOperation(operation) }
            }
        } else {
            selectionPill.hide()
        }
    }

    // MARK: - AI operation execution

    @MainActor
    private func executeAIOperation(_ operation: AIWritingOperation) async {
        guard let settings = appState.aiSettings else { return }
        guard let webView = findWKWebView() as? WKWebView else { return }

        // 1. Tell JS to capture the selection and show the loading placeholder.
        //    JS returns the selected plain text (used as prompt input), or null.
        let selectedText: String = await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("beginAIOperation()") { result, _ in
                continuation.resume(returning: (result as? String) ?? "")
            }
        }
        guard !selectedText.isEmpty else { return }

        // 2. Call Claude (selection operations never use web search — faster + cheaper)
        let client = AnthropicClient(apiKey: settings.apiKey)
        let system = AIPromptBuilder.systemPrompt(styleGuide: settings.styleGuide)
        let userMsg = AIPromptBuilder.operationPrompt(selectedHTML: selectedText, operation: operation)

        do {
            let resultHTML = try await client.complete(
                userMessage: userMsg,
                systemPrompt: system,
                useWebSearch: false
            )
            // 4. Show result in editor — JS replaces loading placeholder with result,
            //    selects it, and returns a bounding rect for panel positioning.
            guard let jsonData = try? JSONEncoder().encode(resultHTML),
                  let jsonStr = String(data: jsonData, encoding: .utf8) else { return }

            let resultRect: CGRect? = await withCheckedContinuation { continuation in
                webView.evaluateJavaScript("showAIResult(\(jsonStr))") { result, _ in
                    if let dict = result as? [String: Any],
                       let x = dict["x"] as? Double,
                       let y = dict["y"] as? Double,
                       let w = dict["width"] as? Double,
                       let h = dict["height"] as? Double {
                        continuation.resume(returning: CGRect(x: x, y: y, width: w, height: h))
                    } else {
                        continuation.resume(returning: currentSelectionRect)
                    }
                }
            }

            // 5. Show accept/discard panel anchored below the result
            let anchorRect = resultRect ?? currentSelectionRect ?? .zero
            resultPanel.show(
                belowRect: anchorRect,
                in: webView,
                onAccept: {
                    webView.evaluateJavaScript("acceptAIResult()", completionHandler: nil)
                    // Trigger contentChanged so Swift gets the accepted HTML
                    webView.evaluateJavaScript(
                        "window.webkit?.messageHandlers?.contentChanged?.postMessage(editor.getHTML())",
                        completionHandler: nil
                    )
                },
                onDiscard: {
                    webView.evaluateJavaScript("discardAIResult()", completionHandler: nil)
                }
            )
        } catch {
            // Restore original text and show a toast
            webView.evaluateJavaScript("discardAIResult()", completionHandler: nil)
            toastMessage = "Claude couldn't complete that — please try again."
        }
    }

    /// Walks the AppKit view hierarchy of the key window to locate the WKWebView
    /// (DroppableWebView subclass) used by EditorView.
    private func findWKWebView() -> NSView? {
        for window in NSApplication.shared.windows where window.isKeyWindow || window.isMainWindow {
            if let found = findWKWebViewRecursive(in: window.contentView) { return found }
        }
        // Fallback: search all windows
        for window in NSApplication.shared.windows {
            if let found = findWKWebViewRecursive(in: window.contentView) { return found }
        }
        return nil
    }

    private func findWKWebViewRecursive(in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if view is WKWebView { return view }
        for sub in view.subviews {
            if let found = findWKWebViewRecursive(in: sub) { return found }
        }
        return nil
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
