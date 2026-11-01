# Masthead Empty State — Implementation Plan

> **For agentic workers:** Ask Chris which execution method to use before starting: superpowers:executing-plans (one session does every task) or superpowers:subagent-driven-development (a fresh subagent per task). Do not pick one yourself. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace "Select a … to edit" and "No …s yet" with a masthead: the site's name over a double rule, a Continue writing item, and up to three scheduled posts, missed ones first.

**Architecture:** Pure static functions in a new `Masthead.swift` pick the Continue writing item and the scheduled list from `AppState`'s lists, the autosave stash times and the user's ID. `AppState` gains the user ID, the site name and the missed-schedule confirmation. A new `MastheadView` draws the page and replaces `EmptyEditorPlaceholder` in `ContentView` except for load failures.

**Tech Stack:** SwiftUI (macOS 27), Swift Testing, URLSession through `WordPressClient`, SQLite.swift (`AutosaveStore`), `JSONFileStore`.

**Spec:** `docs/superpowers/specs/2026-10-31-empty-state-masthead-design.md`. Read it in full before Task 1. Mockup: `docs/superpowers/specs/2026-10-31-empty-state-masthead-mockups.html`, Front page layout with SF Pro and Feather: None. The spec wins where they differ: no "Other drafts" list, no feather.

## Start here (for a fresh session)

**Project rules** (`~/.claude/CLAUDE.md`, repo `CLAUDE.md`):

- Work on `main`. **Do not commit** unless Chris asks. Each task ends with a check-in, not a commit. When he asks to commit: run `codex review --uncommitted -c model="gpt-6.1-sol" -c model_reasoning_effort="high"`, show the findings, check each against the code, fix the ones that hold, say which you rejected and why, then commit.
- Build after every code change with exactly `pkill -f "^$PWD/Quill.app/Contents/MacOS/Quill"; sleep 2 && ./build.sh 2>&1 && open Quill.app`. If the build fails, report the error instead of opening.
- `./test.sh` runs everything; Swift only: `swift test`, or `swift test --filter <Suite>`.
- Comments: default none, one line max, never narrate the change.

**Facts verified on 2026-10-31:**

- `ContentView.swift` (~50–64) shows `EmptyEditorPlaceholder(section:sectionIsEmpty:loadFailed:)` when nothing is selected and the list has loaded. `EmptyEditorPlaceholder` is defined in the same file (~67).
- Quill never restores the selection at launch; `SidebarView` sets `appState.selectedItem = nil` on a section switch.
- **Post list request:** `WordPressClient.fetchAllPaginated` (~38) sends `_fields=id,type,title,status,date,date_gmt,modified,slug,link,featured_media,categories,tags,parent,comment_status` with every status. There's no content, `author` or `modified_gmt`.
- **`WPPost`** (`API/Models/WPPost.swift`) has a hand-written `init(from:)`. New fields go in `CodingKeys` and decode with `decodeIfPresent`.
- **`endpoint(_:query:)`** in `WordPressClient` always builds `/wp-json/wp/v2/<path>`. The REST index (`/wp-json/`) needs its own URL built the same way, from `credentials.siteURL`.
- **`canPostUnfilteredHTML()`** (~243) fetches `users/me?context=edit` into a private `CurrentUser { capabilities }`, then a one-post request. `AppState.loadUnfilteredHTMLCapability()` (~187) runs it once, guarded by `canPostUnfilteredHTML == nil`. Its only caller is `PostEditorView` (~110), on editor ready.
- **Stashes:** `AutosaveStore` has `save`, `load(site:postID:)` and `delete`. The table has columns `site`, `post_id` and `saved_at` (a `Double`, Unix seconds) in `AppDatabase`.
- **Local drafts:** `LocalDraft { id, title, type, updatedAt, … }`, listed in `appState.localDrafts`. They aren't scoped to a site.
- **Selection plumbing:** `AppState.switchSection(to:then:)` (~215) and `createNewDraft` (~205), which clears `searchText` inside `then`. `statusFilter` is per section, with a setter that writes the current section's filter.
- **Credentials equality drives reloads** (`SidebarView` ~203, ~324: `credentials != lastLoadedCredentials`), so the site name must not go in `Credentials`.
- **Date parsing:** `PostSettings.parseWPDate(_:)` (`Views/Settings/PostSettingsPanel.swift` ~40) parses WordPress's GMT strings.
- **Shortcuts:** New Post ⌘N, New Page ⇧⌘N (`QuillApp.swift` ~123–130).
- Tests use Swift Testing (`@Suite`, `@Test`, `#expect`). `WordPressClientTests.swift` shows how requests are stubbed. `AppStateTests.swift` and `AutosaveStoreTests.swift` show the store and state patterns. `AppState.loadAIModelsIfNeeded(fetch:save:)` is the pattern for injecting a network call into `AppState`.

