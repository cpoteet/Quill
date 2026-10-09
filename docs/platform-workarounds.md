# Platform workarounds

Code that exists only because macOS, AppKit, SwiftUI or WebKit misbehaves. If Apple fixes the underlying bug, the code can go. This file is the list to work through when asking "are our workarounds still needed?", typically after a macOS major or point release.

Design rules that merely look odd (Quill's own sidebar toggle, the AppKit search field, the custom section picker) are not listed. They exist because the system control can't do what the design needs, not because of a bug. Their reasons are in `Sources/QuillKit/Views/Sidebar/CLAUDE.md`.

## How to check one

1. Comment out or bypass the workaround. Change nothing else.
2. Build with the command in the root `CLAUDE.md`, then run the entry's test on a new local draft.
3. If the bug is gone, delete the code and its gotcha entry (the entry names where that is), then move the workaround to **Retired** below with the macOS version and commit.
4. If the bug is still there, restore the code and update **Last checked**.

Run every test with real clicks, with Quill frontmost. Background computer-use clicks miss the web view and do not focus AppKit fields (`docs/gotchas.md`). Several of these bugs only show for one or two frames. Confirm them with a screen recording (`screencapture -v`) read frame by frame, cropped to the region the bug affects. Looking at the screen is not enough.

## Active

### Inspector panel stops below the toolbar on reopen

- **Bug:** after the first open, AppKit keeps the editor pane's titlebar background at full window width on each reopen. It paints over the top 52pt of the inspector.
- **Code:** `InspectorTitlebarFix.trimContentTitlebar()` in `Views/Editor/InspectorTitlebarFix.swift`. It is attached in `PostEditorView`'s `.inspector` content.
- **Test:** open Post Settings, close it, then open it again. The panel's background must reach the top edge of the window.
- **Detail:** `docs/gotchas.md`, "Re-expanding the inspector needs `InspectorTitlebarFix`".
- **Last checked:** macOS 27.0, 2026-09-19.

### Toolbar fades on inspector toggle

- **Bug:** while the inspector animates, SwiftUI swaps the sublayers of the toolbar's glass hosting view. Core Animation fades that swap in over 0.25s, so every glass toolbar button dims. Another developer reported the same bug as FB24782376 (<https://developer.apple.com/forums/thread/845735>).
- **Code:** `InspectorTitlebarFix.suppressToolbarFade()`, in the same file.
- **Test:** toggle Post Settings with a published post open. Record the toggle and crop to the Preview and Update buttons: their dark-pixel count must not dip.
- **Detail:** `docs/gotchas.md`, "The toolbar-wide fade on inspector toggle".
- **Last checked:** macOS 27.0, 2026-09-19.

### Opening the inspector makes the editor flash blank

- **Bug:** the inspector's split item uncollapses with AppKit's default `preferResizingSplitViewWithFixedSiblings`. The window cannot grow, so the inner split view grows past the window edge. On every animation frame, Auto Layout then squashes the editor pane to its 100pt minimum height and SwiftUI restores it. That squashes the web view from 552pt to 52pt about 15 times per open, and WebKit paints the post body blank on any frame that catches the squash.
- **Code:** `.background(SplitItemCollapseFix(behavior: .inspector))` in `PostEditorView`, placed before `.inspector`. The helper is `Views/SplitItemCollapseFix.swift`.
- **Test:** with text in the editor, record an inspector open. The post text must never vanish, and the text column must narrow over several frames. Without the fix the width does not animate and the text blanks out on about 3 frames. For a more precise check, temporarily log `DroppableWebView.setFrameSize`: the height must stay constant during the open.
- **Detail:** `docs/gotchas.md`, "A split item's default uncollapse grows the split view".
- **Last checked:** macOS 27.0, 2026-10-05.

### Dragging the sidebar back out grows the window

- **Bug:** the same AppKit default as above, on the sidebar item. After a drag-collapse, dragging the sidebar back out adds its width to the window instead of taking it from the detail column.
- **Code:** `.background(SplitItemCollapseFix(behavior: .sidebar))` in `SidebarView`.
- **Test:** in a 900pt window, drag the sidebar closed, then drag it back out. The window width must not change.
- **Detail:** `Sources/QuillKit/Views/Sidebar/CLAUDE.md`, the `SplitItemCollapseFix(behavior: .sidebar)` entry.
- **Last checked:** macOS 27.0, 2026-10-05.

### Toolbar dims when a post opens

- **Bug:** the automatic toolbar backdrop fades in and out on each view-graph update. A post load makes several updates, so the toolbar dimmed for about 200ms twice per open.
- **Code:** `.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)` on `ContentView`.
- **Keep regardless:** this modifier also lets each column's background reach the top of the window, which the design depends on. Removing it changes the look, even if Apple fixes the fade. Test it only if the design itself is changing.
- **Detail:** `Sources/QuillKit/Views/CLAUDE.md`, the `.toolbarBackgroundVisibility` entry.
- **Last checked:** macOS 27.0, 2026-09-19.

### Sidebar width is not restored between launches

- **Bug:** SwiftUI's split-view autosave key embeds a framework address that changes between boots and rebuilds, so the saved width gets lost.
- **Code:** `sidebarWidthKey`, `launchSidebarWidth` and the `onGeometryChange` writer in `ContentView`.
- **Test:** remove the custom save, drag the sidebar to about 295pt, quit, rebuild, and relaunch. The sidebar must come back at 295pt. It also has to survive a reboot before the bug can count as fixed.
- **Detail:** `Sources/QuillKit/Views/Sidebar/CLAUDE.md`, the `.navigationSplitViewColumnWidth` entry.
- **Last checked:** macOS 27.0, 2026-10-05.

### Search field takes focus at launch and keeps it

- **Bug:** AppKit gives first responder to the only focusable control in a SwiftUI window. Clicking a SwiftUI `List` row doesn't take focus back, so the search field keeps it.
- **Code:** the `refusesFirstResponder` toggle in `ClickToFocusSearchField`, `Views/Sidebar/SidebarSearchField.swift`.
- **Test:** launch the app. The search field must not have focus, one click must focus it, and Tab must reach it.
- **Detail:** `Sources/QuillKit/Views/Sidebar/CLAUDE.md`, the `ClickToFocusSearchField` entry.
- **Last checked:** macOS 27.0, 2026-09-20.

### `NSOpenPanel` cancels itself during a SwiftUI update

- **Bug:** `runModal()` called inside a view-graph update returns `.cancel` after about 0.3s, and no panel ever appears.
- **Code:** the `DispatchQueue.main.async` hop in `MediaLibraryView.startUpload()`.
- **Test:** call `uploadFromDisk()` directly, then use File → New Media. The open panel must appear.
- **Detail:** `Sources/QuillKit/Views/Media/CLAUDE.md`, the `NSOpenPanel.runModal()` entry.
- **Last checked:** macOS 27.0, 2026-09-19.

### An AppKit callback cannot open `.inspector(isPresented:)`

- **Bug:** setting the inspector flag from an AppKit callback updates the value, but SwiftUI never presents the inspector.
- **Code:** `appState.triggerShowMediaDetails` and its `.onChange` in `MediaLibraryView`.
- **Test:** make "Show Details" set `isMediaInspectorOpen` directly. The media inspector must open.
- **Detail:** `Sources/QuillKit/Views/Media/CLAUDE.md`, the "AppKit callback" entry.
- **Last checked:** macOS 27.0, 2026-09-19.

### Text fields in a reorderable `List` row barely take clicks

- **Bug:** in a `List` row with `.onMove`, the drag gesture claims mouse-down before the `TextField` can.
- **Code:** `.moveDisabled(expandedIDs.contains(sel.id))` in `GallerySheet`, plus the hover-cursor and collapse-on-hover logic that depends on it.
- **Test:** remove `.moveDisabled`, open the gallery sheet, expand a selected image and click its alt-text field. The field must focus on the first click.
- **Detail:** `Sources/QuillKit/Views/Media/CLAUDE.md`, the "`TextField` inside a `List` row" entry.
- **Last checked:** before macOS 27, 2026-08-13. The fix may already be unnecessary.

### WebKit drops keystrokes next to a widget decoration

- **Bug:** a `contenteditable="false"` widget next to the caret makes WebKit discard every character typed. Chromium and jsdom don't show the bug.
- **Code:** the `is-untitled` placeholders in `editor.html`, drawn with `::before`/`::after` instead of a `Decoration.widget`.
- **Keep regardless:** the CSS version is simpler than the widget it replaced. Revisit it only if a future feature needs a real widget decoration next to the caret.
- **Detail:** `docs/editor-gotchas.md`, "A widget decoration next to the caret".
- **Last checked:** before macOS 27, 2026-09-12.

### Section picker button slides up after leaving an open inspector

- **Bug:** when a section switch removes the view that owns an open inspector, SwiftUI removes the inspector's split item. In that same layout pass, AppKit places the sidebar's split item at its collapsed position (`{-260, 0}`) and sizes its `NSGlassEffectView` and hosting view to their fitting height (147pt instead of the window's 672pt). The next pass restores them. The newly selected picker segment is the only view with real glass, and its glass animates from the transient position, so it slides up into place. Our own `SplitItemCollapseFix` is not involved: the pass happens without it.
- **Code:** `AppState.switchSection(to:then:)`. It closes both inspectors with animations disabled (`isMediaInspectorOpen`, and `inspectorCloseToken`, which `PostEditorView` watches), then changes the section 10ms later, so the close and the switch land in separate layout passes. The sidebar picker, the + menu and the File menu all switch sections through it.
- **Test:** open Media, select an image, open Media Info, click Posts. The Posts segment must appear in place, with no slide. Repeat from a post with Post Settings open, clicking Media, and with + ▸ Upload Media…. To bypass the workaround, set `selectedSection` directly instead of calling `switchSection`. For a precise check, log the sidebar `NSGlassEffectView`'s frame: it must never drop below the window height.
- **Detail:** `Sources/QuillKit/Views/Sidebar/CLAUDE.md`, "Section switches go through `AppState.switchSection`".
- **Last checked:** macOS 27.0, 2026-10-08.

## Retired

- **`Picker` appearance workaround** — removed in `4bc933a` once macOS 27 fixed the stale appearance (`docs/superpowers/plans/2026-09-18-native-ui.md`, Task 9).
