# First-Run Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the "empty window plus Settings" first launch with a one-panel onboarding that connects a WordPress site through browser approval, falls back to manual entry, and offers optional AI setup once.

**Architecture:** Pure logic first (`SiteDiscovery`, `AppAuthorization`, `ConnectSite`, `AnthropicClient.verifyKey`), then an `OnboardingModel` that owns every state transition behind injectable dependencies, then thin SwiftUI views and the `quill://` wiring. `ContentView` swaps the split view for `OnboardingView` while no credentials are saved or the AI step is showing.

**Tech Stack:** Swift 6.3.1, SwiftUI (macOS 27), URLSession (ephemeral), Swift Testing with per-suite `URLProtocol` stubs.

**Spec:** `docs/superpowers/specs/2026-10-02-first-run-onboarding-design.md`. Mockups: `docs/superpowers/specs/2026-10-02-first-run-onboarding-mockups.html`.

## Working in chunks

The plan is six chunks, each sized for one conversation. Start each conversation with: "Implement chunk N of `docs/superpowers/plans/2026-10-02-first-run-onboarding.md`." The implementer reads the spec, this header, and that chunk only. Tick the chunk's checkboxes in this file as steps finish, so the next conversation can see where things stand.

Every chunk ends the same way: run `./test.sh`, summarize what changed, and **stop without committing**. Commits happen only when Chris asks, after the Codex review described in `~/.claude/CLAUDE.md`.

| Chunk | Tasks | Needs |
|---|---|---|
| 1. URL scheme routing | 1 | — |
| 2. Site discovery and approval URLs | 2, 3 | 1 (scheme decision) |
| 3. Verify-and-save and key check | 4, 5 | — |
| 4. Onboarding model | 6 | 2, 3 |
| 5. Views and wiring | 7, 8 | 1–4 |
| 6. Docs and release checklist | 9 | 5 |

## Global Constraints

- macOS 27 only, no availability checks. Every `URLSession` is built from `URLSessionConfiguration.ephemeral`; no `AsyncImage`, no `URLSession.shared`.
- Typography is San Francisco only. Use system text styles: `.largeTitle` (Welcome title), `.title` (other titles), `.body` (intro text), `.callout` (labels, help, errors, links).
- Inputs are `.textFieldStyle(.roundedBorder)`. The primary button is `.borderedProminent` with `.keyboardShortcut(.defaultAction)`. Links are `Button` with `.buttonStyle(.link)`.
- The approval request uses the fixed `app_id` `9c21c21a-4ed4-4f29-8b5d-99fe76d9e9ab`, and `app_name` "Quill on {device name}".
- Copy, verbatim:
  - Welcome intro: "Write and edit your WordPress posts and pages on your Mac. Connect your site to get started."
  - Waiting: "Approve Quill in your browser" / "Log in to **{site name}** if asked, then approve the connection. Quill continues on its own." / "Browser didn't open?" + "Open it again"
  - Manual: "Connect with an application password" / "Create one in WordPress, then paste it here." / note: "This site doesn't allow approving apps from the browser, so Quill needs a password you create yourself." / "Open Profile Page" + " to create one under Application Passwords."
  - AI: "Connected to **{site name}**" / "Add AI writing help" / "Quill can draft posts, review your writing and rewrite selections with Claude. It uses your own Anthropic API key, and Anthropic bills you for what you use." / "Get a key from the " + "Anthropic Console" + ". You can change it later in Settings." / buttons "Skip for Now", "Save"
  - With no site name, "{site name}" reads "your site".
