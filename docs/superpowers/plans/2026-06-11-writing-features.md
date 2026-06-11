# Five Writing Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add post stats (words/characters/reading time), Private + Pending Review statuses, in-editor find & replace, Gutenberg-compatible embeds, and self-contained footnotes to Quill.

**Architecture:** Five independent phases, ordered smallest to largest, each shippable on its own. Pure logic (counting, match scanning, provider detection, footnote renumbering) goes in `Sources/QuillKit/Resources/editor-transforms.js` so `Scripts/test-editor.js` covers it under Node/jsdom. Editor behavior (Tiptap nodes, ProseMirror plugins, find bar UI) lives in `Sources/QuillKit/Resources/editor.html`. Swift-side state (stats display, status picker) follows the existing `WKScriptMessageHandler` → `EditorCoordinator` callback → `PostEditorView` `@State` pattern.

**Tech Stack:** Swift 6 / SwiftUI, Tiptap 2 (local IIFE bundle — `Plugin`, `PluginKey`, `Decoration`, `DecorationSet` already exported), WKWebView, swift-testing (`@Suite`/`@Test`), Node `node:test` + jsdom.

**Spec:** `docs/superpowers/specs/2026-06-11-writing-features-design.md`

**Project rules that apply to every task:**
- After every Swift or resource change that affects the running app: quit Quill, `./build.sh`, reopen `Quill.app`.
- `./test.sh` runs all tests (Swift + JS). JS only: `node --test Scripts/test-editor.js`. One Swift suite: `swift test --filter <SuiteName>`.
- Commit directly to `main` after each task.
- **Edit-tool gotcha:** when editing `Scripts/test-editor.js`, never let an Edit `old_string` span the unicode test region (~line 277, contains U+2019 as content) — the Edit tool can corrupt ASCII quote delimiters into curly quotes. Append new `describe` blocks at the END of the file. If you ever see `SyntaxError: Invalid or unexpected token` after an edit, fix with a Python byte-level replacement, not another Edit.

---

## Phase 1 — Post stats

### Task 1: `countStats` in editor-transforms.js

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js` (add function + export)
- Test: `Scripts/test-editor.js` (append at end of file)

- [ ] **Step 1: Write the failing tests** — append at the very end of `Scripts/test-editor.js` (before nothing; it's the last line). Also update the require line at the top of the file (line 6) to destructure `countStats`:

```js
const { extractAlignment, toWordPressHTML, formatHTML, countStats } = require('../Sources/QuillKit/Resources/editor-transforms.js')
```

Appended tests:

```js
// ---------------------------------------------------------------------------
// countStats
// ---------------------------------------------------------------------------

