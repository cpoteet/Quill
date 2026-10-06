# Inserting and editing Custom HTML blocks

_Design, 2026-10-05._

## Problem

Quill keeps a Custom HTML block (`core/html`) as a read-only card. The only way to write a new one, or change an existing one, is to switch the whole post to Code View and edit the raw markup with block comments. Since the 2026-10-05 freeform change, HTML outside any block that Quill cannot model (a classed `<div>`, an `<iframe>`) also loads as a Custom HTML card, so these cards are more common than before.

## Goals

1. The insert menu has a **Custom HTML** item that opens a native sheet with a text box. Inserting writes the HTML into the post as a `core/html` block, wrapped in `<!-- wp:html -->` delimiters, exactly as Gutenberg's Custom HTML block saves it.
2. Every Custom HTML card has an **Edit…** button and responds to double-click. Both open the same sheet with the block's HTML filled in. Saving replaces that block.
3. The HTML is never rendered or run inside the editor. The card keeps showing a text preview of the markup.

Non-goals: a live preview of the HTML, syntax highlighting, validating the HTML, editing other read-only cards (shortcodes, spacers, third-party blocks), and editing a Custom HTML block nested inside a modeled container (columns, a group Quill models), which has no top-level card.

## What the author sees

### Insert menu

`#insert-menu` in `editor.html` gains one item, **Custom HTML**, after Preformatted.

### The sheet

```
Custom HTML
┌──────────────────────────────────────────────┐
│ <div class="ai-disclosure-box">              │
│   <p>Portions of this post were …</p>        │
│ </div>                                       │
│                                              │
└──────────────────────────────────────────────┘
                                 [Cancel] [Insert]
```

- Title, top-leading, `.font(.headline)`: "Custom HTML" when inserting, "Edit Custom HTML" when editing.
- A monospaced text box, 520pt wide, at least 240pt tall, growing with the sheet.
- Bottom bar, trailing: **Cancel** and the default action, **Insert** or **Save** (⌘↩, `.borderedProminent`). Per the sheet rule in `docs/gotchas.md`, there is no top header row.
- The default action is disabled while the text box holds only whitespace. Removing a Custom HTML block is done by deleting its card, as now.
- The box is focused when the sheet opens.
- Smart quotes, smart dashes, text replacement, spell-check and autocorrect are off. A curly quote inside an attribute value breaks the HTML, and SwiftUI's `TextEditor` follows the system substitution settings on macOS with no way to turn them off, so the box is an `NSTextView` wrapped in an `NSViewRepresentable`, the way `TitleTextField` wraps its own text view.

### The card

A card whose source is a `core/html` block changes its hint line from "Not editable in the visual editor; use Code View (</>)" to "Renders as Custom HTML in WordPress · " followed by an **Edit…** button, the same as the gallery card's. Double-clicking the card anywhere other than the button also opens the sheet. Every other read-only card is unchanged.

Undo: the insert and the replace are each one ProseMirror transaction, so ⌘Z reverses them.

## How it works

The flow is the gallery's (`window.editGallery` → `GallerySheet` → `window.insertGallery`).

### Editor → Swift

- The insert-menu action posts `window.webkit.messageHandlers.customHTML.postMessage({})`.
- `window.editCustomHTML(pos)` reads the node at `pos`, returns without doing anything unless it is a `gutenbergPassthrough` node whose `unsupportedSource` parses (`parseBlocks`) to a single `core/html` block, stores that node in `_customHTMLEdit`, and posts `{ html }`, where `html` is the block's inner HTML: the text between the opening comment and the closing comment, minus one leading and one trailing newline.
- `PassthroughNodeView` receives `getPos` so the button and double-click can call `window.editCustomHTML(getPos())`.

### Swift

- `EditorView` registers a `customHTML` message handler. `EditorCoordinator` decodes the body with `CustomHTMLRequest(body:)` (`html: String?`; `nil` means insert) and calls a new `onCustomHTML` closure on the main queue.
- `PostEditorView` holds `@State var customHTMLSheet: CustomHTMLRequest?` and presents `CustomHTMLSheet(request:onCommit:onCancel:)`.
- On commit it posts a notification that `EditorCoordinator` forwards as `window.insertCustomHTML(json)` with `{ html, replace }`, JSON-encoded the way `insertGallery` encodes its payload.

