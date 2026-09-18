# Block settings preservation — design

Date: 2026-09-13
Status: approved; stage 1 implemented 2026-09-13, stages 2 and 3 outstanding
Scope: phase 1 of two. This phase stops Quill from losing block settings. Adding
UI controls for those settings is phase 2 and is deliberately out of scope here.

## Problem

Quill silently discards Gutenberg block settings on posts it edits. The loss
happens on the first visual edit to any post containing them — the user never
touches the setting, and nothing warns them.

There are three distinct failure modes.

### 1. Comment-only attributes are dropped on every non-container block

`withBlockAttrs` — the carrier that preserves a block's `<!-- wp:x {…} -->`
attributes across an edit — is applied to the sixteen container nodes only.
Paragraph, list, quote, table, separator, image, gallery and embed do not have
it, so any attribute that lives only in the delimiter is deleted.

Verified by round-tripping through the live editor:

| Loaded | Saved after one edit |
| --- | --- |
| `wp:paragraph {"dropCap":true}` | `wp:paragraph` |
| `wp:list {"ordered":true,"start":5,"reversed":true,"type":"upper-roman"}` | `wp:list {"ordered":true}` |
| `wp:table {"hasFixedLayout":false,"className":"is-style-stripes"}` | `wp:table` |
| `wp:separator {"className":"is-style-dots"}` | `wp:separator` |
| `wp:image {…,"lightbox":{"enabled":true},"className":"is-style-rounded"}` | `wp:image {"id":9,"sizeSlug":"large"}` |

This removes every block style (`is-style-outline`, `-stripes`, `-dots`,
`-plain`, `-rounded`), lightbox, list numbering and fixed table layout.

### 2. Container nodes render a fixed class list

Each container's `renderHTML` emits a hardcoded attribute object, so the markup
Gutenberg derives from an attribute is stripped even when the attribute itself
survives in the comment. The result is a comment that disagrees with the HTML,
which is what makes the block editor report "this block contains unexpected or
invalid content", and what makes the front end lose the styling.

| Attribute kept in the comment | Markup Quill deletes |
| --- | --- |
| `columns.verticalAlignment` / `isStackedOnMobile` | `are-vertically-aligned-center is-not-stacked-on-mobile` |
| `column.width` | `style="flex-basis:33.33%"` |
| `accordion-item.openByDefault` | `is-open` |
| `details.name` | `name="faq"` |
| `button.className` | `is-style-outline` |

### 3. Outright content destruction

- A button's `target="_blank"` and `rel` are deleted from the HTML and never
  reach the comment. A link set to open in a new tab silently stops doing so.
- A table's `<tfoot>` row is merged into `<tbody>`.
- A table's `<figcaption>` is torn out of the figure and left behind in the
  document as a loose `core/paragraph` block.
- A table cell's `scope` and `data-align` attributes are dropped.
- An ordered list's numbering style is re-emitted as `type="upper-roman"`.
  Gutenberg saves it as `style="list-style-type:upper-roman"`, so Quill's output
  is a form WordPress will not accept.

## Approach

Three mechanisms exist today and are applied inconsistently:

| Mechanism | Behaviour | Applied to |
| --- | --- | --- |
| `withClassAttr` | keeps `class`/`id` verbatim | core nodes |
| `withBlockAttrs` | keeps the delimiter JSON verbatim | container nodes |
| `descriptor.attrsFrom` + `ownedAttrs` | derives comment keys from rendered markup | a few keys |

The chosen approach inverts the third. **The Tiptap node attribute becomes the
single source of truth; both the markup and the comment JSON are generated from
it.** For each modeled setting:

- a Tiptap attribute whose `parseHTML` reads the delimiter comment first and the
  rendered markup only as a fallback — the comment is Gutenberg's own source of
  truth and the markup is merely its output;
- a `renderHTML` that regenerates exactly what Gutenberg's `save()` emits;
- an `attrsFrom` entry writing the value back into the comment, with the key
  listed in `ownedAttrs` so a stale carried value cannot resurrect it.

`withBlockAttrs` is retained and applied to **every** node rather than only
containers. It is the floor for everything nobody modeled: `lightbox`,
`activeTabIndex`, `templateLock`, `layout`, third-party attributes, and whatever
a future WordPress release adds.

### The dividing line

> Any attribute that generates markup must be modeled. Anything that generates
> none stays with the carrier.

A half-modeled attribute is worse than an unmodeled one: if `textAlign` survives
in the comment but its `has-text-align-center` class is not regenerated, the
result is the very mismatch this phase exists to remove. The inventory below is
therefore determined by whether `save()` emits anything, not by whether the
setting is interesting. Some settings are modeled purely for preservation and
will never get a control.

