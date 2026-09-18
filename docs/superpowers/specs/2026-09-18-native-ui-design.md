# Native macOS UI — design

**Date:** 2026-09-18
**Branch:** `native-ui`
**Status:** approved, pending implementation plan

## Summary

Replace Quill's hand-built window chrome, warm panel surfaces and hand-rolled
split layout with native macOS 27 (Golden Gate) structure: `NavigationSplitView`,
a real window toolbar, a real `.inspector`, and system-drawn sidebar selection.
Quill's identity moves from painted surfaces to the accent colour.

The goal is a Mac-standard app with materially less code. Roughly 250 lines of
chrome workarounds are deleted, and nothing replaces them.

## Decisions

| Question | Decision |
|---|---|
| Deployment target | macOS 27 only. No backwards compatibility, no availability gates. |
| Amber | App-wide accent via `.tint(.wpAmber)`, overriding the user's system accent. |
| Toolbar | One bar. Actions move into the window toolbar; the custom second row is deleted. |
| Sidebar | Two columns. Sections become a segmented picker in the toolbar. |
| Post title | Stays as a large editable field at the top of the document body. |
| Editor webview | Colour retune only. No structural change, no SwiftUI rewrite of the formatting toolbar. |
| Warm surfaces | Dropped entirely. See *Findings*. |

## Findings from the native spike

A throwaway SwiftUI app was built against the macOS 27 SDK and run, to settle
questions the SDK alone could not answer. These are observed, not assumed.

1. **`.tint(_:)` reaches the OS-drawn sidebar selection.** The selected `List`
   row renders as an amber capsule. No `AccentColor` asset is required.
2. **`.buttonStyle(.glassProminent)` adopts the tint.** Publish renders as a
   solid amber glass pill in both light and dark mode. This is the app's
   strongest identity moment.
3. **`backgroundExtensionEffect()` does not tint the toolbar glass.** The
   toolbar strip stays neutral regardless of the content colour behind it. A
   warm title bar is reachable only through the same `titlebarAppearsTransparent`
   hacks this work exists to delete.
4. **A warm content panel creates seams rather than removing them.** With the
   sidebar and inspector drawn as system materials, a warm editor panel breaks
   against cool grey on three edges. The old design avoided this only by
   painting every surface itself, including the title bar.

Conclusion: neutral surfaces, amber accent. If warmth is wanted later, the
non-fighting place for it is the writing surface inside the webview, where it
is CSS and nothing native competes.

## What gets deleted

### `Sources/QuillKit/Views/ContentView.swift`
The entire window-chrome apparatus: `WindowObservingView`, `titleBarColor(for:)`,
`titleBarFixNeeded(for:)`, `applyTitleBarFix(to:)`, `WindowTitleBarFix`, and the
`.toolbarBackground(.hidden, for: .windowToolbar)` modifier that existed to stop
SwiftUI fighting it. The OS draws the title bar.

### `Sources/QuillKit/DesignSystem.swift`
`WarmPanelBackground`, `WarmSidebarBackground`, `WarmPanelHeaderBackground`,
`SoftPanelBoundary`, `SoftHorizontalDivider`, `PanelInteriorFade`, and the
`NSColor.wpSidebarBg` / `Color.wpSidebarBg` / `wpPanelBg` / `wpTitleBarBg`
tokens.

Retained: `Color.wpAmber`, `statusColor(_:)`, `ToastView`, `UploadStatusPill`
and their view modifiers.

Retained **provisionally**: `rebuildsOnAppearanceChange()`. It works around a
stale `NSAppearance` stamp on SwiftUI's `Picker`. Whether that still reproduces
on macOS 27 is unknown and must be tested before removal — the new toolbar
section picker is exactly the control it protects.

### `Sources/QuillKit/Views/Sidebar/SidebarView.swift`
`sectionTabs` (the hand-drawn amber pill row), the 2.5pt amber selection bar and
tinted row background, and the custom `SearchField`.

### `Sources/QuillKit/App/AppState.swift`
`isSidebarVisible` and its four call sites. `NavigationSplitView` owns column
visibility and supplies the standard toggle.

## Target architecture

### Window

```
NavigationSplitView
├── sidebar: List(selection: $appState.selectedItem)
│            .listStyle(.sidebar)
│            .searchable(text: $appState.searchText, placement: .sidebar)
│            .navigationSplitViewColumnWidth(min: 270, ideal: 310, max: 400)
└── detail:  PostEditorView | MediaDetailView | EmptyEditorPlaceholder
             .inspector(isPresented:) { PostSettingsPanel }
```

