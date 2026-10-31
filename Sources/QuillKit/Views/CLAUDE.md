# Top-level views (ContentView)

Implementation gotchas specific to this directory. See the root `CLAUDE.md` for architecture, build/test commands, and cross-cutting conventions.

## Known gotchas

- **`detailContent`'s `.background(SplitItemSizePin())` is load-bearing** — without it every window resize step lays the detail column out at its minimum (835×152 with Post Settings open) for one pass, and the editor inside flashes blank. `PostEditorView` pins the inner editor item with the same helper; pinning only that one left this squash. Full explanation in `docs/gotchas.md`.

- **`.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)` on `ContentView` is load-bearing, and SwiftUI owns the window-toolbar configuration** — note the spelling: the older `.toolbarBackground(.hidden, for: .windowToolbar)` was dropped in `2db092c` as a "leftover" so the toolbar would draw its own Liquid Glass, and the current modifier was restored on 2026-09-19 under its macOS 27 name. It does two jobs. It lets each `NavigationSplitView` column's own background reach the top edge of the window, which is how Mail is built; without it the toolbar paints its own material band across both columns and the detail pane shows a visible step. It also suppresses the automatic toolbar backdrop's fade transition, which is what made the whole toolbar dim for ~200ms twice on every post open — see the toolbar-fade gotcha in `docs/gotchas.md`. Its only visual cost is a 1px `(229,229,229)` hairline under the toolbar that appears when content scrolls beneath it, measured at native resolution. It also matters *how* this is set: SwiftUI re-asserts its whole window-toolbar configuration on every view-graph update (traced 2026-07-25: `ViewGraph update` → `NSHostingView.updateEnvironment()` → `AppKitWindowController.hostingView(_:willUpdate:)` → `BarAppearanceBridge.updateWindowToolbarConfiguration`), and `ContentView`'s body reads `AppState`, so every data change re-applies it — which is why a post load, with its several async state changes, produced repeated flashes. Fighting that from outside — an `NSWindow` observer that repairs the bar after the fact — loses, and the repair lag shows up as flashing. Asking for the state you want through SwiftUI's own modifier is the only stable route.

- **Judge a surface colour from a native-resolution pixel scan, never a downsampled screenshot** — downsampled captures flatten small differences and have produced wrong conclusions twice: once making `#F2F1EF` look white, and once hiding that the editor was ~6 units darker than the native content pane. `screencapture -o -l <windowID>` at native resolution, plus a run-length scan down one pixel column, is decisive: a seamless surface shows as a *single* uninterrupted colour run and any seam splits that run in two. Three caveats: values shift slightly through the display-profile→sRGB conversion, so compare regions *within one capture* rather than against a token's hex; a translucent material picks up the wallpaper, so scan horizontally too, and move the window to tell a material from a flat colour; and make sure Quill is frontmost (`osascript -e 'tell application "Quill" to activate'`) before capturing, or you measure another window — note that a prominent button renders grey when its window is not key, which is standard AppKit and not a defect.

## Cross-cutting gotchas that apply here

Full text: `docs/gotchas.md`.

- **The toolbar-wide fade on inspector toggle is an implicit `sublayers` CATransition on the toolbar's glass hosting view, and `InspectorTitlebarFix` nulls that action**
- **A split item's default uncollapse grows the split view instead of shrinking its siblings, so `SplitItemCollapseFix` sets `collapseBehavior = .useConstraints` on the sidebar and the inspector**
- **SwiftUI leaves a split item's size free in the layout engine, so `SplitItemSizePin` pins the detail column and the editor pane to their frames**
- **Re-expanding the inspector needs `InspectorTitlebarFix`, or the panel stops below the toolbar**
- **A view placed in an `.inspector` must not set its own width**
- **Color tokens & surface components**
- **`Color.wpContentSurface` and `editor.html`'s page colour are one value in two files and must move together**
- **`SectionLabel` is the one heading above an inspector or sheet section**
- **Sheet actions go in a bottom bar, never in a top header row**
- **Each kind of feedback has one job: alert, editor banner, toast, inline error**
- **Inputs are system `.roundedBorder` fields; only a list gets a hand-drawn surface**
