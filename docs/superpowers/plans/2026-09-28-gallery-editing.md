# Editable Galleries Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Double-clicking a gallery card opens `GallerySheet` filled in with that gallery, and **Update Gallery** replaces it in place without losing anything the sheet does not show.

**Architecture:** First the `galleryBlock` node learns to hold and render every per-image detail a real gallery carries, proven by rebuilding both gallery fixtures from the node. Then a JS bridge sends a gallery's attributes to Swift and replaces the node on return. Last, `GallerySheet` gains an edit mode, and a pure payload builder in `PostEditorView` merges the sheet's choices with the untouched keys.

**Tech Stack:** Tiptap 2 in `editor.html` / `editor-transforms.js`, jsdom test suites under `Scripts/`, Swift 6 / SwiftUI, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-11-gallery-editing-design.md` (read it first; its Decisions section is binding).

## Global Constraints

- Work on `main`. **Do not commit** unless the user asks; each task ends by reporting to the user instead.
- After any Swift or Resources change, run exactly: `pkill -f "^$PWD/Quill.app/Contents/MacOS/Quill"; sleep 2 && ./build.sh 2>&1 && open Quill.app`. Report a build failure instead of opening.
- No new file under `Sources/QuillKit/Resources/` (a new one needs its own `cp` line in `build.sh`).
- Anything `editor.html` reads from `editor-transforms.js` must be a `function` declaration, never a top-level `const`.
- Comments: default none; one line maximum; never narrate the change.
- Sheet actions stay in the bottom bar; inputs stay `.roundedBorder`.
- Manual testing only on a new local draft ("+ New Post"), discarded afterwards.
- Copy, verbatim: sheet title `Edit Gallery`, primary button `Update Gallery`, card link `Edit`, size menu entry `Mixed`, link menu entry `Keep Current Links`.

## Review Focus

1. The post changes while the sheet is open (autosave reload, switching posts): Update must do nothing, never insert a second gallery. Pinned in Task 2.
2. Cancel an edit, then use the toolbar's Gallery button: that must insert a new gallery, not replace the old one. Pinned in Task 2.
3. An attachment-linked gallery switched to Full Image must save `media` links, not the carried `attachment`. Pinned in Task 2 (pruning) and Task 3 (payload).
4. A gallery image with no media id (hotlinked, or deleted from the library) must survive an edit with its URL. Pinned in Task 1 and Task 3.
5. Script in a loaded caption must never run. Pinned in Task 1.

---

### Task 1: The node holds and renders every per-image detail

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` (`GalleryNodeView`, `GalleryBlock` ~line 2264–2388)
- Test: `Scripts/test-editor-gallery.js`
- Docs: `Sources/QuillKit/Resources/CLAUDE.md` (gallery row), `docs/editor-gotchas.md` (delete the "`galleryBlock.sizeSlug` is per-gallery" known edge case)

**Interfaces:**
- Produces: each `images[]` entry is `{ id: number|null, url, fullUrl, alt, caption, captionHTML: string|null, sizeSlug: string|null, href: string|null, blockAttrs: string|null, extraClasses: string }`. The gallery gains `captionHTML: string|null`. Existing attributes keep their names.
- Render rules: image figure class = `wp-block-image size-${image.sizeSlug || node.attrs.sizeSlug || 'large'}` + ` ${extraClasses}` when non-empty; `data-quill-block-attrs` = `image.blockAttrs` when set; link target = `image.href ?? (node.attrs.linkTo === 'media' ? (image.fullUrl || image.url) : null)`; caption = `captionHTML` when set, else `caption` as text; the gallery figure gets `align${blockAttrs.align}` when the carried JSON has `align`, and a trailing `figcaption.blocks-gallery-caption.wp-element-caption` from its `captionHTML`.

- [ ] **Step 1: Write the failing tests** in a new `describe('galleryBlock — rebuilding a loaded gallery')`. Helper: `rebuild(src)` = `win.setContent(src)`, set `sourceHTML: null` on every `galleryBlock` via one `setNodeMarkup` transaction, then `win.extractFootnotes(win.toWordPressHTML(editor.getHTML())).content`.

