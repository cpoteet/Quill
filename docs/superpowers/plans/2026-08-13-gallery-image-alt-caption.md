# Gallery Per-Image Alt Text & Captions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user set per-image alt text and a caption for each image while building a gallery in Quill's gallery sheet, seeded from the WordPress media item and written into the gallery block's markup.

**Architecture:** Six independent tasks, back to front. The editor (`editor.html`'s `galleryBlock`) learns to render and parse a per-image `caption`; `WPMedia` learns to decode WordPress's `caption` field; `GallerySheet` swaps its `[WPMedia]` selection for a `[GallerySelection]` carrying editable `alt`/`caption`; the final task adds the expandable-row UI. Nothing touches the `sourceHTML` verbatim path that preserves galleries loaded from existing posts, and `editor-transforms.js` is not modified at all.

**Tech Stack:** Swift 6 / SwiftUI (macOS 13+), Swift Testing (`@Test`/`#expect`), Tiptap 2.x in WKWebView, Node `node:test` + jsdom for the JS suites.

**Spec:** `docs/superpowers/specs/2026-08-13-gallery-image-alt-caption-design.md`

## Global Constraints

- Captions are **plain text only** — no rich text, links, or line breaks. Render with `textContent`, never `innerHTML`.
- Alt/caption edits are **block-local**. Never write back to the WordPress media library (no `PUT /media/{id}` from the gallery sheet).
- Alt/caption are **insert-time only**. Do not add any flow for reopening or editing an inserted gallery.
- Do not modify `galleryBlock`'s `sourceHTML` render branch, and do not modify `Sources/QuillKit/Resources/editor-transforms.js`.
- `toWordPressHTML` needs no change: its figure pass (`editor-transforms.js:173`) already reaches nested gallery image figures, adds `wp-element-caption` to non-empty figcaptions, and removes empty ones.
- After every code change affecting the app: quit Quill, run `./build.sh`, reopen. Manual verification uses a **new local draft** only — never a published post or page.
- Full test command: `./test.sh` (runs Swift + all JS suites).

---

### Task 1: `WPMedia.caption` decoding

**Files:**
- Modify: `Sources/QuillKit/API/Models/WPMedia.swift:11` (add property), `:31-39` (CodingKeys), `:41-52` (init)
- Test: `Tests/QuillTests/WPMediaDecodingTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `WPMedia.caption: RenderedString?` and `WPMedia.captionText: String` (plain text, `""` when absent). Task 5 calls `captionText`.

- [ ] **Step 1: Write the failing tests**

Append inside the existing `@Suite struct WPMediaDecodingTests` in `Tests/QuillTests/WPMediaDecodingTests.swift` (before its closing brace). The suite already has a private `decode(_:)` helper — use it.

```swift
    @Test func captionDecodesPlainTextFromRaw() throws {
        let json = """
        {"id":6,"source_url":"https://example.com/img.jpg",
         "caption":{"rendered":"<p>A rendered caption</p>","raw":"A raw caption"}}
        """
        let media = try decode(json)
        #expect(media.captionText == "A raw caption")
    }

    @Test func captionRawHasHTMLStrippedAndEntitiesDecoded() throws {
        let json = """
        {"id":7,"source_url":"https://example.com/img.jpg",
         "caption":{"rendered":"<p>x</p>","raw":"Bob &amp; <em>Alice</em>"}}
        """
        let media = try decode(json)
        #expect(media.captionText == "Bob & Alice")
    }

    // context=edit is always requested for media (WordPressClient.swift:116,122), so
    // `raw` is normally present. A rendered-only payload (e.g. the upload response)
    // yields an empty caption rather than HTML — matching RenderedString.excerptText.
    @Test func captionWithOnlyRenderedYieldsEmptyText() throws {
        let json = """
        {"id":8,"source_url":"https://example.com/img.jpg",
         "caption":{"rendered":"<p>Rendered only</p>"}}
        """
        let media = try decode(json)
        #expect(media.caption != nil)
        #expect(media.captionText == "")
    }

    @Test func missingCaptionIsNilAndTextIsEmpty() throws {
        let json = """
        {"id":9,"source_url":"https://example.com/img.jpg"}
        """
        let media = try decode(json)
        #expect(media.caption == nil)
        #expect(media.captionText == "")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --filter WPMediaDecodingTests
```

Expected: compile error — `value of type 'WPMedia' has no member 'captionText'`.

- [ ] **Step 3: Add the property, coding key, decode line, and computed text**

In `Sources/QuillKit/API/Models/WPMedia.swift`, add the stored property directly below `public var altText: String` (line 11):

```swift
    public var caption: RenderedString?
```

Change the `CodingKeys` line `case link, date` to:

```swift
        case link, date, caption
```

Add to `init(from:)`, directly below the `altText` line:

```swift
        caption = try c.decodeIfPresent(RenderedString.self, forKey: .caption)
```

Add the computed property below `sizedURL(for:)`:

```swift
    /// Plain-text caption, for prefilling the gallery sheet's caption field.
    /// Reads `caption.raw` only (present because both media fetches use
    /// `context=edit`); returns "" when the caption is absent or rendered-only.
    public var captionText: String {
        caption?.excerptText ?? ""
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
swift test --filter WPMediaDecodingTests
```

Expected: PASS, all tests in the suite.

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/API/Models/WPMedia.swift Tests/QuillTests/WPMediaDecodingTests.swift
git commit -m "feat: decode the WordPress media caption field on WPMedia"
```

---

### Task 2: Render per-image captions in `galleryBlock`

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html:1726-1742` (the `renderHTML` reconstruction loop)
- Test: `Scripts/test-editor-gallery.js`

**Interfaces:**
- Consumes: nothing.
- Produces: `galleryBlock` renders `images[].caption` (string) as `<figcaption class="wp-element-caption">` inside that image's `<figure class="wp-block-image">`. Task 5 sends this key over the bridge.

- [ ] **Step 1: Write the failing tests**

Append a new `describe` block at the end of `Scripts/test-editor-gallery.js`. `editor` and `win` are the module-level globals the file's `before()` hook already sets up.

```js
describe('galleryBlock — per-image captions', () => {
  const insert = (images, extra = {}) => {
    editor.commands.setContent('<p></p>')
    editor.commands.insertContent({
      type: 'galleryBlock',
      attrs: { images, columns: 3, cropped: true, linkTo: 'none', ...extra },
    })
    return editor.getHTML()
  }

  test('a non-empty caption renders as a wp-element-caption figcaption', () => {
    const html = insert([{ id: 1, url: 'http://x.test/a.png', alt: '', caption: 'Sunrise over the bay' }])
    assert.match(html, /<figcaption class="wp-element-caption">Sunrise over the bay<\/figcaption>/)
  })

  test('each caption lands inside its own image figure', () => {
    const html = insert([
      { id: 1, url: 'http://x.test/a.png', alt: '', caption: 'First' },
      { id: 2, url: 'http://x.test/b.png', alt: '', caption: '' },
    ])
    const doc = new win.DOMParser().parseFromString(html, 'text/html')
    const figures = doc.querySelectorAll('figure.wp-block-image')
    assert.equal(figures.length, 2)
    assert.equal(figures[0].querySelector('figcaption').textContent, 'First')
    assert.equal(figures[1].querySelector('figcaption'), null)
  })

  test('an omitted caption emits no figcaption at all', () => {
    const html = insert([{ id: 1, url: 'http://x.test/a.png', alt: '' }])
    assert.doesNotMatch(html, /figcaption/)
  })

  test('caption text containing markup is escaped, not injected', () => {
    const html = insert([
      { id: 1, url: 'http://x.test/a.png', alt: '', caption: '<script>x</script> & <b>bold</b>' },
    ])
    assert.doesNotMatch(html, /<script>/)
    assert.doesNotMatch(html, /<b>bold<\/b>/)
    assert.match(html, /&lt;script&gt;/)
    assert.match(html, /&amp;/)
  })

  test('the caption follows the anchor when linkTo is media', () => {
    const html = insert(
      [{ id: 1, url: 'http://x.test/a.png', fullUrl: 'http://x.test/a-full.png', alt: '', caption: 'Linked' }],
      { linkTo: 'media' }
    )
    const doc = new win.DOMParser().parseFromString(html, 'text/html')
    const fig = doc.querySelector('figure.wp-block-image')
    assert.equal(fig.children[0].tagName, 'A')
    assert.equal(fig.children[1].tagName, 'FIGCAPTION')
  })

  test('a per-image alt override lands on the img', () => {
    const html = insert([{ id: 1, url: 'http://x.test/a.png', alt: 'Overridden alt' }])
    assert.match(html, /alt="Overridden alt"/)
  })
})
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
node --test Scripts/test-editor-gallery.js
```

Expected: the caption tests FAIL (no `figcaption` in the output); the alt-override test already passes.

- [ ] **Step 3: Emit the figcaption in `renderHTML`**

In `Sources/QuillKit/Resources/editor.html`, inside `GalleryBlock`'s `renderHTML` reconstruction loop, directly after the `if (node.attrs.linkTo === 'media') { … } else { … }` block that appends the image and before `figure.appendChild(imgFigure)`:

```js
          // Plain text only — textContent, never innerHTML: caption text comes
          // straight from a TextField in GallerySheet and must not inject markup.
          if (image.caption) {
            const cap = document.createElement('figcaption')
            cap.className = 'wp-element-caption'
            cap.textContent = image.caption
            imgFigure.appendChild(cap)
          }
```

Leave the `if (node.attrs.sourceHTML)` branch at the top of `renderHTML` untouched.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
node --test Scripts/test-editor-gallery.js
```

Expected: PASS, all tests in the file (19 existing + 6 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Scripts/test-editor-gallery.js
git commit -m "feat: render per-image captions in the gallery block"
```

---

### Task 3: Extract captions when parsing a loaded gallery

**Files:**
- Modify: `Sources/QuillKit/Resources/editor.html:1693-1701` (the `parseHTML` `getAttrs` image map)
- Test: `Scripts/test-editor-gallery.js`

**Interfaces:**
- Consumes: Task 2's caption attribute shape.
- Produces: `node.attrs.images[].caption` populated on parse. Nothing reads it back yet — this keeps the attrs honest rather than repeating the per-image `sizeSlug` ground-truth loss documented in `Sources/QuillKit/Resources/CLAUDE.md`.

- [ ] **Step 1: Write the failing tests**

Append to `Scripts/test-editor-gallery.js`:

```js
describe('galleryBlock — parsing captions from loaded galleries', () => {
  const LOADED =
    '<figure class="wp-block-gallery has-nested-images columns-2 is-cropped">' +
    '<figure class="wp-block-image size-large"><img src="http://x.test/a.png" alt="" class="wp-image-1">' +
    '<figcaption class="wp-element-caption">Loaded caption</figcaption></figure>' +
    '<figure class="wp-block-image size-large"><img src="http://x.test/b.png" alt="" class="wp-image-2"></figure>' +
    '</figure>'

  const galleryAttrs = () => {
    let attrs = null
    editor.state.doc.descendants(node => {
      if (node.type.name === 'galleryBlock') attrs = node.attrs
    })
    return attrs
  }

  test('a caption on a loaded image figure is extracted into node attrs', () => {
    editor.commands.setContent(LOADED, false)
    const attrs = galleryAttrs()
    assert.equal(attrs.images[0].caption, 'Loaded caption')
  })

  test('an image with no figcaption parses to an empty caption', () => {
    editor.commands.setContent(LOADED, false)
    const attrs = galleryAttrs()
    assert.equal(attrs.images[1].caption, '')
  })

  test('a loaded gallery still re-renders verbatim from sourceHTML', () => {
    editor.commands.setContent(LOADED, false)
    assert.match(editor.getHTML(), /<figcaption class="wp-element-caption">Loaded caption<\/figcaption>/)
  })
})
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
node --test Scripts/test-editor-gallery.js
```

Expected: the first two FAIL with `undefined !== 'Loaded caption'` and `undefined !== ''`; the third already passes (the `sourceHTML` branch preserves it).

- [ ] **Step 3: Capture the caption in `getAttrs`**

In `Sources/QuillKit/Resources/editor.html`, in `GalleryBlock.parseHTML()`'s `imageFigures.map(fig => { … })`, add a `caption` key to the returned object alongside `id`, `url`, and `alt`:

```js
                caption: fig.querySelector('figcaption')?.textContent || '',
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
node --test Scripts/test-editor-gallery.js
```

Expected: PASS, all tests in the file.

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/Resources/editor.html Scripts/test-editor-gallery.js
git commit -m "feat: capture per-image captions when parsing a gallery"
```

---

### Task 4: Regression-test captions through `toWordPressHTML`

**Files:**
- Test: `Scripts/test-editor.js` (append to the existing `describe('toWordPressHTML — gallery', …)` block)

No production code changes. This task proves the claim the spec relies on: the figure pass at `editor-transforms.js:173` already normalizes gallery captions, and the comment-wrapping pass stays idempotent with captions present.

**Interfaces:**
- Consumes: the markup shape Task 2 produces.
- Produces: nothing.

- [ ] **Step 1: Write the tests**

Add inside the existing `describe('toWordPressHTML — gallery', () => { … })` in `Scripts/test-editor.js`, after the `'gallery wrapping is idempotent'` test. The `wp()` helper and `GALLERY_FIGURE` const are already in scope.

```js
  const CAPTIONED_GALLERY =
    '<figure class="wp-block-gallery has-nested-images columns-3 is-cropped">' +
    '<figure class="wp-block-image size-large"><img src="http://x.test/a.png" alt="" class="wp-image-145">' +
    '<figcaption class="wp-element-caption">First caption</figcaption></figure>' +
    '<figure class="wp-block-image size-large"><img src="http://x.test/b.png" alt="" class="wp-image-146"></figure>' +
    '</figure>'

  test('gallery image captions survive the save transform', () => {
    const out = wp(CAPTIONED_GALLERY)
    assert.match(out, /<figcaption class="wp-element-caption">First caption<\/figcaption>/)
  })

  test('a captionless gallery image gains no figcaption', () => {
    const out = wp(CAPTIONED_GALLERY)
    assert.equal((out.match(/<figcaption/g) || []).length, 1)
  })

  test('an unclassed gallery caption gains wp-element-caption', () => {
    const out = wp(CAPTIONED_GALLERY.replace(' class="wp-element-caption"', ''))
    assert.match(out, /<figcaption class="wp-element-caption">First caption<\/figcaption>/)
  })

  test('an empty gallery caption is removed', () => {
    const withEmpty = CAPTIONED_GALLERY.replace('First caption', '')
    assert.doesNotMatch(wp(withEmpty), /<figcaption/)
  })

  test('wrapping a captioned gallery is idempotent', () => {
    const once = wp(CAPTIONED_GALLERY)
    assert.equal(wp(once), once)
  })
```

- [ ] **Step 2: Run the tests**

```bash
node --test Scripts/test-editor.js
```

Expected: PASS. These assert existing behavior, so they should pass on the first run — that is the point of the task. If any fail, stop: the spec's "no `toWordPressHTML` changes" assumption is wrong and needs revisiting before continuing.

- [ ] **Step 3: Commit**

```bash
git add Scripts/test-editor.js
git commit -m "test: cover gallery image captions through toWordPressHTML"
```

---

### Task 5: `GallerySelection` and the insert payload

**Files:**
- Modify: `Sources/QuillKit/Views/Media/GallerySheet.swift` (new struct; `:4-5` closure type, `:16` state, `:22-28` init, `:67` insert call, `:91` selection check, `:133-166` list rows, `:232-238` toggle, `:251` upload append)
- Modify: `Sources/QuillKit/Views/Editor/PostEditorView.swift:179-187` (payload builder)

**Interfaces:**
- Consumes: `WPMedia.captionText` (Task 1); the `caption` payload key the editor reads (Task 2).
- Produces: `public struct GallerySelection: Identifiable` with `media: WPMedia`, `alt: String`, `caption: String`, `id: Int`. `GallerySheet.onInsert` becomes `(_ images: [GallerySelection], _ columns: Int, _ cropped: Bool, _ linkTo: String, _ sizeSlug: String) -> Void`. Task 6 binds to `alt`/`caption`.

There is no unit-test harness for SwiftUI views in this project; verification is a clean build, the full suite, and a manual check that the gallery flow is unchanged apart from the new payload key.

- [ ] **Step 1: Add the `GallerySelection` struct**

At the top of `Sources/QuillKit/Views/Media/GallerySheet.swift`, below `import SwiftUI` and above `public struct GallerySheet`:

```swift
/// One image queued for insertion, with the alt text and caption that will be
/// written into this gallery's markup. Seeded from the media library item;
/// edits here never write back to the library.
///
/// `public` because `GallerySheet.init` is public and its `onInsert` closure
/// references this type.
public struct GallerySelection: Identifiable {
    public let media: WPMedia
    public var alt: String
    public var caption: String
    public var id: Int { media.id }
}
```

- [ ] **Step 2: Change the selection state and the callback type**

In `GallerySheet`, change the `onInsert` stored property (line 4) and the `init` parameter (line 23) so both read:

```swift
    var onInsert: (_ images: [GallerySelection], _ columns: Int, _ cropped: Bool, _ linkTo: String, _ sizeSlug: String) -> Void
```

```swift
        onInsert: @escaping (_ images: [GallerySelection], _ columns: Int, _ cropped: Bool, _ linkTo: String, _ sizeSlug: String) -> Void,
```

Change the state declaration (line 16) to:

```swift
    @State private var selected: [GallerySelection] = []
```

- [ ] **Step 3: Update every `selected` call site inside the sheet**

`toggle(_:)` seeds both fields from the media item:

```swift
    private func toggle(_ media: WPMedia) {
        if let idx = selected.firstIndex(where: { $0.id == media.id }) {
            selected.remove(at: idx)
        } else {
            selected.append(
                GallerySelection(media: media, alt: media.altText, caption: media.captionText)
            )
        }
    }
```

The upload path (line 251, inside `uploadFromDisk`'s `Task`) becomes:

```swift
                selected.append(
                    GallerySelection(media: uploaded, alt: uploaded.altText, caption: uploaded.captionText)
                )
```

In the media grid (line 91), the `isSelected` check is unchanged in form — `GallerySelection.id` is the media id, so this still compiles as written:

```swift
                            MediaThumbnail(media: media, isSelected: selected.contains(where: { $0.id == media.id }), size: 80)
```

In the selection `List`, rename the loop variable and reach through `.media`:

```swift
                        ForEach(selected) { sel in
                            HStack(spacing: 8) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                AsyncImage(url: URL(string: sel.media.thumbnailURL)) { phase in
                                    if case .success(let image) = phase {
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } else {
                                        Rectangle().fill(.quaternary)
                                    }
                                }
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                Text(sel.media.title.decodedTitle)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    selected.removeAll { $0.id == sel.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .onHover { hovering in
                                if hovering { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
                            }
                        }
```

The `onMove`, the `Insert Gallery` button's `onInsert(selected, columns, cropped, linkTo, sizeSlug)` call, and `selected.isEmpty`/`selected.count` all stay exactly as they are.

- [ ] **Step 4: Send `alt` and `caption` from the selection**

In `Sources/QuillKit/Views/Editor/PostEditorView.swift`, replace the `GallerySheet(onInsert:)` payload builder (lines 179-187) with:

```swift
                    GallerySheet(onInsert: { selections, columns, cropped, linkTo, sizeSlug in
                        let imagePayload: [[String: Any]] = selections.map { sel in
                            [
                                "id": sel.media.id,
                                "url": sel.media.sizedURL(for: sizeSlug),
                                "fullUrl": sel.media.sourceURL,
                                "alt": sel.alt,
                                "caption": sel.caption,
                            ]
                        }
```

The rest of the closure (the `info` dictionary, the `NotificationCenter.post`, `showGallerySheet = false`) is unchanged. `EditorCoordinator.insertGallery` serializes the dictionaries generically (`EditorCoordinator.swift:262`) and needs no edit.

- [ ] **Step 5: Build and run the full suite**

```bash
swift build 2>&1 | tail -20
```

Expected: no errors.

```bash
./test.sh
```

Expected: all Swift and JS suites pass.

- [ ] **Step 6: Verify in the app**

```bash
./build.sh && open Quill.app
```

In the running app, on a **new local draft** (never a published post): insert a gallery of 2–3 images from the sheet exactly as before. Confirm the flow is unchanged — selection, reorder, remove, upload-and-auto-select, Insert Gallery. Open Code View (`</>`) and confirm the markup is what it was before this task, plus a `<figcaption class="wp-element-caption">` on any image whose media library item already carries a caption.

- [ ] **Step 7: Commit**

```bash
git add Sources/QuillKit/Views/Media/GallerySheet.swift Sources/QuillKit/Views/Editor/PostEditorView.swift
git commit -m "feat: carry per-image alt and caption through the gallery insert payload"
```

---

### Task 6: Expandable Alt/Caption fields in the selection list

**Files:**
- Modify: `Sources/QuillKit/Views/Media/GallerySheet.swift` (new `expandedIDs` state; the selection `List` rows)

**Interfaces:**
- Consumes: `GallerySelection.alt` / `.caption` (Task 5).
- Produces: the user-facing feature. Nothing depends on it.

- [ ] **Step 1: Add the expansion state**

In `GallerySheet`, below `@State private var selected: [GallerySelection] = []`:

```swift
    @State private var expandedIDs: Set<Int> = []
```

- [ ] **Step 2: Rebuild the row with a chevron and the two fields**

Replace the `ForEach(selected) { sel in … }` body from Task 5 with a binding-based loop. The chevron is the only expansion affordance — the row body stays free for drag-to-reorder, and `.onHover`'s open-hand cursor stays on the header `HStack` so it never appears over a text field.

```swift
                        ForEach($selected) { $sel in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Image(systemName: "line.3.horizontal")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                    AsyncImage(url: URL(string: sel.media.thumbnailURL)) { phase in
                                        if case .success(let image) = phase {
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        } else {
                                            Rectangle().fill(.quaternary)
                                        }
                                    }
                                    .frame(width: 32, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    Text(sel.media.title.decodedTitle)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                    Spacer()
                                    Button {
                                        if expandedIDs.contains(sel.id) {
                                            expandedIDs.remove(sel.id)
                                        } else {
                                            expandedIDs.insert(sel.id)
                                        }
                                    } label: {
                                        Image(systemName: expandedIDs.contains(sel.id) ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Alt text and caption")
                                    Button {
                                        expandedIDs.remove(sel.id)
                                        selected.removeAll { $0.id == sel.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .onHover { hovering in
                                    if hovering { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
                                }

                                if expandedIDs.contains(sel.id) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        sectionLabel("Alt text")
                                        TextField("", text: $sel.alt)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 11))
                                        sectionLabel("Caption")
                                        TextField("", text: $sel.caption)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 11))
                                    }
                                    .padding(.leading, 19)
                                    .padding(.bottom, 4)
                                }
                            }
                        }
```

- [ ] **Step 3: Build and run the full suite**

```bash
swift build 2>&1 | tail -20
```

Expected: no errors.

```bash
./test.sh
```

Expected: all Swift and JS suites pass.

- [ ] **Step 4: Verify the feature end to end in the app**

```bash
./build.sh && open Quill.app
```

On a **new local draft**, walk this checklist:

1. Insert ▸ Gallery, select three images. Rows look as they did before, plus a chevron.
2. Expand the second row. Alt and Caption fields appear, seeded from the media library (alt text pre-filled where the library has it).
3. Type a distinct caption and a distinct alt in the second row. Collapse it, re-expand it — the typed text is still there.
4. Drag the third row above the first. Reordering still works, and the typed text stays with its own image.
5. Remove the first row, then re-add the same image from the grid — it comes back with library values, not the removed row's text (expected behavior).
6. Insert Gallery. Open Code View: only the second image has a `<figcaption class="wp-element-caption">`, holding exactly the typed text, and its `<img alt>` holds the typed alt.
7. Type a caption containing `<b>bold</b> & "quotes"`, insert, and confirm Code View shows it escaped as text rather than as markup.
8. Save the draft, switch to another post and back, and confirm the caption survives the round-trip.

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/Views/Media/GallerySheet.swift
git commit -m "feat: add expandable alt text and caption fields to the gallery sheet"
```

- [ ] **Step 6: Update the user guide**

In `docs/user-guide.md`, in the Galleries section, insert this paragraph directly after the one ending "…or click the **X** next to it to remove it." (currently the first paragraph of the section):

```markdown
Click the chevron on a selected image to set its **Alt text** and **Caption**. Both start from whatever the media library holds for that image, and changes you make here apply only to this gallery — the media library item itself is untouched, so other posts using the same image are unaffected. Captions are plain text and appear beneath their image on your published site.
```

Then extend the paragraph that begins "Click **Insert Gallery**" so its second sentence reads:

```markdown
A gallery appears as a read-only thumbnail grid card in Quill; to change it — including alt text and captions — delete it and insert a new one, or edit the markup directly in Code View.
```

```bash
git add docs/user-guide.md
git commit -m "docs: document per-image alt text and captions in the gallery sheet"
```

---

## Verification summary

- Task 1: `swift test --filter WPMediaDecodingTests`
- Tasks 2–3: `node --test Scripts/test-editor-gallery.js`
- Task 4: `node --test Scripts/test-editor.js`
- Tasks 5–6: `swift build`, `./test.sh`, then `./build.sh` and the manual checklists above on a local draft.
