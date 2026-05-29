# Quill

Native macOS app for writing and managing WordPress content. Built with Swift Package Manager (no Xcode needed).

## Status

Implementation complete and running. Active polish/iteration phase.

## TODO

- [x] Update the side panel for pages to reflect page-specific options (no categories/tags)
- [x] Media capability is completely broken — investigate and fix
- [x] Link button in Tiptap toolbar does not work
- [ ] Post/page title and breadcrumb bars should be white in dark mode
- [x] App title bar changes color when entering/exiting full screen
- [x] Fix page/post title spacing with top border
- [x] After sending a local draft post to WordPress, the local copy should disappear immediately from the draft list
- [x] Remove "New Draft" button from the bottom of the draft listing panel
- [x] Empty state placeholder text should say "post", "page", or "draft" depending on which section is active (currently always says "Select a post to edit")
- [x] Image resizing in the editor — ability to resize images inline, and respect sizes that come from WordPress
- [x] Fix styling and alignment on settings panel
- [x] Add application logo
- [x] Rename application to Quill
- [x] Unsaved changes warning — what should happen when a user navigates away from an editor with unsaved changes (remote or local post/page)?
- [x] New post/page slug field incorrectly inherits slug from the previously selected item — should be blank until the user types one
- [x] Add image alignment buttons to the rich text editor toolbar
- [x] Investigate how the editor HTML output can match what the default WordPress editor (Gutenberg) produces

## Build & run

```bash
./build.sh        # compiles, assembles Quill.app, ad-hoc signs
open Quill.app
```

**After every code change:** quit the app, run `./build.sh`, reopen. Always.

Requirements: Swift 6.3.1 (already installed), macOS 13+.

## Key decisions

- **Stack:** Swift 6, SwiftUI (macOS 13+), WKWebView, URLSession async/await
- **Editor:** Tiptap 2.x inside WKWebView, loaded from a local bundle (`tiptap-bundle.js` in Resources). Bundled via `./Scripts/bundle-tiptap.sh` (requires `node`). To update Tiptap at any time, just tell Claude "check for new versions of Tiptap" — Claude will check the latest release, update the version in the script if needed, regenerate the bundle, update `editor.html` and `CLAUDE.md`, and rebuild.
- **API:** WordPress REST API with Application Passwords (no plugin required)
- **Storage:** SQLite.swift for local drafts/autosaves; credentials stored as JSON in `~/Library/Application Support/Quill/credentials.json` (chmod 600, not the system keychain — avoids password prompts)
- **URLSession:** Always use `URLSessionConfiguration.ephemeral` (default in `WordPressClient`) — prevents URLSession from touching the system keychain credential store

## Future architecture options

### Image node: figure-first model (Approach C)

**Context (as of 2026-05-24):** Image alignment with text wrap was implemented using Approach A — the `ResizableImage` Tiptap extension was extended with an `alignment` attribute, Gutenberg `<figure>` input is parsed via a custom `parseHTML` rule, and a `toWordPressHTML()` JS post-processor re-wraps aligned images in `<figure class="wp-block-image alignXXX">` on every `getContent()` / `contentChanged` call. Internal Tiptap representation stays as `<img class="alignXXX ...">`.

