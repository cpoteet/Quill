# Promote Local Draft Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a local draft is saved or published to WordPress, remove it from the sidebar's Drafts list immediately and transition the editor to the newly created remote post.

**Architecture:** `PostEditorView.save()` already deletes the SQLite record on successful WP creation; the fix adds four `appState` mutations in the same block to sync in-memory state and redirect navigation.

**Tech Stack:** Swift 6, SwiftUI, AppState (@Published), PostEditorView

---

### Task 1: Update `PostEditorView.save()` to sync appState after local→remote promotion

**Files:**
- Modify: `Sources/WPWriterKit/Views/Editor/PostEditorView.swift:359-366`

The `.local(let draft)` case currently ends at line 366. After the `DraftStore.delete` call, add the four state mutations below.

- [ ] **Step 1: Open `PostEditorView.swift` and locate the `.local(let draft)` case**

It looks like this (around line 359):

```swift
case .local(let draft):
    let created =
        draft.type == "page"
        ? try await client.createPage(payload)
        : try await client.createPost(payload)
    let db = try AppDatabase.production()
    try DraftStore(db: db).delete(id: draft.id)
    lastSavedServerModified = created.modified
```

- [ ] **Step 2: Add the four appState mutations immediately after `DraftStore.delete`**

Replace the block above with:

```swift
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
```

- [ ] **Step 3: Build and verify no compiler errors**

```bash
./build.sh
```

Expected: build succeeds, `WPWriter.app` produced with no errors.

- [ ] **Step 4: Manual smoke test**

1. Open WPWriter, go to Local Drafts, create or open a local draft.
2. Click "Save Draft" (sends to WP as status=draft).
3. Verify: draft disappears from the Drafts list; sidebar switches to Posts (or Pages); editor now shows the post as a remote post with the correct content.
4. Repeat step 1-3 with "Publish".
5. Verify: same transition; toast says "Published".

- [ ] **Step 5: Commit**

```bash
git add Sources/WPWriterKit/Views/Editor/PostEditorView.swift
git commit -m "fix: remove local draft from sidebar immediately after WP promotion"
```
