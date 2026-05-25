# Local Draft Save Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make "Save Draft" (⌘S) persist local drafts to SQLite only — no WordPress call — and hide the button for remote posts/pages, where ⌘S instead triggers the existing publish/update action.

**Architecture:** Two focused changes to `PostEditorView.swift`. (1) A new `saveLocalOnly()` function handles the SQLite-only path; `saveDraft()` routes to it for `.local` items. (2) The toolbar conditionally shows "Save Draft" only for local items; a hidden button captures ⌘S for remote items and forwards it to `publish()`.

**Tech Stack:** Swift 6, SwiftUI, SQLite.swift via `DraftStore`

---

## Files

- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift`
  - `saveDraft()` routing (line ~398)
  - new `saveLocalOnly()` function (insert after `saveDraft()`)
  - toolbar buttons (lines ~178–190)

---

### Task 1: Add `saveLocalOnly()` and update `saveDraft()` routing

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift`

- [ ] **Step 1: Replace `saveDraft()` and insert `saveLocalOnly()`**

In `PostEditorView.swift`, find the `// MARK: - Save / Publish` section (~line 396). Replace:

```swift
private func saveDraft() async {
    await save(status: "draft")
}
```

With:

```swift
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
```

- [ ] **Step 2: Build to verify no compile errors**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && swift build 2>&1 | tail -20
```

Expected: `Build complete!` with no errors.

- [ ] **Step 3: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
git add Sources/QuillKit/Views/Editor/PostEditorView.swift
git commit -m "feat: add saveLocalOnly() — Save Draft writes to SQLite only for local drafts"
```

---

### Task 2: Update toolbar — hide Save Draft for remote, wire ⌘S

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift`

- [ ] **Step 1: Replace the toolbar buttons block**

In `PostEditorView.swift`, find the toolbar section (~line 178). Replace:

```swift
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
```

With:

```swift
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
```

- [ ] **Step 2: Build to verify no compile errors**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && swift build 2>&1 | tail -20
```

Expected: `Build complete!` with no errors.

- [ ] **Step 3: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
git add Sources/QuillKit/Views/Editor/PostEditorView.swift
git commit -m "feat: hide Save Draft for remote items, wire ⌘S to update action"
```

---

### Task 3: Build app, run, and manually verify

**Files:**
- No file changes — verification only.

- [ ] **Step 1: Build and launch the app**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh && open Quill.app
```

- [ ] **Step 2: Verify — local draft, Save Draft stays local**

1. Press ⌘N to create a new draft post.
2. Type a title and some body text.
3. Press ⌘S (or click "Save Draft").
4. Expected: toast reads **"Saved locally"**. The draft remains in the Drafts section of the sidebar. No WordPress API call is made (confirm by checking the WordPress admin — no new draft post appears).
5. Navigate away (click another post), then click back to the draft.
6. Expected: title and content are restored exactly as typed.

- [ ] **Step 3: Verify — local draft, Publish Draft sends to WordPress**

1. Open a local draft.
2. Click **"Publish Draft"** (or ⌘⇧P).
3. Expected: local draft disappears from the Drafts sidebar. The post appears in the Posts list as a WordPress draft. Toast reads **"Draft saved"**.

- [ ] **Step 4: Verify — local page draft works the same**

1. Navigate to Pages section.
2. Press ⌘N to create a new page draft.
3. Type a title and body.
4. Press ⌘S — expected: toast **"Saved locally"**, page draft stays in Drafts sidebar.
5. Click **"Publish Draft"** — expected: page draft removed, page appears in Pages list on WordPress.

- [ ] **Step 5: Verify — remote post, Save Draft button is hidden**

1. Open any existing post or page from the WordPress-backed list.
2. Expected: **no "Save Draft" button** in the toolbar.
3. Press ⌘S — expected: the post is updated on WordPress (same behavior as clicking the right button). Toast reads **"Draft saved"** (for a draft post) or **"Published"** (for a published post).

- [ ] **Step 6: Verify — remote post, ⌘⇧P still works**

1. With a remote post open, press ⌘⇧P.
2. Expected: same update behavior — post saved to WordPress, toast shown.

- [ ] **Step 7: Commit verification note (no code change)**

If all checks pass, no additional commit needed. The two feature commits from Tasks 1 and 2 are the deliverable.