```js
test('settings-gallery.html rebuilt from the node comes back byte for byte', () => {
  assert.equal(rebuild(fixture('settings-gallery.html')), fixture('settings-gallery.html'))
})
test('gallery-block.html rebuilt from the node keeps every comment attribute', () => {
  const src = fixture('gallery-block.html')
  assert.deepEqual(commentAttributes(rebuild(src)), commentAttributes(src))
  assert.deepEqual(problems(rebuild(src)), [])
})
test('a theme class on an image figure survives a rebuild', () => {
  assert.match(rebuild(fixture('gallery-block.html')), /class="wp-block-image size-large image-plain"/)
})
test('an image with no media id keeps its url through a rebuild', () => {
  const src = '<!-- wp:gallery {"linkTo":"none"} -->\n<figure class="wp-block-gallery has-nested-images columns-default is-cropped"><!-- wp:image {"sizeSlug":"large","linkDestination":"none"} -->\n<figure class="wp-block-image size-large"><img src="https://x.test/hotlinked.png" alt=""/></figure>\n<!-- /wp:image --></figure>\n<!-- /wp:gallery -->'
  assert.match(rebuild(src), /src="https:\/\/x\.test\/hotlinked\.png"/)
})
test('script in a loaded caption never runs', async () => {
  win.__pwned = false
  rebuild(fixture('settings-gallery.html').replace('Screens from', '<img src="x" onerror="window.__pwned=true">Screens from'))
  await new Promise(r => setTimeout(r, 50))
  assert.equal(win.__pwned, false)
})
```

`commentAttributes` and `problems` come from `./wp-validator.js`; `fixture(name)` reads `Scripts/fixtures/<name>`. Require the validator after the editor is ready, as `test-fixture-validity.js` does, and call its `close()` in `after()`.

- [ ] **Step 2: Run to verify they fail** — `node --test Scripts/test-editor-gallery.js`. Expected: the byte-for-byte and comment-attribute tests fail (lost `attachment`/`custom` links, sizes, gallery caption); the script test may already pass.
- [ ] **Step 3: Extend `parseHTML`'s `getAttrs`** to read each key in the Interfaces block. `blockAttrs` is the JSON of the image figure's preceding `wp:image` comment (use the same comment-reading approach as `blockCommentAttrsJSON`). Read `captionHTML` as the `figcaption`'s `innerHTML`, `null` when absent. Keep `caption` as `textContent`. Set `fullUrl` to the `href` when `uploadStem(href) === uploadStem(src)` (the link is the image's own file; `uploadStem` is already a function in `editor-transforms.js`), else leave it unset.
- [ ] **Step 4: Extend `renderHTML`'s rebuild path** per the render rules. Build caption HTML inside a `document.createElement('template')` and move its `content` in; never assign `innerHTML` to an element the page owns.
- [ ] **Step 5: Run to verify they pass**, then `./test.sh`. Expected: all suites pass; the existing gallery insert tests are unchanged.
- [ ] **Step 6: Update the docs** named under Files, build and open the app, report to the user.