## Global Constraints

- SF Pro only, no serif and no feather. System semantic colours (`.primary`, `.secondary`, `.tertiary`, the accent). No new fonts or assets.
- Column at most 520pt wide, about 72pt from the top. Name: bold, about 46pt, tracking about -2.5%, centred, two lines max, scaling to about 32pt before truncating.
- Rule: 2pt `.primary` above, a hairline separator below, 7pt padding. Date (`.formatted(date: .complete, time: .omitted)`) on the left, host on the right, `.secondary`, about 12pt.
- Labels "continue writing" and "scheduled" in `.lowercaseSmallCaps()`, `.secondary`, about 15pt.
- Continue writing title about 23pt semibold. Scheduled rows: title about 16pt, a `.tertiary` dotted leader, date like "Tue 3 Nov" in tabular figures. Missed: "Missed schedule" in place of the date.
- Empty line: "Start a post with ⌘N" (Posts, Drafts), "Start a page with ⇧⌘N" (Pages).
- Meta lines, exact copy: "Draft · edited 2 hours ago"; "Draft · unsaved changes on this Mac"; "Published · unsaved changes on this Mac" (and Scheduled, Private); "Post draft · on this Mac · edited yesterday"; "Page draft · on this Mac · edited …". Named relative time up to 7 days, then the date ("12 Oct").
- Scheduled window: now to now + 14 days. Missed grace: 5 minutes. Cap: 3, missed included, missed first.
- Load failure ("Couldn't load …") and the loading spinner are unchanged. Media is unchanged.

## Review Focus

1. **Signed out, or no site yet:** the masthead must not crash or show an empty name. It shows only once credentials exist, and the name falls back to the host. (Task 5 test on `Masthead.displayName`.)
2. **A local draft with an empty title:** it shows "Untitled" (`PostItem.title`), not a blank line. (Task 3 test.)
3. **Two candidates with the same timestamp:** the result is deterministic, with remote first, then by ID. (Task 3 test.)
4. **Switching sites:** the masthead must not show the old site's name or stashes for a moment. Both are keyed by `siteKey`. (Task 2 test: the name lookup for a different `siteKey` returns nil.)
5. **A missed-schedule fetch that comes back after the user switched sites:** its result is dropped. (Task 4 test.)

---

## File structure

| File | Status | Responsibility |
|---|---|---|
| `Sources/QuillKit/API/Models/WPPost.swift` | Modify | `modifiedGmt`, `author`. |
| `Sources/QuillKit/API/WordPressClient.swift` | Modify | List `_fields`; `currentUser()`; `fetchSiteName()`. |
| `Sources/QuillKit/Storage/AutosaveStore.swift` | Modify | `stashTimes(site:)`. |
| `Sources/QuillKit/Storage/SiteProfileStore.swift` | Create | Site name per `siteKey`. |
| `Sources/QuillKit/App/AppState.swift` | Modify | `currentUserID`, `siteName`, `refreshSiteName`, `missedSchedules`, `confirmMissedSchedules`, `openFromMasthead`. |
| `Sources/QuillKit/App/Masthead.swift` | Create | Pure selection and copy functions. |
| `Sources/QuillKit/Views/MastheadView.swift` | Create | The page. |
| `Sources/QuillKit/Views/ContentView.swift` | Modify | Use `MastheadView`; start the user and site-name loads. |
| Tests | Create/Modify | `WPPostDecodingTests`, `WordPressClientTests`, `AutosaveStoreTests`, new `SiteProfileStoreTests`, new `MastheadTests`, `AppStateTests`. |
| Docs | Modify | Task 6. |

