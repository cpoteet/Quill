# Quill

Native macOS app for writing and managing WordPress content. Built with Swift Package Manager (no Xcode needed). Implementation complete and running; active polish/iteration phase.

## Build & run

```bash
osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app
```

**Run exactly that after every code change.** `build.sh` replaces the binary under a running process, so skipping the quit leaves the old app running and shows no visible change. If the build fails, report the error instead of opening.

```bash
./test.sh
```

Runs everything — 435 Swift + 1,202 JS tests, all passing as of 2026-09-19 (1,201 JS pass and one is deliberately skipped; that skip is why this line used to read 1,201). Individual suites, what each one covers, the test-suite gotchas, and the manual release checklists: `docs/testing-plan.md`. If you touch a suite, re-run it and correct the counts there.

```bash
./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"
```

**The only test that runs in real WebKit**, and required before release sign-off — the jsdom suites cannot see a WebKit/jsdom divergence, and three have shipped. Needs a current `./build.sh`.

Requirements: Swift 6.3.1, macOS 27, and `node` + `jsdom` installed in **`Scripts/`** (`Scripts/package.json`, gitignored), *not* the project root, which has no `package.json` at all. Consequence: an ad-hoc jsdom probe script must also live in `Scripts/`, or it dies with `Cannot find module 'jsdom'`.

**Computer-use testing goes on a new local draft.** Click "+ New Post" first and discard it when done. Never test edits on a published post or page — one Cmd+Z too many blows past the test edits and undoes the initial content load, emptying the editor.

## Key decisions

- **Stack:** Swift 6, SwiftUI (macOS 27 only — no availability gates), WKWebView, URLSession async/await
- **Editor:** Tiptap 2.x inside WKWebView, loaded from a local bundle (`tiptap-bundle.js` in Resources). Bundled via `./Scripts/bundle-tiptap.sh` (requires `node`). To update Tiptap at any time, just tell Claude "check for new versions of Tiptap" — Claude will check the latest release, update the version in the script if needed, regenerate the bundle, update `editor.html` and `CLAUDE.md`, and rebuild.
- **API:** WordPress REST API with Application Passwords (no plugin required)
- **Storage:** SQLite.swift for local drafts/autosaves; credentials stored as JSON in `~/Library/Application Support/Quill/credentials.json` (chmod 600, not the system keychain — avoids password prompts)
- **URLSession:** Always use `URLSessionConfiguration.ephemeral` (default in `WordPressClient`) — prevents URLSession from touching the system keychain credential store

## Future architecture options

See `docs/future-architecture.md` for deferred design notes: local draft settings persistence (B), image figure-first model (C), LanguageTool grammar checking (D), generic Gutenberg passthrough (E — since implemented as the `gutenbergPassthrough` node; doc entry is the original design context), editor image cache-busting (F), native Pullquote block (G), a Gutenberg fixture-diff harness for automated markup-change detection (H), a gradient-matched title bar (I), and Quick Look for media preview (J).

## Architecture

```
Sources/QuillKit/
  App/              AppState, AppServices, QuillApp, AppSupportDirectory, UpdateChecker
  Auth/             CredentialsStore (file-based, not system keychain)
  API/              WordPressClient, Models (WPPost, WPMedia, WPTaxonomy), MimeType, ImageConversion
  AI/               AnthropicClient, AISettings, AISettingsStore, AIPromptBuilder
  Storage/          Database, DraftStore, AutosaveStore, TaxonomyCache
  Views/
    ContentView.swift
    Editor/         PostEditorView, EditorView, EditorCoordinator, DroppableWebView
                    TitleTextField, LinkPickerView, BlockRiskAlarm
    Sidebar/        SidebarView, PostListRow
    Settings/       PreferencesView, PostSettingsPanel, AboutView
    Media/          MediaLibraryView, MediaGalleryView, MediaPreviewOverlay
                    MediaSidebarSection (filter list), MediaDetailView (inspector)
                    MediaPickerView, GallerySheet
    AI/             GeneratePostSheet, AIResultPanel, SamplePostPickerSheet
  Resources/        editor.html (Tiptap)
                    editor-transforms.js (WordPress HTML transforms, shared with test suite)
                    block-descriptors.js (Tiptap node → Gutenberg block map, used by the save transform)
                    block-settings.js (one entry per block setting; drives the Tiptap attribute, the delimiter key and the toolbar control)
                    block-parser-bundle.js + block-serializer.js (WordPress's own block parser and its inverse; loaded by editor.html for unsupported-block preservation)
  DesignSystem.swift
```

