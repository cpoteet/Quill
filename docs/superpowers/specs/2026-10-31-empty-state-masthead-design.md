# Masthead empty state

Mockup: `2026-10-31-empty-state-masthead-mockups.html` next to this spec. Chris chose the Front page layout in SF Pro with no feather. The mockup still has the "Other drafts" list and the feather options; where the mockup and this spec differ, the spec wins.

## Why

Quill does not restore the open post at launch, and switching sidebar sections clears the selection, so the empty state is the first thing the author sees every time they open the app, and again on every section switch. Today it says "Select a post to edit" beside a large feather. It could instead take them straight back to what they were writing.

The page borrows the layout of a newspaper masthead: the site's name over a double rule, with the date and the address in the rule.

## Goals

- The site's name as a masthead, with today's date and the site's address in the rule beneath it.
- **Continue writing:** one item, the thing the author was most recently writing. One click opens it.
- **Scheduled:** up to three posts due in the next two weeks, with their dates.
- Posts, Pages and Drafts each get a version of the page. Media is unchanged.

## Non-goals

- A list of every draft. The sidebar already lists them with their status.
- Word counts, streaks, stats or anything else that needs post content. The post list request leaves content out, and fetching it for this page is not worth the cost.
- The site icon. Mastheads are type only, and site icons are often small raster logos that would sit badly at this size.
- Restoring the last open post at launch. That would mean the page is seen less, not that it is needed less, and it is a separate decision.

## Anti-goals

- Repeating the sidebar. Every item on the page must be something the sidebar does not already put in front of the author.
- Delaying the editor. The page must never block or slow opening a post.
- A serif, or any typeface Quill does not already use. *(Chris's call, 2026-10-31: he was unsure about bringing a serif into the app and about losing the Quill mark. He then tried the feather in the mockup and dropped it, because it was too faint at masthead sizes. My reasoning for SF: the grip gets its character from print conventions set in the editor's own sans, not from a second typeface.)*

## Decisions

### When it shows

- In Posts, Pages and Drafts whenever nothing is selected and the list has loaded. It replaces both "Select a … to edit" and "No …s yet". In a section with no items, the page's empty line ("Start a post with ⌘N") says the same thing as "No posts yet" and still shows the masthead and any local draft. *(Chris's call, 2026-10-31, on my suggestion: a brand-new site with a local draft in progress is exactly when Continue writing helps.)*
- Unchanged: the loading spinner, and "Couldn't load posts" (and its Pages, Drafts and Media versions) when the list fails to load.
- Media keeps its grid. Its empty state never appears.

### Layout

One centred column, at most 520pt wide, starting about 72pt from the top. Every colour is a system semantic colour (`.primary`, `.secondary`, `.tertiary`, the accent), so light and dark need no special cases.

- **Name:** SF Pro, bold, about 46pt, tracking tightened to about -2.5%, centred. A long name wraps to at most two lines and scales down to fit them (to about 32pt) before it truncates.
- **Rule:** a 2pt rule in `.primary` above, a hairline in the separator colour below, 7pt of padding between them. Inside: the date on the left (`Date.formatted(date: .complete, time: .omitted)`, in the user's locale) and the site's host on the right, both in `.secondary` at about 12pt.
- **Section labels:** "continue writing" and "scheduled" in lowercase small caps (`.lowercaseSmallCaps()`), `.secondary`, about 15pt. These echo the grip's small-caps heading markers. Check in the built app that SF draws true small caps here; if SwiftUI synthesises them by scaling capitals, use regular `.secondary` text at 12pt instead and tell Chris.
- **Continue writing:** the title at about 23pt semibold, then a `.secondary` line saying what it is and when it was last edited (see below).
- **Scheduled:** one row per post: the title at about 16pt on the left, a dotted leader in `.tertiary` filling the space, and the date on the right ("Tue 3 Nov", tabular figures). A long title truncates before the leader shrinks below about 16pt.
- **Nothing to show:** if there is no Continue writing item and nothing scheduled, a single `.secondary` line under the rule: "Start a post with ⌘N" in Posts and Drafts, "Start a page with ⇧⌘N" in Pages.
- No feather. `QuillMark.emptyStateIcon` stays for "Couldn't load".

### Interaction

- Each item is a plain button. On hover its title takes the accent colour. With Full Keyboard Access each item is focusable, and Return or Space opens it.
- Opening an item selects it in its own section. An item from another section switches the sidebar first, the way `AppState.createNewDraft` does with `switchSection(to:then:)`: a local draft opened from the Posts page goes to Drafts, and a remote page with an autosave stash goes to Pages. If the search text or status filter would hide the item in the sidebar, clear them, as `createNewDraft` clears the search.
- VoiceOver reads each item as one element: the section label, the title, and the meta line, for example "Continue writing, Packing for the coast, draft, edited 2 hours ago".

### Which item is Continue writing

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

The newest candidate wins. These are all absolute times, so comparing them across sources is sound.

**What counts as a draft:** status `draft` only. A pending post is waiting for an editor, not being written. A published, private or scheduled post qualifies only through an autosave stash.

**The author's drafts:** on a site with several authors, another author's draft must not lead. Filter remote drafts by `author` against the signed-in user's ID. `WordPressClient.canPostUnfilteredHTML()` already fetches `users/me`; decode `id` from that response, not from a new request. Today `AppState.loadUnfilteredHTMLCapability()` runs only once the editor is ready, so the masthead must also start it when it appears (it is guarded to run once per site). Until the ID arrives, don't filter. Stashes and local drafts are this Mac's by definition and are not filtered.

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

- **The site's name.** `SiteDiscovery.discover` decodes `name` at sign-in, but nothing stores it. Store it per site (keyed by `siteKey`), and refresh it in the background at launch from the REST index; try `_fields=name` on that request, since the full index lists every route. Do not add it to `Credentials`: `SidebarView` compares `credentials` against `lastLoadedCredentials` to decide when to reload, so a renamed site would trigger a full reload. Until a name is known, or if the site has none, the masthead shows the site's host.
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
- `WPPost` decodes with and without `modified_gmt` and `author`.
- The site name store round-trips and is keyed per site.
- Another author's draft is not filtered out before the user ID arrives, and is filtered out after.
- Opening a local draft from the Posts page switches to Drafts, and a stashed remote page switches to Pages; both clear a filter that would hide the item.

Update the counts in `docs/testing-plan.md`.

### Manual (`docs/testing-plan.md` §7)

- Launch: the Posts page shows the post last written; clicking it opens it.
- A local draft newer than every WordPress draft leads on the Posts page and opens in Drafts.
- Long site name at the narrowest window with the sidebar open: two lines at most, nothing clipped.
- Light and dark; Full Keyboard Access; VoiceOver reads each item as one element.
- No masthead in Media; "Couldn't load posts" unchanged when offline.

## Docs to update

- `site/docs.html`: replace "When Nothing Is Open".
- `docs/testing-plan.md`: new tests and counts, the §7 steps.
- `Sources/QuillKit/Views/CLAUDE.md`: a gotcha entry for keeping the site name out of `Credentials`.

## Left to the builder

- Where the site name is stored (a small JSON file beside `credentials.json`, or a table in the existing database).
- How the dotted leader is drawn.
- Names and placement of the new view and the selection functions.
