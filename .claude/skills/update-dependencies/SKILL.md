---
name: update-dependencies
description: Use when checking or updating Quill's dependencies — before a release, when asked "are our dependencies up to date", "check for new versions of Tiptap", after an npm audit warning, or when updating esbuild, jsdom, marked, ProseMirror, the @wordpress test packages or SQLite.swift.
---

# Update dependencies (Quill)

Reports what is out of date, decides what should move, and moves it one tool at a time with the full suite between each. The report alone is not the answer: twice it has pointed the wrong way (see Traps).

**Working directory:** `/Users/Chris/Documents/Claude/WP Mac App`

## What Quill depends on

| Dependency | Where pinned | Ships in Quill.app | Rule |
|---|---|---|---|
| SQLite.swift | `Package.swift`, `Package.resolved` | Yes | Update within its major |
| Tiptap 2.x (16 packages) + ProseMirror via `@tiptap/pm` | `Scripts/tiptap-bundle/` | Yes, as `tiptap-bundle.js` | Stay on v2. v3 is a planned migration, not an update |
| marked | `Scripts/marked-bundle/` | Yes, as `marked-bundle.js` | Update within its major |
| esbuild | both bundle folders | No, but it writes both bundles | Update both folders together |
| jsdom | `Scripts/package.json` | No | Update freely, fix the harnesses |
| `@wordpress/*` test references | `Scripts/package.json` (devDependencies + overrides) | No | Match the current WordPress release, never npm's latest |

Swift Testing comes from the toolchain; there is no package dependency for it.

## Step 1 — Report

```bash
./Scripts/check-dependencies.sh
```

It prints, per npm folder, each direct dependency's pinned version, the newest in its current range and the newest overall, then `npm audit`; ProseMirror packages behind their latest; the @wordpress versions the current WordPress release ships beside the ones pinned (`MISMATCH` marks a difference); and the Swift pins. It changes nothing.

Present the report to the user grouped as **ships in the app** / **build and test only**, and say which updates you recommend and which are major migrations to defer. Wait for their go-ahead before Step 2.

## Step 2 — Verify every advisory before acting on it

For each `npm audit` advisory, read the advisory (`gh api /advisories/<GHSA-id>`) and then the installed source of the flagged function. An advisory's version range can be wrong for a backported fix. If the claim matters, write a jsdom probe that feeds the payload through the real `editor.html`, with a positive control that proves the probe can detect a leak.

## Step 3 — Update one tool at a time

After each one: `./test.sh`, and stop to fix before moving on, so a failure points at one tool.

- **ProseMirror patches:** `cd Scripts/tiptap-bundle && npm update --package-lock-only <packages>`, check that the lockfile diff names only those packages, then `./Scripts/bundle-tiptap.sh`.
- **esbuild:** read the release notes of every minor version crossed (0.x minors break). Change the version in both bundle folders' `package.json`, `npm install --package-lock-only` in each, regenerate both bundles. Copy each bundle aside first and compare after: explain every byte that changed, or revert.
- **jsdom:** `cd Scripts && npm install --save-dev jsdom@^<version>`. Expect harness failures, not app bugs; see Traps.
- **@wordpress test references:** follow `docs/wordpress-release-audit.md` steps 3–5 and 7 for the current release (`api.wordpress.org/core/version-check/1.7/`). A minor WordPress release can mean no change at all.
- **marked / SQLite.swift:** within the major only; a major goes to the user as its own task.

## Step 4 — Finish

```bash
./test.sh
pkill -f "^$PWD/Quill.app/Contents/MacOS/Quill"; sleep 2 && ./build.sh 2>&1 && ./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"
```

Then update: test counts in `CLAUDE.md` and `docs/testing-plan.md` if they moved; `CLAUDE.md` Requirements if a toolchain version changed; any gotcha whose workaround changed. Summarize what moved, what was deferred and why, and wait for the user to ask for a commit.

## Traps

- **The @wordpress packages look outdated on purpose.** npm runs ahead of WordPress; the validator suites must check against the release users run. On 2026-10-08 aligning them meant moving *down*.
- **A lockfile can hide a broken fresh install.** In 2026-10 newer `@wordpress/rich-text`, `data`, `compose` and `components` moved to `private-apis` 2.x; the pinned packages' `^` ranges pulled them in, two `private-apis` copies loaded, and every validator suite died with "Cannot unlock an object that was not locked before". The fix is the transitive overrides in audit step 4 plus a fresh resolve (delete `Scripts/node_modules` and `Scripts/package-lock.json`).
- **Tiptap's `mergeAttributes` advisory (GHSA-cp6q-959q-f8rh) is fixed in 2.27.3** despite its range; `npm audit` reports 31 moderate findings for it in `Scripts/tiptap-bundle/` until the range is corrected. Re-check only if Tiptap changes.
- **jsdom 30:** `FileReader` is ~20× slower, so harnesses wait for a condition, never a fixed delay; and blurring the view no longer keeps ProseMirror's scroll-into-view off `getClientRects`, so container suites stub it (`docs/editor-gotchas.md`).
- **`swift package clean` after removing a Swift package**, or the test build fails on a stale module such as `_TestingInternals`.
- **npm may warn about install scripts** (`npm install-scripts`) for esbuild; the platform binary installs through optional dependencies, so the bundles build without approving it.
