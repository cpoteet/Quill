# Gutenberg Block Model — Design Spec

**Date:** 2026-09-11
**Status:** Superseded in part — see "As built" below. The goals held; the architecture did not.

## As built (2026-09-15)

The inversion described under "Architecture" **was not implemented**, and a session
reading this spec as a description of the running code will look for the block tree
in the wrong place. What shipped instead:

- **The Tiptap document is still the source of truth.** `toWordPressHTML` is still a
  sequence of DOM passes over `editor.getHTML()`.
- **Delimiters come from a DOM pass, `wrapInDelimiters`, driven by
  `block-descriptors.js`.** This is the "bolt delimiter emission onto
  `toWordPressHTML`" option listed under Rejected alternatives. It was taken anyway,
  because it is DOM insertion rather than regex and so does not inherit the
  comment-stripping bug class, and because the projection/reconcile step carried the
  regression risk the plan itself flagged.
- **Attributes ride through Tiptap on the element**, not in a tree: comment-only
  attributes on `data-quill-block-attrs` (`withBlockAttrs`), every other root
  attribute in a `rawAttrs` snapshot replayed on save (`withRawAttrs`), and the
  attributes of the child elements a node renders from a template in a per-tag
  snapshot (`RAW_CHILD_ATTRS`).
- **The bundled WordPress parser is used for two things only:** wrapping every
  top-level block Quill has no node for (`wrapUnsupportedBlocks`), and the data-loss
  tripwire (`_reportBlocksAtRisk`). Modeled blocks never go through it.

The precedence rules that hold this together are in
`Sources/QuillKit/Resources/CLAUDE.md`, which is the file to read before changing any
of it.

## Problem

Two user-visible failures share one root cause.

### 1. Quill publishes classic posts

`toWordPressHTML` emits `<!-- wp: -->` comment delimiters for exactly three blocks: `wp:image`, `wp:gallery`, `wp:embed` (plus whatever `gutenbergPassthrough` captured verbatim). For paragraphs, headings, lists, blockquotes, code, tables and separators it adds the `wp-block-*` **CSS class** and nothing else — see `editor-transforms.js:254-333`.

WordPress's block parser keys on delimiters, not classes. A `<p>Hello</p>` with no preceding `<!-- wp:paragraph -->` is not a paragraph block; it is swept into a `core/freeform` (Classic) block. So a post written in Quill opens in Gutenberg as one large Classic blob with a few real image blocks stranded inside it.

The classes are why this went unnoticed: they make the *front end* render correctly, so published posts look right. The defect is only visible when the post is reopened in Gutenberg.

### 2. Most blocks cannot be edited

`gutenbergPassthrough` preserves unmodeled blocks byte-for-byte but renders them as static "Not editable in the visual editor" cards. Columns, Accordion, Tabs, Details and Buttons are all frozen. Editing them requires code view.

### Shared root cause

The round-trip is **HTML string → Tiptap document → HTML string**. Gutenberg's actual format is HTML *plus* comment delimiters carrying JSON attributes. Comments are not DOM elements, so Tiptap cannot model them; every save therefore strips them by regex and re-synthesizes them.

That design choice is the direct parent of three shipped bugs, all documented in the root `CLAUDE.md`:

- the greedy `[^\n]*` strip that consumed every image between two `wp:image` comments, silently deleting galleries
- the compounding-whitespace growth in the gallery wrapper
- the `.*?` vs `[\s\S]*?` line-terminator failure

These are not three bugs. They are one bug — attributes living out-of-band from the document — surfacing three times.

## Goals

1. Posts written in Quill open in Gutenberg as real blocks, not Classic content.
2. Columns, Accordion, Tabs, Details and Buttons become editable in the visual editor.
3. Adding a further core block later is a descriptor, not a node implementation.
4. Serialization correctness stops depending on regex over an HTML string.

## Non-goals

- **Converting existing classic posts.** Roughly five posts are affected, they render correctly as they are, and Gutenberg already has a built-in "Convert to blocks" button for the ones worth fixing. See Existing posts are out of scope.

