---
name: update-gutenberg-html-format
description: Use when WordPress/Gutenberg changes the expected HTML format for a block element (headings, lists, images, tables, embeds, footnotes, galleries, etc.) and Quill's editor needs to match it — updating toWordPressHTML() or a Tiptap parseHTML() rule.
---

# Updating Gutenberg HTML compatibility

All WordPress/Gutenberg HTML compatibility lives in two files (line numbers drift as the files grow — grep for the function/rule name rather than trusting a hardcoded line):

1. **`toWordPressHTML(html)`** in `Sources/QuillKit/Resources/editor-transforms.js` — called on every save/content-change. Transforms Tiptap's internal HTML into Gutenberg-format HTML before sending to Swift. Mostly DOM operations (create element, add class, reparent), but it also has a few regex-based passes that strip pre-existing `wp:gallery`/`wp:image`/`wp:embed` comments before re-wrapping — see the regex gotcha below before touching those.
2. **Per-node `parseHTML()` rules** in `Sources/QuillKit/Resources/editor.html` — each Tiptap node extension (`ResizableImage`, `galleryBlock`, `embedBlock`, table, footnotes, `gutenbergPassthrough`, etc.) has its own `parseHTML()`/`getAttrs` for extracting attrs from Gutenberg markup on load. Find the right one by grepping for the node's `name:` and reading its `parseHTML()` method, not by a fixed line number.

See `Sources/QuillKit/Resources/CLAUDE.md` for the current per-element output reference table and the full gotcha list (referenced ones below are just the traps most likely to bite a format update).

**Auditing a whole WordPress release** (rather than fixing one known block) has its own routine: `docs/wordpress-release-audit.md` — pre-flight steps, the ground-truth source order that worked for WP 7.1, the standing checklist, and the 7.1 run record.

## How to update when WordPress changes its HTML format

1. Check the new format against real sources, in priority order:
   - **Gutenberg's test fixtures — primary ground truth.** `packages/block-library/src/*/test/fixtures/*.html` in the `WordPress/gutenberg` GitHub repo, at the release tag matching the Gutenberg version bundled in the target WordPress release. These are the canonical `save()` output strings Gutenberg's own test suite asserts against — exact, version-pinnable, and require no login or local site.
   - **A live site as confirmation — use the scratch site, never production.** Open a post in the WordPress block editor, add the element, save, then view the stored HTML (`GET /wp-json/wp/v2/posts/{id}?context=edit`, `content.raw`). Create test content on the local Studio scratch site (localhost:8881 — the port can drift between Studio launches), NOT on the production site Quill is connected to.
   - **REST caveat:** a raw REST `POST` stores whatever you send without running Gutenberg's client-side serialization, and for an admin `content.raw` comes back byte-identical to what was posted — so a REST-only round-trip proves storage fidelity, not how the editor serializes markup. Real editor-saved markup or the fixtures are the evidence that counts.

2. Update `toWordPressHTML()` in `editor-transforms.js` to emit the new structure.
   - **Passthrough shielding window:** if you add a new whole-tree `div.querySelectorAll(...)` pass, it must run before `gutenbergPassthrough` elements are spliced back in (they're stashed out at the very top of the function and spliced back late, right before comment regeneration). A pass added after the splice-back point will reach into passthrough subtrees and corrupt content that's supposed to be preserved byte-for-byte.
   - **Regex comment-stripping:** if the new/changed block uses `<!-- wp:name -->` comments, use a non-greedy `[\s\S]*?-->` for the attrs group, not `.*?` (JS `.` excludes line terminators, so a stray `\r`/`\n` in the attrs breaks the match) and not a greedy `[^\n]*` (matches past the first comment's own `-->` when there's no whitespace between adjacent comments, deleting everything in between — this is what caused the gallery-images-disappearing regression).
   - **Verbatim round-trip pattern:** for blocks that don't have full structured-attr modeling (gallery, embed, `gutenbergPassthrough`), the established pattern is to preserve a `sourceHTML`-style attr verbatim and re-emit it unchanged, rather than fully reconstructing the output from parsed attrs. Follow this pattern for a new block type unless you're deliberately adding full structured modeling for it.
   - **Brand-new block Quill doesn't model:** usually needs no code change at all — the `gutenbergPassthrough` node in `editor.html` catches any `wp-block-*` classed, non-`<figure>` element no other parse rule claims. The check is: confirm the block's `wp-block-*` class name, run its saved markup through the passthrough logic, and assert byte-for-byte preservation with a fixture test in `Scripts/test-editor-passthrough.js` (follow the existing tests there as the pattern). Only build a real Tiptap node if the block should become visually editable in Quill.

3. If WordPress also changes how it *stores* the format (what the API sends back on load), check whether Tiptap still parses it correctly by loading an existing post. If not, add or update the relevant node's `parseHTML()` rule. For block elements wrapped in a `<figure>` (like images and tables), add a `getAttrs` rule that extracts the inner element's attrs.

4. Rebuild and test the round-trip: load a post with the affected element → verify it displays correctly in Quill → save → verify the API-stored HTML matches the new expected format.
   - **This is the manual GUI step** — it requires a human driving the Quill app. An autonomous session (e.g. a scheduled run) cannot do it: treat the jsdom test suites in step 5 as the automated stand-in, and report this step as not-verified rather than silently skipping it.
   - **Draft posts only:** Quill's credentials point at the production site. Use a brand-new local draft pushed as a draft — never test against an existing post/page, and never publish.

5. Add or update tests in the relevant `Scripts/test-editor*.js` file for the changed behavior, then run `./test.sh` to confirm the full suite (Swift + JS) still passes.
   - **Edit-tool trap:** the Edit tool can corrupt straight ASCII `'` string delimiters into curly Unicode quotes when its `old_string` spans a region containing existing curly quotes, producing `SyntaxError: Invalid or unexpected token`. If that happens, fix it with a targeted Python byte-level replacement — do NOT re-edit with the Edit tool, which re-introduces the corruption (details in the root `CLAUDE.md` test-suite gotchas).

6. Update `Sources/QuillKit/Resources/CLAUDE.md`'s per-element markup reference table (and the root `CLAUDE.md` test-count/status lines, if you added tests) to reflect the new behavior.

7. Run `./build.sh` to confirm the app still builds before considering the update done.