## Key files to know

- `Sources/QuillKit/Resources/editor.html` — the entire Tiptap editor; JS↔Swift bridge via `window.webkit.messageHandlers.*` and `window.*` globals
- `Sources/QuillKit/Resources/editor-transforms.js` — `toWordPressHTML`, `formatHTML`, `countStats`, `findMatches`, the passthrough parse helpers; shared between `editor.html` and the JS test suites, loaded as a plain `<script>` so everything in it is a global
- `Sources/QuillKit/Resources/block-descriptors.js` — Tiptap node → Gutenberg block map; `block-settings.js` — one entry per block setting
- `Sources/QuillKit/Views/Editor/EditorCoordinator.swift` — WKWebView delegate + message handler; handles the insert-image notification
- `Sources/QuillKit/Views/Editor/DroppableWebView.swift` — WKWebView subclass intercepting Finder image drops
- `Sources/QuillKit/API/WordPressClient.swift` — all REST API calls
- `Sources/QuillKit/API/ImageConversion.swift` — HEIC/HEIF → JPEG before upload (WP 7.1 accepts HEIC but can't generate sub-sizes for it); used by all three upload paths
- `Sources/QuillKit/Views/Media/GallerySheet.swift` — native gallery picker; posts `.insertGalleryData`, which `EditorCoordinator` turns into `window.insertGallery(json)`

Concepts that have their own doc:

- **Block model** — adding a block setting, the raw-attribute carrier, unsupported-block preservation, the `gutenbergPassthrough` node: `docs/block-model.md`
- **Footnotes live in post meta, not `post_content`**: `docs/footnotes-meta.md`
- **Code view** — the `</>` toggle and its `_rawHTML` / `_rawHTMLOnLoad` / `_codeViewOriginal` state: `docs/code-view.md`
- **Paste as Markdown (⌘⇧V)** — `AppState.triggerPasteMarkdown` → `PostEditorView.pasteAsMarkdown()` → `window.insertMarkdown(text)`; deliberately bypasses ProseMirror's clipboard plumbing so ⌘V is unaffected

## Maintaining Gutenberg HTML compatibility

All WordPress/Gutenberg HTML compatibility lives in three files:

1. **`toWordPressHTML(html)`** in `editor-transforms.js` (line 16) — called on every save/content-change. Transforms Tiptap's internal HTML into Gutenberg-format HTML before sending to Swift. `renderHTML` on `ResizableImage` now always outputs `<figure><img ...><figcaption/></figure>`; `toWordPressHTML` annotates existing figures (adds classes, moves alignment, handles caption) rather than wrapping bare `<img>` tags. Edit this when WordPress changes expected output format.

2. **`ResizableImage.parseHTML()`** (~line 1079 in `editor.html`) — custom parse rule for `<figure class="wp-block-image">` that extracts image attrs (including alignment) from Gutenberg figure wrappers on load.

3. **`block-descriptors.js`** — maps each Tiptap node name to its Gutenberg block name, shape, `attrsFrom`, and `ownedAttrs`. `wrapInDelimiters` in `editor-transforms.js` emits `<!-- wp:name -->` delimiters for every descriptor, so teaching Quill a new modeled block is a descriptor entry, not another `toWordPressHTML` pass.

See `Sources/QuillKit/Resources/CLAUDE.md` for the current per-element output reference table, and the `update-gutenberg-html-format` skill for the update workflow.

## Gotchas

These two fail silently with the whole test suite green:

- **`build.sh` copies each `Resources/` file by name — a new resource needs its own `cp` line or it 404s at runtime** — the assemble step lists each file individually rather than copying the directory. Swift builds fine and the tests pass (jsdom loads from the source tree), so a missing line shows up only as a silently undefined global in the running app.
- **A top-level `const` in a Resources JS file is NOT reachable as `window.x` from `editor.html`; only `function` declarations are** — classic scripts share one global lexical scope, so a top-level `const` is reachable by *bare identifier* from another classic script but never as a property of `window`/`globalThis`. Since `editor-transforms.js` resolves `block-descriptors.js` as `globalThis` in the browser and as a CommonJS `require` under Node, a `const` reads `undefined` in the app while working perfectly in every Node test. Anything crossing that boundary must be a `function` declaration (`modelsBlockName` is the pattern) or explicitly assigned to `window`. Only the real-`editor.html`-in-jsdom harness catches this class of bug.

**Full text of every cross-cutting gotcha below: `docs/gotchas.md`** — read it when a title looks relevant. File-specific gotchas live in the per-directory `CLAUDE.md` files (`Resources/`, `Views/Editor/`, `API/`, `Views/Media/`, `Views/Sidebar/`, `App/`, `AI/`, `Views/AI/`, `Views/Settings/`, `Views/`), which load only when working in that directory.

- **A carried attribute is a script sink — everything the raw-attribute carrier snapshots gets replayed onto the live contenteditable**
- **The unsupported-block sentinel is a per-save random nonce, and must stay one**
- **The block-risk banner only blocks saving once the body has been edited**
- **`_reportBlocksAtRisk` posts its list on every load and code-view edit, empty list included**
- **New JS dependencies get their own bundle script, not a `bundle-tiptap.sh` edit**
- **Synchronous image work must not run on the main actor**
- **Anything that writes `uploadStatus` must go through `dropTask`**
- **Ad-hoc signing**
- **Editor link colour is one CSS variable per theme**
- **Color tokens & surface components**
- **`Color.wpContentSurface` and `editor.html`'s page colour are one value in two files and must move together**
- **A view placed in an `.inspector` must not set its own width**
- **`SectionLabel` is the one uppercase caption above an inspector or sheet section**
- **Sheet actions go in a bottom bar, never in a top header row**
- **`.textFieldStyle(.plain)` is the house style for every text field**
- **Verify saved draft HTML straight from SQLite rather than through the UI**
- **jsdom and Chrome both lie about ProseMirror's empty-node caret**
- **Background computer-use clicks do not reach the WKWebView's DOM handlers**
- **Unicode curly quotes in Swift strings**

## Docs

- `docs/testing-plan.md` — every test by name, test-suite gotchas, manual release checklists
- `docs/gotchas.md`, `docs/block-model.md`, `docs/code-view.md`, `docs/footnotes-meta.md`
- `docs/editor-gotchas.md` — the 70 `editor.html` gotchas, indexed by title in `Sources/QuillKit/Resources/CLAUDE.md`
- `docs/future-architecture.md` — deferred design notes (A–I)
- `docs/user-guide.md` — end-user guide
- `docs/wordpress-release-audit.md` — markup audit routine, run once per WP major release
- `docs/editor-preview-gaps.md`, `docs/gutenberg-block-snippets.md`, `docs/Privacy.md`
- `docs/superpowers/specs/` and `docs/superpowers/plans/` — one spec + plan pair per feature, named by date
- `Sources/QuillKit/Resources/CLAUDE.md` — per-element Gutenberg output reference table

**After major changes:** run the `claude-md-management:revise-claude-md` skill to keep this file current. Keep it an index — detail belongs in `docs/`.
