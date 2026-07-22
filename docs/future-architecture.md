# Future Architecture Options

Deferred design notes for Quill. None of these are in the current implementation.

---

## Approach C: Image node — figure-first model

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

---

## Approach B: Local draft settings persistence

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

---

## Approach D: Grammar checking — LanguageTool integration

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

---

## Approach E: Generic passthrough for unrecognized Gutenberg blocks

**Context (as of 2026-07-03):** The HTML Snippets Manager (`docs/superpowers/specs/2026-07-03-html-snippets-design.md`) gives Quill-authored raw HTML a first-class Tiptap node (`SnippetBlock`) so it survives arbitrary visual edits elsewhere in a post — a private, flat, non-nested comment-marker grammar the app fully controls. That fixes the round-trip problem only for snippets. A post containing real Gutenberg blocks Quill has no node for (a `wp:gallery` from the WordPress block editor, an ACF block, a third-party plugin block) still relies entirely on the `_rawHTML`/`_rawHTMLOnLoad` verbatim safety net, which is nulled the instant the user makes any visual edit anywhere in the post — at which point those unmodeled blocks are silently dropped on next save.

**What Approach E would be:** A generic `GutenbergPassthrough` Tiptap node that recognizes any `<!-- wp:name {json attrs} --> ... <!-- /wp:name -->` (or self-closing `<!-- wp:name {json attrs} /-->`) comment pair not already claimed by one of Quill's specific nodes, and treats it the same way `SnippetBlock` treats a snippet: parse it into an atomic node holding `{blockName, attrsJSON, innerHTML}`, render an opaque card for it (block name + a hint that it's unrecognized), and re-serialize it back to the identical comment-fenced form on save — surviving edits elsewhere in the document the same way images, embeds, and snippets already do.

**Why it wasn't done as part of the snippets feature:** Real Gutenberg block comments are a much richer grammar than what snippets need — structured JSON attributes, a self-closing form, and arbitrary nesting (a Columns block containing Column blocks containing Paragraph blocks). Supporting it properly means a real recursive block parser that, at every nesting level, decides whether a block is one Quill already models by CSS class (paragraph, heading, list, image, table, quote — none of which Quill emits as literal `wp:` comments today) or an unknown block that needs opaque passthrough. That's a foundational change to how Quill treats content it didn't author, not a natural extension of a personal snippet library.

**What a future implementer would need to know:**
- Start from `SnippetBlock`'s unwrap/restore transform pair in `toWordPressHTML()` / the pre-`setContent` restore pass (editor-transforms.js) — the DOM-level comment-reparenting mechanism is directly reusable; only the grammar being matched needs to grow (JSON attrs, self-closing form, recursion).
- Nesting means the restore pass can't just gather flat siblings between two comments — it needs to recursively re-run itself on the captured region to find and convert any nested `wp:` blocks before handing the result to Tiptap's parser, or accept that nested foreign blocks stay opaque as a whole (simpler, likely sufficient — a foreign block's internal structure isn't something Quill needs to edit, only preserve).
- Decide the precedence rule explicitly: Quill's own class-based parse rules for `figure.wp-block-image`, `table`, etc. should keep matching first; `GutenbergPassthrough` should only catch what nothing else claims.
- The `_rawHTML`/`_rawHTMLOnLoad` safety net (editor.html) becomes unnecessary for any content covered by this node — but should stay for anything still outside its grammar (malformed or non-block classic content) until proven otherwise.
- Test against a real WordPress site's actual Gutenberg output for at least: a self-closing block, a nested block (Columns/Column), and a block whose JSON attrs contain a literal `>` character inside a string value (a plausible edge case for the comment-boundary regex/DOM-walk).

---

## Approach F: Ephemeral (or cache-busted) editor image loading

**Context (as of 2026-07-14):** `EditorView.swift`'s `WKWebViewConfiguration()` (`makeNSView`, ~line 70) does not set a `websiteDataStore`, so the editor's WKWebView uses the default **persistent** data store for all network loads, including `<img>` tags. This differs from `WordPressClient`, which always uses an ephemeral `URLSession` (`.ephemeral` config) specifically to avoid persistent caching/credential storage. A user reported that replacing a media file in WordPress with the same filename (same URL) kept showing the old image in the editor — WebKit's disk-backed HTTP cache (`~/Library/Caches/com.quill.app/WebKit/NetworkCache`) was reusing the cached response rather than re-fetching, since there's no app-level cache-busting and the fix depends entirely on the WordPress host's `Cache-Control`/`ETag` headers. Worked around in the moment by manually clearing that cache directory on disk; no code changed.

