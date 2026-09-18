# Session prompt — Gutenberg block model

Copy the block below into a **fresh conversation**. Replace `<SCOPE>` with what you want done, e.g.:

- `Task 4`
- `Tasks 1-3`
- `Phase 2`
- `the next unchecked task`

---

```
Work on the Quill Gutenberg block model rewrite.

SCOPE THIS SESSION: <SCOPE>

Branch: gutenberg-block-model (create it from main if it doesn't exist; never work on main)
Plan:   docs/superpowers/plans/2026-09-11-gutenberg-block-model.md
Spec:   docs/superpowers/specs/2026-09-11-gutenberg-block-model-design.md

Read BOTH before touching code. The plan's steps assume the spec's reasoning —
when a step looks wrong or underspecified, the spec is what tells you why it's
written that way.

HOW TO START
1. Read the plan's "Global Constraints" section. It is not optional context.
2. Find my scope in the plan. If I said "the next unchecked task", scan for the
   first `- [ ]` and start at the task that contains it.
3. Confirm the earlier tasks it depends on are actually done — check the code,
   not just the checkboxes. A ticked box with missing code means someone got
   interrupted; tell me rather than building on top of it.
4. Tell me which task(s) you're doing and what the first step is. Then go.

HOW TO WORK
- Follow the steps in order. They're deliberately TDD: write the failing test,
  RUN it and confirm it fails for the stated reason, then implement, then run
  again. Do not skip the "verify it fails" step — a test that passes before the
  implementation exists is testing nothing.
- Tick each `- [ ]` to `- [x]` in the plan file as you complete that step.
- Commit at each task's commit step, using the message the plan gives. Append:
  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
- Stop at the end of my scope. Don't roll into the next task.

THE PLAN WILL BE WRONG SOMEWHERE
It was written in advance without running anything. Expect some code not to
work as written. When that happens: fix it, and TELL ME what differed and why.
Never silently deviate, and never edit a test to make a failing implementation
pass. If a step's premise is wrong (an API doesn't behave as assumed, a file
isn't shaped as described), stop and say so before writing a workaround.

NON-NEGOTIABLES
- Round-trip byte-identity outranks every feature. A post loaded and saved with
  no edits must produce byte-identical post_content. If a change breaks this,
  it's wrong no matter what else it delivers.
- Every new file in Sources/QuillKit/Resources/ needs its own `cp` line in
  build.sh (lines 29-33). Swift builds fine and jsdom tests pass without it;
  it only shows up as a silently undefined global in the running app.
- Never edit Scripts/bundle-tiptap.sh. Its "^2" pin re-resolves Tiptap on every
  run and can drift the editor onto a newer release.
- Comment-stripping regexes use [\s\S]*?, never .*? or [^\n]*. Both of the
  others have shipped as silent data-loss bugs in this file.
- Nothing in this project converts, migrates, or rewrites existing published
  posts. That's an explicit non-goal.
- Don't touch the image, gallery, or embed comment-wrapping in
  editor-transforms.js. Those already emit correct delimiters.

BEFORE CLAIMING ANYTHING IS DONE
Run ./test.sh and show me the actual output. Not "tests pass" — the output.
If anything fails, say so plainly and stop. For tasks with a build step, run:
  osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app
and report the real result.

If a task asks you to check something in the running app, test on a NEW LOCAL
DRAFT (click "+ New Post"). Never on a published post or page.

WHEN YOU FINISH
Report: which tasks are done, what the test output was, what deviated from the
plan and why, and what the next unchecked task is. Don't commit anything I
didn't ask for, and don't push.
```

---

## Suggested session sizes

| Session | Scope | Why |
|---|---|---|
| 1 | `Tasks 1-3` | One arc: bundle, serialize, prove the round-trip. Task 3 is the safety net everything else leans on. |
| 2 | `Tasks 4-5` | Descriptors then delimiters. Ends with the classic-post problem actually fixed — verify in Gutenberg before moving on. |
| 3 | `Task 6` | Columns alone. It establishes the container pattern the next four copy, so it's worth its own session. |
| 4 | `Tasks 7-8` | Details and Buttons, both small once Columns exists. |
| 5 | `Task 9` | Accordion — four block types, the most intricate. |
| 6 | `Task 10` | Tabs. Starts by capturing real markup from your site; don't let it skip that. |
| 7 | `Tasks 11-12` | Insert menu plus Pullquote/Preformatted. |

Stop after session 2 and use the app for a while before starting Phase 3 — that's the natural checkpoint. Phase 3 is additive, and everything in it is optional.
