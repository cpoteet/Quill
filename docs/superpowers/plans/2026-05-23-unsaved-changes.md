# Unsaved Changes — Preserve & Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a user navigates away from a post with unsaved changes, silently flush the editor state to SQLite and restore it when they return, with an amber dot indicating pending unsaved content.

**Architecture:** `PostEditorView` gains a clean-baseline state (`cleanTitle`, `cleanContent`) and a `loadedItem` sentinel. On item change, `loadItem()` flushes dirty state for the old item via `flushToDB(for:)`, then loads new content — checking `AutosaveStore` (remote posts) or `DraftStore` directly (local drafts) for a stash to restore. After a successful WP save the stash is cleared and baselines reset.

**Tech Stack:** Swift 6, SwiftUI, SQLite.swift, Swift Testing (`@Suite`/`@Test`/`#expect`)

---

## File Map

| File | Change |
|------|--------|
| `Sources/QuillKit/Storage/DraftStore.swift` | Add `load(id: Int64) -> LocalDraft?` |
| `Tests/QuillTests/DraftStoreTests.swift` | Add tests for `load(id:)` |
| `Sources/QuillKit/Views/Editor/PostEditorView.swift` | Dirty tracking, flush helper, toolbar dot, modified `loadItem()`, baseline reset in `save()` and `loadFromServer()` |

---

## Task 1: Add `DraftStore.load(id:)` (TDD)

**Files:**
- Modify: `Sources/QuillKit/Storage/DraftStore.swift`
- Modify: `Tests/QuillTests/DraftStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `Tests/QuillTests/DraftStoreTests.swift`, inside the `DraftStoreTests` suite:

```swift
@Test func loadByIdReturnsNilForUnknownId() throws {
    let draft = try store.load(id: 999)
    #expect(draft == nil)
}

@Test func loadByIdReturnsCorrectDraft() throws {
    let id = try store.create(title: "Hello", content: "<p>World</p>", excerpt: "Ex", type: "post")
    let draft = try store.load(id: id)
    #expect(draft != nil)
    #expect(draft?.id == id)
    #expect(draft?.title == "Hello")
    #expect(draft?.content == "<p>World</p>")
    #expect(draft?.excerpt == "Ex")
    #expect(draft?.type == "post")
}

