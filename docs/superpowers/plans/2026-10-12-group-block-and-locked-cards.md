# Editing Groups and Clearer Locked Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Existing Groups whose contents Quill fully models become editable; every locked card shows a readable label and text preview; synced-pattern cards show the pattern's title and text fetched from WordPress.

**Architecture:** A `groupBlock` container node follows `columnBlock`. A top-level check in `wrapUnsupportedBlocks` keeps any top-level block holding a not-fully-supported Group on the existing byte-exact unsupported path. Card label and preview changes live in `editor-transforms.js` (label) and `PassthroughNodeView` (preview). Synced-pattern data follows the `requestMediaSizes` → `setMediaSizes` round trip and is held outside the ProseMirror document.

**Tech Stack:** Tiptap 2 / ProseMirror in WKWebView, Node `node:test` + jsdom suites in `Scripts/`, Swift 6 / Swift Testing, `WordPressClient` on URLSession.

**Spec:** `docs/superpowers/specs/2026-10-12-group-block-and-locked-cards-design.md`

## Global Constraints

- **Do not commit.** Project rule: make the changes, summarise, and wait. Every task ends with a report, not a commit.
- After every code change, run the build exactly as `CLAUDE.md` gives it: `pkill -f "^$PWD/Quill.app/Contents/MacOS/Quill"; sleep 2 && ./build.sh 2>&1 && open Quill.app`. Report a build failure instead of opening.
- A post opened and not edited saves back byte for byte. Anything not fully representable stays a locked card exactly as today.
- Cross-boundary JS (anything `editor.html` reads from a Resources script) must be a `function` declaration, never a top-level `const` (root `CLAUDE.md` gotcha).
- Post markup is parsed only into `inertDocument()`, never into an element of the live page.
- Comments: none by default; one line maximum; never narrate the change.
- Group label copy: custom name, else `Row`, `Stack`, `Grid`, `Group`. Synced-pattern copy: `Synced pattern`, `Synced pattern: {title}`, `Synced pattern #{ref}`, `Synced pattern #{ref} (not found)`, hint `Shared across posts · ` + button `Edit in WordPress`.
- Preview: joined with ` · `, whitespace collapsed, cut at 120 characters + `…`.
- Group label styling: editor sans-serif, small, secondary colour, never monospaced.

## Review Focus

1. **An empty Group** (`<div class="wp-block-group"></div>`, no inner blocks): `content: 'block+'` would insert an empty paragraph and change the saved markup on edit. Expected: it is not fully supported and stays a locked card. Test in Task 1.
2. **A Group with an anchor `id` and an extra custom class**: expected to survive an edit unchanged. Test in Task 1.
3. **A `metadata.name` containing markup** (`"<b>Hero</b>"`): expected to show literally as text, never as HTML. Tests in Tasks 2 and 3.
4. **A synced pattern whose content contains `<img onerror>`**: expected to show only text and never run. Test in Task 5.
5. **A synced-pattern result arriving after the post changed, when both posts use the same pattern**: expected to be ignored, not to overwrite the new post's card. Load-generation test in Task 5.

---

### Task 1: Groups open when fully supported

**Files:**
- Modify: `Sources/QuillKit/Resources/block-descriptors.js` (add `groupBlock` to `BLOCK_DESCRIPTORS`)
- Modify: `Sources/QuillKit/Resources/editor-transforms.js` (`NODE_FOR_BLOCK_CLASS`, `QUILL_MODELED_BLOCK_CLASSES`, `blockNeedsWrapping`, new `groupFullySupported`, export it)
- Modify: `Sources/QuillKit/Resources/editor.html` (`GroupBlock` node next to `ColumnBlock` at ~2567; register via `withBlockAttrs` at ~4271)
- Create fixtures: `Scripts/fixtures/settings-group.html`, `settings-group-tags.html`, `settings-group-layouts.html`, `settings-group-styled.html`, `settings-group-nested.html`
- Create fixture: `Scripts/fixtures/group-unsupported-children.html` (not `settings-*`: locked, but byte-exact)
- Modify: `Scripts/fixtures/README.md` (one table row per fixture)
- Test: `Scripts/test-editor-containers.js` (new `describe('group block')`), `Scripts/test-editor-preservation.js` (new `describe('a group with an unsupported block stays locked')`), `Scripts/test-block-serializer.js` (`groupFullySupported` unit tests)

