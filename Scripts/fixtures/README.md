# Round-trip fixtures

Captures of real `post_content` from the live site, used to prove that Quill
reads blocks as WordPress does and that `setContent` → `getContent` is lossless.

`test-block-serializer.js` and `test-block-parser.js` glob every `*.html` here,
so dropping a new capture in adds it to the corpus. Anything that is not a fixture must not end in
`.html`. The `ai/` subdirectory is a separate corpus (see its README); only
`test-block-parser.js` globs it too.

`test-fixture-validity.js` loads, edits and saves every fixture here and fails
if WordPress's validator finds anything wrong with Quill's save that it did not
already find in the fixture. Three fixtures fail that validator on their own and
are covered only by that "nothing new" rule: `accordion-block.html` and
`post-17780.html` hold the older accordion-heading shape (see below), and
`settings-image-custom-link.html` has an `<img>` border style its block comment
does not declare, which no WordPress version tested accepts. It is probably not
an unedited capture.

| File | What it is |
|---|---|
| `accordion-block.html` | A `core/accordion` with two items, from post 17780 |
| `gallery-block.html` | A `core/gallery` with captions |
| `post-17780.html` | A whole published post: classic prose, images, footnotes, two accordions |
| `tabs-block.html` | A `core/tabs` with a tab list and panels |
| `unsupported-blocks.html` | Hand-written, not a site capture: one of each block shape Quill cannot model, so Custom HTML, a shortcode, three self-closing dynamic blocks, a synced pattern, a page break, a read-more, and a third-party block with no `wp-block-` class |
| `settings-paragraph.html` | A `core/paragraph` with `dropCap` |
| `settings-list.html` | A `core/list`, ordered, with `start`, `reversed` and `type: upper-roman` |
| `settings-quote.html` | A `core/quote` in the Plain style, with a `<cite>` |
| `settings-separator.html` | A `core/separator` in the Dots style |
| `settings-table.html` | A `core/table` with a head and foot section, a caption, the Stripes style and `hasFixedLayout: false` |
| `settings-image.html` | A `core/image` linked to the media file in a new tab, with a `title` and the Rounded style |
| `settings-columns.html` | A `core/columns` with `isStackedOnMobile: false`, unequal widths, and one column vertically centred |
| `settings-buttons.html` | A `core/buttons` with a Fill button opening in a new tab and an Outline button |
| `settings-accordion.html` | A `core/accordion` with left icons and a first item `openByDefault` |
| `settings-details.html` | A `core/details` with a `name`, and a panel paragraph carrying a `placeholder` |
| `settings-tabs.html` | A `core/tabs` with two tabs |
| `settings-embed.html` | A responsive YouTube `core/embed`, whose URL holds the `\u0026` escape |

The twelve `settings-*.html` files were captured together from one throwaway
draft on WordPress 7.1 (`block-library.js` of 2026-08-20), which was deleted
afterwards. They are the regression subjects for block-settings preservation.

## These are subjects, not specifications

**A fixture records what one version of WordPress wrote on one day. It is not a
statement about what core emits now, and must never be used as the reference
when implementing a block's `renderHTML`.**

This has already cost a day. Quill's `core/accordion-heading` markup was
modelled on `accordion-block.html`, which came from post 17780 — written by a
WordPress older than the one the site now runs. Current core emits
`has-icon has-icon-right` classes and a `+` icon span, and never emits
`wp-block-heading`. Gutenberg compares class sets, so every accordion Quill
saved came up as "Block contains unexpected or invalid content", and post
17780's own accordions are invalid in current Gutenberg for the same reason.

The authoritative source is the site's own bundled copy of core:

```bash
curl -s https://<site>/wp-includes/js/dist/block-library.js > /tmp/bl.js
# then read the block's save.mjs and block.json (attribute defaults matter —
# accordion-heading's showIcon defaults to true, so save() always emits the icon)
```

Deprecations matter too: a block may accept several past shapes. Grep for
`deprecated_default` near the block to see how many, and check each before
concluding that markup is invalid.

## Why the old markup stays here

These files must keep round-tripping byte-identically — that is the point of
them, and it is what protects already-published posts when they are opened in
Quill. So `accordion-block.html` deliberately still holds the old heading shape.
Do not "fix" it to match current core: that would delete the only regression
test covering posts written by older WordPress versions.

For the same reason, **do not add comments or a header to a fixture file.** The
bytes are the test.

## The WebKit runner

`./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"` runs
every `settings-*.html` here through the real WKWebView — load, save untouched,
save after an edit, and save again for idempotency. The jsdom suites cannot see
a WebKit/jsdom divergence, and the inline-style bug that motivated this runner
was green in jsdom while invalidating every coloured block in WordPress.
