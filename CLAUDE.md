# Quill

Native macOS app for writing and managing WordPress content. Built with Swift Package Manager (no Xcode needed).

## Status

Implementation complete and running. Active polish/iteration phase.

## TODO

- [ ] Post/page title bar should be white in dark mode
- [ ] Inline command palette — slash-command style input (type `/` at the start of a block) for triggering AI operations and inserting blocks, similar to Notion

## Build & run

```bash
./build.sh        # compiles, assembles Quill.app, ad-hoc signs
open Quill.app
./test.sh                                # run ALL tests (Swift + JS editor) — use this
swift test                               # Swift tests only
swift test --filter WordPressClientTests # one Swift suite
node --test Scripts/test-editor.js          # JS transform tests only
node --test Scripts/test-editor-keyboard.js # live editor keyboard tests only
node --test Scripts/test-editor-gallery.js  # gallery node insert/parse/render tests only
node --test Scripts/test-editor-passthrough.js # unmodeled Gutenberg block passthrough tests only
```

**After every code change:** quit the app, run `./build.sh`, reopen. Always.
**After major changes:** run the `claude-md-management:revise-claude-md` skill to keep this file current.

Requirements: Swift 6.3.1 (already installed), macOS 13+. JS tests require `node` (already installed) and `jsdom` (installed via `npm install` in the project root).

## Test suite status (2026-07-12 — 334 Swift + 210 JS tests, all passing)

**Swift (334 tests):** 22 suites covering all models (including wpautop classic-content handling — now also gated on a `wp-block-` class substring so class-only Gutenberg passthrough content isn't misclassified as classic — HTML entity decoding, and `WPMedia.sizedURL(for:)` size-slug resolution with blank-URL and "full" fallback), WordPressClient (incl. `+`-in-query escaping), all storage layers, AIPromptBuilder (including list/table context-aware prompts with correct `<ul>`/`<ol>` tag selection, phantom punctuation-spacing suppression, `<cite>` wrapper stripping), AnthropicClient (incl. optional `stop_reason` decoding and `AnthropicError.networkError` friendly messaging), AppState view-model logic, EditorCoordinator (incl. `mediaSizesDict(for:)`'s "full"-entry fallback), status helpers, PostStats, MimeType, UpdateChecker version comparison, and a regression guard confirming `wp:gallery`/`wp:image` block-comment content survives `editorHTML` unchanged. Each network suite uses its own MockURLProtocol subclass to avoid global-state races.

**JS transforms (140 tests):** `Scripts/test-editor.js` covers `toWordPressHTML`, `extractAlignment`, `formatHTML`, `countStats`, `findMatches`, `findMatchesLoose`, `fuzzyAnchorRegex`, `detectEmbedProvider`, `embedClassFor`, and the `gutenbergPassthrough` parsing helpers (`passthroughLabelFromClass`, `passthroughLabelFromBlockName`, `parsePassthroughBlock`) via Node + jsdom (headings, lists, blockquotes, code blocks, horizontal rules, images, tables incl. Tiptap artifact cleanup, embeds, footnotes, footnote backrefs, gallery block-comment wrapping incl. idempotency, unicode, whitespace-tolerant anchor matching, CR-before-`-->` comment stripping, unmodeled-Gutenberg-block passthrough incl. nested-content byte-for-byte preservation).

**JS editor keyboard (38 tests):** `Scripts/test-editor-keyboard.js` loads the **real `editor.html`** in jsdom, instantiates the live Tiptap editor via the `window._tiptapEditor` global, dispatches real `keydown` events, and asserts on the resulting ProseMirror document. This is the only automated coverage of the live Enter/Backspace/Shift-Enter handlers (the code paths that caused the June 2026 regression chain). Covers plain paragraphs, headings, lists, blockquotes/cite, footnotes (soft-break Enter, Backspace), image captions, class-preservation through schema round-trips, and image link-to-full-size (`linkTo`/`linkHref` attrs, incl. classic non-figure markup and empty-href handling) — each with the regression commit referenced inline where applicable. **jsdom caveat:** ProseMirror only keymap-binds Backspace at node boundaries (joinBackward/lift); mid-text character delete is browser `beforeinput`, which jsdom does not emit, so only boundary Backspace is asserted. Polyfills `crypto.randomUUID`/`matchMedia`/`requestAnimationFrame`/`ResizeObserver`; the `document.execCommand` jsdom error from `onCreate` is harmless.