- **Block coverage parity with Gutenberg.** WordPress's own React Native editor required a hand-written `.native.js` implementation per block, never covered the catalog, and is now unmaintained on trunk after the React 19 upgrade. Competing on coverage is a lost race. Everything outside the modeled set stays passthrough.
- **Gutenberg's editing chrome.** No hover-`+` between blocks, no block drag handles, no per-block floating toolbars. Quill stays a prose-first writing surface.
- **Theme-accurate rendering.** Columns render as columns, not as *your theme's* columns.
- **Drag-to-resize.** Column widths are set numerically.
- **A generic attribute-form generator.** Investigated and rejected for v1 — see Rejected Alternatives.

## Architecture

### The inversion

Today Tiptap's document is the source of truth and Gutenberg HTML is derived from it on save.

This inverts: **the block tree is the source of truth; the Tiptap document is a view onto it.**

```
load:  post_content ──parse──> block tree ──project──> Tiptap doc
save:  Tiptap doc ──reconcile──> block tree ──serialize──> post_content
```

Delimiters and attributes are then emitted because the tree *has* them, not because a regex glued them on. The entire bug class above becomes unrepresentable.

### Parsing

Use `@wordpress/block-serialization-default-parser`, bundled via a new `Scripts/bundle-block-parser.sh` following the `bundle-marked.sh` pattern — its own script and its own output file, never an edit to `bundle-tiptap.sh` (whose `"^2"` pin would drift the editor onto a newer Tiptap on any re-run). The package is dependency-free and carries no React.

It yields, per block:

```js
{ blockName, attrs, innerBlocks, innerHTML, innerContent }
```

`innerContent` is the interleaving of literal HTML and child-block placeholders (`null` entries). It must be preserved — it is what makes re-serialization lossless for blocks with mixed content.

### Serialization

One generic function for all blocks:

```
<!-- wp:name {attrs} --> innerContent (children spliced at null slots) <!-- /wp:name -->
```

Per-block serialization code disappears. Attribute JSON is `JSON.stringify`'d from the tree rather than scraped from markup. Blocks with no attributes emit the short form; self-closing blocks emit `<!-- wp:name /-->`.

**This is what fixes Problem 1**, and it fixes it for every block simultaneously, including blocks Quill does not model.

### The shape system

Core blocks fall into four shapes. **New** modeled blocks are declared as descriptors against a shape rather than implemented as bespoke Tiptap nodes:

| Shape | Structure | Blocks in scope |
|---|---|---|
| `text` | one editable rich-text region + attrs | Pullquote, Preformatted |
| `container` | N children of a fixed child block type | Columns, Buttons, Accordion, Tabs |
| `media` | attrs + optional caption, no editable body | — (existing nodes retained) |
| `leaf` | no content | — (existing nodes retained) |

**Blocks Quill already models keep their existing Tiptap nodes.** Paragraph, Heading, List, Quote, Code, Table, Separator, Image and Gallery are working today; rewriting them as descriptors would be a refactor with no user-visible payoff and real regression risk against a well-covered test suite. They gain correct delimiters from the new serializer and nothing else changes. The `media` and `leaf` rows are listed because they describe those existing nodes' shapes and define where a *future* block of that shape would attach.

A descriptor declares: block name, shape, child block name (for `container`), which attributes surface in the contextual toolbar, and the Tiptap node it projects to.

`Details` is a `container` whose children are heterogeneous (summary + body) — it is the one member of the set that needs a small amount of bespoke projection. This is expected; the shape system is designed around the five containers actually being built, not speculatively widened.

**Scope discipline:** do not invent a fifth shape before a real block needs it. Level 1 (below) means nothing breaks while waiting.

### Three levels of block support

| Level | Behavior | Cost per new block |
|---|---|---|
| 1 | Round-trips correctly, renders as passthrough card | **Zero** — automatic for every block, including plugin blocks |
| 2 | Editable, if it fits an existing shape | A descriptor |
| 3 | Novel interaction (map picker, chart editor) | Real code |

