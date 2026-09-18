# Code view (`editor.html`)


`editor.html` has a `</>` toggle button (`#btn-code-view`) in the toolbar's utility group (alongside spell-check and image-align controls). Clicking it switches the Tiptap editor for a `<textarea id="code-editor">` showing the raw WordPress HTML.

**State:** `codeViewActive` (boolean, JS module-level) tracks which mode is active.

**`_enterCodeView()` / `_exitCodeView()`** — helpers that toggle DOM visibility, the button's `.active` class, and the disabled state of all other toolbar controls. `_exitCodeView()` compares the textarea value against `_codeViewOriginal`; if the user made no changes, `editor.commands.setContent` is skipped entirely (preserving Tiptap's visual state). Only when the user actually edited the HTML does `_exitCodeView()` call `setContent(html, false)` to parse it back into Tiptap.

**`window.getContent()`** returns `textarea.value` when `codeViewActive`, otherwise `_rawHTML` if set (the last raw HTML loaded from WordPress), or `toWordPressHTML(editor.getHTML())` after visual edits — so Swift's save/autosave paths work correctly from either mode.

**`window.setContent()`** exits code view silently (without round-tripping the textarea through Tiptap) before loading the new HTML, so switching posts always lands in visual mode.

**`_rawHTML`** — stores the last raw HTML passed to `setContent()` or saved from code view. Cleared on every Tiptap `update` event so Tiptap becomes the source of truth after visual edits. Used by `getContent()` so saving without any visual edits sends the original WordPress HTML (including block comments) back verbatim.

**`_rawHTMLOnLoad`** — like `_rawHTML` but never cleared by visual edits. Set in `setContent()` and updated in `_exitCodeView()` only when the user edited the textarea. Used by `_enterCodeView()` to seed the textarea, so block comments (e.g. `<!-- wp:gallery -->`) remain visible in code view even after the user has typed in the visual editor. After exiting code view with an edit, `_rawHTMLOnLoad` is updated to the code-view-edited HTML so subsequent re-entries show the latest code.

**`_codeViewOriginal`** — snapshot of the textarea value captured in `_enterCodeView()` (after formatting). `_exitCodeView()` compares `textarea.value` against this to detect whether the user changed anything. Set to `null` after comparison. Prevents unnecessary `setContent` calls (and the content wipe / compounding-whitespace regression they cause) when the user enters and exits code view without editing.

**`_codeViewChanged()`** — debounced `input` listener attached to the textarea on `_enterCodeView` and removed on `_exitCodeView`. Fires `contentChanged` to Swift on a 500 ms debounce, keeping `htmlContent` in sync so ⌘S saves code-view edits without requiring an explicit exit. Uses the same `debounce` variable as the visual editor; `_exitCodeView()` cancels any pending debounce and fires `contentChanged` directly with the final value.

**`formatHTML(html, doc)`** — pure DOM HTML pretty-printer in `editor-transforms.js`, called by `_enterCodeView`. Block elements indented, inline elements inline, void elements self-close, `<pre>` verbatim, HTML comment nodes (nodeType 8) preserved verbatim. 17 JS tests.

**Link extension:** `Link.configure({ openOnClick: false, HTMLAttributes: { target: null, rel: null } })` — the `target: null` and `rel: null` override the Tiptap Link default of `target="_blank" rel="noopener noreferrer nofollow"`, which would otherwise be added to every link.

