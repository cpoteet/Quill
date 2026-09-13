# Block Settings Framework, Controls and Table Sections — implementation plan

> Supersedes the forward half of `2026-09-13-block-settings-preservation.md`.
> That document stays as the record of stage 1, which is committed, plus its
> Findings section, which is still binding.

**Goal:** a registry where a block setting is one line, so settings can be added
or removed over time without touching editor code; toolbar controls for an
agreed set; table header/footer sections; and a Word-style table size picker.

**Prior work, committed:** `01ec015` (delimiter escaping) and `b6a2e8e` (the
carrier on every node, `className` splicing, the twelve fixtures). Together they
are tier 1 below, and they already make Quill preserve anything Gutenberg wrote
that does not need redrawing.

---

## State of play (2026-09-13)

Committed on `gutenberg-block-model`, 12 test suites green:

| Commit | What |
|---|---|
| `01ec015` | Delimiter attribute escaping, matching core's six escapes |
| `b6a2e8e` | The carrier on every node, `className` splicing, twelve fixtures |
| `f90234c` | This plan |
| `4f0f9b7` | **Task A1 done** — the registry, with one entry and two guards |
| `669eeff` | **Task A2 done** — `withBlockSettings`, the generated Tiptap attributes |
| `c5130b5` | **Tasks A3 and A4 done** — the delimiter half and the generated controls |

**Stage A is complete. Next: task B1.**

The registry still ships with exactly one entry — `accordionItem.openByDefault`
— which was the machinery's subject through A2–A4.

Two deviations from the tasks as written, both deliberate:

- **`withBlockAttrs` composes `withBlockSettings`** rather than being a third
  wrapper applied at each node's call site. The stage-A completion test caught
  the reason: added per node, a second registry entry produced its toolbar
  control but neither its class nor its comment attribute — two edits, not one.
  The nesting order the plan specifies is unchanged.
- **Only the `toggle` control type is built.** `_buildSettingControl` is a
  switch with one case; `blockStyle` belongs with B1's five entries and
  `choice` with C/D, where each has a subject and a test. Building them now
  would have meant untested code.

Proven, then reverted: adding `columnsBlock.isStackedOnMobile` as one registry
line produced the class, the comment key and the control with no other edit.

Two things not repeated below that are worth knowing:

- The scope cuts came from scanning all 158 posts and pages on the site. Drop
  caps, list numbering, column widths, text direction, details names, image link
  settings, lightbox and aspect ratio appear in **zero** of them. Block styles
  appear in 9, YouTube embeds in 8, an image `title` in 22 (already safe), a
  table footer row in 1. Re-run that scan before adding anything back.
- WordPress draft **18195** ("Block Test") is still on the live site. It is the
  source of the `settings-*.html` fixtures and is kept so stage B and D can
  re-check markup in Gutenberg. Task G1 deletes it.

---

## The three tiers

A setting sits in exactly one. Moving between them is editing one line.

| Tier | What it means | Configuration |
|---|---|---|
| **1 — Carried** | The delimiter JSON is handed back untouched | none, automatic, **already shipped** |
| **2 — Redrawn** | Quill regenerates the markup the setting draws | one registry entry |
| **3 — Controlled** | As tier 2, plus a toolbar control | same entry, plus a `control` field |

Tier 1 is the floor for everything nobody modeled, including third-party
attributes and whatever a future WordPress adds. Tier 2 exists only because
Quill rebuilds the visible HTML on save: a setting that draws something would
otherwise come back as a comment that disagrees with its own markup, which is
what makes Gutenberg report a block as invalid.

### What the registry cannot express

Two things are document *structure*, not a setting on an element, and stay
hand-written: a table's head/foot sections, and a table caption's attachment to
its figure. Stage F covers both. Do not try to force them into the registry.

---

## Global Constraints

- **The oracle for markup is the site's own installed core**, never GitHub trunk
  and never a fixture. `curl -s https://<site>/wp-includes/js/dist/block-library.js`.
  `Scripts/fixtures/README.md` records the day this rule cost when broken.
- **Sourced attributes never reach the delimiter.** `block.json` marks many
  attributes `source: "attribute" | "rich-text" | "query"`; Gutenberg reads those
  back out of the HTML and omits them from the comment. A registry entry for one
  carries `sourced: true` and writes markup only. The full per-block list is in
  the old plan's Findings section 1.
- **A new file in `Resources/` needs its own `cp` line in `build.sh`** or it 404s
  at runtime while every Node test still passes.
- **Anything `editor-transforms.js` must reach across the classic-script boundary
  has to be a `function` declaration**, never a top-level `const`.
