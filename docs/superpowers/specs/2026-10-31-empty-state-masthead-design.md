# Empty state: continue writing

Mockup: `2026-11-01-empty-state-native-mockups.html` next to this spec, direction C (Grouped list) with the site icon. *(Chris's call, 2026-11-01: the first build used the newspaper masthead from `2026-10-31-empty-state-masthead-mockups.html`, and in the app its size, print styling and small-caps labels felt foreign to Quill. Direction C replaces it.)* Where a mockup and this spec differ, the spec wins.

## Why

Quill does not restore the open post at launch, and switching sidebar sections clears the selection, so the empty state is the first thing the author sees every time they open the app, and again on every section switch. Today it says "Select a post to edit" beside a large feather. It could instead take them straight back to what they were writing.

The page is built from native Mac parts: a header with the site's icon and name, and inset grouped rows like System Settings.

## Goals

- A header with the site's name and address, and its WordPress Site Icon when it has one.
- **Continue writing:** up to three items, the things the author was most recently writing, newest first. One click opens one. *(Chris's call, 2026-11-01: the grouped list has room for more than one. On Drafts the three repeat the top of the sidebar, which is sorted the same way; he chose the same count in every section over avoiding that.)*
- **Scheduled:** up to three posts due in the next two weeks, with their dates.
- Posts, Pages and Drafts each get a version of the page. Media is unchanged.

## Non-goals

- A list of every draft. The sidebar already lists them with their status.
- Word counts, streaks, stats or anything else that needs post content. The post list request leaves content out, and fetching it for this page is not worth the cost.
- The theme's Site Logo. The REST index gives only its media ID, and it is often a wordmark that repeats the site's name.
- Restoring the last open post at launch. That would mean the page is seen less, not that it is needed less, and it is a separate decision.

## Anti-goals

- Repeating the sidebar. Every item on the page must be something the sidebar does not already put in front of the author.
- Delaying the editor. The page must never block or slow opening a post.
- A visual language Quill does not already use: display-size type, heavy rules, small caps, dotted leaders, or a second typeface.
- The Quill feather beside the site's name, where it could read as the site's own logo. *(Chris's call, 2026-11-01.)*

## Decisions

### When it shows

- In Posts, Pages and Drafts whenever nothing is selected and the list has loaded. An empty section still shows the page, since a brand-new site with a local draft in progress is exactly when Continue writing helps. *(Chris's call, 2026-10-31.)*
- Unchanged: the loading spinner, and "Couldn't load posts" (and its Pages, Drafts and Media versions) when the list fails to load.
- Media keeps its grid. Its empty state never appears.

### Layout

One column, at most 480pt wide, starting about 72pt from the top. Every colour is a system semantic colour or one of Quill's status colours, so light and dark need no special cases.

- **Header:** the site's name in `.title` bold, with its host beneath in `.secondary`. When the site has a Site Icon, it sits to the left at 40pt with 9pt corners and a hairline `.separator` border, like the site tile on the onboarding waiting panel. With no icon, the header is text only. A long name truncates on one line.
- **Section labels:** "Continue Writing" and "Scheduled", each a `SectionLabel`.
- **Rows:** inset grouped rows in a box filled with `.fill.quaternary` at a 10pt radius, divided by separators. Each row is the status symbol (`statusSymbol(_:)`, palette white on `Color.statusColor(_:)`) at about 20pt, the title in `.body` medium on one line, a `.subheadline` `.secondary` line beneath, and a `.tertiary` chevron. On hover the row takes a light `.fill` highlight; the title keeps its colour.
- **Continue writing:** up to three rows. Each row's second line is its meta line (see below).
- **Scheduled:** one row per post. The second line is the date and time ("Tue, Nov 3 at 9:00 AM" in the user's locale), or "Missed schedule". A missed row uses the Pending colour with `exclamationmark.circle.fill`, so it stands apart from the blue scheduled rows.
- **Nothing to show:** if there is no Continue writing item and nothing scheduled, the page is a `ContentUnavailableView` like "Couldn't load posts": the feather (`QuillMark.emptyStateIcon`), the site's name, and one line: "Select a post to edit" (page, draft) when the section has items, "No posts yet" (pages, drafts) when it has none. *(Chris's call, 2026-11-01: the page should not assume the author wants to start something new.)*

### Interaction

- Each row is a plain button with the row's hover highlight. With Full Keyboard Access each item is focusable, and Return or Space opens it.
- Opening an item selects it in its own section. An item from another section switches the sidebar first, the way `AppState.createNewDraft` does with `switchSection(to:then:)`: a local draft opened from the Posts page goes to Drafts, and a remote page with an autosave stash goes to Pages. If the search text or status filter would hide the item in the sidebar, clear them, as `createNewDraft` clears the search.
- VoiceOver reads each item as one element: the section label, the title, and the meta line, for example "Continue writing, Packing for the coast, draft, edited 2 hours ago".

### Which items are Continue writing

**Candidates:**

| Page | Candidates |
|---|---|
| Posts | The author's post drafts on WordPress; any remote post or page with unsaved changes in Quill (an autosave stash), whatever its status; every local draft, post or page |
| Pages | The author's page drafts on WordPress; any remote page with an autosave stash |
| Drafts | Every local draft |

The Posts page reaches across sections because it is the page seen at launch, and the author most likely wants whatever they were last writing, wherever it lives. *(Chris's call, 2026-10-31.)* Pages and Drafts stay inside their own section, because the author got there by clicking that section.

**Timestamp:** for each candidate, the latest of:

- WordPress's `modified_gmt`, for a remote post;
- the stash's `savedAt`, when a remote post has one;
- `updatedAt`, for a local draft.

The three newest candidates are shown, newest first. These are all absolute times, so comparing them across sources is sound.

**What counts as a draft:** status `draft` only. A pending post is waiting for an editor, not being written. A published, private or scheduled post qualifies only through an autosave stash.

**The author's drafts:** on a site with several authors, another author's draft must not lead. Filter remote drafts by `author` against the signed-in user's ID. `WordPressClient.canPostUnfilteredHTML()` already fetches `users/me`; decode `id` from that response, not from a new request. Today `AppState.loadUnfilteredHTMLCapability()` runs only once the editor is ready, so the page must also start it when it appears (it is guarded to run once per site). Until the ID arrives, don't filter. Stashes and local drafts are this Mac's by definition and are not filtered.

**Meta line:**

| Candidate | Meta line |
|---|---|
| WordPress draft | Draft · edited 2 hours ago |
| Remote post with a stash | Draft · unsaved changes on this Mac, or Published (or Scheduled, Private) · unsaved changes on this Mac |
| Local draft | Post draft · on this Mac · edited yesterday, or Page draft · … |

"Edited …" uses a named relative time ("2 hours ago", "yesterday") up to a week old, and the date after that ("12 Oct").

### Scheduled

- Status `future`, with `date_gmt` from now to 14 days ahead, earliest first, at most three.
- **Missed schedules** come first, inside the same limit of three: a post still `future` whose `date_gmt` passed more than 5 minutes ago, with "Missed schedule" in place of the date. The grace period covers WP-Cron publishing a little late. *(Chris's call, 2026-10-31: include it if it is cheap.)*
- The list is not refreshed on a timer, so a post that published on time still reads `future` in a list loaded earlier. Before flagging a post as missed, fetch it once (`fetchPost` / `fetchPage`) and flag it only if it is still `future`. If it has published, replace it in `appState.posts` or `appState.pages`, so the sidebar row updates too. Fetch each post at most once per passed schedule, not on every redraw. If the fetch fails, show nothing for that post.
- Posts page: scheduled posts. Pages page: scheduled pages. Drafts page: none, since a local draft cannot be scheduled until it is on WordPress.
- Recomputed whenever the list changes (⌘R, a save, a publish), since everything on the page is derived from `AppState` lists.
- The date, the relative times and the 14-day window also depend on the clock. A window left open overnight must not show yesterday's date, so the page also redraws at least once a minute (a `TimelineView` with a minute schedule, or similar).

### Data the app does not have yet

- **The site's name and icon.** `SiteDiscovery.discover` decodes `name` and `site_icon_url` at sign-in, but nothing stores them. Store both per site (keyed by `siteKey`), and refresh them in the background at launch from the REST index with `_fields=name,site_icon_url`, since the full index lists every route. Keep the icon's bytes too, so the header does not flash empty at launch or go blank offline, and download it again only when its URL changes. The download goes through `SiteDiscovery`'s unauthenticated session: the icon may live on a CDN, and the site's credentials must not go with it. Do not add any of this to `Credentials`: `SidebarView` compares `credentials` against `lastLoadedCredentials` to decide when to reload, so a renamed site would trigger a full reload. Until a name is known, or if the site has none, the header shows the site's host.
- **The signed-in user's ID**, from the existing `users/me` request (above). It does not need storing.
- **`modified_gmt` and `author`** on each post: add both to the list request's `_fields` and to `WPPost`. Decode both as optional, so a cached or older response without them still decodes.
- **Every stash's post ID and `savedAt` for a site:** a new `AutosaveStore` query. A stash for a post that is no longer in the list is ignored.

## Testing

### Swift

The candidate and scheduled rules should be static functions that take the lists, the stashes, the user's ID and the current date, so they can be tested without a view.

- Posts page: a local draft edited after the newest WordPress draft wins, and vice versa.
- A published post with a stash newer than every draft wins, with the "Published · unsaved changes on this Mac" line.
- Another author's newer draft is skipped. A pending post is skipped.
- Pages page ignores local drafts and post drafts. Drafts page ignores remote posts.
- Scheduled: excludes posts more than 14 days out; caps at three, missed ones included; sorts missed first, then earliest first.
- Missed schedule: not flagged inside the 5-minute grace period; not flagged until the confirming fetch says `future`; a confirming fetch that returns `publish` updates the list and drops the item; a failed fetch shows nothing; a post is fetched only once.
- Meta lines and relative times, including the switch to a date after a week.
- Name fallback: no stored name shows the host.
- The site icon is downloaded when its URL is new, not again while it is unchanged, cleared when the site drops it, and kept when a download fails.
- The empty line: "Select a … to edit" with items, "No …s yet" without.
- `WPPost` decodes with and without `modified_gmt` and `author`.
- The site name store round-trips and is keyed per site.
- Another author's draft is not filtered out before the user ID arrives, and is filtered out after.
- Opening a local draft from the Posts page switches to Drafts, and a stashed remote page switches to Pages; both clear a filter that would hide the item.

Update the counts in `docs/testing-plan.md`.

### Manual (`docs/testing-plan.md` §7)

- Launch: the Posts page shows the post last written; clicking it opens it.
- A local draft newer than every WordPress draft leads on the Posts page and opens in Drafts.
- Long site name at the narrowest window with the sidebar open: one line, truncated, nothing clipped. A site with a Site Icon shows it; one without shows text only.
- Light and dark; Full Keyboard Access; VoiceOver reads each item as one element.
- No page in Media; "Couldn't load posts" unchanged when offline.

## Docs to update

- `site/docs.html`: replace "When Nothing Is Open".
- `docs/testing-plan.md`: new tests and counts, the §7 steps.
- `Sources/QuillKit/Views/CLAUDE.md`: a gotcha entry for keeping the site name out of `Credentials`.

## Left to the builder

- Where the site name is stored (a small JSON file beside `credentials.json`, or a table in the existing database).
- How the dotted leader is drawn.
- Names and placement of the new view and the selection functions.
