# Handoff — native-ui branch

**Status as of 2026-09-18: every task in the plan is implemented and committed.**
What remains is a human manual pass and whatever touch-ups come out of it.

Paste the block below as the first message of the new conversation.

---

Continue work on the `native-ui` branch in /Users/Chris/Documents/Claude/WP Mac App.

The implementation plan at docs/superpowers/plans/2026-09-18-native-ui.md is
complete — Tasks 1 through 9 are all committed. We are now doing touch-ups.

Read this file and the plan before touching anything. The plan's Task 7.5 and
Task 8 were rewritten mid-execution when their original premises turned out to
be wrong; the plan records what actually happened and why.

---

## What is done

Tasks 1–9, all committed on `native-ui` (local only, **never pushed**):

  7d3eff4  build: target macOS 27 only
  9d6076d  refactor: let macOS draw the title bar
  e12df04  refactor: adopt the Swift 6 language mode
  5f2424c  refactor: rebuild the window on NavigationSplitView
  e4f3373  refactor: move every action into the window toolbar
  1384bc0  refactor: put the settings and evaluation panels in a real inspector
  a55d6a1  refactor: drop the warm surfaces for system materials
  c981e91  refactor: native styling for preferences, about and the sheets
  4e0ad16  refactor: drop the custom accent for the user's system accent
  7913e0d  style: match the editor surface to the native content background
  de13159  style: run each column's background to the top edge, as Mail does
  4bc933a  refactor: drop the Picker appearance workaround

Tests: 428 Swift + 1,202 JS (1,201 pass, 1 deliberately skipped, 0 fail).
Real-WebKit fixture check: 21/21.

## What is NOT done

**The manual pass in the plan's "Final verification" section.** Everything an
agent could verify has been verified; these need a human because background
computer-use cannot reach them:

  - inspector resize (synthetic drags are not honoured by native split dividers)
  - image drop into the editor, and the upload pill / toast
  - anything behind the editor's HTML toolbar: gallery sheet, image picker,
    link picker (⌘K), AI generate sheet, AI result panel, evaluation panel
  - full-screen enter/exit
  - a real publish round-trip

The appearance switch and both pickers *were* verified during Task 9.

**Three leftover empty "Untitled" drafts** in the sidebar from verification runs
(ids 168, 169, 170 in `local_drafts`). 168 predates this work. Right-click →
Delete Draft is the way; deleting rows from `drafts.db` is blocked as an
irreversible local delete.

## Decisions reversed during execution — do not re-litigate

1. **The app has no accent colour of its own.** The spec said Quill's identity
   moves to an amber accent. That was abandoned: `NSAccentColorName` only wins
   while the user's System Settings accent is "Multicolour", so the amber was
   invisible to anyone who had picked an accent, and it failed macOS's
   prominent/disabled button rendering (2.14:1 against white). The
   `AccentColor` asset, the `actool` step, the plist key and the app-wide
   `.tint` are all deleted. `Color.accentColor` is now the token for selection,
   focus and actions. Semantic colours (status dots, warnings) must **never**
   be the accent. `Color.wpAmber` no longer exists.

2. **`.toolbarBackground(.hidden, for: .windowToolbar)` is back.** Task 2
   deleted it; Task 8's follow-up re-added it. Not a regression — Task 2 removed
   it because it propped up the hand-built title bar, and it returns for an
   unrelated reason: it is what lets each column's background reach the top edge
   of the window, which is how Mail is built.

3. **The `Picker` appearance workaround is gone.** macOS 27 fixes the stale
   `NSAppearance` stamp. Verified with the modifier reduced to a true no-op that
   never reads `colorScheme` — note that blanking only the `.id(colorScheme)`
   line is *not* a valid probe, because the surviving `@Environment` property
   makes SwiftUI rebuild the subtree anyway and reports a false pass.

## Traps that cost real time here

- **`NSColor.textBackgroundColor` is the wrong dark value for the editor
  surface.** It reports `#1E1E1E`, the flat token; a `NavigationSplitView`
  detail column actually renders a material compositing to about `#242124`.
  Trusting the token made the editor visibly darker than the rest of the window.
  Sample rendered pixels instead. Mail is the reference: `#252123` content
  against a `#2C2529` sidebar.
- **`Color.wpContentSurface` (DesignSystem.swift) and `editor.html`'s `body` /
  `--toolbar-bg` / `#editor-wrap` are one colour declared in two files.** They
  must move together or the title field steps against the webview.
- **Never judge a colour from a downsampled screenshot.** Native-resolution
  `screencapture -o -l <windowID>` plus a pixel scan. Scan horizontally as well
  as vertically, and move the window, to tell a translucent material from a flat
  colour.
- **A prominent button renders grey when its window is not key.** Standard
  AppKit. Front the app before judging any colour.
- **The system appearance may be on Auto**, which silently undoes an `osascript`
  toggle. Re-read `defaults read -g AppleInterfaceStyle` after setting it.
- **`swift build` does NOT compile the test target.** Use `--build-tests`.
  Build with `-c release` to type-check the whole module in one pass, and never
  mix release and debug in one `.build` tree.
- **A crashed Swift test process looks like failures**: every test prints
  "started" and none prints "passed". Re-run with `--no-parallel`; the last test
  to print "started" is the culprit.

## Still stale, flagged but not fixed

`Sources/QuillKit/Views/AI/CLAUDE.md` carries a rule that buttons inside a
transparent `NSPanel` need `.plain` with an explicit background. Task 7 converted
the AI result bar to `.borderedProminent` on `.regularMaterial`, so the cited
example no longer exists and the rule may be obsolete. The dead `Color.wpAmber`
reference is removed and the staleness is noted in place. Confirming or deleting
the rule needs a human who can open the AI result panel.

## Hard constraints

- Work on `native-ui`. Never commit to `main`.
- Rebuild and relaunch after every change:
  `osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app`
  `build.sh` swaps the binary under a running process, so skipping the quit
  shows you the old app.
- Test on a NEW local draft ("+ New Post"), never a published post or page.
- Comments: default to none. Delete the comment when you delete the code it
  explains. No narration comments.
- Do not commit unless asked.
