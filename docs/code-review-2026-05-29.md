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

## ✅ Resolved on 2026-05-29 (session 1)

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

---

## ✅ Resolved on 2026-05-29 (session 2)

All remaining low-severity/polish items have been fixed:

1. **Stale CDN comment updated.** `EditorCoordinator` watchdog comment now correctly
   references the local IIFE bundle rather than CDN modules.
2. **HTTP errors show friendly messages.** `APIError.httpError` maps 401/403/404/409/5xx
   to plain-English strings; the raw server body is logged to stderr instead of shown to the
   user.
3. **Shared `URLSession` across all `WordPressClient` instances.** `WordPressClient` now
   holds a `private static let sharedSession` (ephemeral config, mirroring `AnthropicClient`),
   so all instances reuse the same connection pool. `ISO8601DateFormatter` hoisted to a
   `private static let` in `PostEditorView`.
4. **AI token budget is dynamic; truncation is surfaced.** `AnthropicClient.complete()`
   accepts `maxTokens:` and `model:` parameters (defaulting to current values). Returns
   `Result(text:truncated:)` instead of a plain `String`. `GeneratePostSheet` runs an
   initial 4096-token pass; if truncated, prompts the user to regenerate at 16 384 tokens
   or use what was generated. Selection edits and style-guide generation are unaffected.
   `CancellationError`/`URLError.cancelled` now translate cleanly rather than surfacing as
   an error.
5. **Duplicated file-store boilerplate extracted.** New `JSONFileStore<T: Codable>` in
   `Sources/QuillKit/Storage/JSONFileStore.swift` handles atomic write + chmod 600.
   `KeychainStore` and `AISettingsStore` each reduced to three one-line forwarding methods.
6. **`findWKWebView()` replaced with a direct reference.** `EditorView` gains an
   `onWebViewCreated: ((WKWebView) -> Void)?` callback, called asynchronously from
   `makeNSView`. `PostEditorView` stores the reference in `@State private var editorWebView`
   and uses it directly in `handleSelectionChange` and `executeAIOperation`. The recursive
   view-tree walk and its helper are deleted.
7. **Misc consistency fixes.**
   - `RenderedString.init(raw:)` has a one-line comment explaining why `rendered = raw`.
   - `imageMimeType` unknown-extension default changed from `image/jpeg` to
     `application/octet-stream`.
   - Drag-drop upload failures now route to `toastMessage` (matching the success toast),
     not the persistent `saveError` banner.
   - Stale `WPWriter.app` bundle deleted from the working tree.

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