describe('countStats', () => {
  test('empty string is zero words, zero characters', () => {
    assert.deepEqual(countStats(''), { words: 0, characters: 0 })
  })

  test('null/undefined input is zero', () => {
    assert.deepEqual(countStats(null), { words: 0, characters: 0 })
    assert.deepEqual(countStats(undefined), { words: 0, characters: 0 })
  })

  test('simple sentence', () => {
    assert.deepEqual(countStats('hello world'), { words: 2, characters: 11 })
  })

  test('multiple spaces and newlines count as one separator', () => {
    assert.equal(countStats('one  two\n\nthree\tfour').words, 4)
  })

  test('leading/trailing whitespace does not add words', () => {
    assert.equal(countStats('  hello  ').words, 1)
  })

  test('whitespace-only string is zero words', () => {
    assert.equal(countStats('   \n\t ').words, 0)
  })

  test('characters counted as code points, not UTF-16 units', () => {
    // 👍 is one code point but two UTF-16 units
    assert.deepEqual(countStats('👍'), { words: 1, characters: 1 })
  })

  test('unicode words count normally', () => {
    assert.equal(countStats('café naïve résumé').words, 3)
  })
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test Scripts/test-editor.js`
Expected: FAIL — `countStats is not a function`

- [ ] **Step 3: Implement** — in `Sources/QuillKit/Resources/editor-transforms.js`, add above the `module.exports` block:

```js
// Word/character counts for the stats display. Words are whitespace-separated
// tokens; characters are Unicode code points (so emoji count as 1).
function countStats(text) {
  const t = text || ''
  const trimmed = t.trim()
  return {
    words: trimmed ? trimmed.split(/\s+/).length : 0,
    characters: Array.from(t).length,
  }
}
```

And extend the export line:

```js
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { extractAlignment, toWordPressHTML, formatHTML, countStats }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test Scripts/test-editor.js`
Expected: PASS (all existing 57 + 8 new)

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/Resources/editor-transforms.js Scripts/test-editor.js
git commit -m "feat: add countStats word/character counter to editor transforms"
```

### Task 2: `PostStats` struct with reading time (Swift)

**Files:**
- Modify: `Sources/QuillKit/Views/Settings/PostSettingsPanel.swift` (add struct at top, after `PostSettings`)
- Test: `Tests/QuillTests/PostEditorHelpersTests.swift` (append tests)

- [ ] **Step 1: Write the failing tests** — append inside the `PostEditorHelpersTests` suite in `Tests/QuillTests/PostEditorHelpersTests.swift`:

```swift
    // MARK: - PostStats reading time

    @Test func readingTimeZeroWordsIsZero() {
        #expect(PostStats(words: 0, characters: 0).readingMinutes == 0)
    }

    @Test func readingTimeShortTextIsOneMinute() {
        #expect(PostStats(words: 1, characters: 5).readingMinutes == 1)
        #expect(PostStats(words: 238, characters: 1000).readingMinutes == 1)
    }

    @Test func readingTimeRoundsUp() {
        #expect(PostStats(words: 239, characters: 1000).readingMinutes == 2)
        #expect(PostStats(words: 1000, characters: 5000).readingMinutes == 5)  // 1000/238 = 4.2 → 5
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter PostEditorHelpersTests`
Expected: FAIL — `cannot find 'PostStats' in scope`

- [ ] **Step 3: Implement** — in `Sources/QuillKit/Views/Settings/PostSettingsPanel.swift`, insert after the closing brace of `PostSettings` (line 27):

```swift
/// Live word/character counts reported by the JS editor. Reading time uses
/// the common 238 words-per-minute average, rounded up, minimum 1 minute.
public struct PostStats: Equatable {
    public var words: Int
    public var characters: Int

    public init(words: Int = 0, characters: Int = 0) {
        self.words = words
        self.characters = characters
    }

    public var readingMinutes: Int {
        guard words > 0 else { return 0 }
        return max(1, Int((Double(words) / 238.0).rounded(.up)))
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter PostEditorHelpersTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/Views/Settings/PostSettingsPanel.swift Tests/QuillTests/PostEditorHelpersTests.swift
git commit -m "feat: add PostStats struct with reading-time calculation"
```

### Task 3: Wire stats from JS to the settings panel

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` (post stats on change)
- Modify: `Sources/QuillKit/Views/Editor/EditorCoordinator.swift` (handle `statsChanged`)
- Modify: `Sources/QuillKit/Views/Editor/EditorView.swift` (register handler, new callback param)
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift` (hold `@State`, pass to panel)
- Modify: `Sources/QuillKit/Views/Settings/PostSettingsPanel.swift` (Stats section)

- [ ] **Step 1: editor.html — post stats.** Add a helper right after the `editor.on('update', …)` block (~line 1516), and call it from three places:

```js
    function _postStats() {
      window.webkit?.messageHandlers?.statsChanged?.postMessage(countStats(editor.getText()))
    }
```

(a) Inside the existing `editor.on('update')` debounce callback, after the `contentChanged` postMessage:

```js
    editor.on('update', () => {
      _rawHTML = null
      clearTimeout(debounce)
      debounce = setTimeout(() => {
        if (window.webkit?.messageHandlers?.contentChanged) {
          window.webkit.messageHandlers.contentChanged.postMessage(toWordPressHTML(editor.getHTML()))
        }
        _postStats()
      }, 500)
    })
```

(b) At the end of `window.setContent` (after `clearTimeout(debounce)`), add `_postStats()` — so stats appear when a post loads.

(c) At the end of `_exitCodeView()` (after the manual `contentChanged` postMessage), add `_postStats()` — code-view edits update stats on exit. (Stats freeze while code view is active, per spec.)

- [ ] **Step 2: EditorCoordinator.swift.** Add the callback property next to `onSelectionChanged` (line 15):

```swift
    var onStatsChanged: ((Int, Int) -> Void)?
```

Add a case to the `switch message.name` (before `default:`):

```swift
        case "statsChanged":
            if let body = message.body as? [String: Any],
               let words = body["words"] as? Int,
               let characters = body["characters"] as? Int {
                DispatchQueue.main.async { self.onStatsChanged?(words, characters) }
            }
```

- [ ] **Step 3: EditorView.swift.** Add the property + init param (default `nil`, alongside `onSelectionChanged`):

```swift
    var onStatsChanged: ((Int, Int) -> Void)?
```

In `makeNSView`, register the handler with the others:

```swift
        config.userContentController.add(context.coordinator, name: "statsChanged")
```

And assign in BOTH `makeNSView` and `updateNSView` (next to the `onSelectionChanged` assignments):

```swift
        context.coordinator.onStatsChanged = onStatsChanged
```

- [ ] **Step 4: PostEditorView.swift.** Add state (near the other `@State` vars):

```swift
    @State private var stats = PostStats()
```

Add the callback in the `EditorView(...)` call (after `onSelectionChanged:`):

```swift
                        onStatsChanged: { words, characters in
                            stats = PostStats(words: words, characters: characters)
                        },
```

Pass to the panel:

```swift
                PostSettingsPanel(
                    settings: $settings,
                    postType: postType,
                    categories: appState.categories,
                    tags: appState.tags,
                    pages: availableParentPages,
                    stats: stats
                )
```

- [ ] **Step 5: PostSettingsPanel.swift.** Add property + init param (default keeps other call sites compiling):

```swift
    let stats: PostStats
```

In `init`, add `stats: PostStats = PostStats()` as the last parameter and `self.stats = stats`. Add `statsSection` as the last entry of the `VStack` in `body` (after `discussionSection`), and the section itself after `discussionSection`:

```swift
    // MARK: - Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Stats")
            VStack(alignment: .leading, spacing: 3) {
                Text("\(stats.words.formatted()) words · \(stats.characters.formatted()) characters")
                if stats.readingMinutes > 0 {
                    Text("\(stats.readingMinutes) min read")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
```

- [ ] **Step 6: Build and verify manually**

Run: `./test.sh` — expected: all pass.
Run: `./build.sh && open Quill.app`
Verify: open a post → open the settings panel (sidebar.right button) → Stats shows non-zero words/characters and a "N min read" line. Type a sentence → counts update within ~1 s. Open code view → type → counts hold; exit code view → counts update. Open an empty new draft → "0 words · 0 characters", no read-time line.

- [ ] **Step 7: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Sources/QuillKit/Views/Editor/EditorCoordinator.swift Sources/QuillKit/Views/Editor/EditorView.swift Sources/QuillKit/Views/Editor/PostEditorView.swift Sources/QuillKit/Views/Settings/PostSettingsPanel.swift
git commit -m "feat: live word count, character count, and reading time in settings panel"
```

---

## Phase 2 — Private + Pending Review statuses

### Task 4: Status helper logic (Swift, TDD)

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift` (static helpers)
- Modify: `Sources/QuillKit/Views/Settings/PostSettingsPanel.swift` (`PostSettings.statusDidChange`)
- Test: `Tests/QuillTests/PostEditorHelpersTests.swift`

- [ ] **Step 1: Write the failing tests** — append inside `PostEditorHelpersTests`:

```swift
    // MARK: - Status helpers

    @Test func publishButtonTitlePerStatus() {
        #expect(PostEditorView.publishButtonTitle(status: "draft", isPublishedRemote: false) == "Publish Draft")
        #expect(PostEditorView.publishButtonTitle(status: "future", isPublishedRemote: false) == "Schedule")
        #expect(PostEditorView.publishButtonTitle(status: "pending", isPublishedRemote: false) == "Submit for Review")
        #expect(PostEditorView.publishButtonTitle(status: "private", isPublishedRemote: false) == "Publish Privately")
        #expect(PostEditorView.publishButtonTitle(status: "publish", isPublishedRemote: false) == "Publish")
        #expect(PostEditorView.publishButtonTitle(status: "publish", isPublishedRemote: true) == "Update")
    }

    @Test func toastMessagePerStatus() {
        #expect(PostEditorView.toastMessage(forStatus: "publish") == "Published")
        #expect(PostEditorView.toastMessage(forStatus: "future") == "Scheduled")
        #expect(PostEditorView.toastMessage(forStatus: "pending") == "Submitted for review")
        #expect(PostEditorView.toastMessage(forStatus: "private") == "Published privately")
        #expect(PostEditorView.toastMessage(forStatus: "draft") == "Draft saved")
    }

    @Test func statusChangeToFutureSetsDefaultDate() {
        var s = PostSettings()
        s.status = "future"
        s.statusDidChange()
        #expect(s.publishDate != nil)
    }

    @Test func statusChangeToPrivateClearsScheduledDate() {
        var s = PostSettings()
        s.status = "future"
        s.statusDidChange()
        s.status = "private"
        s.statusDidChange()
        #expect(s.publishDate == nil)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter PostEditorHelpersTests`
Expected: FAIL — missing `publishButtonTitle`, `toastMessage`, `statusDidChange`

- [ ] **Step 3: Implement.** In `PostSettingsPanel.swift`, add to `PostSettings` (after `setScheduled`):

```swift
    /// Keeps publishDate consistent with the chosen status: entering "future"
    /// seeds a default date one hour out; every other status (including
    /// "private", which WordPress cannot schedule) clears it.
    public mutating func statusDidChange() {
        if status == "future" {
            if publishDate == nil { publishDate = Date().addingTimeInterval(3600) }
        } else {
            publishDate = nil
        }
    }
```

In `PostEditorView.swift`, add static helpers (near `previewURL`):

```swift
    static func publishButtonTitle(status: String, isPublishedRemote: Bool) -> String {
        switch status {
        case "draft": return "Publish Draft"
        case "future": return "Schedule"
        case "pending": return "Submit for Review"
        case "private": return "Publish Privately"
        case "publish": return isPublishedRemote ? "Update" : "Publish"
        default: return "Publish"
        }
    }

    static func toastMessage(forStatus status: String) -> String {
        switch status {
        case "publish": return "Published"
        case "future": return "Scheduled"
        case "pending": return "Submitted for review"
        case "private": return "Published privately"
        default: return "Draft saved"
        }
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter PostEditorHelpersTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/Views/Editor/PostEditorView.swift Sources/QuillKit/Views/Settings/PostSettingsPanel.swift Tests/QuillTests/PostEditorHelpersTests.swift
git commit -m "feat: status helper logic for pending and private statuses"
```

### Task 5: Status picker UI, button/toast wiring, sidebar badges

**Files:**
- Modify: `Sources/QuillKit/Views/Settings/PostSettingsPanel.swift` (picker → dropdown, hide schedule for private)
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift` (use helpers)
- Modify: `Sources/QuillKit/Views/Sidebar/PostListRow.swift` (badge color + subtitle)

- [ ] **Step 1: Replace `statusSection`** in `PostSettingsPanel.swift` (the segmented picker becomes a dropdown with five states; `onChange` delegates to the tested helper):

```swift
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Status")
            Picker("Status", selection: $settings.status) {
                Text("Draft").tag("draft")
                Text("Pending Review").tag("pending")
                Text("Published").tag("publish")
                Text("Scheduled").tag("future")
                Text("Private").tag("private")
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: settings.status) { _ in settings.statusDidChange() }
        }
    }
