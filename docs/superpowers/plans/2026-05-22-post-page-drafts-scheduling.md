# Post/Page Type Awareness, Draft Publishing, and Scheduling — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make local drafts track post vs page type, make the new-button contextual, make the publish button respect the status picker, and fix scheduled post editing.

**Architecture:** Four self-contained changes layered from the data model outward: (1) SQLite schema migration adds a `type` column to `local_drafts`; (2) that type flows through `PostItem` and into the sidebar list labels; (3) `PostEditorView` uses it to route creates to the right endpoint and to drive a dynamic publish button; (4) `PostSettingsPanel` couples the schedule toggle and status picker so they stay in sync and so an existing scheduled post restores its date on open.

**Tech Stack:** Swift 6, SwiftUI (macOS 13+), SQLite.swift, Swift Testing

---

## File Map

| File | Change |
|------|--------|
| `Sources/WPWriterKit/Storage/Database.swift` | Add `draftType` expression; add type column to `CREATE TABLE`; add `ALTER TABLE` migration |
| `Sources/WPWriterKit/Storage/DraftStore.swift` | Add `type` to `LocalDraft`; add `type` param to `create()`; read type in `fetchAll()` |
| `Sources/WPWriterKit/App/AppState.swift` | Update `PostItem.statusBadge` to return type-aware badges |
| `Sources/WPWriterKit/Views/Sidebar/SidebarView.swift` | Pass `type` based on active section in `createNewDraft()` |
| `Sources/WPWriterKit/Views/Sidebar/PostListRow.swift` | Show "post draft" / "page draft" subtitle; add indigo color for page drafts |
| `Sources/WPWriterKit/Views/Editor/PostEditorView.swift` | Fix breadcrumb; route `createPage`/`createPost` by type; dynamic publish button title; load scheduled date |
| `Sources/WPWriterKit/Views/Settings/PostSettingsPanel.swift` | Add `setScheduled(_:)` to `PostSettings`; couple toggle ↔ picker |
| `Tests/WPWriterTests/DraftStoreTests.swift` | Update existing tests; add type-aware tests |

---

## Task 1: Add `type` to `LocalDraft` (Database + DraftStore)

**Files:**
- Modify: `Sources/WPWriterKit/Storage/Database.swift`
- Modify: `Sources/WPWriterKit/Storage/DraftStore.swift`
- Modify: `Tests/WPWriterTests/DraftStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Replace all of `Tests/WPWriterTests/DraftStoreTests.swift` with:

```swift
import Foundation
import Testing
@testable import WPWriterKit

@Suite struct DraftStoreTests {
    var db: AppDatabase
    var store: DraftStore

    init() throws {
        db = try AppDatabase.inMemory()
        store = DraftStore(db: db)
    }

    @Test func createAndFetch() throws {
        let id = try store.create(title: "Test", content: "<p>Hello</p>", excerpt: "", type: "post")
        let drafts = try store.fetchAll()
        #expect(drafts.count == 1)
        #expect(drafts[0].id == id)
        #expect(drafts[0].title == "Test")
        #expect(drafts[0].type == "post")
    }

    @Test func createPageDraft() throws {
        let id = try store.create(title: "About", content: "", excerpt: "", type: "page")
        let drafts = try store.fetchAll()
        #expect(drafts[0].id == id)
        #expect(drafts[0].type == "page")
    }

    @Test func fetchAllPreservesType() throws {
        _ = try store.create(title: "Post Draft", content: "", excerpt: "", type: "post")
        _ = try store.create(title: "Page Draft", content: "", excerpt: "", type: "page")
        let drafts = try store.fetchAll()
        #expect(drafts.count == 2)
        let types = Set(drafts.map(\.type))
        #expect(types == ["post", "page"])
    }

    @Test func update() throws {
        let id = try store.create(title: "Original", content: "", excerpt: "", type: "post")
        try store.update(id: id, title: "Updated", content: "<p>New</p>", excerpt: "Excerpt")
        let drafts = try store.fetchAll()
        #expect(drafts[0].title == "Updated")
        #expect(drafts[0].content == "<p>New</p>")
    }

