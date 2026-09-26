# WordPress release checklist

Run this once per WordPress major release (about three times a year), on release day or soon after — not before: release notes describe intent, and only the shipped code is evidence. It confirms that Quill still reads and writes every block the way the new release does.

To fix one block's markup once this checklist finds a change, use the `update-gutenberg-html-format` skill.

---

## Before you start (you, not Claude)

A Claude session cannot launch apps and must never sign into wp-admin, so these are yours:

- [ ] Launch Studio, and update the scratch site to the new WordPress version (wp-admin → Dashboard → Updates). Leave Studio running. If Studio picks a port other than 8881, update it in `local-studio-credentials.json` and in the scheduled audit prompt.
- [ ] Export the production site: wp-admin → **Tools → Export → All content**, saved to the Desktop. Step 6 reads it; delete it when the checklist is done.
- [ ] Make sure Quill is connected to the Studio site, not production. The in-app step writes drafts.

Check the Studio site is up and on the new version:

```bash
curl -s -m 5 http://localhost:8881/ | grep -io '<meta name="generator"[^>]*>'
```

No response means Studio is not running; an older version means the site was not updated. The checklist still runs without Studio, falling back to Gutenberg's GitHub fixtures, but the evidence is weaker and steps 6 and 13 lose their PHP and in-app halves. Never skip the release because the site is down.

---

## The checklist

Work top to bottom. Each step says what passes.

### Confirm the release

- [ ] **1. The release shipped.** `api.wordpress.org/core/stable-check` is authoritative; the wordpress.org news post can lag by hours.
- [ ] **2. Studio runs it.** `grep wp_version /Users/Chris/Dev/Studio/wp-includes/version.php` prints the new version. Read nothing from `/Users/Chris/Studio/codex/` — it is an older checkout and silently gives wrong answers.

### Move the test references to the new release

The comparison and validator suites run WordPress's own packages as test-only references. They must match the release, not npm's latest, which runs ahead of WordPress.

- [ ] **3. Find the package versions the release ships.** WordPress builds from a pinned Gutenberg commit:

  ```bash
  V=7.2.0   # the new release
  SHA=$(curl -s https://raw.githubusercontent.com/WordPress/wordpress-develop/$V/package.json | python3 -c "import sys,json; print(json.load(sys.stdin)['gutenberg']['sha'])")
  for p in block-serialization-default-parser blocks block-library block-editor; do
    echo "$p $(curl -s https://raw.githubusercontent.com/WordPress/gutenberg/$SHA/packages/$p/package.json | python3 -c "import sys,json; print(json.load(sys.stdin)['version'])")"
  done
  ```

- [ ] **4. Pin them.** In `Scripts/`, run `npm install --save-dev --save-exact` with those four versions (`@wordpress/block-serialization-default-parser@…`, `@wordpress/blocks@…`, `@wordpress/block-library@…`, and `@wordpress/block-editor@…` only if it is listed), then set the same `blocks` and `block-editor` versions in the `overrides` block of `Scripts/package.json`.

### Check that Quill reads blocks as WordPress does

- [ ] **5. Parser comparison.** `node --test Scripts/test-block-parser.js` passes. A failure means WordPress changed how it reads block comments; the failing input shows where. Fix `block-parser.js` from the measured output — never by reading WordPress's parser source, which is GPL.
- [ ] **6. Your whole site, through both of WordPress's parsers.**

  ```bash
  node Scripts/compare-export.js ~/Desktop/<export>.xml /Users/Chris/Dev/Studio
  ```

  Exit 0 and `✓ Quill reads every item exactly as WordPress does` passes. Exit 1 lists each item that differs, and says when WordPress's own JavaScript and PHP parsers disagree with each other on it (a no-break space or U+2028 inside a block comment is the known case). Exit 3 means the PHP comparison did not run — fix that before moving on. Delete the export afterwards.
- [ ] **7. Full suite.** `./test.sh` passes. With the new packages pinned, the fixture-validity and AI-output suites now check Quill's saves against the new release's block validator.

### Check what the release changed

