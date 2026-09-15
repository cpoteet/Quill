# Editor chrome gaps: block-setting previews and row-2 metrics

Audited 2026-09-14, after fixing the accordion. Two categories, one theme —
editor chrome that does not follow what the settings say. Block-setting previews
come first; row-2 button metrics are the last section.

## Block settings with no editor preview

Every block setting in `block-settings.js` writes its delimiter attribute and its
markup correctly — the 147-test block-settings suite proves that end of it. The
gap is one-sided: the editor canvas draws its own fixed chrome and ignores most
of what the settings say, so a control can be correct and still look dead.

The check is cheap. For a setting that draws a class, grep `editor.html` for the
class; no rule means no preview:

```bash
for t in is-style-outline is-style-plain is-style-wide is-style-dots is-style-rounded; do
  echo "$t: $(grep -c "\.$t" Sources/QuillKit/Resources/editor.html)"
done
```

### Fixed

| Setting | Was | Now |
| --- | --- | --- |
| `accordionBlock.showIcon` | The real `__toggle-icon` span was `display:none` and the visible `+` was an unconditional `::after` on the heading, so turning the icon off changed nothing on screen. | `::after` is gated on `.has-icon`. |
| `accordionBlock.iconPosition` | The same `::after` was pinned `right: 8px` with no left variant. | `.has-icon-left` flips it to `left: 8px` and flips the toggle's padding. |
| Caret stranded after a toolbar `<select>` | The two select-backed controls (icon side, block style) dispatched their change and left DOM focus on the `<select>`, so the caret sat at the block's start and every keystroke was dropped. The toggle *buttons* never had this — they `preventDefault()` on `mousedown`, which keeps focus in the editor; a select cannot, because it must take focus to open. | Both change handlers return focus to the editor after dispatching. |
| Placeholder overlapped the left icon | The "Accordion title" hint is absolutely positioned at a hard-coded `left: 4px`, measured against the heading rather than the toggle's padding box. With the icon on the right that happened to line up; with it on the left the icon was drawn on top of the hint. | `.has-icon-left` moves the hint to `left: 34px`. |
| `accordionItem.openByDefault` | Wrote `is-open`, which had no CSS at all. The editor's expand/collapse runs off a separate editor-only `is-collapsed` decoration. | An `is-open` item's heading carries an "open on the site" label, matching how `detailsBlock.showContent` already draws "closed on the site". Content is never hidden. |

### Not fixed

Ordered by how visible the gap is.

#### 1. Block styles draw nothing — five of six

`is-style-stripes` on tables is the only block style the editor renders. The
other five write the class correctly and land it on the editor DOM, but no CSS
rule matches:

| Block | Style | Editor DOM carries the class? |
| --- | --- | --- |
| Button | `is-style-outline` | yes |
| Quote | `is-style-plain` | yes |
| Separator | `is-style-wide` | yes |
| Separator | `is-style-dots` | yes |
| Image | `is-style-rounded` | **no** |

For the first four this is CSS only — add a rule per token in `editor.html` and
the toolbar button starts meaning something. Rough shapes: outline is a
transparent fill with a `currentColor` border; plain drops the quote's left rule
and italics; wide is a full-width `hr`; dots replaces the rule with three
centred dots.

Image is the one that needs more than CSS. `ResizableImage`'s node view builds
its own `div.image-wrapper` and never puts `figureClass` on it, so
`is-style-rounded` is absent from the editor DOM entirely. The node view has to
carry the class onto the wrapper before any rule can match it.

#### 2. Tabs: the default tab is invisible

`tabPanel.isDefaultTab` writes `activeTabIndex` onto the tabs block correctly,
but `_tabDecorations` picks the visibly active tab from wherever the caret is,
so the setting never shows. Same class of problem as the accordion's "Open", and
the same fix applies: a label on the tab that `activeTabIndex` points at. The
toolbar button does light up, so there is some feedback today.

#### 3. Autoclose behaves as designed

`accordionBlock.autoclose` is front-end-only — it means "close the other
sections when one opens" on the live site, and the editor expands every panel
independently, so there is nothing for it to do here. The toolbar button's
active state is the correct and complete feedback. No change needed.