**What Approach F would be:** Either (a) switch the editor's `WKWebViewConfiguration` to a non-persistent `WKWebsiteDataStore` (`.nonPersistent()`), matching the ephemeral-everywhere pattern already used for the REST client, or (b) keep the persistent store but append a cache-busting query parameter (e.g. `?v=<timestamp or mediaId+modified>`) when rendering `<img src>` for media loaded from WordPress, forcing a re-fetch whenever the underlying file changes.

**Why it wasn't done immediately:** It's a minor, infrequent annoyance (only triggered by uploading a same-filename replacement) with an easy manual workaround (clear the cache dir, or quit/reopen after the server cache header expires). Not worth a code change without weighing the tradeoff: option (a) means images re-download on every app launch instead of being cached across sessions (slower editor loads for image-heavy posts); option (b) requires plumbing a reliable "last modified" or version signal through wherever image URLs are rendered/inserted (`ResizableImage` render path, gallery figures, passthrough-preserved `<img>` tags from raw HTML) without breaking the byte-for-byte preservation guarantees those paths rely on.

**What a future implementer would need to know:**
- `EditorView.swift` (`makeNSView`, ~line 70) is the single call site for `WKWebViewConfiguration()` — for option (a), set `config.websiteDataStore = .nonPersistent()` there.
- For option (b), the query-param would need to be added consistently everywhere an image URL reaches the DOM: `ResizableImage`'s `renderHTML`/parse path, `insertImageAt` (Swift→JS bridge), the gallery node's `sourceHTML` verbatim re-render, and `gutenbergPassthrough`'s byte-for-byte preserved markup — the last two are especially risky since they're designed to preserve original HTML exactly, so injecting a query param there could break round-trip fidelity or the "identical to original" assumptions their tests assert on.
- `WPMedia` (API/Models) may already carry a `modified` timestamp from the REST API that could serve as the cache-busting value instead of `Date()`, avoiding a fresh miss on every single load.
- Manual workaround in the meantime: quit Quill and clear `~/Library/Caches/com.quill.app/WebKit/NetworkCache` (plus `Cache.db`/`Cache.db-shm`/`Cache.db-wal`/`fsCachedData` in the same directory) on disk.

---

## Approach G: Native Pullquote block support

**Context (as of 2026-07-15):** `docs/gutenberg-block-snippets.md` catalogs core Gutenberg blocks with no toolbar button in Quill. Testing confirmed `core/pullquote` doesn't round-trip: it renders as `<figure class="wp-block-pullquote"><blockquote>...<cite>...</cite></blockquote></figure>`, and `gutenbergPassthrough` explicitly skips `<figure>` elements (to avoid colliding with `ResizableImage`'s own figure parsing). With nothing claiming the outer figure, Tiptap's parser recurses past it and the inner `<blockquote><cite>` matches Quill's existing unscoped `CustomBlockquote` parse rule — the quote text and citation survive, but the `wp-block-pullquote` wrapper and large-pulled-quote presentation are silently dropped on load.

**What Approach G would be:** A dedicated `Pullquote` Tiptap node (or a variant/attribute on the existing blockquote) with `parseHTML` scoped specifically to `figure.wp-block-pullquote` — taking priority over the generic blockquote rule — plus distinct rendering (larger type, centered, no left border) and a `toWordPressHTML` step that re-wraps it in the figure on save.

**Why it wasn't done:** Low priority — pullquotes are a niche, largely decorative block. Not worth the schema/parse-priority work unless it turns out to matter in practice.

**What a future implementer would need to know:**
- `CustomBlockquote` (`editor.html`, ~line 2053) has no class/figure scoping, so it currently wins whenever a bare `<blockquote>` appears anywhere in parsed HTML — a new Pullquote node's `parseHTML` would need higher priority than it, or `CustomBlockquote` would need to explicitly refuse to match inside a `figure.wp-block-pullquote` ancestor.
- `gutenbergPassthrough`'s `<figure>` exclusion (see its own note earlier in this doc, and `Sources/QuillKit/Resources/CLAUDE.md`) is deliberate and shouldn't be relaxed generally — a Pullquote node should claim `figure.wp-block-pullquote` directly rather than routing through passthrough.
- Reuse the existing `Cite` node for the citation child, same as `CustomBlockquote` already does — no need to invent new citation handling.

---

## Approach H: Gutenberg fixture-diff harness for automated markup-change detection

