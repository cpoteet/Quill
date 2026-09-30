# Codex review fixes

A full-codebase Codex review on 2026-09-29 reported 31 findings. Each was checked
against the code before this list was written: 27 hold as described, 3 are real but
matter less than Codex rated them, 1 (media offsets) is mostly wrong. Checking also
found a quit problem Codex missed, since fixed. This file is the working list for
the rest. Tick a box when its commit lands.

## How to work through it

- Work on `main`, one group per commit. Build and relaunch after every change
  (the command in the root `CLAUDE.md`) and run `./test.sh`.
- Run the real-WebKit fixture check whenever `editor.html` or a Resources JS file changes.
- Anything that writes to WordPress (save, publish, preview) touches the live site.
  Test it only on a new local draft or with the user's say-so.
- Update the per-directory `CLAUDE.md` or `docs/` entry a change affects, and the test
  counts in `CLAUDE.md` and `docs/testing-plan.md` when a suite changes.
- Commits 1–3 skipped the Codex pre-commit review at the user's request. Ask whether
  the remaining commits should have one, or one review over the whole range at the end.

## Done

- [x] **1. Quit and pending typing** — `10accae`. `window.flushContent()` plus
  `EditorHandle`; flushed before save, preview, switch, disappear and quit;
  `QuillAppDelegate` saves before quitting; stale content messages dropped while a
  `setContent` is unanswered. New suite `Scripts/test-editor-bridge.js`.
- [x] **2. Preview guards and footnotes** — `7e301c4`. `writeBlockedReason(_:)` shared
  by save, Save Draft and preview; preview sends footnotes, and for a draft writes them
  with `WordPressClient.updateFootnotes` because WordPress drops meta on that path.
  Not exercised against a live site.
- [x] **3. Local publish keeps concurrent edits** — `1d80d8e`. Typing during the create
  is stashed as the new post's autosave; a failed draft delete is a warning, not a
  failure. Not exercised against a live site.
- [x] **4. Dropped images go to the post they were dropped on** — drop and paste
  capture `loadedItem?.id` before queueing; each upload inserts through
  `EditorHandle.insertImage` only while that post is still open, otherwise the toast
  says it went to the Media Library only. The picker sheet keeps `.insertMediaURL`.
  Not exercised against a live site.
- [x] **5. Switching WordPress sites** — `AppState.connect` flushes the open post
  under the old site, then clears selection, lists and media. Autosaves are keyed by
  `(site, post_id)` (table rebuilt; old rows adopted once by the first site to load).
  Local drafts stay site-independent (user's call). Media reloads on a site change.
- [x] **6. AI results replace only the selection** — the operation is `aiOperation`
  plugin state, mapped through later edits; "✶ Rewriting…" is a widget decoration with
  the pending text dimmed; Discard inverts only the insertion step. Six jsdom tests.
  The decoration's look has not been checked in the running app.
- [x] **7. Settings changes are tracked and reverted** — `cleanSettings` baseline in
  `isDirty`; Revert applies the fetched post through `applyRemotePost` (settings
  included) and toasts a failure; `PostSettings(post:)` is the one mapping. Open: a
  settings-only change on a remote post is still dropped on leaving it, because the
  stash holds only the body and there is no leave prompt. The user chose to leave it.
- [x] **8. Media library fixes** — alt-text save throws, shows "Not saved: …", and
  applies through `AppState.replaceMedia` (by ID); `loadMoreMedia` drops a page whose
  `reloadKey` changed; the picker and gallery sheets request `media_type=image`; a
  library upload during a search clears the search instead of inserting.
- [x] **9. Small fixes** — three commits (`c375306`, `7b8f1ec`, and the tests/docs
  one). Security 1–4, bugs 12 and 16, `build.sh` copies the Resources directory, the unused SPM `resources:` bundle removed, the three weak tests tightened, the
  three docs corrected. The sheets now page by offset too, since the doc claim that
  only the library mutates its list was wrong.
- [x] **10. Footnotes keep preserved source byte for byte** — `inlineFootnotes`
  splices the list in at the delimiter's string position. The regression test is in
  `test-editor-footnotes.js`, not a fixture file: the fixture corpus has no way to
  pass footnote meta, so a fixture would never reach this path.

## To do

Nothing.

## Deferred

- `AppState` is not `@MainActor`. Cheap to add, but expect compiler fallout.
- `editor.html` (about 6,500 lines) holds CSS, JS and markup together, against the
  user's separate-files rule. Splitting it is large; the top-level `const` gotcha in
  the root `CLAUDE.md` applies.
- `Scripts/bundle-tiptap.sh` installs `^2` ranges with no lockfile, so regenerating
  the bundle is not reproducible. The committed bundle is what ships.
- `InspectorTitlebarFix` depends on private AppKit class names; it already degrades
  to doing nothing.