### Task 2: Edit and replace in the editor

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html` (`GalleryNodeView`, `GalleryBlock.addKeyboardShortcuts`, `window.insertGallery` ~line 5760, the `gallery` toolbar command ~line 4308, `.gallery-card-hint` CSS)
- Test: `Scripts/test-editor-gallery.js`

**Interfaces:**
- Consumes: Task 1's `images[]` shape.
- Produces: `window.editGallery(pos: number)` posts `insertGallery` with body `{ edit: { images, columns, cropped, linkTo } }`, where `linkTo` is the gallery `blockAttrs.linkTo` when present, else the node's `linkTo`. The toolbar command posts `{}` and clears any remembered edit. `window.insertGallery(json)` with `payload.replace === true` and `payload.keepLinks: boolean` replaces the remembered node.

- [ ] **Step 1: Write the failing tests** in `describe('galleryBlock — editing')`. Stub `win.webkit = { messageHandlers: { insertGallery: { postMessage: m => posted.push(m) } } }` in `before()`.

```js
test('editGallery posts the node attrs under edit', () => {
  win.setContent(fixture('settings-gallery.html'))
  win.editGallery(galleryPos(0))
  assert.equal(posted.at(-1).edit.linkTo, 'attachment')
  assert.equal(posted.at(-1).edit.images.length, 2)
})
test('replace swaps the gallery in one undo step and clears sourceHTML', () => {
  win.setContent(fixture('settings-gallery.html'))
  win.editGallery(galleryPos(0))
  win.insertGallery(JSON.stringify({ replace: true, keepLinks: true, images: reversed(0), columns: 3, cropped: true, linkTo: 'attachment' }))
  assert.equal(galleries().length, 2)
  assert.equal(galleries()[0].attrs.sourceHTML, null)
  assert.equal(galleries()[0].attrs.columns, 3)
  editor.commands.undo()
  assert.notEqual(galleries()[0].attrs.sourceHTML, null)
})
test('replace does nothing when the post changed while the sheet was open', () => {
  win.setContent(fixture('settings-gallery.html'))
  win.editGallery(galleryPos(0))
  win.setContent(fixture('settings-gallery.html'))
  win.insertGallery(JSON.stringify({ replace: true, keepLinks: true, images: reversed(0), columns: 3, cropped: true, linkTo: 'attachment' }))
  assert.equal(galleries().length, 2)
  assert.notEqual(galleries()[0].attrs.sourceHTML, null)
})
test('the toolbar Gallery button after a cancelled edit inserts instead of replacing', () => {
  win.setContent(fixture('settings-gallery.html'))
  win.editGallery(galleryPos(0))
  win._runToolbarCommand('gallery')
  win.insertGallery(JSON.stringify({ images: [{ id: 9, url: 'https://x.test/n.png', alt: '', caption: '' }], columns: 3, cropped: true, linkTo: 'none', sizeSlug: 'large' }))
  assert.equal(galleries().length, 3)
})
test('switching to Full Image drops carried link destinations', () => {
  win.setContent(fixture('settings-gallery.html'))
  win.editGallery(galleryPos(0))
  const images = posted.at(-1).edit.images.map(i => ({ ...i, href: i.fullUrl || i.url }))
  win.insertGallery(JSON.stringify({ replace: true, keepLinks: false, images, columns: 2, cropped: true, linkTo: 'media' }))
  const out = win.toWordPressHTML(editor.getHTML())
  assert.doesNotMatch(out, /"linkDestination":"attachment"/)
  assert.doesNotMatch(out, /"linkTo":"attachment"/)
})
test('the edited gallery saves byte-identically on a second save', () => { /* replace as above, then save twice and compare */ })
test('double-click and Return on a selected card call editGallery', () => { /* dispatch dblclick on the card DOM; NodeSelection + Enter keydown; assert posted grew by one each */ })
```

Helpers: `galleries()` returns `galleryBlock` nodes in order; `galleryPos(n)` their positions; `reversed(n)` returns gallery n's `images` in reverse. `win._runToolbarCommand` is whatever the toolbar's command map exposes; if nothing is exposed, click `[data-cmd="gallery"]`.

- [ ] **Step 2: Run to verify they fail** — `node --test Scripts/test-editor-gallery.js`. Expected: `editGallery is not a function`.
- [ ] **Step 3: Implement.** `window.editGallery` stores `{ pos, node }` in a module-level `_galleryEdit`. `window.insertGallery` with `replace` checks `editor.state.doc.nodeAt(pos) === node`, then one `setNodeMarkup` with the payload's attributes, `sourceHTML: null`, and the gallery `blockAttrs` with `ids` and `sizeSlug` removed (and `linkTo` too when `keepLinks` is false). When `keepLinks` is false, remove `linkDestination` from each image's `blockAttrs`. Clear `_galleryEdit` afterwards, and in the toolbar command.
- [ ] **Step 4: Add the card affordances.** `GalleryNodeView` listens for `dblclick` and for a click on an `Edit` link (a `<button type="button">` in `.gallery-card-hint`, styled as a text link in the editor's link colour variable, not a pill); both call `window.editGallery(getPos())`. Add an `Enter` keyboard shortcut on `GalleryBlock` that fires only for a `NodeSelection` of a `galleryBlock`. The node view needs `getPos` from `addNodeView`'s arguments.
- [ ] **Step 5: Run to verify they pass**, then `./test.sh`.
- [ ] **Step 6: Build, open the app, report to the user.**

### Task 3: Swift data for edit mode

**Files:**
- Create: `Sources/QuillKit/Views/Media/GalleryEdit.swift`
- Modify: `Sources/QuillKit/API/WordPressClient.swift` (media section), `Sources/QuillKit/Views/Media/GallerySheet.swift` (`GallerySelection`), `Sources/QuillKit/Views/Editor/PostEditorView.swift` (payload builder)
- Test: `Tests/QuillTests/WordPressClientTests.swift`, `Tests/QuillTests/PostEditorHelpersTests.swift`

**Interfaces:**
- Consumes: Task 2's `edit` body.
- Produces:
  - `public struct GalleryImage: Codable, Sendable, Equatable { var id: Int?; var url: String; var fullUrl: String?; var alt: String; var caption: String; var captionHTML: String?; var sizeSlug: String?; var href: String?; var blockAttrs: String?; var extraClasses: String }`
  - `public struct GalleryEdit: Sendable { var images: [GalleryImage]; var columns: Int; var cropped: Bool; var linkTo: String; init?(body: Any) }`, plus `var initialSizeSlug: String` (`"mixed"` when the images' sizes differ, else the shared size, else `"large"`) and `var showsKeepLinks: Bool` (true when `linkTo` is not `none`/`media`, or any image's link disagrees with `linkTo`).
  - `public struct GallerySelection: Identifiable { var media: WPMedia?; var existing: GalleryImage?; var alt: String; var caption: String; let id: Int }` — `id` is the media id, or a negative number unique within the sheet for an image with none.
  - `WordPressClient.fetchMedia(ids: [Int]) async throws -> [WPMedia]`
  - `nonisolated static func galleryPayload(selections: [GallerySelection], columns: Int, cropped: Bool, linkTo: String, sizeSlug: String, editing: GalleryEdit?) -> [String: Any]` on `PostEditorView`. `linkTo` is `"none"`, `"media"` or `"keep"`; `sizeSlug` is a slug or `"mixed"`.

- [ ] **Step 1: Write the failing tests.**
  - `fetchMediaByIdsSendsIncludeAndPerPage`: mirroring `fetchMediaItemHitsCorrectEndpointWithEditContext`, `fetchMedia(ids: [3, 1, 2])` sends `include=3,1,2`, `per_page=3`, `context=edit`.
  - `galleryEditDecodesTheEditBody`: `GalleryEdit(body:)` from a dictionary shaped like Task 2's body yields its images in order, and `initialSizeSlug == "mixed"` for sizes `thumbnail`/`large`.
  - `galleryEditShowsKeepLinksForAttachmentGalleries`: `linkTo: "attachment"` → `showsKeepLinks == true`; `linkTo: "media"` with every image's `href` set → `false`.
  - `galleryPayloadKeepsUntouchedKeys`: an existing image with `blockAttrs`, `extraClasses` and `captionHTML`, caption unchanged → all three in the payload, plus `"replace": true`.
  - `galleryPayloadDropsCaptionHTMLWhenCaptionChanged`.
  - `galleryPayloadMixedKeepsEachSize`: `sizeSlug: "mixed"` → each existing image keeps its `sizeSlug` and `url`; a new image gets `"large"` and `media.sizedURL(for: "large")`.
  - `galleryPayloadKeepLinksLinksNewImagesByGalleryLinkTo`: `linkTo: "keep"` with `editing.linkTo == "attachment"` → existing image keeps its `href`, new image's `href == media.link`, `"keepLinks": true`.
  - `galleryPayloadFullImageReplacesLinks`: `linkTo: "media"` → every `href` is `media.sourceURL` (existing `fullUrl ?? url` when there is no `WPMedia`), `"keepLinks": false`.
  - `galleryPayloadImageWithoutMediaKeepsItsURL`.
- [ ] **Step 2: Run to verify they fail** — `swift test --filter "WordPressClientTests|PostEditorHelpersTests"`. Expected: compile errors for the missing types.
- [ ] **Step 3: Implement** the types and functions in the Interfaces block. `GalleryEdit.init?(body:)` round-trips `body["edit"]` through `JSONSerialization` into `JSONDecoder`. The insert path's existing payload keys (`id`, `url`, `fullUrl`, `alt`, `caption`, `columns`, `cropped`, `linkTo`, `sizeSlug`) stay as they are when `editing` is nil, so inserting a gallery is unchanged; move the dictionary-building out of the `.sheet` closure into `galleryPayload`.
- [ ] **Step 4: Run to verify they pass**, then `./test.sh`.
- [ ] **Step 5: Build, open the app, report to the user.**

### Task 4: The sheet in edit mode

**Files:**
- Modify: `Sources/QuillKit/Views/Media/GallerySheet.swift`, `Sources/QuillKit/Views/Editor/PostEditorView.swift` (`showGallerySheet` → an optional `GalleryEdit` state), `Sources/QuillKit/Views/Editor/EditorCoordinator.swift` (`case "insertGallery"`, `insertGallery(...)` forwards the payload as-is), `Sources/QuillKit/Views/Editor/EditorView.swift` (`onInsertGallery: ((GalleryEdit?) -> Void)?`)
- Docs: `site/docs.html` (Galleries section: how to edit, what Mixed and Keep Current Links mean), `Sources/QuillKit/Views/Media/CLAUDE.md`, `docs/testing-plan.md` (counts, new rows, a manual checklist entry)

**Interfaces:**
- Consumes: Task 3's `GalleryEdit`, `GallerySelection`, `fetchMedia(ids:)`, `galleryPayload`.
- Produces: `GallerySheet.init(editing: GalleryEdit? = nil, onInsert:, onCancel:)`; `onInsert` gains nothing new, the `"keep"` and `"mixed"` values travel through its existing `linkTo`/`sizeSlug` strings.

- [ ] **Step 1: Wire the message.** `case "insertGallery"` passes `GalleryEdit(body: message.body)` to `onInsertGallery`. `PostEditorView` presents the sheet when it receives a call, with `editing` set or nil. On insert it posts `.insertGalleryData` with `galleryPayload(...)`; `EditorCoordinator.handleInsertGallery` forwards the whole `userInfo` dictionary to `window.insertGallery` instead of picking five keys.
- [ ] **Step 2: Edit mode in the sheet.** With `editing` set: title and primary button use the Global Constraints copy; `columns`, `cropped` start from `editing`; `sizeSlug` starts from `initialSizeSlug`, and the Size picker lists `Mixed` (tag `"mixed"`) only while that is the value; `linkTo` starts at `"keep"` when `showsKeepLinks`, and the Link To picker lists `Keep Current Links` (tag `"keep"`) only in that case. `selected` is built from `editing.images` in order after `fetchMedia(ids:)` returns, matching by id; an image with no match gets `media: nil`, its own `url` as thumbnail, and a title from its URL's last path component. While that request runs, the selection pane shows a `ProgressView`.
- [ ] **Step 3: Verify in the app.** Build and open. On a new local draft, switch to code view and paste `Scripts/fixtures/settings-gallery.html`, switch back, then for each gallery: double-click → sheet shows both images, `Mixed` for the second gallery, `Keep Current Links` for both → reorder, change a caption, Update → Save Draft, read the draft from SQLite (`docs/gotchas.md`) and confirm the untouched image still has its custom link, attachment links and formatted caption. Repeat once choosing Full Image. Also check Return on a selected card, the Edit link, Cancel, and Cmd+Z. Discard the draft.
- [ ] **Step 4: Run `./test.sh`, the build, and the WebKit fixture check** (`./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"`, all pass).
- [ ] **Step 5: Update the docs** named under Files, including the test counts in `CLAUDE.md` and `docs/testing-plan.md`. Report to the user with the list of changes and ask whether to commit and close cpoteet/Quill#5.