The attribute name `autoclose` is core's and is fixed. The toolbar label is ours
and now reads "Auto-close", matching Gutenberg's inspector.

#### 4. New tab

`buttonBlock.linkTarget` has no editor-visible effect by nature. The toolbar
active state is the feedback. Working as intended.

## Row-2 toolbar button metrics

Audited 2026-09-14, after the accordion work.

Row 2's text buttons get `min-width: auto; padding: 0 9px` and their group gets
`gap: 5px`. Both rules name their groups by **id**, so a group added later does
not join them — it silently falls back to the icon-button metrics
(`min-width: 26px; padding: 0 4px`) and reads visibly tighter than the text
buttons beside it. That is how Open and the two Icon controls ended up narrower
than Auto-close in the same row.

Re-run the check any time a row-2 group is added:

```bash
python3 - <<'PY'
import io, re
s = io.open('Sources/QuillKit/Resources/editor.html', encoding='utf-8').read()
i = s.index('#table-controls, #image-align-controls'); gap = s[i:s.index('{', i)]
j = s.index('#table-controls button,');             pad = s[j:s.index('{', j)]
row2 = s[s.index('<div id="toolbar-row2"'):]
row2 = row2[:row2.index('\n    </div>')]
for sid in re.findall(r'<span id="([a-z0-9-]+)"', row2):
    print(f'{sid:24}{"gap" if sid in gap else "NO ":5}{"pad" if sid in pad else "NO"}')
PY
```

### Fixed — spacing rhythm

Row 2 spaced *within* a group at `gap: 5px` and *between* groups at `gap: 14px`
— close to 3x apart, in a row where the group boundaries are invisible. The
uneven beat was most obvious wherever two painted pills met across a boundary
(a hovered −Item beside an active Auto-close), because a painted pill shows its
padding and an unpainted one does not.

Both are now `8px`, so the row has one rhythm and grouping is carried by the
`setting-pair` track instead of by gap width. `#block-controls` (the ✕) takes an
extra `margin-left: 8px`, keeping the destructive control set apart from the
settings next to it.

### Fixed — button metrics

The generated block-settings groups now match by prefix
(`#toolbar-row2 [id^="settings-"]`) rather than by name, so every future block
setting inherits the text-button metrics instead of needing a CSS edit.

### Not fixed

Every row-2 group was checked against the kind of button it actually holds
(2026-09-14). Only one group is wrong:

| Group | Buttons | Missing | Verdict |
| --- | --- | --- | --- |
| `link-controls` — "New tab" | 1 text | gap **and** padding | **The one real bug.** A text button rendering at icon metrics (`min-width: 26px; padding: 0 4px`), so it is visibly tighter than every other text button in the row. Add it to both selector lists. |
| `block-controls` — the ✕ | 1 glyph | gap and padding | **Judgement call, not a bug.** Correcting an earlier claim in this doc that it is an icon button: its content is the text glyph `&#10005;`, not an SVG. The 26px square still suits a delete affordance, so leave it — but leave it deliberately. |
| `image-align-controls` | 3 SVG | padding only | Correct as-is. SVG icons want the 26px square; the gap rule it does have is the right half. |
| table (6), blockquote, columns (2), buttons (3), accordion (3), details, tabs (2) | all text | nothing | Clean. All carry both rules. |

### Not fixed — cross-surface drift

`#image-toolbar`, the floating image popover, runs its own scale: `gap: 4px` and
`padding: 0 8px` against row 2's `gap: 8px` and `padding: 0 9px`, plus explicit
`.img-tb-sep` divider elements where row 2 uses none. It is internally
consistent and it is a different surface, so nothing reads as broken — but the
two will drift further apart every time one is touched alone. Worth unifying to
one set of tokens if the toolbars are ever reworked; not worth a standalone
change.

### The durable fix

Both rules should key off a class every row-2 group carries (say `tb-group`,
with `tb-group-icons` opting the two icon groups back to square metrics) instead
of an id list plus a prefix match. That is a small refactor — a class on eight
static spans, one line in `_buildSettingGroups`, and two rewritten selectors —
and it removes the whole category: no group can be added without picking up the
metrics one way or the other.