### Swift → editor

`window.insertCustomHTML(json)`:

- Builds the block source. A new block is `<!-- wp:html -->\n` + `html` + `\n<!-- /wp:html -->`. A replaced block keeps its original opening comment, so attributes such as `metadata` survive.
- Builds the same `div.wp-block-quill-unsupported` wrapper that `wrapUnsupportedBlocks` makes, in `inertDocument()`, using the shared `unsupportedWrapper` helper in `editor-transforms.js`, and inserts it as a `gutenbergPassthrough` node with `unsupportedSource` set to the source and `blockLabel` "Custom HTML".
- Insert puts the node at the current selection. Replace swaps the node only while the document still holds the exact node stored in `_customHTMLEdit`, found by identity; if it is gone, nothing changes. `_customHTMLEdit` is cleared either way.

### Saving

No change. `toWordPressHTML` already writes a card's `unsupportedSource` back unchanged, and `_reportBlocksAtRisk` already counts the `html` blocks inside a card's source, so an inserted block raises no alarm and a replaced one keeps its count.

## Script safety

The HTML is only ever stored in an attribute (`data-quill-unsupported-source`) and shown through `textContent`. It is never assigned to `innerHTML` of an element in the live page; the wrapper is built in `inertDocument()`, as `docs/gotchas.md` requires for post markup. `__runScriptSinkProbes` in `editor.html` also calls `window.insertCustomHTML` with each probe source, so `--check-fixtures` fails if a handler in inserted HTML runs in WebKit.

## Testing

jsdom, against the real `editor.html` (`Scripts/test-editor-preservation.js`, new `describe('Custom HTML insert and edit')`):

- Insert puts one card at the selection, labelled Custom HTML, and an edited save contains the block with `wp:html` delimiters.
- `editCustomHTML` posts the inner HTML without the delimiters or their newlines.
- A replace changes only that card and keeps the original opening comment's attributes.
- A replace after the card was deleted changes nothing.
- `editCustomHTML` on a shortcode card posts nothing, and only Custom HTML cards show **Edit…**.
- An inserted `<img src=x onerror=…>` never runs its handler.
- The insert-menu item posts `customHTML` with an empty body.

Swift (`Tests/QuillTests`): `CustomHTMLRequest(body:)`, failable like `GalleryEdit(body:)`, decodes `{}` as an insert and `{ html }` as an edit, and returns `nil` for a body that is not a dictionary or whose `html` is not a string, in which case no sheet opens.

Manual, in the built app, on a new local draft (root `CLAUDE.md`): insert a block, save locally, check the saved HTML in SQLite (`docs/gotchas.md`, "Verify saved draft HTML straight from SQLite"), edit it, undo the edit, and confirm a typed `"` stays straight.

Docs: `docs/block-model.md` (the card is now editable for `core/html`), the output table in `Sources/QuillKit/Resources/CLAUDE.md`, `docs/testing-plan.md` counts and tables, and `site/docs.html` (the end-user guide) gains a short Custom HTML section.

## Addendum: CSS and JavaScript tabs

Added after the first version shipped to the branch. Gutenberg's Custom HTML block keeps CSS and JavaScript inside the same `content`, as `<style data-wp-block-html="css">` and `<script data-wp-block-html="js">` ahead of the HTML, a blank line apart (`parseContent` / `serializeContent` in `packages/block-library/src/html/utils.js`). The sheet does the same split and join in Swift (`CustomHTMLParts`), so the editor bridge is unchanged. The markers are matched as exact text, and content without them stays byte for byte.

Gutenberg shows the CSS and JavaScript tabs only to users with `unfiltered_html`, because WordPress strips `<script>` and `<style>` from everyone else's posts on save. Quill asks `GET /wp/v2/users/me?context=edit` once per connection, the first time the sheet opens, and shows the tabs when the answer is yes or when the block already holds CSS or JavaScript. Offline or on an error, the sheet shows the HTML tab only.
