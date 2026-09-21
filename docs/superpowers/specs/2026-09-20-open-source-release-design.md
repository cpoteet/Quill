# Quill — Open the repo, move the site, publish real releases

Date: 2026-09-20
Status: approved design, not yet implemented

## Goal

Move Quill to a public `cpoteet/Quill` repository that also hosts the public
website at `quill.siolon.com`. Replace the hand-maintained ZIP and
`version.json` with real published GitHub releases. Retire the
`Quill-Releases` repository completely.

The work splits into two phases. **Phase 1 sets everything up and is safe to do
now.** Phase 2 is the 2.0.0 release itself and runs only when testing is
finished.

## Decisions

These were settled before this document was written.

| Question | Decision |
|---|---|
| Repository visibility | Public. Required, not optional — see "Why public is forced". |
| Site location | `site/` in the `Quill` repo, published by a GitHub Actions workflow. |
| Site URL | Custom domain `quill.siolon.com`. |
| License | Keep the proprietary EULA. Amend one clause for internal consistency. |
| Old draft releases | Publish all 12, oldest first, each with its true date in the note. |
| `Quill-Releases` repo | Retire it. No redirects, no `version.json`, no dependency of any kind. |
| `docs/superpowers/` specs and plans | Stay public. |
| Engineering docs in `docs/` | Stay public. |
| Update banner link target | The GitHub release page. |

### Why public is forced

The account is on the GitHub Free plan. GitHub Pages publishes from public
repositories only on Free. Release assets and the releases API on a private
repository require an authentication token, so anonymous download links and an
anonymous update check both fail. Making the repository public is a
precondition for the site move, the download link, and the update checker.

### Why the old repo can be dropped cleanly

Three URLs are compiled into every shipped Quill 1.x binary: the update check
at `UpdateChecker.swift:9`, the Help menu at `QuillApp.swift:87`, and the
About window at `AboutView.swift:25`. All three point at `Quill-Releases`.
Retiring that repository breaks all three for anyone running 1.x.

This is accepted. There is no meaningful install base to strand, so the clean
break is worth more than a permanent stub repository.

## Non-goals

- Rewriting git history to remove anything. The history stays as it is.
- Changing the EULA's restrictions. Only the reverse-engineering clause is amended.
- Preserving any `Quill-Releases` URL.
- Adding CI for builds or tests. Only the Pages deployment workflow is added.

---

# Phase 1 — set everything up

Everything below can be done now. At the end of Phase 1 the repository is
public, the site is live at `quill.siolon.com`, and the download button serves
a working 1.11.0 build. Nothing waits on the 2.0.0 release.

## 1.1 Repository preparation

### Amend the EULA

`LICENSE:33` forbids the user to "attempt to discover the source code". The
source will sit in the same repository as that sentence, so the clause
contradicts itself once the repository is public.

Add one sentence to that section stating that the source is published for
reference and transparency, and that its publication grants no license to
modify, redistribute, or create derivative works. Every restriction chosen at
`LICENSE:16-17` and `LICENSE:30` stays in force. This is a two-line edit.

Mirror the same edit into `site/license.html`.

### Trim the README

It is 176 lines and repeats the website. Cut it to roughly 40 lines:

- One paragraph on what Quill is
- A screenshot
- A link to `quill.siolon.com` for download, docs, and changelog
- Build and test instructions
- A short license note stating the source is readable but not open source
- A pointer to `CLAUDE.md` for architecture

The website sells the app. The README serves someone standing in the repository.

### Delete stray tracked files

Four files are tracked under `.superpowers/` despite the `.gitignore` entry.
They were committed before the ignore rule existed:

```
.superpowers/brainstorm/2463-1779406854/state/server.log
.superpowers/brainstorm/2463-1779406854/state/server.pid
.superpowers/brainstorm/2575-1779406862/state/server.log
.superpowers/brainstorm/2575-1779406862/state/server.pid
```

Remove them with `git rm --cached` and commit.