- Comments follow `CLAUDE.md`: default to none, one line maximum, never restate
  the code.
- Do not commit unless asked. After each task `./test.sh`; after each stage quit
  the app, `./build.sh`, reopen, and check a **new local draft**, reading saved
  HTML from `drafts.db` rather than code view.

---

## Scope, as agreed

**In:**

| Block | Setting | Tier |
|---|---|---|
| button | Fill / Outline style | 3 |
| quote | Default / Plain style | 3 |
| table | Stripes style | 3 |
| image | Rounded style | 3 |
| separator | Default / Wide / Dots style | 3 |
| button, link | open in new tab | 3 |
| accordion item | open by default | 3 |
| accordion | show icon, icon position | 3 |
| tabs | default tab | 3 |
| table | header row, footer row | structural + 3 |
| table | preserve a Gutenberg-authored caption | structural |

Plus two insert affordances: a **Separator** entry in the insert dropdown, and a
**Word-style table size picker**.

**Explicitly out**, decided against on evidence that nothing in 158 posts and
pages uses them: paragraph drop cap and text direction, ordered-list start /
reversed / numbering style, column widths and vertical alignment, columns
stacking, details `name`, image link target and aspect ratio and lightbox, quote
text alignment, table fixed-width layout, and creating or editing table captions
inside Quill.

Adding any of these later is a registry line, which is the point of stage A.

---

## Stage A — the settings registry

### Task A1: The registry file and its four kinds

**Files:**
- Create: `Sources/QuillKit/Resources/block-settings.js`
- Modify: `build.sh` (its own `cp` line), `Sources/QuillKit/Resources/editor.html` (load it)
- Test: `Scripts/test-block-settings-registry.js` (create — pure Node, no DOM)

Every setting in the inventory reduces to one of five kinds. Confirm that claim
against the installed bundle before writing the machinery; if a sixth is needed,
add it deliberately rather than bending an existing one.

```js
// carried   — draws nothing; tier 1 already preserves it. Present here only so
//             a control can be declared against it.
// flagClass — a class that is either present or absent
// valueClass— a class with the value interpolated
// style     — one inline CSS property
// attr      — an HTML attribute, optionally on a descendant
```

Entry shape:

```js
const BLOCK_SETTINGS = {
  accordionItem: {
    openByDefault: { kind: 'flagClass', class: 'is-open', when: true, default: false },
  },
  tabsBlock: {
    activeTabIndex: { kind: 'carried', default: 0 },
  },
  buttonBlock: {
    linkTarget: { kind: 'attr', attr: 'target', on: 'a', sourced: true },
    rel:        { kind: 'attr', attr: 'rel',    on: 'a', sourced: true },
  },
}
```

`when` matters: `isStackedOnMobile` defaults to true and renders its class when
**false**, so presence cannot be assumed to mean truth.

- [ ] **Step 1: Write the failing test**

Assert the registry's own shape before any consumer exists — every entry has a
known `kind`, every `flagClass` declares `class`, `when` and `default`, every
`valueClass` pattern contains `{}`, every `attr` names an attribute, and no
entry names a setting that `block-descriptors.js` does not have a block for.

- [ ] **Step 2: Implement the registry with a single entry** — `accordionItem.openByDefault`, so the machinery has one real subject.

- [ ] **Step 3: Export it the way this codebase requires**

`function settingsFor(nodeName)` and `function settingKinds()` as **function
declarations**, plus a CommonJS export for Node. A top-level `const` is not
reachable as a property of `globalThis` from a classic script and will read
`undefined` in the running app while every Node test passes.

- [ ] **Step 4: Add the `cp` line to `build.sh` and the `<script>` tag to `editor.html`**

- [ ] **Step 5: `./test.sh`**

- [ ] **Step 6: Commit**

```bash
git add Sources/QuillKit/Resources/block-settings.js Scripts/test-block-settings-registry.js build.sh Sources/QuillKit/Resources/editor.html
git commit -m "feat: add the block settings registry

One entry per setting, naming how it draws. The machinery that reads it lands
next; this is the data and its shape guard."
```

---

### Task A2: Generate the Tiptap attributes from the registry

**Files:** `Sources/QuillKit/Resources/editor.html`, `Scripts/test-editor-block-settings.js`

**Produces:** `withBlockSettings(extension)` — a third wrapper beside
`withClassAttr` and `withBlockAttrs`, deriving `addAttributes()` from the
registry so a node's parse and render come from data.