### `className` is modeled once, globally

Every block style a user would want — Outline, Stripes, Dots, Plain, Rounded —
lives in `className`, and `useBlockProps.save()` splices it into the rendered
class list for every block. It becomes one shared attribute rather than fifteen.

`className` parses from **the comment only**. Deriving it from the rendered
class list would require Quill to know each block's generated-class vocabulary
well enough to subtract it, and getting that wrong either duplicates a class or
deletes the user's own. A block Quill created itself simply has no `className`.

### Cost, accepted knowingly

This puts roughly fifteen blocks' class-generation rules inside Quill, and they
are WordPress's rules rather than Quill's. `docs/wordpress-release-audit.md`
gains a section to re-verify them each release. The ordered-list numbering error
above is exactly the drift that section exists to catch.

### `ownedAttrs` changes meaning

Today it means "only declare a key the node genuinely round-trips", which is why
`columnBlock` disowns `width`. Under this design every modeled key round-trips,
so `ownedAttrs` becomes the full modeled set for each block. The explanatory
comment at the top of `block-descriptors.js` must be rewritten to match.

## Inventory

### Verified against installed core, 2026-09-13

The inventory below was drafted against GitHub trunk and has since been checked
against the site's own WordPress 7.1 bundle. Two corrections stand:

**Sourced attributes get markup and no comment key.** `block.json` marks many
attributes `source: "attribute" | "rich-text" | "query"`; Gutenberg reads those
back out of the saved HTML and omits them from the delimiter. So button `url` /
`title` / `linkTarget` / `rel`, image `title` / `href` / `rel` / `linkClass` /
`linkTarget`, details `name`, tab-list `tabs` and table `caption` / `head` /
`body` / `foot` are modeled in `renderHTML` only — no `attrsFrom`, no
`ownedAttrs`. Writing one into the comment would diverge from core's own output
and break fixture byte-identity.

**Four settings need no modeling at all.** Where a core node's setting is a
class, `withClassAttr` keeps the class and the carrier keeps the comment, so
paragraph `dropCap`, quote `textAlign` and separator `opacity` round-trip for
free once the carrier is applied everywhere. Table `hasFixedLayout` looks like
the same case but is not: the carrier lands on the `<table>` while the
descriptor reads the `<figure>` built at save time, so it still needs its
comment key restored.

### Modeled — generates markup

| Block | Attribute | Generated markup |
| --- | --- | --- |
| *all* | `className` | spliced into the element's class list |
| ~~paragraph~~ | ~~`dropCap`~~ | round-trips via the class carrier; nothing to do |
| paragraph | `direction` | `dir="rtl"` |
| list | `start` | `start="5"` |
| list | `reversed` | `reversed` |
| list | `type` | `style="list-style-type:upper-roman"`, only when ordered and not `decimal` |
| ~~quote~~ | ~~`textAlign`~~ | round-trips via the class carrier; nothing to do |
| ~~separator~~ | ~~`opacity`~~ | round-trips via the class carrier; nothing to do |
| table | `hasFixedLayout` | `has-fixed-layout` on the `<table>` |
| table | `caption` | `<figcaption class="wp-element-caption">` |
| table row | `rowType` | `<thead>` / `<tbody>` / `<tfoot>` grouping |
| table cell | `scope`, `align` | `scope=`, `data-align=` plus `has-text-align-*` |
| image | `linkTarget`, `rel`, `linkClass` | on the `<a>` |
| image | `title` | `title=` on the `<img>` |
| image | `aspectRatio`, `scale` | `aspect-ratio` / `object-fit` inline style |
| columns | `verticalAlignment` | `are-vertically-aligned-*` |
| columns | `isStackedOnMobile` | `is-not-stacked-on-mobile` when false |
| column | `verticalAlignment` | `is-vertically-aligned-*` |
| column | `width` | `style="flex-basis:33.33%"` |
| details | `name` | `name="faq"` |
| button | `linkTarget`, `rel`, `title` | on the `<a>` |
| button | `tagName`, `type` | `<button type="button">` instead of `<a>` (see note) |
| accordion-item | `openByDefault` | `is-open` |
| ~~tab-list~~ | ~~`tabs`~~ | sourced from the rendered buttons; nothing to do |
| embed | `responsive` | `wp-has-aspect-ratio` |