```

Note: the old picker had no tag for `pending`/`private`, so opening such a post left the control with no selection — the dropdown fixes that bug.

- [ ] **Step 2: Hide the schedule section for private posts.** In `body`, change `publishDateSection` to:

```swift
                if settings.status != "private" { publishDateSection }
```

- [ ] **Step 3: Wire helpers in `PostEditorView.swift`.** Replace the `publishButtonTitle` computed property (lines 325–334) with:

```swift
    private var publishButtonTitle: String {
        var isPublishedRemote = false
        if case .remote(let p) = item, p.status == "publish" { isPublishedRemote = true }
        return Self.publishButtonTitle(status: settings.status, isPublishedRemote: isPublishedRemote)
    }
```

In `save(status:force:)`, replace the toast ternary (line 613) with:

```swift
            toastMessage = Self.toastMessage(forStatus: status)
```

- [ ] **Step 4: Sidebar badges.** In `PostListRow.swift`, add cases to `statusColor`:

```swift
        case "pending": return .orange
        case "private": return .teal
```

And replace `subtitle` so pending/private posts are labeled:

```swift
    private var subtitle: String {
        switch item {
        case .remote(let post):
            let date = formattedDate(post.date)
            switch post.status {
            case "pending": return date + " · Pending"
            case "private": return date + " · Private"
            default: return date
            }
        case .local(let draft): return "\(draft.type.capitalized) Draft"
        }
    }
```

- [ ] **Step 5: Build and verify manually**

Run: `./test.sh` — expected: all pass.
Run: `./build.sh && open Quill.app`
Verify against the live WordPress site:
1. Open a draft → set status to Pending Review → button reads "Submit for Review" → click → toast "Submitted for review" → confirm in wp-admin the post is Pending.
2. Set status to Private → schedule section disappears → button reads "Publish Privately" → click → confirm in wp-admin the post is Private (and invisible logged-out).
3. Sidebar shows orange "· Pending" / teal "· Private" rows; opening each shows the correct dropdown selection (the old broken-selection bug is gone).
4. Scheduled flow still works: status Scheduled → date picker appears → Schedule button.

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/Views/Settings/PostSettingsPanel.swift Sources/QuillKit/Views/Editor/PostEditorView.swift Sources/QuillKit/Views/Sidebar/PostListRow.swift
git commit -m "feat: Private and Pending Review statuses in picker, buttons, and sidebar"
```

---

## Phase 3 — Find & replace

### Task 6: `findMatches` in editor-transforms.js (TDD)

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js`
- Test: `Scripts/test-editor.js` (append at end)

- [ ] **Step 1: Write the failing tests** — append at end of `Scripts/test-editor.js`, and add `findMatches` to the require destructure at line 6:

```js
// ---------------------------------------------------------------------------
// findMatches
// ---------------------------------------------------------------------------

describe('findMatches', () => {
  test('case-insensitive by default', () => {
    assert.deepEqual(findMatches('Hello hello HELLO', 'hello', false), [
      { start: 0, end: 5 }, { start: 6, end: 11 }, { start: 12, end: 17 },
    ])
  })

  test('case-sensitive mode', () => {
    assert.deepEqual(findMatches('Hello hello', 'hello', true), [{ start: 6, end: 11 }])
  })

  test('empty query returns no matches', () => {
    assert.deepEqual(findMatches('anything', '', false), [])
  })

  test('no match returns empty array', () => {
    assert.deepEqual(findMatches('abc', 'xyz', false), [])
  })

  test('regex special characters are treated literally', () => {
    assert.deepEqual(findMatches('price is $5.00 (sale)', '$5.00 (sale)', false), [{ start: 9, end: 21 }])
  })

  test('matches are non-overlapping', () => {
    assert.deepEqual(findMatches('aaa', 'aa', false), [{ start: 0, end: 2 }])
  })

  test('offsets are JS string indices (UTF-16)', () => {
    // 👍 occupies indices 0–1
    assert.deepEqual(findMatches('👍 hi', 'hi', false), [{ start: 3, end: 5 }])
  })
})
```

- [ ] **Step 2: Run to verify failure**

Run: `node --test Scripts/test-editor.js`
Expected: FAIL — `findMatches is not a function`

- [ ] **Step 3: Implement** — add to `editor-transforms.js` above `module.exports` (same escaping pattern as the spell-check regex in editor.html):

```js
// Non-overlapping substring matches for find & replace. Returns JS string
// indices ({ start, end }) on the original text; the editor maps them to
// ProseMirror positions. Query is matched literally (regex chars escaped).
function findMatches(text, query, caseSensitive) {
  if (!query) return []
  const escaped = query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const re = new RegExp(escaped, caseSensitive ? 'g' : 'gi')
  const out = []
  let m
  while ((m = re.exec(text)) !== null) {
    out.push({ start: m.index, end: m.index + m[0].length })
  }
  return out
}
```

Add `findMatches` to `module.exports`.

- [ ] **Step 4: Run to verify pass**

Run: `node --test Scripts/test-editor.js`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/Resources/editor-transforms.js Scripts/test-editor.js
git commit -m "feat: findMatches scanning logic for find & replace"
```

### Task 7: Find bar UI + ProseMirror highlight plugin

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` (all changes in this task)

- [ ] **Step 1: HTML.** Add the find bar markup immediately before `<div id="editor-wrap">` (line 748):

```html
  <div id="find-bar">
    <input id="find-input" type="text" placeholder="Find" spellcheck="false">
    <span id="find-count">0 of 0</span>
    <button id="find-prev" title="Previous match (⇧↩)">‹</button>
    <button id="find-next" title="Next match (↩)">›</button>
    <button id="find-case" title="Match case">Aa</button>
    <span class="find-sep"></span>
    <input id="replace-input" type="text" placeholder="Replace" spellcheck="false">
    <button id="replace-one">Replace</button>
    <button id="replace-all">All</button>
    <button id="find-close" title="Close (Esc)">✕</button>
  </div>
```

- [ ] **Step 2: CSS.** Add inside the `<style>` block (after the AI-writing section, ~line 625):

```css
    /* ── Find & replace ─────────────────────────────── */
    #find-bar {
      display: none;
      align-items: center;
      gap: 6px;
      padding: 6px 12px;
      background: #f4f3f1;
      border-bottom: 1px solid rgba(0,0,0,0.08);
      font-size: 12px;
    }
    #find-bar.visible { display: flex; }
    #find-bar input {
      flex: 0 1 180px;
      padding: 3px 7px;
      font-size: 12px;
      border: 1px solid rgba(0,0,0,0.15);
      border-radius: 5px;
      background: #fff;
      color: inherit;
      outline: none;
    }
    #find-bar input:focus { border-color: #b45309; }
    #find-bar button {
      padding: 3px 8px;
      font-size: 12px;
      border: 1px solid rgba(0,0,0,0.12);
      border-radius: 5px;
      background: #fff;
      cursor: pointer;
    }
    #find-bar button.active { background: #b45309; color: #fff; border-color: #b45309; }
    #find-count { color: #888; min-width: 52px; text-align: center; }
    .find-sep { width: 1px; height: 16px; background: rgba(0,0,0,0.12); margin: 0 4px; }
    .find-match { background: rgba(255, 200, 0, 0.35); border-radius: 2px; }
    .find-match-active { background: rgba(255, 145, 0, 0.6); }
    body.dark #find-bar { background: #2a2a2a; border-bottom-color: rgba(255,255,255,0.1); }
    body.dark #find-bar input,
    body.dark #find-bar button { background: #3a3a3a; border-color: rgba(255,255,255,0.15); color: #eee; }
    body.dark #find-bar button.active { background: #d97706; border-color: #d97706; }
    body.dark .find-match { background: rgba(255, 200, 0, 0.30); }
    body.dark .find-match-active { background: rgba(255, 145, 0, 0.55); }
