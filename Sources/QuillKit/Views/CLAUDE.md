# Top-level views (ContentView)

Implementation gotchas specific to this directory, split out from the project root `CLAUDE.md` (2026-07-11) to keep the root file lazy-loaded. See the root `CLAUDE.md` for architecture, build/test commands, and cross-cutting conventions.

## Known gotchas

- **Layout uses `HStack + SoftPanelBoundary`, not `NavigationSplitView` or `HSplitView`** — `ContentView` uses a plain `HStack(spacing: 0)` with `SoftPanelBoundary()` between the sidebar/editor and editor/settings-panel boundaries (replaces `Divider()`). `NavigationSplitView` reinstates macOS Tahoe sidebar chrome (drop shadows, raised layer). `HSplitView` renders a draggable resize cursor on panel dividers even when frames are fixed. Do NOT switch to either.
