# Quill

Native macOS app for writing and managing WordPress content. Built with Swift Package Manager. Implementation complete; active polish/iteration phase.

## Build & run

```bash
pkill -f "^$PWD/Quill.app/Contents/MacOS/Quill"; sleep 2 && ./build.sh 2>&1 && open Quill.app
```

**Run exactly that after every code change.** `build.sh` replaces the binary under a running process, so skipping the quit leaves the old app running. The quit matches this project's binary by path, so it never closes the notarized copy in `/Applications`. If the build fails, report the error instead of opening.

```bash
./test.sh
```

Runs every Swift and JS test. Current counts, every suite, the test-suite gotchas and the manual release checklists: `docs/testing-plan.md`. If you touch a suite, re-run it and correct the counts there.

```bash
./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"
```

**The only test that runs in real WebKit**, required before release sign-off — jsdom cannot see a WebKit/jsdom divergence, and three have shipped. It also fails if a script handler in post content runs inside the editor (`Scripts/fixtures/script-sinks/`). Needs a current `./build.sh`.

**Skills:** `update-dependencies` (read-only report: `./Scripts/check-dependencies.sh`), `manual-test-pass` (runs `docs/testing-plan.md` §7 against the local Studio site), `/release <version>`. Bundle ID is `com.siolon.quill` (was `com.quill.app` before 2.0.0).

**Requirements:** Swift 6.4, macOS 27, full Xcode (`build.sh` runs `actool`, which the Command Line Tools lack). `node` + `jsdom` are installed in **`Scripts/`**, not the project root, which has no `package.json` — an ad-hoc jsdom probe script must also live in `Scripts/`, or it dies with `Cannot find module 'jsdom'`.

**Computer-use testing goes on a new local draft.** Click "+ New Post" first and discard it when done. Never test edits on a published post or page — one Cmd+Z too many undoes the initial content load and empties the editor. Read the testing gotchas under "Running the manual pass with an agent" in `docs/testing-plan.md` first.

## Key decisions

- **Stack:** Swift 6, SwiftUI (macOS 27 only — no availability gates), WKWebView, URLSession async/await
- **Editor:** Tiptap 2.x inside WKWebView, loaded from a local bundle (`tiptap-bundle.js` in Resources, built by `./Scripts/bundle-tiptap.sh`)
- **API:** WordPress REST API with Application Passwords (no plugin required)
- **Login:** WordPress's browser approval (`authorize-application.php`), calling back on `quill://authorize`; manual application-password entry is the fallback
- **Storage:** SQLite.swift for local drafts/autosaves; credentials as JSON in `~/Library/Application Support/Quill/credentials.json` (chmod 600, not the system keychain — avoids password prompts)
- **Accent:** amber `#C77700` light / `#BF801E` dark via `Assets.xcassets` + `NSAccentColorName`, *not* `.tint()` — `List` selection reads the bundle's accent and ignores the view tree. macOS honours it only while the system accent is "Multicolor".
- **URLSession:** always `URLSessionConfiguration.ephemeral` (default in `WordPressClient`) — keeps URLSession away from the keychain credential store
- **Deferred design decisions** are GitHub issues on `cpoteet/Quill`, not files in `docs/`

## Architecture

`Sources/QuillKit/`, each directory with its own `CLAUDE.md` of file-specific gotchas:

- `App/` — `AppState`, `AppServices`, `QuillApp`, `UpdateChecker`
- `Auth/` — `CredentialsStore` (file-based), `AppAuthorization`, `ConnectSite`
- `API/` — `WordPressClient` (all REST calls), `SiteDiscovery`, models (`WPPost`, `WPMedia`, `WPTaxonomy`, `WPSyncedPattern`), `ImageConversion`
- `AI/` — `AnthropicClient`, `AISettings`, prompt builders, `EvaluationState`
- `Storage/` — `Database`, `DraftStore`, `AutosaveStore`, `TaxonomyCache`
- `Views/` — `ContentView`, split-view fixes; `Editor/`, `Sidebar/`, `Settings/`, `Media/`, `AI/`, `Onboarding/`
- `Resources/` — `editor.html` (the whole Tiptap editor; JS↔Swift bridge via `window.webkit.messageHandlers.*` and `window.*` globals), `editor-transforms.js`, `block-descriptors.js`, `block-settings.js` (one entry per block setting), `block-parser.js` (checked against WordPress's parser; used for unsupported-block preservation), `block-move.js` (moving top-level blocks), `block-grip.js` (the drag grip beside each block) and `click-seat.js` (seating a click that lands outside every line)
- `DesignSystem.swift`

Concepts with their own doc: block model, Groups and synced patterns (`docs/block-model.md`); footnotes in post meta (`docs/footnotes-meta.md`); code view (`docs/code-view.md`); paste and Paste as Markdown (`docs/paste.md`).

## Maintaining Gutenberg HTML compatibility

All WordPress/Gutenberg HTML compatibility lives in three files:

1. **`toWordPressHTML(html)`** in `editor-transforms.js` — runs on every save/content change and turns Tiptap's HTML into Gutenberg HTML. `ResizableImage.renderHTML` always outputs `<figure><img><figcaption/></figure>`; `toWordPressHTML` annotates those figures rather than wrapping bare `<img>`. `editor-transforms.js` is a plain `<script>` shared with the JS test suites, so everything in it is a global.
2. **`ResizableImage.parseHTML()`** in `editor.html` — extracts image attrs (including alignment) from `<figure class="wp-block-image">` on load.
3. **`block-descriptors.js`** — maps each Tiptap node to its Gutenberg block name, shape, `attrsFrom` and `ownedAttrs`. `wrapInDelimiters` emits `<!-- wp:name -->` for every descriptor, so a new modeled block is a descriptor entry, not another `toWordPressHTML` pass.

Per-element output table: `Sources/QuillKit/Resources/CLAUDE.md`. Fixing one block: the `update-gutenberg-html-format` skill. Per-release checklist: `docs/wordpress-release-audit.md`.

## Gotchas

These two fail silently with the whole test suite green:

- **A top-level `const` in a Resources JS file is NOT reachable as `window.x` from `editor.html`; only `function` declarations are** — classic scripts share one lexical scope, so a `const` is reachable by bare identifier but not on `globalThis`, which is how `editor-transforms.js` reads `block-descriptors.js` in the browser (Node uses `require`, so every Node test passes). Expose such values as a `function` declaration (`modelsBlockName`) or assign them to `window`.
- **WKWebView rewrites pasted HTML before the page sees it, and jsdom cannot** — a paste fix proven only in jsdom proves nothing; run the real-WebKit harness (`Scripts/fixtures/paste/README.md`). Detail: `docs/paste.md`.

Cross-cutting gotchas, full text in `docs/gotchas.md`. Titles that belong to one directory are listed in that directory's `CLAUDE.md`; the testing ones are in `docs/testing-plan.md`.

- **A carried attribute is a script sink — everything the raw-attribute carrier snapshots gets replayed onto the live contenteditable**
- **Post markup is parsed only into `inertDocument()`, never into an element of the live page**
- **The unsupported-block sentinel is a per-save random nonce, and must stay one**
- **New JS dependencies get their own bundle script, not a `bundle-tiptap.sh` edit**
- **Synchronous image work must not run on the main actor**
- **Each browser-approval attempt needs its own application-password name**
- **Ad-hoc signing for dev, Developer ID only for release**
- **Unicode curly quotes in Swift strings**

## Docs

- `docs/testing-plan.md` — every test by name, test-suite gotchas, manual release checklists
- `docs/platform-workarounds.md` — every Apple/WebKit workaround with a test for whether it is still needed; work through it after each macOS release. A new workaround gets an entry here as well as its gotcha
- `docs/editor-gotchas.md` — the `editor.html` gotchas, indexed in `Sources/QuillKit/Resources/CLAUDE.md`
- `docs/wordpress-release-audit.md` — once per WordPress major release
- `docs/superpowers/specs/` and `docs/superpowers/plans/` — one spec + plan pair per feature, named by date
- `site/docs.html` — end-user guide, published on the site; edit it directly (no Markdown source)

**After major changes:** run `claude-md-management:revise-claude-md`. Keep this file an index — detail belongs in `docs/` or the per-directory `CLAUDE.md` files.
