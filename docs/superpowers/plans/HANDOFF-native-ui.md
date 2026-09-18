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

The plan argues from the spec, so you need both. The spec's "Findings from the
native spike" section records decisions that were already tested and settled —
treat them as closed, not as open questions to re-explore. The plan has been
kept up to date as tasks completed: finished steps are checked off, each
finished task ends with a "**Done.** Committed as ..." line, and several steps
were corrected in place. Trust the plan over the spec where they differ.

## What is already done

Tasks 1, 2 and 2.5 are complete and committed on `native-ui`:

  e12df04  refactor: adopt the Swift 6 language mode
  9d6076d  refactor: let macOS draw the title bar
  7d3eff4  build: target macOS 27 only

Start at **Task 3: Convert the layout to NavigationSplitView**.

Task 2.5 was not in the original plan. It was inserted because Task 1 had to
bump swift-tools-version to 6.4 to reach .macOS(.v27), which flips the default
language mode to Swift 6. Task 1 pinned the mode back to v5; Task 2.5 removed
the pins and fixed the 20 lines of strict-concurrency fallout. The project now
compiles in Swift 6 language mode, so write all new code under Swift 6 rules.

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
  - One commit per task, using the commit message given in the plan.
  - Comments: default to none. When you delete code that a comment explains,
    delete the comment. Don't add narration comments about the refactor.
  - You may toggle the system appearance with osascript to run the light/dark
    checks. I have already authorised this. Always toggle back to light when
    the check is done.

## Resolve this before starting Task 3

`Sources/QuillKit/Views/CLAUDE.md` contains a gotcha that flatly forbids Task 3:

  "Layout uses HStack + SoftPanelBoundary, not NavigationSplitView or
   HSplitView — NavigationSplitView reinstates macOS Tahoe sidebar chrome
   (drop shadows, raised layer) ... Do NOT switch to either."

The spec's design spike tested NavigationSplitView on macOS 27 and chose it, so
the spec supersedes this note. But confirm the drop-shadow and raised-layer
symptoms do not reappear on macOS 27 before you delete the gotcha. If they do
reappear, stop and tell me — that is a real conflict between the spike and this
file, not a stale note.

That same file also holds six title-bar gotchas that Task 2 made obsolete. They
get deleted in the final docs pass, not now.

## Three things in the plan that are easy to lose

  1. Task 3: .searchable must be applied BEFORE
     .navigationSplitViewColumnWidth. Reversed, the width silently never
     reaches the column and the sidebar collapses to ~144pt.
  2. Task 4: the deleted toolbar row held TWO separate ⌘S bindings — a visible
     "Save Draft" for local drafts and an invisible button routing ⌘S to
     publish() for remote posts. Both must survive.
  3. Task 9 may correctly end in "no change." That's a success, not a failure.

## Things found the hard way, so you don't repeat them

  - `swift build` does NOT compile the test target. Use
    `swift build --build-tests` when you need to know whether Tests/ compiles.
    Sizing the Swift 6 migration without this understated it by more than half.
  - A debug build stops at the first failing file and hides the rest. Build with
    `-c release` to type-check the whole module in one pass and see every error
    at once. Do not mix release and debug in the same .build tree — it produces
    a bogus "unable to resolve Swift module dependency" error.
  - Under Swift 6, SwiftUI's View and WebKit's WKNavigationDelegate are
    @MainActor, so static members of conforming types inherit that isolation.
    Because both protocols are @preconcurrency, nonisolated callers still
    compile and then trap at runtime. Symptom: the suite reports failures while
    every test prints "started" and none prints "passed". That is a crashed
    process, not a failed test. Re-run with `swift test --no-parallel` and the
    last test to print "started" is the culprit.
  - Test counts are 428 Swift and 1,202 JS. CLAUDE.md and the original plan both
    said 1,201. The figure had drifted; correct it in the final docs pass.
  - Background computer-use right-click is refused, so the sidebar's "Delete
    Draft" context menu is not reachable that way. To discard a test draft,
    quit Quill and delete the row from
    ~/Library/Application Support/Quill/drafts.db, table `local_drafts`.
    The `autosaves` table is keyed by remote post_id and is unrelated.
  - `QuillApp.swift` already declares BOTH a Settings scene (line ~97) and the
    preferences .sheet (line ~44). The spec argues for keeping the sheet as
    though it were an open choice; it is already the status quo. Task 7 only
    restyles PreferencesView's interior, which serves both. No action needed.

## Settled decisions carried forward

  - Task 4's status dot uses the key expression lifted from the deleted
    `statusBadge` property, not the plan's original two-way ternary. The plan
    has been corrected in place and explains why. The ternary collapsed four of
    the six status colours into amber.
  - Task 4 must also fix `SidebarEmptyState.hint`, which tells the user to
    "Create one with the + button below" for Posts, Pages and Media. Task 4
    moves that button into the toolbar, so "below" becomes wrong.

## If the plan is wrong about the codebase

Stop and tell me rather than improvising around it. Four such errors have been
caught so far — two during planning, two during execution.