    @Test func delete() throws {
        let id = try store.create(title: "ToDelete", content: "", excerpt: "", type: "post")
        try store.delete(id: id)
        let drafts = try store.fetchAll()
        #expect(drafts.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests — confirm they fail**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && swift test --filter DraftStoreTests 2>&1 | tail -20
```

Expected: compilation error — `create` has no `type` argument, `LocalDraft` has no `type` property.

- [ ] **Step 3: Add `draftType` expression and migration to `Database.swift`**

In `Sources/WPWriterKit/Storage/Database.swift`, add the `draftType` expression after `draftUpdatedAt`:

```swift
let draftType = Expression<String>("type")
```

In the `migrate()` function, add `t.column(draftType, defaultValue: "post")` to the drafts `create` call, and add the `ALTER TABLE` migration immediately after. The full updated `migrate()` function:

```swift
private func migrate() throws {
    try db.run(drafts.create(ifNotExists: true) { t in
        t.column(draftID, primaryKey: .autoincrement)
        t.column(draftTitle)
        t.column(draftContent)
        t.column(draftExcerpt)
        t.column(draftCreatedAt)
        t.column(draftUpdatedAt)
        t.column(draftType, defaultValue: "post")
    })
    // Migration for existing databases: silently ignored if column already exists
    try? db.run("ALTER TABLE local_drafts ADD COLUMN type TEXT NOT NULL DEFAULT 'post'")

    try db.run(autosaves.create(ifNotExists: true) { t in
        t.column(autosavePostID, primaryKey: true)
        t.column(autosaveTitle)
        t.column(autosaveContent)
        t.column(autosaveSavedAt)
        t.column(autosaveServerModified)
    })

    try db.run(taxonomyCache.create(ifNotExists: true) { t in
        t.column(taxType)
        t.column(taxID)
        t.column(taxName)
        t.column(taxSlug)
        t.column(taxFetchedAt)
        t.primaryKey(taxType, taxID)
    })
}
```

- [ ] **Step 4: Add `type` to `LocalDraft` and update `DraftStore`**

Replace all of `Sources/WPWriterKit/Storage/DraftStore.swift` with:

```swift
import Foundation
import SQLite

public struct LocalDraft: Identifiable, Hashable, Sendable {
    public let id: Int64
    public var title: String
    public var content: String
    public var excerpt: String
    public var type: String          // "post" or "page"
    public var createdAt: Date
    public var updatedAt: Date
}

public final class DraftStore: @unchecked Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    @discardableResult
    public func create(title: String, content: String, excerpt: String, type: String = "post") throws -> Int64 {
        let now = Date().timeIntervalSince1970
        return try db.db.run(db.drafts.insert(
            db.draftTitle <- title,
            db.draftContent <- content,
            db.draftExcerpt <- excerpt,
            db.draftType <- type,
            db.draftCreatedAt <- now,
            db.draftUpdatedAt <- now
        ))
    }

    public func fetchAll() throws -> [LocalDraft] {
        try db.db.prepare(db.drafts.order(db.draftUpdatedAt.desc)).map { row in
            LocalDraft(
                id: row[db.draftID],
                title: row[db.draftTitle],
                content: row[db.draftContent],
                excerpt: row[db.draftExcerpt],
                type: row[db.draftType],
                createdAt: Date(timeIntervalSince1970: row[db.draftCreatedAt]),
                updatedAt: Date(timeIntervalSince1970: row[db.draftUpdatedAt])
            )
        }
    }

    public func update(id: Int64, title: String, content: String, excerpt: String) throws {
        let row = db.drafts.filter(db.draftID == id)
        try db.db.run(row.update(
            db.draftTitle <- title,
            db.draftContent <- content,
            db.draftExcerpt <- excerpt,
            db.draftUpdatedAt <- Date().timeIntervalSince1970
        ))
    }

    public func delete(id: Int64) throws {
        try db.db.run(db.drafts.filter(db.draftID == id).delete())
    }
}
```

- [ ] **Step 5: Run tests — confirm they pass**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && swift test --filter DraftStoreTests 2>&1 | tail -20
```

Expected: `Test run with 5 tests passed`

- [ ] **Step 6: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add Sources/WPWriterKit/Storage/Database.swift Sources/WPWriterKit/Storage/DraftStore.swift Tests/WPWriterTests/DraftStoreTests.swift && git commit -m "feat: add type field to LocalDraft with schema migration"
```

---

## Task 2: Thread Type Through PostItem and PostListRow

**Files:**
- Modify: `Sources/WPWriterKit/App/AppState.swift`
- Modify: `Sources/WPWriterKit/Views/Sidebar/PostListRow.swift`

- [ ] **Step 1: Update `PostItem.statusBadge` in `AppState.swift`**

Find this in `AppState.swift`:

```swift
    public var statusBadge: String {
        switch self {
        case .remote(let p): return p.status
        case .local: return "local"
        }
    }
```

Replace with:

```swift
    public var statusBadge: String {
        switch self {
        case .remote(let p): return p.status
        case .local(let d): return "local-\(d.type)"
        }
    }
```

- [ ] **Step 2: Update `PostListRow` subtitle and status color**

Replace all of `Sources/WPWriterKit/Views/Sidebar/PostListRow.swift` with:

```swift
import SwiftUI

public struct PostListRow: View {
    let item: PostItem