`.navigationSplitViewColumnWidth` must be applied **after** `.searchable`.
Applied before it, the modifier does not reach the column and the sidebar
collapses to roughly 144pt with every headline truncated. Verified in the spike.

Minimum sidebar width is 270pt; below that the two-line row (title + excerpt)
truncates unusably.

The sidebar keeps its existing media branch. `SidebarView` currently swaps its
whole body for `MediaSidebarSection` when the section is `.media`
(`SidebarView.swift:16` and `:174`), and `ContentView` swaps the detail pane to
match (`ContentView.swift:133`). That branch survives the conversion unchanged
in behaviour: the post `List` is what becomes native, while the media sidebar
keeps its own content. `.searchable` applies only to the post branch, matching
today's behaviour, where search is hidden in the media section.

`PostSettingsPanel` moves from a hand-rolled third `HStack` column to
`.inspector(isPresented:)`, gaining the standard slide-in, a resizable divider
and OS-drawn toggle behaviour. This touches `PostEditorView.swift` (1,330
lines) and is the highest-risk step; it gets its own commit.

### Toolbar

Leading to trailing:

1. Sidebar toggle — supplied by `NavigationSplitView`, not hand-built.
2. Section picker — segmented `Picker` with text labels (`Posts`, `Pages`,
   `Drafts`, `Media`), ~280pt. Icon-only segments were tested and are
   ambiguous; labels are required.
3. `ToolbarSpacer(.flexible)`
4. Status indicator — a bare amber dot, not a capsule. A capsule reads as a
   disabled control among the glass buttons.
5. `ToolbarItemGroup` — Revert, Preview.
6. `ToolbarSpacer(.fixed)`
7. Publish — `.buttonStyle(.glassProminent)`.
8. Inspector toggle.

`.navigationTitle("")` on the detail view. A window title next to the section
picker reads as stray text, and the post's own title is already the first thing
in the document.

Keyboard shortcuts carry over unchanged: ⌘S saves or updates, ⌘⇧P publishes.

### Editor body

Title field at the top on the plain content background, then the webview. The
header's `SoftHorizontalDivider` is removed; `scrollEdgeEffectStyle` handles
that edge natively.

## Sidebar action buttons

The sidebar's bottom bar currently holds two hand-drawn buttons: Refresh (⌘R)
and a section-aware "New Post" / "New Page" (⌘N), the latter drawn as an amber
pill. Both move into the window toolbar's leading group as standard toolbar
buttons — `arrow.clockwise` and `square.and.pencil` — which is where Mail and
every other Mac app puts them. Keyboard shortcuts and the section-aware title
(exposed as a `.help` tooltip) are preserved. The bottom bar is then deleted.

The update-available banner keeps its place at the bottom of the sidebar but
loses its amber wash, becoming a plain row with the standard amber accent on
its icon.

## Second right-hand panel

The right column is shared by two mutually exclusive panels, not one:
`PostSettingsPanel` and `EvaluationPanel` (AI evaluation), switched by
`isSettingsOpen` and `showEvaluationPanel` in `PostEditorView`. The inspector
conversion covers both: a single `.inspector(isPresented:)` whose content
switches on which panel is active, preserving the existing rule that opening
one closes the other. `EvaluationPanel` carries the heaviest custom styling in
the app after the sidebar, so it is restyled in the same pass.

## Secondary surfaces

The window is not the whole app. These surfaces are also in scope.

**`PreferencesView`** — a hand-rolled settings sheet with a private
`settingSection` helper that draws its own rounded boxes and stroke borders.
Its interior becomes `Form(.grouped)` with real `Section`s, deleting the helper
and the hand-drawn boxes.

It stays a `.sheet` rather than becoming a `Settings` scene. A `Settings` scene
gives a native ⌘, window, but Quill also opens preferences programmatically on
first run when no credentials exist, and doing that to a `Settings` scene
requires poking a private selector — reintroducing exactly the kind of hack
this work removes. The sheet is the lower-hack answer and is legitimate for a
first-run gate.

**`AboutView`** — keeps its structure. A custom About panel with third-party
notices is normal on macOS and the standard panel cannot present them. Only its
hand-drawn spacing and dividers are brought in line.

