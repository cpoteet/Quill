# Round-trip fixtures

Captures of real `post_content` from the live site, used to prove parse →
serialize and `setContent` → `getContent` are lossless.

`test-block-serializer.js` globs every `*.html` here, so dropping a new capture
in adds it to the corpus. Anything that is not a fixture must not end in
`.html`.

| File | What it is |
|---|---|
| `accordion-block.html` | A `core/accordion` with two items, from post 17780 |
| `gallery-block.html` | A `core/gallery` with captions |
| `post-17780.html` | A whole published post: classic prose, images, footnotes, two accordions |
| `tabs-block.html` | A `core/tabs` with a tab list and panels |
| `unsupported-blocks.html` | Hand-written, not a site capture: one of each block shape Quill cannot model, so Custom HTML, a shortcode, three self-closing dynamic blocks, a synced pattern, a page break, a read-more, and a third-party block with no `wp-block-` class |

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
