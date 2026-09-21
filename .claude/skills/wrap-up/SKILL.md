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

This checklist runs against a typical session diff of 50–200 lines. It must stay proportionate to that. Three rules govern every step below:

1. **Never read a large file whole.** `docs/testing-plan.md` (~1,700 lines), `docs/user-guide.md` (~670), `Scripts/test-editor.js` (~1,100) and `editor.html` (~3,500) must be reached by `grep -n` for the relevant section, then `Read` with `offset`/`limit`. A whole-file read costs its size on *every subsequent turn* of the run, not once.
2. **Broad file sweeps go to a subagent.** When a step needs to survey many files (the test-coverage audit, the multi-section `testing-plan.md` edit), dispatch a subagent with a self-contained brief and take back only its summary. The files never enter the main conversation, so they are never re-billed.
3. **Review the diff once.** The diff is analyzed in Step 6 and nowhere else. Do not re-read source files in later steps to "double-check" — that is the single largest source of waste in this checklist.

---

## Step 0 — Scope the session and pick a lane

```bash
git status --short
git log --since=midnight --oneline
BASE=$(git log --since=midnight --format=%H | tail -1)
[ -n "$BASE" ] && git diff --stat "$BASE^" HEAD || echo "no commits today"
```

Classify the session into one lane and **say which lane you picked and why**:

| Lane | Trigger | Steps to run |
|------|---------|--------------|
| **A — Docs only** | Only `docs/`, `README`, comments, or version strings changed. No behavior change. | 1, 2, 9, 10 |
| **B — Small change** | Source changed, under ~150 lines, confined to one area, no new functions/nodes/files and no new user-facing capability. | 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 |
| **C — Feature** | New functions, new Tiptap nodes, new files, new user-facing capability, or a change touching Gutenberg HTML round-tripping. | All steps |

When in doubt between B and C, pick C. When in doubt between A and B, pick B.

**Working directory for all steps:** `/Users/Chris/Documents/Claude/WP Mac App`

### Step 1 — Commit & push pending work

Stage and commit any uncommitted changes from `git status --short` above, then push if there are unpushed commits. Review what you're staging before you stage it.

### Step 2 — Summarize today's commits

From the `git log` output already in context, summarize what changed today in 2–4 bullets. Do not re-run git commands for this.

### Step 3 — Test-coverage audit *(lanes B, C — dispatch a subagent)*

Dispatch **one subagent** with a self-contained brief. Do not do this sweep in the main thread — it requires reading multiple test files that would then sit in context for the rest of the run.

The brief must include: the list of changed source files, the diff hunks themselves, and this instruction:

> For every changed function or logic path in `Sources/QuillKit/Resources/editor-transforms.js`, `Sources/QuillKit/Resources/editor.html`, or Swift sources under `Sources/QuillKit/`, locate the corresponding tests in `Scripts/test-editor.js`, `Scripts/test-editor-keyboard.js`, `Scripts/test-editor-gallery.js`, `Scripts/test-editor-passthrough.js`, or `Tests/QuillTests/`. Read them and judge whether they cover the changed behavior *structurally* — asserting output shape and ordering, not merely that a string appears somewhere. Write new or strengthened tests where coverage is missing or shallow. Changes to `editor.html`'s embedded JS are usually paired with `editor-transforms.js` — check both. Tests written in the same session as the feature they cover are themselves suspect; evaluate them as you would any pre-existing test. Report back only: which tests you added or changed, and which changed paths you judged already covered.

Take back the summary. Do not re-read the test files yourself.

### Step 4 — Run all tests *(lanes B, C)*

```bash
./test.sh
```

### Step 5 — Stop on failure *(lanes B, C)*

If `./test.sh` reports failures: show them clearly and **stop**. Do not continue until they are fixed.

### Step 6 — Single review pass *(lanes B, C)*

Run **`/code-review` at medium effort**, and include the scenario-walkthrough directives in the same invocation so the reviewer traces behavior rather than only structure:

> In addition to structural review, trace at least three concrete user scenarios end-to-end against the actual code for each changed path: (a) the happy path; (b) the user does *nothing* — enters a mode and immediately exits, saves without editing; (c) repeated use — enters/exits several times, switches posts. Trace variable state explicitly rather than reasoning about what the code is meant to do. Flag any function that unconditionally runs a side effect (e.g. `setContent`) without a no-change guard, and any variable updated on every exit whose second-entry behavior is untraced.

This is the **only** analysis pass over the diff. After it returns, do not open source files again to re-verify — work from the findings.

