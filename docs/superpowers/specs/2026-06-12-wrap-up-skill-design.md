# Wrap-Up Skill Design

**Date:** 2026-06-12
**Project:** Quill (macOS WordPress editor)

## Overview

A personal skill (`~/.claude/skills/wrap-up/SKILL.md`) that runs a standard end-of-session checklist for the Quill project. An optional `deploy` argument triggers an additional packaging step at the end.

## Invocation

```
/run wrap-up          # normal wrap-up
/run wrap-up deploy   # wrap-up + package Quill.zip for distribution
```

## Steps (always run)

1. **Commit & push pending work** — stage any uncommitted changes, commit, push to GitHub if there are unpushed commits.
2. **Review today's commits** — run `git log --since=midnight --oneline` and summarize what changed.
3. **Update automated tests** — assess whether new code requires new or updated Swift/JS tests; write them if so.
4. **Update functional/manual tests** — assess whether `docs/testing-plan.md` checklists need updating; edit if so.
5. **Run all tests** — execute `./test.sh` (Swift + JS).
6. **Report failures** — if any tests fail, report them and stop; do not continue until fixed.
7. **Fast code review** — scan recent changes for architectural, security, consistency, and quality issues.
8. **Address issues** — fix anything found in the review.
9. **Update documentation** — update `CLAUDE.md` and any other relevant project docs to reflect the changes.
10. **Commit & push** — if steps 3–9 produced any changes, commit and push.
11. **Rebuild** — run `./build.sh`.

## Deployment step (only when `deploy` argument present)

12. **Package for release** — run `./build.sh` again for a clean build, then create `~/Desktop/Quill.zip` containing `Quill.app` and `LICENSE` from the project root.

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
./build.sh
zip -r ~/Desktop/Quill.zip Quill.app LICENSE
```

## Decisions

- **Argument-based flag** — `deploy` as a positional argument keeps invocation simple and explicit; no interactive prompts needed.
- **Personal skill location** — `~/.claude/skills/` (not project repo) since this is operator/session tooling, not project code.
- **Stop on test failure** — the checklist halts at step 6 if tests fail; nothing beyond that is safe to commit or package.
