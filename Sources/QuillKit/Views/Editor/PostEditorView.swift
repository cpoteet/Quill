import SwiftUI
import WebKit

public struct PostEditorView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var services: AppServices
    let item: PostItem

    @State private var title: String = ""
    @State private var htmlContent: String = ""
    @State private var footnotesMeta: String = ""
    @State private var settings = PostSettings()
    @State private var stats = PostStats()
    @State private var isSettingsOpen: Bool = false
    @State private var isSaving: Bool = false
    @State private var saveError: String?
    @State private var previewError: String?
    @State private var showConflictAlert: Bool = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var lastSavedServerModified: String = ""
    @State private var showImagePicker = false
    @State private var showGallerySheet = false
    @State private var toastMessage: String? = nil
    @State private var toastIsError: Bool = false
    // Bumped on every presentToast() call so the toast's dismiss timer restarts even when
    // two consecutive toasts share identical text (e.g. two "Image inserted" toasts from a
    // multi-file drop) — keying the timer on the message string alone wouldn't detect that.
    @State private var toastToken: Int = 0
    // Non-nil while a dropped image is being converted/uploaded; drives the bottom pill.
    @State private var uploadStatus: String? = nil
    // Tail of the drop queue. Each new drop awaits it, so batches never interleave.
    @State private var dropTask: Task<Void, Never>? = nil
    @State private var cleanTitle: String = ""
    @State private var cleanContent: String = ""
    @State private var cleanFootnotes: String = ""
    @State private var loadedItem: PostItem? = nil
    @State private var editorReady = false
    @State private var contentLoaded = false
    @State private var showDiscardAlert: Bool = false
    @State private var contentSyncPending: Bool = false
    @State private var contentLoadFailed: Bool = false
    @State private var blockRiskAlarm: BlockRiskAlarm? = nil

    private static let iso8601Formatter: ISO8601DateFormatter = ISO8601DateFormatter()

    // Parses date_gmt values without a timezone suffix (some WP versions); treated as UTC.
    private static let utcNoSuffixFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return df
    }()

    // AI state
    @State private var isAISheetOpen: Bool = false
    @State private var showAIReplaceAlert: Bool = false
    @State private var currentSelectionRect: CGRect? = nil
    @State private var hasTextSelection: Bool = false
    @State private var editorWebView: WKWebView? = nil
    @State private var resultPanel: AIResultPanel = AIResultPanel()

    // Evaluation state
    @State private var showEvaluationPanel: Bool = false
    @State private var isEvaluating: Bool = false
    @State private var evaluationResult: EvaluationResult? = nil
    @State private var evaluationError: String? = nil
    @State private var evaluationTask: Task<Void, Never>? = nil

    public init(item: PostItem) {
        self.item = item
    }

    public var body: some View {
        VStack(spacing: 0) {
            editorHeader
            // The alarm sits above the save error, which refers to it as
            // "the warning above".
            if let alarm = blockRiskAlarm { blockRiskBanner(alarm) }
            if saveError != nil { errorBanner }
            ZStack {
                EditorView(
                    html: $htmlContent,
                    footnotes: footnotesMeta,
                    contentSyncPending: $contentSyncPending,
                    onContentChange: { newHTML in
                        htmlContent = newHTML
                        scheduleAutosave()
                    },
                    onEditorReady: {
                        withAnimation(.easeOut(duration: 0.15)) { editorReady = true }
                    },
                    onInsertImage: {
                        showImagePicker = true
                    },
                    onInsertGallery: {
                        showGallerySheet = true
                    },
                    onImageFilesDropped: { urls in
                        // Serialized: overlapping drops share `uploadStatus`, so a second
                        // batch must not clear the pill while the first is still uploading.
                        let previous = dropTask
                        dropTask = Task {
                            await previous?.value
                            await handleDroppedImages(urls)
                        }
                    },
                    onDropRejected: { message in
                        presentToast(message, isError: true)
                    },
                    onSearchLinks: { query in
                        guard let creds = appState.credentials else { return [] }
                        return try await WordPressClient(credentials: creds).searchLinks(query: query)
                    },
                    onRequestMediaSizes: { mediaId in
                        if let cached = appState.mediaItems.first(where: { $0.id == mediaId }) {
                            return cached
                        }
                        guard let creds = appState.credentials else { return nil }
                        let fetched = try? await WordPressClient(credentials: creds).fetchMediaItem(id: mediaId)
                        if let fetched {
                            await MainActor.run { appState.mediaItems.append(fetched) }
                        }
                        return fetched
                    },
                    onSelectionChanged: { rect in
                        currentSelectionRect = rect
                        handleSelectionChange(rect: rect)
                    },
                    onStatsChanged: { words, characters in
                        stats = PostStats(words: words, characters: characters)
                    },
                    onBlocksAtRisk: { names in
                        blockRiskAlarm = Self.nextAlarm(from: blockRiskAlarm, names: names)
                    },
                    onFootnotesChange: { footnotesMeta = $0 },
                    onWebViewCreated: { webView in
                        editorWebView = webView
                    },
                    onAIOperation: { operation in
                        Task { await executeAIOperation(operation) }
                    },
                    onTriggerGenerate: {
                        let trimmed = htmlContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        let titleIsEmpty = title.isEmpty || title == "Untitled"
                        let contentIsEmpty = titleIsEmpty && (trimmed.isEmpty || trimmed == "<p></p>")
                        if contentIsEmpty {
                            isAISheetOpen = true
                        } else {
                            showAIReplaceAlert = true
                        }
                    },
                    onTriggerEvaluate: {
                        if !isEvaluating {
                            isSettingsOpen = false
                            showEvaluationPanel = true
                            if evaluationResult == nil && evaluationError == nil {
                                evaluationTask = Task { await executeEvaluation() }
                            }
                        }
                    },
                    aiEnabled: appState.aiEnabled,
                    hasTextSelection: hasTextSelection
                )
                if !editorReady || !contentLoaded {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Loading editor…")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                }
            }
            .sheet(isPresented: $showImagePicker) {
                MediaPickerView(onSelect: { selected in
                    // Ensure item is in appState so requestMediaSizes can find it
                    if !appState.mediaItems.contains(where: { $0.id == selected.id }) {
                        appState.mediaItems.append(selected)
                    }
                    var info: [String: Any] = [
                        "url":     selected.sourceURL,
                        "mediaId": selected.id,
                    ]
                    if let w = selected.mediaDetails?.width  { info["width"]  = w }
                    if let h = selected.mediaDetails?.height { info["height"] = h }
                    if !selected.altText.isEmpty { info["alt"] = selected.altText }
                    NotificationCenter.default.post(name: .insertMediaURL, object: nil, userInfo: info)
                    showImagePicker = false
                }, onCancel: {
                    showImagePicker = false
                })
                .environmentObject(appState)
                .frame(minWidth: 600, minHeight: 400)
            }
            .sheet(isPresented: $showGallerySheet) {
                GallerySheet(onInsert: { selections, columns, cropped, linkTo, sizeSlug in
                    let imagePayload: [[String: Any]] = selections.map { sel in
                        [
                            "id": sel.media.id,
                            "url": sel.media.sizedURL(for: sizeSlug),
                            "fullUrl": sel.media.sourceURL,
                            "alt": sel.alt,
                            "caption": sel.caption,
                        ]
                    }
                    let info: [String: Any] = [
                        "images": imagePayload,
                        "columns": columns,
                        "cropped": cropped,
                        "linkTo": linkTo,
                        "sizeSlug": sizeSlug,
                    ]
                    NotificationCenter.default.post(name: .insertGalleryData, object: nil, userInfo: info)
                    showGallerySheet = false
                }, onCancel: {
                    showGallerySheet = false
                })
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 480)
            }
        }
        .uploadStatus($uploadStatus)
        .toast(message: $toastMessage, isError: $toastIsError, token: toastToken)
        .alert("Revert to Server Version?", isPresented: $showDiscardAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Revert", role: .destructive) { discardChanges() }
        } message: {
            Text("Your unsaved changes will be lost.")
        }
        .alert("Replace Content?", isPresented: $showAIReplaceAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Continue") { isAISheetOpen = true }
        } message: {
            Text("This will replace your current title and content.")
        }
        .sheet(isPresented: $isAISheetOpen) {
            if let settings = appState.aiSettings {
                GeneratePostSheet(
                    aiSettings: settings
                ) { generatedTitle, generatedHTML in
                    title = generatedTitle
                    contentSyncPending = true
                    htmlContent = generatedHTML
                    isAISheetOpen = false
                    scheduleAutosave()
                } onCancel: {
                    isAISheetOpen = false
                }
            }
        }
        .alert("Conflict Detected", isPresented: $showConflictAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Use Server") {
                if case .remote(let post) = item {
                    loadFromServer(postID: post.id)
                }
            }
            Button("Keep Local") { saveToWordPress() }
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
        .onChange(of: item.id) { _ in
            contentLoaded = false
            evaluationTask?.cancel()
            evaluationTask = nil
            showEvaluationPanel = false
            isEvaluating = false
            evaluationResult = nil
            evaluationError = nil
        }
        .onChange(of: showEvaluationPanel) { open in
            editorWebView?.evaluateJavaScript("window.setEvaluationPanelOpen?.(\(open))", completionHandler: nil)
        }
        .inspector(isPresented: Binding(
            get: { isSettingsOpen || showEvaluationPanel },
            set: { newValue in
                if !newValue {
                    isSettingsOpen = false
                    showEvaluationPanel = false
                }
            }
        )) {
            inspectorContent
                .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
        }
        .navigationTitle(title.isEmpty ? "Untitled" : title)
        .toolbar {
            ToolbarItem {
                Image(systemName: statusSymbol(statusKey))
                    .foregroundStyle(Color.statusColor(statusKey))
                    .help(statusBadgeLabel)
                    .accessibilityLabel("Status: \(statusBadgeLabel)")
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItemGroup {
                if !isRemote {
                    Button("Save Draft") { Task { await saveDraft() } }
                        .disabled(isSaving)
                }
                if isRemote && isDirty {
                    Button("Revert") { showDiscardAlert = true }
                }
                if isRemote {
                    Button("Preview") { Task { await openPreview() } }
                        .disabled(isSaving)
                }
            }
            ToolbarSpacer(.fixed)
            ToolbarItem {
                Button(publishButtonTitle) { Task { await publish() } }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .disabled(isSaving)
            }
            ToolbarSpacer(.fixed)
            ToolbarItem {
                Button {
                    withAnimation {
                        if showEvaluationPanel {
                            showEvaluationPanel = false
                        } else {
                            isSettingsOpen.toggle()
                        }
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Post Settings")
                .accessibilityLabel("Post Settings")
            }
        }
        .background {
            Button("") { Task { isRemote ? await publish() : await saveDraft() } }
                .keyboardShortcut("s", modifiers: .command)
                .hidden()
                .disabled(isSaving)
        }
        .task(id: item.id) { await loadItem() }
        .onDisappear {
            autosaveTask?.cancel()
            evaluationTask?.cancel()
            if let loadedItem, isDirty {
                Task { await flushToDB(for: loadedItem) }
            }
        }
        .onChange(of: appState.triggerFindBar) { newValue in
            guard newValue else { return }
            appState.triggerFindBar = false
            editorWebView?.evaluateJavaScript("openFindBar()", completionHandler: nil)
        }
        .onChange(of: appState.triggerPasteMarkdown) { newValue in
            guard newValue else { return }
            appState.triggerPasteMarkdown = false
            pasteAsMarkdown()
        }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if showEvaluationPanel {
            EvaluationPanel(
                state: evaluationPanelState,
                onReEvaluate: { if !isEvaluating { evaluationTask = Task { await executeEvaluation() } } },
                onFindingSelected: { quote in
                    guard let data = try? JSONEncoder().encode(quote),
                          let json = String(data: data, encoding: .utf8) else { return }
                    if let wv = editorWebView { wv.window?.makeFirstResponder(wv) }
                    editorWebView?.evaluateJavaScript(
                        "window.findAndSelectText(\(json))", completionHandler: nil)
                }
            )
        } else {
            PostSettingsPanel(
                settings: $settings,
                postType: postType,
                isLocalDraft: !isRemote,
                categories: appState.categories,
                tags: appState.tags,
                pages: availableParentPages,
                stats: stats
            )
        }
    }

    private var editorHeader: some View {
        titleField
    }

    private var statusBadgeLabel: String {
        if case .local = item { return "Local Draft" }
        switch settings.status {
        case .publish:  return "Published"
        case .draft:    return "Draft"
        case .future:   return "Scheduled"
        case .pending:  return "Pending Review"
        case .private:  return "Private"
        }
    }

    private var statusKey: String {
        if case .local(let d) = item { return "local-\(d.type)" }
        return settings.status.rawValue
    }

    // Distinct danger styling, not the amber of a recoverable save error:
    // this is content about to be deleted.
    private func blockRiskBanner(_ alarm: BlockRiskAlarm) -> some View {
        let danger = alarm.stage != .saved
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: danger ? "exclamationmark.triangle.fill" : "clock.arrow.circlepath")
                .foregroundStyle(danger ? Color.red : Color.secondary)
                .font(.system(size: 13))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                if !alarm.title.isEmpty {
                    Text(alarm.title)
                        .font(.callout.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(boldingNames(in: alarm.body, names: alarm.names))
                    .font(.callout)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                if alarm.blocksSaving {
                    Button("Save anyway, I understand") {
                        blockRiskAlarm = BlockRiskAlarm(names: alarm.names, stage: .acknowledged)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 9)
                }
            }
            Spacer(minLength: 8)
            if alarm.stage == .saved {
                Button { blockRiskAlarm = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                        .accessibilityLabel("Dismiss")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background((danger ? Color.red : Color.secondary).opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func boldingNames(in text: String, names: [String]) -> AttributedString {
        var attributed = AttributedString(text)
        for display in names.map(BlockRiskAlarm.displayName(for:)) {
            var search = attributed.startIndex..<attributed.endIndex
            while let found = attributed[search].range(of: display) {
                attributed[found].inlinePresentationIntent = .stronglyEmphasized
                search = found.upperBound..<attributed.endIndex
            }
        }
        return attributed
    }

    // #1 Dismissible error banner
    private var errorBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 13))
            Text(saveError ?? "")
                .font(.callout)
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
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
        var isPublishedRemote = false
        if case .remote(let p) = item, p.status == PostStatus.publish.rawValue { isPublishedRemote = true }
        return Self.publishButtonTitle(status: settings.status, isPublishedRemote: isPublishedRemote)
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

    // An untouched body saves the original bytes back verbatim, so the alarm
    // only has to block once an edit could squash something.
    private var alarmBlocksSaving: Bool {
        blockRiskAlarm?.blocksSaving == true && htmlContent != cleanContent
    }

    private var isDirty: Bool {
        title != cleanTitle || htmlContent != cleanContent || footnotesMeta != cleanFootnotes
    }

    // The editor reports its at-risk list on every load and code-view edit,
    // empty included, so a post the user repaired can clear its own banner.
    nonisolated static func nextAlarm(from current: BlockRiskAlarm?, names: [String]) -> BlockRiskAlarm? {
        guard !names.isEmpty else { return nil }
        if let current, current.names == names, current.stage != .unacknowledged { return current }
        return BlockRiskAlarm(names: names, stage: .unacknowledged)
    }

    private func presentToast(_ text: String, isError: Bool = false) {
        toastMessage = text
        toastIsError = isError
        toastToken += 1
    }

    /// Backs the Edit ▸ Paste as Markdown command. Reads the clipboard here in Swift
    /// and hands the text to `window.insertMarkdown`, so this never goes through the
    /// web view's own paste handling — an ordinary ⌘V is completely unaffected.
    private func pasteAsMarkdown() {
        guard let webView = editorWebView else { return }
        guard let text = NSPasteboard.general.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            presentToast("The clipboard has no text to paste.", isError: true)
            return
        }
        guard let encoded = try? JSONEncoder().encode(text),
              let jsString = String(data: encoded, encoding: .utf8)
        else { return }

        webView.evaluateJavaScript("insertMarkdown(\(jsString))") { result, _ in
            guard let status = result as? String, status != "ok" else { return }
            let message: String
            switch status {
            case "footnote":    message = "Markdown can't be pasted inside a footnote."
            case "code-block":  message = "Markdown can't be pasted inside a code block."
            case "code-view":   message = "Switch out of code view to paste Markdown."
            case "parse-error": message = "That clipboard text couldn't be read as Markdown."
            default:            message = "The clipboard has no text to paste."
            }
            presentToast(message, isError: true)
        }
    }

    // MARK: - Load

    private func loadItem() async {
        let requestedItem = item

        // Cancel any pending autosave for the old item — flushToDB handles persistence
        autosaveTask?.cancel()

        // Flush dirty state for the previously-loaded item before overwriting editor state
        if let prev = loadedItem, prev.id != item.id, isDirty {
            await flushToDB(for: prev)
        }
        loadedItem = item
        // Every per-post banner and save guard resets here, for both branches.
        // A local draft opened after a remote post failed to load must not
        // inherit its blocked state. The editor re-posts blocksAtRisk after the
        // content below lands, so a real alarm for this post still arrives.
        saveError = nil
        blockRiskAlarm = nil
        contentLoadFailed = false

        switch requestedItem {
        case .remote(let post):
            applyRemotePost(post)

            let loadedPost: WPPost
            if let creds = appState.credentials {
                let client = WordPressClient(credentials: creds)
                do {
                    loadedPost = try await (post.type == "page"
                        ? client.fetchPage(id: post.id)
                        : client.fetchPost(id: post.id))
                } catch is CancellationError {
                    return
                } catch {
                    // Bail out here (instead of falling through to the staleness guard below)
                    // if the user has already switched away — otherwise this now-irrelevant
                    // task's failure would stomp contentLoadFailed/saveError for whichever
                    // post is currently displayed.
                    guard !Task.isCancelled, loadedItem == requestedItem else { return }
                    loadedPost = post
                    contentLoadFailed = true
                    saveError = "Couldn't load the full post (showing cached preview only — it may be missing content). Reopen this post once your connection is back before making changes."
                }
            } else {
                loadedPost = post
            }

            guard !Task.isCancelled, loadedItem == requestedItem else { return }
            lastSavedServerModified = loadedPost.modified
            applyRemotePost(loadedPost)

            // Refresh taxonomy cache if the post references tags/categories we don't have locally
            if let creds = appState.credentials, post.type != "page" {
                let knownTagIDs = Set(appState.tags.map(\.id))
                let knownCatIDs = Set(appState.categories.map(\.id))
                let missingTags = !Set(loadedPost.tags).subtracting(knownTagIDs).isEmpty
                let missingCats = !Set(loadedPost.categories).subtracting(knownCatIDs).isEmpty
                if missingTags || missingCats {
                    let client = WordPressClient(credentials: creds)
                    if missingTags, let allTags = try? await client.fetchAllTags() {
                        try? services.taxonomyCache.saveTags(allTags)
                        appState.tags = allTags
                    }
                    if missingCats, let allCats = try? await client.fetchAllCategories() {
                        try? services.taxonomyCache.saveCategories(allCats)
                        appState.categories = allCats
                    }
                }
            }
            guard !Task.isCancelled, loadedItem == requestedItem else { return }

            // Restore from stash if one exists (stash content differs from WP → isDirty stays true)
            if let snap = try? services.autosaveStore.load(postID: post.id) {
                if shouldRestoreAutosave(snap, over: loadedPost) {
                    title = snap.title
                    htmlContent = snap.content
                    footnotesMeta = snap.footnotes
                    presentToast("Unsaved changes restored")
                } else {
                    try? services.autosaveStore.delete(postID: post.id)
                }
            }
            contentLoaded = true

        case .local(let draft):
            // Read directly from SQLite to pick up any navigate-flush that updated the draft
            if let fresh = try? services.draftStore.load(id: draft.id) {
                let showToast = fresh.title != draft.title || fresh.content != draft.content
                title = fresh.title
                htmlContent = fresh.content
                footnotesMeta = fresh.footnotes
                settings = PostSettings()
                settings.excerpt = fresh.excerpt
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if showToast { presentToast("Unsaved changes restored") }
            } else {
                title = draft.title
                htmlContent = draft.content
                footnotesMeta = draft.footnotes
                settings = PostSettings()
                settings.excerpt = draft.excerpt
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            cleanTitle = title
            cleanContent = htmlContent
            cleanFootnotes = footnotesMeta
            contentLoaded = true
        }
    }

    private func applyRemotePost(_ post: WPPost) {
        let wpTitle = post.title.decodedTitle
        let wpContent = post.content.editorHTML
        title = wpTitle
        htmlContent = wpContent
        footnotesMeta = post.footnotes
        lastSavedServerModified = post.modified
        settings.status = PostStatus(rawValue: post.status) ?? .draft
        settings.categoryIDs = Set(post.categories)
        settings.tagIDs = Set(post.tags)
        settings.featuredMediaID = post.featuredMedia
        settings.slug = post.slug
        settings.commentStatus = post.commentStatus
        settings.parentID = post.parent
        settings.excerpt = post.excerpt.excerptText
        settings.publishDate = PostStatus(rawValue: post.status) == .future
            ? parseWPDate(post.dateGmt.isEmpty ? post.date : post.dateGmt)
            : nil
        cleanTitle = wpTitle
        cleanContent = wpContent
        cleanFootnotes = post.footnotes
    }

    private func shouldRestoreAutosave(_ snap: AutosaveSnapshot, over post: WPPost) -> Bool {
        let snapContent = snap.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverContent = post.content.editorHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        if snapContent.isEmpty,
           !serverContent.isEmpty,
           snap.title == post.title.decodedTitle {
            return false
        }
        return true
    }

    // MARK: - Autosave

    private func flushToDB(for oldItem: PostItem) async {
        // Same reason as performAutosave: the squashed content must not reach the store.
        if alarmBlocksSaving { return }
        switch oldItem {
        case .remote(let post):
            try? services.autosaveStore.save(
                postID: post.id, title: title, content: htmlContent,
                footnotes: footnotesMeta, serverModified: lastSavedServerModified)
        case .local(let draft):
            try? services.draftStore.update(id: draft.id, title: title, content: htmlContent, excerpt: settings.excerpt, footnotes: footnotesMeta)
            if let updated = try? services.draftStore.load(id: draft.id),
               let idx = appState.localDrafts.firstIndex(where: { $0.id == draft.id }) {
                appState.localDrafts[idx] = updated
            }
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let expectedItemID = item.id
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(30))
            if !Task.isCancelled && isDirty && item.id == expectedItemID { await performAutosave() }
        }
    }

    private func performAutosave() async {
        // Or the squashed content silently becomes the local draft.
        if alarmBlocksSaving { return }
        switch item {
        case .remote(let post):
            try? services.autosaveStore.save(
                postID: post.id, title: title, content: htmlContent,
                footnotes: footnotesMeta, serverModified: lastSavedServerModified)
        case .local(let draft):
            try? services.draftStore.update(id: draft.id, title: title, content: htmlContent, excerpt: settings.excerpt, footnotes: footnotesMeta)
        }
    }

    // MARK: - Save / Publish

    private func saveDraft() async {
        switch item {
        case .local: await saveLocalOnly()
        case .remote: await save(status: .draft)
        }
    }

    private func saveLocalOnly() async {
        guard case .local(let draft) = item else { return }
        guard !alarmBlocksSaving else {
            saveError = "Can't save yet. Quill found content it can't preserve in this post, see the warning above."
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try services.draftStore.update(id: draft.id, title: title, content: htmlContent, excerpt: settings.excerpt, footnotes: footnotesMeta)
            if let updated = try? services.draftStore.load(id: draft.id),
               let idx = appState.localDrafts.firstIndex(where: { $0.id == draft.id }) {
                appState.localDrafts[idx] = updated
            }
            cleanTitle = title
            cleanContent = htmlContent
            cleanFootnotes = footnotesMeta
            presentToast("Saved locally")
        } catch {
            presentToast("Save failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func publish() async {
        await save(status: settings.status)
    }

    private func save(status: PostStatus, force: Bool = false) async {
        guard let creds = appState.credentials else { return }
        guard !contentLoadFailed else {
            saveError = "Can't save — this post never finished loading. Reopen it before making changes."
            return
        }
        guard !alarmBlocksSaving else {
            saveError = "Can't save yet. Quill found content it can't preserve in this post, see the warning above."
            return
        }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let client = WordPressClient(credentials: creds)

        // Create any pending new categories/tags before building the payload.
        // Remove each name from the pending list as soon as it succeeds — if a later
        // name fails, retrying must not re-submit already-created names (WordPress
        // rejects those with "term_exists", wedging the save until the user notices).
        do {
            while let name = settings.newCategoryNames.first {
                let cat = try await client.createCategory(name: name)
                settings.categoryIDs.insert(cat.id)
                appState.categories.append(cat)
                settings.newCategoryNames.removeFirst()
            }

            while let name = settings.newTagNames.first {
                let tag = try await client.createTag(name: name)
                settings.tagIDs.insert(tag.id)
                appState.tags.append(tag)
                settings.newTagNames.removeFirst()
            }
        } catch {
            saveError = "Failed to create taxonomy: \(error.localizedDescription)"
            return
        }

        let cleanExcerpt = settings.excerpt
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = PostPayload(
            title: title,
            content: htmlContent,
            excerpt: cleanExcerpt,
            status: status.rawValue,
            dateGmt: settings.publishDate.map { Self.iso8601Formatter.string(from: $0) },
            featuredMedia: settings.featuredMediaID > 0 ? settings.featuredMediaID : nil,
            categories: Array(settings.categoryIDs),
            tags: Array(settings.tagIDs),
            slug: settings.slug.isEmpty ? nil : settings.slug,
            commentStatus: settings.commentStatus,
            parent: postType == "page" ? settings.parentID : nil,
            footnotes: footnotesMeta
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
                        showConflictAlert = true
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
                cleanFootnotes = footnotesMeta
                try? services.autosaveStore.delete(postID: post.id)
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
                try services.draftStore.delete(id: draft.id)
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
            if status != .future { settings.publishDate = nil }
            if let alarm = blockRiskAlarm {
                blockRiskAlarm = BlockRiskAlarm(names: alarm.names, stage: .saved)
            }
            presentToast(Self.toastMessage(forStatus: status))
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func saveToWordPress() {
        Task { await save(status: settings.status, force: true) }
    }

    private func discardChanges() {
        guard case .remote(let post) = item else { return }
        try? services.autosaveStore.delete(postID: post.id)
        loadFromServer(postID: post.id)
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
                title = post.title.decodedTitle
                htmlContent = post.content.editorHTML
                lastSavedServerModified = post.modified
                cleanTitle = title
                cleanContent = htmlContent
                cleanFootnotes = footnotesMeta
            }
        }
    }

    // MARK: - Drag & Drop

    private func handleDroppedImages(_ urls: [URL]) async {
        guard let creds = appState.credentials else { return }
        let client = WordPressClient(credentials: creds)
        let files = urls.filter { $0.isFileURL }
        guard !files.isEmpty else { return }

        var inserted = 0
        var didConvert = false
        var firstError: String? = nil

        for (index, url) in files.enumerated() {
            uploadStatus = Self.uploadStatusText(index: index + 1, total: files.count)
            do {
                // Off the main actor: decode + re-encode is CPU-bound and this
                // function is MainActor-isolated via SwiftUI's View conformance.
                let prepared = await Task.detached(priority: .userInitiated) {
                    ImageConversion.prepareForUpload(url)
                }.value
                defer { prepared.cleanup() }
                let media = try await client.uploadMedia(
                    fileURL: prepared.fileURL,
                    filename: prepared.filename,
                    mimeType: prepared.mimeType
                )
                var info: [String: Any] = ["url": media.sourceURL, "mediaId": media.id]
                if let w = media.mediaDetails?.width  { info["width"]  = w }
                if let h = media.mediaDetails?.height { info["height"] = h }
                if !media.altText.isEmpty { info["alt"] = media.altText }
                NotificationCenter.default.post(name: .insertMediaURL, object: nil, userInfo: info)
                inserted += 1
                if prepared.didConvert { didConvert = true }
            } catch {
                if firstError == nil { firstError = error.localizedDescription }
            }
        }

        // Clear the pill before any toast — both use the same bottom slot.
        uploadStatus = nil
        let failed = files.count - inserted
        if failed > 0, let firstError {
            presentToast(
                Self.uploadFailureMessage(failed: failed, total: files.count, firstError: firstError),
                isError: true
            )
        } else {
            presentToast(Self.uploadSuccessMessage(inserted: inserted, didConvert: didConvert))
        }
    }

    nonisolated static func uploadStatusText(index: Int, total: Int) -> String {
        total == 1 ? "Uploading image…" : "Uploading image \(index) of \(total)…"
    }

    nonisolated static func uploadSuccessMessage(inserted: Int, didConvert: Bool) -> String {
        guard inserted == 1 else { return "\(inserted) images inserted" }
        return didConvert ? "Converted to JPEG · Image inserted" : "Image inserted"
    }

    nonisolated static func uploadFailureMessage(failed: Int, total: Int, firstError: String) -> String {
        total == 1 ? "Upload failed: \(firstError)" : "\(failed) of \(total) images failed to upload"
    }

    nonisolated static func previewURL(from link: String) -> URL? {
        guard var components = URLComponents(string: link) else { return nil }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "preview" }
        items.append(URLQueryItem(name: "preview", value: "true"))
        components.queryItems = items
        return components.url
    }

    nonisolated static func publishButtonTitle(status: PostStatus, isPublishedRemote: Bool) -> String {
        switch status {
        case .draft: return "Publish Draft"
        case .future: return "Schedule"
        case .pending: return "Submit for Review"
        case .private: return "Publish Privately"
        case .publish: return isPublishedRemote ? "Update" : "Publish"
        }
    }

    nonisolated static func toastMessage(forStatus status: PostStatus) -> String {
        switch status {
        case .publish: return "Published"
        case .future: return "Scheduled"
        case .pending: return "Submitted for review"
        case .private: return "Published privately"
        case .draft: return "Draft saved"
        }
    }

    private func openPreview() async {
        guard let creds = appState.credentials,
            case .remote(let post) = item
        else { return }
        let client = WordPressClient(credentials: creds)
        let cleanExcerpt = settings.excerpt
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = PostPayload(title: title, content: htmlContent, excerpt: cleanExcerpt, status: post.status)
        do {
            let autosave =
                post.type == "page"
                ? try await client.createPageAutosave(postID: post.id, payload: payload)
                : try await client.createAutosave(postID: post.id, payload: payload)
            let linkBase = autosave.link ?? post.link
            guard let url = PostEditorView.previewURL(from: linkBase) else {
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

    // MARK: - Evaluation

    private var evaluationPanelState: EvaluationPanelState {
        if stats.words < 100 { return .shortContent }
        if isEvaluating { return .loading }
        if let error = evaluationError { return .error(error) }
        if let result = evaluationResult { return .result(result) }
        return .loading
    }

    @MainActor
    private func executeEvaluation() async {
        guard let aiSettings = appState.aiSettings else {
            evaluationError = "No API key configured. Add one in Preferences → AI."
            return
        }
        guard stats.words >= 100 else { return }

        isEvaluating = true
        evaluationResult = nil
        evaluationError = nil
        editorWebView?.evaluateJavaScript("window.setEvaluating?.(true)", completionHandler: nil)
        defer {
            isEvaluating = false
            editorWebView?.evaluateJavaScript("window.setEvaluating?.(false)", completionHandler: nil)
        }

        let prompt = AIPromptBuilder.evaluatePostPrompt(title: title, html: htmlContent, styleGuide: aiSettings.styleGuide)
        let system = AIPromptBuilder.systemPrompt(styleGuide: aiSettings.styleGuide)
        let client = AnthropicClient(apiKey: aiSettings.apiKey)

        do {
            let responseText = try await client.complete(
                userMessage: prompt,
                systemPrompt: system,
                useWebSearch: false
            ).text
            guard !Task.isCancelled else { return }
            if let result = AIPromptBuilder.parseEvaluationResponse(responseText) {
                evaluationResult = result
            } else {
                evaluationError = "Could not parse evaluation response."
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            evaluationError = error.localizedDescription
        }
    }

    // MARK: - AI selection handling

    private func handleSelectionChange(rect: CGRect?) {
        guard appState.aiEnabled else { return }
        hasTextSelection = rect != nil
    }

    // MARK: - AI operation execution

    @MainActor
    private func executeAIOperation(_ operation: AIWritingOperation) async {
        guard let settings = appState.aiSettings else { return }
        guard let webView = editorWebView else { return }

        // 1. Tell JS to capture the selection and show the loading placeholder.
        //    JS returns { text, context, containerText, containerFrom, containerTo }.
        let opInfo: (text: String, context: String?, containerText: String?, containerFrom: Int?, containerTo: Int?) = await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("beginAIOperation()") { result, _ in
                if let dict = result as? [String: Any] {
                    continuation.resume(returning: (
                        text: dict["text"] as? String ?? "",
                        context: dict["context"] as? String,
                        containerText: dict["containerText"] as? String,
                        containerFrom: dict["containerFrom"] as? Int,
                        containerTo: dict["containerTo"] as? Int
                    ))
                } else {
                    continuation.resume(returning: ("", nil, nil, nil, nil))
                }
            }
        }
        guard !opInfo.text.isEmpty else { return }

        // 2. Determine if this operation needs to replace the whole container
        let isList = opInfo.context == "bulletList" || opInfo.context == "orderedList"
        let isTable = opInfo.context == "table"
        let needsContainerReplace = (isList || isTable) && (
            operation == .convertToTable || operation == .convertToList ||
            operation == .makeLonger || operation == .makeShorter
        )

        // For container operations, send the full container content to Claude
        let promptText = needsContainerReplace ? (opInfo.containerText ?? opInfo.text) : opInfo.text

        // 3. Call Claude (selection operations never use web search — faster + cheaper)
        let client = AnthropicClient(apiKey: settings.apiKey)
        let system = AIPromptBuilder.systemPrompt(styleGuide: settings.styleGuide)
        let userMsg = AIPromptBuilder.operationPrompt(selectedHTML: promptText, operation: operation, context: opInfo.context)

        do {
            let resultHTML = AIPromptBuilder.cleanOperationResult(try await client.complete(
                userMessage: userMsg,
                systemPrompt: system,
                useWebSearch: false
            ).text)
            // 4. Show result in editor — JS replaces loading placeholder with result,
            //    selects it, and returns a bounding rect for panel positioning.
            guard let jsonData = try? JSONEncoder().encode(resultHTML),
                  let jsonStr = String(data: jsonData, encoding: .utf8) else { return }

            // Pass container boundaries for structural transforms so JS replaces the whole container
            let showArgs: String
            if needsContainerReplace, let cf = opInfo.containerFrom, let ct = opInfo.containerTo {
                showArgs = "\(jsonStr), \(cf), \(ct)"
            } else {
                showArgs = jsonStr
            }

            let resultRect: CGRect? = await withCheckedContinuation { continuation in
                webView.evaluateJavaScript("showAIResult(\(showArgs))") { result, _ in
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
                    webView.evaluateJavaScript("window.pushContentToSwift?.()", completionHandler: nil)
                },
                onDiscard: {
                    webView.evaluateJavaScript("discardAIResult()", completionHandler: nil)
                }
            )
        } catch {
            // Restore original text and show a toast
            webView.evaluateJavaScript("discardAIResult()", completionHandler: nil)
            presentToast("Claude couldn't complete that — please try again.", isError: true)
        }
    }

    /// Parses a WordPress REST API date string. Tries ISO8601 with timezone first
    /// (handles date_gmt "2026-05-30T14:00:00Z"), then falls back to the
    /// no-timezone-suffix format some WP versions emit, treated as UTC.
    private func parseWPDate(_ iso: String) -> Date? {
        Self.iso8601Formatter.date(from: iso) ?? Self.utcNoSuffixFormatter.date(from: iso)
    }
}

