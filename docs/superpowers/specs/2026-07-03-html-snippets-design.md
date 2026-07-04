# HTML Snippets Manager — Design Spec

**Date:** 2026-07-03
**Status:** Approved

## Overview

A personal library of reusable raw HTML snippets (ad codes, CTA boxes, share buttons, custom `<details>` blocks, etc.) that can be inserted from the toolbar without a dedicated button per item. Inserted snippets appear as a static card in the visual editor and can be hand-edited as raw HTML in code view. Each insertion is an independent copy — editing an inserted instance never touches the library entry, and editing the library entry never retroactively changes posts where it was already used.

---

## 1. Data model & storage

```swift
public struct Snippet: Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var html: String
    public var createdAt: Date
    public var updatedAt: Date
}
```

Stored as a single JSON array via the existing `JSONFileStore<T>` pattern, mirroring `AISettingsStore`:

```swift
public struct SnippetStore {
    private static let store = JSONFileStore<[Snippet]>("snippets.json")
    public static func save(_ snippets: [Snippet]) throws { try store.save(snippets) }
    public static func load() throws -> [Snippet]? { try store.load() }
}
```

`AppState.snippets: [Snippet]` loads once via `try? SnippetStore.load() ?? []`, mirroring `aiSettings`. The manage window writes through a callback that updates both `AppState.snippets` and the file, following the `onSaveAISettings` pattern.

---

## 2. Toolbar button & insert popover

