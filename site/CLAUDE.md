# site/

The public site (quill.siolon.com). Plain HTML, no build step.

## The user guide (`docs.html`)

`docs.html` is the end-user guide. Edit it directly; it has no Markdown source. It was cut from about 15,000 words to about 7,300 in November 2026 because it had become a record of every fix, not a guide. These rules apply to every edit, inside the `wrap-up` skill or not.

**The bar for adding text.** Add a sentence only if a writer would come to the guide to look it up, or would be surprised or lose work without knowing it. Most changes make Quill behave the way a writer already expects, and need no text at all. When in doubt, leave it out.

**Don't document:**
- A bug fix or polish that just makes something work ("clicking beside a line puts the cursor in it")
- Edge cases: what happens mid-save or mid-upload, after switching posts, at a block's edge, or with the cursor in a caption, citation, title or button
- Error, notice and empty-state wording. The app shows it when it happens
- Where an inserted, pasted, dropped or moved block lands, beyond "after the block you're in"
- Why something works the way it does, or how Quill stores it
- Something the guide already says. Link to it instead (the Keyboard Shortcuts section and the toolbar tables are the reference; prose doesn't repeat shortcuts)

**Do document:** what each control does, how to do each task, anything that changes or deletes content on WordPress (Preview saving a draft, Conflict Detected, permanent deletes), and what Quill keeps or won't keep from the WordPress editor (Limitations and Compatibility).

**When something changes or is removed,** correct or delete every mention: `grep -n` the old label, shortcut or block name across the whole file. The same fact can appear in the toolbar tables, Keyboard Shortcuts and Block Editor Compatibility.

**App icons.** The guide shows the app's own icons beside the names of buttons and statuses, drawn with `<span class="docs-icon docs-icon--NAME" aria-hidden="true">` (a CSS mask filled with the text colour, or a status colour) so the name stays the text. Two generated sets; never edit either by hand:
- `images/symbols/*.svg` — Apple's SF Symbols for the window toolbar and the status badges, from `swift Scripts/export-symbol-icons.swift` (needs `brew install poppler`).
- `images/editor/*.svg` — the formatting toolbar's own icons, copied out of `editor.html` by `node Scripts/export-editor-icons.js`. Its buttons drawn as text (B, I, S, A, {}, *, ABC, </>, P) are `.docs-glyph` spans instead.

A new icon is one entry in the right script's list plus one `.docs-icon--NAME` line in `style.css`.

**Markup.** Match the existing `docs-*` classes. A new `h2` goes in the Contents list. Give a heading an `id` only when something links to it. Every `href="#…"` must resolve. Keep the ids linked from outside the page: `#connecting-to-wordpress` (`index.html`), plus `#requirements--installation`, `#saving--publishing` and `#working-with-blocks` (the screenshot draft in `.claude/skills/site-screenshots/quill-draft.md`).