- Error copy, verbatim:
  - Insecure address: "Quill needs an https:// address."
  - Unusable address (decided in this plan; the spec doesn't name it): "Enter your site's address, like example.com."
  - Unreachable: "Couldn't reach {host}. Check the address and your connection."
  - Not WordPress: "This doesn't look like a WordPress site, or its REST API is turned off."
  - Declined: "Quill wasn't approved. Try again, or use an application password."
  - Rejected key: "Anthropic didn't accept this key."
  - Anthropic unreachable: "Couldn't reach Anthropic. Check your connection, or skip and add the key later in Settings."
- Comments: none, except a section label (see `~/.claude/CLAUDE.md`).
- After any app-code change, rebuild and relaunch with the command in the root `CLAUDE.md`.
- When a test suite changes, update the counts in `docs/testing-plan.md` and the root `CLAUDE.md`.
- Test isolation:
  - Each new network suite gets its own `URLProtocol` subclass in `Tests/QuillTests/Support/`, copied from `MockURLProtocol` with its own `static var requestHandler`. Suites never share one (`AGENTS.md`, test-suite gotchas).
  - No new suite sets `AppSupportDirectory.override`; storage is injected.
  - `AppState()` loads the real `ai_settings.json` in tests, so a test that needs a known AI state sets `appState.aiSettings` explicitly after creating it.

## Review Focus

1. **Pasted admin or login URLs.** Someone pastes `https://example.com/wp-admin/` or `…/wp-login.php`. `normalize` should strip from `/wp-admin` or `/wp-login.php` onward. *(Task 2)*
2. **Usernames with spaces.** WordPress builds the callback query with PHP's `urlencode`, so `John Doe` arrives as `John+Doe`. `parseCallback` must decode `+` as a space, while `%2B` still decodes to `+`. *(Task 3)*
3. **Empty strings in the REST index.** WordPress sends `"site_icon_url": ""` when there is no icon, and `name` can be `""`. Both must become nil, which gives the letter tile and "your site". *(Task 2)*
4. **Replayed callback.** The browser can re-fire `quill://…`, through a refresh, Back, or a double click on approve. After the first approval succeeds, the same URL must do nothing: no second save and no second connect. *(Task 6)*
5. **Return pressed twice on Welcome.** That must run one discovery and open the browser once. `continueTapped` does nothing while busy or outside Welcome. *(Task 6)*

---

## Chunk 1: URL scheme routing

Settles the spec's open risk: the dev build and `/Applications/Quill.app` share `com.siolon.quill`, so macOS may route `quill://` to the wrong copy.

### Task 1: Register the scheme and check where callbacks land

**Files:**
- Modify: `build.sh` (variables near the top; the Info.plist heredoc)
- Modify: `Sources/QuillKit/App/QuillApp.swift` (the `WindowGroup`)
- Modify: `Sources/QuillKit/Views/ContentView.swift` (`body`)

**Interfaces:**
- Produces: the Info.plist's `CFBundleURLTypes[0].CFBundleURLSchemes[0]` is the callback scheme. Task 3 reads it at runtime, so later code never hard-codes it.

- [x] **Step 1: Register `quill` in `build.sh`.** Add `URL_SCHEME="quill"` beside `BUNDLE_ID`. Add a `CFBundleURLTypes` array to the heredoc with one dict: `CFBundleURLName` = `$BUNDLE_ID`, `CFBundleURLSchemes` = [`$URL_SCHEME`].
- [x] **Step 2: Route external events to the existing window.** On the `WindowGroup`, add `.handlesExternalEvents(matching: ["*"])`. In `ContentView.body`, add `.handlesExternalEvents(preferring: ["*"], allowing: ["*"])` and a temporary `.onOpenURL { NSLog("QuillCallback %@", $0.absoluteString) }`.
- [x] **Step 3: Build and launch** with the root `CLAUDE.md` command. Expected: the build succeeds and `plutil -extract CFBundleURLTypes xml1 -o - Quill.app/Contents/Info.plist` shows `quill`.
- [x] **Step 4: Check routing with the `/Applications` copy not running.** Run `open "quill://authorize?nonce=check1"`, then `log show --last 2m --style json --predicate 'eventMessage CONTAINS "QuillCallback"' | grep -E 'processImagePath|eventMessage'`. Pass: the path is this repo's `Quill.app`, and the dev window shows no second window (take a screenshot with computer use).
- [x] **Step 5: Check routing with both copies running.** Open `/Applications/Quill.app` too, run `open "quill://authorize?nonce=check2"`, and read the log the same way. Pass: the log line comes from the dev build.
- [x] **Step 6: Decide.** **Decision (2026-10-02): keep `quill`.** Steps 4 and 5 passed: every callback reached the dev build, and each running copy kept one window. The installed 2.1.0 copy does not declare `quill`, so a scratch copy of the dev build that does (also at version 9.9.9, and launched before the dev build) was run too; the dev build still received every callback. macOS 27 redacts `NSLog` text as `<private>`, so the Step 4 grep only matches with `Logger().notice("QuillCallback \(url, privacy: .public)")`.
  - If Steps 4 and 5 both pass, keep `quill`.
  - If either fails, set `URL_SCHEME="quill"` only when `$RELEASE` is true and `quill-dev` otherwise. Rebuild, repeat Steps 4 and 5 with `quill-dev://`, and record the outcome in the spec's "Risk to settle first" paragraph.
  - Either way, also record it in this step's checkbox line.
- [x] **Step 7: Remove the temporary `NSLog` `.onOpenURL`.** Keep both `handlesExternalEvents` modifiers. Rebuild, then run `./test.sh`. Expected: all pass. Stop and summarize.

---

## Chunk 2: Site discovery and approval URLs

### Task 2: `SiteDiscovery`

**Files:**
- Create: `Sources/QuillKit/API/SiteDiscovery.swift`
- Create: `Tests/QuillTests/Support/DiscoveryMockURLProtocol.swift`
- Test: `Tests/QuillTests/SiteDiscoveryTests.swift` (`@Suite(.serialized)`, using `DiscoveryMockURLProtocol`)

**Interfaces:**
- Produces:
  ```swift
  public struct DiscoveredSite: Equatable, Sendable {
      public let siteURL: URL
      public let name: String?
      public let iconURL: URL?
      public let authorizationURL: URL?
  }
  public enum SiteDiscoveryError: Error, Equatable, LocalizedError {
      case insecure, invalidAddress, unreachable(host: String), notWordPress
  }
  public struct SiteDiscovery: Sendable {
      public init(session: URLSession? = nil)
      public static func normalize(_ input: String) throws(SiteDiscoveryError) -> URL
      public static func profileURL(site: URL, authorizationURL: URL?) -> URL
      public func discover(_ site: URL) async throws(SiteDiscoveryError) -> DiscoveredSite
      public func loadIcon(_ url: URL) async -> NSImage?
  }
  ```

- [x] **Step 1: Write the failing `normalize` tests.**
  ```swift
  #expect(try SiteDiscovery.normalize("lanternandink.com") == URL(string: "https://lanternandink.com"))
  #expect(try SiteDiscovery.normalize("  https://Example.COM/ \n") == URL(string: "https://example.com"))
  #expect(try SiteDiscovery.normalize("https://example.com/blog/") == URL(string: "https://example.com/blog"))
  #expect(try SiteDiscovery.normalize("https://example.com/wp-admin/") == URL(string: "https://example.com"))
  #expect(try SiteDiscovery.normalize("https://example.com/wp/wp-login.php?redirect_to=x") == URL(string: "https://example.com/wp"))
  #expect(try SiteDiscovery.normalize("http://localhost:8080") == URL(string: "http://localhost:8080"))
  #expect(throws: SiteDiscoveryError.insecure) { try SiteDiscovery.normalize("http://example.com") }
  #expect(throws: SiteDiscoveryError.invalidAddress) { try SiteDiscovery.normalize("") }
  #expect(throws: SiteDiscoveryError.invalidAddress) { try SiteDiscovery.normalize("not a site") }
  ```
- [x] **Step 2: Write the failing `profileURL` tests.**
  - With an authorization URL of `https://example.com/wp/wp-admin/authorize-application.php`, the result is `https://example.com/wp/wp-admin/profile.php#application-passwords-section`.
  - With nil and site `https://example.com/blog`, the result is `https://example.com/blog/wp-admin/profile.php#application-passwords-section`.
- [x] **Step 3: Write the failing `discover` tests.** The mock handler serves `GET https://example.com/wp-json/`. Fixture JSON:
  ```json
  {"name":"Lantern & Ink","namespaces":["wp/v2"],"site_icon_url":"https://example.com/icon.png",
   "authentication":{"application-passwords":{"endpoints":{"authorization":"https://example.com/wp-admin/authorize-application.php"}}}}
  ```
  - Full fixture: every field is mapped.
  - `"authentication": []`: `authorizationURL == nil`. WordPress sends an empty array when the list is empty.
  - `"site_icon_url": ""` and `"name": ""`: both nil.
  - HTML body: `.notWordPress`.
  - Status 404, 401, or 403: `.notWordPress`.
  - JSON with no `namespaces`: `.notWordPress`.
  - The handler throws `URLError(.cannotFindHost)`: `.unreachable(host: "example.com")`.
  - A response whose `url` is `https://www.example.com/wp-json/`: `siteURL == https://www.example.com`.
  - The request carries no `Authorization` header.
- [x] **Step 4: Run** `swift test --filter SiteDiscoveryTests`. Expected: FAIL, because the types are undefined.
- [x] **Step 5: Implement `SiteDiscovery.swift`.**
  - Normalize with `URLComponents`. Add `https://` when there's no scheme. Lowercase the host. Cut the path at `/wp-admin` or `/wp-login.php`, then trim trailing slashes. Drop the query and fragment. Allow `http` only for `localhost`, `127.0.0.1` and `::1`.
  - Decode the index with a private `Decodable` that tolerates `authentication` being an array (`try?` on the nested decode).
  - The session defaults to a static ephemeral session, as `AnthropicClient` does.
  - `errorDescription` returns the Global Constraints copy.
- [x] **Step 6: Run** `swift test --filter SiteDiscoveryTests`. Expected: PASS.

### Task 3: `AppAuthorization`

**Files:**
- Create: `Sources/QuillKit/Auth/AppAuthorization.swift`
- Test: `Tests/QuillTests/AppAuthorizationTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum AppAuthorization {
      public static let appID: String
      public static var callbackScheme: String
      public static func makeNonce() -> String
      public static func approvalURL(base: URL, nonce: String, deviceName: String, scheme: String = callbackScheme) -> URL
      public enum CallbackResult: Equatable { case approved(username: String, password: String), rejected, ignored }
      public static func parseCallback(_ url: URL, expectedNonce: String, scheme: String = callbackScheme) -> CallbackResult
  }
  ```
  `callbackScheme` reads the first `CFBundleURLSchemes` entry from `Bundle.main`, and falls back to `"quill"` when there is none (as under `swift test`).

- [x] **Step 1: Write the failing tests.**
  - `makeNonce()` is 64 lowercase hex characters, and two calls differ.
  - `approvalURL(base: https://example.com/wp-admin/authorize-application.php, nonce: "abc", deviceName: "Chris's MacBook", scheme: "quill")`:
    - `app_name` decodes to `Quill on Chris's MacBook`.
    - `app_id` equals `appID`.
    - `success_url` and `reject_url` both decode to `quill://authorize?nonce=abc`.
    - The raw `percentEncodedQuery` contains `success_url=quill%3A%2F%2Fauthorize%3Fnonce%3Dabc`. Values are encoded to the RFC 3986 unreserved set, so `?`, `=` and `&` can't leak into WordPress's own query.
  - `parseCallback`, with `expectedNonce: "abc"` and `scheme: "quill"`:
    - `quill://authorize?nonce=abc&site_url=x&user_login=John+Doe&password=p1` gives `.approved(username: "John Doe", password: "p1")`.
    - `user_login=a%2Bb` gives username `a+b`.
    - `quill://authorize?nonce=abc&success=false` gives `.rejected`.
    - Wrong nonce, missing nonce, missing `password`, an empty `user_login`, `quill-dev://authorize…` with scheme `quill`, and host `other` each give `.ignored`.
- [x] **Step 2: Run** `swift test --filter AppAuthorizationTests`. Expected: FAIL.
- [x] **Step 3: Implement.**
  - The nonce is 32 bytes from `SecRandomCopyBytes`, hex-encoded.
  - Build the query with `percentEncodedQueryItems`, each value encoded with `.alphanumerics` plus `-._~`.
  - When parsing, split `percentEncodedQuery` on `&` and `=`, replace `+` with a space, then `removingPercentEncoding`. `URLComponents.queryItems` doesn't decode `+`.
- [x] **Step 4: Run** `swift test --filter AppAuthorizationTests`. Expected: PASS. Update the test counts, run `./test.sh`, then stop and summarize.

---

## Chunk 3: Verify-and-save and key check

### Task 4: `ConnectSite`, adopted by Settings

**Files:**
- Create: `Sources/QuillKit/Auth/ConnectSite.swift`
- Modify: `Sources/QuillKit/Views/Settings/PreferencesView.swift:138-156` (the inline check-then-save)
- Create: `Tests/QuillTests/Support/ConnectSiteMockURLProtocol.swift`
- Test: `Tests/QuillTests/ConnectSiteTests.swift` (`@Suite(.serialized)`, using `ConnectSiteMockURLProtocol` and a recording `save` closure)

**Interfaces:**
- Produces: `public enum ConnectSite { public static func verifyAndSave(_ credentials: Credentials, session: URLSession? = nil, save: (Credentials) throws -> Void = CredentialsStore.save) async throws }`

- [x] **Step 1: Write the failing tests.**
  - When the mock returns `[]` with status 200 for `/wp-json/wp/v2/posts`, the `save` closure received exactly those credentials.
  - When the mock returns 401, the call throws and `save` was never called.
- [x] **Step 2: Run** `swift test --filter ConnectSiteTests`. Expected: FAIL.
- [x] **Step 3: Implement.** Call `WordPressClient(credentials:session:).fetchPosts(page: 1, perPage: 1)`, then `save`. Errors propagate unchanged.
- [x] **Step 4: Replace the inline block in `PreferencesView.saveAll`** with `try await ConnectSite.verifyAndSave(creds)` inside the existing `do`/`catch`. Keep the existing `saveError` and `isSaving` handling.
- [x] **Step 5: Run** `swift test --filter ConnectSiteTests`, then build and launch. Expected: PASS. Saving valid credentials in Settings still reloads the sidebar.

### Task 5: `AnthropicClient.verifyKey`

**Files:**
- Modify: `Sources/QuillKit/AI/AnthropicClient.swift` (`AnthropicError`, `AnthropicClient`)
- Test: `Tests/QuillTests/AnthropicClientTests.swift`

**Interfaces:**
- Produces:
  - `public func verifyKey() async throws` on `AnthropicClient`. It checks the client's own `apiKey`; the spec's `verifyKey(_ key:)` became an instance method so it matches the client's shape.
  - `AnthropicError.invalidKey`, with `errorDescription` "Anthropic didn't accept this key."
- If `2026-10-02-ai-model-selection-design.md` is already implemented, call its Models API request instead of adding a second one, and keep the same public signature.

- [x] **Step 1: Write the failing tests.**
  - The request is `GET https://api.anthropic.com/v1/models?limit=1`, with `x-api-key: test-key` and `anthropic-version: 2023-06-01`.
  - Status 200 succeeds.
  - Status 401 throws `.invalidKey`.
  - Status 500 throws `.httpError(500, …)`.
  - A thrown `URLError` gives `.networkError`.
- [x] **Step 2: Run** `swift test --filter AnthropicClientTests`. Expected: the new tests FAIL.
- [x] **Step 3: Implement.** Add the `invalidKey` case, including its branch in the `==` switch.
- [x] **Step 4: Run** `swift test --filter AnthropicClientTests`. Expected: PASS. Update the counts, run `./test.sh`, then stop and summarize.

---

## Chunk 4: Onboarding model

### Task 6: `OnboardingModel`

**Files:**
- Create: `Sources/QuillKit/Views/Onboarding/OnboardingModel.swift`
- Test: `Tests/QuillTests/OnboardingModelTests.swift` (`@MainActor`, `.serialized`; no network and no disk, since every effect goes through `Dependencies`)

**Interfaces:**
- Consumes: `SiteDiscovery`, `DiscoveredSite`, `SiteDiscoveryError` (Task 2); `AppAuthorization` (Task 3); `ConnectSite` (Task 4); `AnthropicClient.verifyKey`, `AnthropicError.invalidKey` (Task 5); `AppState.connect(_:)`, `AppState.aiEnabled`, `AppState.aiSettings`.
- Produces:
  ```swift
  @MainActor public final class OnboardingModel: ObservableObject {
      public enum State: Equatable {
          case welcome
          case waiting(site: DiscoveredSite, nonce: String)
          case manual(automatic: Bool)
          case aiSetup(siteName: String?)
          case finished
      }
      public struct Dependencies {
          var discover: @MainActor (URL) async throws -> DiscoveredSite
          var loadIcon: @MainActor (URL) async -> NSImage?
          var openURL: @MainActor (URL) -> Void
          var verifyAndSave: @MainActor (Credentials) async throws -> Void
          var verifyKey: @MainActor (String) async throws -> Void
          var saveAISettings: @MainActor (AISettings) throws -> Void
          var deviceName: @MainActor () -> String
          var makeNonce: @MainActor () -> String
          static var live: Dependencies { get }
      }
      @Published public private(set) var state: State
      @Published public var address: String
      @Published public var username: String
      @Published public var appPassword: String
      @Published public var apiKey: String
      @Published public private(set) var siteIcon: NSImage?
      @Published public private(set) var isBusy: Bool
      @Published public private(set) var errorMessage: String?
      public weak var appState: AppState?
      public var showsPanel: Bool { get }
      public var profileURL: URL? { get }
      public init(dependencies: Dependencies = .live)
      public func continueTapped() async
      public func useManualEntry()
      public func back()
      public func cancelWaiting()
      public func reopenBrowser()
      public func handleCallback(_ url: URL) async
      public func connectManually() async
      public func saveAIKey() async
      public func skipAI()
      public func openProfilePage()
      public func openAnthropicConsole()
  }
  ```
  - `showsPanel` is true when `appState?.credentials == nil` or the state is `.aiSetup`.
  - `live` wires `SiteDiscovery().discover`, `SiteDiscovery().loadIcon`, `NSWorkspace.shared.open`, `ConnectSite.verifyAndSave`, `AnthropicClient(apiKey:).verifyKey()`, `AISettingsStore.save`, `Host.current().localizedName ?? "Mac"` and `AppAuthorization.makeNonce`.
  - `openAnthropicConsole` opens `https://console.anthropic.com/settings/keys`.

Rules the tests pin:
- **Continue.**
  - `continueTapped` does nothing unless the state is `.welcome` and `isBusy` is false.
  - It normalizes `address` and discovers the site.
  - With no `authorizationURL`, it goes to `.manual(automatic: true)` and keeps the discovered site for the profile URL and the AI step's name.
  - Otherwise it makes a nonce, goes to `.waiting`, opens `approvalURL`, and loads the icon into `siteIcon`.
- **Errors.** Any thrown error sets `errorMessage` to the error's `localizedDescription` and leaves the state as it was. A state change clears `errorMessage`.
- **Callbacks.** `handleCallback` acts only in `.waiting`, and only with the matching nonce.
  - `.rejected`: back to `.welcome`, with the "Quill wasn't approved…" message.
  - `.approved`: build `Credentials` from the discovered `siteURL` and call `verifyAndSave`.
    - On success, set the state to `.aiSetup(siteName:)`, or to `.finished` when `appState.aiEnabled`, **before** awaiting `appState.connect`, so the app never flashes in for a frame. Posts start loading when the app appears, because `SidebarView` owns that load.
    - On failure, go to `.welcome` with the error message.
- **Manual.** `connectManually` normalizes the address and runs the same success and failure path as an approval.
- **Saving the key.** `saveAIKey` calls `verifyKey`.
  - On success it saves `AISettings(apiKey:)` through `saveAISettings`, sets `appState.aiSettings`, and goes to `.finished`.
  - `AnthropicError.invalidKey` stays on `.aiSetup` with its message.
  - `.networkError` stays with the "Couldn't reach Anthropic…" message.
  - Any other error stays with its `localizedDescription`.
- **Skip.** `skipAI` goes to `.finished` and saves nothing.

- [x] **Step 1: Write the failing tests.** Use fake `Dependencies` that record calls, and a real `AppState()` with `model.appState` set and `appState.aiSettings = nil` (its init reads the real `ai_settings.json`). Fix the nonce at `"n1"`, set the address to `example.com`, and make discovery return a site with an authorization URL unless the test says otherwise.
  - `continueOpensApproval`: the state is `.waiting(site:, nonce: "n1")`, and `openURL` was called once with a URL whose `success_url` holds `n1`.
  - `continueWithoutAuthorizationGoesManual`: `.manual(automatic: true)`.
  - `continueShowsDiscoveryError`: discovery throws `.notWordPress`, so the state stays `.welcome` and `errorMessage` is the not-WordPress copy.
  - `continueIgnoredWhenNotWelcome`: a second `continueTapped` while `.waiting` calls `discover` no more times. *(Review Focus 5)*
  - `declineReturnsToWelcome`: the callback `quill://authorize?nonce=n1&success=false` gives `.welcome` with the declined copy.
  - `staleNonceIgnored`: after `cancelWaiting()`, an approved callback for `n1` leaves the state at `.welcome`, with `verifyAndSave` never called.
  - `approvalWithoutKeyGoesToAISetup`: the state is `.aiSetup(siteName: "Lantern & Ink")`, and `appState.credentials?.username` is the callback's `user_login`.
  - `approvalWithKeySkipsAI`: with `appState.aiSettings = AISettings(apiKey: "k")`, the state is `.finished`.
  - `approvalCheckFails`: `verifyAndSave` throws, so the state is `.welcome` with the error, and `appState.credentials` is nil.
  - `replayedCallbackIgnored`: after a successful approval, the same URL again calls `verifyAndSave` no more times. *(Review Focus 4)*
  - `manualConnectGoesToAISetupWithoutName`: from `useManualEntry()`, `connectManually()` gives `.aiSetup(siteName: nil)`.
  - `profileURLFromDiscovery`: after the automatic manual state, `profileURL` uses the discovered site.
  - `skipSavesNothing`: `skipAI()` gives `.finished`, and `saveAISettings` was never called.
  - `saveRejectedKey`: `verifyKey` throws `.invalidKey`, so the state stays `.aiSetup` with "Anthropic didn't accept this key."
  - `saveGoodKey`: the state is `.finished`, `saveAISettings` received `apiKey == "sk-ant-x"`, and `appState.aiEnabled` is true.
- [x] **Step 2: Run** `swift test --filter OnboardingModelTests`. Expected: FAIL.
- [x] **Step 3: Implement `OnboardingModel.swift`** to the rules above.
- [x] **Step 4: Run** `swift test --filter OnboardingModelTests`. Expected: PASS. Update the counts, run `./test.sh`, then stop and summarize.

---

## Chunk 5: Views and wiring

Compare each view against the mockups file in a browser while building it. Layout, hierarchy and copy come from the mockups; native controls set the sizes.

### Task 7: Onboarding views

**Files:**
- Create in `Sources/QuillKit/Views/Onboarding/`: `OnboardingView.swift`, `OnboardingWelcomeView.swift`, `OnboardingWaitingView.swift`, `OnboardingManualView.swift`, `OnboardingAIView.swift`

**Interfaces:**
- Consumes: `OnboardingModel` (Task 6), `QuillMark.view(_:size:)`, `Color.wpContentSurface`, and the app accent (`Color.accentColor`).
- Produces: `struct OnboardingView: View { @ObservedObject var model: OnboardingModel }`

- [x] **Step 1: `OnboardingView`.**
  - Fills the window on `Color.wpContentSurface`. Holds a centered column 330pt wide that switches on `model.state`. Shows nothing for `.finished`.
  - `errorMessage` renders as `.callout` secondary text, under the field on Welcome and AI, and above Connect on Manual.
  - Each view runs its async action in a `Task`.
- [x] **Step 2: `OnboardingWelcomeView`.**
  - Quill mark in the accent color at height 61, then the title "Welcome to Quill", the intro, and the "Site address" field bound to `address`.
  - A row with the link "Use an application password instead" (calls `useManualEntry`) on the left and Continue on the right.
  - Continue is disabled while `address` is empty or `isBusy`. While busy it shows a small `ProgressView` in place of its label.
- [x] **Step 3: `OnboardingWaitingView`.**
  - Two 52pt rounded tiles with the dots between them. The left tile is the Quill mark. The right tile is `siteIcon`, or the site name's first letter (white, semibold) on the accent color.
  - The middle dot pulses with an opacity animation that is off when `accessibilityReduceMotion` is on.
  - The tiles are `accessibilityHidden(true)`; the sentence carries the site name.
  - Then the Cancel button, and "Browser didn't open?" with the link "Open it again".
- [x] **Step 4: `OnboardingManualView`.**
  - Title and intro. The amber note only when `.manual(automatic: true)`: accent at 12% opacity behind text in the primary color, 8pt corner radius.
  - Three fields (`SecureField` for the password), the help line with the "Open Profile Page" link, which is disabled while `model.profileURL` is nil (an empty or unusable address).
  - Back and Connect.
- [x] **Step 5: `OnboardingAIView`.**
  - The "Connected to" line with `checkmark.circle.fill` in green (`Color.statusColor("publish")`).
  - Title, intro, and the key field (`SecureField`, prompt `sk-ant-…`).
  - The help line with the "Anthropic Console" link.
  - "Skip for Now" (bordered) and "Save" (prominent, default), aligned right. Save is disabled while the key is empty or `isBusy`.
- [x] **Step 6: Build.** Expected: compiles. The views aren't reachable yet; Task 8 wires them in.

### Task 8: Wire it in and run it end to end

**Files:**
- Modify: `Sources/QuillKit/Views/ContentView.swift`

**Interfaces:**
- Consumes: `OnboardingView`, `OnboardingModel.showsPanel`, and `handleCallback` (Tasks 6 and 7). The routing modifiers come from Task 1.

- [x] **Step 1: Wire `ContentView`.**
  - Add `@StateObject private var onboarding = OnboardingModel()`.
  - In `body`, show `OnboardingView(model: onboarding)` when `onboarding.showsPanel`, and the existing `NavigationSplitView` otherwise. Keep `.toolbar(removing:)`, `.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)` and the frame on the outer view; they're load-bearing (see `Views/CLAUDE.md`).
  - In `.onAppear`, set `onboarding.appState = appState` before `loadCredentialsAtLaunch()`.
  - `.onOpenURL { url in Task { await onboarding.handleCallback(url) } }`
- [x] **Step 2: Remove the automatic `openSettings()`** from `loadCredentialsAtLaunch`, and remove the `openSettings` environment property if nothing else uses it. Keep the loading flags.
- [x] **Step 3: Build, launch, and run the first-run manual checks.** *Done 2026-10-02.* Passed: Welcome with no Settings window; insecure and not-WordPress errors; manual entry from the link, Back keeping the address; waiting state on siolon.com (letter tile, since it sends an empty `site_icon_url`); Cancel; a decline callback and a real approval both reaching the same window; the AI step showing "Connected to Siolon"; Skip saving no AI settings and posts loading; Settings showing no key and its Save still working; a stale approval with no onboarding in progress ignored; dark mode (dev build forced dark); relaunch with credentials going straight to the app.
  - Move `~/Library/Application Support/Quill/credentials.json` and `ai_settings.json` to the scratchpad. Never delete them.
  - Relaunch, and connect a real site through browser approval, then work through every case below.
  - Restore both files when finished, and revoke the test "Quill on {Mac}" passwords on the site's profile.
  - Pass:
    - Welcome appears, with no Settings window.
    - Approval comes back to the same window.
    - The AI step shows the site name, and posts load once you skip or save.
    - Declining shows the declined copy.
    - Manual entry works from the link.
    - The Settings save still works.
    - Dark mode looks right.
    - Relaunching with credentials saved goes straight to the app.
- [x] **Step 4: Run `./test.sh`**, then the fixture check from the root `CLAUDE.md`. Expected: all pass. Stop and summarize.

---

## Chunk 6: Docs and release checklist

### Task 9: Documentation

**Files:**
- Modify: `site/docs.html` ("Connecting to WordPress", around line 80; the AI Writing section)
- Modify: `docs/testing-plan.md` (manual release checklists)
- Modify: `CLAUDE.md` (root: the architecture tree, Key decisions)

- [ ] **Step 1: `site/docs.html`.** *Deferred to the release, so the guide isn't published early. Drafted and kept in `git stash` as "onboarding user-guide draft (site/docs.html) — apply at release".*
  - Rewrite "Connecting to WordPress" to lead with the browser approval steps (enter the address, approve in the browser, done). Keep the existing three-step application password instructions under a heading for sites that turn browser approval off.
  - In AI Writing, add one sentence: first-run setup offers to add the key.
- [x] **Step 2: `docs/testing-plan.md`.** Add the spec's four manual checks to the release checklist, worded as steps with pass conditions. Include the Chunk 1 outcome on which scheme dev builds use.
- [x] **Step 3: Root `CLAUDE.md`.**
  - Add `Onboarding/  OnboardingModel, OnboardingView (+ Welcome, Waiting, Manual, AI)` under `Views/`.
  - Add to Key decisions: "**Login:** first run connects through WordPress's browser approval (`authorize-application.php`), which calls back on `quill://authorize`; manual application-password entry is the fallback."
  - Use the `quill-dev` wording instead if Chunk 1 chose it.
- [ ] **Step 4:** *Deferred with Step 1.* Proofread `site/docs.html` in the browser pane. Stop and summarize.