---

### Task 1: Post fields, user ID, stash times

**Files:**
- Modify: `Sources/QuillKit/API/Models/WPPost.swift`, `Sources/QuillKit/API/WordPressClient.swift`, `Sources/QuillKit/Storage/AutosaveStore.swift`, `Sources/QuillKit/App/AppState.swift`
- Test: `Tests/QuillTests/WPPostDecodingTests.swift`, `Tests/QuillTests/WordPressClientTests.swift`, `Tests/QuillTests/AutosaveStoreTests.swift`

**Interfaces:**
- Produces:
  - `WPPost.modifiedGmt: String` (`"modified_gmt"`, `""` when absent) and `WPPost.author: Int?` (`nil` when absent).
  - The list `_fields` gains `modified_gmt,author`.
  - `public struct CurrentUserInfo: Sendable, Equatable { public let id: Int; public let canPostUnfilteredHTML: Bool }` and `WordPressClient.currentUser() async throws -> CurrentUserInfo`. This replaces `canPostUnfilteredHTML()`: the same two requests, also decoding `id` from `users/me`.
  - `AppState.currentUserID: Int?` (`@Published`), set alongside `canPostUnfilteredHTML` in `loadUnfilteredHTMLCapability()`, and reset to `nil` in `connect(_:)` when the site changes.
  - `public struct StashTime: Sendable, Equatable { public let postID: Int; public let savedAt: Date }` and `AutosaveStore.stashTimes(site: String) throws -> [StashTime]`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func decodesModifiedGmtAndAuthor()          // JSON with "modified_gmt":"2026-10-31T09:00:00","author":3 → modifiedGmt, author == 3
@Test func modifiedGmtAndAuthorAreOptional()      // JSON without them → modifiedGmt == "", author == nil
@Test func listRequestAsksForModifiedGmtAndAuthor() // stubbed request's _fields contains "modified_gmt" and "author"
@Test func currentUserDecodesIDAndCapability()    // users/me {"id":7,"capabilities":{"unfiltered_html":true}} → id 7, canPost per the existing action-link rule
@Test func stashTimesListsOnlyThatSite()          // save for site A posts 1, 2 and site B post 3 → stashTimes(site: A) has 1 and 2 with their savedAt
```

- [ ] **Step 2: Run** `swift test --filter "WPPostDecodingTests|WordPressClientTests|AutosaveStoreTests"`. Expected: FAIL, the new members aren't defined.
- [ ] **Step 3: Implement** as specified. Update `canPostUnfilteredHTML`'s callers and existing tests to use `currentUser()`.
- [ ] **Step 4: Run** `swift test`. Expected: PASS.
- [ ] **Step 5: Check in with Chris.**

---

### Task 2: Site name

**Files:**
- Create: `Sources/QuillKit/Storage/SiteProfileStore.swift`, `Tests/QuillTests/SiteProfileStoreTests.swift`
- Modify: `Sources/QuillKit/API/WordPressClient.swift`, `Sources/QuillKit/App/AppState.swift`, `Sources/QuillKit/Views/ContentView.swift`
- Test: `Tests/QuillTests/WordPressClientTests.swift`, `Tests/QuillTests/AppStateTests.swift`

**Interfaces:**
- Produces:
  - `public struct SiteProfileStore: Sendable { init(in baseDirectory: URL? = nil); func name(for siteKey: String) -> String?; func setName(_ name: String?, for siteKey: String) throws }`, backed by `JSONFileStore<[String: String]>("site_profiles.json")`.
  - `WordPressClient.fetchSiteName() async throws -> String?`: `GET <siteURL>/wp-json/?_fields=name`, decoding `name`. Empty means nil, and HTML entities are decoded (`decodingHTMLEntities()`, as `SiteDiscovery` does).
  - `AppState.siteName: String?` (`@Published`). `AppState.refreshSiteName(store:fetch:) async`: it sets `siteName` from the store first, then fetches, saves and sets it, dropping the result if `credentials?.siteKey` changed while it ran. The default arguments are the real store and client.
  - `ContentView`: `.task(id: appState.credentials?.siteKey) { await appState.refreshSiteName() }`. This covers launch and sign-in, since signing in changes the key.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func storesNamesPerSiteKey()                // setName("Siolon", for: "a"); name(for: "a") == "Siolon"; name(for: "b") == nil
@Test func nilNameRemovesTheEntry()
@Test func fetchSiteNameDecodesEntities()         // stub {"name":"Tom &amp; Jerry"} → "Tom & Jerry"; request URL path "/wp-json/" with _fields=name
@Test func fetchSiteNameTreatsEmptyAsNil()
@Test func refreshShowsStoredNameThenFetched()    // store has "Old"; fetch returns "New" → siteName "New", store "New"
@Test func refreshDropsAResultForAnotherSite()    // credentials change during fetch → siteName unchanged
```

