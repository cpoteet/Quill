# Quill Open-Source Release — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `cpoteet/Quill` public, host the Quill website from `site/` in that repo at `quill.siolon.com`, publish the 12 existing draft releases, switch the in-app update check to the GitHub releases API, and retire the `Quill-Releases` repository.

**Architecture:** Nothing about the app's internals changes. This is a distribution change. One Swift file swaps its remote data source from a hand-written `version.json` to the GitHub releases API. Three hard-coded URLs move to the new domain. The website becomes a `site/` directory published by a GitHub Actions Pages workflow. Everything else is repository hygiene and one-time operational steps.

**Tech Stack:** Swift 6.3.1, swift-testing, GitHub Actions, GitHub Pages, the `gh` CLI.

**Spec:** `docs/superpowers/specs/2026-09-20-open-source-release-design.md`

## Global Constraints

- The app version stays at `1.11.0` for all of Phase 1. Bumping it to `2.0.0` is Phase 2 work and must not happen here.
- Every release asset must be named exactly `Quill.zip`. The site's download link is `https://github.com/cpoteet/Quill/releases/latest/download/Quill.zip`, which resolves by asset name.
- The new site URL is `https://quill.siolon.com`. No page, document, or source file may still reference `cpoteet.github.io/Quill-Releases` when Phase 1 is done.
- The 12 draft releases publish oldest first: `v1.0.0`, `v1.1.0`, `v1.2.0`, `v1.3.0`, `v1.4.0`, `v1.5.0`, `v1.6.0`, `v1.7.0`, `v1.8.0`, `v1.9.0`, `v1.10.0`, `v1.11.0`.
- Do not delete or disable `Quill-Releases` until Task 9 has finished. Task 9 downloads `Quill.zip` from that site.
- Work directly on `main`. Do not create a branch.
- Do not commit anything unless a step says to commit.
- Comments follow `CLAUDE.md`: default to none. Do not add a comment that restates the code.

## File Structure

| Path | Status | Responsibility |
|---|---|---|
| `Sources/QuillKit/App/UpdateChecker.swift` | Modify | Reads the GitHub releases API; normalizes the `v` tag prefix |
| `Tests/QuillTests/UpdateCheckerTests.swift` | Modify | Adds coverage for tag normalization |
| `Sources/QuillKit/App/QuillApp.swift` | Modify | Help menu URLs; new Changelog item |
| `Sources/QuillKit/Views/Settings/AboutView.swift` | Modify | EULA link URL |
| `LICENSE` | Modify | One paragraph permitting reading of the published source |
| `README.md` | Rewrite | Short repo-facing readme that points at the site |
| `site/` | Create | The public website, deployed to `quill.siolon.com` |
| `.github/workflows/pages.yml` | Create | Builds and deploys `site/` to GitHub Pages |
| `.claude/skills/wrap-up/SKILL.md` | Modify | Deploy step uploads the ZIP to a GitHub release |
| `docs/Privacy.md`, `docs/user-guide.md`, `docs/testing-plan.md` | Modify | Stale `Quill-Releases` URLs |

## Task Order and Dependencies

Tasks 1 through 8 are ordinary repository work and can be done in any order, though the numbering is the cleanest sequence. Tasks 9, 10 and 11 are one-time operational steps that must run in order, after 1 through 8 are committed.

---

## Task 1: Repository hygiene and stale documentation URLs

**Files:**
- Delete from index: `.superpowers/brainstorm/2463-1779406854/state/server.log`
- Delete from index: `.superpowers/brainstorm/2463-1779406854/state/server.pid`
- Delete from index: `.superpowers/brainstorm/2575-1779406862/state/server.log`
- Delete from index: `.superpowers/brainstorm/2575-1779406862/state/server.pid`
- Modify: `docs/Privacy.md:52`
- Modify: `docs/user-guide.md:56`
- Modify: `docs/testing-plan.md:2912-2913`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing other tasks depend on.

- [ ] **Step 1: Confirm which stray files are tracked**

```bash
git ls-files .superpowers
```

Expected: exactly the four paths listed above. `.gitignore` already contains `.superpowers/`; these four were committed before that rule existed.

- [ ] **Step 2: Untrack them**

```bash
git rm --cached .superpowers/brainstorm/2463-1779406854/state/server.log \
                .superpowers/brainstorm/2463-1779406854/state/server.pid \
                .superpowers/brainstorm/2575-1779406862/state/server.log \
                .superpowers/brainstorm/2575-1779406862/state/server.pid
```

- [ ] **Step 3: Verify they are gone from the index and still on disk**

```bash
git ls-files .superpowers && echo "STILL TRACKED — STOP" || echo "untracked, ok"
ls .superpowers/brainstorm
```

Expected: no tracked files, and the directories still present locally.

- [ ] **Step 4: Fix the issues link in `docs/Privacy.md:52`**