    public init(item: PostItem) {
        self.item = item
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .foregroundStyle(.primary)
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private var statusColor: Color {
        switch item.statusBadge {
        case "publish":     return .green
        case "draft":       return Color.wpAmber
        case "future":      return .blue
        case "local-post":  return .purple
        case "local-page":  return Color(nsColor: .systemIndigo)
        default:            return Color(.tertiaryLabelColor)
        }
    }

    private var subtitle: String {
        switch item {
        case .remote(let post): return formattedDate(post.date)
        case .local(let draft): return "\(draft.type) draft"
        }
    }

    private func formattedDate(_ iso: String) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ssZZZZZ"] {
            df.dateFormat = fmt
            if let date = df.date(from: iso) {
                return date.formatted(date: .abbreviated, time: .omitted)
            }
        }
        return String(iso.prefix(10))
    }
}
```

- [ ] **Step 3: Build to verify no compile errors**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add Sources/WPWriterKit/App/AppState.swift Sources/WPWriterKit/Views/Sidebar/PostListRow.swift && git commit -m "feat: type-aware status badges and draft list labels (post draft / page draft)"
```

---

## Task 3: Contextual New Button in SidebarView

**Files:**
- Modify: `Sources/WPWriterKit/Views/Sidebar/SidebarView.swift`

- [ ] **Step 1: Update `createNewDraft()` to pass type from active section**

Find this in `SidebarView.swift`:

```swift
    private func createNewDraft() {
        guard let id = try? services.draftStore.create(
            title: "Untitled",
            content: "",
            excerpt: ""
        ) else { return }
        if let updated = try? services.draftStore.fetchAll(),
           let newDraft = updated.first(where: { $0.id == id }) {
            appState.localDrafts = updated
            appState.selectedSection = .localDrafts
            appState.selectedItem = .local(newDraft)
        }
    }
```

Replace with:

```swift
    private func createNewDraft() {
        let type = appState.selectedSection == .pages ? "page" : "post"
        guard let id = try? services.draftStore.create(
            title: "Untitled",
            content: "",
            excerpt: "",
            type: type
        ) else { return }
        if let updated = try? services.draftStore.fetchAll(),
           let newDraft = updated.first(where: { $0.id == id }) {
            appState.localDrafts = updated
            appState.selectedSection = .localDrafts
            appState.selectedItem = .local(newDraft)
        }
    }
```

- [ ] **Step 2: Build to verify no compile errors**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add Sources/WPWriterKit/Views/Sidebar/SidebarView.swift && git commit -m "feat: new draft button creates post or page type based on active sidebar section"
```

---

## Task 4: PostSettingsPanel — Schedule/Status Coupling

**Files:**
- Modify: `Sources/WPWriterKit/Views/Settings/PostSettingsPanel.swift`

This task couples the Schedule toggle and Status picker so they always stay in sync, and makes picking "Scheduled" from the picker pre-fill a default date.

- [ ] **Step 1: Add `setScheduled(_:)` to `PostSettings` and update `publishDateSection`**

Replace all of `Sources/WPWriterKit/Views/Settings/PostSettingsPanel.swift` with:

```swift
import SwiftUI