**JS gallery node (19 tests):** `Scripts/test-editor-gallery.js` uses the same real-`editor.html`-in-jsdom approach as the keyboard tests to exercise the `galleryBlock` node's insert/parseHTML/renderHTML/`sourceHTML`-round-trip behavior end-to-end — a custom Tiptap node's parse/render logic can't be exercised through the pure `editor-transforms.js` helpers alone. Includes `sizeSlug` coverage: extraction from a loaded figure's `size-*` class on parse, propagation through the `window.insertGallery` JSON bridge, and honoring a non-default value in the reconstruction render path. Includes `fullUrl` coverage: `linkTo: 'media'` links to the image's `fullUrl` (true full-resolution original) rather than its display-size `url`, with a fallback to `url` when `fullUrl` is absent.

**JS passthrough node (13 tests):** `Scripts/test-editor-passthrough.js` uses the same real-`editor.html`-in-jsdom approach to exercise the `gutenbergPassthrough` node's parse/render behavior end-to-end — catches any `wp-block-*` classed, non-`<figure>` element no other parse rule claims (Accordion, Columns, Group, etc.), preserves its `outerHTML` verbatim, and regenerates any original `<!-- wp:name -->` comments on save. Covers class-only markup, comment-wrapped markup, nested real blocks (e.g. a `wp:image` nested inside a passthrough `wp:group`) surviving save, and specificity guards confirming the catch-all never steals elements `galleryBlock`/`image`/`embedBlock`/`table`/`heading` already claim.

**Full reference:** `docs/testing-plan.md` — lists every test by name with what it checks, plus the manual/functional checklists for release sign-off.

## Test suite gotchas

