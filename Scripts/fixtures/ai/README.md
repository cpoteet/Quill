# AI output fixtures

Hand-written stand-ins for what Claude sends back, used by
`Scripts/test-ai-output-validity.js` to prove that AI content saves as markup
WordPress's own block validator accepts.

Each case is a pair:

| File | What it is |
|---|---|
| `<name>.raw.txt` | Claude's reply as the API returns it, including the quirks Quill cleans up (code fences, the web-search preamble, citation tags, inline table styles) |
| `<name>.html` | What Swift hands the editor after cleanup |

`generate-*` cases go through `AIPromptBuilder.parseGenerateResponse` (the
Generate Post sheet); `operation-*` cases go through
`AIPromptBuilder.cleanOperationResult` (the right-click rewrites).
`AIOutputFixtureTests.swift` fails if a `.html` stops matching its `.raw.txt`, so
edit the raw reply first and then regenerate its partner. The JS suite never
reads the `.raw.txt` files.

When Claude returns markup the corpus does not cover, add it to the raw reply
of the closest case, update the `.html`, and run `./test.sh`.

## The validator

`Scripts/wp-validator.js` loads `@wordpress/block-library` and
`@wordpress/blocks` from `Scripts/node_modules` (test-only, about 1.0 GB, never
bundled into Quill.app). This suite and `test-fixture-validity.js` both use it.
Each saved post is checked three ways: no block is invalid, no content falls
outside a block, and `serialize(parse(saved))` returns the same bytes.

The versions are pinned exactly in `Scripts/package.json`, and its `overrides`
force a single copy of `@wordpress/blocks` and `@wordpress/block-editor`.
Without them npm installs two copies of the block editor, both register the
custom-class hook, and every custom class is saved several times over
(`class="lead lead lead"`), which fails any block that has one. After changing
the pins, delete `node_modules` and `package-lock.json` before `npm install`,
or the lock file keeps the old duplicates.

npm has no `wp-7.1` dist-tag. 10.3.0, 10.4.0, 10.5.0 and 11.0.0 all gave
identical results against the `settings-*` fixtures (2026-09-16), so the pin
(`block-library` 10.4.0, the last release before the site's bundled
`block-library.js` of 2026-08-20) matters less than it looks. Bump it when the
site moves to a new WordPress release.

Two differences from a real block editor, neither of which makes a block
invalid: the test copy orders support attributes differently (`fontSize` before
`style`), and it drops a `null` attribute the live editor keeps. Both only show
up in the byte-for-byte re-save check, which is why the fixture sweep applies
that check only to fixtures that already pass it.