**Security review — conditional.** Run `/security-review` only if the diff touches any of:

```bash
git diff --name-only "$BASE^" HEAD | grep -E 'Sources/QuillKit/(Auth|API|AI)/|editor\.html|CredentialsStore|WordPressClient|AnthropicClient'
```

If that returns nothing, skip it and say so. Quill's credential, URL, and WKWebView surfaces warrant a dedicated pass; a picker styling change does not.

### Step 7 — Address issues *(lanes B, C)*

Fix anything the review found. Re-run `./test.sh` after fixes.

### Step 8 — Documentation pass *(lanes B, C — one consolidated pass, after review)*

All doc updates happen here, **after** review, so that a fix from Step 7 doesn't invalidate freshly-written docs.

Dispatch **one subagent** covering all three docs, with a brief containing the change summary from Step 2, the test changes from Step 3, and this instruction:

> Update three docs to match today's changes. Reach every section via `grep -n` and read only that range with offset/limit — never read these files whole.
>
> **`docs/testing-plan.md`** — three things, all of them: (a) add a row per new test to the relevant suite section and update that section's header count; (b) add a row to the regression matrix at the bottom linking each new behavioral guard to the scenario it guards; (c) add manual-checklist items under the relevant §7.x for any new feature or behavior change.
>
> **`docs/user-guide.md`** — for each user-facing change: add coverage for undocumented capabilities, correct any section describing behavior that no longer matches (wrong labels, outdated steps, removed options), and delete content for things that no longer exist. Write for a new user of the current build; no internal implementation details.
>
> **`CLAUDE.md`** — new gotchas or constraints discovered, architecture changes, new key files or patterns, and the test-count line in the test suite status section.
>
> Report back only a list of the edits you made.

If today's changes were purely internal with no user-facing surface, say so and skip the `user-guide.md` portion of the brief.

For substantial architectural change, run `claude-md-management:revise-claude-md` instead of the `CLAUDE.md` portion above.

### Step 9 — Commit & push

If steps 3–8 produced changes, stage them, commit, and push. Review what you're staging.

### Step 10 — Rebuild app

```bash
./build.sh
```

Confirm the build succeeds.

---

## Deployment step (only when `deploy` argument present)

### Step 11 — Package Quill.zip

**The name `Quill.zip` is load-bearing.** Every page of the site links to
`https://github.com/cpoteet/Quill/releases/latest/download/Quill.zip`, which GitHub
resolves by asset name against whichever release is marked latest. A ZIP uploaded
under any other name breaks the download button site-wide.

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
./build.sh
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
| 0 | Scope the diff, pick a lane, announce it | all | — |
| 1 | Commit & push pending | all | — |
| 2 | Summarize today's commits | all | — |
| 3 | Test-coverage audit (**subagent**) | B, C | — |
| 4 | Run `./test.sh` | B, C | — |
| 5 | Report failures | B, C | Tests fail |
| 6 | Single `/code-review` at medium + folded-in scenario walkthrough; `/security-review` only if sensitive paths touched | B, C | — |
| 7 | Fix issues, re-run `./test.sh` | B, C | — |
| 8 | Doc pass (**subagent**): testing-plan + user-guide + CLAUDE.md | B, C | — |
| 9 | Commit & push | all | — |
| 10 | `./build.sh` | all | Build fails |
| 11 | Package ZIP (deploy only) | all | Build failed |
| 12 | Attach ZIP to a GitHub release, mark latest, verify the download 200s | all | Build failed |

## Red Flags

- **Never** read `testing-plan.md`, `user-guide.md`, `test-editor.js`, or `editor.html` whole — `grep -n` for the section, then `Read` with `offset`/`limit`
- **Never** run the test-coverage audit or the doc pass in the main thread — both are subagent work
- **Never** re-open source files after Step 6 to re-verify the review's findings — one analysis pass is the budget
- **Never** skip Step 5 and continue when tests are failing
- **Never** conclude "no regressions" from structural analysis alone — the scenario walkthrough is folded into Step 6 and must actually be requested there
- **Never** package a ZIP if the build failed
- **Never** upload a release asset under a name other than `Quill.zip` — the site's download link resolves by asset name and breaks site-wide
- **Never** commit without reviewing what's being staged
- **Never** leave Step 8 until all three of `testing-plan.md`'s parts are updated — test tables, regression matrix, *and* manual checklists
- **Never** run lane A on a diff that touched source, or lane B on a diff that added a new function or node — when torn, pick the heavier lane