```

- [ ] **Step 3: Highlight plugin.** Add after the `SpellCheck` extension definition (~line 1186), before `CustomBlockquote`:

```js
    // ── Find & replace highlight ─────────────────────
    const findKey = new PluginKey('findReplace')

    const FindHighlight = Extension.create({
      name: 'findHighlight',
      addProseMirrorPlugins() {
        return [
          new Plugin({
            key: findKey,
            state: {
              init() { return DecorationSet.empty },
              apply(tr, set) {
                const incoming = tr.getMeta(findKey)
                if (incoming !== undefined) return incoming
                return tr.docChanged ? set.map(tr.mapping, tr.doc) : set
              }
            },
            props: {
              decorations(state) { return findKey.getState(state) }
            }
          })
        ]
      }
    })
```

Add `FindHighlight,` to the `extensions:` array of `new Editor({...})` (after `SpellCheck,`).

- [ ] **Step 4: Find logic + events.** Add a new section after the `window.replaceSpellError` function (~line 1570), before the Code view section:

```js
    // ── Find & replace ────────────────────────────────
    let _findOpen = false
    let _findActiveIndex = 0
    let _findMatchPositions = []   // [{ from, to }] in doc positions

    function _collectFindMatches() {
      const query = document.getElementById('find-input').value
      const caseSensitive = document.getElementById('find-case').classList.contains('active')
      const result = []
      if (!query) return result
      editor.state.doc.descendants((node, pos) => {
        if (!node.isTextblock) return true
        // Build the block's text with a char→doc-position map so inline atoms
        // (images, footnote markers) can't shift match offsets.
        let text = ''
        const positions = []
        node.descendants((child, childPos) => {
          if (child.isText) {
            for (let i = 0; i < child.text.length; i++) {
              positions.push(pos + 1 + childPos + i)
              text += child.text[i]
            }
          }
        })
        for (const m of findMatches(text, query, caseSensitive)) {
          result.push({ from: positions[m.start], to: positions[m.end - 1] + 1 })
        }
        return false
      })
      return result
    }

    function _renderFindDecorations() {
      const decos = _findMatchPositions.map((m, i) =>
        Decoration.inline(m.from, m.to, {
          class: i === _findActiveIndex ? 'find-match find-match-active' : 'find-match'
        })
      )
      const { state, dispatch } = editor.view
      dispatch(state.tr.setMeta(findKey, DecorationSet.create(state.doc, decos)))
      document.getElementById('find-count').textContent = _findMatchPositions.length
        ? `${_findActiveIndex + 1} of ${_findMatchPositions.length}`
        : '0 of 0'
    }

    function _scrollToActiveMatch() {
      const m = _findMatchPositions[_findActiveIndex]
      if (!m) return
      try {
        const dom = editor.view.domAtPos(m.from).node
        const el = dom.nodeType === Node.TEXT_NODE ? dom.parentElement : dom
        el?.scrollIntoView({ block: 'center' })
      } catch (_) {}
    }

    function _refreshFind(resetIndex) {
      _findMatchPositions = _collectFindMatches()
      if (resetIndex || _findActiveIndex >= _findMatchPositions.length) _findActiveIndex = 0
      _renderFindDecorations()
    }

    function _stepFind(delta) {
      if (!_findMatchPositions.length) return
      _findActiveIndex = (_findActiveIndex + delta + _findMatchPositions.length) % _findMatchPositions.length
      _renderFindDecorations()
      _scrollToActiveMatch()
    }

    function _openFindBar() {
      if (codeViewActive) return
      _findOpen = true
      document.getElementById('find-bar').classList.add('visible')
      const input = document.getElementById('find-input')
      const sel = window.getSelection()
      if (sel && !sel.isCollapsed) input.value = sel.toString()
      input.focus()
      input.select()
      _refreshFind(true)
      if (_findMatchPositions.length) _scrollToActiveMatch()
    }

    function _closeFindBar() {
      if (!_findOpen) return
      _findOpen = false
      document.getElementById('find-bar').classList.remove('visible')
      _findMatchPositions = []
      const { state, dispatch } = editor.view
      dispatch(state.tr.setMeta(findKey, DecorationSet.empty))
      editor.commands.focus()
    }

    function _replaceActive() {
      const m = _findMatchPositions[_findActiveIndex]
      if (!m) return
      const replacement = document.getElementById('replace-input').value
      // insertText with an empty string deletes the range
      editor.view.dispatch(editor.state.tr.insertText(replacement, m.from, m.to))
      _refreshFind(false)
      _scrollToActiveMatch()
    }

    function _replaceAll() {
      if (!_findMatchPositions.length) return
      const replacement = document.getElementById('replace-input').value
      const tr = editor.state.tr
      // Reverse order so earlier replacements don't shift later positions
      for (const m of [..._findMatchPositions].reverse()) {
        tr.insertText(replacement, m.from, m.to)
      }
      editor.view.dispatch(tr)
      _refreshFind(true)
    }

    document.getElementById('find-input').addEventListener('input', () => _refreshFind(true))
    document.getElementById('find-next').addEventListener('click', () => _stepFind(1))
    document.getElementById('find-prev').addEventListener('click', () => _stepFind(-1))
    document.getElementById('find-case').addEventListener('click', e => {
      e.currentTarget.classList.toggle('active')
      _refreshFind(true)
    })
    document.getElementById('replace-one').addEventListener('click', _replaceActive)
    document.getElementById('replace-all').addEventListener('click', _replaceAll)
    document.getElementById('find-close').addEventListener('click', _closeFindBar)
    document.getElementById('find-input').addEventListener('keydown', e => {
      if (e.key === 'Enter') { e.preventDefault(); _stepFind(e.shiftKey ? -1 : 1) }
    })
    document.addEventListener('keydown', e => {
      if (e.metaKey && !e.shiftKey && !e.altKey && e.key === 'f') {
        e.preventDefault()
        _openFindBar()
      } else if (e.key === 'Escape' && _findOpen) {
        e.preventDefault()
        _closeFindBar()
      }
    })
```

- [ ] **Step 5: Integrations.**
(a) In `editor.on('update', …)` add `if (_findOpen) _refreshFind(false)` as the second line (after `_rawHTML = null`). Note: `_refreshFind` dispatches a meta-only transaction, which does not re-fire `update`, so there is no loop. JS function declarations hoist, so calling `_refreshFind` from the earlier `update` handler is fine — but `_findOpen` is `let`, declared later in the script; updates only fire after full script evaluation, so there is no TDZ issue.
(b) At the top of `_enterCodeView()` add `_closeFindBar()`.
(c) In `window.setContent`, add `_closeFindBar()` before `_rawHTML = html || null`.

- [ ] **Step 6: Build and verify manually**

Run: `./test.sh` — expected: all pass.
Run: `./build.sh && open Quill.app`
Verify in a long post:
1. ⌘F opens the bar; selected text pre-fills the find field; all matches highlight amber, active match darker; counter reads "1 of N".
2. ↩ / ⇧↩ and ‹ › cycle matches and scroll them into view (wrap-around at ends).
3. "Aa" toggles case sensitivity and recounts.
4. Replace replaces the active match and advances; All replaces every match in one undoable step (⌘Z restores all).
5. Typing in the document while the bar is open recounts live.
6. Esc closes and clears highlights; in code view ⌘F does nothing.
7. Find a word that is split by formatting (e.g. "hello **wor**ld", search "world") — it matches.

- [ ] **Step 7: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html
git commit -m "feat: in-editor find & replace bar with match highlighting"
```

---

## Phase 4 — Embeds

### Task 8: Provider detection + transform guards (TDD)

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js`
- Test: `Scripts/test-editor.js` (append at end)

- [ ] **Step 1: Write the failing tests** — append at end of `Scripts/test-editor.js`; add `detectEmbedProvider, embedClassFor` to the require destructure:

```js
// ---------------------------------------------------------------------------
// Embeds — provider detection
// ---------------------------------------------------------------------------