- [ ] **Step 2: Run** the filtered tests. Expected: FAIL.
- [ ] **Step 3: Implement** as specified.
- [ ] **Step 4: Run** `swift test`. Expected: PASS.
- [ ] **Step 5: Check in with Chris.**

---

### Task 3: Selection rules and copy

**Files:**
- Create: `Sources/QuillKit/App/Masthead.swift`, `Tests/QuillTests/MastheadTests.swift`

**Interfaces:**
- Consumes: `WPPost.modifiedGmt`, `WPPost.author`, `StashTime`, `AppState.currentUserID` (Task 1).
- Produces (`enum Masthead`, all `static`, no state):
  - `struct Lead: Equatable { let item: PostItem; let section: SidebarSection; let edited: Date; let meta: String }`. `section` is where the item lives: `.posts`, `.pages` or `.localDrafts`.
  - `lead(for section: SidebarSection, posts: [WPPost], pages: [WPPost], localDrafts: [LocalDraft], stashes: [StashTime], userID: Int?, now: Date) -> Lead?`. Candidates follow the spec's table. The timestamp is the latest of `modifiedGmt` (parsed with `PostSettings.parseWPDate`), the stash's `savedAt` and `updatedAt`. Drafts are `status == "draft"`, filtered by `author == userID` only when `userID != nil`. Any status qualifies when there's a stash. Ties go to remote first, then the lower ID. Stashes whose post isn't in the lists are ignored.
  - `Lead.meta` is built inside `lead(…)` from the exact copy in Global Constraints. The status word for a stashed remote post comes from `PostListRow.statusLabel(_:)`. `editedPhrase(_ date: Date, now: Date) -> String` gives `RelativeDateTimeFormatter` with `.named` up to 7 days ("2 hours ago", "yesterday"), then `date.formatted(.dateTime.day().month(.abbreviated))`.
  - `struct ScheduledRow: Equatable { let post: WPPost; let date: Date; let missed: Bool }`.
  - `scheduled(for section: SidebarSection, posts: [WPPost], pages: [WPPost], confirmedMissed: Set<MissedKey>, now: Date) -> [ScheduledRow]`. For `.posts`/`.pages`: `status == "future"`, upcoming when `now <= date <= now + 14 days`, missed when `date < now - 5 min` and `MissedKey(id:, dateGmt:)` for its current date is in `confirmedMissed`. Missed come first, then the earliest, at most 3. For `.localDrafts` it's `[]`.
  - `public struct MissedKey: Hashable, Sendable { public let id: Int; public let dateGmt: String }`: one passed schedule. A rescheduled post gets a new key, so it is checked again and an old confirmation doesn't carry over.
  - `missedCandidates(posts: [WPPost], now: Date) -> [MissedKey]`: the keys of `future` posts more than 5 minutes past their date, to confirm in Task 4.
  - `emptyLine(for section: SidebarSection) -> String`.
  - `displayName(siteName: String?, siteURL: URL) -> String`: the name, else `siteURL.host()`, else the absolute string.

