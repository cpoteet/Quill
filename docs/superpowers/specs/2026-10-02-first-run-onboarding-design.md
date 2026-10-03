# First-run onboarding

_Design, 2026-10-02._

Mockups of all four states: [`2026-10-02-first-run-onboarding-mockups.html`](2026-10-02-first-run-onboarding-mockups.html). They set layout, hierarchy and copy; SwiftUI's native controls set the exact sizes.

## Problem

When Quill launches with no saved credentials, `ContentView.loadCredentialsAtLaunch` leaves an empty main window and opens the Settings window on top of it. Settings shows three bare fields (Site URL, Username, Application Password) above the AI Writing section, with one line of help. Nothing says what Quill is or why Settings opened, and the user has to leave Quill, find the Application Passwords section of their WordPress profile, create a password and paste it back.

WordPress has had a browser approval flow for application passwords since 5.6: an app sends the user to `wp-admin/authorize-application.php`, the user clicks approve, and WordPress redirects to the app's URL with a newly created password. Quill has never used it.

## Goals

1. A first-time user goes from launch to seeing their own posts without guessing what to do next.
2. The usual path asks for one thing, the site address. The username and password come back from WordPress.
3. Onboarding is one panel in the main window, not a tour. It appears only while no credentials are saved.
4. Sites that turn browser approval off can still connect, through manual entry in the same panel.
5. Right after connecting, a user without an Anthropic key is offered AI setup once, as a step they can skip.

Non-goals: picking writing-style sample posts during onboarding (it stays in Settings), a feature tour, and browser approval in Settings (see Out of scope).

## Where it appears

`ContentView` shows `OnboardingView` in place of the `NavigationSplitView` while `appState.credentials` is nil, and also while the onboarding model is in the AI writing state. Credentials are saved and `appState.connect` runs as soon as the site is verified. Posts start loading when the app appears after the AI step, because `SidebarView` owns the initial load and is not mounted while the panel shows. Once the AI step is finished, or skipped because a key is already saved, the normal app replaces the panel. The automatic `openSettings()` call at launch is removed. The sidebar's "Open Blog Settings…" error row stays for failures after onboarding.

Typography is San Francisco throughout, matching the rest of the app. The Quill mark is drawn in the accent colour.

## States

### Welcome

```
            [Quill mark]
          Welcome to Quill
  Write and edit your WordPress posts and
  pages on your Mac. Connect your site to
  get started.

  Site address
  [ example.com                        ]

  Use an application password instead     [ Continue ]
```

- The field accepts a bare address (`lanternandink.com`). Quill adds `https://`.
- Continue is the default button and is disabled while the field is empty. While discovery runs it shows a small spinner and is disabled.
- "Use an application password instead" is an accent-coloured link that switches to the manual state, carrying over the address.
- Errors appear as one line of secondary text under the field.

### Waiting for approval

```
     [Quill tile] · · · [site icon tile]
    Approve Quill in your browser
  Log in to Lantern & Ink if asked, then
  approve the connection. Quill continues
  on its own.

              [ Cancel ]

  Browser didn't open? Open it again
```

- Quill opens the approval URL in the default browser as it enters this state.
- The left tile is the Quill mark, the right tile the site's icon. The middle dot pulses while waiting. With no icon, or if the icon fails to load, the right tile shows the first letter of the site name on the accent colour.
- The site name in the sentence is bold. With no name, it reads "your site".
- "Open it again" reopens the same approval URL. Cancel returns to Welcome and drops the pending nonce.
- There is no timeout.

### Manual

```
  Connect with an application password
  Create one in WordPress, then paste it here.

  [ amber note, only when reached automatically ]

  Site address
  [ lanternandink.com                  ]
  Username
  [ Your WordPress username            ]
  Application password
  [ xxxx xxxx xxxx xxxx xxxx xxxx      ]
  Open Profile Page to create one under Application Passwords.

  Back                                     [ Connect ]
```

- Reached from the Welcome link, or automatically when discovery finds no approval URL. In the automatic case the note reads: "This site doesn't allow approving apps from the browser, so Quill needs a password you create yourself."
- "Open Profile Page" is enabled once the address is filled in. When discovery found an approval URL, the profile URL is built from the same admin path (so a WordPress install in a subdirectory works). Otherwise it is `{site}/wp-admin/profile.php`. Either way it ends in `#application-passwords-section`.
- Back returns to Welcome, keeping the address.
- Validation matches Settings today (https, or http for localhost only). Errors appear above Connect.

### AI writing (optional)