**Interfaces:**
- Produces: `function groupFullySupported(block, doc) -> boolean` in `editor-transforms.js`, where `block` is a `parseBlocks` node (`blockName`, `innerBlocks`, `innerHTML`). Exported for Node.
- Produces: `function groupTags() -> string[]` in `editor-transforms.js`, the seven lowercase tag names.
- Produces: Tiptap node `groupBlock` with attribute `tagName` (string, default `'div'`). Descriptor `groupBlock: { blockName: 'core/group', shape: 'container', childBlockName: null, ownedAttrs: ['tagName'], attrsFrom: el => tag === 'DIV' ? {} : { tagName: lowercase tag } }`.

- [ ] **Step 1: Write the fixtures.** Hand-write each in Gutenberg's current save format. Before using a `settings-group-*` fixture, confirm `require('./wp-validator.js').problems(html)` returns `[]` for it. `group-unsupported-children.html` is exempt: the validator registers only core blocks, so its third-party block is reported as unregistered. That fixture is covered by byte preservation and `test-fixture-validity.js`'s "nothing new" rule.
  - `settings-group.html`: a plain Group with a heading, a paragraph and a list.
  - `settings-group-tags.html`: one Group each for `section`, `header`, `footer`, `main`, `aside`, `article` (`{"tagName":"section"}` and so on).
  - `settings-group-layouts.html`: Group `{"layout":{"type":"constrained"}}`, Row `{"layout":{"type":"flex","flexWrap":"nowrap"}}`, Stack `{"layout":{"type":"flex","orientation":"vertical"}}`, Grid `{"layout":{"type":"grid"}}`.
  - `settings-group-styled.html`: `backgroundColor`, `style.spacing.padding`, `style.border`, `anchor` (`id`), an extra `className`, and `metadata.name`.
  - `settings-group-nested.html`: a Group in a Group, and a Group inside a Column of a Columns block.
  - `group-unsupported-children.html`: separate Groups holding a Spacer, a Cover, a shortcode, Custom HTML, `<!-- wp:block {"ref":123} /-->`, a third-party block, `<!-- wp:latest-posts /-->`, an empty Group, a `wp-block-group__inner-container` Group, a `<nav class="wp-block-group">` Group (`{"tagName":"nav"}`), a Group holding a paragraph and a markup-less `<!-- wp:image /-->`, a Group with stray text before its first inner block, a Group with a stray `<span>` between inner blocks, and a Columns whose Column holds a Group with a Spacer.

- [ ] **Step 2: Write the failing tests.**
  - `test-block-serializer.js`, `describe('groupFullySupported')`: true for a Group of paragraph + heading; true for a Group in a Group; false for a Group holding `core/spacer`; false for one holding a Group holding `core/spacer`; false for a Group with no inner blocks; false for an `inner-container` Group; false for a `nav` Group; false for a Group holding a paragraph and `<!-- wp:image /-->`; false for a Group holding a Columns whose Column holds `<!-- wp:image /-->`; false for stray text inside the wrapper before, between or after inner blocks; false for a stray element inside the wrapper; false for text outside the wrapper element.
  - `test-editor-containers.js`, `describe('group block')`: `setContent` of `settings-group.html` produces a `groupBlock` whose children are `heading`, `paragraph`, `bulletList`; for every `settings-group-*.html`, `getContent()` before any edit `===` the fixture, and after typing one character into the first paragraph inside a Group and deleting it again, `getContent()` `===` the fixture; a `section` Group's node has `attrs.tagName === 'section'`; `win.document.querySelectorAll(".passthrough-card").length === 0` for `settings-group.html`; pasting Quill's own copy of a Group yields a `groupBlock`; `cleanPastedHTML` keeps an external `<div class="wp-block-group"><p>Hello</p></div>` and pasting it yields a `groupBlock`; an external `<section class="wp-block-group"><p>Hello</p></section>` still flattens to `<p>Hello</p>`, as today.
  - `test-editor-preservation.js`, `describe('a group with an unsupported block stays locked')`: for `group-unsupported-children.html`, every top-level Group and the Columns load as `gutenbergPassthrough` with `unsupportedSource` equal to their exact source slice; after an edit to a paragraph added before them, every slice is still in `getContent()` byte for byte; the `blocksAtRisk` message posts `names: []`.
  - `test-editor-preservation.js`: for `settings-group.html` after an edit, `blocksAtRisk` posts `names: []`.