describe('detectEmbedProvider', () => {
  test('youtube.com and youtu.be map to youtube', () => {
    assert.equal(detectEmbedProvider('https://www.youtube.com/watch?v=abc').slug, 'youtube')
    assert.equal(detectEmbedProvider('https://youtu.be/abc').slug, 'youtube')
  })

  test('vimeo maps to vimeo with video type', () => {
    const p = detectEmbedProvider('https://vimeo.com/12345')
    assert.equal(p.slug, 'vimeo')
    assert.equal(p.type, 'video')
  })

  test('x.com and twitter.com map to twitter', () => {
    assert.equal(detectEmbedProvider('https://x.com/user/status/1').slug, 'twitter')
    assert.equal(detectEmbedProvider('https://twitter.com/user/status/1').slug, 'twitter')
  })

  test('unknown host returns null', () => {
    assert.equal(detectEmbedProvider('https://example.com/video'), null)
  })

  test('invalid URL returns null', () => {
    assert.equal(detectEmbedProvider('not a url'), null)
  })
})

describe('embedClassFor', () => {
  test('youtube gets full Gutenberg class list with aspect ratio', () => {
    assert.equal(
      embedClassFor('https://www.youtube.com/watch?v=abc'),
      'wp-block-embed is-type-video is-provider-youtube wp-block-embed-youtube wp-embed-aspect-16-9 wp-has-aspect-ratio'
    )
  })

  test('twitter gets rich type without aspect classes', () => {
    assert.equal(
      embedClassFor('https://x.com/user/status/1'),
      'wp-block-embed is-type-rich is-provider-twitter wp-block-embed-twitter'
    )
  })

  test('unknown provider gets bare wp-block-embed', () => {
    assert.equal(embedClassFor('https://example.com/thing'), 'wp-block-embed')
  })
})

describe('toWordPressHTML — embeds', () => {
  const EMBED = '<figure class="wp-block-embed is-type-video is-provider-youtube wp-block-embed-youtube wp-embed-aspect-16-9 wp-has-aspect-ratio"><div class="wp-block-embed__wrapper">\nhttps://youtu.be/abc\n</div></figure>'

  test('embed figure passes through unchanged', () => {
    assert.equal(wp(EMBED), EMBED)
  })

  test('embed figure does not gain wp-block-image', () => {
    assert.ok(!wp(EMBED).includes('wp-block-image'))
  })

  test('embed figure with caption passes through unchanged', () => {
    const withCaption = EMBED.replace('</figure>', '<figcaption class="wp-element-caption">My <a href="https://e.com">video</a></figcaption></figure>')
    assert.equal(wp(withCaption), withCaption)
  })
})
```

- [ ] **Step 2: Run to verify failure**

Run: `node --test Scripts/test-editor.js`
Expected: FAIL — `detectEmbedProvider is not a function` (the pass-through tests may incidentally pass; the function tests must fail)

- [ ] **Step 3: Implement** in `editor-transforms.js` above `module.exports`:

```js
// Embed provider table. `aspect: true` providers get Gutenberg's 16:9 classes.
const EMBED_PROVIDERS = [
  { slug: 'youtube',    type: 'video', aspect: true,  hosts: ['youtube.com', 'www.youtube.com', 'm.youtube.com', 'youtu.be'] },
  { slug: 'vimeo',      type: 'video', aspect: true,  hosts: ['vimeo.com', 'www.vimeo.com', 'player.vimeo.com'] },
  { slug: 'twitter',    type: 'rich',  aspect: false, hosts: ['twitter.com', 'www.twitter.com', 'x.com', 'www.x.com'] },
  { slug: 'spotify',    type: 'rich',  aspect: false, hosts: ['open.spotify.com', 'spotify.com'] },
  { slug: 'soundcloud', type: 'rich',  aspect: false, hosts: ['soundcloud.com', 'www.soundcloud.com'] },
  { slug: 'tiktok',     type: 'video', aspect: false, hosts: ['tiktok.com', 'www.tiktok.com'] },
  { slug: 'instagram',  type: 'rich',  aspect: false, hosts: ['instagram.com', 'www.instagram.com'] },
]

function detectEmbedProvider(url) {
  let host
  try { host = new URL(url).hostname.toLowerCase() } catch (_) { return null }
  for (const p of EMBED_PROVIDERS) {
    if (p.hosts.includes(host)) return p
  }
  return null
}

