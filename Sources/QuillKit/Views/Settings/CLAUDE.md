# Settings views (PreferencesView, PostSettingsPanel)

Implementation gotchas specific to this directory, split out from the project root `CLAUDE.md` (2026-07-11) to keep the root file lazy-loaded. See the root `CLAUDE.md` for architecture, build/test commands, and cross-cutting conventions.

## Known gotchas

- **Page-specific settings panel** — `PostSettingsPanel` takes `postType: String` and `pages: [WPPost]`. When `postType == "page"` it shows Parent Page picker + Slug + Discussion (no categories, tags, or excerpt). Posts show categories, tags, slug, excerpt, and discussion. The `isPage` computed var drives all conditional rendering.
- **Style guide regeneration rules in `PreferencesView.saveAll()`** — the guide is regenerated only when: (a) sample post IDs have changed, or (b) no guide exists yet. If IDs are unchanged and a guide already exists, the existing guide is reused and no Claude call is made. If the WordPress site URL changes, `aiSamplePostIDs` is cleared and the guide is set to `nil` — post IDs from one site are meaningless on another. `saveAll()` is `async`; the button is disabled via `isAnalyzing` while the Claude call is in flight.
- **`PreferencesView` must not use `@EnvironmentObject`** — the SwiftUI `Settings` scene creates a separate window context that does not inherit the main app's environment objects. `PreferencesView` receives what it needs as explicit init parameters: `posts: [WPPost]` (for the sample post picker) and `onSaveAISettings: ((AISettings) -> Void)?` (to update `AppState` after saving). Both `QuillApp`'s `.sheet` and `Settings` scene pass these from `appState` at the call site where `AppState` is in scope.