**Sheets and panels** — `GallerySheet`, `MediaPickerView`, `MediaDetailView`,
`MediaSidebarSection`, `GeneratePostSheet`, `SamplePostPickerSheet`,
`AIResultPanel`, `LinkPickerView`, `BlockRiskAlarm`, `PostListRow`. Each is
audited for the deleted tokens and for `.buttonStyle(.plain)` used to escape
system styling. Rule applied: amber stays only where it carries meaning (status,
accent), and hand-drawn containers give way to system materials.

## Amber strategy

- `.tint(.wpAmber)` at the app root. This drives the sidebar selection capsule,
  focus rings, the selected picker segment and the Publish pill.
- `statusColor(_:)` unchanged — status dots keep their existing meanings.
- Amber empty-state icons unchanged.
- The editor's amber link colour CSS variable is unchanged.

`wpAmber` was originally tuned against a warm #F2F1EF panel. Against neutral
system backgrounds it may need a small adjustment; this is judged in the running
app, not in advance.

## Editor webview

Colour only, in `Sources/QuillKit/Resources/editor.html`:

- Page background `#f4f3f1` → a neutral matching the native content background.
- Toolbar strip `rgba(247,247,248,0.96)` and its dark counterpart → values that
  sit flush under the native chrome, so there is no visible seam where the
  native toolbar meets the HTML one.

No markup changes, no transform changes. `editor-transforms.js`,
`block-descriptors.js`, `block-settings.js` and the whole save path are
untouched, so the 1,201 JS tests are unaffected by construction.

Per the `Resources/` build gotcha: no new resource files are added, so no
`build.sh` `cp` lines are needed.

## Implementation order

Each step ends with `./build.sh` and a launch, per CLAUDE.md.

1. Raise deployment target to macOS 27 in both `Package.swift` and `build.sh`
   (`MIN_MACOS`, which feeds `LSMinimumSystemVersion`); confirm package and
   tests still build.
2. Delete the window-chrome apparatus from `ContentView`. Verify the title bar
   is system-drawn and does not flash.
3. Convert the layout to `NavigationSplitView` with a sidebar `List`; delete
   `isSidebarVisible`, `sectionTabs` and the custom `SearchField`.
4. Build the window toolbar; delete `PostEditorView`'s custom toolbar row.
5. Convert `PostSettingsPanel` and `EvaluationPanel` to `.inspector`.
   *(Highest risk; own commit.)*
6. Apply `.tint(.wpAmber)`; delete the warm surfaces from `DesignSystem.swift`.
7. Restyle the secondary surfaces: `PreferencesView`, `AboutView`, and the
   sheets and panels listed above.
8. Retune the webview colours.
9. Test whether the `Picker` appearance bug still reproduces; delete
   `rebuildsOnAppearanceChange()` if it does not.

## Verification

- `./test.sh` — 428 Swift + 1,201 JS tests. Swift view coverage is thin, so this
  is a regression guard, not proof the UI is right.
- `./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"` —
  required before sign-off, since the webview colours are touched.
- Manual, on a **new local draft only** (never a published post or page):
  - light/dark toggle, including the section picker after a switch
  - sidebar collapse and reveal
  - inspector open, close and resize
  - full-screen enter and exit — the deleted code needed a dedicated fix here;
    native behaviour must be confirmed, not assumed
  - a save and a publish round-trip
  - window resize down to the minimum width

## Risks

1. **macOS 27 only.** Accepted explicitly. Quill will not launch on older
   systems.
2. **Step 5 touches the largest file in the app.** `PostEditorView.swift` is
   1,330 lines and the inspector conversion reaches into its layout. Isolated
   to its own commit so it can be reverted alone.
3. **The `Picker` appearance workaround may still be needed.** Removing it
   without testing would reintroduce a light-pill-on-dark-panel bug in the new
   toolbar picker. Step 8 exists for this.
4. **Reverting is cheap.** All work is on `native-ui`, and the deleted surfaces
   live in one file.

## Out of scope

- Moving the Tiptap formatting toolbar from HTML into SwiftUI. This is a full
  rebuild of the JS↔Swift bridge and belongs in its own project, after this
  shell lands.
- Three-column (Mail-style) layout. Considered and rejected: four sections is
  thin content for a dedicated column, and it would push the minimum window
  width from 900 to roughly 1100.
- Any change to WordPress HTML output, block handling or the save path.