Replace this line:

```markdown
Questions or concerns? Open an issue at [github.com/cpoteet/Quill-Releases](https://github.com/cpoteet/Quill-Releases/issues).
```

with:

```markdown
Questions or concerns? Open an issue at [github.com/cpoteet/Quill](https://github.com/cpoteet/Quill/issues).
```

- [ ] **Step 5: Fix the download link in `docs/user-guide.md:56`**

Replace this line:

```markdown
Quill is available for free at [cpoteet.github.io/Quill-Releases](https://cpoteet.github.io/Quill-Releases/). Download the latest release, unzip the file, and drag **Quill.app** into your `/Applications` folder.
```

with:

```markdown
Quill is available for free at [quill.siolon.com](https://quill.siolon.com/). Download the latest release, unzip the file, and drag **Quill.app** into your `/Applications` folder.
```

- [ ] **Step 6: Fix the update-checker checklist in `docs/testing-plan.md`**

Find section `### 7.21 Update checker`. Replace its first two checklist lines:

```markdown
- [ ] Launch the app → if a newer version is available at `cpoteet.github.io/Quill-Releases/version.json`, a banner appears in the sidebar with the new version number.
- [ ] Click "View Release" → opens the changelog URL in the default browser.
```

with:

```markdown
- [ ] Launch the app → if the latest release at `api.github.com/repos/cpoteet/Quill/releases/latest` has a higher version than the running build, a banner appears in the sidebar with the new version number.
- [ ] Click "View Release" → opens that release's GitHub page in the default browser.
- [ ] The banner version number has no leading `v`, even though the Git tag does.
```

- [ ] **Step 7: Confirm no stale URL remains in these three files**

```bash
grep -n "Quill-Releases" docs/Privacy.md docs/user-guide.md docs/testing-plan.md || echo "clean"
```

Expected: `clean`.

- [ ] **Step 8: Commit**

```bash
git add -A .superpowers docs/Privacy.md docs/user-guide.md docs/testing-plan.md
git commit -m "chore: untrack stray state files and repoint docs at the new site

Removes four .superpowers server log and PID files committed before the
gitignore rule existed. Points the Privacy, user guide and testing plan
URLs at github.com/cpoteet/Quill and quill.siolon.com.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 2: Amend the EULA for published source

**Files:**
- Modify: `LICENSE` — Section 2, after the bullet list that ends at line 40

**Interfaces:**
- Consumes: nothing.
- Produces: the paragraph text reused verbatim in Task 6 for `site/license.html`.

**Why:** `LICENSE:33` forbids the reader to "attempt to discover the source code". Once the repository is public, that source sits in the same repository as the sentence forbidding its discovery. Only that contradiction is being removed. Every other restriction stays.

- [ ] **Step 1: Locate the insertion point**

```bash
grep -n "written permission from the Licensor" LICENSE
```

Expected: one hit, the final bullet of Section 2. The new paragraph goes after that bullet and before the `3.` heading.

- [ ] **Step 2: Insert the paragraph**

Add exactly this text, separated by a blank line above and below, after the final bullet of Section 2:

```
Notwithstanding the foregoing, the Licensor publishes the Software's source code in a
public repository for reference and transparency. Reading that published source code is
permitted and does not violate this Section. That publication grants no license to the
source code: you may not modify, adapt, redistribute, or create derivative works from it,
and every other restriction in this Section continues to apply in full.
```

Do not renumber any section. Do not change any existing sentence.

- [ ] **Step 3: Verify the structure is intact**

```bash
grep -n "^[0-9]\+\. " LICENSE
```

Expected: the section numbers run in unbroken order, unchanged from before the edit.

- [ ] **Step 4: Commit**

```bash
git add LICENSE
git commit -m "legal: permit reading the published source in the EULA

Section 2 forbade attempting to discover the source code, which
contradicts publishing that source in the same repository. Reading is now
permitted. No other restriction changes: modification, redistribution and
derivative works remain prohibited.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 3: Rewrite the README

**Files:**
- Rewrite: `README.md`

**Interfaces:**
- Consumes: the screenshot path `site/images/post-view.png`, created in Task 6.
- Produces: nothing other tasks depend on.

**Why:** The current README is 176 lines that duplicate the website and contain three factual errors. It claims macOS 13 Ventura, but `CLAUDE.md` states macOS 27 only. It names an `Auth/KeychainStore`, but the type is `CredentialsStore`. It says "SwiftUI (macOS 13+)". The site sells the app; the README serves someone standing in the repository.

**Ordering note:** the screenshot referenced below does not exist until Task 6 copies `images/` into `site/`. Either run Task 6 first, or accept a broken image link until it does. The commit is still valid either way.

- [ ] **Step 1: Replace the entire file**

Write `README.md` with exactly this content:

````markdown
# Quill

A native macOS app for writing and managing WordPress content.