public struct PostSettings: Equatable {
    public var status: String = "draft"
    public var publishDate: Date? = nil
    public var categoryIDs: Set<Int> = []
    public var tagIDs: Set<Int> = []
    public var featuredMediaID: Int = 0
    public var excerpt: String = ""

    public init() {}

    public mutating func setScheduled(_ enabled: Bool) {
        if enabled {
            if publishDate == nil { publishDate = Date().addingTimeInterval(3600) }
            status = "future"
        } else {
            publishDate = nil
            if status == "future" { status = "draft" }
        }
    }
}

public struct PostSettingsPanel: View {
    @Binding var settings: PostSettings
    let categories: [WPCategory]
    let tags: [WPTag]

    public init(settings: Binding<PostSettings>, categories: [WPCategory], tags: [WPTag]) {
        self._settings = settings
        self.categories = categories
        self.tags = tags
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statusSection
                publishDateSection
                categoriesSection
                tagsSection
                excerptSection
            }
            .padding(16)
        }
        .frame(width: 260)
        .background(Color.wpPanelBg)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Status")
            Picker("Status", selection: $settings.status) {
                Text("Draft").tag("draft")
                Text("Published").tag("publish")
                Text("Scheduled").tag("future")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: settings.status) { _ in
                if settings.status == "future" {
                    if settings.publishDate == nil {
                        settings.publishDate = Date().addingTimeInterval(3600)
                    }
                } else {
                    settings.publishDate = nil
                }
            }
        }
    }

    private var publishDateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Publish Date")
            Toggle("Schedule", isOn: Binding(
                get: { settings.publishDate != nil },
                set: { settings.setScheduled($0) }
            ))
            .toggleStyle(.switch)
            if settings.publishDate != nil {
                DatePicker("", selection: Binding(
                    get: { settings.publishDate ?? Date() },
                    set: { settings.publishDate = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
            }
        }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Categories")
            if categories.isEmpty {
                Text("No categories").font(.caption).foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(categories) { cat in
                            Toggle(cat.name, isOn: Binding(
                                get: { settings.categoryIDs.contains(cat.id) },
                                set: { checked in
                                    if checked { settings.categoryIDs.insert(cat.id) }
                                    else { settings.categoryIDs.remove(cat.id) }
                                }
                            ))
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(maxHeight: 210)
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Tags")
            if tags.isEmpty {
                Text("No tags").font(.caption).foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(tags) { tag in
                            Toggle(tag.name, isOn: Binding(
                                get: { settings.tagIDs.contains(tag.id) },
                                set: { checked in
                                    if checked { settings.tagIDs.insert(tag.id) }
                                    else { settings.tagIDs.remove(tag.id) }
                                }
                            ))
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(1.0)
    }

    private var excerptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Excerpt")
            TextEditor(text: $settings.excerpt)
                .frame(height: 70)
                .font(.body)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(.separator, lineWidth: 1)
                )
        }
    }
}
```

- [ ] **Step 2: Build to verify no compile errors**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add Sources/WPWriterKit/Views/Settings/PostSettingsPanel.swift && git commit -m "feat: couple schedule toggle and status picker so they stay in sync"
```

---

## Task 5: PostEditorView — Breadcrumb, Save Routing, Publish Button, Load Date

**Files:**
- Modify: `Sources/WPWriterKit/Views/Editor/PostEditorView.swift`

This task makes four coordinated changes to `PostEditorView`:
1. Breadcrumb shows "Pages" for page-type local drafts
2. Saving a local draft routes to `createPage` or `createPost` based on `draft.type`
3. Publish button title reflects current status setting
4. Opening a scheduled post restores its date

- [ ] **Step 1: Update `breadcrumbSection`**

Find:

```swift
    private var breadcrumbSection: String {
        switch item {
        case .remote(let post): return post.type == "page" ? "Pages" : "Posts"
        case .local: return "Drafts"
        }
    }
```

Replace with:

```swift
    private var breadcrumbSection: String {
        switch item {
        case .remote(let post): return post.type == "page" ? "Pages" : "Posts"
        case .local(let draft): return draft.type == "page" ? "Pages" : "Posts"
        }
    }
```

- [ ] **Step 2: Update `publishButtonTitle` to reflect status**

Find:

```swift
    private var publishButtonTitle: String {
        switch item {
        case .remote(let p): return p.status == "publish" ? "Update" : "Publish"
        case .local: return "Publish"
        }
    }
```

Replace with:

```swift
    private var publishButtonTitle: String {
        switch settings.status {
        case "draft":  return "Save as Draft"
        case "future": return "Schedule"
        case "publish":
            if case .remote(let p) = item, p.status == "publish" { return "Update" }
            return "Publish"
        default: return "Publish"
        }
    }
```

- [ ] **Step 3: Update `publish()` to respect settings.status**

Find:

```swift
    private func publish() async {
        await save(status: settings.status == "future" ? "future" : "publish")
    }
```

Replace with:

```swift
    private func publish() async {
        await save(status: settings.status)
    }
```

- [ ] **Step 4: Add `parseWPDate(_:)` helper**

Add this private helper at the bottom of `PostEditorView`, before the closing `}` of the struct (after `openPreview()`):

```swift
    private func parseWPDate(_ iso: String) -> Date? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ssZZZZZ"] {
            df.dateFormat = fmt
            if let date = df.date(from: iso) { return date }
        }
        return nil
    }
```

- [ ] **Step 5: Load scheduled date in `loadItem()`**

Find the remote branch of `loadItem()`:

```swift
        case .remote(let post):
            title = post.title.rendered
            htmlContent = post.content.raw ?? post.content.rendered
            lastSavedServerModified = post.modified
            settings.status = post.status
            settings.categoryIDs = Set(post.categories)
            settings.tagIDs = Set(post.tags)
            settings.featuredMediaID = post.featuredMedia
```

Replace with:

```swift
        case .remote(let post):
            title = post.title.rendered
            htmlContent = post.content.raw ?? post.content.rendered
            lastSavedServerModified = post.modified
            settings.status = post.status
            settings.categoryIDs = Set(post.categories)
            settings.tagIDs = Set(post.tags)
            settings.featuredMediaID = post.featuredMedia
            if post.status == "future" {
                settings.publishDate = parseWPDate(post.date)
            }
```

- [ ] **Step 6: Update save routing for local drafts**

Find in the `save()` function:

```swift
            case .local(let draft):
                let created = try await client.createPost(payload)
                let db = try AppDatabase.production()
                try DraftStore(db: db).delete(id: draft.id)
                lastSavedServerModified = created.modified
```

Replace with:

```swift
            case .local(let draft):
                let created = draft.type == "page"
                    ? try await client.createPage(payload)
                    : try await client.createPost(payload)
                let db = try AppDatabase.production()
                try DraftStore(db: db).delete(id: draft.id)
                lastSavedServerModified = created.modified
```

- [ ] **Step 7: Build to verify no compile errors**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 8: Run full test suite**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && swift test 2>&1 | tail -10
```

Expected: All tests pass.

- [ ] **Step 9: Commit**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && git add Sources/WPWriterKit/Views/Editor/PostEditorView.swift && git commit -m "feat: dynamic publish button, page draft routing, load scheduled date on open"
```

---

## Task 6: Build, Run, and Verify

- [ ] **Step 1: Final build**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && ./build.sh 2>&1 | tail -5
```

Expected: build succeeds, `WPWriter.app` created.

- [ ] **Step 2: Run tests one final time**

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App" && swift test 2>&1 | tail -10
```

Expected: All tests pass.

- [ ] **Step 3: Launch and smoke-test**

```bash
pkill -x WPWriter 2>/dev/null; sleep 1; open "/Users/Chris/Documents/Claude/WP Mac App/WPWriter.app"
```

Manual checks:
- Browse to Pages section → press ⌘N → new draft appears with "page draft" label (indigo dot)
- Browse to Posts section → press ⌘N → new draft appears with "post draft" label (purple dot)
- Open a local page draft → breadcrumb reads "Pages › Untitled"
- Open Post Settings panel → set Status to "Scheduled" → date picker appears automatically
- Enable Schedule toggle → status picker flips to "Scheduled" automatically
- Main button label changes: Draft → "Save as Draft", Scheduled → "Schedule", Published → "Update"/"Publish"
