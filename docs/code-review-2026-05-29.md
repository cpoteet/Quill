# Quill — In-Depth Code Review

**Date:** 2026-05-29
**Scope:** Full `Sources/QuillKit` Swift codebase, `editor.html` JS bridge, build & test setup
**Reviewer:** Claude (Opus 4.8)
**Method:** Manual static review.

---

## Summary

Quill is a well-structured, single-developer macOS app. The architecture is clean,
the WordPress/Gutenberg round-trip is thoughtfully handled, and `CLAUDE.md` documents
the non-obvious decisions unusually well. Most findings below are about **robustness,
data-loss footguns, and consistency** rather than outright defects.

---

## ✅ Resolved on 2026-05-29

The two high-severity findings and all four medium-severity findings have been fixed:

1. **Tests no longer destroy real user credentials.** A shared `AppSupportDirectory`
   helper now resolves the `Quill` data directory, and an `AppSupportDirectory.override`
   hook lets `KeychainStoreTests` redirect all stores to a throwaway temp directory.
   `KeychainStore`, `AISettingsStore`, and `AppDatabase.production()` all route through it.
2. **`PostEditorView` uses the shared `AppServices` connection.** It now injects
   `@EnvironmentObject var services: AppServices` and uses `services.draftStore` /
   `services.autosaveStore` everywhere, instead of opening a fresh SQLite connection
   (and re-running `migrate()`) on every load/autosave/save.
3. **Posts/pages are fully paginated.** `WordPressClient.fetchAllPosts()` /
   `fetchAllPages()` follow the `X-WP-TotalPages` header until all pages are retrieved;
   `SidebarView` calls these instead of the single-page fetches.
4. **Editor webview has a navigation-policy delegate.** `EditorCoordinator` implements
   `decidePolicyFor`: only `file://` loads are allowed; any other navigation is cancelled,
   and user-activated external links open in the default browser via `NSWorkspace`.
5. **HTTPS enforced + storage directory hardened.** `PreferencesView.saveAll()` rejects
   non-`https` site URLs (except localhost), and the `Quill` data directory is created
   with `0700` permissions, closing the brief world-readable window on credential files.
6. **In-memory DB fallback is surfaced.** `AppServices.storageUnavailable` is set when the
   on-disk DB can't be opened, and `QuillApp` shows an alert warning that drafts won't persist.

The remaining items below are lower-severity polish, left for a future pass.

---

## Low severity / polish (outstanding)

### 1. Stale comments referencing the removed CDN

The ready-watchdog comment says *"editorReady never fired — CDN modules likely failed to
load"* ([EditorCoordinator.swift](../Sources/QuillKit/Views/Editor/EditorCoordinator.swift)),
but Tiptap is now a local IIFE bundle with no CDN (per `CLAUDE.md`). Same in `EditorView`'s
load comment phrasing. Update to reflect the local bundle.

### 2. Raw server response bodies surfaced to the UI

`APIError.httpError(statusCode:body:)` carries the full response body
([WordPressClient.swift](../Sources/QuillKit/API/WordPressClient.swift)) and
`error.localizedDescription` is shown directly in `saveError`/`listError`. WordPress error
payloads can be long and may include internal detail. Consider mapping common status codes
(401/403/404/409/5xx) to friendly messages and logging the raw body rather than displaying it.

### 3. Per-call object allocation

- A new `WordPressClient` (and therefore a new ephemeral `URLSession`) is constructed on
  nearly every action (`searchLinks`, `save`, `loadItem`, `performDelete`, media ops…).
  Cheap individually, but a shared client keyed off `credentials` would be cleaner and reuse
  connections. `AnthropicClient` already shares a static session — the WP client doesn't.
- `ISO8601DateFormatter()` is allocated inline in `save()` and `parseWPDate()`
  ([PostEditorView.swift](../Sources/QuillKit/Views/Editor/PostEditorView.swift)).
  Formatters are relatively expensive; hoist to a static.

### 4. `AnthropicClient` hardcodes model and token budget

`model: "claude-haiku-4-5"` and `maxTokens: 4096` are fixed
([AnthropicClient.swift](../Sources/QuillKit/AI/AnthropicClient.swift)). For
full-post generation 4096 output tokens can truncate longer posts (the response would stop
mid-content and parsing may still "succeed" with a cut-off body). Consider raising the cap
for the generate path, or at least handling `stop_reason == "max_tokens"` by warning the
user. Also unlike `WordPressClient`, this client doesn't translate `CancellationError`.

### 5. Duplicated file-store boilerplate

`KeychainStore` and `AISettingsStore` still duplicate the save/load/delete pattern
([KeychainStore.swift](../Sources/QuillKit/Auth/KeychainStore.swift),
[AISettings.swift](../Sources/QuillKit/AI/AISettings.swift)). They now share the directory
logic via `AppSupportDirectory`, but a small generic `JSONFileStore<T: Codable>` would
remove the remaining duplication entirely.

### 6. `findWKWebView()` walks the entire window hierarchy

AI selection features locate the webview by recursively scanning every window's view tree
([PostEditorView.swift](../Sources/QuillKit/Views/Editor/PostEditorView.swift)). It
works, but it's fragile (breaks if a second `WKWebView` is ever added, e.g. a preview pane)
and runs on every selection change. The coordinator already holds a `weak var webView` —
plumbing that reference through to the view (e.g. via a binding or the coordinator) would be
more direct and robust.

### 7. Minor consistency notes

- `RenderedString.init(raw:)` sets `rendered = raw` — fine for local drafts, but worth a
  one-line comment since it's semantically "unrendered raw treated as rendered."
- `imageMimeType` defaults unknown extensions to `image/jpeg`
  ([PostEditorView.swift](../Sources/QuillKit/Views/Editor/PostEditorView.swift)),
  which could mislabel an upload; `application/octet-stream` (or rejecting) is safer.
- `handleDroppedImages` sets `saveError` on upload failure (the post-save error banner),
  which is a slightly surprising channel for a drag-drop failure — a toast would match the
  success path ("Image inserted").
- Stale `WPWriter.app` bundle (old app name) sits in the working tree. Harmless (gitignored)
  but worth deleting to avoid confusion.

---

## Things done well (worth preserving)

- **Ephemeral `URLSession` everywhere** to avoid keychain prompts — consistent and
  well-documented.
- **All Swift→JS injection goes through `JSONEncoder`/`JSONSerialization`** rather than
  string interpolation (`insertImage`, `setMediaSizes`, `applySpellErrors`, `applyLink`),
  which closes the obvious script-injection vector into the editor bridge.
- **`setContent` flows through `editor.commands.setContent`** (ProseMirror schema parsing),
  so malicious `<script>` in fetched WordPress content is dropped rather than executed.
- **Conflict detection** with a server-modified baseline refreshed on load, plus the
  autosave-stash restore flow, is genuinely thoughtful.
- **ATS** is correctly scoped: HTTPS required except an explicit localhost exception.
- **`CLAUDE.md`** is an exemplary record of non-obvious decisions and gotchas.

---

## Suggested priority order (remaining)

1. Update the stale CDN comments (#1).
2. Map HTTP error codes to friendly messages; stop surfacing raw bodies (#2).
3. Share a `WordPressClient` instance; hoist `ISO8601DateFormatter` to a static (#3).
4. Raise/handle the AI token budget; translate `CancellationError` in `AnthropicClient` (#4).
5. Extract a generic `JSONFileStore<T>` for the credential/AI-settings stores (#5).
6. Plumb the webview reference instead of `findWKWebView()` (#6).
7. Misc consistency cleanups (#7).