- [ ] **8. List every claimed change** from the release post and the dev notes, then check each against the shipped code and sort it into one of three results: no saved-markup change, editor-side capability only, or a real markup change. Only the third needs Quill work. Read `/Users/Chris/Dev/Studio/wp-includes/js/dist/block-library.js` for what each block's `save()` writes — to learn the format only; never copy its code into Quill.
- [ ] **9. Standing items, whatever the notes say:**
  - **New blocks.** A new block at the top level of a post is preserved byte for byte automatically. The risk is a new block *nested inside* a block Quill models: a `div` root goes to `gutenbergPassthrough`, but a `<figure>` root must not be in `QUILL_MODELED_FIGURE_CLASSES` (`editor-transforms.js`). WordPress 7.1's Playlist broke exactly here.
  - **Blocks Quill models** — every name `modelsBlockName` in `block-descriptors.js` accepts: their `save()` output is unchanged. `core/footnotes` has no `save()`; check its meta key, marker anchor and server-rendered list against `docs/footnotes-meta.md`.
  - **Block settings** — re-verify the table below against `block-library.js`. A changed class name or default is silent data loss.
  - **New attributes on existing blocks** — an attribute that lives only in the block comment is carried automatically. One that draws a child element, or changes a class the node computes itself, needs work.
- [ ] **10. The upload path.** Upload a JPEG and a HEIC through Quill to the Studio site, then read each attachment's stored metadata with PHP: `width`, `height` and `sizes` are populated. The 7.1 HEIC break changed no markup at all, so only this step would have caught it. Watch for core relaxing a rule on the assumption that a browser does the work.
- [ ] **11. Each real markup change:** replay the real markup through `editor.html` in jsdom, then fix it with the `update-gutenberg-html-format` skill, which covers the tests.

### Finish

- [ ] **12. Real WebKit.** `./build.sh`, then `./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"` reports every fixture passing.
- [ ] **13. In the app.** On a new local draft (never a published post), paste markup for each changed block through code view, edit a paragraph, Save Draft, and read the saved HTML from SQLite (see the `docs/gotchas.md` entry "Verify saved draft HTML straight from SQLite"). Discard the draft.
- [ ] **14. Docs.** Update the per-element table in `Sources/QuillKit/Resources/CLAUDE.md`, the test counts in the root `CLAUDE.md` and `docs/testing-plan.md`, and anything in `docs/future-architecture.md` the release made false.
- [ ] **15. Record the run** under **Past runs** below: date, what was verified live versus inferred, findings, what changed in Quill, and open items. Say plainly when nothing needed changing.
- [ ] **16. Commit**, once the user says so.

---

## Evidence, strongest first

1. **The shipped `block-library.js` in the Studio install** — the exact code that WordPress version runs, about 3 MB unminified. Better than GitHub fixtures, which need a tag-to-release mapping.
2. **The live REST API for attribute schemas.** `GET /wp-json/wp/v2/block-types` lists every server-registered block. The 7.1 run caught that Table of Contents shipped `save()` code but was not registered (`/wp-json/wp/v2/block-types/core/table-of-contents` returned 404).
3. **WordPress's PHP parser, for markup you assemble by hand.** `echo '["<markup>"]' | php Scripts/php-block-parser.php /Users/Chris/Dev/Studio` runs the install's `WP_Block_Parser` over a JSON array of strings; a clean tree with no stray freeform text proves the markup parses.
4. **Quill's real `editor.html` in jsdom**, to turn "WordPress writes X" into "Quill does or does not survive X".
5. **Gutenberg's GitHub fixtures**, `packages/block-library/src/*/test/fixtures/*.html`, when no live install is available.

**Weak evidence:** a post created over the REST API stores exactly what you send and never runs the editor's serializer, so it proves storage only.

**Credentials:** `/Users/Chris/.claude/scheduled-tasks/wordpress-7-1-markup-audit/local-studio-credentials.json` (chmod 600) holds the Studio URL, username and application password. Never print the password.

## Safety rules

- **Never touch production.** Quill must be connected to the Studio site. Test only on new local drafts, never publish.
- **Never sign into wp-admin.** Application passwords do not work on the login form, and entering passwords into forms is off-limits.
- Scratch content on the Studio site is unrestricted; the site exists for this.

## Scheduling