- [ ] **Step 1: Write the failing tests** (fixed `now`, `en_GB` locale for copy)

```swift
@Test func postsLeadPrefersANewerLocalDraft()
@Test func postsLeadPrefersANewerWordPressDraft()
@Test func aStashedPublishedPostLeadsWithItsMetaLine()   // meta == "Published · unsaved changes on this Mac"
@Test func anotherAuthorsDraftIsSkippedOnceTheUserIsKnown()
@Test func anotherAuthorsDraftCountsBeforeTheUserIsKnown()
@Test func pendingPostsNeverLead()
@Test func pagesLeadIgnoresLocalDraftsAndPosts()
@Test func draftsLeadIgnoresRemotePosts()
@Test func untitledLocalDraftShowsUntitled()             // lead.item.title == "Untitled"
@Test func tiesResolveRemoteFirstThenLowerID()
@Test func editedPhraseIsRelativeForAWeekThenADate()     // 2h → "2 hours ago"; 1d → "yesterday"; 8d → "23 Oct"
@Test func localDraftMetaNamesItsType()                  // "Page draft · on this Mac · edited yesterday"
@Test func scheduledKeepsTheNextTwoWeeksCappedAtThree()
@Test func missedComeFirstOnlyWhenConfirmed()
@Test func missedWaitsOutTheFiveMinuteGrace()
@Test func draftsSectionHasNoScheduled()
@Test func displayNameFallsBackToHost()
```

- [ ] **Step 2: Run** `swift test --filter MastheadTests`. Expected: FAIL, `Masthead` isn't defined.
- [ ] **Step 3: Implement** as specified.
- [ ] **Step 4: Run** `swift test --filter MastheadTests`. Expected: PASS.
- [ ] **Step 5: Check in with Chris.**

---

### Task 4: Confirming missed schedules

**Files:**
- Modify: `Sources/QuillKit/App/AppState.swift`
- Test: `Tests/QuillTests/AppStateTests.swift`

**Interfaces:**
- Consumes: `Masthead.missedCandidates`, `MissedKey` (Task 3).
- Produces:
  - `AppState.confirmedMissed: Set<MissedKey>` (`@Published`) and a private `checkedMissed: Set<MissedKey>` holding the schedules already fetched. Both reset in `connect(_:)` on a site change.
  - `AppState.confirmMissedSchedules(now: Date = .now, fetch: (WPPost) async throws -> WPPost = <client fetchPost/fetchPage by type>) async`. For each candidate key not in `checkedMissed`, it adds the key to `checkedMissed` and fetches the post. If the result is still `future` with the same `date_gmt`, it inserts the key into `confirmedMissed`. Otherwise it replaces the post in `posts` or `pages`. A thrown fetch leaves it unconfirmed. Results are dropped if `credentials?.siteKey` changed during the fetch.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func aStillFutureFetchConfirmsTheMiss()