### Fix stale URLs in repository docs

| File | Current | Change to |
|---|---|---|
| `docs/Privacy.md:52` | `Quill-Releases/issues` | `Quill/issues` |
| `docs/user-guide.md:56` | `cpoteet.github.io/Quill-Releases` | `quill.siolon.com` |
| `docs/testing-plan.md:2912` | manual check of `version.json` | the new releases-API check |

### Repository metadata

- Description: currently empty. Set it.
- Homepage: set to `https://quill.siolon.com`.
- Topics: `macos`, `swift`, `swiftui`, `wordpress`, `tiptap`, `editor`.
- Issues: turn on.

### Content review before flipping to public

Already checked and clear: no API keys, no credentials, no private tokens in
tracked files. `AGENTS.md` is gitignored and will not publish.

One item to confirm by eye: `Scripts/fixtures/` contains real post content from
siolon.com, including `post-17780.html`. This is your own writing, so there is
no legal issue. Confirm you are comfortable publishing it.

## 1.2 Move the site into `site/`

### Files to move

From `cpoteet/Quill-Releases` into `Quill/site/`:

- `index.html`, `docs.html`, `changelog.html`, `license.html`, `privacy.html`
- `style.css`
- `images/`

Do not move `Quill.zip` or `version.json`. Both are retired. The ZIP becomes a
release asset in 1.4; `version.json` has no successor because the update check
moves to the API.

### Path edits required

A custom domain serves the site from the root, so the project-page prefix
`/Quill-Releases/` becomes a 404.

1. Line 16 of all five pages: change `href="/Quill-Releases/"` to `href="/"`.
2. Lines 21 and 31 of `index.html`, and line 21 of the other four pages:
   replace `https://cpoteet.github.io/Quill-Releases/Quill.zip` with
   `https://github.com/cpoteet/Quill/releases/latest/download/Quill.zip`.
3. `docs.html:83` — body text naming `cpoteet.github.io/Quill-Releases`.
   Change to `quill.siolon.com`.
4. `changelog.html:277` — body text linking `docs.html` by absolute URL.
   Change to a relative link.
5. `index.html:198` — the issues link points at `Quill-Releases/issues`.
   Change to `Quill/issues`.

Add `site/CNAME` containing the single line `quill.siolon.com`. The Pages
settings also record the domain, but the file makes the deployment
self-describing and survives a settings reset.

After the edits, grep `site/` for `Quill-Releases` and expect no hits.

### Pages workflow

Create `.github/workflows/pages.yml`:

```yaml
name: Deploy site
on:
  push:
    branches: [main]
    paths: ['site/**', '.github/workflows/pages.yml']
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/configure-pages@v5
      - uses: actions/upload-pages-artifact@v3
        with:
          path: site
      - id: deployment
        uses: actions/deploy-pages@v4
```

In **Settings → Pages**, set the source to **GitHub Actions**.

### DNS

Add one record at the `mddservices.com` control panel:

- Type: `CNAME`
- Name: `quill`
- Value: `cpoteet.github.io`

The target has no path. GitHub resolves the repository from the `CNAME` file
and the Pages settings. Verify with `dig +short quill.siolon.com`, which must
return `cpoteet.github.io`.

Then set the custom domain in **Settings → Pages**, wait for the DNS check to
pass, and tick **Enforce HTTPS**. Certificate issue can take up to an hour.

Optional: verify `siolon.com` under account settings to stop anyone else
attaching the subdomain to their own repository.

## 1.3 App changes

Four code edits. The version stays at `1.11.0` throughout Phase 1. Bumping it
is a Phase 2 step.

### Update checker reads the GitHub API

`Sources/QuillKit/App/UpdateChecker.swift:9` currently reads `version.json`.
Point it at `https://api.github.com/repos/cpoteet/Quill/releases/latest` and
decode `tag_name` and `html_url`.

