# WordPress release markup audit

The routine Quill runs against each new WordPress major release to confirm its Gutenberg HTML round-trip is still correct. Written up on 2026-08-19 immediately after the WP 7.1 run, so the next release (7.2) can repeat it without rebuilding the procedure.

Related: the `update-gutenberg-html-format` skill (how to *fix* a format change), `docs/future-architecture.md` Approach H (how to *automate* detection), `Sources/QuillKit/Resources/CLAUDE.md` (the per-element markup reference table this audit checks).

---

## When to run it

Once per WordPress major release, roughly three times a year. Run it on release day or shortly after — not before, because pre-release changelogs describe intent, and only the shipped `save()` code is evidence.

The 7.1 audit was set up as two one-time scheduled tasks:

| Task | Timing | Job |
|---|---|---|
| `wp-7-X-audit-preflight-reminder` | ~3 hours before the audit | Check the Studio site, tell the user what they must do by hand |
| `wordpress-7-X-markup-audit` | Release day | The audit itself |

Both prompts are preserved in `/Users/Chris/.claude/scheduled-tasks/`. Copy them, change the version number and the dates, and re-arm.

---

## Pre-flight — user-only steps

An audit session cannot do these. It cannot launch an app, and it must never log into wp-admin.

1. Launch the Studio app so the scratch WordPress site is running.
2. Update that site to the new WordPress version (wp-admin → Dashboard → Updates).
3. Leave Studio running through the audit.
4. If Studio assigns a port other than 8881, update the port in `local-studio-credentials.json` and in the audit prompt.

Verify with:

```bash
curl -s -m 5 http://localhost:8881/ | grep -io '<meta name="generator"[^>]*>'
```

Three outcomes, and they have different fixes. No response means Studio is not running. A 7.0.x/older version means Studio runs but the site is not updated. The new version means full ground-truth mode.

The audit still runs without the local site — it falls back to Gutenberg's GitHub fixtures — but the evidence is weaker. Never skip the audit because the site is down.

---

## Ground-truth sources, in the order that worked

The 7.1 run found a better source than the one the skill documents. Use this order.

1. **Core's own shipped `save()` source, read from the live Studio install.** `/wp-includes/js/dist/block-library.js` — the unminified build, about 3 MB. This is the exact code that install runs, so it beats the GitHub fixtures, which need a tag-to-release mapping you have to guess at. The Studio install path is **`/Users/Chris/Dev/Studio/`**. Confirm it before reading anything: `/Users/Chris/Studio/codex/` is a *different, older* checkout that still sits at 7.0, and reading it silently yields wrong answers. Verify with `grep wp_version /Users/Chris/Dev/Studio/wp-includes/version.php`, or locate the tree that owns a known upload under `wp-content/uploads/`.
2. **The live REST API for attribute schemas.** `GET /wp-json/wp/v2/block-types` lists every *server-registered* block. This is how the 7.1 run caught that Table of Contents ships `save()` code but is not registered — `/wp-json/wp/v2/block-types/core/table-of-contents` returned 404.
3. **WordPress's own PHP parser, for validating markup you assemble by hand.** PHP is available on this machine. Running candidate markup through the install's `WP_Block_Parser` proves the block tree parses correctly with no stray freeform text. The 7.1 run used this to validate the Tabs snippet.
4. **Quill's real `editor.html` in jsdom, to replay the markup.** Load the real markup, save it back, and compare. This is what turns "WordPress emits X" into "Quill does or does not survive X".
5. **Gutenberg's GitHub fixtures**, `packages/block-library/src/*/test/fixtures/*.html`, as the fallback when no live install is available.

**Weak source, know the limit:** creating a post over the REST API stores exactly what you send. It does not run Gutenberg's client-side serialization, so `content.raw` comes back byte-identical to what you posted. That proves storage fidelity only, never how the editor serializes.

**Credentials:** `/Users/Chris/.claude/scheduled-tasks/wordpress-7-1-markup-audit/local-studio-credentials.json` (chmod 600) holds the Studio site URL, username, and application password. Never print the password value in a report.

---

## Safety rules

- **Never touch the production site.** Quill's configured credentials point at the user's real WordPress site. If a test genuinely needs Quill talking to WordPress, use a brand-new local draft, push it as a draft, name it obviously, and never publish. The 7.1 run needed none of this.
- **Never log into wp-admin.** Application passwords do not work on the login form, and entering passwords into forms is off-limits. Use an existing authenticated browser session or skip the browser path.
- Scratch content on the Studio site is unrestricted. That site exists for this.