**What Approach C would be:** Replace `ResizableImage` (which uses ProseMirror's `<img>` as its schema element) with a new `WPImage` node whose schema element is `<figure class="wp-block-image">`. The NodeView would render `<figure>` → `<img>` directly rather than a bare `<img>` with a JS wrapper div. `parseHTML` would natively match `figure.wp-block-image`. `renderHTML` would output the full Gutenberg figure structure without any postprocessing step.

**Why it wasn't done now:** Requires rewriting all image-related code — `insertImageAt`, the `insertImage` command, `ImageNodeView` (resize handles, selection, toolbar positioning), `setMediaSizes` round-trip, the `MediaPickerView` insert path, drag-drop in `DroppableWebView`, and every `setNodeMarkup` call. Approach A achieved the same user-visible result with much less churn.

**What a future implementer would need to know:**
- `ResizableImage` is defined entirely in `editor.html` (no Swift changes needed for the node itself). The extension starts at the `const ResizableImage = TiptapImage.extend({...})` block (~line 543).
- `ImageNodeView` is the plain-JS ProseMirror NodeView class above it (~line 349). It manages the wrapper div, resize handles, and the `#image-toolbar` floating panel.
- The `#image-toolbar` positioning logic (`_showImageToolbar`, `_positionImageToolbar`, `_hideImageToolbar`) is tied to `ImageNodeView.wrapper` — a figure-first redesign would need to update these to reference the `<figure>` element instead.
- `insertImageAt` (Swift→JS) calls `editor.chain().setImage(attrs)` — this would need to change to a custom `setWPImage` command that inserts a `figure` node.
- `EditorCoordinator.swift` handles the `insertImage` WKWebView message and calls `insertImageAt` — the Swift side is stable and wouldn't change.
- The `toWordPressHTML()` post-processor (added in Approach A) could be deleted entirely — the node would serialize correctly by default.
- The `parseHTML` rule for `figure.wp-block-image` (added in Approach A) would become the primary parse rule rather than a supplemental one.
- Tiptap's block vs. inline distinction: the current node uses `inline: false` (block image). A figure node should also be block-level. Text wrapping via float still works across sibling block nodes — no model change needed for wrap behavior.

### Local draft settings persistence (Approach B)

**Context (as of 2026-05-25):** Local drafts (SQLite-backed `LocalDraft`) only store `title`, `content`, `excerpt`, and `type`. The "Save Draft" button for local items saves these fields locally without touching WordPress. Post settings configured in the settings panel (categories, tags, slug, featured image, parent page, comment status, publish date) are **not** persisted on local save — they are lost if the user closes the editor before sending to WordPress.

**What Approach B would be:** Expand the `LocalDraft` schema and struct to hold the full set of post settings. Add a DB migration to add columns: `categoryIDs` (JSON array), `tagIDs` (JSON array), `slug`, `featuredMediaID`, `parentID`, `commentStatus`, `publishDate`, `status`. `DraftStore.update()` would accept a `PostSettings` value alongside title/content/excerpt. `PostEditorView.saveLocalOnly()` would pass the current `settings` object. When "Publish Draft" sends the draft to WordPress, the payload would be built from the stored settings rather than just the in-memory panel state.

**Why it wasn't done in the initial pass:** The immediate goal was to stop "Save Draft" from hitting the WordPress API. Expanding the schema requires a SQLite migration, changes to `DraftStore`, and wiring `PostSettings` into the save path — worthwhile but separable work.

**What a future implementer would need to know:**
- `LocalDraft` is defined in `Sources/QuillKit/Storage/DraftStore.swift`. Add new fields here and update `create()`, `update()`, `fetchAll()`, and `load()`.
- `AppDatabase` in `Sources/QuillKit/Storage/Database.swift` defines the SQLite table columns — add new `Expression<T>` properties and include them in the `CREATE TABLE` statement (or add a migration for existing installs).
- `PostSettings` is defined in `Sources/QuillKit/Views/Editor/PostEditorView.swift` (or nearby). Serialise `categoryIDs`/`tagIDs` as JSON strings for storage; deserialise on load.
- `saveLocalOnly()` in `PostEditorView` is the call site — pass the current `settings` value alongside title/content.
- When loading a local draft into the editor (`loadItem()` → `.local` branch), restore settings from the `LocalDraft` fields back into the `settings` state object so the panel reflects the saved values.
- The `PostPayload` built in `save()` for the `.local` → WordPress path already reads from `settings` — no changes needed there once settings are properly restored on load.

### Grammar checking: LanguageTool integration (Approach D)

**Context (as of 2026-05-25):** Spell checking is implemented as an on-demand toolbar button ("ABC") that runs `NSSpellChecker.shared` on the editor text and highlights misspelled words via ProseMirror decorations (`.spell-error` CSS class). Highlights clear on the first edit. Right-click on a highlighted word shows system suggestions via the context menu. No grammar checking beyond what `NSSpellChecker` provides for misspellings.

**What Approach D would be:** Add the `tiptap-languagetool` community Tiptap extension (loadable from a CDN, no npm needed). It calls the free public LanguageTool API (`https://api.languagetool.org/v2/check`) and underlines grammar/style issues with colored markers. Right-clicking an underline shows the suggestion card. Works in 30+ languages. A self-hosted LanguageTool instance (Java, Docker) can be substituted for the public API for privacy or offline use.

**Why it wasn't done in the initial pass:** The macOS native checker is sufficient for most users and requires zero external dependencies. LanguageTool is worthwhile if grammar feedback (subject-verb agreement, passive voice, punctuation) beyond spell correction becomes a priority.

**What a future implementer would need to know:**
- Add `tiptap-languagetool` to `Scripts/bundle-tiptap.sh` (add to `package.json` and `entry.js` exports), re-run the script to regenerate `tiptap-bundle.js`, then add it to the `const { ... } = TiptapBundle` destructure in `editor.html`. Do NOT load it from CDN — the bundle must stay IIFE format for `file://` compatibility.
- Add it to the `extensions: [...]` array in the `new Editor({...})` call, configured with `{ language: 'en-US', apiUrl: 'https://api.languagetool.org/v2/check' }`.
- The extension debounces API calls automatically; no Swift-side changes are needed.
- `spellcheck="true"` and LanguageTool can coexist — the native red squiggles handle individual words while LanguageTool handles multi-word grammar patterns. Consider disabling native spell check (`spellcheck="false"`) if the double-underline visual is noisy.
- The public API has a rate limit (~20 requests/min); a self-hosted instance removes this constraint.
- **macOS 26 note on visual squiggles:** `WKWebView.setValue(true, forKey: "continuousSpellCheckingEnabled")` throws `NSUndefinedKeyException` on macOS 26 (Tahoe) — that KVC key no longer exists. Remove it if present; the HTML `spellcheck="true"` attribute still enables context-menu suggestions. A LanguageTool integration (or a future public WKWebView API) would be the path to visual underlines.

## Architecture

```
Sources/QuillKit/
  App/              AppState, AppServices, QuillApp
  Auth/             KeychainStore (file-based, not system keychain)
  API/              WordPressClient, Models (WPPost, WPMedia, WPTaxonomy)
  AI/               AnthropicClient, AISettings, AISettingsStore, AIPromptBuilder
  Storage/          Database, DraftStore, AutosaveStore, TaxonomyCache
  Views/
    Editor/         PostEditorView, EditorView, EditorCoordinator, DroppableWebView
    Sidebar/        SidebarView, PostListRow
    Settings/       PreferencesView, PostSettingsPanel
    Media/          MediaPickerView
    AI/             GeneratePostSheet, SelectionPillPanel, AIResultPanel, SamplePostPickerSheet
  Resources/        editor.html (Tiptap)
  DesignSystem.swift
```

## Key files to know

- `Sources/QuillKit/Resources/editor.html` — entire Tiptap editor; JS↔Swift bridge via `window.webkit.messageHandlers.*` and `window.*` globals
- `Sources/QuillKit/Views/Editor/EditorCoordinator.swift` — WKWebView delegate + message handler; handles insert-image notification
- `Sources/QuillKit/Views/Editor/DroppableWebView.swift` — WKWebView subclass intercepting Finder image drops
- `Sources/QuillKit/API/WordPressClient.swift` — all REST API calls

## Maintaining Gutenberg HTML compatibility

All WordPress/Gutenberg HTML compatibility lives in two places in `Sources/QuillKit/Resources/editor.html`:

1. **`toWordPressHTML(html)`** (~line 789) — called on every save/content-change. Transforms Tiptap's internal HTML into Gutenberg-format HTML before sending to Swift. Edit this when WordPress changes expected output format.

2. **`ResizableImage.parseHTML()`** (~line 599) — custom parse rule for `<figure class="wp-block-image">` that extracts image attrs (including alignment) from Gutenberg figure wrappers on load.

### What each element currently outputs (as of 2026-05-24)

| Tiptap internal | `toWordPressHTML()` output |
|---|---|
| `<h1>`–`<h6>` | `+ class="wp-block-heading"` |
| `<ul>` (non-task) | `+ class="wp-block-list"`; `<p>` inside `<li>` unwrapped to text node |
| `<ol>` | `+ class="wp-block-list"`; `<p>` inside `<li>` unwrapped to text node |
| `<blockquote>` | `+ class="wp-block-quote"` |
| `<pre>` | `+ class="wp-block-code"` |
| `<img class="alignleft/right/center">` | wrapped in `<figure class="wp-block-image alignXXX">`; `class="wp-image-{id}"` re-emitted when `data-media-id` is set |
| `<table>` | wrapped in `<figure class="wp-block-table">`; first all-`<th>` row promoted from `<tbody>` to `<thead>` |
| Bold, italic, strike, inline code, links, paragraphs | unchanged — already match Gutenberg |

### How to update when WordPress changes its HTML format

1. Check the new format by inspecting a post in a live WordPress site: open a post in the WordPress block editor, add the element in question, save, then view the post's source HTML (or fetch it via the REST API: `GET /wp-json/wp/v2/posts/{id}?context=edit` and look at `content.raw`).

2. Update `toWordPressHTML()` in `editor.html` to emit the new structure. All transforms are DOM operations (create element, add class, reparent) — no regex.

3. If WordPress also changes how it *stores* the format (what the API sends back on load), check whether Tiptap still parses it correctly by loading an existing post. If not, add or update a `parseHTML()` rule on the relevant Tiptap extension. For block elements wrapped in a `<figure>` (like images and tables), add a `getAttrs` rule that extracts the inner element's attrs.

4. Rebuild and test the round-trip: load a post with the affected element → verify it displays correctly in Quill → save → verify the API-stored HTML matches the new expected format.

## Known gotchas

- **Pages endpoint** omits `categories` and `tags` fields — `WPPost` uses `decodeIfPresent` with `[]` defaults; do not make those fields required again
- **`WPPost.type` field** — set to `"post"` or `"page"` by the API; used throughout `PostEditorView` and `WordPressClient` to route to the correct endpoint (`/posts/` vs `/pages/`). Do not remove this field.
- **`WPPost.dateGmt` field** — decoded from `date_gmt` JSON key (UTC). Used in `PostEditorView.loadItem()` for scheduling round-trips. `PostPayload` sends scheduled dates as `dateGmt` (JSON key `date_gmt`) — never use `date` for scheduling; WordPress interprets `date` as site-local time and ignores timezone suffix.
- **WKWebView editor loading** — `editor.html` is loaded via `loadFileURL(_:allowingReadAccessTo:)` pointing to the Resources directory in the app bundle. Do NOT use `loadHTMLString` — there is no longer a CDN import that needs a non-null origin.
- **Tiptap is bundled locally as IIFE** — `Sources/QuillKit/Resources/tiptap-bundle.js` is a minified IIFE bundle (`window.TiptapBundle`) generated by `./Scripts/bundle-tiptap.sh` (requires `node`). No CDN requests at runtime; editor loads instantly from disk. IIFE format is required — `type="module"` + ES module `import` statements do NOT work with `file://` URLs in WKWebView (silent failure, `editorReady` never fires). `editor.html` loads the bundle via `<script src="./tiptap-bundle.js">` and destructures from `TiptapBundle`. To update Tiptap 2.x: re-run the script and rebuild. To upgrade to Tiptap 3.x: bump `"^2"` → `"^3"` in the script's package.json block, verify exports in `entry.js` still exist, and check for API changes in `editor.html`.
- **Credential store** — `WordPressClient` must use ephemeral URLSession; switching to `.shared` will re-introduce keychain prompts during network calls
- **Ad-hoc signing** — `build.sh` signs with `-`; "Always Allow" on keychain prompts won't persist across rebuilds (irrelevant now that credentials use file storage, but WKWebView may still prompt once per binary for its own internal keychain use)
- **Layout uses `HStack + Divider`, not `NavigationSplitView` or `HSplitView`** — `ContentView` uses a plain `HStack(spacing: 0)` with `Divider()` between panels. `NavigationSplitView` reinstates macOS Tahoe sidebar chrome (drop shadows, raised layer). `HSplitView` renders a draggable resize cursor on panel dividers even when frames are fixed. Do NOT switch to either.
- **Sidebar post list is `ScrollView+LazyVStack`, NOT `List`** — SwiftUI's `List` on macOS uses `NSTableRowView` which paints selection blue at the AppKit layer, overriding any SwiftUI modifier. `SidebarView` uses `ScrollView { LazyVStack { ForEach { Button } } }` for full control over selection appearance. Do NOT revert to `List` with a selection binding.
- **Color tokens** — `Color.wpSidebarBg` (#F2F1EF light) and `Color.wpPanelBg` (#F4F3F1 light) are in `DesignSystem.swift` with `NSColor` dynamic providers for dark mode fallback. Use these instead of `NSColor.windowBackgroundColor` in sidebars/panels.
- **Inline taxonomy creation** — `PostSettings.newCategoryNames` / `newTagNames` hold names typed in the panel that don't exist on the server yet. On save/publish, `PostEditorView` calls `createCategory`/`createTag` for each pending name before building the payload, inserts the returned ID into `categoryIDs`/`tagIDs`, and appends the new item to `appState.categories`/`appState.tags`. Do not remove `newCategoryNames`/`newTagNames` — they are the mechanism for deferred creation.
- **`AutosaveResponse` type** — the WordPress autosave endpoint (`/posts/{id}/autosaves`, `/pages/{id}/autosaves`) returns a partial object, not a full `WPPost`. Only `link?` and `parent?` are decoded into `AutosaveResponse`. The preview URL is built as `autosave.link ?? post.link` to handle sites that omit `link` from the autosave response.
- **Trash vs. force-delete** — `WordPressClient.trashPost/trashPage` call `DELETE /posts/{id}?force=false`, which moves to WordPress Trash (recoverable). `force=true` would permanently delete. Do not change the `force` parameter unless permanent deletion is explicitly intended.
- **`performVoid` helper** — `WordPressClient` has a private `performVoid(_:)` alongside `perform<T>(_:)`. Use `performVoid` for DELETE (and any future) calls that don't need to decode a response body. Do not use `perform<T>` with a dummy decodable type just to discard the result.
- **Unicode curly quotes in Swift strings** — Swift treats `"` (U+201C) and `"` (U+201D) as string delimiters, identical to ASCII `"`. Do not use curly quotes inside string literals with interpolation — use escaped ASCII quotes `\"...\(value)...\"` instead.
- **Page-specific settings panel** — `PostSettingsPanel` takes `postType: String` and `pages: [WPPost]`. When `postType == "page"` it shows Parent Page picker + Slug + Discussion (no categories, tags, or excerpt). Posts show categories, tags, slug, excerpt, and discussion. The `isPage` computed var drives all conditional rendering.
- **`WPPost.parent` and `WPPost.commentStatus`** — both use `decodeIfPresent` with defaults (`0` and `"open"`). `PostPayload` sends `parent` only for pages (nil for posts); `commentStatus` is always sent. `slug` is sent only when non-empty (nil omits it from the request, leaving the server value unchanged on update).
- **Delete state in SidebarView** — `itemPendingDelete: PostItem?` drives the confirmation alert; `deleteError: String?` drives the error alert. Both are `@State` locals in `SidebarView`. Setting `itemPendingDelete` non-nil triggers the alert; the confirm button clears it and calls `performDelete` in a `Task`.
- **Context menu — WKWebView (`DroppableWebView`)** — WebKit's Cut/Copy/Paste items use private internal selectors, so filtering by `["cut:", "copy:", "paste:"]` removes them too. In `willOpenMenu`, replace `menu.items` entirely with fresh `NSMenuItem`s using `NSSelectorFromString("cut:")` etc. WKWebView handles these standard selectors through the responder chain with automatic enable/disable. Set `menu.delegate` to an `NSMenuDelegate` that re-filters in `menuWillOpen` to catch AutoFill/Services that macOS appends after `willOpenMenu` returns.
- **Context menu — title field (`TitleTextField`)** — `NSTextField` uses a shared field editor (`NSTextView`); overriding `menu(for:)` on the NSTextField subclass is never called during editing. Use `NSTextView` directly via `NSViewRepresentable` (`RestrictedTextView`) — `menu(for:)` on the NSTextView subclass IS called on right-click. Build a fresh menu with only Cut/Copy/Paste items and set an `NSMenuDelegate` to catch late-appended items. Do NOT try the NSTextField field editor delegate wrapping approach — it is fragile and AutoFill leaks through regardless.
- **`MediaDetails.width`/`height` as floats** — The WordPress REST API returns `media_details.width` and `height` as JSON floating-point numbers (e.g. `2560.0`) for some media items. Swift's `Int` decoder rejects these. `MediaDetails` and `MediaSize` use a try-Int-then-Double pattern in their `init(from:)` to accept both. Do not change these back to a bare `decodeIfPresent(Int.self, ...)` call.
- **Media sidebar when Media tab active** — `SidebarView` hides the post list / search / toolbar when `selectedSection == .media`. The `else { MediaSidebarSection() }` branch fills the sidebar with the thumbnail grid. Do not remove that `else` branch or replace it with `Spacer()`.
- **`MediaPickerView` is picker-only** — The `.browser` case and `MediaPickerMode` enum have been removed. `MediaPickerView` is now a sheet-only picker used for inserting images into the editor. The media sidebar (`MediaSidebarSection`) handles browsing. Do not add a `mode:` parameter back.
- **Media state lives in `AppState`** — `appState.mediaItems`, `appState.selectedMedia`, `appState.isLoadingMedia`, `appState.mediaError` are the single source of truth. `MediaSidebarSection` loads into and reads from these; `ContentView`/`MediaDetailView` observe `selectedMedia` to show the detail view. Pagination state (`currentPage`, `hasMore`) is local to `MediaSidebarSection` — no need to persist it in `AppState`.
- **`deleteMedia` is permanent** — `WordPressClient.deleteMedia(id:)` calls `DELETE /media/{id}?force=true`. WordPress media items have no trash state — deletion is immediate and irreversible. Always show a confirmation alert before calling it.
- **`MediaSidebarCell` uses `Color.clear` overlay, not `AsyncImage` directly** — `AsyncImage` participates in SwiftUI layout and reports its natural image dimensions when loaded, which breaks `LazyVGrid` column sizing (wide images span both columns, rows misalign). The fix: use `Color.clear.frame(minWidth: 0, maxWidth: .infinity, minHeight: 80, maxHeight: 80)` as the layout anchor and put `AsyncImage` inside `.overlay { }`. Overlays fill their parent's bounds without affecting layout, so every cell is always column-width × 80pt. Do not switch back to `AsyncImage` as the root view of the cell.
- **Link picker uses `ObservableObject`, not `@State`, for async search results** — `LinkPickerView` is hosted in an `NSHostingController`/`NSPopover`. `@State` mutations from async `Task {}` closures do NOT trigger SwiftUI re-renders in this context. `LinkPickerModel: ObservableObject` with `@Published` properties uses Combine's `objectWillChange` which reliably triggers re-renders. Do not revert `LinkPickerModel` to `@State` properties on the view.
- **`NSHostingController.sizingOptions = .preferredContentSize` required for dynamic popover resizing** — `NSHostingController` defaults to `sizingOptions = []`, which means `preferredContentSize` is set once at initial layout and never updated. When SwiftUI content grows (e.g. search results appear), the `NSPopover` stays locked at its original height and clips the new content. Set `hosting.sizingOptions = .preferredContentSize` after creating the controller so the popover resizes automatically as content changes.
- **Link picker popover anchors to text selection rect, not toolbar button** — JS sends `showLinkPicker` with `window.getSelection().getRangeAt(0).getBoundingClientRect()` (falls back to the toolbar button rect when nothing is selected). WKWebView is flipped (Y-down, same as JS), so no coordinate conversion is needed — pass the JS rect directly to `NSPopover.show(relativeTo:of:preferredEdge:)` with `preferredEdge: .maxY`.
- **`ResizableImage` Tiptap extension** — `Image` from `@tiptap/extension-image@2` must be imported as a named import (`{ Image as TiptapImage }`) so the default export doesn't shadow the name. `ResizableImage` extends `TiptapImage` and adds `width`, `height`, `mediaId` attributes. It parses standard `<img width="..." height="...">` and `class="wp-image-{id}"` on load; serializes to `width="..."`, `height="..."`, `data-media-id="..."` on output.
- **`ImageNodeView` is a plain JS class, not a React/Svelte component** — registered via `addNodeView()` returning `new ImageNodeView(node, editor, getPos)`. Implements the ProseMirror NodeView interface: `dom`, `update()`, `selectNode()`, `deselectNode()`, `destroy()`, `stopEvent()`, `ignoreMutation()`. `stopEvent` returns `true` for `mousedown` on `.resize-handle` elements so ProseMirror doesn't steal the event.
- **Use `state.tr.setNodeMarkup(pos, null, attrs)` to commit image attribute changes** — do NOT use `editor.chain().updateAttributes()` for the image node; it resets ProseMirror's selection state. `setNodeMarkup` commits only the attributes without touching selection. Always get `pos` from `getPos()` and check `typeof pos === 'number'` before dispatching.
- **`#image-toolbar` is `position: fixed`, not an absolute child of the NodeView** — the toolbar div lives at the body level (inside `#editor-wrap`'s sibling scope) to avoid overflow clipping. Positioned via `getBoundingClientRect()` of the image wrapper. A scroll listener (`tb._scrollHandler`) is attached to `#editor-wrap` when shown and removed when hidden — always clean it up in `_hideImageToolbar()`.
- **`tb._activeNodeView` stored on the toolbar DOM element** — the currently selected `ImageNodeView` instance is stored directly as a property on the `#image-toolbar` element (`tb._activeNodeView`). Toolbar event handlers read this to find the active node. Always null-check it; it is set to `null` by `_hideImageToolbar()`.
- **80 ms delay in `deselectNode()`** — without the `setTimeout(..., 80)`, clicking a toolbar input deselects the image before the input receives focus, which would immediately trigger `_hideImageToolbar()` and close the toolbar. The delay lets the input's `focus` event fire first; the timeout body then re-checks `tb.contains(document.activeElement)` before hiding.
- **`requestMediaSizes` / `setMediaSizes` round-trip** — when an image with a `mediaId` is selected, JS posts `{ mediaId }` to the `requestMediaSizes` WKWebView message handler. Swift's `EditorCoordinator` calls `onRequestMediaSizes?(mediaId)` (a closure wired in `PostEditorView` to `appState.mediaItems.first(where:)`), serializes the result's `mediaDetails.sizes` to JSON, and calls `window.setMediaSizes(id, JSON)` back into the webview. If the media item isn't loaded, `setMediaSizes(id, null)` is sent and named-size buttons stay hidden. Do not forget to register `"requestMediaSizes"` in `EditorView.makeNSView` via `config.userContentController.add(context.coordinator, name: "requestMediaSizes")`.
- **AI feature is gated on API key** — `appState.aiEnabled` returns `false` when `aiSettings` is nil or the API key is empty; the ✦ toolbar button and selection pill are hidden in that state. Settings are stored in `~/Library/Application Support/Quill/ai_settings.json` (chmod 600) via `AISettingsStore`. `AppState.aiSettings` is the runtime source of truth; updating it (via `onSaveAISettings` callback in `PreferencesView`) enables the feature without relaunch.
- **Writing style guide is pre-computed, not resolved at call time** — `AISettings.styleGuide` holds a ≤150-word plain-text description of the author's style, generated once by Claude when the user saves their sample post selection in Settings. `AIPromptBuilder.systemPrompt(styleGuide:)` embeds this string in the system prompt on every AI call. Do NOT go back to resolving `samplePostIDs` against the post list and stripping HTML at call time — that was replaced to eliminate per-call token cost. The system prompt is cached by `AnthropicClient` via `cache_control: ephemeral`.
- **Style guide regeneration rules in `PreferencesView.saveAll()`** — the guide is regenerated only when: (a) sample post IDs have changed, or (b) no guide exists yet. If IDs are unchanged and a guide already exists, the existing guide is reused and no Claude call is made. If the WordPress site URL changes, `aiSamplePostIDs` is cleared and the guide is set to `nil` — post IDs from one site are meaningless on another. `saveAll()` is `async`; the button is disabled via `isAnalyzing` while the Claude call is in flight.
- **`PreferencesView` must not use `@EnvironmentObject`** — the SwiftUI `Settings` scene creates a separate window context that does not inherit the main app's environment objects. `PreferencesView` receives what it needs as explicit init parameters: `posts: [WPPost]` (for the sample post picker) and `onSaveAISettings: ((AISettings) -> Void)?` (to update `AppState` after saving). Both `QuillApp`'s `.sheet` and `Settings` scene pass these from `appState` at the call site where `AppState` is in scope.
- **Anthropic web search fragments the response into many small text blocks** — when `web_search_20250305` is enabled, the API returns a `content` array with `server_tool_use`, `web_search_tool_result`, and multiple `text` blocks (one per inline citation span). `AnthropicClient` joins all `type == "text"` blocks with `joined()` to reconstruct the full response. Do NOT use `first` or `last` — only the joined string has the complete `TITLE:` … `CONTENT:` structure.
- **Anthropic web search prepends a preamble to the `TITLE:` line** — Claude emits a preamble text block (e.g. "I'll search for…") as a separate fragment that gets joined directly to `TITLE:` without a newline. `AIPromptBuilder.parseGenerateResponse` therefore uses `range(of: "TITLE:", options: .caseInsensitive)` to find the marker anywhere in the joined string, not `hasPrefix` on individual lines.
- **AI generate prompt must specify HTML structure explicitly** — the `generatePostPrompt` template must name the HTML elements to use (`<h2>`, `<h3>`, `<p>`, `<ul>/<li>`). Using vague descriptions like "HTML paragraphs" causes Claude to emit only `<p>` tags and omit headings entirely, even when web search is active and the content is clearly structured.
- **`AIResultPanel` must NOT use `sizingOptions = .preferredContentSize`** — `AIResultPanel` is a static two-button bar whose size is computed once via `fittingSize` and set with `setContentSize`. Adding `.preferredContentSize` makes `NSHostingController` fight AppKit's layout engine over the window size during the layout pass triggered by `setContentSize`, creating infinite recursive layout (6000+ levels deep, stack overflow crash). Use the default `sizingOptions = []` for any panel with static content. Only use `.preferredContentSize` for popovers with dynamically growing content (like `LinkPickerView`).
- **Floating panels must use child window relationship, NOT `level = .floating`** — `NSWindow.Level.floating` floats above all windows system-wide including other applications. `AIResultPanel` and `SelectionPillPanel` use `hasShadow = false` and no `level` override; in `show()` they call `webView.window?.addChildWindow(self, ordered: .above)` to stay above Quill's main window, and `parent?.removeChildWindow(self)` before `orderOut` in dismiss/hide. Do not restore `level = .floating` — it causes panels to appear on top of every other app when the user switches away.
- **Buttons inside transparent `NSPanel` must use `.plain` style with explicit backgrounds** — `.borderedProminent` and `.bordered` SwiftUI button styles rely on `NSButton` internal rendering that does not draw correctly on a transparent `NSPanel` in light mode (the tinted fill may not appear, leaving invisible buttons). Use `.buttonStyle(.plain)` with an explicit `.background(color, in: RoundedRectangle(...))` instead. For the AI result bar, the Accept button uses `Color.wpAmber` background with `.white` foreground; Discard uses `Color(NSColor.controlColor)` with `Color(NSColor.labelColor)`.
- **`hasShadow = false` on floating panels** — both `AIResultPanel` and `SelectionPillPanel` set `hasShadow = false` on the `NSPanel`. The system window shadow on a transparent `NSPanel` draws a rectangular shadow around the panel frame regardless of the SwiftUI content shape, creating a visible rectangular border artifact on top of the SwiftUI rounded-rect shadow. SwiftUI's `.shadow()` modifier inside the view handles the visual shadow correctly.
- **`showAIResult` inserts at block-node boundaries, not text positions** — using `setTextSelection({ from, to }).insertContent(html)` with character positions inside a paragraph causes ProseMirror to split the paragraph at those points, leaving empty `<p>` fragments before and after the inserted content. Instead, expand to node boundaries: `$from.before($from.depth)` / `$to.after($to.depth)`, then call `insertContentAt({ from: nodeFrom, to: nodeTo }, html, { parseOptions: { preserveWhitespace: false } })`. The `preserveWhitespace: false` option is required — the default `'full'` causes ProseMirror to wrap the `\n` characters Claude emits between `<p>` tags into blank paragraph nodes.
- **Strip inter-block whitespace text nodes before inserting AI HTML** — even with `preserveWhitespace: false`, ProseMirror can create a blank paragraph from the first whitespace text node at the start of a slice. Before calling `insertContentAt`, parse the HTML through a temporary `div`, remove whitespace-only `childNodes` (text nodes between block elements), and use the resulting `innerHTML`. This ensures zero inter-paragraph whitespace reaches ProseMirror's parser.
- **`NSWindow.allowsAutomaticWindowTabbing = false` in `QuillApp.init()`** — macOS automatically injects a "View → Show Tab Bar" menu item and window-tabbing support into every NSWindow-based app. Since Quill is a single-window app, this is noise. The class-level property is set to `false` in `QuillApp.init()` to suppress it. Do not remove this — the menu item reappears without it.
- **File menu commands use `AppState.createNewDraft(type:draftStore:)` and `AppState.triggerMediaUpload`** — `QuillApp.commands` cannot use `@EnvironmentObject`, but `appState` and `appServices` are `@StateObject` properties captured by reference in the commands closure. New Post / New Page call `appState.createNewDraft(type:draftStore:)` directly. New Media sets `appState.triggerMediaUpload = true` after switching to `.media` section; `MediaSidebarSection` watches this in both `.onAppear` (if the view wasn't yet mounted when the flag was set) and `.onChange` (if already mounted), then calls `uploadFromDisk()` and resets the flag to `false`. Do not collapse these into a single observer — both are needed to handle the mount-ordering race.

## Docs

- Spec: `docs/superpowers/specs/2026-05-21-wp-mac-app-design.md`
- Plan: `docs/superpowers/plans/2026-05-21-wp-writer-implementation.md`
- Spec (delete): `docs/superpowers/specs/2026-05-22-delete-post-draft-design.md`
- Plan (delete): `docs/superpowers/plans/2026-05-22-delete-post-draft.md`
- Spec (media sidebar): `docs/superpowers/specs/2026-05-23-media-sidebar-design.md`
- Plan (media sidebar): `docs/superpowers/plans/2026-05-23-media-sidebar.md`
- Spec (link picker): `docs/superpowers/specs/2026-05-23-link-picker-design.md`
- Plan (link picker): `docs/superpowers/plans/2026-05-23-link-picker.md`
- Spec (image resize): `docs/superpowers/specs/2026-05-23-image-resize-design.md`
- Plan (image resize): `docs/superpowers/plans/2026-05-23-image-resize.md`
- Spec (AI writing): `docs/superpowers/specs/2026-05-23-ai-writing-design.md`
- Plan (AI writing): `docs/superpowers/plans/2026-05-23-ai-writing.md`
- Spec (AI style guide caching): `docs/superpowers/specs/2026-05-24-ai-style-guide-caching-design.md`
- Plan (AI style guide caching): `docs/superpowers/plans/2026-05-24-ai-style-guide-caching.md`
- Public docs: `docs/Quill.md`