- **Each network test suite needs its own `URLProtocol` subclass** — `@Suite(.serialized)` only serializes within a suite; two serialized suites sharing `MockURLProtocol.requestHandler` (a global static) race against each other. Solution: give each suite its own subclass with its own `static var requestHandler` (e.g. `AnthropicMockURLProtocol` in `Tests/QuillTests/Support/`).
- **`httpBody` is always nil in `URLProtocol.startLoading()`** — URLSession moves the body to `httpBodyStream`. To inspect request bodies in mock tests, reconstruct from the stream. See `AnthropicMockURLProtocol.startLoading()` for the pattern.
- **DOM-wrap + string-strip round-trips can leave orphaned whitespace text nodes** — when a transform inserts a separator (e.g. `\n\n`) *between* two wrapped elements rather than adjacent to either one's own delimiter, a later strip-by-regex pass can't fully remove it (each strip regex only consumes whitespace touching its own comment tag), so the separator survives as a stray whitespace-only text node between the bare elements. Re-wrapping then stacks a new separator on top instead of replacing it, and the output grows on every save. Fix at the DOM level, scoped to the exact container being re-wrapped: strip whitespace-only child text nodes immediately before re-inserting separators, rather than adding more regex. Discovered in the gallery block-comment wrapper (`toWordPressHTML`'s `figure.wp-block-gallery` handling); relevant to any future block that wraps a repeated list of sibling elements with per-item comments.
- **Greedy `[^\n]*` in comment-stripping regexes can span multiple comments and delete the content between them** — `toWordPressHTML`'s upfront strip of pre-existing `wp:embed`/`wp:gallery`/`wp:image` comments used `<!-- wp:X [^\n]*-->` to match one comment's attrs. This assumes each comment is followed by a `\n` before the next one starts, which holds for freshly-wrapped content (the wrap step itself always inserts a `\n`) but not for a *loaded* gallery's `sourceHTML` (`galleryBlock`'s verbatim-re-render attr, captured from the original WordPress figure) — DOM whitespace-node collapsing during Tiptap's parse can leave zero characters between one image figure's closing `<!-- /wp:image -->` and the next image's opening `<!-- wp:image -->`. With no `\n` boundary, `[^\n]*` greedily matched past the *first* comment's own `-->` all the way to the *last* `-->` in the string, deleting every image figure in between — this is what caused a gallery's images to silently disappear after any visual edit (the `toWordPressHTML(editor.getHTML())` call on every debounced save re-triggers the strip). Fixed by making the attrs group non-greedy (`[\s\S]*?-->`), which always stops at the nearest `-->` regardless of surrounding whitespace. Use `[\s\S]*?`, not `.*?` — JS `.` excludes all line-terminator characters (`\n`, `\r`, U+2028, U+2029), not just `\n`, so a `.*?` group fails to match at all (leaving the comment unstripped) if a stray `\r` ever lands inside a comment's attrs before its own `-->`. Regression tests: `Scripts/test-editor.js`'s `'stripping pre-existing wp:image comments does not consume the images between them'` and `'stripping a pre-existing wp:gallery comment works even with a CR before its closing -->'`.
- **Edit tool corrupts quotes in JS test files** — when the Edit tool's `old_string` spans a region containing curly Unicode quotes (U+2018/U+2019), it can replace straight ASCII `'` delimiters with curly ones in the output, producing `SyntaxError: Invalid or unexpected token` in Node.js. If you see that error after editing `Scripts/test-editor.js`, the fix is a targeted Python byte-level replacement — do NOT use the Edit tool again to fix it, as it will re-introduce the same corruption. The existing unicode test on line 277 intentionally contains U+2019 as *content* (not delimiters) and must be left alone.
- **`test-editor-keyboard.js`: the first `setContent(figureHTML)` right after an `extendMarkRange('link')`-over-an-existing-mark call silently no-ops** — confirmed via `git stash` to reproduce on unmodified `editor.html`, so it's a pre-existing jsdom/Tiptap interaction, not caused by any one feature's code: `editor.chain().extendMarkRange('link').setLink(...).run()` over an *existing* link mark poisons exactly the next `setContent(...)` call, which produces an empty `<p></p>` instead of parsing the given HTML (only that one call — the next one parses fine). Reproduces with any figure/image HTML, not just linked images; never root-caused past "ProseMirror's stored marks/selection mapping through the full-doc `replaceWith` is the suspect." If a new `describe()` block's first test calls `setContent` with block-level HTML and lands right after a test exercising `extendMarkRange`, add a throwaway `editor.commands.setContent('<p></p>', false)` in a `before()` hook to absorb the one-shot quirk (see the `'image link-to-full-size'` describe block for the pattern).

## Key decisions

- **Stack:** Swift 6, SwiftUI (macOS 13+), WKWebView, URLSession async/await
- **Editor:** Tiptap 2.x inside WKWebView, loaded from a local bundle (`tiptap-bundle.js` in Resources). Bundled via `./Scripts/bundle-tiptap.sh` (requires `node`). To update Tiptap at any time, just tell Claude "check for new versions of Tiptap" — Claude will check the latest release, update the version in the script if needed, regenerate the bundle, update `editor.html` and `CLAUDE.md`, and rebuild.
- **API:** WordPress REST API with Application Passwords (no plugin required)
- **Storage:** SQLite.swift for local drafts/autosaves; credentials stored as JSON in `~/Library/Application Support/Quill/credentials.json` (chmod 600, not the system keychain — avoids password prompts)
- **URLSession:** Always use `URLSessionConfiguration.ephemeral` (default in `WordPressClient`) — prevents URLSession from touching the system keychain credential store

## Future architecture options

See `docs/future-architecture.md` for deferred design notes: image figure-first model (Approach C), local draft settings persistence (Approach B), and LanguageTool grammar checking (Approach D).

## Architecture

```
Sources/QuillKit/
  App/              AppState, AppServices, QuillApp, AppSupportDirectory, UpdateChecker
  Auth/             CredentialsStore (file-based, not system keychain)
  API/              WordPressClient, Models (WPPost, WPMedia, WPTaxonomy)
  AI/               AnthropicClient, AISettings, AISettingsStore, AIPromptBuilder
  Storage/          Database, DraftStore, AutosaveStore, TaxonomyCache
  Views/
    ContentView.swift
    Editor/         PostEditorView, EditorView, EditorCoordinator, DroppableWebView
                    TitleTextField, LinkPickerView
    Sidebar/        SidebarView, PostListRow
    Settings/       PreferencesView, PostSettingsPanel, AboutView
    Media/          MediaPickerView, MediaDetailView, MediaSidebarSection, GallerySheet
    AI/             GeneratePostSheet, AIResultPanel, SamplePostPickerSheet
  Resources/        editor.html (Tiptap)
                    editor-transforms.js (WordPress HTML transforms, shared with test suite)
  DesignSystem.swift
