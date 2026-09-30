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

## To do

- [ ] **5. Switching WordPress sites** (Codex bug 5; the user does switch sites)
  - `QuillApp` Settings `onSave` sets `appState.credentials` but leaves
    `selectedItem`, `mediaItems` and `selectedMedia` from the old site.
  - `autosaves` is keyed by post ID only (`Database.swift`), so site A's stash can
    restore into site B's post with the same ID.
  - Fix: when the site URL changes, flush the open post (through `beforeQuit`'s
    closure or `EditorHandle`), clear selection and media state, then set credentials.
    Add a `site` column to `autosaves` (migration like the existing `ALTER TABLE`s),
    key save/load/delete by site + post ID, and treat rows without a site as belonging
    to the current one once. Local drafts are site-independent; decide with the user
    whether they should stay that way.
- [ ] **6. AI results replace only the selection** (Codex bug 4, high)
  - `editor.html` `beginAIOperation` saves the whole doc; `showAIResult` and
    `discardAIResult` call `_restoreAIOriginal`, which puts the whole doc back, losing
    edits made anywhere while Claude responds.
  - The "✶ Rewriting…" placeholder is real content, so autosave or a post switch can
    save it (the known-unfixed entry in `Views/Editor/CLAUDE.md`).
  - Fix: show the placeholder as a decoration, keep the original slice and its range,
    map the range through later transactions, and replace or restore only that range.
    Read the AI entries in `docs/editor-gotchas.md` first (whitespace stripping,
    `insertContentAt` plain-text handling, container replacement for lists/tables).
    Add jsdom tests: edit elsewhere during an operation, then accept and discard.
- [ ] **7. Settings changes are tracked and reverted** (Codex bugs 10, 11)
  - `isDirty` compares title, body and footnotes only, so a settings-only change is
    lost on navigation with no prompt or stash.
  - `loadFromServer` (Revert / "Use Server") resets content but not settings, so the
    next save sends the old local settings; its fetch failure is ignored.
  - Fix: keep a clean `PostSettings` baseline set wherever clean title/content are set
    and include it in `isDirty`; reuse `applyRemotePost` in `loadFromServer` and show a
    failure. Decide with the user whether settings go in the autosave stash (needs a
    column) or only mark the post dirty. Local drafts store only the excerpt of all
    the settings; that limit is already disclosed.
- [ ] **8. Media library fixes** (Codex bugs 7, 8, 14, and what is left of 9)
  - `MediaLibraryView` alt-text save holds an array index across the network call
    (can crash) and swallows errors; `MediaDetailView.commitAltText` shows "Saved"
    regardless. Make the save throw, look the item up by ID afterwards, show failure.
  - `loadMoreMedia` runs in an unstructured task that a filter or search change does
    not cancel; a stale page can append to new results. Add a query generation.
  - `MediaPickerView` and `GallerySheet` fetch all media types; a first page with no
    images leaves nothing to trigger paging. Request `media_type=image`.
  - Library upload is checked against the type filter but not the search text
    (`MediaLibraryView.startUpload`). Low.
- [ ] **9. Small fixes, one commit**
  - Bug 12: `flushToDB` and `performAutosave` use `try?`; surface a failure (toast)
    and keep the post dirty.
  - Bug 16: `PreferencesView.saveAll` with an empty AI key returns early and keeps
    the old saved key; `try? AISettingsStore.save` hides failures.
  - Security 1: the `CredentialsStore` comment's keychain-equivalence claim is wrong;
    `JSONFileStore.save` writes then `chmod`s, leaving the file readable by others for a
    moment. Create it with 0600.
  - Security 2: `ButtonBlock` in `editor.html` renders its `href` without the
    `isCarryableAttr` script-URL check.
  - Security 3: `EditorCoordinator` allows every `file:` navigation although its doc
    says they are cancelled; allow only the editor's own file. Media "Open in
    Browser" and preview URLs skip `isAllowedExternalURL`.
  - Security 4: `Scripts/roundtrip-check.sh` passes the app password to curl as an
    argument; use `--config -` on stdin.
  - Dead code: `editorReady` in `Scripts/paste-harness/harness.swift`. The SPM
    `resources: [.copy("Resources")]` bundle nobody reads: either drop it, or have
    `build.sh` copy the whole directory (excluding `CLAUDE.md`), which also removes
    the "one `cp` line per resource" gotcha in the root `CLAUDE.md`. Ask the user.
  - Tests: `test-fixture-validity.js` "keeps every block's comment attributes" skips
    blocks missing from the output; `FixtureCheck.checkNoScriptRan` treats a JS error
    as zero handlers run; "every registry entry is covered" in
    `test-editor-block-settings.js` only checks the name appears in the file.
  - Docs: `docs/gotchas.md` says local drafts are written only on Save Draft;
    `Views/Editor/CLAUDE.md` lists an Insert Footnote context-menu item that does not
    exist; `Views/Media/CLAUDE.md` says only the library changes its paged list.
- [ ] **10. Footnotes keep preserved source byte for byte** (Codex bug 13)
  - `inlineFootnotes` in `editor-transforms.js` rebuilds the whole post through
    `innerHTML` before `wrapUnsupportedBlocks` captures unsupported-block source.
  - Fix: splice the list in at the delimiter's string position, the way
    `extractFootnotes` splices it out. Add a fixture with footnotes and an
    unsupported block using single-quoted attributes.

## Deferred

- `AppState` is not `@MainActor`. Cheap to add, but expect compiler fallout.
- `editor.html` (about 6,500 lines) holds CSS, JS and markup together, against the
  user's separate-files rule. Splitting it is large; the top-level `const` gotcha in
  the root `CLAUDE.md` applies.
- `Scripts/bundle-tiptap.sh` installs `^2` ranges with no lockfile, so regenerating
  the bundle is not reproducible. The committed bundle is what ships.
- `InspectorTitlebarFix` depends on private AppKit class names; it already degrades
  to doing nothing.
