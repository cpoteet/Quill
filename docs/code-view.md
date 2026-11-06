# Code view (`editor.html`)


`editor.html` has a `</>` toggle button (`#btn-code-view`) in the toolbar's utility group (alongside spell-check and image-align controls). Clicking it switches the Tiptap editor for a `<textarea id="code-editor">` showing the raw WordPress HTML.

**State:** `codeViewActive` (boolean, JS module-level) tracks which mode is active.

**`_enterCodeView()` / `_exitCodeView()`** — helpers that toggle DOM visibility, the button's `.active` class, and the disabled state of all other toolbar controls. `_exitCodeView()` compares the textarea value against `_codeViewOriginal`; if the user made no changes, `editor.commands.setContent` is skipped entirely (preserving Tiptap's visual state). Only when the user actually edited the HTML does `_exitCodeView()` call `_parseCodeView()` to parse it back into Tiptap, then post `toWordPressHTML(editor.getHTML())` to Swift.

**`window.getContent()`** returns `textarea.value` when `codeViewActive`, otherwise `_rawHTML` if set (the last raw HTML loaded from WordPress), or `toWordPressHTML(editor.getHTML())` after visual or code-view edits.

**A code-view edit is saved as Quill writes it, never as typed.** The textarea holds `formatHTML`'s blank lines, and a class typed onto an element has no `className` in its comment yet, which Gutenberg flags as invalid. So `window.flushContent()`, which Swift calls before every save, autosave and post switch, runs `_parseCodeView()` whenever code view is open and edited (`_codeViewEdited()`), and returns the document's `toWordPressHTML` output — even when no debounced post is pending, because the debounce already posted the raw textarea. A block the parse cannot represent is reported through `_reportBlocksAtRisk` and is not saved.

**`_parseCodeView()`** — parses the textarea into Tiptap (`_wrapIncoming`, footnotes inlined) and clears `_rawHTML`. `_codeViewParsed` holds the textarea value it last parsed, so a flush followed by an exit parses once; `_codeViewDirty` records that a parse happened since code view opened. Footnote bodies come from `_codeViewFootnotes`, the copy of `_footnotes` taken on entry: each save rewrites `_footnotes` from the parsed document, so a marker deleted, saved and then restored by undo in the textarea would otherwise come back with an empty body. `updateToolbar()` returns while `codeViewActive`, so this parse leaves the code-view toolbar disabled.

**`window.setContent()`** exits code view silently (without round-tripping the textarea through Tiptap) before loading the new HTML, so switching posts always lands in visual mode.

**`_rawHTML`** — stores the last raw HTML passed to `setContent()`. Cleared by a code-view parse and on every Tiptap `update` event so Tiptap becomes the source of truth after visual edits. Used by `getContent()` so saving without any visual edits sends the original WordPress HTML (including block comments) back verbatim.

**`_rawHTMLOnLoad`** — set in `setContent()` only. While `_rawHTML` is still set (no visual or code-view edit since the load), `_enterCodeView()` seeds the textarea from it, so code view shows the post exactly as WordPress stored it; after any edit, it shows `toWordPressHTML(editor.getHTML())` instead.

**`_codeViewOriginal`** — snapshot of the textarea value captured in `_enterCodeView()` (after formatting). `_exitCodeView()` compares `textarea.value` against this to detect whether the user changed anything. Set to `null` after comparison. Prevents unnecessary `setContent` calls (and the content wipe / compounding-whitespace regression they cause) when the user enters and exits code view without editing.

**`_codeViewChanged()`** — debounced `input` listener attached to the textarea on `_enterCodeView` and removed on `_exitCodeView`. Fires `contentChanged` to Swift on a 500 ms debounce, keeping `htmlContent` in sync so ⌘S saves code-view edits without requiring an explicit exit. Uses the same `debounce` variable as the visual editor; `_exitCodeView()` cancels any pending debounce and fires `contentChanged` directly with the final value.

**`formatHTML(html, doc)`** — pure DOM HTML pretty-printer in `editor-transforms.js`, called by `_enterCodeView`. Block elements indented, inline elements inline, void elements self-close, `<pre>` verbatim, HTML comment nodes (nodeType 8) preserved verbatim. 17 JS tests.

**Link extension:** `Link.configure({ openOnClick: false, HTMLAttributes: { target: null, rel: null } })` — the `target: null` and `rel: null` override the Tiptap Link default of `target="_blank" rel="noopener noreferrer nofollow"`, which would otherwise be added to every link.