```

## Key files to know

- `Sources/QuillKit/Resources/editor.html` — entire Tiptap editor; JS↔Swift bridge via `window.webkit.messageHandlers.*` and `window.*` globals
- `Sources/QuillKit/Views/Editor/EditorCoordinator.swift` — WKWebView delegate + message handler; handles insert-image notification
- `Sources/QuillKit/Views/Editor/DroppableWebView.swift` — WKWebView subclass intercepting Finder image drops
- `Sources/QuillKit/API/WordPressClient.swift` — all REST API calls
- `Sources/QuillKit/Resources/editor-transforms.js` — `toWordPressHTML`, `extractAlignment`, `formatHTML`, `countStats`, `findMatches`, `findMatchesLoose`, `fuzzyAnchorRegex`, `detectEmbedProvider`, `embedClassFor`, `passthroughLabelFromClass`, `passthroughLabelFromBlockName`, `parsePassthroughBlock`; shared between `editor.html` and `Scripts/test-editor.js`. Loaded as `<script src="./editor-transforms.js">` before the main editor script block, so all functions are available as globals inside `editor.html`'s JS.
- `Sources/QuillKit/Views/Media/GallerySheet.swift` — native picker for creating a WordPress gallery (multi-select media grid, reorderable selection, columns/crop/link-to/size controls); posts `.insertGalleryData` which `EditorCoordinator` turns into a `window.insertGallery(json)` call
- `gutenbergPassthrough` Tiptap node (`editor.html`) — catches any `wp-block-*` classed, non-`<figure>` element no other parse rule claims (Accordion, Columns, Group, third-party blocks), preserves it byte-for-byte as a static "unsupported block" card. See `docs/superpowers/specs/2026-07-12-gutenberg-passthrough-block-design.md` and the `toWordPressHTML` gotcha above about its shielding window.

## Maintaining Gutenberg HTML compatibility

All WordPress/Gutenberg HTML compatibility lives in two files:

1. **`toWordPressHTML(html)`** in `editor-transforms.js` (line 16) — called on every save/content-change. Transforms Tiptap's internal HTML into Gutenberg-format HTML before sending to Swift. `renderHTML` on `ResizableImage` now always outputs `<figure><img ...><figcaption/></figure>`; `toWordPressHTML` annotates existing figures (adds classes, moves alignment, handles caption) rather than wrapping bare `<img>` tags. Edit this when WordPress changes expected output format.

2. **`ResizableImage.parseHTML()`** (~line 1079 in `editor.html`) — custom parse rule for `<figure class="wp-block-image">` that extracts image attrs (including alignment) from Gutenberg figure wrappers on load.

See `Sources/QuillKit/Resources/CLAUDE.md` for the current per-element output reference table, and the `update-gutenberg-html-format` skill for the update workflow.

## Code view

`editor.html` has a `</>` toggle button (`#btn-code-view`) in the toolbar's utility group (alongside spell-check and image-align controls). Clicking it switches the Tiptap editor for a `<textarea id="code-editor">` showing the raw WordPress HTML.

**State:** `codeViewActive` (boolean, JS module-level) tracks which mode is active.

**`_enterCodeView()` / `_exitCodeView()`** — helpers that toggle DOM visibility, the button's `.active` class, and the disabled state of all other toolbar controls. `_exitCodeView()` compares the textarea value against `_codeViewOriginal`; if the user made no changes, `editor.commands.setContent` is skipped entirely (preserving Tiptap's visual state). Only when the user actually edited the HTML does `_exitCodeView()` call `setContent(html, false)` to parse it back into Tiptap.

**`window.getContent()`** returns `textarea.value` when `codeViewActive`, otherwise `_rawHTML` if set (the last raw HTML loaded from WordPress), or `toWordPressHTML(editor.getHTML())` after visual edits — so Swift's save/autosave paths work correctly from either mode.

**`window.setContent()`** exits code view silently (without round-tripping the textarea through Tiptap) before loading the new HTML, so switching posts always lands in visual mode.

**`_rawHTML`** — stores the last raw HTML passed to `setContent()` or saved from code view. Cleared on every Tiptap `update` event so Tiptap becomes the source of truth after visual edits. Used by `getContent()` so saving without any visual edits sends the original WordPress HTML (including block comments) back verbatim.

