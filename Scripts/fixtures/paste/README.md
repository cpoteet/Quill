# Paste fixtures

Each pair is one clipboard exactly as WKWebView handed it to the editor's `paste` event: `<name>.html` is the `text/html` flavor and `<name>.txt` is `text/plain`. WebKit rewrites HTML from outside the page before the page sees it (computed styles inline, comments stripped), so these are captures of that output, not of what the source app wrote. `Scripts/test-editor-paste-sources.js` pastes every pair into the real `editor.html` in jsdom and checks the save with WordPress's own validator. What the cleanup does and why is in `docs/paste.md`.

These live in a subdirectory so the block-parser and fixture-validity globs of `Scripts/fixtures/*.html` never pick them up: they are clipboards, not `post_content`.

| Fixture | Source | How it was made |
|---|---|---|
| `word-native` | Microsoft Word 16 for Mac | Real. A document with native bulleted and numbered lists (a lettered sub-level), a table, centering, formatting and an embedded image, copied with ⌘A ⌘C in Word |
| `word-html-import` | Microsoft Word 16 for Mac | Real. The same content opened from HTML, so Word keeps HTML lists |
| `web-article`, `web-table`, `web-images`, `web-partial-inline`, `web-partial-list` | A web page | Real WebKit copy (the path Safari takes) of a test page with a site stylesheet |
| `web-wordpress-site` | A WordPress 7.1 front end | Real WebKit copy of rendered block markup, including render-only layout classes, an embed iframe and footnotes |
| `webkit-closed-details`, `webkit-closed-details-short`, `webkit-open-details` | A web page | Real WebKit copies that show its `<details>` serialization bug |
| `rtf-textedit` | TextEdit | RTF written by AppKit, the same writer TextEdit uses, converted to HTML by WebKit on paste |
| `vscode` | VS Code | Reconstructed from VS Code's known clipboard HTML, then sanitized by real WebKit |
| `google-docs` | Google Docs | Reconstructed from Docs' known clipboard HTML, then sanitized by real WebKit |
| `chatgpt`, `claude-ai` | Chat apps in a browser | Reconstructed from each site's rendered answer markup, then sanitized by real WebKit |
| `apple-notes` | Apple Notes | Reconstructed from Notes' HTML shape, then sanitized by real WebKit |
| `block-editor` | The WordPress block editor | Reconstructed from its copy handler (serialized blocks as HTML, plain text as text), then sanitized by real WebKit |

"Reconstructed" means the source app's HTML was written by hand from its known clipboard format, because capturing it needs a signed-in account. Replace one with a real capture when you can: copy in the app, save the pasteboard with `pbsnap save <dir>`, and run it through the harness in `snapshot` mode.

## The real-WebKit harness

jsdom cannot see what WebKit's paste sanitizer does, and several of the fixes in `docs/paste.md` exist only because of it. `Scripts/paste-harness/harness.swift` runs the bundled `editor.html` in a WKWebView. It puts a clipboard on the system pasteboard, pastes it with a native `paste:`, and writes out what the page received and what Quill would save. It stands in for Swift's upload by answering each `uploadPastedImages` token with a hosted URL.

```bash
swiftc -O Scripts/paste-harness/harness.swift -o /tmp/paste-harness
```

```bash
/tmp/paste-harness "$PWD/Quill.app/Contents/Resources/editor.html" cases.json out.json
```

`cases.json` is a list of `{ "name", "mode", … }`. The modes:

- `web` renders `html` (with an optional `css`) in a second web view and copies `select` (default `body`) the way Safari does.
- `url` does the same with a live page at `url`.
- `html` puts `html` on the pasteboard as `public.html`, with `text` as the plain flavor.
- `rtf` converts `html` to RTF with AppKit.
- `plain` puts only `text` on the pasteboard.
- `quill` loads `html` into the editor, copies with `select` (a JS function, default select all) and pastes it back. The result carries the load-and-save `baseline` for comparison.
- `snapshot` restores every flavor saved in `dir` by `Scripts/paste-harness/pbsnap.swift`.
- `png` and `file` put an image or a Finder file on the pasteboard.

The harness uses the system pasteboard, so it replaces whatever you had copied. Each row of `out.json` has the flavors the page saw (`paste`), the saved HTML (`saved`), the document JSON and any `uploads`. Check `saved` with `Scripts/wp-validator.js` (`problems`, and `resaved(html) === html`).
