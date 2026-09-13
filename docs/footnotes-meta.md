# Footnotes: why they live in post meta

`core/footnotes` is a **dynamic block**. Its registration in WordPress's own
`block-library.js` is `{ icon, edit }` — there is no `save()`. Nothing it shows
on the front end is stored in `post_content`.

Verified against `https://www.siolon.com/wp-includes/js/dist/block-library.js`
on 2026-09-13, and by round-tripping a real draft through the REST API.

## The wire format

`post_content` carries the markers and a self-closing delimiter:

```html
<p>Body text.<sup data-fn="ID" class="fn" id="ID-link"><a href="#ID">1</a></sup></p>
<!-- wp:footnotes /-->
```

Post meta `footnotes` carries the bodies, as a JSON string:

```json
[{"id":"ID","content":"The <em>note</em> body."}]
```

WordPress renders the list itself, generating the backref:

```html
<ol class="wp-block-footnotes">
  <li id="ID">The <em>note</em> body. <a href="#ID-link" aria-label="Jump to footnote reference 1">↩︎</a></li>
</ol>
```

Two consequences for Quill:

- **The marker's `id` must be `<fnId>-link`.** That is the anchor core's
  server-side render points its ↩︎ at. Quill wrote `ref-<fnId>` until 2026-09-13;
  posts saved before then have backrefs that do not resolve once migrated.
- **Quill must never write a backref.** WordPress adds one at render time, so a
  stored one is duplicated on the page.

## How Quill splits it

`extractFootnotes` / `inlineFootnotes` in `editor-transforms.js` are the split
and its inverse. The editor edits a real `<ol class="wp-block-footnotes">`;
the wire format never sees one.

- **Load** — `setContent(html, footnotesJSON)` runs `inlineFootnotes` *before*
  `wrapUnsupportedBlocks`. Order matters: a bare `<!-- wp:footnotes /-->` has no
  inner markup, so `blockNeedsWrapping` would otherwise freeze it into a
  passthrough card. A post whose meta *is* empty gets exactly that, which is the
  right outcome — there is nothing to edit.
- **Save** — `getContent()` returns the content with the delimiter;
  `getFootnotes()` returns the meta JSON. `PostPayload.footnotes` sends it as
  `meta.footnotes`; `nil` omits the key so a payload that never touched
  footnotes cannot blank out what the post has.
- **Authority** — only the visual document is authoritative for the bodies.
  Code view shows the delimiter alone, so `_postContent(html, false)` there
  leaves `_footnotes` untouched; an edit in code view must not clear what the
  delimiter stands for.

## Migration

A post written before 2026-09-13 has the `<ol>` inline in `post_content` and
empty meta. Loading it changes nothing (`inlineFootnotes` with empty meta is a
no-op, and the inline list parses as it always did). The **first visual edit**
extracts the bodies into meta and leaves the delimiter behind — so migration
happens on save, per post, only when the post is actually edited.

Legacy `<a class="footnote-backref">` anchors are stripped out of the bodies on
the way into meta.

## Local storage

Both stash tables carry the JSON alongside the content, so a recovered draft
keeps its footnote bodies: `local_drafts.footnotes` for local drafts,
`autosaves.footnotes` for the unsaved-changes stash on remote posts.

WordPress's own `/autosaves` endpoint takes title, content and excerpt only, so
a remote autosave revision never carries meta. That is a WordPress limit, not a
Quill one, and Quill's local stash is what the restore prompt actually reads.