Nesting order matters and must be settled with a test, not assumed:
`withBlockAttrs(withBlockSettings(withClassAttr(X)))` is the expected shape, so
the class carrier runs innermost and the delimiter carrier outermost.

- [ ] **Step 1: Write the failing test** — an accordion item with `openByDefault` loads, keeps `is-open` through a save, and an item without it gains neither the class nor the comment key.

- [ ] **Step 2: Run it to confirm it fails**

- [ ] **Step 3: Implement `withBlockSettings`**

For each setting, generate a Tiptap attribute whose `parseHTML` reads **the
delimiter comment first and the markup only as a fallback** — the comment is
Gutenberg's own source of truth and the markup is merely its output — and whose
`renderHTML` regenerates exactly what core's `save()` emits. A `sourced` setting
parses from markup only, since no comment will ever hold it.

- [ ] **Step 4: Apply it to `accordionItem` and no other node yet**

- [ ] **Step 5: `./test.sh`**

- [ ] **Step 6: Commit**

---

### Task A3: Generate the delimiter half from the registry

**Files:** `Sources/QuillKit/Resources/block-descriptors.js`, `Sources/QuillKit/Resources/editor-transforms.js`

**Produces:** `attrsFromSettings(nodeName, el)` and `ownedAttrsFor(nodeName)`,
so a descriptor no longer hand-writes `attrsFrom` for anything the registry
covers. Skips `sourced` settings entirely.

The header comment at the top of `block-descriptors.js` must be rewritten:
`ownedAttrs` no longer means "only keys the node genuinely round-trips", it now
means the registry's non-sourced set for that block. Delete the sentence about
`columnBlock` not owning `width`.

- [ ] **Step 1: Write the failing test**
- [ ] **Step 2: Confirm it fails**
- [ ] **Step 3: Implement, leaving every hand-written `attrsFrom` that the registry does not yet cover untouched**
- [ ] **Step 4: `./test.sh`**, and confirm `test-editor-containers.js` stays green
- [ ] **Step 5: Build and check a new local draft, reading `drafts.db`**
- [ ] **Step 6: Commit**

---

### Task A4: Generate toolbar controls from the registry

**Files:** `Sources/QuillKit/Resources/editor.html`, `Scripts/test-editor-block-settings.js`

The toolbar already has per-block groups — `#table-controls`,
`#columns-controls`, `#buttons-controls`, `#accordion-controls`,
`#details-controls`, `#tabs-controls` — shown and hidden in `updateToolbar`, and
`#btn-details-open` and `#btn-accordion-autoclose` are already exactly a toggle
bound to a block attribute. **Generalize that pattern; do not rewrite the
controls that already work.**

Three control types cover the agreed scope:

```js
control: { type: 'toggle', label: 'Open' }
control: { type: 'choice', label: 'Icon', options: [...] }
control: { type: 'blockStyle', options: [{ value: '', label: 'Fill' },
                                         { value: 'is-style-outline', label: 'Outline' }] }
```

`blockStyle` is its own type because it edits one `is-style-*` token inside the
`className` string and must leave every other class the user has alone.

- [ ] **Step 1: Write the failing test** — a generated toggle appears when the cursor is inside its block, is absent outside it, reflects the current value, and flips the attribute when pressed.
- [ ] **Step 2: Confirm it fails**
- [ ] **Step 3: Implement generation into the existing group spans**
- [ ] **Step 4: Declare the control on `accordionItem.openByDefault` only**
- [ ] **Step 5: `./test.sh`**
- [ ] **Step 6: Build, and click the control in the app**
- [ ] **Step 7: Commit**

**Stage A is done when adding a setting is one registry line and nothing else.**
Prove it: add a second setting in one line, with no other edit, and watch it
work. If that is not true, stage A is not finished and stages B–E will each
re-introduce bespoke code.

---

## Stage B — block styles

### Task B1: One `blockStyle` control, five blocks

**Files:** `Sources/QuillKit/Resources/block-settings.js`, `editor.html`, `Scripts/test-editor-block-settings.js`

`className` is already carried and spliced into the rendered class list by
`b6a2e8e`, so **no redraw work is needed** — these are `kind: 'carried'` entries
whose only content is a control.

- [ ] **Step 1: Read each block's registered styles from installed core**

```bash
grep -o 'is-style-[a-z-]*' /tmp/block-library.js | sort -u
```

Confirm the exact style slugs for button, quote, table, image and separator, and
which is each block's default. Do not take the names below on trust.

- [ ] **Step 2: Write the failing tests** — one per block: the style survives a save in both the class and the comment, switching styles replaces the old token rather than stacking, and a user's own unrelated class on the same element is untouched.