Group, Cover, Verse and Spacer are all Level 2 against existing shapes, so they are near-free once this lands. This satisfies Goal 3.

## Editing experience

The document remains one continuous, flowing page. Typing behavior is unchanged.

**Existing text and media blocks** — Paragraph, Heading, List, Quote, Code, Table, Image, Gallery — behave exactly as they do today. Click, cursor, type. Image and Gallery keep their existing sheets and selection UI. No user-visible change; only serialization changes.

**Pullquote and Preformatted** are new `text`-shape blocks. They behave like Quote and Code respectively: click, cursor, type. Both are inserted from the new toolbar menu.

**Container blocks** become live structure in the document flow rather than frozen cards:

- **Columns** renders as side-by-side columns with a faint boundary. Click into one, type. Typing is ordinary typing, constrained to a region.
- **Accordion** renders as disclosure triangles with summary lines and bodies; both are typed into directly. The triangle collapses for preview only.
- **Tabs** renders as a tab strip; click a tab, edit its panel.
- **Details** renders as summary + body.
- **Buttons** renders as actual buttons; click a label and type.

Structural changes that cannot be expressed by typing use the **contextual toolbar group** pattern already in `editor.html` — `#table-controls`, `#blockquote-controls` and `#image-align-controls` are `display:none` groups revealed when the cursor enters that context:

- inside Columns → `+Col`, `−Col`, stack-on-mobile
- inside Accordion → `+Item`, `−Item`, open-by-default
- inside Buttons → `+Button`, style
- inside Tabs → `+Tab`, `−Tab`, reorder

## Insertion UI

A single new toolbar button in the existing insert group (alongside image / gallery / table / link / footnote / embed), modeled directly on `#heading-button` / `#heading-menu` — which is already a toolbar dropdown with `aria-haspopup="menu"`, its own positioning, keyboard handling and dismissal.

```
Columns      ▸ 2 / 3 / 4
Accordion
Tabs
Details
Buttons
Pullquote
Preformatted
```

Image, Gallery, Table and Embed keep their dedicated one-click buttons; they are frequent actions and are not demoted into the menu.

The menu is a **dispatcher**, not a subsystem: some entries open an existing sheet (`GallerySheet`, media picker), others insert a block skeleton. Slash commands and a menu-bar `Insert` menu were both considered and rejected by the user in favour of this.

## Existing posts are out of scope

> **Correction (2026-09-15).** This holds for a *save with no edit*: the original bytes
> go back unchanged. It does not hold once the post is edited. A classic (undelimited)
> post is converted to blocks on the first edit — each paragraph becomes a
> `core/paragraph`, and a wrapper element the conversion has no block for, such as a
> bare `<div class="custom-box">`, is dropped along with its class. The data-loss
> tripwire is deliberately silent here, because freeform content is not a block and
> the parser reports none to compare against. This is the same flattening Gutenberg's
> own "Convert to blocks" performs and is almost always what the user wants, but it is
> a conversion, not preservation, and it is recorded here rather than left implicit.