The 7.1 run used two one-time scheduled tasks, both kept in `/Users/Chris/.claude/scheduled-tasks/`: `wp-7-1-audit-preflight-reminder` (about three hours before, to check Studio and tell the user what to do by hand) and `wordpress-7-1-markup-audit` (release day). For the next release, copy both, rename them, change the version, the date and the "what to check" list, point the audit prompt at this checklist, and move the credentials file somewhere version-neutral. Only the 7.1 tasks exist today.

---

## Block settings

Every setting Quill redraws or offers a control for is one entry in
`Sources/QuillKit/Resources/block-settings.js`. Re-verify this table against the
site's own `block-library.js` each major release: a changed class name or
default here is silent data loss, not a crash. This is the drift the ordered-list
numbering error was a worked example of.

| Block | Setting | What core draws | Where Quill puts it |
|---|---|---|---|
| `core/accordion` | `showIcon`, `iconPosition` | nothing — its `save()` ignores both | carried in the comment; the control propagates to every heading |
| `core/accordion-heading` | `showIcon`, `iconPosition` | `has-icon`, `has-icon-left`/`has-icon-right`, and the `__toggle-icon` span before or after the title | redrawn by `accordionHeading.renderHTML` |
| `core/accordion-item` | `openByDefault` | `is-open` on the item div | `flagClass` |
| `core/tabs` | `activeTabIndex` | nothing | carried; the control sits on the panel |
| `core/button` | `className` | the style class on the button div | carried |
| `core/button` | `linkTarget`, `rel` | `target`/`rel` on the `<a>` — `source: "attribute"`, so never in the comment | markup only; `rel` is `noopener` alone |
| `core/quote`, `core/separator`, `core/image`, `core/table` | `className` | the style class on the block's root element | carried |
| `core/table` | `caption` | a `figcaption.wp-element-caption` in the figure — `source: "rich-text"`, so never in the comment | markup only |