**Note on `button.tagName`.** `ButtonBlock`'s parse rule uses
`contentElement: 'a'` so the Link mark never claims the anchor. A button saved
with `tagName: "button"` has no `<a>` for that rule to find, so the rule needs a
second form selecting `a, button`, and `renderHTML` must emit `<button
type="...">` with no `href` / `target` / `rel` in that case. If this proves
awkward, the acceptable fallback is to leave `tagName` to the carrier and route
`tagName: "button"` markup to the passthrough card, which preserves it
byte-for-byte at the cost of inline editing. Decide during stage 2; do not let
it block the rest of the button work.

Already correct and unchanged: heading `level`; image `sizeSlug`, dimensions,
`isDecorative`, `href`; details `showContent`; accordion-heading `level`,
`showIcon`, `iconPosition`; tab-panel `label`.

### Carrier only — generates no markup

`lightbox`, `linkDestination`, `activeTabIndex`, `accordion.autoclose`, the
accordion parent's `headingLevel` / `showIcon` / `iconPosition` copies,
`templateLock`, `layout`, `levelOptions`, `placeholder`, the button's
`style.dimensions.width`, and every third-party attribute. These need no code
beyond applying `withBlockAttrs` everywhere.

### Deliberately excluded

**`separator.tagName: "div"`.** Modeling it requires the node to render two
different tags, which Tiptap's `HorizontalRule` is not shaped for. Today a
`div.wp-block-separator` matches no `<hr>` parse rule and falls through to the
passthrough card, where it is preserved byte-for-byte. That outcome is already
safe; changing it trades a working result for schema risk.

**Gallery beyond `className`.** Its `save()` pulls in a layout helper that has
not been traced, and `randomOrder` / `fixedHeight` / `allowResize` /
`aspectRatio` are newer than the markup `GallerySheet` was built against. Its
real output should be pinned down in its own pass rather than guessed at here.

## The table

The table is the largest single piece and the only one needing a schema change.

The root cause of most of its damage is that **nothing in Quill ever sees the
`<figure>`**. Tiptap's bare `table` rule claims the inner `<table>` and the
parser descends past the wrapper, so the figure's classes are invisible and its
`<figcaption>` is orphaned into a paragraph. The figure Quill saves is a fresh
one built at save time in `editor-transforms.js`.

**The fix is one parse rule.** Give the Table node a `figure.wp-block-table`
rule with `contentElement: 'table'` — the same technique `pullquote` already
uses with `contentElement: 'blockquote'`. Its `getAttrs` reads `className` off
the figure and the caption out of the `<figcaption>`. Scoping content to the
`<table>` is also what stops the caption leaking into the document.

Four attributes hang off that rule:

- **`className`** — from the figure, re-applied to the generated figure on save
  and written to the comment.
- **`caption`** — captured as an attribute and re-emitted into the figure. Not
  editable in this phase. Making it a real editable child requires changing
  Tiptap's `tableRow+` content model, which is a phase-2 feature rather than a
  leak fix. Preserved-but-uneditable is strictly better than destroyed.
- **`hasFixedLayout`** — default true, parsed from the comment or the
  `has-fixed-layout` class, rendered back as that class. The class already
  survives via `withClassAttr(Table)`; the comment key is what is lost.
- **`rowType`** on each row — `head` | `body` | `foot`, default `body`, parsed
  from the row's `<thead>` / `<tfoot>` ancestor. On save, rows are collected by
  type and emitted in Gutenberg's fixed head-body-foot order. The existing
  all-`<th>`-first-row promotion applies **only when no row in that table
  declares a `rowType` other than the default** — that is, to classic tables
  with no explicit sections and to tables Quill created itself. Once any row
  carries a type, `rowType` is authoritative and the heuristic does not run.

Plus `scope` and `data-align` as attributes on the cell and header nodes.
`has-text-align-*` already survives through the class carrier, but Gutenberg
emits `data-align` alongside it and validates against both.

### Accepted limit: colspan plus explicit sections

When a table has explicit sections **and** a colspanned cell, ProseMirror pads
every row out to a uniform cell count, so the header and footer each gain a
phantom empty cell. This is ProseMirror's table normalization running at parse
time, upstream of anything the save transform can reach. In isolation, colspan
round-trips correctly and sections round-trip correctly; only the combination
fails.

This is documented rather than fixed. The alternative — detecting the
combination on load and routing the table to a frozen passthrough card — makes
an ordinary table uneditable, which is a worse outcome for a rare case.

## Testing