A new toolbar button (`#btn-snippets`) sits next to `#btn-code-view` in the utility group — grouped there because both need to stay **enabled** while in code view. `_enterCodeView()`'s toolbar-disable pass (`querySelectorAll('button:not(#btn-code-view), select')`) is extended to also exempt `#btn-snippets`.

Clicking it posts `showSnippetPicker` (with the button's bounding rect) to Swift, which shows an `NSPopover` hosting a new `SnippetPickerView` — the same `NSHostingController` + `ObservableObject` model + `sizingOptions = .preferredContentSize` plumbing as the existing `LinkPickerView`.

The popover shows:
- A search field filtering by snippet name
- A list of snippets, each row showing the name and a truncated, single-line preview of its HTML
- Empty state: "No snippets yet" plus the manage link below
- A persistent "Manage snippets…" row at the bottom that opens the manage window

Clicking a row inserts the snippet (behavior differs by mode — see §4 and §6) and closes the popover.

---

## 3. Manage Snippets window

A separate sheet (not the toolbar popover), reachable via "Manage snippets…". Layout:
- Left: a list of snippet names, with a "+ New" control above it
- Right: a **Name** field and a monospace **HTML** textarea for the selected snippet
- Footer: **Cancel** / **Save**, right-aligned, `Save` styled as the primary action

Edits apply to a working copy in memory. Cancel discards all changes (including deletions); Save commits the working copy to `AppState.snippets` and `SnippetStore`. Because Cancel is always available as a safety net, Delete requires no separate confirmation dialog.

New snippets default to name "New snippet" and empty HTML, immediately selected for editing.

---

## 4. Editor representation — `SnippetBlock` node

A new atomic Tiptap node, modeled directly on the existing `EmbedBlock` (`editor.html:1491`):

- **Attributes:** `name` (string), `html` (string, the raw content)
- **Node view:** renders a static, non-editable card — name as title, truncated monospace HTML preview underneath, same visual language as the embed card
- **Not editable inline.** The card cannot be typed into. The only way to change its content is via code view (§6). Selecting, moving, and deleting the card as a whole works like any other atomic block (embed, image).

Because `SnippetBlock` is a genuine node in the Tiptap/ProseMirror schema — not raw unparsed text — it is included whenever `editor.getHTML()` serializes the document, regardless of what else in the post was edited. This is the same mechanism that already lets images, embeds, tables, and footnotes survive arbitrary edits elsewhere in a post. See §7 for the specific test case this guarantees.

---

## 5. Round-trip format — comment markers, no wrapper element

**Constraint:** the saved HTML must not add any visible or functional markup around the snippet's content — no wrapper `<div>`, no extra attributes on existing elements.

**Mechanism:** `toWordPressHTML()` gains an unwrap step for `SnippetBlock`'s intermediate DOM representation. It reads the node's `name` attribute, then replaces the node's DOM element with a pair of inert HTML comments, reparenting all of the element's children out to sit directly between the comments and removing the now-empty element:

```html
<!-- quill:snippet name="Newsletter CTA" -->
{raw html, byte-for-byte, however many top-level elements it contains}
<!-- /quill:snippet -->
```

HTML comments are never rendered or styled by browsers or WordPress — nothing is added to the live page. This is standard WordPress behavior, not something specific to this app: `wp_kses` (which only runs on save for users lacking the `unfiltered_html` capability) passes HTML comments through unchanged regardless of content, and `force_balance_tags` (which always runs on save) only rewrites real tags, since its tag-matching requires a word-character name immediately after `<` — a comment opener never qualifies. This is the identical mechanism that already lets Gutenberg's own `<!-- wp:paragraph -->`-style delimiters survive WordPress's save pipeline for every user role.

**Name escaping:** before embedding, the snippet's `name` has `"` replaced with `&quot;` and any run of two or more `-` characters collapsed to a single `-` (HTML comments cannot contain `--` per spec). This is a lossy but safe transform applied only to the marker's `name` attribute — it never touches the snippet's actual HTML content.

**Loading:** a new preprocessing pass, symmetric to the unwrap step, runs before `editor.commands.setContent()` (both at initial post load and when exiting code view after an edit — see §6). It walks the DOM for `quill:snippet` comment pairs and, for each one, gathers **all sibling nodes between the open and close comment** (not just a single child element — a snippet's content may contain multiple top-level elements, e.g. three `<details>` blocks), reparents them under a temporary wrapper, and removes the comment nodes. `SnippetBlock`'s `parseHTML` rule matches that wrapper and reconstructs the node with its original `name` and the reparented content as `html`. The card reliably reappears every time the post is reopened, with the correct name, regardless of how many elements or what structure it contains.

Both passes are pure DOM operations (create comment nodes, reparent children) consistent with how the rest of the transform pipeline works — no regex on raw HTML strings.

---

## 6. Code view support

`#btn-snippets` stays live while `codeViewActive` (see §2). Clicking a snippet there splices the same marker-wrapped text directly into the `<textarea>` at the cursor position, replacing any active selection, rather than inserting a Tiptap node.

Because this is exactly the raw text a saved document would contain, the user can then freely hand-edit anything inside the markers — including restructuring the content, e.g. duplicating a single `<details>` block into three. If the user exits code view without further edits, nothing changes. If they made edits (including inside a snippet's markers), `_exitCodeView()`'s existing change-detection re-parses the whole document via `setContent`, which runs the restore pass from §5 and reconstructs the `SnippetBlock` node from whatever content is now between the markers — same name, updated `html`.

Once restored to a card, further changes to individual pieces inside it (e.g. deleting just one of three `<details>` blocks) also require going back into code view — the visual editor never edits inside the card.

---

## 7. Testing

**JS transforms** (`Scripts/test-editor.js`): the unwrap (save) and restore (load) transform pair — including a case with multiple top-level elements between the markers, and a case with `"` and `--` in the snippet name.

**JS editor keyboard / live editor** (`Scripts/test-editor-keyboard.js` or a new suite): insert a snippet via the popover equivalent, make an edit to an unrelated paragraph elsewhere in the document, call `getContent()`, and assert the snippet's marker-wrapped HTML is still present and unchanged — this is the specific regression test for the round-trip guarantee described in §4 (unlike unmodeled Gutenberg block comments, a modeled node must survive edits anywhere else in the document).

**Swift** (alongside the existing storage-layer suites): `Snippet` / `SnippetStore` codec and persistence — save, load, round-trip through `JSONFileStore`.

---

## 8. Out of scope

- **Generic passthrough for arbitrary/unrecognized Gutenberg blocks** (e.g. a real `wp:gallery` block authored in the WordPress block editor, which Quill has no node for today and which can still be lost on visual edit). The snippet marker grammar deliberately stays private and flat — no JSON attributes, no nesting, no self-closing form — specifically to avoid needing a general Gutenberg block parser. Logged as a deferred idea in `docs/future-architecture.md` (Approach E) rather than folded into this feature.
- Linking an inserted instance back to its library entry (already decided: independent copies only)
- Rendering a live preview of the snippet's HTML inside the card
- Categories/tags/search-by-content for the snippet library
- Sharing or exporting snippets between machines