@Test func loadByIdReflectsUpdates() throws {
    let id = try store.create(title: "Old", content: "old", excerpt: "", type: "post")
    try store.update(id: id, title: "New", content: "new", excerpt: "updated")
    let draft = try store.load(id: id)
    #expect(draft?.title == "New")
    #expect(draft?.content == "new")
    #expect(draft?.excerpt == "updated")
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter DraftStoreTests 2>&1 | grep -E "PASS|FAIL|error:|Build"
```

Expected: build succeeds, three tests fail with `value of type 'DraftStore' has no member 'load'`.

- [ ] **Step 3: Implement `load(id:)` in DraftStore**

Add this method to `Sources/QuillKit/Storage/DraftStore.swift`, after the `fetchAll()` method:

```swift
public func load(id: Int64) throws -> LocalDraft? {
    let query = db.drafts.filter(db.draftID == id)
    guard let row = try db.db.pluck(query) else { return nil }
    return LocalDraft(
        id: row[db.draftID],
        title: row[db.draftTitle],
        content: row[db.draftContent],
        excerpt: row[db.draftExcerpt],
        type: row[db.draftType],
        createdAt: Date(timeIntervalSince1970: row[db.draftCreatedAt]),
        updatedAt: Date(timeIntervalSince1970: row[db.draftUpdatedAt])
    )
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter DraftStoreTests 2>&1 | grep -E "PASS|FAIL|error:|Build"
```

Expected: all `DraftStoreTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/Storage/DraftStore.swift Tests/QuillTests/DraftStoreTests.swift
git commit -m "feat: add DraftStore.load(id:) for direct SQLite reads"
```

---

## Task 2: Add Dirty-Tracking State and `flushToDB` Helper

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift`

- [ ] **Step 1: Add state variables**

In `PostEditorView`, replace the existing `@State` block (lines 7–18) with the same variables plus three new ones:

```swift
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
```

- [ ] **Step 2: Add `isDirty` computed var**

Add this computed property after the `availableParentPages` computed var (around line 226):

```swift
private var isDirty: Bool {
    title != cleanTitle || htmlContent != cleanContent
}
```

- [ ] **Step 3: Add `flushToDB(for:)` helper**

Add this method in the `// MARK: - Autosave` section, just before `scheduleAutosave()`:

```swift
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
```

- [ ] **Step 4: Guard `performAutosave` against clean content**

The `scheduleAutosave` fires on every title/content change including the initial load. Guard it so it skips the write when nothing is actually dirty. Replace the current `scheduleAutosave()`:

```swift
private func scheduleAutosave() {
    autosaveTask?.cancel()
    autosaveTask = Task {
        try? await Task.sleep(for: .seconds(30))
        if !Task.isCancelled && isDirty { await performAutosave() }
    }
}
```

- [ ] **Step 5: Build to verify it compiles**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/Views/Editor/PostEditorView.swift
git commit -m "feat: add dirty-tracking state and flushToDB helper to PostEditorView"
```

---

## Task 3: Dirty Indicator in Toolbar

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift`

- [ ] **Step 1: Add amber dot to toolbar**

In the `toolbar` computed var, the `HStack` currently has `Spacer()` then the buttons. Insert the dot just after the `Spacer()`, before the "Save Draft" button:

```swift
Spacer()
// Unsaved-changes indicator
if isDirty {
    Circle()
        .fill(Color.wpAmber)
        .frame(width: 6, height: 6)
}
Button("Save Draft") { Task { await saveDraft() } }
```

- [ ] **Step 2: Build and run**

```bash
./build.sh && open Quill.app
```

- [ ] **Step 3: Manually verify dot behavior**

1. Open a remote post or local draft.
2. Type a character in the title or body — amber dot should appear immediately.
3. Delete the character (restoring original text) — dot should disappear.
4. Type again — dot reappears.
5. Click "Save Draft" — dot disappears after save completes.

- [ ] **Step 4: Commit**

```bash
git add Sources/QuillKit/Views/Editor/PostEditorView.swift
git commit -m "feat: show amber dirty indicator in toolbar when post has unsaved changes"
```

---

## Task 4: Flush on Navigate + Stash Restore in `loadItem()`

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift`

- [ ] **Step 1: Replace `loadItem()` with the full implementation**

Replace the entire existing `loadItem()` function (the `// MARK: - Load` section) with:

```swift
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
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 3: Run app and verify flush + restore for remote posts**

```bash
./build.sh && open Quill.app
```

1. Open a remote post (Posts or Pages section).
2. Make a visible edit to the title (e.g. add " X" to the end).
3. Click a different post in the sidebar **without saving**.
4. Click back to the original post.
5. Expected: the title shows your unsaved edit, and "Unsaved changes restored" toast appears briefly.

- [ ] **Step 4: Verify flush + restore for local drafts**

1. Open a local draft (Local Drafts section).
2. Edit the title.
3. Click a different draft in the sidebar without saving.
4. Click back to the original draft.
5. Expected: your edit is present; toast appears.

- [ ] **Step 5: Verify no spurious restore on unedited posts**

1. Open any post.
2. Do not make any edits.
3. Click another post, then click back.
4. Expected: no toast, content is normal WP content.

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/Views/Editor/PostEditorView.swift
git commit -m "feat: flush unsaved changes on navigate and restore from stash on return"
```

---

## Task 5: Reset Baselines After Save + Clear Stash

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift`

- [ ] **Step 1: Reset baselines after a successful remote-post save**

In the `save()` function, find the `.remote(let post)` branch where `lastSavedServerModified` is updated after a successful save. It looks like:

```swift
let updated = post.type == "page"
    ? try await client.updatePage(id: post.id, payload: payload)
    : try await client.updatePost(id: post.id, payload: payload)
lastSavedServerModified = updated.modified
// Keep appState cache fresh...
```

Immediately after `lastSavedServerModified = updated.modified`, add:

```swift
cleanTitle = title
cleanContent = htmlContent
if let db = try? AppDatabase.production() {
    try? AutosaveStore(db: db).delete(postID: post.id)
}
```

- [ ] **Step 2: Reset baselines after a local draft is published to WP**

In the same `save()` function, find the `.local(let draft)` branch where `appState.selectedItem = .remote(created)` is set. The new `selectedItem` triggers `loadItem()` which will set baselines for the new remote item, so no manual reset is needed here. However, verify that no stale stash for the original post ID lingers (it won't — local drafts use DraftStore, not AutosaveStore).

No code change required for this case.

- [ ] **Step 3: Reset baselines in `loadFromServer()`**

Find `loadFromServer()` and add baseline resets after the content is applied:

```swift
if let post = fetched {
    title = post.title.rendered
    htmlContent = post.content.raw ?? post.content.rendered
    lastSavedServerModified = post.modified
    cleanTitle = title
    cleanContent = htmlContent
}
```

- [ ] **Step 4: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 5: Run app and verify dot disappears after save**

```bash
./build.sh && open Quill.app
```

1. Open a remote post.
2. Edit the title — amber dot appears.
3. Click "Save Draft" — dot disappears, "Draft saved" toast appears.
4. Click another post and return — no "Unsaved changes restored" toast (stash was cleared).

- [ ] **Step 6: Verify restore still works before a save**

1. Edit a post title — dot appears.
2. Navigate away without saving.
3. Return — toast fires, dot is still showing (content differs from WP).
4. Save — dot disappears, no restore toast on next visit.

- [ ] **Step 7: Verify quit-and-reopen preserves unsaved remote-post changes**

1. Edit a remote post title.
2. Navigate away (triggers flush to AutosaveStore).
3. Quit the app entirely.
4. Reopen and navigate to the edited post.
5. Expected: unsaved title is restored, toast shows, dot shows.

- [ ] **Step 8: Commit**

```bash
git add Sources/QuillKit/Views/Editor/PostEditorView.swift
git commit -m "feat: clear stash and reset dirty baselines after successful save"
```

---

## Final Verification

- [ ] Run the full test suite to confirm no regressions:

```bash
swift test 2>&1 | tail -5
```

Expected: all tests pass.