- [ ] **Step 3: Confirm they fail**

- [ ] **Step 4: Add five registry entries**

| Block | Options |
|---|---|
| button | Fill (default), Outline |
| quote | Default, Plain |
| table | Default, Stripes |
| image | Default, Rounded |
| separator | Default, Wide, Dots |

- [ ] **Step 5: `./test.sh`**
- [ ] **Step 6: Build and try all five in the app**
- [ ] **Step 7: Commit**

---

## Stage C — the easy toggles

### Task C1: Accordion item open-by-default, and the tabs default tab

`openByDefault` lands with task A2/A4 as the machinery's subject; this task
finishes it and adds `tabsBlock.activeTabIndex`, which draws nothing and is
therefore a control over an already-preserved value.

Check during implementation whether core also keeps `openByDefault` on
`accordion-heading` — the bundle shows it on both the item and the heading, and
the control must not leave the two disagreeing.

- [ ] Steps as per the standard shape: failing test, confirm, implement, `./test.sh`, build, commit.

### Task C2: Open in new tab, for buttons and links

`linkTarget` and `rel` are `source: "attribute"` on the `<a>` — **markup only,
no comment keys**. Core writes `rel="noreferrer noopener"` alongside
`target="_blank"`; match whatever the installed bundle actually emits, including
its exact spacing, rather than composing the string yourself.

For prose links this is the existing `Link` mark rather than a block setting, so
it needs its own control beside the link button rather than a registry entry.
Confirm which of the two paths a link takes before writing either.

- [ ] Steps as per the standard shape.

---

## Stage D — accordion icons

### Task D1: Show icon and icon position

The awkward part, and the reason this is its own stage: core stores `showIcon`
and `iconPosition` **twice** — on `core/accordion` and again on every
`core/accordion-heading` — and it is the heading's copy that draws
`has-icon has-icon-left` and the icon span. A control that sets only the parent
leaves the two disagreeing and every heading unchanged.

So this needs a propagating control: setting it on the accordion writes it to
the parent and to every heading beneath it, in one transaction so a single undo
reverses the lot.

`CLAUDE.md` records that accordion-heading already models `level`, `showIcon`
and `iconPosition` correctly, so the redraw exists; what is new is the control
and the propagation.

- [ ] **Step 1: Verify the markup against installed core** — `accordion-heading`'s `showIcon` defaults to true, so `save()` always emits the icon. Check the class names and the icon span exactly.
- [ ] **Step 2: Write the failing test** — includes a two-item accordion where flipping the parent updates both headings, and one undo restores both.
- [ ] **Step 3–6:** confirm, implement, `./test.sh`, build, commit.

---

## Stage E — insert affordances

These are independent of the registry and of each other, and can be built in
either order.

### Task E1: Separator in the insert dropdown

`#insert-menu` already holds Columns, Accordion, Tabs, Details, Buttons,
Pullquote and Preformatted, driven by an `INSERT_ACTIONS` map. Separator is
missing, and StarterKit's own `horizontalRule` is disabled, so there is no way
to insert one today.

- [ ] One menu entry, one `INSERT_ACTIONS` line, one test that it inserts a `core/separator` that survives a save. Respect the existing footnote refusal.

### Task E2: Word-style table size picker

Today `insertTable` drops a 3×3 with a header row immediately, with no size
choice. Replace that with a grid picker.

**Agreed shape:** a 10×8 grid; hovering highlights the region and a label above
reads "4×3 Table"; clicking inserts. Header row on by default, matching both
today's behaviour and Gutenberg's. The table button keeps its place in the main
toolbar.

Reuse `#insert-menu`'s mechanics rather than inventing new ones: absolute
positioning off the button's rect, `mousedown` `preventDefault` so the editor
selection survives, click-outside and Escape to dismiss, and the
`_isMenuOpen()` check that other handlers consult.

- [ ] **Step 1: Write the failing test** — the picker opens from the table button, reports the hovered size, inserts exactly that many rows and columns with a header row, closes afterwards, and refuses inside a footnote.
- [ ] **Step 2: Confirm it fails**
- [ ] **Step 3: Implement**, keyboard included — arrows resize, Enter inserts, Escape closes — since the sibling menus are already keyboard-navigable. Theme the panel with a `body.dark` rule, as `#insert-menu` has.
- [ ] **Step 4: `./test.sh`**
- [ ] **Step 5: Build and use it in the app**, checking hover, keyboard and dark mode
- [ ] **Step 6: Commit**

---

## Stage F — table sections and caption

The largest stage, and the only one the registry cannot express. Build it last,
on its own, and expect iteration.