**Context (as of 2026-07-22):** Keeping Quill's round-trip in sync with Gutenberg's saved HTML has three parts: *detecting* that WordPress changed its markup, *getting ground truth* for the new format, and *applying the fix*. The `update-gutenberg-html-format` skill covers the last two well (it now ranks Gutenberg's own test fixtures as primary ground truth). Detection, however, currently depends on the user hearing about a change or on hand-built one-off scheduled audits (e.g. the `wordpress-7-1-markup-audit` task firing 2026-08-20) — each of which takes real effort to write and covers exactly one release. The skill only ever runs *after* something else notices a problem.

**What Approach H would be:** Make detection mechanical by turning the fixtures into a regression suite:

1. **Vendor fixtures into the repo** — a `Scripts/fixtures/gutenberg/` directory holding the fixture files for the blocks Quill actually models (paragraph, heading, list, blockquote, code, separator, image, table, embed, footnotes, gallery — mirror the per-element table in `Sources/QuillKit/Resources/CLAUDE.md`).
2. **A fetch script** — `Scripts/fetch-gutenberg-fixtures.sh`, pinned to a Gutenberg release tag via a version variable at the top (same pattern as `Scripts/bundle-tiptap.sh`), that downloads the fixture files for the tracked blocks from the `WordPress/gutenberg` GitHub repo.
3. **A jsdom round-trip test** — `Scripts/test-editor-fixtures.js`, using the same real-`editor.html`-in-jsdom harness as `test-editor-keyboard.js`: for each fixture, `setContent(fixtureHTML)` → `toWordPressHTML(editor.getHTML())` → assert the result equals a **committed per-block expectation file** (see caveats — not the fixture itself).
4. Wire it into `./test.sh`.

A new WordPress release then collapses the whole audit to: bump the tag in the fetch script, re-run it, run `./test.sh`, and read the diff. A changed fixture shows up as either a parse failure or a reviewable expectation diff that names the exact block — the skill handles the fix from there. A lightweight recurring scheduled task (~3×/year, matching WP's release cadence) could do the bump-and-run automatically and report only when something diverges, replacing hand-built audits like the 7.1 one entirely.

**Why it wasn't done now:** A few hours of setup, mostly in curating the initial expectations (see the first caveat), and the August 2026 release is already covered by the one-off audit task. Worth doing when the next WP release after 7.1 approaches, or the first time a markup change slips through unnoticed.

**Caveats (read before implementing):**
- **Blind byte-equality against the fixtures will not work.** Quill intentionally differs from raw Gutenberg output in places: Tiptap normalizations, the annotate-don't-reconstruct approach to figures, attribute ordering, and the absence of block comments for elements Quill doesn't comment-wrap. The harness must assert against *committed Quill expectation files* ("Quill's round-trip of fixture X produces Y"), generated on first run and human-reviewed before committing. Fixture updates then surface as diffs to review, not automatic failures of correctness.
- **Verify the fixture location at implementation time.** The skill references `packages/block-library/src/*/test/fixtures/*.html`; Gutenberg has also historically kept full-content fixtures under `test/integration/fixtures/blocks/` (as `core__*.html` with sibling `.parsed.json` / `.serialized.html` files — the `.serialized.html` variant is the canonical *re-save* output and may be the better comparison target). Check both paths in the repo at the chosen tag and document which one the fetch script uses.
- **Tag selection is not obvious.** A WordPress core release bundles a *range* of Gutenberg plugin releases. Find the right mapping (the Gutenberg repo's `wp/X.Y` release branches exist for this) rather than assuming the latest plugin tag matches core.
- **Scope is modeled blocks only.** Blocks Quill doesn't model are already covered by the byte-for-byte `gutenbergPassthrough` tests (`Scripts/test-editor-passthrough.js`); duplicating them here adds noise. New blocks in a WP release are still detected — they appear as new fixture files during the fetch review.
- **Fixtures skew toward default attributes.** They won't exercise every alignment/size/link-to variant Quill handles; the existing hand-written tests in `Scripts/test-editor*.js` remain the coverage for those paths. This harness detects *format drift*, it does not replace the behavioral suites.
- **Licensing:** Gutenberg is GPL-licensed; vendoring its fixture files into this personal project's repo is fine, but note their origin in a README line inside the fixtures directory.
- **Rejected stronger alternative:** embedding Gutenberg's own `@wordpress/blocks` parser/serializer in the WKWebView would eliminate drift by construction, but requires rewriting the editor's entire save path — ruled out; the passthrough + verbatim patterns already contain the problem well.

**What a future implementer would need to know:**
- The real-`editor.html`-in-jsdom harness setup (polyfills, the `window._tiptapEditor` global, the one-shot `setContent` no-op quirk after `extendMarkRange`) is documented in the root `CLAUDE.md` test-suite section — copy the boot code from `Scripts/test-editor-keyboard.js`.
- When editing/creating the JS test file, mind the Edit-tool curly-quote corruption gotcha (root `CLAUDE.md`).
- After wiring into `./test.sh`, update the test-count/status lines in the root `CLAUDE.md` and the per-test listing in `docs/testing-plan.md`.
- The expectation files are the contract: any deliberate change to Quill's output format (e.g. implementing a skill-driven format update) must regenerate and re-review them in the same commit, or the suite goes red for the wrong reason.