**`_rawHTMLOnLoad`** — like `_rawHTML` but never cleared by visual edits. Set in `setContent()` and updated in `_exitCodeView()` only when the user edited the textarea. Used by `_enterCodeView()` to seed the textarea, so block comments (e.g. `<!-- wp:gallery -->`) remain visible in code view even after the user has typed in the visual editor. After exiting code view with an edit, `_rawHTMLOnLoad` is updated to the code-view-edited HTML so subsequent re-entries show the latest code.

**`_codeViewOriginal`** — snapshot of the textarea value captured in `_enterCodeView()` (after formatting). `_exitCodeView()` compares `textarea.value` against this to detect whether the user changed anything. Set to `null` after comparison. Prevents unnecessary `setContent` calls (and the content wipe / compounding-whitespace regression they cause) when the user enters and exits code view without editing.

**`_codeViewChanged()`** — debounced `input` listener attached to the textarea on `_enterCodeView` and removed on `_exitCodeView`. Fires `contentChanged` to Swift on a 500 ms debounce, keeping `htmlContent` in sync so ⌘S saves code-view edits without requiring an explicit exit. Uses the same `debounce` variable as the visual editor; `_exitCodeView()` cancels any pending debounce and fires `contentChanged` directly with the final value.

**`formatHTML(html, doc)`** — pure DOM HTML pretty-printer in `editor-transforms.js`, called by `_enterCodeView`. Block elements indented, inline elements inline, void elements self-close, `<pre>` verbatim, HTML comment nodes (nodeType 8) preserved verbatim. 17 JS tests.

**Link extension:** `Link.configure({ openOnClick: false, HTMLAttributes: { target: null, rel: null } })` — the `target: null` and `rel: null` override the Tiptap Link default of `target="_blank" rel="noopener noreferrer nofollow"`, which would otherwise be added to every link.

## Known gotchas

Most file-specific gotchas moved to per-directory `CLAUDE.md` files on 2026-07-11 so they load only when Claude is working in that directory: `Sources/QuillKit/Resources/`, `Sources/QuillKit/Views/Editor/`, `Sources/QuillKit/API/`, `Sources/QuillKit/Views/Media/`, `Sources/QuillKit/Views/Sidebar/`, `Sources/QuillKit/App/`, `Sources/QuillKit/AI/`, `Sources/QuillKit/Views/AI/`, `Sources/QuillKit/Views/Settings/`, `Sources/QuillKit/Views/`. What's left here is cross-cutting or doesn't map to one directory.

- **Ad-hoc signing** — `build.sh` signs with `-`; "Always Allow" on keychain prompts won't persist across rebuilds (irrelevant now that credentials use file storage, but WKWebView may still prompt once per binary for its own internal keychain use)
- **Color tokens & surface components** — `Color.wpSidebarBg` (#F2F1EF light) and `Color.wpPanelBg` (#F4F3F1 light) are in `DesignSystem.swift` with `NSColor` dynamic providers. `NSColor.wpSidebarBg` is also defined as a direct `NSColor` extension (used for `window.backgroundColor`). Do not use `NSColor.windowBackgroundColor` in sidebars/panels. Surface components: `WarmSidebarBackground` (sidebar bg with shimmer gradient), `WarmPanelHeaderBackground` (editor header + settings panel bg), `SoftPanelBoundary` (vertical boundary between panes — replaces `Divider()`), `SoftHorizontalDivider` (horizontal separator — replaces `Divider()`), `PanelInteriorFade(from:)` (edge fade for scroll lists). Use these instead of plain `Divider()`.
- **Unicode curly quotes in Swift strings** — Swift treats `"` (U+201C) and `"` (U+201D) as string delimiters, identical to ASCII `"`. Do not use curly quotes inside string literals with interpolation — use escaped ASCII quotes `\"...\(value)...\"` instead.

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
- Spec (gallery support): `docs/superpowers/specs/2026-07-08-gallery-support-design.md`
- Plan (gallery support): `docs/superpowers/plans/2026-07-08-gallery-support.md`
- Spec (image link-to-full-size): `docs/superpowers/specs/2026-07-10-image-link-to-full-design.md`
- Plan (image link-to-full-size): `docs/superpowers/plans/2026-07-10-image-link-to-full.md`
- Spec (Gutenberg passthrough block): `docs/superpowers/specs/2026-07-12-gutenberg-passthrough-block-design.md`
- Plan (Gutenberg passthrough block): `docs/superpowers/plans/2026-07-12-gutenberg-passthrough-block.md`
- End-user guide: `docs/user-guide.md`