@Test func aPublishedFetchUpdatesTheListAndDoesNotConfirm()   // posts[i].status == "publish" afterwards
@Test func aFailedFetchConfirmsNothing()
@Test func eachPostIsFetchedOnce()                             // call twice; fetch closure counts 1
@Test func aRescheduledPostIsCheckedAgain()                   // confirm at date A; change dateGmt to B (also passed); call again → fetched again; key A's confirmation doesn't mark it
@Test func aPostCrossingTheGraceIsPickedUpOnALaterCall()      // call with now inside the grace → no fetch; call with now 6 min later, lists unchanged → fetched
@Test func aResultAfterASiteSwitchIsDropped()
```

- [ ] **Step 2: Run** `swift test --filter AppStateTests`. Expected: FAIL.
- [ ] **Step 3: Implement** as specified.
- [ ] **Step 4: Run** `swift test`. Expected: PASS.
- [ ] **Step 5: Check in with Chris.**

---

### Task 5: The view

**Files:**
- Create: `Sources/QuillKit/Views/MastheadView.swift`
- Modify: `Sources/QuillKit/Views/ContentView.swift`, `Sources/QuillKit/App/AppState.swift`
- Test: `Tests/QuillTests/AppStateTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `AppState.openFromMasthead(_ item: PostItem, in section: SidebarSection)`: calls `switchSection(to: section)`, and in `then` clears `searchText`, sets `statusFilter = .all` if the current filter wouldn't match the item, then sets `selectedItem`.
  - `MastheadView(section: SidebarSection)`. It reads `AppState` and `AppServices` (`@EnvironmentObject`), loads `stashTimes(site:)` on appear and whenever the lists change, and wraps its body in `TimelineView(.everyMinute)` so the date, the relative times and the windows follow the clock. Its `.task(id: credentials?.siteKey)` calls `loadUnfilteredHTMLCapability()`. Inside the `TimelineView`, a `.task(id:)` keyed on `Masthead.missedCandidates(posts: posts + pages, now: context.date)` calls `confirmMissedSchedules(now: context.date)`. A redraw alone never fetches, so this task is what picks up a post that passes its grace period while the page is open, with no list change (Codex review, 2026-10-31). Layout and copy come from Global Constraints. Each item is a `Button` with `.buttonStyle(.plain)` and an accent title on hover. It gets `.accessibilityElement(children: .combine)` with a label like "Continue writing, <title>, <meta>".
  - `ContentView`: the `EmptyEditorPlaceholder` branch shows `EmptyEditorPlaceholder` only when `loadFailed`, otherwise `MastheadView(section:)`. `EmptyEditorPlaceholder` keeps its feather and loses the strings it no longer shows ("Select a …", "No …s yet").

- [ ] **Step 1: Write the failing tests**

```swift
@Test func openingALocalDraftFromPostsSwitchesToDrafts()
@Test func openingAStashedPageFromPostsSwitchesToPages()
@Test func openingClearsAFilterThatWouldHideTheItem()    // statusFilter .published, open a draft → .all
@Test func openingKeepsAFilterThatShowsTheItem()
```

- [ ] **Step 2: Run** `swift test --filter AppStateTests`. Expected: FAIL.
- [ ] **Step 3: Implement** `openFromMasthead`, `MastheadView` and the `ContentView` change.
- [ ] **Step 4: Run** `swift test`, then the build command. Expected: PASS, and Quill opens on the masthead.
- [ ] **Step 5: Check the small caps.** Zoom into "continue writing" in the running app. If the letters are scaled capitals with thin strokes, not true small caps, switch the labels to regular `.secondary` text at 12pt, as the spec says, and tell Chris.
- [ ] **Step 6: Check in with Chris** with a screenshot in light and dark.

---

### Task 6: Manual pass and docs

**Files:**
- Modify: `docs/testing-plan.md`, `site/docs.html`, `Sources/QuillKit/Views/CLAUDE.md`

- [ ] **Step 1: Run the spec's manual steps** against the local Studio site:
  - At launch, Posts shows the post you last wrote, and clicking it opens it.
  - A new local draft that's newer than every WordPress draft leads on Posts and opens in Drafts.
  - Set a WordPress draft's schedule 3 minutes ahead with WP-Cron disabled (`define('DISABLE_WP_CRON', true)` in the Studio site's `wp-config.php`, restored afterwards). With the masthead left open, and without pressing ⌘R or switching sections, it shows as Scheduled, then as Missed schedule once 5 minutes have passed.
  - A long site name at the narrowest window fits in two lines.
  - Check light and dark, Full Keyboard Access and VoiceOver.
  - Media is unchanged, and "Couldn't load posts" still shows when offline.
- [ ] **Step 2: Update docs.**
  - `docs/testing-plan.md`: the new tests, the counts and the manual steps.
  - `site/docs.html`: replace "When Nothing Is Open".
  - `Sources/QuillKit/Views/CLAUDE.md`: a gotcha entry, "the site name lives in `SiteProfileStore`, not `Credentials`, because credential equality triggers a reload".
- [ ] **Step 3: Run** `./test.sh`. Expected: all suites pass.
- [ ] **Step 4: Check in with Chris** with a summary, and ask whether to commit.
