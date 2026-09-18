# Editor chrome gaps: block-setting previews and row-2 metrics

Audited 2026-09-14, after fixing the accordion. Two categories, one theme —
editor chrome that does not follow what the settings say. Block-setting previews
come first; row-2 button metrics are the last section.

## Block settings with no editor preview

Every block setting in `block-settings.js` writes its delimiter attribute and its
markup correctly — the block-settings suite proves that end of it. The
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

### Fixed on 2026-09-15

| Setting | Was | Now |
| --- | --- | --- |
| Button `is-style-outline` | Class on the editor DOM, no rule to match it. | Transparent fill, `currentColor` border, padding trimmed by the border width so the box does not grow. |
| Quote `is-style-plain` | Same. | Drops the left rule and the italics. |
| Separator `is-style-wide` / `is-style-dots` | Same, and the editor drew the browser-default `hr`, which is already full width — so Wide would have looked identical to Default. | The base rule is now core's short centred line; Wide goes to 100% and Dots draws core's three serif middle dots. The rule itself moved to a `::before` so the `hr` element stays a full-width 26px box — a 2px line the width of a thumbnail was close to unhittable, and nothing styled `ProseMirror-selectednode`, so a selected separator looked identical to an unselected one. It now takes a hover tint, a selected tint, and the row-2 ✕. |
| Image `is-style-rounded` | The class was absent from the editor DOM: `ResizableImage`'s node view builds its own `div.image-wrapper` and replaces `renderHTML`. | `_applyAttrs` copies the `is-style-*` token from `figureClass` (falling back to the carried `className`) onto the wrapper, and the wrapper rounds the image. |
| `tabPanel.isDefaultTab` | `_tabDecorations` picks the visibly active tab from the caret, so the setting showed nowhere. | A second `is-default-tab` decoration on the tab `activeTabIndex` names, drawn as a small "default" label. Suppressed when there is only one tab, which is trivially the default. |

Three of these are DOM, not CSS, so they carry regression tests in
`Scripts/test-editor-block-settings.js`: the image wrapper's token and the tab
mark, including that neither reaches the saved markup. The four CSS-only rules
cannot be tested in jsdom and were verified in Quill itself.

### Not fixed

#### 1. Autoclose behaves as designed

`accordionBlock.autoclose` is front-end-only — it means "close the other
sections when one opens" on the live site, and the editor expands every panel
independently, so there is nothing for it to do here. The toolbar button's
active state is the correct and complete feedback. No change needed.

The attribute name `autoclose` is core's and is fixed. The toolbar label is ours
and now reads "Auto-close", matching Gutenberg's inspector.

#### 2. New tab

`buttonBlock.linkTarget` has no editor-visible effect by nature. The toolbar
active state is the feedback. Working as intended.

## Row-2 toolbar button metrics

Audited 2026-09-14, after the accordion work.

Row 2's text buttons get `min-width: auto; padding: 0 9px` and their group gets
`gap: 5px`. Both rules used to name their groups by **id**, so a group added
later did not join them — it silently fell back to the icon-button metrics
(`min-width: 26px; padding: 0 4px`) and read visibly tighter than the text
buttons beside it. That is how Open and the two Icon controls ended up narrower
than Auto-close in the same row.

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

A first pass matched the generated block-settings groups by prefix
(`#toolbar-row2 [id^="settings-"]`) rather than by name. The durable fix below
replaced it.

### Fixed — the durable fix

Both rules now key off `tb-group`, a class every row-2 group carries, with
`tb-group-icons` opting the two icon groups (`image-align-controls` and the
`block-controls` ✕) back to the 26px square. `_buildSettingGroups` sets
`tb-group` on each generated group, so no group can be added without picking up
the metrics one way or the other — the id list and the `[id^="settings-"]`
prefix match are both gone.

That also closed the one real bug the audit found: `link-controls` — "New tab",
a text button rendering at icon metrics because it was in neither selector list.

The ✕ keeps its 26px square deliberately: its content is the text glyph
`&#10005;` rather than an SVG, but the square suits a delete affordance.

Re-run the check any time a row-2 group is added:

```bash
python3 - <<'PY'
import io, re
s = io.open('Sources/QuillKit/Resources/editor.html', encoding='utf-8').read()
row2 = s[s.index('<div id="toolbar-row2"'):]
row2 = row2[:row2.index('\n    </div>')]
for m in re.finditer(r'<span id="([a-z0-9-]+)"([^>]*)>', row2):
    cls = re.search(r'class="([^"]*)"', m.group(2))
    print(f'{m.group(1):24}{cls.group(1) if cls else "NO CLASS"}')
PY
```

### Not fixed — cross-surface drift

`#image-toolbar`, the floating image popover, runs its own scale: `gap: 4px` and
`padding: 0 8px` against row 2's `gap: 8px` and `padding: 0 9px`, plus explicit
`.img-tb-sep` divider elements where row 2 uses none. It is internally
consistent and it is a different surface, so nothing reads as broken — but the
two will drift further apart every time one is touched alone. Worth unifying to
one set of tokens if the toolbars are ever reworked; not worth a standalone
change.