### Task F1: Claim the table figure, so a caption stops being torn out

Nothing in Quill currently sees `<figure class="wp-block-table">`. Tiptap's bare
`table` rule claims the inner `<table>` and the parser walks past the wrapper,
so the figure's classes are invisible and its `<figcaption>` is orphaned into a
loose paragraph after the table. That is visible corruption, not just loss.

The fix is one parse rule with `contentElement: 'table'`, the same technique
`Pullquote` already uses with `contentElement: 'blockquote'`.

**Scope, as agreed:** preserve a caption that came from Gutenberg. Quill does
not create or edit one — that needs a change to Tiptap's `tableRow+` content
model and is explicitly out.

`caption` is `source: "rich-text"`, so it is markup only and must **not** be
written to the comment. `className` on the figure is a real comment attribute
and is what makes the Stripes style in stage B work on tables.

**The trap:** the figure is created at save time in `editor-transforms.js`,
before `wrapInDelimiters` runs, and `nodeNameForElement` maps it to `'table'` —
so the table descriptor's `attrsFrom` receives **the figure, not the `<table>`**.

- [ ] Failing test, confirm, implement, `./test.sh`, build, commit.

### Task F2: Row sections, and the header/footer toggles

Tiptap's schema has no concept of table sections, so a `<tfoot>` row parses as
an ordinary body row and is re-emitted inside `<tbody>`.

Give `tableRow` a `rowType` of `head | body | foot`, default `body`, parsed from
the row's `<thead>`/`<tfoot>` ancestor. On save, collect rows by type and emit
them in core's fixed head-body-foot order.

The existing all-`<th>`-first-row promotion stays, but applies **only when no
row declares a type other than the default** — that is, to classic tables and to
tables Quill created itself. Once any row carries a type, `rowType` is
authoritative.

Then two toolbar toggles in `#table-controls`, matching Gutenberg's Header
section and Footer section: turning one on adds a row of that type, turning it
off removes it.

**Recorded limit, not a bug to fix:** when a table has explicit sections *and* a
colspanned cell, ProseMirror pads every row to a uniform cell count at parse
time, so the header and footer each gain a phantom empty cell. This is upstream
of anything the save transform can reach. In isolation colspan round-trips
correctly and sections round-trip correctly; only the combination fails. Write a
test that **asserts the phantom cell**, so it is recorded behaviour rather than
a lurking surprise — if it is ever fixed, that test fails and points here.

- [ ] Failing test, confirm, implement, `./test.sh`, build against the
      `settings-table.html` fixture in a new local draft, commit.

---

## Stage G — wrap-up

### Task G1: Corpus assertion, drift guard, docs, cleanup

- [ ] **Whole-corpus test** — every `settings-*.html` fixture round-trips byte-identically with no edit, and survives an edit idempotently.
- [ ] **Drift guard** — fail the suite if a registry entry has no test and no fixture covering its block, so the corpus cannot silently fall behind the registry.
- [ ] **`docs/wordpress-release-audit.md`** — add a Block settings section listing every registry entry and the class or attribute it generates, to be re-verified against the site's own `block-library.js` each WordPress major release. This is the drift the ordered-list numbering error was a worked example of.
- [ ] **`docs/testing-plan.md`** — the new suites and the colspan-plus-sections limit.
- [ ] **`docs/gutenberg-block-snippets.md`** — correct the pullquote entry, still described as not visually editable; it has been since `f552d07`.
- [ ] **`docs/user-guide.md`** — the new toolbar controls, the separator entry and the table picker are user-visible and belong here.
- [ ] **`CLAUDE.md`** — re-run each suite and correct the counts; add the new files to the command list; record the registry as the way to add a block setting.
- [ ] **`rm Scripts/probe-attrs.js`**
- [ ] **Delete WordPress draft 18195** ("Block Test"), kept through this work so its settings could be re-checked in Gutenberg. Ask first — it is on the live site.

---

## Verification checklist

- [ ] `./test.sh` passes
- [ ] Adding a setting is one registry line, demonstrated
- [ ] All twelve `settings-*.html` fixtures round-trip byte-identically with no edit, and idempotently after one
- [ ] The pre-existing fixtures still round-trip — they protect already-published posts
- [ ] Every agreed control appears only inside its own block, reflects the current value, and survives a save
- [ ] A table keeps its header and footer rows, and a Gutenberg-authored caption, through an edit in the running app
- [ ] The table picker inserts the size the label reported, by mouse and by keyboard, in both themes
- [ ] `drafts.db` bytes checked directly, not through code view
