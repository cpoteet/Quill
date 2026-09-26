---
name: release
description: Use when cutting a new Quill release — bumping the version, notarizing the app, drafting release notes, publishing to GitHub, or updating the changelog and public site for a new version.
---

# Release (Quill)

Takes Quill from committed code to a notarized draft release on GitHub, then updates the site once the user has published it. The user publishes the release on GitHub; this skill never does.

**Announce at start:** "Running the release checklist for Quill `<version>`."

```
/release 2.1.0    # the version to release
/release          # no version: ask for one (Step 0)
```

Invoking this skill is the user's request to commit and push the version bump and the site changes it describes. Everything else follows the normal git rules.

**Working directory:** `/Users/Chris/Documents/Claude/WP Mac App`

---

## Part 1 — Build the draft release

### Step 0 — Version and pre-flight

If no version was given, ask for one. Suggest the next version from the latest tag (`git describe --tags --abbrev=0 --match 'v*'`) and the size of the change, and wait for the answer.

```bash
git fetch --tags
git status --short
git log --oneline origin/main..HEAD
PREV=$(git describe --tags --abbrev=0 --match 'v*')
echo "PREV=$PREV"
```

Stop if the working tree is dirty or `v<version>` already exists. Push unpushed commits. The draft release targets a commit on GitHub, so everything must be pushed before Step 2.

Run `./test.sh`. Stop on any failure.

### Step 1 — Bump the version

`build.sh` holds the version twice, as `CFBundleVersion` and `CFBundleShortVersionString`. Both are always the release version. If they already match `<version>`, skip this step.

```bash
sed -i '' -E 's#(<key>CFBundle(Short)?Version(String)?</key><string>)[^<]*#\1<version>#' build.sh
grep -n 'CFBundle.*Version' build.sh
git commit -am "chore: bump version to <version>" && git push
```

### Step 2 — Notarize (in the background)

Record `SHA=$(git rev-parse HEAD)`. It is the commit being notarized, and the release must point at it.

Quit the dev build, then start the script with `run_in_background`. It builds with `./build.sh --release`, runs `--check-fixtures` against the signed app, submits to Apple and waits, staples the ticket, and writes `~/Desktop/Quill.zip` (the app plus `LICENSE.md` and `NOTICES.md`). Apple usually answers within 15 minutes.

```bash
pkill -f "^$PWD/Quill.app/Contents/MacOS/Quill"; sleep 2
Scripts/notarize.sh > "$TMPDIR/quill-notarize.log" 2>&1
```

The script needs the `quill-notary` keychain profile. If it's missing, the user creates it with `xcrun notarytool store-credentials "quill-notary" --apple-id <apple-id> --team-id NRCW9A2622`. That command asks for an app-specific password, so the user runs it, not you.

### Step 3 — Draft the release notes (while Apple works)

Dispatch one subagent with `$PREV`, `<version>` and this brief:

> Write release notes for Quill `<version>` from `git log --format='%h %s%n%b' <PREV>..HEAD`. Read the whole log. Open `site/docs.html` or a diff whenever a commit message doesn't make the user-visible effect clear.
>
> Include only what a user of `<PREV>` would notice in `<version>`. Leave out docs, tests, refactors, build tooling and review cleanups. Leave out fixes for bugs that were introduced after `<PREV>`, because users never saw those bugs. Merge several commits about one feature into one entry.
>
> Write for a user deciding whether to update. Each What's New entry is 1–3 sentences: what changed, then why it matters to them (what it fixes, what it lets them do, why it was built). Describe a broad change at the level the user experiences it ("custom chrome replaced by native controls"), not as a list of its parts. Leave out how-to detail such as shortcuts, click paths and every option a feature has; the user guide covers that. Merge related features into one entry, and order What's New by how much the change affects the user, not by how much code it took.
>
> Improvements and fixes get one sentence each, using Quill's real menu, button and shortcut names. Drop fixes too small for a user to have noticed. Use American spelling and no marketing language.
>
> Return Markdown in exactly this shape. Omit a section only if it would be empty.
>
> ```
> _Released YYYY-MM-DD_
>
> ## What's New
>
> ### Sentence-case feature name
> One to three sentences.
>
> ---
>
> ## Improvements
>
> - **Sentence-case name** — One sentence.
>
> ---
>
> ## Fixes
>
> - One sentence per fix, stating the corrected behavior.
> ```

Use today's date. Read the draft yourself and cut any entry that runs past its limit, then save it to `$TMPDIR/quill-notes-<version>.md`. `gh release view v2.0.0 --repo cpoteet/Quill --json body -q .body` shows a finished example.

### Step 4 — Confirm notarization

When the background job finishes, read the tail of `$TMPDIR/quill-notarize.log`. It must end with `✓ Notarized: …/Quill.zip`. On any other ending, show the failing section and stop. If Apple returned **Invalid**, the log includes Apple's issue list from `notarytool log`.

The script left a release-signed `Quill.app` in the project. Rebuild the dev app so later local work runs the usual ad-hoc build:

```bash
./build.sh 2>&1 | tail -1
```

The user runs the notarized build day to day. Replace `/Applications/Quill.app` with the one in the zip, never with the project's dev build. First check whether the installed copy is running:

```bash
pgrep -f "^/Applications/Quill.app/Contents/MacOS/Quill" && echo "RUNNING"
```