Every post published through older Quill is classic content: paragraphs, headings, lists, standalone images and footnotes carry `wp-block-*` classes but no delimiters, so WordPress parses each post as one `core/freeform` block. Verified against a real published post — ["Learning to Build with Codex"](https://www.siolon.com/blog/learning-to-build-with-codex/) (post 17780).

**Decision: do not convert them, and do not build conversion into Quill.**

Classic content is valid. Those posts render correctly today and will keep rendering correctly if left alone — nothing is broken for readers. Roughly five posts are affected, and WordPress's own block editor already offers a "Convert to blocks" button on any Classic block, so the handful that matter can be fixed by hand in Gutenberg at zero engineering cost. Building a conversion command, a diff UI, and an idempotency-tested converter to save five manual clicks is not a trade worth making.

A useful detail confirmed in the same post: galleries and accordions **already carry correct delimiters** — Quill's gallery output and `gutenbergPassthrough`'s comment regeneration have both been right all along. Only the un-delimited prose is affected.

**Consequence for this design:** nothing in it reads, rewrites, or migrates existing content. A post loaded and saved with no edits must still come back byte-identical (see Round-trip safety below) — that guarantee is what keeps old posts safe when they are opened in the new editor.

### Round-trip safety

**The hardest constraint in the project.** A post loaded and saved with *no* edits must produce byte-identical `post_content`. The failure mode is silent corruption of published content, so this outranks every feature in the plan.

`_rawHTML` provides this guarantee today for the no-visual-edit path and must survive the rewrite intact.

### Local drafts

Drafts in Quill's SQLite store are HTML strings and pass through the same parser. No schema change, no separate migration path.

## Testing

The existing JS suites (`Scripts/test-editor*.js`) are the model: real `editor.html` in jsdom, real Tiptap instance via `window._tiptapEditor`.

1. **Parser/serializer round-trip** — a corpus of real `post_content` fixtures, each asserted byte-identical through parse → serialize. Cheap to run, catches the entire regression class that produced the three shipped bugs. This is the highest-value new test.
2. **Delimiter emission** — each tier-A block asserted to emit correct `<!-- wp:name -->` delimiters, replacing the class-only assertions in `test-editor.js`.
3. **Container editing** — a new `Scripts/test-editor-containers.js` covering insert / type-into / nested-child / contextual-control behavior per container, following `test-editor-gallery.js`'s structure.
4. **Projection/reconcile** — Tiptap edits land on the correct tree node and leave siblings untouched.
5. **Passthrough non-regression** — `test-editor-passthrough.js` must stay green; unmodeled blocks are still preserved byte-for-byte.
6. **Swift** — `WordPressClient` and storage layers are unaffected. No new Swift tests expected.

A Gutenberg fixture-diff harness is described as Approach H in `docs/future-architecture.md`; item 1 is a subset of it and worth building first.

## Rejected alternatives

**Embed the real Gutenberg editor in the WKWebView.** Multi-megabyte React expecting WP data stores, the REST API and `theme.json` to render correctly. Deletes every native affordance Quill has — the toolbar, media sidebar, AI panel, keyboard handling — and makes Quill wp-admin in a window, which is the reason the app exists.

**Bolt delimiter emission onto `toWordPressHTML` without the tree.** This is the cheap fix for Problem 1 alone, and it would work. Rejected because it adds seven more comment-wrapping regex passes to the exact machinery that produced three silent-data-loss bugs, and it does nothing for Problem 2. The delimiter fix is free and structurally correct inside the tree.

**Generic attribute-form generator from `/wp/v2/block-types`.** Attractive — it would make every block's settings editable, including plugin blocks, from schemas discovered on the user's own site. Rejected for v1 because the contextual-toolbar pattern already in `editor.html` covers the controls that matter for all fifteen blocks in scope, and a generated form is a worse UX for those. Revisit if passthrough blocks become a real friction point.

**Per-block native implementations in the Gutenberg Mobile style.** The empirical case against it: WordPress funded a full-time team, had complete access to block internals, still never covered the catalog, still shipped an "Unsupported Block" card for the remainder, and the project is now unmaintained. Quill's `gutenbergPassthrough` card is the same fallback, arrived at independently.

## Risks

- **Tabs markup instability.** `core/tabs` only became core in WP 7.1 and was structurally refactored on the way in. It is the least settled block in scope and the most likely to need rework. Consider sequencing it last.
- **Accordion is four block types.** `core/accordion` → `accordion-item` → `accordion-heading` + `accordion-panel`. The container tier is ~11 block types, not 5.
- **Projection/reconcile is the genuinely hard part.** Tiptap's document is effectively flat; Gutenberg's is a tree. Mapping edits across that boundary is where the real difficulty lives — everything else is mechanical.
- **Scope.** This is a rewrite of the load/save path, not a refactor. Quill works today; this buys correctness and future capability, not immediate features.

## Open questions

None blocking. Sequencing is deferred to the implementation plan.
