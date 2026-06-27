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
/run wrap-up          # standard checklist
/run wrap-up deploy   # standard checklist + package Quill.zip
```

## Checklist

**Working directory for all steps:** `/Users/Chris/Documents/Claude/WP Mac App`

### Step 1 — Commit & push pending work

```bash
git status
git diff --stat
```

Stage and commit any uncommitted changes, then push if there are unpushed commits.

### Step 2 — Review today's commits

```bash
git log --since=midnight --oneline
```

Summarize what changed today in 2–4 bullet points.

### Step 3 — Update automated tests

For each file changed in today's commits, read the actual diff. For every changed function or logic path in testable files (`Sources/QuillKit/Resources/editor-transforms.js` and Swift source files under `Sources/QuillKit/`):

1. **Find** the corresponding tests in `Scripts/test-editor.js` or `Tests/QuillTests/`
2. **Read** those tests — not just that they exist, but whether they cover the changed behavior structurally (e.g. assert output shape and ordering, not just that a string is present somewhere)
3. **Write** new or updated tests if coverage is missing or shallow

**Critical:** Changes to `editor.html`'s embedded JS are often paired with changes to `editor-transforms.js` — check both. Tests added in the same session as a feature may themselves be shallow; evaluate them as you would any existing tests.

### Step 4 — Update docs/testing-plan.md

`docs/testing-plan.md` tracks three things. Update all three as appropriate:

**4a — Automated test tables:** If tests were added or modified in Step 3, find the relevant suite section and update it: add a row for each new test, update the section header count, and confirm nothing is missing.

**4b — Regression matrix:** For each behavioral guard added in Step 3, add a row to the regression matrix (at the bottom of the doc) linking the test suite to the scenario it guards against.

**4c — Manual/functional checklists:** If any new features or behavior changes aren't covered in the manual test steps, add checklist items under the relevant section (§7.x).

### Step 5 — Run all tests

```bash
./test.sh
```

### Step 6 — Report failures and stop if any

If `./test.sh` reports any failures:

1. Show the failures clearly.
2. **Stop.** Do not continue to step 7 until all failures are fixed.

If all tests pass, continue.

### Step 7 — Review end user documentation

Read `docs/user-guide.md`. For each feature added, changed, or removed in today's commits, evaluate:

- **Add:** Is there a user-facing capability that isn't documented? Add a section or update existing prose to cover it.
- **Update:** Does any existing section describe behavior that no longer matches — wrong UI labels, outdated steps, removed options? Correct it.
- **Remove:** Is anything documented that no longer exists in the app? Delete stale content.

Focus on what a new user reading the doc would experience in the current build. Do not document internal implementation details here — `CLAUDE.md` is for that.

If no user-facing changes were made today, note that and move on.

### Step 8 — Code review

Run `/code-review` at **high** effort. This is mandatory, not optional.

### Step 9 — Security review

Run `/security-review`. Quill handles credentials, URLs, and WKWebView content — security issues are easy to miss in a general code review and warrant their own pass.

### Step 10 — Code review: scenario walkthrough

**This step is mandatory and separate from steps 8–9.** Static and security analysis catch structural problems; this step catches behavioral regressions that only appear when tracing real user flows.

For each changed function or code path, walk through **at least 3 concrete user scenarios** step by step against the actual code — not your mental model of the code. Ask:

- What happens on the **happy path**?
- What happens if the user does **nothing** (enters a mode and immediately exits, saves without editing, etc.)?
- What happens on **repeated use** (enters/exits multiple times, switches posts, etc.)?

Trace variable state explicitly. Do not skip steps. Do not substitute "this should work" for actually following the execution.

**Red flags that mean you missed something:**
- You analyzed a non-issue in detail but skipped simulating the basic user flow
- You concluded "no regressions" from reading the diff without tracing a scenario end-to-end
- A function always runs a side effect (like `setContent`) but you didn't ask "what if the user made no changes?"
- A variable is updated on every exit but you didn't trace what happens on the second entry

### Step 11 — Address issues

Fix anything found in steps 8–10. Re-run `./test.sh` after fixes.

### Step 12 — Update documentation

Update `CLAUDE.md` and any other relevant project docs (`docs/`) to reflect today's changes. Key areas:
- New gotchas or constraints discovered
- Architecture changes
- New key files or patterns
- Test suite status line (test count)

Use the `claude-md-management:revise-claude-md` skill if the changes were substantial.

### Step 13 — Commit & push

If steps 3–12 produced any new changes:

```bash
git add <relevant files>
git commit -m "..."
git push
```

### Step 14 — Rebuild app

```bash
./build.sh
```

Confirm the build succeeds.

---

## Deployment step (only when `deploy` argument present)

### Step 15 — Package Quill.zip

Run a clean build and create the release ZIP on the Desktop:

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
./build.sh
rm -f ~/Desktop/Quill.zip
zip -r ~/Desktop/Quill.zip Quill.app LICENSE
```

Report: "Quill.zip created at ~/Desktop/Quill.zip"

---

## Quick Reference

| Step | Action | Stop if… |
|------|--------|----------|
| 1 | Commit & push pending | — |
| 2 | Review today's commits | — |
| 3 | Update automated tests (read + evaluate, don't just decide) | — |
| 4 | Update testing-plan.md: test tables + regression matrix + manual checklists | — |
| 5 | Run `./test.sh` | — |
| 6 | Report failures | Tests fail |
| 7 | Review end user docs (docs/user-guide.md) | — |
| 8 | `/code-review` at high effort | — |
| 9 | `/security-review` | — |
| 10 | Code review: scenario walkthrough | — |
| 11 | Fix issues | — |
| 12 | Update CLAUDE.md / project docs | — |
| 13 | Commit & push changes | — |
| 14 | `./build.sh` | Build fails |
| 15 | Package ZIP (deploy only) | — |

## Red Flags

- **Never** skip step 6 and continue when tests are failing
- **Never** claim "no regressions" from static analysis alone — step 10 scenario walkthrough is required
- **Never** package a ZIP (step 15) if the build in step 14 failed
- **Never** commit without reviewing what's being staged
- **Never** conclude "no tests needed" from an abstract judgment — read the actual test file for every changed function in `editor-transforms.js` or Swift before deciding
- **Never** leave Step 4 until the automated test tables, regression matrix, and manual checklists in `docs/testing-plan.md` are all updated — all three, not just the manual checklists