**Trap:** `isNewer` at `UpdateChecker.swift:51` parses version parts with
`Int()` and drops anything that fails. The API returns `tag_name` as `v2.0.0`.
`Int("v2")` returns nil, so `[v2, 0, 0]` becomes `[0, 0]` and the comparison
silently reports no update, forever. Strip the leading `v` before comparing.

Add a test for this. `Tests/QuillTests/UpdateCheckerTests.swift` already covers
`isNewer`; extend it with a `v`-prefixed input.

Rate limit: 60 unauthenticated requests per hour per IP address. The app checks
once per sidebar remount, which is far below that. A 403 throws, and the
existing code already treats a throw as "retry later" rather than "no update",
so the failure mode is correct as written.

The endpoint ignores drafts. It returns 404 until at least one release is
published, so 1.4 must come before this can be tested.

### Help menu points at the new guide

`Sources/QuillKit/App/QuillApp.swift:87` → `https://quill.siolon.com/docs.html`.

### Add a Changelog item

Add a second button in the same `CommandGroup(replacing: .help)` block at
`QuillApp.swift:85`, opening `https://quill.siolon.com/changelog.html`.

### About window EULA link

`Sources/QuillKit/Views/Settings/AboutView.swift:25` →
`https://quill.siolon.com/license.html`.

## 1.4 Publish the 12 draft releases

All 12 tags already exist on the remote with their true commit dates. No tag is
created by publishing. GitHub stamps a release with the time it is published
and the API cannot backdate it, so all 12 will display today's date.

### True dates to add to each note

Prepend one line to each release body, for example `Released 2026-05-24`. This
list matches the site changelog exactly — there are 12 versions, no more.

| Tag | True date | Tag | True date |
|---|---|---|---|
| v1.0.0 | 2026-05-24 | v1.6.0 | 2026-06-12 |
| v1.1.0 | 2026-05-26 | v1.7.0 | 2026-06-15 |
| v1.2.0 | 2026-05-29 | v1.8.0 | 2026-06-17 |
| v1.3.0 | 2026-06-01 | v1.9.0 | 2026-06-26 |
| v1.4.0 | 2026-06-06 | v1.10.0 | 2026-07-10 |
| v1.5.0 | 2026-06-07 | v1.11.0 | 2026-08-20 |

### Publishing order

Publish oldest first. GitHub resolves "latest" by publish time, so publishing
out of order makes an old version the latest and points every download link at
the wrong build.

### Attach the 1.11.0 build to v1.11.0

This is what keeps the site working during the testing period.

The ZIP currently served at `cpoteet.github.io/Quill-Releases/Quill.zip` has
been verified to contain `CFBundleShortVersionString` `1.11.0`. Download it and
attach it to the `v1.11.0` release under the exact name `Quill.zip`.

With that asset in place, `releases/latest/download/Quill.zip` resolves
correctly from the moment the site goes live. The site advertises 1.11.0, which
is accurate, and the whole download and update path can be tested end to end
before 2.0.0 exists.

The other 11 releases stay note-only. Those builds no longer exist.

**Constraint for every future release:** the asset must be named exactly
`Quill.zip`, or the download link 404s. Add this to the `wrap-up` skill's
deploy path.

## 1.5 Go public and cut over

1. Flip `cpoteet/Quill` to public.
2. Enable Pages with the Actions source.
3. Add the DNS record. Set the custom domain. Enable HTTPS.
4. Retire `Quill-Releases`: turn Pages **off** first, then archive the
   repository. Turning Pages off is what kills the old URL. Archiving alone
   leaves the old site serving a stale download button. Deleting the repository
   outright also works and is equally acceptable here; archiving is preferred
   only because it costs nothing and keeps the history.

## 1.6 Phase 1 verification