- [ ] **Step 3: Run the tests to verify they fail.**
  Run: `node --test Scripts/test-block-serializer.js Scripts/test-editor-containers.js Scripts/test-editor-preservation.js`
  Expected: FAIL. `groupFullySupported` is not exported, and Groups load as passthrough cards.

- [ ] **Step 4: Implement.**
  - `groupFullySupported`: false if `innerBlocks` is empty; false if any descendant's `blockName` fails `modelsBlockName`; false if any descendant saves no markup (its source, block comments removed, holds no element — the same probe `blockNeedsWrapping` applies at the top level, applied at every depth); false unless `block.innerHTML` parsed into `inertDocument()` is exactly one element whose tag is in `GROUP_TAGS`, with nothing but whitespace beside it **and nothing but whitespace inside it** (inner blocks are already removed from `innerHTML`, so any child element or text there is stray content, and this also rejects `inner-container`); recurse into nested `core/group` blocks.
  - `GROUP_TAGS` is one list of the seven tags (`div`, `section`, `header`, `footer`, `main`, `aside`, `article`), used by both `groupFullySupported` and the node's parse rules so the two cannot disagree. It must be reachable from `editor.html`: expose it through a `function groupTags()` declaration, not a top-level `const`.
  - `blockNeedsWrapping`: after the existing checks, return true if the slice's tree contains any `core/group` for which `groupFullySupported` is false. `blockSourceSlices` needs to carry the parsed block (add `block` to each slice) so the tree is available.
  - Add `['wp-block-group', 'groupBlock']` to `NODE_FOR_BLOCK_CLASS` and `'wp-block-group'` to `QUILL_MODELED_BLOCK_CLASSES`.
  - `GroupBlock` node: `group: 'block'`, `content: 'block+'`, `priority: 210`; one parse rule per tag in `groupTags()` with `.wp-block-group`, each reading `tagName` from the element; `renderHTML` emits `[node.attrs.tagName, { class: 'wp-block-group' }, 0]`.

- [ ] **Step 5: Run the tests to verify they pass.** Same command. Expected: PASS. Then run `node --test Scripts/test-fixture-validity.js Scripts/test-block-parser.js` and expect PASS, with the new fixtures included automatically.

- [ ] **Step 6: Build, then run the real-WebKit check.**
  Run the build command from Global Constraints, then `./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"`.
  Expected: every `settings-group-*` fixture passes.

- [ ] **Step 7: Report.** List the changed files and test results. Do not commit.

### Task 2: Group label, outline and editing behaviour

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` (a `GroupNodeView` class next to `PassthroughNodeView` ~2532; `addNodeView` on `GroupBlock`; container CSS ~1051; `DELETABLE_BLOCKS` ~3480)
- Modify: `Sources/QuillKit/Resources/editor-transforms.js` (new `groupLabel`, exported)
- Test: `Scripts/test-editor-containers.js`, `Scripts/test-block-serializer.js`

**Interfaces:**
- Consumes: `groupBlock` from Task 1.
- Produces: `function groupLabel(attrs) -> string` in `editor-transforms.js`, where `attrs` is the Group's parsed delimiter attributes (object or null).
- The node view reads the delimiter attributes the carrier already holds on the node. Use the attribute `withBlockAttrs` stores them in; do not add a second copy.

- [ ] **Step 1: Write the failing tests.**
  - `test-block-serializer.js`, `describe('groupLabel')`: `{metadata:{name:'Hero'}}` → `'Hero'`; `{metadata:{name:''}, layout:{type:'grid'}}` → `'Grid'`; `{layout:{type:'flex',flexWrap:'nowrap'}}` → `'Row'`; `{layout:{type:'flex',orientation:'horizontal'}}` → `'Row'`; `{layout:{type:'flex',orientation:'vertical'}}` → `'Stack'`; `{layout:{type:'constrained'}}` → `'Group'`; `null` → `'Group'`.
  - `test-editor-containers.js`: after loading `settings-group-layouts.html`, the `.group-label` elements read `Group`, `Row`, `Stack`, `Grid` in order; with `metadata.name` `"<b>Hero</b>"`, the label's `textContent` is `<b>Hero</b>` and it has no element children; `getContent()` contains no `group-label`; with the caret in an empty last paragraph inside a Group, pressing Enter leaves the caret outside the Group (use the same key-dispatch helper the Columns Enter test in `test-editor-keyboard.js` uses); with the caret inside a Group, the delete command for `DELETABLE_BLOCKS` removes the whole Group.

- [ ] **Step 2: Run the tests to verify they fail.**
  Run: `node --test Scripts/test-block-serializer.js Scripts/test-editor-containers.js`
  Expected: FAIL. `groupLabel` is undefined and there is no `.group-label`.

- [ ] **Step 3: Implement.**
  - `groupLabel` as specified.
  - `GroupNodeView`: `dom` is an element of `node.attrs.tagName` with class `wp-block-group`; its first child is `<div class="group-label" contenteditable="false">` set with `textContent`; then a `contentDOM` div. `ignoreMutation` returns true for mutations inside the label.
  - Add `.ProseMirror .wp-block-group` to the shared container rules at ~1051 (position, margin, padding, border, radius, background, and their `body.dark` versions).
  - `.group-label`: `font-size: 11px`, the editor's sans-serif stack, secondary colour matching `.passthrough-card-hint` in each theme, not italic, `margin-bottom: 6px`, `user-select: none`.
  - `DELETABLE_BLOCKS`: add `['groupBlock', 'group']`.
  - If Enter does not leave the Group, give `groupBlock` the same exit handling Columns uses; find that handling before writing a new one.

- [ ] **Step 4: Run the tests to verify they pass.** Same command. Expected: PASS.

- [ ] **Step 5: Build and look.** Run the build command. On a new local draft (click "+ New Post"), use Code View to paste `settings-group-layouts.html` and `settings-group-styled.html`, leave Code View, and screenshot light and dark. Check the outline, the labels, and that typing inside works.

- [ ] **Step 6: Report.** Include the screenshots. Do not commit.

### Task 3: Locked-card label from the block's custom name

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js` (`unsupportedWrapper`, `parsePassthroughBlock`, new `cardLabel`)
- Test: `Scripts/test-block-serializer.js`, `Scripts/test-editor-passthrough.js`