Every leak in this audit shares one shape: it survives the pure transform
helpers and dies in the real editor. CLAUDE.md already records that lesson from
the `const`-versus-`function` `globalThis` bug — only the
real-`editor.html`-in-jsdom harness catches this class. Pure-Node tests are not
sufficient evidence here.

### Two different sources of truth, never confused

`Scripts/fixtures/README.md` records a bug that cost a day: Quill's
`core/accordion-heading` markup was modelled on a *fixture*, that fixture had
been written by an older WordPress than the site now runs, and every accordion
Quill saved came back as "Block contains unexpected or invalid content". Its
rule is therefore binding on this work:

> A fixture records what one version of WordPress wrote on one day. It is not a
> statement about what core emits now, and must never be used as the reference
> when implementing a block's `renderHTML`.

So this phase uses two sources, for two different jobs.

**The oracle for markup is the site's own installed core**, not GitHub trunk and
not a fixture:

```bash
curl -s https://<site>/wp-includes/js/dist/block-library.js > /tmp/bl.js
```

Every `renderHTML` in the inventory is written against that file's `save.mjs`
and `block.json` for the block in question — `block.json` because attribute
defaults change the output (`accordion-heading.showIcon` defaults to true, so
`save()` always emits the icon). Deprecations matter too: a block may accept
several past shapes, so grep for `deprecated_default` near the block before
concluding any markup is invalid.

This design was drafted against GitHub trunk, which may run ahead of the
installed version. **Every markup claim in the inventory above is provisional
until re-checked against the site's own bundle.** The ordered-list numbering
error is a worked example of what that re-check catches.

**Fixtures are regression subjects**, capturing real `post_content` so that
already-published posts keep round-tripping byte-identically. They are generated
by creating one draft post in the user's own WordPress with each block and each
modeled setting enabled, pulling `post_content` back through the REST API Quill
already speaks, and committing the result. The draft is never published and is
deleted once captured. This lines up with the fixture-diff harness sketched as
Approach H in `docs/future-architecture.md`.

Per the README, fixtures carry no comments and no header — the bytes are the
test — and they go in `Scripts/fixtures/` as flat `settings-<block>.html` files
rather than a subdirectory, because `test-block-serializer.js` and
`test-editor-preservation.js` both glob that directory non-recursively and a
subdirectory would silently opt out of their coverage.

### Layout

| File | Covers |
| --- | --- |
| `Scripts/fixtures/settings-*.html` | the generated corpus, one file per block |
| `Scripts/test-editor-block-settings.js` | one test per row of the inventory, asserting generated markup |
| `Scripts/test-editor-table.js` | caption, `rowType`, `scope` / `data-align`, `hasFixedLayout`, `className` |

The colspan-plus-sections limit gets a test that **asserts the phantom cell**,
so it is recorded behaviour rather than a lurking surprise. If it is ever fixed,
that test fails and points at the documentation to update.

A drift guard fails the suite if a block descriptor gains a modeled attribute
with no corresponding fixture, so the corpus cannot silently fall behind.

### Known trap

Anything added to `block-descriptors.js` that `editor-transforms.js` must reach
across the classic-script boundary has to be a `function` declaration, not a
top-level `const`. A `const` is reachable by bare identifier but never as a
property of `globalThis`, so it works in every Node test and reads `undefined`
in the running app. `modelsBlockName` is the existing pattern.

## Rollout

Three stages, each green before the next begins.

1. **Carrier everywhere.** Apply `withBlockAttrs` to every node and add
   `className` as a shared attribute. Largest win for the smallest risk; this
   alone fixes most of the audit.
2. **Per-block attributes.** Work through the inventory block by block.
3. **The table.** The largest piece and the most likely to need iteration.

After each stage: run `./test.sh`, then quit the app, run `./build.sh`, reopen,
and check a **new local draft**. Read the saved HTML straight out of
`drafts.db` rather than trusting code view, which shows pretty-printed content
rather than the bytes.

## Out of scope

- Any UI control for any of these settings. That is phase 2, and which settings
  earn a control is an open decision.
- Extending `_reportBlocksAtRisk`, which detects missing *blocks* and has no
  notion of missing attributes. The fixture corpus is the equivalent guard.
- Gallery attributes beyond `className`.
- Table caption editing.
- `separator.tagName`.

## Cleanup

- Delete `Scripts/probe-attrs.js` once its cases are folded into the real suites.
- Add the block-settings section to `docs/wordpress-release-audit.md`.
- Rewrite the `ownedAttrs` comment at the top of `block-descriptors.js`.
- `docs/gutenberg-block-snippets.md` is stale on pullquote, which it still
  describes as not visually editable. Correct it while in the area.
