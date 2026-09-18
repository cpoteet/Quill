# Handoff — native-ui branch

Paste the block below as the first message of the new conversation.

---

Continue executing the implementation plan at
docs/superpowers/plans/2026-09-18-native-ui.md in
/Users/Chris/Documents/Claude/WP Mac App.

Use the superpowers:executing-plans skill. Work task by task, in order, and
stop after each task for my review before starting the next.

Read all three documents before you touch anything:
  - the plan:  docs/superpowers/plans/2026-09-18-native-ui.md
  - the spec:  docs/superpowers/specs/2026-09-18-native-ui-design.md
  - this file: docs/superpowers/plans/HANDOFF-native-ui.md

The plan argues from the spec, so you need both. Trust the plan over the spec
where they differ. The plan is kept current: finished steps are checked off,
each finished task ends with a "**Done.** Committed as ..." line, and several
steps were corrected in place after they turned out to be wrong.

The spec's "Findings from the native spike" section is NOT fully reliable. Two
of its claims were tested during execution and proved false. See "Where the
spec is wrong" below.

## What is already done

Tasks 1 through 7 are complete and committed on `native-ui`:

  7d3eff4  build: target macOS 27 only
  9d6076d  refactor: let macOS draw the title bar
  e12df04  refactor: adopt the Swift 6 language mode
  5f2424c  refactor: rebuild the window on NavigationSplitView
  e4f3373  refactor: move every action into the window toolbar
  1384bc0  refactor: put the settings and evaluation panels in a real inspector
  a55d6a1  refactor: drop the warm surfaces for system materials
  c981e91  refactor: native styling for preferences, about and the sheets
  0839aab  docs: add Task 7.5 for the washed-out buttons and the last amber washes
  753b11f  docs: cross-reference Task 7.5 from Tasks 6 and 7

Start at **Task 7.5: Darken the accent and clear the last amber washes**.

Task 7.5 was added after Task 7, in response to a bug report with screenshots.
It is fully written up with measurements and exact values. Do not re-derive it.

Remaining after that: Task 8 (webview colours), Task 9 (the Picker workaround),
and a final docs pass.

## Hard constraints

  - Work on the `native-ui` branch. Confirm it before your first edit. Never
    commit to main.
  - This is a view-layer refactor with no meaningful unit-test coverage. The
    plan explains why it isn't TDD and what the verification cycle is instead.
    Follow that cycle; don't invent view tests to satisfy a TDD shape.
  - Rebuild and relaunch after every task:
      osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app
    build.sh replaces the binary under a running process, so skipping the quit
    shows you the old app and no visible change.
  - Do all manual testing on a NEW local draft ("+ New Post"), never on a
    published post or page, and discard it when done.
  - One commit per task, using the commit message given in the plan. If the
    plan's message asserts something you found to be false, rewrite it and say
    so — this has already happened twice.
  - Comments: default to none. When you delete code that a comment explains,
    delete the comment. Don't add narration comments about the refactor.
  - You may toggle the system appearance with osascript to run the light/dark
    checks. I have already authorised this. Always toggle back to light when
    the check is done.

## Where the spec is wrong

The spec's spike section records four findings about `.tint(.wpAmber)`. Two are
false, and Task 6 proved it in the running app:

  - **"`.tint` reaches the OS-drawn sidebar selection."** It does not. The
    capsule stayed system blue both with the tint at the app root and with it
    applied directly to the `List`. macOS draws the focused sidebar selection
    from the *system accent*. The fix was an `AccentColor` asset compiled by
    `actool`, plus `NSAccentColorName` in the Info.plist. Both now live in
    `build.sh`, and `Assets.xcassets/` is a new top-level directory.
  - **"`.tint` drives the selected picker segment."** It does not, even with the
    accent asset. The segmented picker draws a neutral grey pill on macOS 27.
    That is the system design. Accept it.

The other two hold: `.glassProminent` adopts the accent, and warm surfaces were
correctly rejected.

Consequence for new code: **every explicit `.tint(Color.wpAmber)` is now a
no-op**, because the app accent is already amber. Task 7 removed the ones it
found. Don't add more.