```
     (✓) Connected to Lantern & Ink
        Add AI writing help
  Quill can draft posts, review your writing
  and rewrite selections with Claude. It uses
  your own Anthropic API key, and Anthropic
  bills you for what you use.

  Anthropic API key
  [ sk-ant-…                           ]
  Get a key from the Anthropic Console. You
  can change it later in Settings.

                   [ Skip for Now ] [ Save ]
```

- Shown once, right after the site connects, and only when `AISettingsStore.load()` returns nothing or an empty `apiKey`. A reinstall with a key still on disk goes straight to the app.
- The confirmation line uses a green checkmark; the site name is bold, or reads "your site" with no name.
- "Anthropic Console" opens `https://console.anthropic.com/settings/keys` in the default browser.
- Save is the default button and is disabled while the field is empty. Saving first checks the key with `GET /v1/models` (free, no tokens), then saves `AISettings` with only `apiKey` set and every other field at its default, and updates `appState.aiSettings`. A rejected key shows "Anthropic didn't accept this key." under the field. A network failure shows "Couldn't reach Anthropic. Check your connection, or skip and add the key later in Settings."
- Skip for Now saves nothing. Both buttons are full buttons, not links, so skipping is as visible as saving.
- Writing-style samples, the model and reasoning level stay in Settings.

## Components

### `SiteDiscovery` (`API/`)

- `normalize(_ input: String) throws -> URL`: trims whitespace, adds `https://` when there is no scheme, lowercases the host, drops a trailing slash, keeps a subdirectory path. Refuses `http` except for `localhost`, `127.0.0.1` and `::1`, and refuses input that isn't a host.
- `discover(_ site: URL) async throws -> DiscoveredSite`: one unauthenticated `GET {site}/wp-json/` on an ephemeral `URLSession`. If the request was redirected, the site URL is the final response URL with `/wp-json/` removed.
- `DiscoveredSite`: `siteURL`, `name: String?`, `iconURL: URL?` (from `site_icon_url`), `authorizationURL: URL?` (from `authentication["application-passwords"].endpoints.authorization`).
- Errors: `unreachable` (transport failure or timeout), `notWordPress` (non-JSON, 404, 401, 403, or JSON without a `namespaces` array).

Discovery uses `/wp-json/` because `WordPressClient` does. Sites that answer only at `?rest_route=` are unsupported here, as they are everywhere else in Quill.

### `AppAuthorization` (`Auth/`)

Pure functions, no networking or UI.

- `approvalURL(base: URL, nonce: String, deviceName: String) -> URL` adds:
  - `app_name` = "Quill on {deviceName}", where the caller passes `Host.current().localizedName`, so the user can tell their Macs apart on their WordPress profile.
  - `app_id` = one fixed Quill UUID, defined once as a constant.
  - `success_url` = `quill://authorize?nonce={nonce}`
  - `reject_url` = `quill://authorize?nonce={nonce}`
- `parseCallback(_ url: URL, expectedNonce: String) -> Result` where the result is `.approved(username:password:)`, `.rejected`, or `.ignored`. WordPress adds `user_login` and `password` on approval and `success=false` on rejection. Wrong scheme or host, a missing or mismatched nonce, or an approval missing either field all give `.ignored`.

The nonce is 32 random bytes, hex-encoded, made fresh each time Quill enters the waiting state.

### `ConnectSite` (shared)

`verifyAndSave(_ credentials: Credentials) async throws`: the step now inline in `PreferencesView.saveAll`. It makes one `fetchPosts(page: 1, perPage: 1)` call, then `CredentialsStore.save`. Nothing is saved if the call fails. Both `PreferencesView` and onboarding use it, and the caller then runs `appState.connect`.

### `OnboardingModel` and `OnboardingView` (`Views/Onboarding/`)

`OnboardingModel` is a `@MainActor` `ObservableObject` owned by `ContentView` as a `@StateObject`. It holds the state (`welcome`, `waiting(DiscoveredSite, nonce)`, `manual(reason)`, `aiSetup(siteName)`, `finished`), the field values, the busy flag and the current error message. It owns every transition, so they can be tested without the UI. `OnboardingView` switches on the state and renders one small view per state: `OnboardingWelcomeView`, `OnboardingWaitingView`, `OnboardingManualView`, `OnboardingAIView`.

The site icon loads through `SiteDiscovery`'s ephemeral session, not `AsyncImage`, which uses the shared session and so breaks the ephemeral-only rule in `CLAUDE.md`. A failed load shows the letter tile.

### `AnthropicClient.verifyKey`

`verifyKey(_ key: String) async throws`: one `GET https://api.anthropic.com/v1/models?limit=1` with the `x-api-key` and `anthropic-version` headers. A 401 throws `invalidKey`; a transport failure throws the existing network error. If the model-selection feature (`2026-10-02-ai-model-selection-design.md`) lands first, this reuses its Models API request instead of adding a second one.

