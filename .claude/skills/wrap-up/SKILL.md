---
name: wrap-up
description: Use when done with a session of Quill changes and want to run the standard end-of-session checklist. Pass 'deploy' as an argument to also package Quill.zip for distribution.
---

# Wrap-Up (Quill)

## Overview

Standard end-of-session checklist for the Quill project. Ensures work is committed, tests pass, code is reviewed, docs are current, and the app is rebuilt. Add `deploy` to also package a release ZIP.

**Announce at start:** "Running wrap-up checklist."

## Invocation

```
/wrap-up          # standard checklist
/wrap-up deploy   # standard checklist + package Quill.zip
```

## Cost discipline

This checklist usually runs over a multi-day branch, so the diff can be large. Cost comes from what sits in the main conversation, because everything there is re-billed on every later turn. Three rules govern every step below:

1. **The main conversation never reads a large file whole.** `docs/testing-plan.md` (~3,300 lines), `site/docs.html` (~860), the `Scripts/test-*.js` suites (up to ~2,600) and `editor.html` (~6,200) are reached by `grep -n` for the relevant section, then `Read` with `offset`/`limit`. A whole-file read there costs its size on *every subsequent turn* of the run, not once. Subagents are different: their context is discarded when they return, so each brief says what that subagent may read whole. Don't cap a subagent's reads to save usage when the cap would make it miss something.
2. **Broad file sweeps go to a subagent.** When a step needs to survey many files (the test-coverage audit, the multi-section `testing-plan.md` edit), dispatch a subagent with a self-contained brief and take back only its summary. The files never enter the main conversation, so they are never re-billed.
3. **Review the diff once.** The diff is analyzed in Step 6 and nowhere else. Do not re-read source files in later steps to "double-check" — that is the single largest source of waste in this checklist.

---

## Step 0 — Scope the work and pick a lane

The range to wrap up runs from the last wrap-up to `HEAD`. Step 9 marks the end of each run with the local tag `wrap-up-last`; when it doesn't exist (a fresh clone, or the first run), fall back to the latest release tag.

```bash
git status --short
BASE=$(git rev-parse -q --verify wrap-up-last || git describe --tags --abbrev=0 --match 'v*')
echo "BASE=$BASE ($(git log -1 --format='%h %s' "$BASE"))"
git log --oneline "$BASE"..HEAD
git diff --stat "$BASE" HEAD
```

Every later step that diffs uses `"$BASE"` exactly as set here; re-set it with the same line if the shell lost it.

Classify the work into one lane and **say which lane you picked and why**:

| Lane | Trigger | Steps to run |
|------|---------|--------------|
| **A — Docs only** | Only `docs/`, `README`, comments, or version strings changed. No behavior change. | 1, 2, 9, 10 |
| **B — Small change** | Source changed, under ~150 lines, confined to one area, no new functions/nodes/files and no new user-facing capability. | 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 |
| **C — Feature** | New functions, new Tiptap nodes, new files, new user-facing capability, or a change touching Gutenberg HTML round-tripping. | All steps |

When in doubt between B and C, pick C. When in doubt between A and B, pick B.

**Working directory for all steps:** `/Users/Chris/Documents/Claude/WP Mac App`

### Step 1 — Commit & push pending work

Stage and commit any uncommitted changes from `git status --short` above, then push if there are unpushed commits. Review what you're staging before you stage it.

### Step 2 — Summarize the commits since `BASE`

From the `git log` output already in context, summarize what changed, one bullet per distinct feature or fix. Do not re-run git commands for this.

### Step 3 — Test-coverage audit *(lanes B, C — dispatch a subagent)*

Dispatch **one subagent** with a self-contained brief. Do not do this sweep in the main thread — it requires reading multiple test files that would then sit in context for the rest of the run.

The brief must include: the value of `$BASE` and this instruction:

> Run `git diff "<BASE>" HEAD -- Sources/` and read the whole diff. For every changed function or logic path under `Sources/QuillKit/` — the Swift sources and every file in `Resources/` (`editor.html`, `editor-transforms.js`, `block-descriptors.js`, `block-settings.js`, `block-serializer.js`) — locate the corresponding tests. The suites are every file `test.sh` runs (`grep -o 'Scripts/test-[^ ]*\.js' test.sh`) plus `Tests/QuillTests/`; a change can be covered by a suite whose name doesn't match it, so search all of them. Grep by function and fixture name first; read a test file whole when grepping doesn't show you whether the behavior is covered. Read them and judge whether they cover the changed behavior *structurally* — asserting output shape and ordering, not merely that a string appears somewhere. Write new or strengthened tests where coverage is missing or shallow. Changes to `editor.html`'s embedded JS are usually paired with `editor-transforms.js` — check both. Tests written in the same session as the feature they cover are themselves suspect; evaluate them as you would any pre-existing test. Report back only: which tests you added or changed, and which changed paths you judged already covered.

Take back the summary. Do not re-read the test files yourself.

### Step 4 — Run all tests *(lanes B, C)*

```bash
./test.sh
```

### Step 5 — Stop on failure *(lanes B, C)*

If `./test.sh` reports failures: show them clearly and **stop**. Do not continue until they are fixed.

### Step 6 — Single review pass *(lanes B, C)*

Quill's own review, dispatched as subagents. Not `/code-review` or `/security-review`: they review the current or pending diff, and by now Step 1 has committed and pushed everything, so neither has a reliable view of the `BASE..HEAD` range.

**Size the review, and check for sensitive paths:**

```bash
git diff --shortstat "$BASE" HEAD -- Sources/
git diff --name-only "$BASE" HEAD | grep -E 'Sources/QuillKit/(Auth|API|AI)/|editor\.html|CredentialsStore|WordPressClient|AnthropicClient'
```

- **Up to ~1,500 changed lines:** dispatch one reviewer over all of `Sources/`.
- **Over ~1,500:** dispatch three reviewers in parallel, one per area: editor JS (`Sources/QuillKit/Resources/`); Swift views and app code (`Views/`, `App/`, `Storage/`, `DesignSystem.swift`); and services (`API/`, `Auth/`, `AI/`). Each reviews only its area, but gets the full changed-file list.
- **If the grep returns anything,** include the security section in the brief of every reviewer whose area it touches. Otherwise leave it out and say so.

Each brief: the value of `$BASE`, the reviewer's area paths, the output of `git diff --name-only "$BASE" HEAD`, and this instruction (with the security section when it applies):

> Review the changes in `git diff "<BASE>" HEAD -- <area paths>`. Read the whole diff, and open the surrounding code wherever the diff alone doesn't show what a change does.
>
> **Ground yourself in Quill's known failure modes first.** Read the Gotchas list in the root `CLAUDE.md`, the gotcha titles in `docs/gotchas.md`, and the `CLAUDE.md` in every directory your diff touches (`Resources/CLAUDE.md` indexes `docs/editor-gotchas.md`). For each gotcha that applies to a changed file, open its full text and check the diff against it. The ones that fail silently with every test green matter most — a new `Resources/` file with no `cp` line in `build.sh`, a top-level `const` read across the script boundary, a carried attribute replayed onto the live contenteditable, `uploadStatus` written outside `dropTask`, synchronous image work on the main actor.
>
> **Trace behavior, not just structure.** For each changed path, trace three scenarios end-to-end against the actual code: (a) the happy path; (b) the user does *nothing* — enters a mode and immediately exits, saves without editing; (c) repeated use — enters and exits several times, switches posts. Trace variable state explicitly rather than reasoning about what the code is meant to do. Flag any function that unconditionally runs a side effect (e.g. `setContent`) without a no-change guard, and any variable updated on every exit whose second-entry behavior is untraced.
>
> **Check both ends of the bridge.** For any changed `window.webkit.messageHandlers.*` post, message-handler case in `EditorCoordinator`, or `window.*` function Swift calls, find the other end in the changed-file list or the tree and confirm the name and payload shape still match — even when the other end is outside your area.
>
> *(Security section, only when included:)* **Security.** Check how credentials are read, stored, and sent (file permissions, never logged, never in a URL); how request URLs are built from user or server input; anything that reaches the editor's live HTML or `evaluateJavaScript` (script sinks, unescaped interpolation); and whether message-handler input from JS is validated before Swift acts on it.
>
> **Verify before reporting.** For each candidate finding, re-read the code and confirm it with a concrete input or state that produces the wrong result; drop anything you can't confirm. Report each surviving finding as: severity (bug / risk / cleanup), `file:line`, one-sentence defect, and the failure scenario. If you find nothing, say so and list the gotchas you checked against.