`NSAccentColorName` wins only while the user's System Settings accent is
"Multicolour". Chris's is. If a user picks a specific accent, macOS applies
their choice to every app. That is correct behaviour, not a bug.

## What computer-use cannot reach, and what that means

Background computer-use clicks do not reach the WKWebView's DOM handlers (see
`docs/gotchas.md`). Everything opened from the editor's HTML toolbar is
therefore unreachable from an agent session:

  - the gallery sheet and the image picker
  - the link picker (⌘K)
  - the AI generate sheet and the AI result panel
  - the evaluation panel

Background synthetic drags are also not honoured by native split dividers, so
the inspector's resize cannot be verified from a session either.

Do not claim these are verified. Write the user a short numbered test list
instead and wait. That worked well for Task 5 — Chris ran it and reported back.
The three buttons reported in Task 7.5 were found exactly this way.

## Things found the hard way, so you don't repeat them

  - `swift build` does NOT compile the test target. Use
    `swift build --build-tests` when you need to know whether Tests/ compiles.
  - A debug build stops at the first failing file and hides the rest. Build with
    `-c release` to type-check the whole module in one pass. Do not mix release
    and debug in the same .build tree — it produces a bogus "unable to resolve
    Swift module dependency" error.
  - Under Swift 6, SwiftUI's View and WebKit's WKNavigationDelegate are
    @MainActor, so static members of conforming types inherit that isolation.
    Because both protocols are @preconcurrency, nonisolated callers still
    compile and then trap at runtime. Symptom: the suite reports failures while
    every test prints "started" and none prints "passed". That is a crashed
    process, not a failed test. Re-run with `swift test --no-parallel` and the
    last test to print "started" is the culprit.
  - Test counts are 428 Swift and 1,202 JS. CLAUDE.md and the original plan both
    said 1,201. Correct it in the final docs pass.
  - `Section(_ titleKey:content:)` has no `footer:` overload. Use the explicit
    `Section { } header: { } footer: { }` form.
  - A prominent button renders grey when its window is not key. That is standard
    AppKit, not a defect. Front the app with `open -a Quill` before judging any
    accent colour from a screenshot.
  - Background computer-use right-click is refused, so the sidebar's "Delete
    Draft" context menu is not reachable that way. To discard a test draft,
    quit Quill and delete the row from
    ~/Library/Application Support/Quill/drafts.db, table `local_drafts`.
    The `autosaves` table is keyed by remote post_id and is unrelated.
  - There is one empty untitled draft (id 168) left in `local_drafts` from
    testing. I did not create it, so I did not delete it. Ask before removing.
  - `QuillApp.swift` declares BOTH a Settings scene and the preferences .sheet.
    The spec argues for keeping the sheet as though it were an open choice; it is
    already the status quo. ⌘, opens the Settings scene and works. No action.

## Settled decisions carried forward

  - Section switching clears the selection through the `Picker`'s own binding,
    NOT an `.onChange(of: appState.selectedSection)`. The observer also fires
    when `AppState.createNewDraft` switches the section itself, which wiped the
    draft it had just selected and left ⌘N producing a draft the editor would
    not open. The plan's Task 4 Step 2 is corrected in place.
  - The status dot uses the key expression lifted from the deleted `statusBadge`
    property, not a two-way ternary. The ternary collapsed four of the six
    status colours into amber.
  - `PostListRow` no longer paints its selected title. The `List` inverts the
    label itself. Its `isSelected` property is deleted.
  - The `Views/CLAUDE.md` gotcha forbidding `NavigationSplitView` is deleted. The
    drop-shadow and raised-layer symptoms do not reproduce on macOS 27; the
    sidebar boundary is a flat edge. Verified before deleting.
  - `Views/CLAUDE.md` still holds six title-bar gotchas that Task 2 made
    obsolete. They come out in the final docs pass, not before.

## If the plan is wrong about the codebase

Stop and tell me rather than improvising around it. Six such errors have been
caught so far — two during planning, four during execution.