**Interfaces:**
- Produces: `function cardLabel(blockName, attrs, fallback) -> string`: `attrs.metadata.name` when it is a non-empty string, else `fallback`.
- `unsupportedWrapper(doc, source, blockName, attrs)` gains `attrs` (the slice's parsed attributes; `blockSourceSlices` already has them as `attrsJSON`, and the slice carries `block` from Task 1).

- [ ] **Step 1: Write the failing tests.**
  - `test-block-serializer.js`: `cardLabel('core/cover', {metadata:{name:'Hero'}}, 'Cover')` → `'Hero'`; with `metadata.name: ''` → `'Cover'`; with `metadata.name: 7` → `'Cover'`; with `attrs` null → `'Cover'`.
  - `test-editor-passthrough.js`: a top-level `<!-- wp:cover {"metadata":{"name":"Hero"}} -->…` card's `.passthrough-card-label` reads `Hero`; a Cover without a name reads `Cover`; a Cover with a name nested inside a Column reads its name; a name of `"<b>Hero</b>"` renders as literal text.

- [ ] **Step 2: Run the tests to verify they fail.**
  Run: `node --test Scripts/test-block-serializer.js Scripts/test-editor-passthrough.js`
  Expected: FAIL.

- [ ] **Step 3: Implement** `cardLabel` and use it in `unsupportedWrapper` and both returns of `parsePassthroughBlock` that know `attrsJSON`.

- [ ] **Step 4: Run the tests to verify they pass.** Same command. Then run `node --test Scripts/test-editor-preservation.js` and expect PASS; the labels must not change any saved bytes.

- [ ] **Step 5: Build, and report.** Do not commit.

### Task 4: Locked-card text preview

**Files:**
- Modify: `Sources/QuillKit/Resources/editor-transforms.js` (new `cardPreviewText`, exported)
- Modify: `Sources/QuillKit/Resources/editor.html` (`_peekText` ~2525 and `PassthroughNodeView`)
- Test: `Scripts/test-block-serializer.js`, `Scripts/test-editor-passthrough.js`

**Interfaces:**
- Produces: `function cardPreviewText(source, doc) -> string` (`''` when there is no text). Task 5 uses it for synced-pattern content.

- [ ] **Step 1: Write the failing tests.**
  - `test-block-serializer.js`, `describe('cardPreviewText')`: a Cover holding `<h2>Become a member</h2><p>Join <strong>today</strong></p>` → `'Become a member · Join today'`; a Spacer → `''`; text inside `<script>`, `<style>`, `<template>` and `<noscript>` never appears; block comments never appear; runs of whitespace collapse to one space; a 200-character paragraph gives 120 characters + `'…'`; `<img src=x onerror="globalThis.__ran=1">` gives `''` and `globalThis.__ran` stays undefined.
  - `test-editor-passthrough.js`: a Cover card's `.passthrough-card-peek` reads the joined text; a Spacer card has no `.passthrough-card-peek`; a Custom HTML card's peek still shows its markup.

- [ ] **Step 2: Run the tests to verify they fail.**
  Run: `node --test Scripts/test-block-serializer.js Scripts/test-editor-passthrough.js`
  Expected: FAIL.

- [ ] **Step 3: Implement.** `cardPreviewText` strips block comments, parses into `doc || inertDocument()`, removes `script, style, template, noscript`, and walks text nodes. It inserts a boundary between text whose nearest block-level ancestors differ (block-level: `p, h1–h6, li, div, figure, figcaption, blockquote, pre, td, th, a.wp-block-button__link, summary, section, article, header, footer, aside`). It joins segments with `' · '`, collapses whitespace, and cuts at 120 characters + `'…'`. In `PassthroughNodeView`, Custom HTML cards keep `_peekText`; every other card uses `cardPreviewText` and appends no peek element when it returns `''`.

- [ ] **Step 4: Run the tests to verify they pass.** Same command. Expected: PASS.

- [ ] **Step 5: Build, then screenshot** the Cover and Media & Text cards from the original screenshot's content on a new local draft. Report. Do not commit.

### Task 5: Synced-pattern cards (editor side)

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` (`PassthroughNodeView`; `window.setContent` ~6218; `_exitCodeView` ~6091; new `window.setSyncedPattern`)
- Test: `Scripts/test-editor-passthrough.js` (new `describe('synced pattern cards')`)

**Interfaces:**
- Consumes: `cardPreviewText` (Task 4).
- Produces, editor → Swift: `window.webkit.messageHandlers.requestSyncedPatterns.postMessage({ generation: Int, refs: [Int] })`.
- Produces, Swift → editor: `window.setSyncedPattern(generation: Int, ref: Int, result)`, where `result` is one of `{ title: String, content: String }`, `{ notFound: true }` or `{ failed: true }`.
- Edit button: `window.webkit.messageHandlers.openSyncedPattern.postMessage({ ref: Int })`. The editor never holds a URL; Swift builds it (Task 6), so the button works before the fetch finishes.

- [ ] **Step 1: Write the failing tests.** Stub `win.webkit.messageHandlers` with `requestSyncedPatterns`, `openSyncedPattern`, `contentChanged` and `blocksAtRisk` recorders, as `test-editor-bridge.js:41` does.
  - Loading two cards for ref 123 and one for ref 456 posts once, with `refs` `[123, 456]` and a `generation`; a post without synced patterns posts nothing; each `setContent` posts a higher `generation` than the last.
  - Before any result: label `Synced pattern`, no peek, hint `Shared across posts · ` with an `Edit in WordPress` button; clicking it posts `{ ref: 123 }` to `openSyncedPattern`.
  - `setSyncedPattern(g, 123, {title:'Newsletter signup', content:'<!-- wp:paragraph --><p>Get new posts by email</p><!-- /wp:paragraph -->'})`, with `g` the current generation, updates both 123 cards to `Synced pattern: Newsletter signup` with peek `Get new posts by email`.
  - An empty title gives `Synced pattern #123` with the peek.
  - `{notFound:true}` gives `Synced pattern #123 (not found)`, no peek and no button.
  - `{failed:true}` gives `Synced pattern #123` with the button.
  - A result changes neither `getContent()` nor the undo depth, and posts no `contentChanged`.
  - `setSyncedPattern(g, 999, …)` for a ref not on the page throws nothing and changes nothing.
  - Load post A with ref 123 (generation `gA`), then post B with ref 123 (generation `gB`), deliver B's loaded result, then deliver `setSyncedPattern(gA, 123, {failed:true})`: B's card still shows B's title.
  - A top-level synced pattern's saved bytes are unchanged after an edit elsewhere.

- [ ] **Step 2: Run the tests to verify they fail.**
  Run: `node --test Scripts/test-editor-passthrough.js`
  Expected: FAIL.

- [ ] **Step 3: Implement.**
  - A synced-pattern card is a `gutenbergPassthrough` whose `unsupportedSource` parses (`parseBlocks`) to one block named `core/block` with a numeric `attrs.ref`.
  - Module-level `_syncedPatterns = new Map()` (ref → result) and `_syncedPatternViews = new Map()` (ref → Set of views). Views register in the constructor and unregister in `destroy()`. Each renders from `_syncedPatterns.get(ref)`.
  - Post both messages with optional chaining (`window.webkit?.messageHandlers?.requestSyncedPatterns?.postMessage`), as `requestMediaSizes` does, so a host without the handler, such as FixtureCheck before Task 6, does not throw.
  - A module-level `_syncedPatternGeneration` counter. `setContent` and the user-edited branch of `_exitCodeView` increment it and clear `_syncedPatterns`, then collect the refs from the document and post them with the new generation if there are any.
  - `window.setSyncedPattern` ignores a call whose generation is not the current one or whose ref has no registered view; otherwise it stores the result and re-renders those views. It never dispatches a transaction.
  - Add a synced-pattern probe to `window.__runScriptSinkProbes` (~6266): for each source, `setContent('<!-- wp:block {"ref":1} /-->')`, then `setSyncedPattern(currentGeneration, 1, { title: source, content: source })`. FixtureCheck's existing `script-sinks/` corpus and its wait for image error events then cover fetched content in real WebKit. The jsdom `onerror` assertion cannot prove this, because jsdom does not fire image errors here.

- [ ] **Step 4: Run the tests to verify they pass.** Same command, then `node --test Scripts/test-editor-preservation.js`. Expected: PASS.

- [ ] **Step 5: Build and run the real-WebKit check.** `./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"`. Expected: pass, including the script-handler probes.

- [ ] **Step 6: Report.** The Swift side is not wired yet, so cards stay in the loading state in the app. Do not commit.

### Task 6: Synced-pattern fetch (Swift side)

**Files:**
- Modify: `Sources/QuillKit/API/WordPressClient.swift` (new `fetchSyncedPattern(id:)`, next to `fetchPage`)
- Create: `Sources/QuillKit/API/Models/WPSyncedPattern.swift`
- Modify: `Sources/QuillKit/Views/Editor/EditorView.swift` (two closures, init parameters, `userContentController.add` for `requestSyncedPatterns` and `openSyncedPattern`)
- Modify: `Sources/QuillKit/Views/Editor/EditorCoordinator.swift` (`case "requestSyncedPatterns"`, `case "openSyncedPattern"`, `handleRequestSyncedPatterns`, `syncedPatternJS`)
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift` (implement the closure next to `onRequestMediaSizes` ~129)
- Modify: `Sources/QuillKit/App/FixtureCheck.swift` (handler list ~27)
- Test: `Tests/QuillTests/WordPressClientTests.swift`, `Tests/QuillTests/EditorCoordinatorTests.swift`, `Tests/QuillTests/PostEditorHelpersTests.swift`

**Interfaces:**
- Consumes: the message and `window.setSyncedPattern` contract from Task 5.
- Produces: `public struct WPSyncedPattern: Decodable, Sendable { let id: Int; let status: String; let title: String; let content: String }`, decoding `status`, `title.raw` and `content.raw`.
- Produces: `public func fetchSyncedPattern(id: Int) async throws -> WPSyncedPattern`, GET `blocks/{id}` with query `context=edit`, `_fields=id,status,title,content`.
- Produces: `public func syncedPatternEditURL(id: Int) -> URL?` on `WordPressClient`: `{siteURL without trailing /}/wp-admin/post.php?post={id}&action=edit`.
- Produces: `public enum SyncedPatternResult: Sendable { case loaded(WPSyncedPattern), notFound, failed }`.
- Produces: `var onRequestSyncedPattern: ((Int) async -> SyncedPatternResult)?` and `var onOpenSyncedPattern: ((Int) -> Void)?` on `EditorView` and `EditorCoordinator`.
- Produces: `static func syncedPatternJS(generation: Int, ref: Int, result: SyncedPatternResult) -> String` on `EditorCoordinator`, returning the `setSyncedPattern(…)` call with the result JSON-encoded through `JSONSerialization`.

- [ ] **Step 1: Write the failing tests.**
  - `WordPressClientTests`: `fetchSyncedPatternRequestsBlocksEndpointWithEditContext` checks the path `/wp-json/wp/v2/blocks/123`, `context=edit` and `_fields=id,status,title,content`; `fetchSyncedPatternDecodesStatusRawTitleAndContent`; `fetchSyncedPatternThrowsHTTPErrorOn404` expects `APIError.httpError(statusCode: 404, _)`; `syncedPatternEditURLAtDomainRoot` → `https://example.com/wp-admin/post.php?post=123&action=edit`; `syncedPatternEditURLInSubdirectory`, with site `https://example.com/blog/`, → `https://example.com/blog/wp-admin/post.php?post=123&action=edit`.
  - `EditorCoordinatorTests`: `syncedPatternJSLoaded` contains `setSyncedPattern(7, 123,` and the title and content; `syncedPatternJSEscapesQuotesAndScriptClose` checks that a title holding `"` and `</script>` gives a string that `JSONSerialization` round-trips; `syncedPatternJSNotFound` contains `"notFound":true`; `syncedPatternJSFailed` contains `"failed":true`.
  - `PostEditorHelpersTests`: `PostEditorView.syncedPatternResult(for:)` maps a loaded pattern with status `trash` to `.notFound`, `publish` to `.loaded`, `APIError.httpError` 404 and 410 to `.notFound`, and any other error to `.failed`.

- [ ] **Step 2: Run the tests to verify they fail.**
  Run: `swift test --filter "WordPressClientTests|EditorCoordinatorTests|PostEditorHelpersTests"`
  Expected: FAIL to compile, because the symbols are undefined.

- [ ] **Step 3: Implement.**
  - The client methods and model as listed.
  - Coordinator: `case "requestSyncedPatterns"` reads `body["generation"] as? Int` and `body["refs"] as? [Int]` and calls `handleRequestSyncedPatterns(generation:refs:)`. That method, following `handleRequestMediaSizes`, starts one `Task` per ref, awaits the closure, and evaluates `syncedPatternJS` with the same generation on the main actor. Stale results are dropped in the editor by generation (Task 5); Swift does no selection check of its own.
  - Coordinator: `case "openSyncedPattern"` reads `body["ref"] as? Int` and calls `onOpenSyncedPattern`. `PostEditorView` implements it by building `syncedPatternEditURL(id:)` and opening it with `NSWorkspace.shared.open` only if `EditorCoordinator.isAllowedExternalURL` accepts it.
  - `PostEditorView` closure: with no credentials, return `.failed`. Otherwise call `fetchSyncedPattern` and map the outcome through a pure `static func syncedPatternResult(for: Result<WPSyncedPattern, Error>) -> SyncedPatternResult`: status `trash` → `.notFound` (an editor can still read a trashed pattern, but WordPress renders nothing for it), 404 or 410 → `.notFound`, any other error → `.failed`.
  - Add `"requestSyncedPatterns"` and `"openSyncedPattern"` to the `FixtureCheck` handler list and to `EditorView`'s `userContentController.add` calls.

- [ ] **Step 4: Run the tests to verify they pass.** Same command. Expected: PASS. Then run `swift test` in full and expect PASS.

- [ ] **Step 5: Build and try it on the local Studio site.** Using the REST API, create a synced pattern (`POST /wp/v2/blocks` with title `Newsletter signup` and one paragraph) and a draft post containing `<!-- wp:block {"ref":ID} /-->`. Open the draft in Quill and check the label, the preview and Edit in WordPress. Trash the pattern, reopen the draft, and check `(not found)`. Then delete it permanently (`DELETE /wp/v2/blocks/ID?force=true`), reopen, and check `(not found)` again. Report with screenshots. Do not commit.

### Task 7: Docs and full verification

**Files:**
- Modify: `docs/block-model.md`, `Sources/QuillKit/Resources/CLAUDE.md` (output table row for `core/group`), `site/docs.html`, `docs/testing-plan.md` (new tests, counts, a §7 synced-pattern step), `CLAUDE.md` (test counts), `Scripts/fixtures/README.md` (if Task 1 missed any row)

- [ ] **Step 1: Run everything.**
  Run: `./test.sh`
  Expected: all suites pass. Record the new Swift and JS totals.

- [ ] **Step 2: Run the real-WebKit check.**
  Run: `./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"` against a current build.
  Expected: pass.

- [ ] **Step 3: Update the docs** listed above with the spec's rules, and the counts from Step 1.

- [ ] **Step 4: Report** the final file list, test totals and anything deferred. Do not commit; the user asks for the Codex review and commit separately.
