import SwiftUI
import WebKit

enum InspectorPane {
    case settings
    case evaluation
}

public struct PostEditorView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var services: AppServices
    let item: PostItem

    @State private var title: String = ""
    @State private var htmlContent: String = ""
    @State private var footnotesMeta: String = ""
    @State private var settings = PostSettings()
    @State private var stats = PostStats()
    @State private var inspectorPane: InspectorPane?
    @State private var isSaving: Bool = false
    @State private var bannerError: EditorBanner?
    @State private var showConflictAlert: Bool = false
    @State private var conflictFromPreview = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var lastSavedServerModified: String = ""
    @State private var showImagePicker = false
    @State private var gallerySheet: GallerySheetRequest?
    @State private var toastMessage: String? = nil
    @State private var toastStyle: ToastStyle = .success
    // Bumped on every presentToast() call so the toast's dismiss timer restarts even when
    // two consecutive toasts share identical text (e.g. two "Image inserted" toasts from a
    // multi-file drop) — keying the timer on the message string alone wouldn't detect that.
    @State private var toastToken: Int = 0
    // Non-nil while a dropped image is being converted/uploaded; drives the bottom pill.
    @State private var uploadStatus: String? = nil
    // Tail of the drop queue. Each new drop awaits it, so batches never interleave.
    @State private var dropTask: Task<Void, Never>? = nil
    @State private var featuredUploadItemIDs: Set<String> = []
    @State private var cleanTitle: String = ""
    @State private var cleanContent: String = ""
    @State private var cleanFootnotes: String = ""
    @State private var cleanSettings = PostSettings()
    @State private var loadedItem: PostItem? = nil
    @State private var serverPost: WPPost? = nil
    // The site loadedItem came from; its autosave stash is keyed to that site even after a switch.
    @State private var loadedSite = ""
    @State private var aiRequestInFlight = false
    @State private var editorReady = false
    @State private var contentLoaded = false
    @State private var showDiscardAlert: Bool = false
    @State private var showPastScheduleAlert: Bool = false
    @State private var contentSyncPending: Bool = false
    @State private var contentLoadFailed: Bool = false
    @State private var blockRiskAlarm: BlockRiskAlarm? = nil
    @State private var editorHandle = EditorHandle()
    @State private var quitToken = UUID()

    private static let iso8601Formatter: ISO8601DateFormatter = ISO8601DateFormatter()
    nonisolated private static let calloutCapHeight = NSFont.preferredFont(forTextStyle: .callout).capHeight
    // Measured gap between the 13pt triangle's frame top and its apex.
    nonisolated private static let triangleTopInset: CGFloat = 1.5

    // AI state
    @State private var isAISheetOpen: Bool = false
    @State private var showAIReplaceAlert: Bool = false
    @State private var hasTextSelection: Bool = false
    @State private var editorWebView: WKWebView? = nil
    @State private var resultPanel: AIResultPanel = AIResultPanel()

    // Evaluation state
    @State private var isEvaluating: Bool = false
    @State private var evaluationResult: EvaluationResult? = nil
    @State private var evaluationError: String? = nil
    @State private var evaluationTask: Task<Void, Never>? = nil
    @State private var aiTask: Task<Void, Never>? = nil

    public init(item: PostItem) {
        self.item = item
    }

    public var body: some View {
        VStack(spacing: 0) {
            editorHeader
            // The alarm sits above the save error, which refers to it as
            // "the warning above".
            if let alarm = blockRiskAlarm { blockRiskBanner(alarm) }
            if bannerError != nil { errorBanner }
            ZStack {
                EditorView(
                    handle: editorHandle,
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
                    onInsertGallery: { edit in
                        gallerySheet = GallerySheetRequest(editing: edit)
                    },
                    onImageFilesDropped: { urls in
                        // Serialized: overlapping drops share `uploadStatus`, so a second
                        // batch must not clear the pill while the first is still uploading.
                        let previous = dropTask
                        let postID = loadedItem?.id
                        dropTask = Task {
                            await previous?.value
                            await handleDroppedImages(urls, postID: postID)
                        }
                    },
                    onDropRejected: { message in
                        presentToast(message, style: .info)
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
                        // Kept, not replaced: a post switch cancels the running request through aiTask.
                        guard !aiRequestInFlight else {
                            presentToast(Self.aiBusyMessage, style: .info)
                            return
                        }
                        aiTask = Task { await executeAIOperation(operation) }
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
                            inspectorPane = .evaluation
                            if evaluationResult == nil && evaluationError == nil {
                                evaluationTask = Task { await executeEvaluation() }
                            }
                        }
                    },
                    onImagesPasted: { images in
                        let previous = dropTask
                        let postID = loadedItem?.id
                        dropTask = Task {
                            await previous?.value
                            await handlePastedImages(images, postID: postID)
                        }
                    },
                    onGalleryUpdateDropped: {
                        bannerError = EditorBanner(message: "The post changed while the gallery was open, so the gallery wasn't updated.", source: .gallery)
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
                    if !selected.altText.isEmpty { info["alt"] = selected.altText }
                    NotificationCenter.default.post(name: .insertMediaURL, object: nil, userInfo: info)
                    showImagePicker = false
                }, onCancel: {
                    showImagePicker = false
                })
                .environmentObject(appState)
                .frame(minWidth: 600, minHeight: 400)
            }
            .sheet(item: $gallerySheet) { request in
                GallerySheet(editing: request.editing, onInsert: { selections, columns, cropped, linkTo, sizeSlug in
                    bannerError = bannerError?.clearing(.gallery)
                    let info = Self.galleryPayload(
                        selections: selections, columns: columns, cropped: cropped,
                        linkTo: linkTo, sizeSlug: sizeSlug, editing: request.editing)
                    NotificationCenter.default.post(name: .insertGalleryData, object: nil, userInfo: info)
                    gallerySheet = nil
                }, onCancel: {
                    gallerySheet = nil
                })
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 480)
            }
        }
        .uploadStatus($uploadStatus)
        .toast(message: $toastMessage, style: $toastStyle, token: toastToken)
        .onChange(of: bannerError) { _, banner in
            if let banner { AccessibilityNotification.Announcement(banner.message).post() }
        }
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
        .alert("Publish Now?", isPresented: $showPastScheduleAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Publish Now") { Task { await save(status: settings.status) } }
        } message: {
            Text(Self.pastScheduleMessage(for: settings.publishDate ?? Date()))
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
            Button("Use Server") { discardChanges() }
            Button("Keep Local") {
                if conflictFromPreview {
                    Task { await openPreview(force: true) }
                } else {
                    saveToWordPress()
                }
            }
        } message: {
            Text("This post was modified on the server since you last fetched it.")
        }
        .onChange(of: item.id) {
            evaluationTask?.cancel()
            evaluationTask = nil
            if inspectorPane == .evaluation { inspectorPane = nil }
            isEvaluating = false
            evaluationResult = nil
            evaluationError = nil
        }
        .onChange(of: inspectorPane) { _, pane in
            let open = pane == .evaluation
            editorWebView?.evaluateJavaScript("window.setEvaluationPanelOpen?.(\(open))", completionHandler: nil)
        }
        .background(SplitItemCollapseFix(behavior: .inspector).frame(width: 0, height: 0))
        .inspector(isPresented: Binding(
            get: { inspectorPane != nil },
            set: { if !$0 { inspectorPane = nil } }
        )) {
            inspectorContent
                .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
                .background(InspectorTitlebarFix().frame(width: 0, height: 0))
        }
        .background(DocumentEditedMarker(isEdited: isDirty).frame(width: 0, height: 0))
        .navigationTitle(title.isEmpty ? "Untitled" : title)
        .toolbar {
            ToolbarSpacer(.flexible)
            ToolbarItemGroup {
                if !isRemote {
                    Button { Task { await saveDraft() } } label: {
                        Image(systemName: "tray.and.arrow.down")
                    }
                    .help("Save Locally")
                    .accessibilityLabel("Save Locally")
                    .disabled(isSaving)
                }
                if isRemote && isDirty {
                    Button { showDiscardAlert = true } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .help("Revert")
                    .accessibilityLabel("Revert")
                }
                if isRemote {
                    Button { Task { await openPreview() } } label: {
                        Image(systemName: "eye")
                    }
                    .help("Preview")
                    .accessibilityLabel("Preview")
                    .disabled(isSaving)
                }
                if let url = shareURL {
                    ShareLink(item: url, preview: SharePreview(title.isEmpty ? "Untitled" : title)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("Share")
                    .accessibilityLabel("Share")
                }
                // Guarded rather than .disabled(isSaving): the disabled style washes the
                // button out for the whole round-trip, which reads as broken.
                Button {
                    guard !isSaving else { return }
                    Task { await publish() }
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: publishButtonIcon)
                    }
                }
                .help(isSaving ? "Saving…" : publishButtonTitle)
                .accessibilityLabel(publishButtonTitle)
            }
            ToolbarSpacer(.fixed)
            ToolbarItem {
                Button {
                    withAnimation {
                        inspectorPane = inspectorPane == nil ? .settings : nil
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Post Settings")
                .accessibilityLabel("Post Settings")
            }
        }
        .task(id: item.id) { await loadItem() }
        .onAppear {
            appState.persistOpenPost = (quitToken, { await persistOpenPost() })
        }
        .onDisappear {
            autosaveTask?.cancel()
            evaluationTask?.cancel()
            aiTask?.cancel()
            if appState.persistOpenPost?.owner == quitToken { appState.persistOpenPost = nil }
            Task { await persistOpenPost() }
        }
        .onChange(of: appState.triggerFindBar) { _, newValue in
            guard newValue else { return }
            appState.triggerFindBar = false
            editorWebView?.evaluateJavaScript("openFindBar()", completionHandler: nil)
        }
        .onChange(of: appState.triggerPasteMarkdown) { _, newValue in
            guard newValue else { return }
            appState.triggerPasteMarkdown = false
            pasteAsMarkdown()
        }
        .onChange(of: appState.triggerSave) { _, newValue in
            guard newValue else { return }
            appState.triggerSave = false
            guard !isSaving else { return }
            Task { isRemote ? await publish() : await saveDraft() }
        }
        .onChange(of: appState.triggerPublish) { _, newValue in
            guard newValue else { return }
            appState.triggerPublish = false
            guard !isSaving else { return }
            Task { await publish() }
        }
        .onChange(of: appState.triggerPreview) { _, newValue in
            guard newValue else { return }
            appState.triggerPreview = false
            guard isRemote, !isSaving else { return }
            Task { await openPreview() }
        }
        .onChange(of: appState.triggerRevert) { _, newValue in
            guard newValue else { return }
            appState.triggerRevert = false
            guard isRemote, isDirty else { return }
            showDiscardAlert = true
        }
        .onChange(of: isDirty, initial: true) { appState.editorIsDirty = isDirty }
        .onChange(of: isSaving, initial: true) { appState.editorIsSaving = isSaving }
        .onChange(of: publishButtonTitle, initial: true) { appState.editorPublishTitle = publishButtonTitle }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        if inspectorPane == .evaluation {
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
                stats: stats,
                featuredImageUploading: loadedItem.map { featuredUploadItemIDs.contains($0.id) } ?? false,
                onFeaturedImageDrop: uploadFeaturedImage
            )
        }
    }

    private var editorHeader: some View {
        HStack(spacing: 10) {
            statusIcon
            titleField
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var statusIcon: some View {
        Image(systemName: statusSymbol(statusKey))
            .font(.system(size: 18))
            .foregroundStyle(Color.statusColor(statusKey))
            .help(statusBadgeLabel)
            .accessibilityLabel("Status: \(statusBadgeLabel)")
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
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: danger ? "exclamationmark.triangle.fill" : "clock.arrow.circlepath")
                .foregroundStyle(danger ? Color.red : Color.secondary)
                .font(.system(size: 13))
                .alignmentGuide(.firstTextBaseline) { $0[.top] + Self.triangleTopInset + Self.calloutCapHeight }
            VStack(alignment: .leading, spacing: 4) {
                if !alarm.title.isEmpty {
                    Text(alarm.title)
                        .font(.callout.weight(.semibold))
                }
                Text(boldingNames(in: alarm.body, names: alarm.names))
                    .font(.callout)
                    .lineSpacing(1.5)
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
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 13))
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Self.calloutCapHeight / 2 }
            Text(bannerError?.message ?? "")
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
            Button {
                bannerError = nil
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
        .onChange(of: title) { scheduleAutosave() }
    }

    // `item` is the post as it was selected; a save updates only the cached copy.
    private var remotePost: WPPost? {
        guard case .remote(let post) = item else { return nil }
        let cached = post.type == "page" ? appState.pages : appState.posts
        return cached.first { $0.id == post.id } ?? post
    }

    private var isPublishedRemote: Bool {
        remotePost?.status == PostStatus.publish.rawValue
    }

    // Unpublished posts' links are `?p=` URLs that only their editors can open.
    private var shareURL: URL? {
        guard case .remote(let post) = item, let server = serverPost, server.id == post.id,
              [PostStatus.publish.rawValue, PostStatus.private.rawValue].contains(server.status) else { return nil }
        return URL(string: server.link)
    }

    private var publishButtonTitle: String {
        Self.publishButtonTitle(status: settings.status, isLocal: !isRemote, isPublishedRemote: isPublishedRemote)
    }

    private var publishButtonIcon: String {
        Self.publishButtonIcon(status: settings.status, isPublishedRemote: isPublishedRemote)
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

    // Nil when the body may be written to WordPress or the draft store; otherwise why not.
    private func writeBlockedReason(_ action: String) -> String? {
        if contentLoadFailed {
            return "Can't \(action): this post never finished loading. Reopen it before making changes."
        }
        if alarmBlocksSaving {
            return "Can't \(action) yet. Quill found content it can't preserve in this post, see the warning above."
        }
        return nil
    }

    nonisolated static func plainExcerpt(_ excerpt: String) -> String {
        excerpt
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDirty: Bool {
        bodyIsDirty || settings != cleanSettings
    }

    // What the autosave stash holds; settings are not in it.
    private var bodyIsDirty: Bool {
        title != cleanTitle || htmlContent != cleanContent || footnotesMeta != cleanFootnotes
    }

    // The editor reports its at-risk list on every load and code-view edit,
    // empty included, so a post the user repaired can clear its own banner.
    nonisolated static func nextAlarm(from current: BlockRiskAlarm?, names: [String]) -> BlockRiskAlarm? {
        guard !names.isEmpty else { return nil }
        if let current, current.names == names, current.stage != .unacknowledged { return current }
        return BlockRiskAlarm(names: names, stage: .unacknowledged)
    }

    private func uploadFeaturedImage(_ provider: NSItemProvider) {
        guard let creds = appState.credentials, let itemID = loadedItem?.id else { return }
        bannerError = bannerError?.clearing(.featuredImage)
        featuredUploadItemIDs.insert(itemID)
        Task { [editorWebView] in
            defer { featuredUploadItemIDs.remove(itemID) }
            guard let url = await FeaturedImageSection.copyDroppedImage(from: provider) else {
                reportError("Couldn't read the dropped image.", from: .featuredImage, about: itemID)
                return
            }
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            do {
                let media = try await Task.detached(priority: .userInitiated) {
                    try await uploadPickedImage(url, credentials: creds)
                }.value
                if isOpen(itemID), editorWebView?.window != nil {
                    settings.featuredMediaID = media.id
                } else {
                    presentToast("The image is in the Media Library but wasn't set as the featured image.", style: .info)
                }
            } catch {
                reportError("Couldn't upload the featured image: \(error.localizedDescription)", from: .featuredImage, about: itemID)
            }
        }
    }

    private func presentToast(_ text: String, isError: Bool = false) {
        presentToast(text, style: isError ? .error : .success)
    }

    private func presentToast(_ text: String, style: ToastStyle) {
        toastMessage = text
        toastStyle = style
        toastToken += 1
    }

    // The banner belongs to the open post, so an error about a post the user left goes to a toast.
    private func reportError(_ message: String, from source: EditorBanner.Source, about postID: PostItem.ID?) {
        if isOpen(postID) {
            bannerError = EditorBanner(message: message, source: source)
        } else {
            presentToast(message, isError: true)
        }
    }

    /// Backs the Edit ▸ Paste as Markdown command. Reads the clipboard here in Swift
    /// and hands the text to `window.insertMarkdown`, so this never goes through the
    /// web view's own paste handling — an ordinary ⌘V is completely unaffected.
    private func pasteAsMarkdown() {
        guard let webView = editorWebView else { return }
        guard let text = NSPasteboard.general.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            presentToast("The clipboard has no text to paste.", style: .info)
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
            presentToast(message, style: .info)
        }
    }

    // MARK: - Load

    private func loadItem() async {
        let requestedItem = item
        // Reset here, never in onChange(of: item.id) — that handler runs after this task starts.
        contentLoaded = false
        aiTask?.cancel()
        aiTask = nil
        resultPanel.dismiss()

        // Flush dirty state for the previously-loaded item before overwriting editor state
        if let prev = loadedItem, prev.id != item.id {
            await editorHandle.flushPendingContent()
            if isDirty { await flushToDB(for: prev) }
        }
        // After the flush, which reschedules it; flushToDB has already persisted the old item.
        autosaveTask?.cancel()
        loadedItem = item
        loadedSite = appState.credentials?.siteKey ?? ""
        // Every per-post banner and save guard resets here, for both branches.
        // A local draft opened after a remote post failed to load must not
        // inherit its blocked state. The editor re-posts blocksAtRisk after the
        // content below lands, so a real alarm for this post still arrives.
        bannerError = nil
        blockRiskAlarm = nil
        contentLoadFailed = false
        settings.newCategoryNames = []
        settings.newTagNames = []

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
                    // task's failure would stomp contentLoadFailed/bannerError for whichever
                    // post is currently displayed.
                    guard !Task.isCancelled, loadedItem == requestedItem else { return }
                    loadedPost = post
                    contentLoadFailed = true
                    bannerError = EditorBanner(message: "Couldn't load the full post, so this is a cached preview that may be missing content. Reopen the post once you're connected, before making changes.", source: .load)
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
            if let snap = try? services.autosaveStore.load(site: loadedSite, postID: post.id) {
                if let baseline = Self.autosaveRestoreBaseline(snap, over: loadedPost) {
                    title = snap.title
                    htmlContent = snap.content
                    footnotesMeta = snap.footnotes
                    lastSavedServerModified = baseline
                    presentToast("Unsaved changes restored")
                } else {
                    try? services.autosaveStore.delete(site: loadedSite, postID: post.id)
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
                settings.excerpt = Self.plainExcerpt(fresh.excerpt)
                if showToast { presentToast("Unsaved changes restored") }
            } else {
                title = draft.title
                htmlContent = draft.content
                footnotesMeta = draft.footnotes
                settings = PostSettings()
                settings.excerpt = Self.plainExcerpt(draft.excerpt)
            }
            cleanTitle = title
            cleanContent = htmlContent
            cleanFootnotes = footnotesMeta
            cleanSettings = settings
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
        serverPost = post
        settings = PostSettings(post: post)
        cleanTitle = wpTitle
        cleanContent = wpContent
        cleanFootnotes = post.footnotes
        cleanSettings = settings
    }

    // nil discards the autosave; otherwise the server version it was edited from, so a save after a web edit hits the conflict alert.
    nonisolated static func autosaveRestoreBaseline(_ snap: AutosaveSnapshot, over post: WPPost) -> String? {
        let snapContent = snap.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverContent = post.content.editorHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        if snapContent.isEmpty,
           !serverContent.isEmpty,
           snap.title == post.title.decodedTitle {
            return nil
        }
        return snap.serverModified
    }

    // MARK: - Autosave

    private func persistOpenPost() async {
        await editorHandle.flushPendingContent()
        if let loadedItem, isDirty { await flushToDB(for: loadedItem) }
    }

    private func flushToDB(for oldItem: PostItem) async {
        // Same reason as performAutosave: the squashed content must not reach the store.
        if alarmBlocksSaving { return }
        do {
            try writeLocalCopy(of: oldItem)
        } catch {
            presentToast("Unsaved changes to “\(title)” couldn't be kept: \(error.localizedDescription)", isError: true)
            return
        }
        if case .local(let draft) = oldItem,
           let updated = try? services.draftStore.load(id: draft.id),
           let idx = appState.localDrafts.firstIndex(where: { $0.id == draft.id }) {
            appState.localDrafts[idx] = updated
        }
    }

    private func writeLocalCopy(of item: PostItem) throws {
        switch item {
        case .remote(let post):
            guard bodyIsDirty else { return }
            try services.autosaveStore.save(
                site: loadedSite, postID: post.id, title: title, content: htmlContent,
                footnotes: footnotesMeta, serverModified: lastSavedServerModified)
        case .local(let draft):
            try services.draftStore.update(id: draft.id, title: title, content: htmlContent, excerpt: settings.excerpt, footnotes: footnotesMeta)
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
        // Or the squashed content silently becomes the local draft.
        if alarmBlocksSaving { return }
        bannerError = bannerError?.clearing(.autosave)
        do {
            try writeLocalCopy(of: item)
        } catch {
            bannerError = EditorBanner(message: "Autosave failed: \(error.localizedDescription)", source: .autosave)
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
        isSaving = true
        defer { isSaving = false }
        bannerError = bannerError?.clearing(.save)
        await editorHandle.flushPendingContent()
        if let reason = writeBlockedReason("save") {
            bannerError = EditorBanner(message: reason, source: .save)
            return
        }
        do {
            try services.draftStore.update(id: draft.id, title: title, content: htmlContent, excerpt: settings.excerpt, footnotes: footnotesMeta)
            if let updated = try? services.draftStore.load(id: draft.id),
               let idx = appState.localDrafts.firstIndex(where: { $0.id == draft.id }) {
                appState.localDrafts[idx] = updated
            }
            cleanTitle = title
            cleanContent = htmlContent
            cleanFootnotes = footnotesMeta
            cleanSettings = settings
            presentToast("Saved locally")
        } catch {
            bannerError = EditorBanner(message: "Couldn't save the draft: \(error.localizedDescription)", source: .save)
        }
    }

    private func publish() async {
        if settings.status == .future && settings.scheduledDateHasPassed() {
            showPastScheduleAlert = true
            return
        }
        await save(status: settings.status)
    }

    private func save(status requestedStatus: PostStatus, force: Bool = false) async {
        let status = Self.effectiveStatus(requestedStatus, settings: settings)
        guard let creds = appState.credentials else { return }
        isSaving = true
        defer { isSaving = false }
        await editorHandle.flushPendingContent()
        if let reason = writeBlockedReason("save") {
            bannerError = EditorBanner(message: reason, source: .save)
            return
        }
        if let loadedID = loadedItem?.id, featuredUploadItemIDs.contains(loadedID) {
            presentToast("The featured image is still uploading. Save again when it's done.", style: .info)
            return
        }
        bannerError = bannerError?.clearing(.save)

        let client = WordPressClient(credentials: creds)
        // Captured up front so the save finishes for this post even if the user switches mid-save.
        let site = creds.siteKey
        let savedItemID = item.id
        let savedTitle = title
        let savedContent = htmlContent
        let savedFootnotes = footnotesMeta
        let baseline = lastSavedServerModified
        var saved = settings
        // A section switch rebuilds this view, leaving the old one's loadedItem unchanged; the selection moves in both cases.
        func stillOnPost() -> Bool { loadedItem?.id == savedItemID && appState.selectedItem?.id == savedItemID }
        func report(_ message: String) {
            if stillOnPost() {
                bannerError = EditorBanner(message: message, source: .save)
            } else {
                presentToast("“\(savedTitle)” wasn't saved: \(message)", isError: true)
            }
        }

        // Create any pending new categories/tags before building the payload.
        // Remove each name from the pending list as soon as it succeeds — if a later
        // name fails, retrying must not re-submit already-created names (WordPress
        // rejects those with "term_exists", wedging the save until the user notices).
        do {
            while let name = saved.newCategoryNames.first {
                let cat = try await client.createCategory(name: name)
                appState.categories.append(cat)
                saved.categoryIDs.insert(cat.id)
                saved.newCategoryNames.removeFirst()
                if stillOnPost() {
                    settings.categoryIDs.insert(cat.id)
                    settings.newCategoryNames.removeAll { $0 == name }
                }
            }

            while let name = saved.newTagNames.first {
                let tag = try await client.createTag(name: name)
                appState.tags.append(tag)
                saved.tagIDs.insert(tag.id)
                saved.newTagNames.removeFirst()
                if stillOnPost() {
                    settings.tagIDs.insert(tag.id)
                    settings.newTagNames.removeAll { $0 == name }
                }
            }
        } catch {
            report("Couldn't create the new category or tag: \(error.localizedDescription)")
            return
        }

        let payload = PostPayload(
            title: savedTitle,
            content: savedContent,
            excerpt: Self.plainExcerpt(saved.excerpt),
            status: status.rawValue,
            dateGmt: saved.publishDate.map { Self.iso8601Formatter.string(from: $0) },
            featuredMedia: saved.featuredMediaID,
            categories: Array(saved.categoryIDs),
            tags: Array(saved.tagIDs),
            slug: saved.slug.isEmpty ? nil : saved.slug,
            commentStatus: saved.commentStatus,
            parent: postType == "page" ? saved.parentID : nil,
            footnotes: savedFootnotes
        )

        var cleanupWarning: String?
        do {
            switch item {
            case .remote(let post):
                if !force {
                    let current =
                        post.type == "page"
                        ? try await client.fetchPage(id: post.id)
                        : try await client.fetchPost(id: post.id)
                    if current.modified != baseline {
                        if stillOnPost() {
                            conflictFromPreview = false
                            showConflictAlert = true
                        } else {
                            report("it was changed on the server. Open it to choose which version to keep.")
                        }
                        return
                    }
                }
                let updated =
                    post.type == "page"
                    ? try await client.updatePage(id: post.id, payload: payload)
                    : try await client.updatePost(id: post.id, payload: payload)
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
                guard stillOnPost() else {
                    let stash = try? services.autosaveStore.load(site: site, postID: post.id)
                    if let kept = Self.stashAfterSave(stash, title: savedTitle, content: savedContent,
                                                      footnotes: savedFootnotes, serverModified: updated.modified) {
                        try? services.autosaveStore.save(site: site, postID: post.id, title: kept.title, content: kept.content,
                                                         footnotes: kept.footnotes, serverModified: kept.serverModified)
                    } else {
                        try? services.autosaveStore.delete(site: site, postID: post.id)
                    }
                    presentToast("“\(savedTitle)”: \(Self.toastMessage(forStatus: status))")
                    return
                }
                try? services.autosaveStore.delete(site: site, postID: post.id)
                serverPost = updated
                lastSavedServerModified = updated.modified
                cleanTitle = savedTitle
                cleanContent = savedContent
                cleanFootnotes = savedFootnotes
            case .local(let draft):
                let created =
                    draft.type == "page"
                    ? try await client.createPage(payload)
                    : try await client.createPost(payload)
                // The post exists now, so a failed cleanup must not report failure and invite a duplicate.
                let draftRemoved = (try? services.draftStore.delete(id: draft.id)) != nil
                if draftRemoved { appState.localDrafts.removeAll { $0.id == draft.id } }
                if draft.type == "page" {
                    appState.pages.insert(created, at: 0)
                } else {
                    appState.posts.insert(created, at: 0)
                }
                if !draftRemoved {
                    cleanupWarning = "\(Self.toastMessage(forStatus: status)). The local draft couldn't be removed; delete it so it isn't published twice."
                }
                guard stillOnPost() else {
                    presentToast("“\(savedTitle)”: \(cleanupWarning ?? Self.toastMessage(forStatus: status))", isError: cleanupWarning != nil)
                    return
                }
                // Typing during the request is newer than the created post; stash it so the remote load restores it.
                await editorHandle.flushPendingContent()
                if title != savedTitle || htmlContent != savedContent || footnotesMeta != savedFootnotes {
                    try? services.autosaveStore.save(site: site, postID: created.id, title: title, content: htmlContent,
                                                     footnotes: footnotesMeta, serverModified: created.modified)
                }
                guard stillOnPost() else { return }
                lastSavedServerModified = created.modified
                appState.selectedSection = draft.type == "page" ? .pages : .posts
                appState.selectedItem = .remote(created)
            }
            settings.status = status
            if status != .future { settings.publishDate = nil }
            saved.status = status
            if status != .future { saved.publishDate = nil }
            cleanSettings = saved
            if let alarm = blockRiskAlarm {
                blockRiskAlarm = BlockRiskAlarm(names: alarm.names, stage: .saved)
            }
            if let cleanupWarning {
                presentToast(cleanupWarning, isError: true)
            } else {
                presentToast(Self.toastMessage(forStatus: status))
            }
        } catch {
            report(error.localizedDescription)
        }
    }

    // nil deletes the stash; otherwise it holds edits newer than the save, re-based on the version the save made.
    nonisolated static func stashAfterSave(
        _ stash: AutosaveSnapshot?, title: String, content: String, footnotes: String, serverModified: String
    ) -> AutosaveSnapshot? {
        guard var stash, stash.title != title || stash.content != content || stash.footnotes != footnotes else { return nil }
        stash.serverModified = serverModified
        return stash
    }

    private func saveToWordPress() {
        Task { await save(status: settings.status, force: true) }
    }

    private func discardChanges() {
        guard case .remote(let post) = item else { return }
        try? services.autosaveStore.delete(site: loadedSite, postID: post.id)
        loadFromServer(postID: post.id)
    }

    private func loadFromServer(postID: Int) {
        bannerError = bannerError?.clearing(.revert)
        Task {
            guard let creds = appState.credentials,
                case .remote(let current) = item
            else { return }
            let requestedID = item.id
            let client = WordPressClient(credentials: creds)
            do {
                let post = current.type == "page"
                    ? try await client.fetchPage(id: postID)
                    : try await client.fetchPost(id: postID)
                guard loadedItem?.id == requestedID else { return }
                applyRemotePost(post)
            } catch {
                guard loadedItem?.id == requestedID else { return }
                bannerError = EditorBanner(message: "Couldn't load the server version: \(error.localizedDescription)", source: .revert)
            }
        }
    }

    // MARK: - Drag & Drop

    private func handleDroppedImages(_ urls: [URL], postID: PostItem.ID?) async {
        let files = urls.filter { $0.isFileURL }
        await uploadImages(files.map { ($0, insertAtCursor(ifStillOn: postID)) }, postID: postID)
    }

    // A token marks an image already in the document, which only has its source swapped.
    private func handlePastedImages(_ images: [PastedImage], postID: PostItem.ID?) async {
        defer {
            if let script = PastedImage.forgetScript(images.compactMap(\.token)) {
                editorWebView?.evaluateJavaScript(script, completionHandler: nil)
            }
        }
        guard appState.credentials != nil else {
            reportError("Connect a WordPress site in Settings to upload pasted images.", from: .upload, about: postID)
            return
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillPaste-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        var uploads: [(URL, (WPMedia) -> Bool)] = []
        for (index, image) in images.enumerated() {
            let ext = Self.fileExtension(for: image.data, mimeType: image.mimeType)
            let file = folder.appendingPathComponent("pasted-image-\(index + 1).\(ext)")
            guard (try? image.data.write(to: file)) != nil else { continue }
            guard let token = image.token else {
                uploads.append((file, insertAtCursor(ifStillOn: postID)))
                continue
            }
            uploads.append((file, { [editorWebView] media in
                guard isOpen(postID), editorWebView?.window != nil else { return false }
                let args = [token, media.sourceURL].compactMap { Self.jsonLiteral($0) }.joined(separator: ", ")
                editorWebView?.evaluateJavaScript("window.resolvePastedImage?.(\(args), \(media.id))", completionHandler: nil)
                return true
            }))
        }
        await uploadImages(uploads, postID: postID)
    }

    private func isOpen(_ postID: PostItem.ID?) -> Bool {
        postID != nil && loadedItem?.id == postID && appState.selectedItem?.id == postID
    }

    private func insertAtCursor(ifStillOn postID: PostItem.ID?) -> (WPMedia) -> Bool {
        { [editorHandle, editorWebView] media in
            guard isOpen(postID), editorWebView?.window != nil else { return false }
            editorHandle.insertImage(url: media.sourceURL, mediaId: media.id, alt: media.altText)
            return true
        }
    }

    // The bytes decide: Word labels its JPEGs image/png, and WordPress refuses a mismatched extension.
    nonisolated static func fileExtension(for data: Data, mimeType: String) -> String {
        let head = [UInt8](data.prefix(12))
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if head.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "gif" }
        if head.count == 12, head.starts(with: [0x52, 0x49, 0x46, 0x46]), Array(head[8..<12]) == [0x57, 0x45, 0x42, 0x50] { return "webp" }
        if head.count == 12, Array(head[4..<8]) == Array("ftyp".utf8) { return "heic" }
        switch mimeType.lowercased() {
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/heic": return "heic"
        case "image/tiff": return "tiff"
        default: return "png"
        }
    }

    private static func jsonLiteral(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func uploadImages(_ files: [(URL, (WPMedia) -> Bool)], postID: PostItem.ID?) async {
        guard let creds = appState.credentials, !files.isEmpty else { return }
        if isOpen(postID) { bannerError = bannerError?.clearing(.upload) }
        let client = WordPressClient(credentials: creds)

        var inserted = 0
        var notInserted = 0
        var didConvert = false
        var firstError: String? = nil
        toastMessage = nil

        for (index, (url, place)) in files.enumerated() {
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
                if place(media) { inserted += 1 } else { notInserted += 1 }
                if prepared.didConvert { didConvert = true }
            } catch {
                if firstError == nil { firstError = error.localizedDescription }
            }
        }

        // Clear the pill before any toast — both use the same bottom slot.
        uploadStatus = nil
        let failed = files.count - inserted - notInserted
        if failed > 0, let firstError {
            reportError(Self.uploadFailureMessage(failed: failed, total: files.count, firstError: firstError),
                        from: .upload, about: postID)
        } else if notInserted > 0 {
            presentToast(Self.uploadNotInsertedMessage(count: notInserted), isError: true)
        } else {
            presentToast(Self.uploadSuccessMessage(inserted: inserted, didConvert: didConvert))
        }
    }

    /// The `window.insertGallery` payload; see Views/Media/CLAUDE.md (edit mode) for `"keep"` and `"mixed"`.
    nonisolated static func galleryPayload(
        selections: [GallerySelection], columns: Int?, cropped: Bool,
        linkTo: String, sizeSlug: String, editing: GalleryEdit?
    ) -> [String: Any] {
        guard let editing else {
            let images: [[String: Any]] = selections.compactMap { sel in
                guard let media = sel.media else { return nil }
                return [
                    "id": media.id,
                    "url": media.sizedURL(for: sizeSlug),
                    "fullUrl": media.sourceURL,
                    "alt": sel.alt,
                    "caption": sel.caption,
                ]
            }
            return ["images": images, "columns": columns ?? 3, "cropped": cropped, "linkTo": linkTo, "sizeSlug": sizeSlug]
        }
        let keepLinks = linkTo == "keep"
        let images: [[String: Any]] = selections.map { sel in
            let existing = sel.existing
            let media = sel.media
            // An image already in the gallery keeps its own file unless the user picked a new size for all of them.
            let sizeUnchanged = sizeSlug == "mixed" || sizeSlug == editing.initialSizeSlug
            let keepsSize = existing != nil && (media == nil || sizeUnchanged)
            let size = keepsSize ? (existing?.sizeSlug ?? "large") : (sizeSlug == "mixed" ? "large" : sizeSlug)
            let url: String
            if let existing, keepsSize {
                url = existing.url
            } else {
                url = media?.sizedURL(for: size) ?? existing?.url ?? ""
            }
            let fullUrl = media?.sourceURL ?? existing?.fullUrl
            let href: String?
            switch linkTo {
            case "keep" where existing != nil:
                href = existing?.href
            case "keep":
                switch editing.linkTo {
                case "attachment": href = media?.link
                case "media": href = fullUrl ?? url
                default: href = nil
                }
            case "media":
                href = fullUrl ?? url
            default:
                href = nil
            }
            var image: [String: Any] = [
                "url": url,
                "alt": sel.alt,
                "caption": sel.caption,
                "sizeSlug": size,
                "href": href ?? NSNull(),
                "extraClasses": existing?.extraClasses ?? "",
            ]
            if let id = media?.id ?? existing?.id { image["id"] = id }
            if let fullUrl { image["fullUrl"] = fullUrl }
            if let blockAttrs = existing?.blockAttrs {
                image["blockAttrs"] = blockAttrs
            } else if existing == nil, keepLinks, editing.linkTo == "attachment", let media, href != nil {
                // Written in core's key order; an attachment page cannot be told apart from a custom link.
                image["blockAttrs"] = "{\"id\":\(media.id),\"sizeSlug\":\"\(size)\",\"linkDestination\":\"attachment\"}"
            }
            if let extraAttrs = existing?.extraAttrs { image["extraAttrs"] = extraAttrs }
            if let existing, let captionHTML = existing.captionHTML, sel.caption == existing.caption {
                image["captionHTML"] = captionHTML
            }
            return image
        }
        var payload: [String: Any] = [
            "images": images,
            "columns": columns ?? NSNull(),
            "cropped": cropped,
            "linkTo": keepLinks ? editing.linkTo : linkTo,
            "replace": true,
            "keepLinks": keepLinks,
        ]
        if sizeSlug != "mixed" { payload["sizeSlug"] = sizeSlug }
        return payload
    }

    nonisolated static func uploadStatusText(index: Int, total: Int) -> String {
        total == 1 ? "Uploading image…" : "Uploading image \(index) of \(total)…"
    }

    nonisolated static func uploadSuccessMessage(inserted: Int, didConvert: Bool) -> String {
        guard inserted == 1 else { return "\(inserted) images inserted" }
        return didConvert ? "Converted to JPEG · Image inserted" : "Image inserted"
    }

    nonisolated static func aiFailureMessage(for error: Error) -> String {
        (error as? AnthropicError)?.errorDescription ?? "Claude couldn't finish that rewrite. Try again."
    }

    nonisolated static let aiBusyMessage = "Finish the current AI rewrite first: wait for it, then accept or discard it."

    nonisolated static func uploadNotInsertedMessage(count: Int) -> String {
        let subject = count == 1 ? "Image" : "\(count) images"
        return "\(subject) uploaded to the Media Library but not inserted, because a different post is open"
    }

    nonisolated static func uploadFailureMessage(failed: Int, total: Int, firstError: String) -> String {
        total == 1 ? "Upload failed: \(firstError)" : "\(failed) of \(total) images failed to upload"
    }

    nonisolated static func previewURL(from link: String) -> URL? {
        guard var components = URLComponents(string: link),
              ["http", "https"].contains(components.scheme?.lowercased()) else { return nil }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "preview" }
        items.append(URLQueryItem(name: "preview", value: "true"))
        components.queryItems = items
        return components.url
    }

    nonisolated static func publishButtonTitle(status: PostStatus, isLocal: Bool, isPublishedRemote: Bool) -> String {
        switch status {
        case .draft:
            if isLocal { return "Save to WordPress" }
            return isPublishedRemote ? "Switch to Draft" : "Save Draft"
        case .future: return "Schedule"
        case .pending: return "Submit for Review"
        case .private: return "Publish Privately"
        case .publish: return isPublishedRemote ? "Update" : "Publish"
        }
    }

    // The paperplane is reserved for actions that publish or queue the post.
    nonisolated static func publishButtonIcon(status: PostStatus, isPublishedRemote: Bool) -> String {
        switch status {
        case .draft: return "icloud.and.arrow.up"
        case .publish where isPublishedRemote: return "arrow.up.circle"
        default: return "paperplane"
        }
    }

    // WordPress publishes a past-dated "future" post at once, so it is sent as what it becomes.
    nonisolated static func effectiveStatus(_ status: PostStatus, settings: PostSettings, now: Date = Date()) -> PostStatus {
        status == .future && settings.scheduledDateHasPassed(now: now) ? .publish : status
    }

    nonisolated static func pastScheduleMessage(for date: Date) -> String {
        "This time has already passed. WordPress will publish the post now, dated \(date.formatted(date: .abbreviated, time: .shortened))."
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

    // WordPress writes an author's draft preview straight into the post; other statuses get a separate autosave.
    nonisolated static func previewOverwritesPost(status: String) -> Bool {
        status == PostStatus.draft.rawValue
    }

    private func openPreview(force: Bool = false) async {
        guard let creds = appState.credentials, let post = remotePost else { return }
        bannerError = bannerError?.clearing(.preview)
        await editorHandle.flushPendingContent()
        if let reason = writeBlockedReason("preview") {
            bannerError = EditorBanner(message: reason, source: .preview)
            return
        }
        let client = WordPressClient(credentials: creds)
        let payload = PostPayload(title: title, content: htmlContent, excerpt: Self.plainExcerpt(settings.excerpt),
                                  status: post.status, footnotes: footnotesMeta)
        let overwritesPost = Self.previewOverwritesPost(status: post.status)
        let previewedItemID = item.id
        do {
            if overwritesPost && !force {
                let current =
                    post.type == "page"
                    ? try await client.fetchPage(id: post.id)
                    : try await client.fetchPost(id: post.id)
                guard loadedItem?.id == previewedItemID else { return }
                if current.modified != lastSavedServerModified {
                    conflictFromPreview = true
                    showConflictAlert = true
                    return
                }
            }
            let autosave =
                post.type == "page"
                ? try await client.createPageAutosave(postID: post.id, payload: payload)
                : try await client.createAutosave(postID: post.id, payload: payload)
            // WordPress drops meta when a draft preview writes the post itself, leaving new markers with old notes.
            if overwritesPost {
                try await client.updateFootnotes(postID: post.id, type: post.type, footnotes: payload.footnotes ?? "")
            }
            let linkBase = autosave.link ?? post.link
            guard let url = PostEditorView.previewURL(from: linkBase) else {
                reportError("WordPress returned an invalid preview URL: \(linkBase)", from: .preview, about: previewedItemID)
                return
            }
            NSWorkspace.shared.open(url)
            if overwritesPost {
                if let fresh = try? await (post.type == "page"
                    ? client.fetchPage(id: post.id)
                    : client.fetchPost(id: post.id)), loadedItem?.id == previewedItemID {
                    lastSavedServerModified = fresh.modified
                }
            }
        } catch {
            reportError("Couldn't open the preview: \(error.localizedDescription)", from: .preview, about: previewedItemID)
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
            evaluationError = "Add a Claude API key in Settings under AI Writing."
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
                evaluationError = "Claude's evaluation came back in a form Quill couldn't read. Try again."
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
        aiRequestInFlight = true
        defer { aiRequestInFlight = false }
        bannerError = bannerError?.clearing(.ai)

        // 1. Tell JS to capture the selection and show the loading placeholder.
        //    JS returns { text, context, containerText, containerFrom, containerTo }.
        let opInfo: (text: String, context: String?, containerText: String?, containerFrom: Int?, containerTo: Int?, busy: Bool) = await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("beginAIOperation()") { result, _ in
                if let dict = result as? [String: Any] {
                    continuation.resume(returning: (
                        text: dict["text"] as? String ?? "",
                        context: dict["context"] as? String,
                        containerText: dict["containerText"] as? String,
                        containerFrom: dict["containerFrom"] as? Int,
                        containerTo: dict["containerTo"] as? Int,
                        busy: dict["busy"] as? Bool == true
                    ))
                } else {
                    continuation.resume(returning: ("", nil, nil, nil, nil, false))
                }
            }
        }
        if opInfo.busy { presentToast(Self.aiBusyMessage, style: .info) }
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
            guard !Task.isCancelled else { return }
            // 4. Show result in editor — JS replaces loading placeholder with result and selects it.
            guard let jsonData = try? JSONEncoder().encode(resultHTML),
                  let jsonStr = String(data: jsonData, encoding: .utf8) else { return }

            // Pass container boundaries for structural transforms so JS replaces the whole container
            let showArgs: String
            if needsContainerReplace, let cf = opInfo.containerFrom, let ct = opInfo.containerTo {
                showArgs = "\(jsonStr), \(cf), \(ct)"
            } else {
                showArgs = jsonStr
            }

            let inserted: Bool = await withCheckedContinuation { continuation in
                webView.evaluateJavaScript("showAIResult(\(showArgs))") { result, _ in
                    continuation.resume(returning: result as? Bool == true)
                }
            }
            guard inserted else {
                webView.evaluateJavaScript("discardAIResult()", completionHandler: nil)
                bannerError = EditorBanner(message: "Claude couldn't finish that rewrite. Try again.", source: .ai)
                return
            }

            // 5. Show the accept/discard bar along the bottom of the editor
            resultPanel.show(
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
            guard !Task.isCancelled else { return }
            webView.evaluateJavaScript("discardAIResult()", completionHandler: nil)
            bannerError = EditorBanner(message: Self.aiFailureMessage(for: error), source: .ai)
        }
    }
}