Merge the reviewers' findings, dropping duplicates, most severe first.

This is the **only** analysis pass over the diff. After it returns, do not open source files again to re-verify — work from the findings.

### Step 7 — Address issues *(lanes B, C)*

Fix anything the review found. Re-run `./test.sh` after fixes.

### Step 8 — Documentation pass *(lanes B, C — one consolidated pass, after review)*

All doc updates happen here, **after** review, so that a fix from Step 7 doesn't invalidate freshly-written docs.

Dispatch **two subagents** in parallel. The user guide gets its own, because sharing a pass with the testing-plan bookkeeping is how it drifted.

**8a — Testing plan and CLAUDE.md.** Brief: the change summary from Step 2, the test changes from Step 3, and this instruction:

> Update two docs to match the changes since the last wrap-up. Reach every section via `grep -n` and read only that range with offset/limit — never read these files whole.
>
> **`docs/testing-plan.md`** — three things, all of them: (a) add a row per new test to the relevant suite section and update that section's header count; (b) add a row to the regression matrix at the bottom linking each new behavioral guard to the scenario it guards; (c) add manual-checklist items under the relevant §7.x for any new feature or behavior change.
>
> **`CLAUDE.md`** — new gotchas or constraints discovered, architecture changes, new key files or patterns, and the test-count line in the test suite status section.
>
> Report back only a list of the edits you made.

For substantial architectural change, run `claude-md-management:revise-claude-md` instead of the `CLAUDE.md` portion above.

**8b — User guide (`site/docs.html`).** Dispatch it on every lane B or C run; the subagent decides whether anything user-visible changed, not the main thread. Brief: the value of `$BASE`, the change summary from Step 2, and this instruction:

> `site/docs.html` is Quill's user guide, published on the site. It has no Markdown source; edit it directly.
>
> 1. Run `git diff "<BASE>" HEAD -- Sources/` and read the whole diff. List every user-visible change in it: new or removed features, button and menu labels, toolbar icons, keyboard shortcuts, alert and sheet wording, block names, settings, defaults, and what gets saved to WordPress. If there are none, report that with a one-line reason per changed file and stop.
> 2. Otherwise read `site/docs.html` whole. Check every section against your list, not only the sections that look related — the same fact is often stated in several places (the Keyboard Reference, the toolbar tables, the supported and unsupported block lists in Code View and Limitations).
> 3. For each changed label, shortcut, and block name, `grep -n` the old and new spellings across the whole file and fix every hit.
> 4. Add coverage for new capabilities, correct anything that no longer matches, and delete content for things that no longer exist. Write for a new user of the current build; no implementation details. Match the page's existing markup and `docs-*` classes, add a new `h2` to the Contents list, and give a heading an `id` only when something links to it. Every `href="#…"` must still resolve to an `id` on the page.
>
> Report back a line per `h2` section: **updated** (what changed) or **checked, no change needed**.

If 8b reports a section as checked but your Step 2 summary names a change that belongs there, send it back to that section.

### Step 9 — Commit, push, and mark the wrap-up

If steps 3–8 produced changes, stage them, commit, and push. Review what you're staging.

Then move the marker so the next run starts here. It is a local tag; don't push it.

```bash
git tag -f wrap-up-last HEAD
```

Skip the tag if the run stopped early (failing tests at Step 5, unresolved review findings); the next run should cover this range again.

### Step 10 — Rebuild app

Quit the running app first; `build.sh` replaces the binary under a running process, so skipping the quit leaves the old build on screen.

```bash
osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app
```

Confirm the build succeeds. If it fails, report the error and stop.

---