---

## Steps

1. Read the root `CLAUDE.md` and `Sources/QuillKit/Resources/CLAUDE.md` before touching project code. They carry the test-suite gotchas and the Edit-tool curly-quote warning that bites `Scripts/test-editor*.js`.
2. Confirm the release actually shipped. `api.wordpress.org/core/stable-check` is authoritative; the wordpress.org/news post can lag by hours.
3. Confirm the Studio site's version, then read the shipped `save()` source for every block on the checklist.
4. For each change that alters saved `post_content`, replay the real markup through `editor.html` in jsdom and see what Quill does to it.
5. Fix anything that loses data, following the `update-gutenberg-html-format` skill.
6. Move the reference block parser to WordPress's latest release and re-run the comparison: in `Scripts/`, run `npm install --save-dev --save-exact @wordpress/block-serialization-default-parser@latest`, then `node --test Scripts/test-block-parser.js`. A failure means WordPress changed how it reads block comments, and the failing input shows where; fix `block-parser.js` to match.
7. Add tests to the relevant `Scripts/test-editor*.js`, then run `./test.sh` — all Swift and JS suites must pass.
8. Update the per-element table in `Sources/QuillKit/Resources/CLAUDE.md` and the test-count lines in the root `CLAUDE.md`.
9. Run `./build.sh`.
10. Check `docs/future-architecture.md` and `docs/gutenberg-block-snippets.md` for claims the change just made false. The 7.1 run had to correct both.
11. Commit to main. Report what was verified live versus inferred, and say plainly when nothing needed changing.

---

## The checklist to build

For each release, list the changes the release notes claim, then verify each one against shipped code. Sort every item into one of three results: no saved-markup change, editor-side capability only, or a real markup change. Only the third needs Quill work.

Always include these standing items, whatever the release notes say:

- **Every new block.** Confirm its `wp-block-*` class and its root element. A `div` root is caught by `gutenbergPassthrough` automatically. **A `<figure>` root needs checking against `QUILL_MODELED_FIGURE_CLASSES`** — this is where 7.1 broke.
- **The blocks Quill models natively** — heading, list, quote, code, separator, image, gallery, table, embed. Confirm their `save()` output is unchanged. `core/footnotes` has no `save()` at all: check instead that its meta key, marker anchor and server-rendered list still match `docs/footnotes-meta.md`.
- **New attributes on existing blocks.** An attribute that lives only in the block-comment JSON is harmless. An attribute that reaches the HTML is not.

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
grep -o 'is-style-[a-z-]*' /tmp/block-library.js | sort -u
```

---

## Record: WordPress 7.1, audited 2026-08-19

Ran a day early, on release day. Studio site was on 7.1, so this was full ground-truth mode. Commits `f552d07`, `c182896`, `a4342d2`.

### Findings

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

### What changed in Quill

**1. Figure-rooted blocks were being destroyed** — much bigger than the Playlist block that exposed it. `gutenbergPassthrough`'s rule was `[class*="wp-block-"]:not(figure)`, on the assumption Quill's own rules covered every `wp-block-*` figure. Only four do. Verified in jsdom: `wp-block-audio` collapsed to a caption-only `<p>`, `wp-block-video` to an empty `<p>`, `wp-block-pullquote` was rewritten as a quote block, and `wp-block-playlist` lost its wrapper, comments and figcaption. Audio, video and pullquote had been broken for a long time. Fixed with a second figure-only parse rule that defers to `QUILL_MODELED_FIGURE_CLASSES` (image, gallery, embed, table) and otherwise preserves the figure byte-for-byte.

**2. Decorative images lost `role="none"`** — `ResizableImage` did not model `role`, so the accessibility semantic vanished on the first save after any visual edit. Added an `imgRole` attribute that round-trips it under both the figure rule and the bare `img[src]` fallback.

**3. HEIC uploads produced unusable attachments** — found on a follow-up pass over the client-side media processing post, after the markup audit had closed.

The upload endpoint gained `generate_sub_sizes`, `convert_format` and `url` parameters, plus `/sideload` and `/finalize` routes. All of it is opt-in and browser-driven. Both new booleans default to `true`, so Quill's plain `POST /wp/v2/media` keeps the old server-side behavior. Verified by uploading a JPEG in Quill's exact request shape: six sizes generated, `missing_image_sizes` empty. **Quill should not send any of the three parameters.** `generate_sub_sizes: false` promises sub-sizes Quill does not produce, `convert_format: false` overrides the site owner's own WebP setting, and `url` has no caller — every Quill upload passes a local file.

The damage was elsewhere. 7.1 added an exemption letting still HEIC/HEIF past the unsupported-mime gate, assuming the *browser* converts them first. 7.0 rejected HEIC cleanly with `rest_upload_image_type_not_supported`. Quill is not a browser, so nothing converted the file: the attachment stored with `width=NULL`, `height=NULL` and no sizes. Quill then inserted the raw `.heic` into the post, which most browsers cannot display. Quill accepts HEIC explicitly — `DroppableWebView` lists `public.heic`, and the pickers use `UTType.image`.

Fixed with `Sources/QuillKit/API/ImageConversion.swift`: HEIC/HEIF convert to JPEG locally via ImageIO before upload, carrying EXIF orientation across so WordPress still rotates correctly. Any failure falls back to uploading the original, which is the pre-fix behavior. The three upload call sites (`uploadPickedImage`, `PostEditorView.handleDroppedImages`, `MediaSidebarSection.uploadFromDisk`) call it and clean up the temp file in a `defer`. The editor drop path adds a "Converted to JPEG" toast; the picker and sidebar have no toast system, only an error alert, so they stay silent.

Verified end to end against the live 7.1 site: the same source HEIC went from `width=NULL, sizes=NONE` to `1600x1000` with five sub-sizes.

Verification: 13 new JS tests for the markup fixes, 11 new Swift tests for the conversion, full suite 349 Swift + 282 JS passing, `./build.sh` succeeded.

### Open items to carry into the next audit

- **Server-rendered blocks are still lost.** `core/icon`, `core/breadcrumbs`, `core/latest-posts` and similar save as a self-closing `<!-- wp:icon {...} /-->` comment with no HTML element. Tiptap drops comment nodes on parse, so they disappear after a visual edit. Pre-existing since WP 5.0, not a 7.1 regression. Fixing it means modeling comment-only blocks — a design change, not an audit fix.
- **The Shortcode block is still untested.** It serializes as bare text with no wrapping element, so passthrough may have nothing to catch. Noted in `docs/gutenberg-block-snippets.md`.
- **Table of Contents may ship in a later release.** It is `nav`-rooted, so passthrough should handle it, but confirm when it registers.
- **Any new figure-rooted block is the high-risk case.** Check it first.
- **Audit the upload path, not just the markup.** The 7.1 HEIC break shipped no markup change at all, so a fixture diff would have missed it entirely. Add a standing step: upload a JPEG and a HEIC in Quill's exact request shape, then read the stored attachment metadata with PHP. Check `width`, `height` and `sizes` are populated. Watch for core relaxing a rule on the assumption that a browser does the work — that assumption is exactly where a native client falls through.
- **Other formats may break the same way.** Only HEIC/HEIF convert today. TIFF and similar depend on the host's image editor, so a site with a thin GD build can still store an unusable attachment. Re-check if users report it.

---

## Replicating for WordPress 7.2

1. Find the release date. Do not assume — check the WordPress release schedule.
2. Copy the two task prompts from `/Users/Chris/.claude/scheduled-tasks/wordpress-7-1-markup-audit/` and `.../wp-7-1-audit-preflight-reminder/`, renaming for 7.2.
3. In the audit prompt, replace the version numbers, the release date, and the "What to check" list with 7.2's announced changes. Keep the standing items above.
4. Point the credentials line at whichever path the 7.1 credentials file ends up at — it currently sits inside the 7.1 task directory.
5. Update the ground-truth section to lead with the shipped `block-library.js` source, which is what this doc now records and the older task prompt did not.
6. Arm both tasks: the reminder about three hours ahead, the audit on release day.

If Approach H (the fixture-diff harness in `docs/future-architecture.md`) gets built first, most of this collapses into bumping a version tag and reading a test diff. The audit routine stays useful for the parts a fixture diff cannot see — new blocks, root-element changes, and editor-only capabilities.