**An attribute no entry names is carried automatically.** Every block node
snapshots its element's attributes on load and replays them on save, in the
source's own order, so a release only needs auditing for settings that draw a
**child element** (the accordion's icon span is the one Quill models today) or
that change a class the node itself computes. A new attribute on an existing
block — core's next `is-something-on-mobile`, a new `name`-style sourced
attribute — needs no work at all. The exceptions are listed in
`RAW_ATTRS_MODELED` and `RAW_ATTRS_EXEMPT` in `editor.html`; a setting that
draws a class on a node has to appear in the first.

Two things the registry deliberately cannot express, because they are document
structure rather than a setting on an element: a table's `<thead>`/`<tfoot>`
sections (`tableRow.rowType`, regrouped in the save transform) and the table
caption's attachment to its figure.

Verify the style slugs in one command:

```bash
grep -o 'is-style-[a-z-]*' /Users/Chris/Dev/Studio/wp-includes/js/dist/block-library.js | sort -u
```

---

## Open items

- **Table of Contents may register in a later release.** It is `nav`-rooted, so it is preserved either way; confirm when it registers.
- **Formats other than HEIC may break uploads the same way.** Only HEIC/HEIF convert to JPEG. TIFF and similar depend on the host's image editor. Re-check if users report it.
- **The test packages were ahead of 7.1.2** (checked 2026-09-26): `block-library` 10.4.0 against the 10.2.0 WordPress 7.1.2 ships, `blocks` 15.27.0 against 15.24.0, `block-serialization-default-parser` 5.55.0 against 5.51.0. Steps 3–4 align them on the next run.

Closed since the 7.1 run: self-closing server-rendered blocks (`core/icon`, `core/latest-posts`) and the Shortcode block are preserved byte for byte by unsupported-block preservation (2026-09-12) and covered by `Scripts/fixtures/unsupported-blocks.html`.

---

## Past runs

### WordPress 7.1, audited 2026-08-19

Ran a day early, on release day. Studio site was on 7.1, so this was full ground-truth mode. Commits `f552d07`, `c182896`, `a4342d2`.

#### Findings

| Item | Result |
|---|---|
| Gallery lightbox refinements | No saved-markup change. New attributes live in the block-comment JSON only. |
| Image "mark as decorative" | **Real markup change.** New `isDecorative` attribute emits `role="none"` on the `<img>`. Quill dropped it. Fixed. |
| Embed shortcode-to-block transform | Editor-side only. `save()` output unchanged. |
| New blocks — Tabs, Playlist, Accordion, Math | Shipped. Tabs/Accordion/Math are `div`-rooted and passthrough handled them. **Playlist is `<figure>`-rooted and was destroyed.** Fixed. |
| New block — Table of Contents | Did **not** ship as a registered block. `save()` is in the JS bundle but the REST endpoint 404s. |
| Custom HTML inner blocks | Editor capability only. No markup change. |
| `wp-elements-*` collision fix | No effect on block output. The class map is still singular and unchanged. |
| Classic block deprecation | Inserter-only. `core/freeform` still registered; the `wp-block-` gate in `WPPost` unaffected. |
| Heading, list, quote, code, separator, table, embed, preformatted | All unchanged. |
| Client-side media processing | **Real behavior change for uploads.** No saved-markup change. Broke HEIC uploads for non-browser clients. Fixed. See below. |

#### What changed in Quill

**1. Figure-rooted blocks were being destroyed** — much bigger than the Playlist block that exposed it. `gutenbergPassthrough`'s rule was `[class*="wp-block-"]:not(figure)`, on the assumption Quill's own rules covered every `wp-block-*` figure. Only four do. Verified in jsdom: `wp-block-audio` collapsed to a caption-only `<p>`, `wp-block-video` to an empty `<p>`, `wp-block-pullquote` was rewritten as a quote block, and `wp-block-playlist` lost its wrapper, comments and figcaption. Audio, video and pullquote had been broken for a long time. Fixed with a second figure-only parse rule that defers to `QUILL_MODELED_FIGURE_CLASSES` (image, gallery, embed, table) and otherwise preserves the figure byte-for-byte.

**2. Decorative images lost `role="none"`** — `ResizableImage` did not model `role`, so the accessibility semantic vanished on the first save after any visual edit. Added an `imgRole` attribute that round-trips it under both the figure rule and the bare `img[src]` fallback.

**3. HEIC uploads produced unusable attachments** — found on a follow-up pass over the client-side media processing post, after the markup audit had closed.

The upload endpoint gained `generate_sub_sizes`, `convert_format` and `url` parameters, plus `/sideload` and `/finalize` routes. All of it is opt-in and browser-driven. Both new booleans default to `true`, so Quill's plain `POST /wp/v2/media` keeps the old server-side behavior. Verified by uploading a JPEG in Quill's exact request shape: six sizes generated, `missing_image_sizes` empty. **Quill should not send any of the three parameters.** `generate_sub_sizes: false` promises sub-sizes Quill does not produce, `convert_format: false` overrides the site owner's own WebP setting, and `url` has no caller — every Quill upload passes a local file.

The damage was elsewhere. 7.1 added an exemption letting still HEIC/HEIF past the unsupported-mime gate, assuming the *browser* converts them first. 7.0 rejected HEIC cleanly with `rest_upload_image_type_not_supported`. Quill is not a browser, so nothing converted the file: the attachment stored with `width=NULL`, `height=NULL` and no sizes. Quill then inserted the raw `.heic` into the post, which most browsers cannot display. Quill accepts HEIC explicitly — `DroppableWebView` lists `public.heic`, and the pickers use `UTType.image`.

Fixed with `Sources/QuillKit/API/ImageConversion.swift`: HEIC/HEIF convert to JPEG locally via ImageIO before upload, carrying EXIF orientation across so WordPress still rotates correctly. Any failure falls back to uploading the original, which is the pre-fix behavior. The three upload call sites (`uploadPickedImage`, `PostEditorView.handleDroppedImages`, `MediaSidebarSection.uploadFromDisk`) call it and clean up the temp file in a `defer`. The editor drop path adds a "Converted to JPEG" toast; the picker and sidebar have no toast system, only an error alert, so they stay silent.

Verified end to end against the live 7.1 site: the same source HEIC went from `width=NULL, sizes=NONE` to `1600x1000` with five sub-sizes.

Verification: 13 new JS tests for the markup fixes, 11 new Swift tests for the conversion, full suite 349 Swift + 282 JS passing, `./build.sh` succeeded.