If it prints `RUNNING`, ask the user to quit it and wait. Don't kill it, because it may hold unsaved work. Then install:

```bash
D=$(mktemp -d) && ditto -x -k ~/Desktop/Quill.zip "$D" && rm -rf /Applications/Quill.app && ditto "$D/Quill.app" /Applications/Quill.app && rm -rf "$D"
spctl -a -vv /Applications/Quill.app
```

`spctl` must report `source=Notarized Developer ID`.

### Step 5 — Create the draft release

**The asset must be named `Quill.zip`.** Every page of the site links to `https://github.com/cpoteet/Quill/releases/latest/download/Quill.zip`, and GitHub resolves that link by asset name against the release marked latest.

```bash
gh release create "v<version>" --repo cpoteet/Quill --draft --target "$SHA" \
  --title "Quill <version>" --notes-file "$TMPDIR/quill-notes-<version>.md" ~/Desktop/Quill.zip
gh release view "v<version>" --repo cpoteet/Quill --json isDraft,assets -q '{isDraft, assets: [.assets[].name]}'
```

Give the user the release URL, then **stop and wait**. Tell them:
- to edit the notes on GitHub if they want changes;
- to leave **Set as the latest release** checked when they publish;
- to say so when they have finished editing.

The tag `v<version>` is created on `$SHA` when the release is published.

---

## Part 2 — After the user confirms

### Step 6 — Update the changelog

Read the final notes back from GitHub. They may differ from your draft.

```bash
gh release view "v<version>" --repo cpoteet/Quill --json body,isDraft,publishedAt
```

Insert a new `<article class="release">` as the first child of `<div class="releases">` in `site/changelog.html`. Copy the structure of the entry below it. Mapping from the Markdown:

| Markdown | changelog.html |
|---|---|
| version | `<span class="release__version">v<version></span>` |
| `_Released YYYY-MM-DD_` | `<span class="release__date">Month D, YYYY</span>`, using `publishedAt` once the release is published |
| `## What's New` → `### Name` + paragraph | `release__section` › `h2.release__section-title`; each feature is a `div.release__feature` with `h3.release__feature-title` in **Title Case** and `p.release__body` |
| `## Improvements` → `- **Name** — text` | `ul.release__list` › `<li><strong>Name</strong> — text</li>` |
| `## Fixes` → `- text` | `ul.release__list` › `<li>text</li>` |
| `` `code` `` | `<code>`, with `<`, `>` and `&` escaped |
| `---` | nothing (sections are already separate) |

### Step 7 — Site pass

Check every page in `site/` against the new release:

1. **Version:** `grep -n 'version-badge' site/index.html`. The badge reads `v<major>.<minor> · …`. Update the number.
2. **Download links:** every `Download` link must be exactly `https://github.com/cpoteet/Quill/releases/latest/download/Quill.zip` (`grep -n 'releases/' site/*.html`).
3. **Stale statements:** for each item in the release notes, `grep -n` the site for the old behavior, labels and names, and correct every hit. Include the install, first-launch, requirements and update sections of `index.html` and `docs.html`.
4. **Contents links:** every `href="#…"` on a page you edited must still resolve to an `id` on that page.

List every change you made, and anything that looks wrong but isn't clearly stale, as a question for the user.

### Step 8 — Commit, then push only after publishing

```bash
git add site/ && git commit -m "docs: changelog and site for <version>"
gh release view "v<version>" --repo cpoteet/Quill --json isDraft -q .isDraft
```

Pushing `site/` deploys the site immediately (`.github/workflows/pages.yml`). Push only when `isDraft` is `false`. While it's still a draft, tell the user the commit is waiting and push after they confirm the release is published. Then verify:

```bash
git push && git fetch --tags
curl -sIL -o /dev/null -w '%{http_code}\n' https://github.com/cpoteet/Quill/releases/latest/download/Quill.zip
gh api repos/cpoteet/Quill/releases/latest -q .tag_name
```

Expected: `200` and `v<version>`.

---

## Quick reference

| Step | Action | Stop if… |
|---|---|---|
| 0 | Ask for the version if missing; fetch tags; check the tree is clean; push; `./test.sh` | Dirty tree, tag exists, tests fail |
| 1 | Bump both version keys in `build.sh`, commit, push | — |
| 2 | Quit Quill; `Scripts/notarize.sh` in the background; record `SHA` | — |
| 3 | Subagent drafts the notes; save them to `$TMPDIR` | — |
| 4 | Log ends `✓ Notarized`; rebuild the dev app; install the notarized app in `/Applications` | Anything else |
| 5 | `gh release create --draft --target $SHA … Quill.zip`, then **wait for the user** | — |
| 6 | Final notes from GitHub → new article in `changelog.html` | — |
| 7 | Badge, download links, stale statements, anchors | — |
| 8 | Commit; push only once the release is published; check the download 200s and latest is `v<version>` | Release still a draft |

## Red flags

- Publishing the release or marking it latest yourself: the user publishes.
- Uploading the asset under any name other than `Quill.zip`.
- Creating the draft before the log shows `✓ Notarized`.
- Targeting `main` instead of `$SHA`: commits pushed after Step 2 would end up in a tag they weren't built from.
- Pushing `site/` while the release is still a draft: the site would announce a version the Download button doesn't serve.
- Writing the changelog from your draft instead of the notes read back from GitHub.
- Running `store-credentials` or handling the Apple ID password yourself.