Quill connects to any self-hosted WordPress site through the built-in REST API and Application Passwords. No plugin, no third-party service, no subscription.

**[Download, documentation and changelog → quill.siolon.com](https://quill.siolon.com)**

![Quill editing a post](site/images/post-view.png)

## Requirements

- macOS 27 or later
- A self-hosted WordPress site running WordPress 7.0 or later, served over HTTPS
- WordPress.com is not supported

## Build

Building needs Swift 6.3.1 and a full Xcode install. `build.sh` compiles the asset catalog with `actool`, which the Command Line Tools alone do not provide.

```bash
./build.sh && open Quill.app
```

The test suite needs `node` and `jsdom` installed in `Scripts/`, not in the project root.

```bash
./test.sh
```

## Architecture

Start with [CLAUDE.md](CLAUDE.md). It maps `Sources/QuillKit`, records the key design decisions, and indexes the per-directory gotcha files. Longer notes live in [docs/](docs/).

## License

Quill is **not** open source. The source is published for reference and transparency under the terms in [LICENSE](LICENSE), which grants no right to modify, redistribute, or create derivative works.

Third-party components are listed in [NOTICES](NOTICES).
````

- [ ] **Step 2: Verify the length and that no stale URL survives**

```bash
wc -l README.md
grep -n "Quill-Releases\|macOS 13\|KeychainStore" README.md || echo "clean"
```

Expected: roughly 40 lines, and `clean`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: rewrite the README as a short repo-facing entry point

Cuts 176 lines to about 40 and points readers at quill.siolon.com for
download, docs and changelog. Corrects three stale facts: the macOS floor
is 27 not 13, the credential type is CredentialsStore not KeychainStore,
and the SwiftUI target is macOS 27.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 4: Update checker reads the GitHub releases API

**Files:**
- Modify: `Sources/QuillKit/App/UpdateChecker.swift:9` and `:17-49`
- Test: `Tests/QuillTests/UpdateCheckerTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `UpdateChecker.normalizeVersion(_ tag: String) -> String`, internal and static. Strips one leading `v` from a Git tag. `UpdateChecker.check()` keeps its existing signature, `() async throws -> UpdateInfo?`, and `UpdateInfo` is unchanged.

**The trap this task exists to avoid:** `isNewer` at `UpdateChecker.swift:51` splits on `.` and maps with `Int()`, discarding anything that fails to parse. The API returns `tag_name` as `v2.0.0`. `Int("v2")` is nil, so `["v2","0","0"]` collapses to `[0, 0]` and the comparison reports no update — silently, forever, with no error anywhere. The `v` must be stripped before comparison.

- [ ] **Step 1: Write the failing tests**

Add these five tests inside the existing `UpdateCheckerTests` struct in `Tests/QuillTests/UpdateCheckerTests.swift`:

```swift
    @Test func stripsLeadingVFromTag() {
        #expect(UpdateChecker.normalizeVersion("v2.0.0") == "2.0.0")
    }

    @Test func leavesBareVersionUnchanged() {
        #expect(UpdateChecker.normalizeVersion("2.0.0") == "2.0.0")
    }

    @Test func stripsOnlyTheFirstCharacter() {
        #expect(UpdateChecker.normalizeVersion("v1.11.0") == "1.11.0")
    }

    @Test func normalizedTagIsNewerThanCurrentBuild() {
        #expect(UpdateChecker.isNewer(remote: UpdateChecker.normalizeVersion("v2.0.0"), local: "1.11.0"))
    }

    @Test func unnormalizedTagSilentlyFailsToCompare() {
        #expect(!UpdateChecker.isNewer(remote: "v2.0.0", local: "1.11.0"))
    }
```

The last test documents the trap rather than guarding a feature. Leave it in. It is the reason `normalizeVersion` exists, and it fails loudly if someone later "simplifies" the call site.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --filter UpdateCheckerTests
```

Expected: a compile error, because `normalizeVersion` does not exist yet.

- [ ] **Step 3: Replace the URL constant**

In `Sources/QuillKit/App/UpdateChecker.swift`, replace line 9:

```swift
    private static let versionURL = URL(string: "https://cpoteet.github.io/Quill-Releases/version.json")!
```

with:

```swift
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/cpoteet/Quill/releases/latest")!
```

- [ ] **Step 4: Replace the body of `check()`**

Replace the whole `check()` function, keeping its existing doc comment above it untouched:

```swift
    public static func check() async throws -> UpdateInfo? {
        struct ReleasePayload: Decodable {
            let tagName: String
            let htmlURL: String

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case htmlURL = "html_url"
            }
        }

        guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return nil
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(ReleasePayload.self, from: data)
        let remoteVersion = normalizeVersion(payload.tagName)

        let dismissed = UserDefaults.standard.string(forKey: dismissedKey)
        guard isNewer(remote: remoteVersion, local: currentVersion),
              remoteVersion != dismissed,
              let releaseURL = URL(string: payload.htmlURL) else {
            return nil
        }

        return UpdateInfo(version: remoteVersion, url: releaseURL)
    }

    static func normalizeVersion(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }
```

Three things to note while editing. The existing doc comment on `check()` describes throwing on transport failure versus returning `nil` for "no update", and that contract is unchanged — keep the comment. `normalizeVersion` is `static` without `private` so `@testable import` can reach it. The dismissed-version comparison uses the normalized string, which matches what `dismiss(_:)` stores, because callers pass `UpdateInfo.version`.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
swift test --filter UpdateCheckerTests
```

Expected: all 12 tests pass — the 7 that already existed plus the 5 new ones.

- [ ] **Step 6: Run the whole suite**

```bash
./test.sh
```

Expected: all suites pass. Correct the test count line in `docs/testing-plan.md` and in `CLAUDE.md`, which both currently read 455 Swift tests. Five were added, so it becomes 460.

- [ ] **Step 7: Commit**

```bash
git add Sources/QuillKit/App/UpdateChecker.swift Tests/QuillTests/UpdateCheckerTests.swift docs/testing-plan.md CLAUDE.md
git commit -m "feat: read updates from the GitHub releases API

Replaces the hand-maintained version.json with the latest-release
endpoint on cpoteet/Quill. Adds normalizeVersion to strip the tag's v
prefix: isNewer parses segments with Int() and drops what fails, so a raw
v2.0.0 tag compared as [0,0] and reported no update with no error. A test
pins that failure mode so it cannot come back.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 5: In-app URLs and the Changelog menu item

**Files:**
- Modify: `Sources/QuillKit/App/QuillApp.swift:85-89`
- Modify: `Sources/QuillKit/Views/Settings/AboutView.swift:25`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing other tasks depend on.

- [ ] **Step 1: Replace the Help command group**

In `Sources/QuillKit/App/QuillApp.swift`, replace:

```swift
            CommandGroup(replacing: .help) {
                Button("Quill Help") {
                    NSWorkspace.shared.open(URL(string: "https://cpoteet.github.io/Quill-Releases/docs.html")!)
                }
            }
```

with:

```swift
            CommandGroup(replacing: .help) {
                Button("Quill Help") {
                    NSWorkspace.shared.open(URL(string: "https://quill.siolon.com/docs.html")!)
                }
                Button("Changelog") {
                    NSWorkspace.shared.open(URL(string: "https://quill.siolon.com/changelog.html")!)
                }
            }
```

- [ ] **Step 2: Repoint the EULA link**

In `Sources/QuillKit/Views/Settings/AboutView.swift:25`, change the destination only. Leave the label and every modifier as they are:

```swift
                Link("End User Licensing Agreement", destination: URL(string: "https://quill.siolon.com/license.html")!)
```

- [ ] **Step 3: Confirm no stale URL remains in Swift sources**

```bash
grep -rn "Quill-Releases" Sources/ || echo "clean"
```

Expected: `clean`.

- [ ] **Step 4: Build and check the menu by hand**

```bash
osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app
```

Then confirm three things in the running app. The Help menu lists both **Quill Help** and **Changelog**. Both open `quill.siolon.com` pages, which will 404 until Task 10 sets up the domain — a GitHub 404 page is the correct result at this stage, and proves the URL is right. The About window's EULA link points at the new host.

- [ ] **Step 5: Commit**

```bash
git add Sources/QuillKit/App/QuillApp.swift Sources/QuillKit/Views/Settings/AboutView.swift
git commit -m "feat: add a Changelog item and move help links to quill.siolon.com

Help gains a Changelog entry beside Quill Help. Both, and the About
window's EULA link, now point at the new site instead of the
Quill-Releases project page.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 6: Import the website into `site/`

**Files:**
- Create: `site/index.html`, `site/docs.html`, `site/changelog.html`, `site/license.html`, `site/privacy.html`
- Create: `site/style.css`
- Create: `site/images/` (5 PNG files)
- Create: `site/CNAME`

**Interfaces:**
- Consumes: the EULA paragraph written in Task 2.
- Produces: `site/` as the directory that Task 7's workflow deploys, and `site/images/post-view.png` as the README screenshot from Task 3.

**Why the path edits are needed:** the site is currently a GitHub project page served under the `/Quill-Releases/` prefix. A custom domain serves it from the root, so every absolute path containing that prefix becomes a 404.

- [ ] **Step 1: Copy the site in**

```bash
git clone --depth 1 https://github.com/cpoteet/Quill-Releases.git "${TMPDIR:-/tmp}/quill-site"
mkdir -p site
cp "${TMPDIR:-/tmp}"/quill-site/{index,docs,changelog,license,privacy}.html site/
cp "${TMPDIR:-/tmp}"/quill-site/style.css site/
cp -R "${TMPDIR:-/tmp}"/quill-site/images site/
```

Do not copy `Quill.zip`, `version.json`, `README.md`, or `.gitignore`. The ZIP becomes a release asset in Task 9. `version.json` has no successor, because Task 4 moved the update check to the API.

- [ ] **Step 2: Verify what landed**

```bash
ls -R site
```

Expected: five HTML files, `style.css`, and `images/` holding `ai-writing.png`, `draft-view.png`, `media-view.png`, `page-view.png`, `post-view.png`.

- [ ] **Step 3: Rewrite the three repeated URL patterns**

All five pages carry an identical nav logo on line 16 and an identical download button on line 21, so one pass over the directory handles them.

```bash
cd site
sed -i '' 's|href="/Quill-Releases/"|href="/"|g' *.html
sed -i '' 's|https://cpoteet.github.io/Quill-Releases/Quill.zip|https://github.com/cpoteet/Quill/releases/latest/download/Quill.zip|g' *.html
sed -i '' 's|https://github.com/cpoteet/Quill-Releases/issues|https://github.com/cpoteet/Quill/issues|g' *.html
cd ..
```

- [ ] **Step 4: Fix the prose link in `site/docs.html`**

This one is body text, not a repeated template line, so `sed` does not cover it. Replace:

```html
        <p class="docs-body">Quill is available for free at <a href="https://cpoteet.github.io/Quill-Releases/" class="content-link" target="_blank" rel="noopener">cpoteet.github.io/Quill-Releases</a>. Download the latest release, unzip the file, and drag <strong>Quill.app</strong> into your <code>/Applications</code> folder.</p>
```

with:

```html
        <p class="docs-body">Quill is available for free at <a href="/" class="content-link">quill.siolon.com</a>. Download the latest release, unzip the file, and drag <strong>Quill.app</strong> into your <code>/Applications</code> folder.</p>
```

The link is now same-site, so `target="_blank"` and `rel="noopener"` are dropped.

- [ ] **Step 5: Fix the prose link in `site/changelog.html`**

This sits inside the historical v1.7.0 entry. The URL it names is about to stop existing, so it is updated rather than preserved. Replace:

```html
            <p class="release__body">The <strong>Help → Quill Help</strong> menu item now opens the online documentation at <a href="https://cpoteet.github.io/Quill-Releases/docs.html" class="content-link" target="_blank" rel="noopener">cpoteet.github.io/Quill-Releases/docs.html</a>.</p>
```

with:

```html
            <p class="release__body">The <strong>Help → Quill Help</strong> menu item now opens the online documentation at <a href="docs.html" class="content-link">quill.siolon.com/docs.html</a>.</p>
```

- [ ] **Step 6: Mirror the EULA amendment into `site/license.html`**

`site/license.html` is the web rendering of `LICENSE`. Find the Section 2 restrictions list and add the same paragraph written in Task 2, marked up to match the page's existing paragraph style. Use the exact wording:

> Notwithstanding the foregoing, the Licensor publishes the Software's source code in a public repository for reference and transparency. Reading that published source code is permitted and does not violate this Section. That publication grants no license to the source code: you may not modify, adapt, redistribute, or create derivative works from it, and every other restriction in this Section continues to apply in full.

- [ ] **Step 7: Add the CNAME file**

```bash
printf 'quill.siolon.com\n' > site/CNAME
```

GitHub also records the custom domain in the Pages settings. This file makes the deployment self-describing and survives a settings reset.

- [ ] **Step 8: Verify no reference to the old repo survives**

```bash
grep -rn "Quill-Releases" site/ && echo "FOUND — fix before committing" || echo "clean"
```

Expected: `clean`. This grep is the whole safety net for this task. A missed absolute path looks perfectly fine in review and 404s in production.

- [ ] **Step 9: Check the pages render**

```bash
cd site && python3 -m http.server 8000
```

Open `http://localhost:8000/` and click through the nav on every page: logo, Docs, Changelog, Download. The Download button will point at a GitHub release that has no asset until Task 9, so a 404 there is expected now. Everything else must resolve. Stop the server with Ctrl-C.

- [ ] **Step 10: Commit**

```bash
git add site
git commit -m "feat: move the public website into site/

Imports the five pages, stylesheet and images from the Quill-Releases
repo. Rewrites every /Quill-Releases/ absolute path for root-served
hosting, repoints the download button at the latest GitHub release asset,
and mirrors the EULA published-source paragraph into license.html. Adds
the CNAME for quill.siolon.com.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 7: GitHub Pages deployment workflow

**Files:**
- Create: `.github/workflows/pages.yml`

**Interfaces:**
- Consumes: `site/` from Task 6.
- Produces: a deployment to GitHub Pages on every push to `main` that touches `site/`.

**Why Actions rather than branch deploy:** deploying from a branch restricts the source folder to the repository root or `docs/`. `docs/` already holds 13 engineering documents, which would then be served publicly, and renaming it would break every path in `CLAUDE.md`. The Actions method has no folder restriction.

- [ ] **Step 1: Create the workflow**

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

- [ ] **Step 2: Check the YAML parses**

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/pages.yml')); print('valid')"
```

Expected: `valid`.

- [ ] **Step 3: Commit**

The workflow cannot run yet. GitHub Pages is not enabled on this repository, and the repository is still private on a Free plan. Task 10 turns both on, and the first deployment happens there.

```bash
git add .github/workflows/pages.yml
git commit -m "ci: deploy site/ to GitHub Pages on push

Uses the Actions deployment method rather than branch deploy, which would
restrict the source to the repo root or docs/ — and docs/ holds internal
engineering documentation that should not be served.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 8: Teach the wrap-up skill to publish releases

**Files:**
- Modify: `.claude/skills/wrap-up/SKILL.md` — the "Deployment step" section and the Quick Reference table

**Interfaces:**
- Consumes: nothing.
- Produces: the documented release procedure that Phase 2 follows.

**Why:** the deploy step currently builds `~/Desktop/Quill.zip` and stops. That ZIP used to be copied into the `Quill-Releases` repository by hand. It now has to become a release asset, and its name is load-bearing: the site's download link resolves `Quill.zip` by name against the latest release.

- [ ] **Step 1: Replace the deployment section**

Replace the whole `## Deployment step (only when `deploy` argument present)` section with:

````markdown
## Deployment step (only when `deploy` argument present)

### Step 11 — Package Quill.zip

```bash
cd "/Users/Chris/Documents/Claude/WP Mac App"
./build.sh
rm -f ~/Desktop/Quill.zip
zip -r ~/Desktop/Quill.zip Quill.app LICENSE
```

**The name `Quill.zip` is load-bearing.** Every page of the site links to
`https://github.com/cpoteet/Quill/releases/latest/download/Quill.zip`, which
GitHub resolves by asset name against whichever release is marked latest. A ZIP
uploaded under any other name breaks the download button site-wide.

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
````

- [ ] **Step 2: Add the row to the Quick Reference table**

After the existing row for step 11, add:

```markdown
| 12 | Attach ZIP to a GitHub release, mark latest, verify the download 200s | all | Build failed |
```

- [ ] **Step 3: Add the red flag**

In the `## Red Flags` list, add:

```markdown
- **Never** upload a release asset under a name other than `Quill.zip` — the site's download link resolves by asset name and breaks site-wide
```

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/wrap-up/SKILL.md
git commit -m "chore: extend the wrap-up deploy step to publish GitHub releases

The ZIP used to be copied into the Quill-Releases repo by hand. It is now
a release asset. Records that the Quill.zip filename is load-bearing,
since the site's download link resolves by asset name.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 9: Publish the 12 draft releases

**Files:** none. This is an operational task against the GitHub API.

**Interfaces:**
- Consumes: the `Quill.zip` still served by `cpoteet.github.io/Quill-Releases`.
- Produces: 12 published releases, with `v1.11.0` marked latest and carrying a `Quill.zip` asset. Task 11's verification depends on this.

**Background:** all 12 tags already exist on the remote with their true commit dates. Publishing a draft does not create a tag. GitHub stamps a release with the moment it is published and the API cannot backdate it, so all 12 will display today's date. The true date goes in the note body instead.

**Warning:** Step 5 downloads from `cpoteet.github.io/Quill-Releases`. Do not disable or delete that repository before this task completes. Task 10 retires it.

- [ ] **Step 1: Confirm the starting state**

```bash
gh release list --repo cpoteet/Quill --limit 20
```

Expected: 12 entries, every one marked `Draft`, from `v1.0.0` to `v1.11.0`.

- [ ] **Step 2: Build the note files with the true dates prepended**

```bash
NOTES_DIR="${TMPDIR:-/tmp}/quill-notes"
mkdir -p "$NOTES_DIR"
for pair in v1.0.0:2026-05-24 v1.1.0:2026-05-26 v1.2.0:2026-05-29 v1.3.0:2026-06-01 \
            v1.4.0:2026-06-06 v1.5.0:2026-06-07 v1.6.0:2026-06-12 v1.7.0:2026-06-15 \
            v1.8.0:2026-06-17 v1.9.0:2026-06-26 v1.10.0:2026-07-10 v1.11.0:2026-08-20; do
  tag="${pair%%:*}"; date="${pair##*:}"
  body=$(gh release view "$tag" --repo cpoteet/Quill --json body --jq '.body')
  printf '_Released %s_\n\n%s\n' "$date" "$body" > "$NOTES_DIR/$tag.md"
done
ls "$NOTES_DIR"
```

The `pair` loop avoids bash associative arrays, which macOS's bundled bash 3.2 does not support.

- [ ] **Step 3: Inspect one before applying any of them**

```bash
head -8 "${TMPDIR:-/tmp}/quill-notes/v1.11.0.md"
wc -l "${TMPDIR:-/tmp}"/quill-notes/*.md
```

Expected: the file opens with `_Released 2026-08-20_`, a blank line, then the original note. Every file has more than 2 lines — a 2-line file means `gh release view` returned an empty body and that release's notes were lost. Stop and investigate if so.

- [ ] **Step 4: Publish them, oldest first**

GitHub resolves "latest" by publish time. Publishing out of order marks an old version latest and points the site's download link at a release with no asset. The `sleep` keeps the publish timestamps distinct and ordered.

```bash
NOTES_DIR="${TMPDIR:-/tmp}/quill-notes"
for tag in v1.0.0 v1.1.0 v1.2.0 v1.3.0 v1.4.0 v1.5.0 \
           v1.6.0 v1.7.0 v1.8.0 v1.9.0 v1.10.0 v1.11.0; do
  echo "publishing $tag"
  gh release edit "$tag" --repo cpoteet/Quill \
    --notes-file "$NOTES_DIR/$tag.md" --draft=false
  sleep 3
done
```

- [ ] **Step 5: Attach the 1.11.0 build to `v1.11.0`**

This is what keeps the site's download button working through the whole testing period, before 2.0.0 exists. The ZIP at that URL has been verified to contain `CFBundleShortVersionString` `1.11.0`.

```bash
NOTES_DIR="${TMPDIR:-/tmp}/quill-notes"
curl -sL -o "$NOTES_DIR/Quill.zip" https://cpoteet.github.io/Quill-Releases/Quill.zip
unzip -o -q "$NOTES_DIR/Quill.zip" -d "$NOTES_DIR/zcheck"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$NOTES_DIR/zcheck/Quill.app/Contents/Info.plist"
```

Expected: `1.11.0`. Stop if it prints anything else.

```bash
gh release upload v1.11.0 --repo cpoteet/Quill "${TMPDIR:-/tmp}/quill-notes/Quill.zip"
```

The other 11 releases stay note-only. Those builds no longer exist.

- [ ] **Step 6: Mark `v1.11.0` as latest explicitly**

```bash
gh release edit v1.11.0 --repo cpoteet/Quill --latest
```

- [ ] **Step 7: Verify**

```bash
gh release list --repo cpoteet/Quill --limit 20
gh api repos/cpoteet/Quill/releases/latest --jq '{tag: .tag_name, assets: [.assets[].name]}'
```

Expected: 12 entries, none marked `Draft`, `v1.11.0` marked `Latest`, and the API reporting `{"tag": "v1.11.0", "assets": ["Quill.zip"]}`.

---

## Task 10: Go public, enable Pages, cut over the domain

**Files:** none. This is an operational task.

**Interfaces:**
- Consumes: Tasks 1 through 9, all committed and pushed.
- Produces: a live site at `quill.siolon.com` and a public repository.

**Warning:** step 3 cannot be cleanly undone. Anything published can be copied before a reversal takes effect. Confirm every earlier task is committed and pushed first.

- [ ] **Step 1: Confirm the working tree is clean and pushed**

```bash
git status --short
git log origin/main..HEAD --oneline
```

Expected: no output from either command.

- [ ] **Step 2: Final content sweep**

```bash
grep -rn "Quill-Releases" --include='*.swift' --include='*.html' --include='*.md' --include='*.css' . \
  | grep -v '^./docs/superpowers/' | grep -v '^./.git/' || echo "clean"
```

Expected: `clean`. Hits under `docs/superpowers/` are historical specs and plans, including this one, and are fine to leave.

- [ ] **Step 3: Make the repository public**

GitHub web UI: **Settings → General → Danger Zone → Change repository visibility → Make public**.

- [ ] **Step 4: Set the repository metadata**

```bash
gh repo edit cpoteet/Quill \
  --description "A native macOS app for writing and managing WordPress content" \
  --homepage "https://quill.siolon.com" \
  --add-topic macos --add-topic swift --add-topic swiftui \
  --add-topic wordpress --add-topic tiptap --add-topic editor \
  --enable-issues
```

- [ ] **Step 5: Enable Pages with the Actions source**

GitHub web UI: **Settings → Pages → Build and deployment → Source → GitHub Actions**.

Then trigger the first deployment:

```bash
gh workflow run "Deploy site" --repo cpoteet/Quill
gh run watch --repo cpoteet/Quill
```

Expected: the run succeeds. Confirm the site loads at the `github.io` URL it reports before moving on to DNS.

- [ ] **Step 6: Confirm DNS resolves**

The `CNAME` record for `quill` pointing at `cpoteet.github.io` is added by hand in the `mddservices.com` control panel. This may already be done.

```bash
dig +short quill.siolon.com
```

Expected: `cpoteet.github.io`, followed by four addresses starting with `185.199`.

- [ ] **Step 7: Set the custom domain and enforce HTTPS**

GitHub web UI: **Settings → Pages → Custom domain** → enter `quill.siolon.com` → Save. Wait for the DNS check to pass, then tick **Enforce HTTPS**. Certificate issue can take up to an hour.

- [ ] **Step 8: Retire `Quill-Releases`**

Order matters here. Archiving a repository does not stop GitHub Pages serving it. Turning Pages off is what kills the old URL; archiving alone would leave the old site live with a stale download button.

1. In `cpoteet/Quill-Releases`: **Settings → Pages → Unpublish site** (or set the source to None).
2. Confirm it is dead:

```bash
curl -sI -o /dev/null -w '%{http_code}\n' https://cpoteet.github.io/Quill-Releases/
```

Expected: `404`.

3. Then **Settings → General → Danger Zone → Archive this repository**.

Deleting the repository outright is equally acceptable. Archiving is preferred only because it costs nothing and keeps the history.

---

## Task 11: Phase 1 verification

**Files:** none.

**Interfaces:**
- Consumes: Tasks 1 through 10.
- Produces: the evidence that Phase 1 is complete and Phase 2 can be started whenever testing finishes.

Run every check. Do not report Phase 1 complete with any row failing.

- [ ] **Step 1: Automated checks**

```bash
dig +short quill.siolon.com
curl -sI -o /dev/null -w 'site: %{http_code}\n' https://quill.siolon.com/
curl -sIL -o /dev/null -w 'download: %{http_code}\n' https://github.com/cpoteet/Quill/releases/latest/download/Quill.zip
curl -sI -o /dev/null -w 'old site: %{http_code}\n' https://cpoteet.github.io/Quill-Releases/
gh api repos/cpoteet/Quill/releases/latest --jq '{tag: .tag_name, assets: [.assets[].name]}'
grep -rn "Quill-Releases" site/ || echo "site clean"
```

| Check | Expected |
|---|---|
| `dig` | `cpoteet.github.io` plus four `185.199.*` addresses |
| site | `200` |
| download | `200` |
| old site | `404` |
| releases API | `{"tag": "v1.11.0", "assets": ["Quill.zip"]}` |
| site grep | `site clean` |

- [ ] **Step 2: Confirm the downloaded ZIP is the real build**

```bash
cd "${TMPDIR:-/tmp}" && rm -rf dlcheck && mkdir dlcheck && cd dlcheck
curl -sL -o Quill.zip https://github.com/cpoteet/Quill/releases/latest/download/Quill.zip
unzip -q Quill.zip
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Quill.app/Contents/Info.plist
```

Expected: `1.11.0`.

- [ ] **Step 3: Full test suite and the WebKit fixture check**

```bash
./test.sh
```

```bash
osascript -e 'quit app "Quill"' 2>&1; sleep 2 && ./build.sh 2>&1 && open Quill.app
```

```bash
./Quill.app/Contents/MacOS/Quill --check-fixtures "$PWD/Scripts/fixtures"
```

Expected: all suites pass, including the five new `UpdateChecker` tests, and the fixture check passes.

- [ ] **Step 4: Manual checks in the running app**

| Check | Expected |
|---|---|
| Help → Quill Help | opens `quill.siolon.com/docs.html` |
| Help → Changelog | opens `quill.siolon.com/changelog.html` |
| About window → End User Licensing Agreement | opens `quill.siolon.com/license.html` |
| Sidebar update banner | does **not** appear |

The last row is the important one. The running build is 1.11.0 and the latest release is `v1.11.0`, so the correct result is silence. It proves the API path works, the `v` prefix is being stripped, and the comparison is reaching `isNewer` with usable input — all without needing 2.0.0 to exist.

To prove the banner still fires, temporarily set `CFBundleShortVersionString` in `build.sh:65` to `1.10.0`, rebuild, and confirm a banner appears naming 1.11.0 and opening the `v1.11.0` release page. **Set it back to `1.11.0` and rebuild before finishing.**

- [ ] **Step 5: Walk the site**

Open `https://quill.siolon.com` and click every nav link on all five pages: logo, Donate, Docs, Changelog, Download. Confirm the Download button delivers a ZIP. Confirm the footer's feedback link opens `github.com/cpoteet/Quill/issues`.

- [ ] **Step 6: Report Phase 1 complete**

State which checks ran and what each returned. Phase 2, the 2.0.0 release itself, is the numbered checklist at the end of `docs/superpowers/specs/2026-09-20-open-source-release-design.md`.

Note for Phase 2: `site/index.html:32` carries a version badge reading `v1.11 · macOS Tahoe`. It is accurate now and must be updated when 2.0.0 ships. The spec's Phase 2 step 2 covers the changelog entry; add this badge to that same edit.