| Check | Expected |
|---|---|
| `dig +short quill.siolon.com` | returns `cpoteet.github.io` |
| `https://quill.siolon.com/` | loads; logo, Docs, Changelog links all work |
| `grep -r Quill-Releases site/` | no hits |
| `https://github.com/cpoteet/Quill/releases/latest/download/Quill.zip` | downloads a valid 1.11.0 ZIP |
| Releases page | lists 12 entries; v1.11.0 marked Latest |
| `cpoteet.github.io/Quill-Releases/` | 404 |
| `./test.sh` | all suites pass, including the new `isNewer` test |
| `--check-fixtures` run | passes |
| Help menu | Quill Help and Changelog open the right pages |
| About window | EULA link opens the new license page |
| Update check in-app | reports no update, because 1.11.0 equals latest |

The last row is the important one. It proves the new API path works without
needing a 2.0.0 release to exist.

---

# Phase 2 — cut the 2.0.0 release

Run this only when testing is finished. Every step assumes Phase 1 is complete
and verified.

**Before step 3, keep a copy of the current 1.11.0 `Quill.app` somewhere
outside the repository.** Step 3 overwrites it, and the update-banner check in
step 10 cannot be done without it.

1. **Bump the version.** `build.sh:65` — change `CFBundleShortVersionString`
   from `1.11.0` to `2.0.0`.

2. **Write the changelog entry.** Add a `v2.0.0` block at the top of
   `site/changelog.html`, matching the existing markup: `release__version`,
   then `What's New`, `Improvements`, and `Fixes` sections.

3. **Run the full check.** All three, in order. Stop if any fails.

   ```bash
   ./test.sh
   ```

   ```bash
   osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app
   ```

   ```bash
   ./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"
   ```

   The fixture check is the only test that runs in real WebKit and is required
   before release sign-off.

4. **Work the manual release checklist** in `docs/testing-plan.md`.

5. **Tag and push.**

   ```bash
   git tag v2.0.0 && git push origin v2.0.0
   ```

6. **Package the app.** Produce `Quill.zip` containing `Quill.app`. The name
   must be exactly `Quill.zip`.

7. **Create the release with its asset.**

   ```bash
   gh release create v2.0.0 --repo cpoteet/Quill --title "Quill 2.0.0" --notes-file NOTES.md Quill.zip
   ```

8. **Confirm it is latest.**

   ```bash
   gh release edit v2.0.0 --repo cpoteet/Quill --latest
   ```

9. **Deploy the site.** Pushing the changelog edit to `main` triggers the Pages
   workflow. Confirm the run succeeded.

10. **Verify the release.**

    | Check | Expected |
    |---|---|
    | `https://github.com/cpoteet/Quill/releases/latest/download/Quill.zip` | downloads a 2.0.0 ZIP |
    | Releases page | v2.0.0 marked Latest |
    | `https://quill.siolon.com/changelog.html` | shows the v2.0.0 entry |
    | Launch the retained 1.11.0 build | update banner appears, names 2.0.0, and opens the v2.0.0 release page |

    The last row is the only end-to-end proof that the update path works, and
    it cannot be tested after the fact.

---

## Risks

**Wrong release marked latest.** Publishing the 12 drafts out of order points
the download link at a release with no asset. Mitigated by publishing oldest
first and by attaching the ZIP to v1.11.0 in 1.4.

**Silent update-check failure.** The `v` prefix in `tag_name` breaks `isNewer`
without any error. Mitigated by the unit test in 1.3.

**Asset name drift.** A future release whose asset is not named `Quill.zip`
breaks the download link on every page of the site. Mitigated by adding the
constraint to the `wrap-up` skill.

**Site path regressions.** Five pages carry absolute `/Quill-Releases/` paths.
Missing one produces a 404 on a link that looks fine in review. Mitigated by
the grep in 1.2 and 1.6.

**Going public is one-way.** Anything published may be copied before a reversal
takes effect. All reversible work is ordered before step 1.5.1 for this reason.

**Lost 1.11.0 build.** Phase 2 step 3 overwrites `Quill.app`. Without a
retained copy the update-banner test in step 10 is impossible. Noted at the top
of Phase 2 and in step 10.