## Deployment step (only when `deploy` argument present)

### Step 11 — Verify in WebKit, then package Quill.zip

Run the fixture check against the Step 10 build. It is the only test that runs in real WebKit, and it catches the WebKit/jsdom divergences every `./test.sh` suite misses. It exits non-zero on a mismatch; if it does, show the report and **stop** — do not package.

```bash
./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"
```

**The name `Quill.zip` is load-bearing.** Every page of the site links to
`https://github.com/cpoteet/Quill/releases/latest/download/Quill.zip`, which GitHub
resolves by asset name against whichever release is marked latest. A ZIP uploaded
under any other name breaks the download button site-wide.

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
rm -f ~/Desktop/Quill.zip
zip -r ~/Desktop/Quill.zip Quill.app LICENSE
```

Report: "Quill.zip created at ~/Desktop/Quill.zip"

### Step 12 — Attach it to the release

Only when cutting a release, not on every deploy. Read `VERSION` from
`CFBundleShortVersionString` in `build.sh`.

```bash
gh release create "v$VERSION" --repo cpoteet/Quill \
  --title "Quill $VERSION" --notes-file NOTES.md ~/Desktop/Quill.zip
gh release edit "v$VERSION" --repo cpoteet/Quill --latest
```

Verify the download link resolves before announcing:

```bash
curl -sIL -o /dev/null -w '%{http_code}\n' \
  https://github.com/cpoteet/Quill/releases/latest/download/Quill.zip
```

Expected: `200`.

---

## Quick Reference

| Step | Action | Lanes | Stop if… |
|------|--------|-------|----------|
| 0 | Set `BASE` from `wrap-up-last`, scope the diff, pick a lane, announce it | all | — |
| 1 | Commit & push pending | all | — |
| 2 | Summarize the commits since `BASE` | all | — |
| 3 | Test-coverage audit (**subagent**) | B, C | — |
| 4 | Run `./test.sh` | B, C | — |
| 5 | Report failures | B, C | Tests fail |
| 6 | Review subagent(s) over `BASE..HEAD` — one, or three by area above ~1,500 lines; gotcha check, scenario walkthrough, security section when sensitive paths changed | B, C | — |
| 7 | Fix issues, re-run `./test.sh` | B, C | — |
| 8 | Doc pass (**two subagents**): 8a testing-plan + CLAUDE.md; 8b whole-guide review of site/docs.html | B, C | — |
| 9 | Commit & push, then `git tag -f wrap-up-last HEAD` | all | Run stopped early (skip the tag) |
| 10 | Quit Quill, `./build.sh`, reopen | all | Build fails |
| 11 | `--check-fixtures`, then package ZIP (deploy only) | all | Build failed or fixtures mismatch |
| 12 | Attach ZIP to a GitHub release, mark latest, verify the download 200s | all | Build failed |

## Red Flags

- **Never** read `testing-plan.md`, `site/docs.html`, a `test-*.js` suite, or `editor.html` whole in the main conversation — `grep -n` for the section, then `Read` with `offset`/`limit`
- **Never** run the test-coverage audit or the doc pass in the main thread — both are subagent work
- **Never** re-open source files after Step 6 to re-verify the review's findings — one analysis pass is the budget
- **Never** skip Step 5 and continue when tests are failing
- **Never** conclude "no regressions" from structural analysis alone — the scenario walkthrough is part of the Step 6 brief and must be in it
- **Never** use `/code-review` or `/security-review` for Step 6 — they don't reliably see the committed `BASE..HEAD` range
- **Never** package a ZIP if the build failed or `--check-fixtures` reported a mismatch
- **Never** upload a release asset under a name other than `Quill.zip` — the site's download link resolves by asset name and breaks site-wide
- **Never** commit without reviewing what's being staged
- **Never** leave Step 8 until all three of `testing-plan.md`'s parts are updated — test tables, regression matrix, *and* manual checklists
- **Never** skip Step 8b on lane B or C because the session looks internal — the subagent reads the diff and makes that call
- **Never** run lane A on a diff that touched source, or lane B on a diff that added a new function or node — when torn, pick the heavier lane