// Gutenberg figure class for an embed URL — class order matches what the
// block editor emits. Unknown providers get the bare class; WordPress still
// resolves those via oEmbed at render time.
function embedClassFor(url) {
  const p = detectEmbedProvider(url)
  if (!p) return 'wp-block-embed'
  let cls = `wp-block-embed is-type-${p.type} is-provider-${p.slug} wp-block-embed-${p.slug}`
  if (p.aspect) cls += ' wp-embed-aspect-16-9 wp-has-aspect-ratio'
  return cls
}
```

In `toWordPressHTML`, change the image-figure selector (line 29) so embed figures are explicitly excluded (the `!img` guard already skips them, but the explicit selector documents intent and protects against future embed cards containing thumbnails):

```js
  div.querySelectorAll('figure:not(.wp-block-table):not(.wp-block-embed)').forEach(figure => {
```

Add both functions to `module.exports`.

- [ ] **Step 4: Run to verify pass**

Run: `node --test Scripts/test-editor.js`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/Resources/editor-transforms.js Scripts/test-editor.js
git commit -m "feat: embed provider detection and Gutenberg embed class mapping"
```

### Task 9: `EmbedBlock` node, placeholder card, insert popover

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` (all changes in this task)

- [ ] **Step 1: Node + NodeView.** Add after the `Cite` node definition (~line 1153), before the `SpellCheck` section:

```js
    // ── Embed block ───────────────────────────────────
    // Atomic block storing the embed URL. Saved HTML is the Gutenberg embed
    // figure; in the editor it renders as a static placeholder card (no
    // third-party network requests).
    class EmbedNodeView {
      constructor(node) {
        this.dom = document.createElement('div')
        this.dom.className = 'embed-card'
        const p = detectEmbedProvider(node.attrs.url)
        const provider = document.createElement('div')
        provider.className = 'embed-card-provider'
        provider.textContent = p
          ? p.slug.charAt(0).toUpperCase() + p.slug.slice(1) + ' embed'
          : 'Embed'
        const url = document.createElement('div')
        url.className = 'embed-card-url'
        url.textContent = node.attrs.url
        const hint = document.createElement('div')
        hint.className = 'embed-card-hint'
        hint.textContent = 'Renders on your published site'
        this.dom.append(provider, url, hint)
      }
      selectNode()   { this.dom.classList.add('selected') }
      deselectNode() { this.dom.classList.remove('selected') }
    }

    const EmbedBlock = TiptapNode.create({
      name: 'embedBlock',
      group: 'block',
      atom: true,
      draggable: true,
      priority: 110,  // parse figure.wp-block-embed before generic figure rules

      addAttributes() {
        return {
          url:     { default: '' },
          // Raw <figcaption> outerHTML from loaded posts, re-emitted verbatim.
          // Caption editing is out of scope (v1) but content is never lost.
          caption: { default: null },
        }
      },

      parseHTML() {
        return [{
          tag: 'figure.wp-block-embed',
          getAttrs: el => {
            const wrapper = el.querySelector('.wp-block-embed__wrapper')
            const url = wrapper ? wrapper.textContent.trim() : ''
            if (!url) return false
            const fc = el.querySelector('figcaption')
            return { url, caption: fc ? fc.outerHTML : null }
          },
        }]
      },

      renderHTML({ node }) {
        // Built via DOM (a DOMOutputSpec may be a DOM node) because the
        // wrapper requires raw newline text around the URL and the caption is
        // raw HTML — neither is expressible in the array spec format.
        const figure = document.createElement('figure')
        figure.className = embedClassFor(node.attrs.url)
        const wrapper = document.createElement('div')
        wrapper.className = 'wp-block-embed__wrapper'
        wrapper.appendChild(document.createTextNode('\n' + node.attrs.url + '\n'))
        figure.appendChild(wrapper)
        if (node.attrs.caption) figure.insertAdjacentHTML('beforeend', node.attrs.caption)
        return figure
      },

      addNodeView() {
        return ({ node }) => new EmbedNodeView(node)
      },
    })
```

Add `EmbedBlock,` to the `extensions:` array (after `ResizableImage.configure(...)`).

- [ ] **Step 2: CSS.** Add to the `<style>` block:

```css
    /* ── Embed card ─────────────────────────────────── */
    .embed-card {
      margin: 1em 0;
      padding: 14px 16px;
      border: 1px solid rgba(0,0,0,0.14);
      border-radius: 8px;
      background: rgba(0,0,0,0.025);
      cursor: default;
      user-select: none;
    }
    .embed-card.selected { outline: 2px solid #b45309; outline-offset: 1px; }
    .embed-card-provider { font-weight: 600; font-size: 13px; margin-bottom: 3px; }
    .embed-card-url { font-size: 12px; color: #777; word-break: break-all; }
    .embed-card-hint { font-size: 11px; color: #999; margin-top: 6px; font-style: italic; }
    body.dark .embed-card { border-color: rgba(255,255,255,0.18); background: rgba(255,255,255,0.04); }
    body.dark .embed-card-url { color: #999; }
    body.dark .embed-card-hint { color: #777; }
    #embed-menu {
      display: none;
      position: fixed;
      z-index: 60;
      padding: 8px;
      gap: 6px;
      background: #fff;
      border: 1px solid rgba(0,0,0,0.15);
      border-radius: 8px;
      box-shadow: 0 4px 18px rgba(0,0,0,0.14);
    }
    #embed-menu.visible { display: flex; }
    #embed-menu input {
      width: 260px;
      padding: 4px 8px;
      font-size: 12px;
      border: 1px solid rgba(0,0,0,0.15);
      border-radius: 5px;
      outline: none;
    }
    #embed-menu input:focus { border-color: #b45309; }
    #embed-menu button {
      padding: 4px 10px;
      font-size: 12px;
      border: none;
      border-radius: 5px;
      background: #b45309;
      color: #fff;
      cursor: pointer;
    }
    body.dark #embed-menu { background: #2e2e2e; border-color: rgba(255,255,255,0.15); }
    body.dark #embed-menu input { background: #3a3a3a; border-color: rgba(255,255,255,0.15); color: #eee; }
```

- [ ] **Step 3: Toolbar button + popover markup.** In the toolbar, add an embed button right after the `link` button (line 679, inside the same `tb-group`):

```html
      <button id="embed-button" title="Insert embed (YouTube, Vimeo, X…)">
        <svg viewBox="0 0 24 24"><rect x="3" y="5" width="18" height="14" rx="2"></rect><path d="m10 9 5 3-5 3z"></path></svg>
      </button>
```

Add the popover markup next to `#heading-menu` (after its closing `</div>`, line 727):

```html
  <div id="embed-menu">
    <input id="embed-url-input" type="text" placeholder="Paste a YouTube, Vimeo, X… URL" spellcheck="false">
    <button id="embed-insert-btn">Insert</button>
  </div>
```

- [ ] **Step 4: Popover logic.** Add after the heading-menu wiring (~line 1456):

```js
    // ── Embed insert popover ──────────────────────────
    const embedButton = document.getElementById('embed-button')
    const embedMenu = document.getElementById('embed-menu')

    function _openEmbedMenu() {
      const rect = embedButton.getBoundingClientRect()
      embedMenu.style.left = `${Math.max(rect.left, 8)}px`
      embedMenu.style.top = `${rect.bottom + 8}px`
      embedMenu.classList.add('visible')
      const input = document.getElementById('embed-url-input')
      input.value = ''
      input.focus()
    }

    function _closeEmbedMenu() { embedMenu.classList.remove('visible') }

    function _insertEmbedFromMenu() {
      const raw = document.getElementById('embed-url-input').value.trim()
      let parsed
      try { parsed = new URL(raw) } catch (_) { return }
      if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return
      editor.chain().focus().insertContent({ type: 'embedBlock', attrs: { url: raw } }).run()
      _closeEmbedMenu()
    }

    embedButton.addEventListener('click', e => {
      e.preventDefault()
      embedMenu.classList.contains('visible') ? _closeEmbedMenu() : _openEmbedMenu()
    })
    document.getElementById('embed-insert-btn').addEventListener('click', _insertEmbedFromMenu)
    document.getElementById('embed-url-input').addEventListener('keydown', e => {
      if (e.key === 'Enter')  { e.preventDefault(); _insertEmbedFromMenu() }
      if (e.key === 'Escape') { e.preventDefault(); _closeEmbedMenu() }
    })
    document.addEventListener('mousedown', e => {
      if (!embedMenu.contains(e.target) && !embedButton.contains(e.target)) _closeEmbedMenu()
    })
```

- [ ] **Step 5: Build and verify the Gutenberg round-trip manually**

Run: `./test.sh` — expected: all pass.
Run: `./build.sh && open Quill.app`
Verify against the live WordPress site:
1. Insert a YouTube URL via the toolbar button → static card appears ("Youtube embed", URL, hint). No video loads in the editor.
2. Click the card → amber selection outline; Backspace deletes it; ⌘Z restores it.
3. Save the post → in wp-admin, open the post in the block editor → the embed appears as a proper YouTube block and the front-end renders the player.
4. Reopen the post in Quill → card round-trips intact. Check code view shows the exact figure markup with newlines around the URL.
5. In wp-admin, add a caption to the embed, save, reload in Quill, save again from Quill → caption survives (check `content.raw` via code view).
6. Insert an unknown-host URL → card shows "Embed"; saved HTML is the bare `wp-block-embed` figure.

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html
git commit -m "feat: Gutenberg-compatible embed blocks with static placeholder cards"
```

---

## Phase 5 — Footnotes

### Task 10: Footnote transforms in toWordPressHTML (TDD)

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js`
- Test: `Scripts/test-editor.js` (append at end)

- [ ] **Step 1: Write the failing tests** — append at end of `Scripts/test-editor.js`:

```js
// ---------------------------------------------------------------------------
// toWordPressHTML — footnotes
// ---------------------------------------------------------------------------

describe('toWordPressHTML — footnotes', () => {
  test('marker anchors are numbered in document order', () => {
    const html = '<p>One<sup data-fn="fn-a" class="fn"><a href="#fn-a"></a></sup> two<sup data-fn="fn-b" class="fn"><a href="#fn-b"></a></sup></p>'
    const out = wp(html)
    assert.match(out, /<a href="#fn-a">1<\/a>/)
    assert.match(out, /<a href="#fn-b">2<\/a>/)
  })

  test('renumbering is idempotent and corrects stale numbers', () => {
    const html = '<p><sup data-fn="fn-a" class="fn"><a href="#fn-a">7</a></sup><sup data-fn="fn-b" class="fn"><a href="#fn-b">3</a></sup></p>'
    const out = wp(wp(html))
    assert.match(out, />1<\/a>/)
    assert.match(out, />2<\/a>/)
  })

  test('sup without data-fn is left alone', () => {
    const out = wp('<p><sup>2</sup></p>')
    assert.match(out, /<sup>2<\/sup>/)
  })

  test('footnotes list does not gain wp-block-list', () => {
    const out = wp('<ol class="wp-block-footnotes"><li id="fn-a">Note</li></ol>')
    assert.ok(!out.includes('wp-block-list'))
    assert.match(out, /wp-block-footnotes/)
  })

  test('ordinary ol still gains wp-block-list', () => {
    assert.match(wp('<ol><li>x</li></ol>'), /wp-block-list/)
  })
})
```

- [ ] **Step 2: Run to verify failure**

Run: `node --test Scripts/test-editor.js`
Expected: FAIL — markers not numbered, footnotes ol gains `wp-block-list`

- [ ] **Step 3: Implement** in `toWordPressHTML`:

(a) Change the list-class selector (line 56) to exclude the footnotes list:

```js
  div.querySelectorAll('ul:not([data-type="taskList"]), ol:not(.wp-block-footnotes)').forEach(el => {
    el.classList.add('wp-block-list')
  })
```

(b) Add before the `return div.innerHTML` line:

```js
  // Footnote markers: write 1-based numbers into anchors in document order.
  // The editor leaves anchors empty (CSS counters display numbers live);
  // the saved HTML carries real text so it renders anywhere.
  div.querySelectorAll('sup.fn[data-fn] > a').forEach((a, i) => {
    a.textContent = String(i + 1)
  })
```

- [ ] **Step 4: Run to verify pass**

Run: `node --test Scripts/test-editor.js`
Expected: PASS (including the existing list tests — confirm none broke)

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/Resources/editor-transforms.js Scripts/test-editor.js
git commit -m "feat: footnote marker numbering and footnotes-list handling in transforms"
```

### Task 11: Footnote nodes, insert command, click-to-jump

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`

- [ ] **Step 1: Nodes.** Add after the `EmbedBlock` definition, before the `SpellCheck` section:

```js
    // ── Footnotes ─────────────────────────────────────
    // Self-contained HTML footnotes (see spec): markers are inline atoms
    // <sup data-fn class="fn"><a href="#id"></a></sup>; the list is a literal
    // <ol class="wp-block-footnotes"> pinned at the document end. Marker
    // numbers are rendered by CSS counters in the editor and written as real
    // text by toWordPressHTML on save.
    const FootnoteMarker = TiptapNode.create({
      name: 'footnoteMarker',
      group: 'inline',
      inline: true,
      atom: true,
      priority: 110,
      addAttributes() {
        return { fnId: { default: null } }
      },
      parseHTML() {
        return [{
          tag: 'sup.fn[data-fn]',
          getAttrs: el => ({ fnId: el.getAttribute('data-fn') }),
        }]
      },
      renderHTML({ node }) {
        return ['sup', { 'data-fn': node.attrs.fnId, class: 'fn' },
          ['a', { href: '#' + node.attrs.fnId }]]
      },
    })

    const FootnotesList = TiptapNode.create({
      name: 'footnotesList',
      group: 'block',
      content: 'footnoteItem+',
      defining: true,
      isolating: true,
      priority: 110,  // must out-rank OrderedList's generic 'ol' parse rule
      parseHTML() {
        return [{ tag: 'ol.wp-block-footnotes' }]
      },
      renderHTML() {
        return ['ol', { class: 'wp-block-footnotes' }, 0]
      },
    })

    const FootnoteItem = TiptapNode.create({
      name: 'footnoteItem',
      content: 'inline*',
      defining: true,
      priority: 110,  // must out-rank ListItem's generic 'li' rule for these lis
      addAttributes() {
        return { fnId: { default: null } }
      },
      parseHTML() {
        return [{
          tag: 'ol.wp-block-footnotes > li',
          getAttrs: el => ({ fnId: el.getAttribute('id') }),
        }]
      },
      renderHTML({ node }) {
        return ['li', { id: node.attrs.fnId }, 0]
      },
    })
```

Add `FootnoteMarker, FootnotesList, FootnoteItem,` to the `extensions:` array (after `EmbedBlock,`).

- [ ] **Step 2: CSS.** Add to the `<style>` block:

```css
    /* ── Footnotes ──────────────────────────────────── */
    #editor { counter-reset: quill-footnote; }
    sup.fn { counter-increment: quill-footnote; }
    sup.fn a::before { content: counter(quill-footnote); }
    sup.fn a {
      color: #b45309;
      text-decoration: none;
      font-weight: 600;
      cursor: pointer;
    }
    ol.wp-block-footnotes {
      margin-top: 2.2em;
      padding-top: 0.9em;
      border-top: 1px solid rgba(0,0,0,0.15);
      font-size: 0.85em;
      color: #555;
    }
    body.dark ol.wp-block-footnotes { border-top-color: rgba(255,255,255,0.2); color: #aaa; }
```

- [ ] **Step 3: Insert command + click-to-jump.** Add a section after the find & replace block:

```js
    // ── Footnotes: insert + jump ──────────────────────
    function _findFootnoteItemPos(fnId) {
      let itemPos = null
      editor.state.doc.descendants((node, pos) => {
        if (node.type.name === 'footnoteItem' && node.attrs.fnId === fnId) {
          itemPos = pos
          return false
        }
        return true
      })
      return itemPos
    }

    function insertFootnote() {
      if (codeViewActive) return
      const { state } = editor
      // No footnotes-from-within-footnotes: bail if the cursor is in the list
      const $from = state.selection.$from
      for (let d = $from.depth; d > 0; d--) {
        if ($from.node(d).type.name === 'footnotesList') return
      }
      const fnId = 'fn-' + crypto.randomUUID()
      const schema = state.schema
      const tr = state.tr
      tr.insert(state.selection.from, schema.nodes.footnoteMarker.create({ fnId }))

      // Append the entry to the footnotes list, creating it at the doc end if
      // missing. FootnoteSync (separate plugin) renumbers/reorders afterwards.
      let listPos = null
      let listNode = null
      tr.doc.descendants((node, pos) => {
        if (node.type.name === 'footnotesList') { listPos = pos; listNode = node; return false }
        return true
      })
      const item = schema.nodes.footnoteItem.create({ fnId })
      if (listPos === null) {
        tr.insert(tr.doc.content.size, schema.nodes.footnotesList.create(null, [item]))
      } else {
        tr.insert(listPos + listNode.nodeSize - 1, item)
      }
      editor.view.dispatch(tr)

      // Put the cursor inside the new entry so the user can type immediately
      const itemPos = _findFootnoteItemPos(fnId)
      if (itemPos !== null) {
        editor.chain().focus().setTextSelection(itemPos + 1).scrollIntoView().run()
      }
    }
    window.insertFootnote = insertFootnote

    // Clicking a marker jumps to (and focuses) its entry
    document.getElementById('editor').addEventListener('click', e => {
      const sup = e.target.closest('sup.fn[data-fn]')
      if (!sup) return
      const itemPos = _findFootnoteItemPos(sup.getAttribute('data-fn'))
      if (itemPos !== null) {
        editor.chain().focus().setTextSelection(itemPos + 1).scrollIntoView().run()
      }
    })
```

- [ ] **Step 4: Toolbar button.** Add to the utility `tb-group` (next to `#btn-spell` / `#btn-code-view`, line 694):

```html
      <button id="btn-footnote" title="Insert footnote"><span class="tb-text-icon">x¹</span></button>
```

Wire it near the `btn-spell` listener (~line 1458):

```js
    document.getElementById('btn-footnote').addEventListener('mousedown', e => {
      e.preventDefault()
      insertFootnote()
    })
```

- [ ] **Step 5: Build and smoke-test** (full consistency comes in Task 12)

Run: `./test.sh` — expected: all pass.
Run: `./build.sh && open Quill.app`
Verify: place the cursor mid-paragraph → click x¹ → a superscript "1" appears at the cursor, a numbered list materializes at the document end, and the cursor is inside the empty entry ready to type. Insert a second footnote earlier in the doc → its marker shows the lower number (CSS counters renumber automatically). Click a marker → view jumps to its entry. Code view shows `<sup data-fn="fn-…" class="fn"><a href="#fn-…">1</a></sup>` and `<ol class="wp-block-footnotes">` with numbered anchors.

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html
git commit -m "feat: footnote marker/list nodes with insert command and click-to-jump"
```

### Task 12: `FootnoteSync` consistency plugin

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html`

- [ ] **Step 1: Implement the plugin.** Add after the `FootnoteItem` definition:

```js
    // Keeps the footnotes list consistent with the markers after every doc
    // change: entries follow marker order, orphaned entries are removed,
    // missing entries are created (paste/undo edge cases), and the list
    // itself is removed when the last marker goes. appendTransaction runs
    // again on its own output; the second pass finds everything consistent
    // and returns null, so there is no loop.
    const FootnoteSync = Extension.create({
      name: 'footnoteSync',
      addProseMirrorPlugins() {
        return [
          new Plugin({
            key: new PluginKey('footnoteSync'),
            appendTransaction(transactions, oldState, newState) {
              if (!transactions.some(tr => tr.docChanged)) return null

              const markerIds = []
              let listPos = null
              let listNode = null
              newState.doc.descendants((node, pos) => {
                if (node.type.name === 'footnotesList') {
                  listPos = pos
                  listNode = node
                  return false  // don't collect markers inside the list
                }
                if (node.type.name === 'footnoteMarker' && node.attrs.fnId) {
                  markerIds.push(node.attrs.fnId)
                }
                return true
              })

              if (listPos === null) {
                if (markerIds.length === 0) return null
                const items = markerIds.map(id =>
                  newState.schema.nodes.footnoteItem.create({ fnId: id }))
                return newState.tr.insert(
                  newState.doc.content.size,
                  newState.schema.nodes.footnotesList.create(null, items)
                )
              }

              const currentIds = []
              const itemsById = new Map()
              listNode.forEach(child => {
                currentIds.push(child.attrs.fnId)
                if (child.attrs.fnId) itemsById.set(child.attrs.fnId, child)
              })

              if (currentIds.length === markerIds.length &&
                  currentIds.every((id, i) => id === markerIds[i])) return null

              const tr = newState.tr
              if (markerIds.length === 0) {
                tr.delete(listPos, listPos + listNode.nodeSize)
              } else {
                const desired = markerIds.map(id =>
                  itemsById.get(id) || newState.schema.nodes.footnoteItem.create({ fnId: id }))
                tr.replaceWith(listPos + 1, listPos + listNode.nodeSize - 1, desired)
              }
              return tr
            },
          })
        ]
      },
    })
```

Add `FootnoteSync,` to the `extensions:` array (after `FootnoteItem,`).

- [ ] **Step 2: Build and verify consistency behavior**

Run: `./build.sh && open Quill.app`
Verify:
1. Insert three footnotes A, B, C with distinct text → delete marker B (click just after it, Backspace) → its entry disappears; remaining markers show 1, 2; entries are in marker order.
2. Cut a paragraph containing marker C and paste it ABOVE the paragraph with marker A → the list reorders so C's entry is first.
3. Delete all markers → the list disappears entirely.
4. ⌘Z through all of the above — undo restores markers AND entries together.
5. Save to WordPress → front end shows numbered superscript links jumping to the list.

- [ ] **Step 3: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html
git commit -m "feat: FootnoteSync plugin keeps footnote entries ordered and orphan-free"
```

### Task 13: Footnote context-menu item + full round-trip verification

**Files:**
- Modify: `Sources/QuillKit/Views/Editor/DroppableWebView.swift`

- [ ] **Step 1: Context menu item.** In `buildContextMenu` (after the Cut/Copy/Paste block, before the `aiEnabled` block), add:

```swift
        menu.addItem(.separator())
        let footnote = NSMenuItem(title: "Insert Footnote", action: #selector(insertFootnoteAction), keyEquivalent: "")
        footnote.target = self
        menu.addItem(footnote)
```

Add the action method next to the AI menu actions:

```swift
    @objc private func insertFootnoteAction() {
        evaluateJavaScript("window.insertFootnote?.()", completionHandler: nil)
    }
```

(The current `buildContextMenu` constructs the menu from scratch in `rightMouseDown`, so no allow-list registration is needed — the `WebViewMenuFilter` mentioned in older CLAUDE.md notes no longer exists in this code path.)

- [ ] **Step 2: Build and run the full footnote round-trip**

Run: `./test.sh` — expected: all pass.
Run: `./build.sh && open Quill.app`
Verify:
1. Right-click in the editor → "Insert Footnote" appears and works.
2. Full round-trip: write a post with two footnotes → save → view on the live site (numbered links, list at bottom, jump links work) → reopen in Quill → markers and entries intact, numbering correct → edit a footnote's text → save → site reflects the edit.
3. Open the same post in the WordPress block editor → the list appears as an ordinary List block (accepted trade-off per spec) and content is not corrupted by opening/saving in Gutenberg.

- [ ] **Step 3: Commit**

```bash
git add Sources/QuillKit/Views/Editor/DroppableWebView.swift
git commit -m "feat: Insert Footnote context-menu item"
```

---

## Task 14: Documentation and final verification

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/testing-plan.md`

- [ ] **Step 1: Full test run**

Run: `./test.sh`
Expected: all Swift + JS tests pass (224 + new Swift; 57 + new JS).

- [ ] **Step 2: Update CLAUDE.md.** Add rows to the Gutenberg output table:

```markdown
| `<figure class="wp-block-embed">` (EmbedBlock node) | passes through unchanged — classes emitted by `renderHTML` via `embedClassFor()` |
| Footnote marker `<sup data-fn class="fn">` | anchor text renumbered 1..n in document order |
| `<ol class="wp-block-footnotes">` | excluded from `wp-block-list`; passes through |
```

Add gotchas (Known gotchas section), at minimum:
- Embeds render as static cards via `EmbedNodeView`; `renderHTML` returns a DOM node (not an array spec) because the wrapper needs raw newline text and the caption is raw preserved HTML. Caption editing is unsupported; `caption` attr round-trips verbatim.
- `FootnotesList`/`FootnoteItem`/`FootnoteMarker` use `priority: 110` so their parse rules beat the generic `ol`/`li`/figure rules — do not remove the priority.
- Footnote numbers in the editor come from CSS counters (`sup.fn a::before`); the saved number is written by `toWordPressHTML`. Anchors in the editor DOM are intentionally empty.
- `FootnoteSync` `appendTransaction` rebuilds the list children; deleting a marker deletes its entry (including typed text) by design.
- Find & replace decorations use their own `PluginKey('findReplace')`, separate from spell check; `_refreshFind` dispatches meta-only transactions which do not re-fire `update`.
- Stats freeze in code view and refresh on `_exitCodeView()`/`setContent` via `_postStats()`.

Also update the test-count line in "Test suite status".

- [ ] **Step 3: Update `docs/testing-plan.md`** — add the new JS describes (countStats, findMatches, detectEmbedProvider, embedClassFor, toWordPressHTML — embeds, toWordPressHTML — footnotes) and Swift tests (PostStats reading time, status helpers) with one-line descriptions, plus manual checklist items: stats panel, pending/private publish flows, find & replace, embed round-trip, footnote round-trip.

- [ ] **Step 4: Run the `claude-md-management:revise-claude-md` skill** (per project rules after major changes) to catch anything the manual CLAUDE.md edit missed.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs/testing-plan.md
git commit -m "docs: document stats, statuses, find & replace, embeds, and footnotes"
```

---

## Self-review checklist (already applied)

- **Spec coverage:** Phase 1 → Tasks 1–3; Phase 2 → Tasks 4–5; Phase 3 → Tasks 6–7; Phase 4 → Tasks 8–9; Phase 5 → Tasks 10–13; cross-cutting docs → Task 14.
- **Type consistency:** `countStats`/`findMatches`/`detectEmbedProvider`/`embedClassFor` names match across transforms, exports, require line, and editor.html call sites. `PostStats(words:characters:)`, `onStatsChanged: ((Int, Int) -> Void)?`, `statusDidChange()`, `publishButtonTitle(status:isPublishedRemote:)`, `toastMessage(forStatus:)`, `fnId` attr, `footnoteMarker`/`footnotesList`/`footnoteItem` node names are used consistently across tasks.
- **Known intentional behaviors:** stats freeze in code view; private hides scheduling; replace-all is one undo step; embed captions preserved but not editable; deleting a marker deletes its entry text.
