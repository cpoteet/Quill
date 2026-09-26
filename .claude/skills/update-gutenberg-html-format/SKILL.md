---
name: update-gutenberg-html-format
description: Use when WordPress/Gutenberg changes the expected HTML format for a block element (headings, lists, images, tables, embeds, footnotes, galleries, etc.) and Quill's editor needs to match it — updating toWordPressHTML(), a block descriptor or setting, or a Tiptap parseHTML() rule.
---

# Fixing a Gutenberg markup change for one block

Use this to make Quill match a block whose saved markup changed. To find what a whole WordPress release changed, run the checklist in `docs/wordpress-release-audit.md` first; it sends each real markup change here.

## Where compatibility lives

Grep for names rather than trusting line numbers.

1. **`toWordPressHTML(html)`** in `Sources/QuillKit/Resources/editor-transforms.js` — turns Tiptap's HTML into Gutenberg's on every save.
2. **`block-descriptors.js`** — maps each Tiptap node to its Gutenberg block (`blockName`, shape, `attrsFrom`, `ownedAttrs`). `wrapInDelimiters` writes a `<!-- wp:name -->` pair for every descriptor, so teaching Quill a block is a descriptor entry.
3. **`block-settings.js`** — one entry per block setting (a class, style or attribute); it drives the Tiptap attribute, the delimiter key and the toolbar control.
4. **Each node's `parseHTML()`** in `editor.html` — reads Gutenberg markup back into the node on load.

Background: `docs/block-model.md` (the attribute carrier, unsupported-block preservation), and in `Sources/QuillKit/Resources/CLAUDE.md` the per-element output table and the attribute precedence rules.

## Steps

1. **Get the real markup.** Strongest first:
   - The `save()` code in the Studio install's `/Users/Chris/Dev/Studio/wp-includes/js/dist/block-library.js` (confirm the version with `grep wp_version /Users/Chris/Dev/Studio/wp-includes/version.php`). Read it to learn the format only — it is GPL, so never copy its code into Quill.
   - Markup saved by the block editor on the Studio site (`GET /wp-json/wp/v2/posts/{id}?context=edit`, `content.raw`). Never the production site.
   - Gutenberg's fixtures, `packages/block-library/src/*/test/fixtures/*.html`, at the Gutenberg commit the release pins (the checklist shows how to find it).
   - Not a REST-created post: the API stores what you send without running the editor's serializer.

2. **Find which path the block takes.**
   - **Quill models it** (`modelsBlockName` in `block-descriptors.js` accepts it): go to step 3.
   - **Quill does not model it, at the top level of a post:** `wrapUnsupportedBlocks` already preserves it byte for byte. No code change; add a test in `Scripts/test-block-serializer.js` (`wrapUnsupportedBlocks`) or `Scripts/test-editor-preservation.js`.
   - **Quill does not model it, nested inside a block Quill models:** `gutenbergPassthrough` keeps it. A `<figure>` root is caught only if its class is not in `QUILL_MODELED_FIGURE_CLASSES`. Test in `Scripts/test-editor-passthrough.js`.

3. **Change the output** — the descriptor, the settings entry or `toWordPressHTML`. Traps (full text in `docs/editor-gotchas.md`):
   - A new whole-tree `querySelectorAll` pass in `toWordPressHTML` must sit between the passthrough stash and the splice-back, or it reaches into preserved blocks.
   - Delimiter attributes go through `serializeAttributes`, never `JSON.stringify`.
   - A regex over the final HTML must treat `<` and `>` inside attribute values as data; comment-strip regexes use `[\s\S]*?-->`, not `.*?` or a greedy class.
   - For a block Quill does not fully model, keep a verbatim `sourceHTML`-style attribute and re-emit it, as gallery and embed do, rather than rebuilding the markup.

4. **Change the parsing** if the stored format changed: the node's `parseHTML()`, with a `getAttrs` that reads the inner element for figure-wrapped blocks.

5. **Test.**
   - Add tests to the relevant `Scripts/test-editor*.js`.
   - If you have real markup, add it as a fixture in `Scripts/fixtures/` (read its `README.md`); `test-fixture-validity.js` then checks Quill's save of it with WordPress's own block validator.
   - Run `./test.sh`. If the Edit tool turns quotes curly in a JS test file, see the test-suite gotchas in `docs/testing-plan.md`.

6. **Check in real WebKit and the app.**
   - Run the build-and-run command in the root `CLAUDE.md`, then `./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"`.
   - With Quill connected to the Studio site: click "+ New Post", paste the markup through code view, edit a paragraph, Save Draft, and read the saved HTML from SQLite (`docs/gotchas.md`, "Verify saved draft HTML straight from SQLite"). Computer-use clicks need `request_full_control` to reach the editor. Discard the draft.
   - A session that cannot drive the app reports this step as not verified rather than skipping it.

7. **Update the docs:** the per-element table in `Sources/QuillKit/Resources/CLAUDE.md`, and the test counts in the root `CLAUDE.md` and `docs/testing-plan.md`.