### Wiring

- `build.sh` adds `CFBundleURLTypes` with the `quill` scheme to the generated `Info.plist`.
- `QuillApp` delivers incoming URLs to the existing window: `.handlesExternalEvents(matching:)` on the `WindowGroup`, and `.onOpenURL` on `ContentView` passing the URL to the onboarding model. A `WindowGroup` opens a new window for an external URL by default, so this needs a manual check.
- A callback that arrives when no onboarding is in progress is ignored.

## Error handling

| Where | Situation | What the user sees |
|---|---|---|
| Welcome | `http://` on a non-local host | "Quill needs an https:// address." |
| Welcome | Unreachable | "Couldn't reach {host}. Check the address and your connection." |
| Welcome | Not WordPress, or REST API blocked | "This doesn't look like a WordPress site, or its REST API is turned off." |
| Welcome | WordPress, no approval URL | Manual state with the amber note |
| Waiting | User declines | Welcome, with "Quill wasn't approved. Try again, or use an application password." |
| Waiting | Approved, but the check call fails | Welcome, with the server's error message. Nothing is saved. Usually the host strips the `Authorization` header, which manual entry would hit too. |
| Waiting | Late or stale callback (after Cancel or relaunch, or wrong nonce) | Nothing. WordPress has already created that password, and the user can revoke it on their profile. |
| Manual | Validation or check failure | The same messages as Settings today, above Connect |
| AI writing | Key rejected (401) | "Anthropic didn't accept this key." under the field |
| AI writing | Anthropic unreachable | "Couldn't reach Anthropic. Check your connection, or skip and add the key later in Settings." |

## Testing

Unit tests (Swift Testing). Each network suite gets its own `URLProtocol` subclass (the `AGENTS.md` rule), and no new suite sets `AppSupportDirectory.override`; storage is injected instead.

- **`AppAuthorizationTests`**: every query parameter is present and encoded, including spaces in the device name; the nonce appears in both URLs; callbacks for approved, rejected, wrong nonce, missing nonce, missing `user_login` or `password`, wrong scheme, and wrong host.
- **`SiteDiscoveryTests`**: normalization (bare host, trailing slash, capitalised host, subdirectory, http on localhost, http elsewhere, empty and garbage input); discovery (approval URL present, approval URL missing, no icon, no name, non-JSON, 401, 403, 404, transport failure, a redirect keeping the final address).
- **`ConnectSiteTests`**: saves on success and saves nothing on failure, through an injected save function so the suite never touches `AppSupportDirectory.override`.
- **`OnboardingModelTests`**: welcome → waiting; discovery with no approval URL → manual with the reason; decline → welcome with the message; Cancel, then a callback with the old nonce → no change; approved callback whose check fails → welcome with the error and no saved credentials; verified site with no saved Anthropic key → AI writing; verified site with a saved key → finished; Skip → finished with nothing saved; Save with a rejected key → stays on AI writing with the message.
- **`AnthropicClientTests`**: `verifyKey` sends the key and version headers to `/v1/models`, succeeds on 200, and throws `invalidKey` on 401.

Manual checks, added to the release checklists in `docs/testing-plan.md`:

1. Fresh install: move `credentials.json` aside (never delete it), launch, and connect a real site through browser approval. Revoke the "Quill on {Mac}" password on that site afterwards.
2. The callback reaches the existing window, and no second window opens.
3. Decline in WordPress; manual entry from the link; the automatic manual state on a site with application passwords turned off; dark mode.
4. AI writing: Skip, then confirm Settings shows no key; Save a real key, then confirm an AI feature works; a reinstall with `ai_settings.json` present skips the step.

**Risk to settle first:** the dev build and the notarized copy in `/Applications` share the bundle ID `com.siolon.quill`, so both register `quill://`, and macOS may route the callback to the `/Applications` copy. Check this before building on it. If it is a problem, `build.sh` registers a dev-only scheme (`quill-dev`) for non-release builds and `AppAuthorization` takes the scheme as a parameter. Release builds are unchanged.

## Documentation

- `site/docs.html`, "Connecting to WordPress": lead with the browser approval flow, and keep the current three-step manual instructions as the fallback. The AI Writing section mentions that first-run setup offers the key.
- `README.md` line 5 still holds.
- Root `CLAUDE.md`: add `Views/Onboarding/` to the architecture tree and the `quill://` scheme to Key decisions.

## Out of scope

- Browser approval in Settings, for reconnecting or switching sites.
- Sites that answer only at `?rest_route=`.
- WordPress.com-hosted sites, which use a different login system.
- Revoking the application password from Quill.
