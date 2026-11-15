---
name: site-screenshots
description: Use when replacing or refreshing the screenshots on the public site (quill.siolon.com, site/index.html) — the hero, the editor/Accordion, Evaluate, local-draft and Media images in light and dark, and the og-image link-preview card — for example after a UI change makes them stale.
---

# Site screenshots

Retakes the five light/dark image pairs in `site/images/` and re-renders `site/images/og-image.png`, at exactly the sizes and window positions `site/index.html` and `site/style.css` expect. It runs against Chris's live site, with Chris at the keyboard: Chris switches Light/Dark (the agent can't), and frames any shot that takes the agent more than a couple of tries.

**Announce at start:** "Retaking the site screenshots."

## Work with Chris, not around him

- **Each shot is framed once and captured in both appearances back to back.** Capture it, Chris flips Light/Dark, capture it again, so the pair is identical. Alternate which appearance comes first, so there is one flip per shot.
- **If framing a shot isn't right after two attempts, stop and ask Chris to frame it.** Chris can line up a scroll position by eye in seconds; nudging it a few points at a time costs minutes. Say exactly what has to be true (the table below), arm `capture-when-ready.sh`, and let Chris do it.
- Report failures in one line with the fix ("the next post peeks in at the bottom of the list: scroll the list up a little"), not a log of attempts.

## What each image shows

| File (`site/images/`) | Window (points) | Content and state | Copy it illustrates |
|---|---|---|---|
| `hero-editor` | 900×680, sidebar and inspector hidden | Local draft **A** (`quill-draft.md`) at the top: title, active toolbar (click into the body first), first paragraph, "Writing without a connection". An opaque crop with no chrome; the green Published check is pasted over the local-draft badge. | "Write, edit and publish…" |
| `blocks-view` | 1290×710, sidebar (Posts) and Post Settings shown | **Learning to Build with Codex**: the paragraph ending "…had to do from another site.", the gallery card and the **Features** Accordion. The caret is in the Accordion's first bullet, so its settings row (+Item, −Item, Auto-close, Open, Icon, Left, Right, ×) shows, and the pointer rests on "Features", so the ¶ grip shows. Codex is the second row of the post list. | Containers edit like text; "Set a block's options"; "Drag a block to move it" |
| `evaluate-view` | 1094×663, sidebar hidden, Evaluate panel at its default width. Only if that run's feedback doesn't fit: 1170×709 with the panel dragged to its 400pt maximum | The same post at the top, caret in plain text (not a link, which adds a link row), Evaluate finished. The whole panel shows: summary, numbered suggestions, Fixes / Ideas / Facts to Check counts, Re-evaluate. | What works, the few changes, the list of fixes |
| `draft-view` | 1186×652, sidebar (Drafts) shown, inspector hidden | Local draft **B** (`quill-draft-view.md`) with ` It has replaced the browser tab for me.` added (unsaved) to the first paragraph, so a change bar sits beside it. Draft B is the only draft listed. | Drafts stay on your Mac; "Bars in the margin…" |
| `media-view` | 1186×652, sidebar (Media, All Media) shown, inspector shown | The grid at the top, thumbnails loaded, **The Five Stages of AI Reckoning** selected with one click. The inspector shows Title, Alt Text, Caption and the URL with its copy button. | Browse, filter by type, edit titles/captions/alt text, copy a URL |

**Every image:** no text caret, and no cut-off line of text or partial row at the edge of the editor, the post list or the inspector. A container's border running off the bottom is fine; its text isn't.

The four window shots keep a transparent background with the native shadow. `compose.py` (`SHOTS`) holds each canvas size and window position. The 65-of-1400 and 93-of-2200 shadow margins are hard-coded in `site/style.css`, so a window size can change (keep its proportions: the canvas stays the same), but a canvas can't without changing the CSS and the `width`/`height` attributes in `index.html`. Quill's minimum window is 900×652.

## Ground rules: this runs against the live site

- **Never send anything to WordPress.** Never press ⌘S or ⇧⌘P, or click Save to WordPress / Update / Publish, while a post from Posts is open. ⌘S is allowed only on the skill's own local drafts.
- **Never type in the Codex post.** Click only to place the caret. If a change slips in (the close button shows a dot), **File → Revert to Saved**, which reloads the server copy. Revert does nothing on a local draft.
- **Evaluate panel:** never click Apply or open a Fixes/Ideas/Facts row. **Media:** select with one click, and don't type in Title, Alt Text or Caption (a changed field saves when it loses focus).
- **Don't change System Settings**, Light/Dark included, even if asked: Chris flips it.
- Don't commit. Summarize and wait.

## Tools (all in this folder)

- `winid.swift` → window ID for `screencapture -l`. `scroll.swift` → pixel-precise scrolling at a screen point, refusing unless Quill's window is under it (it moves the pointer). Build both into the scratchpad with `swiftc -O`.
- `compose.py` (python3 without `-I`; Pillow is in the user site-packages):
  - `<shot> <capture> <out.webp>` places and encodes a window shot and checks it. It refuses an inactive window (grey close button) or a window of the wrong size.
  - `hero-editor <capture> <out> --badge-from <evaluate capture>` crops the hero and pastes the green check from the Evaluate capture of the same appearance.
  - `steady <out.png> <frames…>` keeps the frame of a 16-capture burst in which the fading caret is fully off.
  - `edges <capture> name:x0,y0,x1,y1[,band] …` fails if content is within `band` points (default 1) of a box's top or bottom edge. Boxes are window points; use band 6–16 for the post list.
  - `stable <a> <b>` and `check <out.webp> <shot>`.
- `capture-when-ready.sh <scratch> <shot> [edge boxes…]`, run in the background: it waits for Quill to come to the front and settle for 3 seconds, captures the current appearance, waits for the flip and a settle, then captures the other. Use it whenever Chris frames.
- `site-state.py` → read-only REST snapshot (the Codex post's and media item's `modified_gmt`, post and page totals).
- **Computer-use screenshots aren't in points.** On this Mac the frame is about 0.93× the real points, so measure positions from a `screencapture` in window points, not from the computer-use image.
- `open Quill.app` brings Quill to the front without moving the pointer; use it right before a capture when Chris is holding the pointer on something.

Starting edge boxes for these layouts (re-measure if the layout changes):

| Shot | Boxes |
|---|---|
| hero | `hero:4,50,860,612` |
| evaluate, widened (1170×709, 400pt panel) | `editor:30,135,768,709 panel:780,93,1160,671` |
| evaluate, default (1094×663) | not measured yet: the editor ends where the panel starts; measure both from a capture |
| blocks (inspector ~300pt) | `editor:270,178,980,710,2 list:24,150,250,710,6 inspector:1000,52,1270,708` |
| draft | `editor:270,130,1160,652` |

## Setup

1. `S=<scratchpad>/site-shots; mkdir -p "$S/raw" "$S/out"`, `K=.claude/skills/site-screenshots`, and build `winid` and `scroll` into `$S`.
2. Build and run Quill exactly as the project `CLAUDE.md` says.
3. Record the starting state: `python3 "$K/site-state.py" > "$S/site-before.txt"`, `sqlite3 ~/Library/Application\ Support/Quill/drafts.db "select site, post_id, saved_at from autosaves order by 1,2; select id, title from local_drafts;" > "$S/db-before.txt"`, and the window frame (`get {position, size} of window 1`).
4. Move the window to `{60, 60}` so the 1290-point blocks window fits on screen.
5. `request_access` for Quill, then `request_full_control`. Release full control before every question to Chris, and request it again after.

## Capture order (one flip per shot)

1. **Drafts.** File → New Post. Click the title and type it (never press Return there). `pbcopy < "$K/quill-draft.md"`, click the body, ⌘⇧V, ⌘S. Repeat for draft B with `quill-draft-view.md`.
2. **Evaluate (Light, then Dark).** Open the Codex post, hide the sidebar, 1094×663, panel at its default width. Click plain text in the first paragraph. Click Evaluate and wait for every row and count.
   - **Resize only if you have to.** Evaluate's feedback varies in length from run to run. Scroll the panel to its end: if the summary, every suggestion, the Fixes / Ideas / Facts to Check rows and Re-evaluate all fit without scrolling, keep 1094×663 and the default width. Only if they don't, resize to 1170×709 (same proportions, so the image size doesn't change) and drag the panel divider as far left as it goes (400pt). Don't re-run Evaluate to get shorter feedback.
   - Nudge the editor until `edges` passes, move the pointer out of the editor in small steps (a jump leaves the grip showing), burst, `steady`, compose. Ask Chris to flip, `open Quill.app`, capture again.
3. **Hero (Dark, then Light).** Draft A, sidebar hidden, 900×680, click the end of the first paragraph so the toolbar is active, pointer out. Capture both appearances. Compose each with `--badge-from` the Evaluate capture of the same appearance. Then delete draft A (right-click its row → Delete Draft).
4. **Media (Light, then Dark).** As in the table.
5. **Blocks (Dark, then Light).** Ask Chris to frame it from the table, arm `capture-when-ready.sh` with the blocks boxes, and tell Chris to flip once the first capture is in.
6. **Draft view (Light, then Dark).** Draft B, make the edit, pointer out, confirm the change bar, capture both. Don't save.

## Finish

1. `compose.py check` all ten (`OK` each). Composite the window shots over `#F2F1EF` and `#1E1E1E` and look at every one. Only then `cp "$S"/out/*.webp site/images/`.
2. Update the `alt` text in `site/index.html`:
   - blocks: `Quill editing an Accordion block, with the block's settings row under the toolbar and its drag grip beside it`
   - draft: `Quill showing a local draft with a change bar beside an edited paragraph and the Save to WordPress button in the toolbar`
   - media: `Quill's media library grid with an image selected and its title, alt text, caption and URL in the inspector`
3. `./Scripts/og-image/render.sh` (it embeds the light hero), and look at `site/images/og-image.png`.
4. Delete draft B, which also discards its edit. Switch the sidebar back to Posts and restore the window frame.
5. Re-run the step 3 commands and diff them against the `-before` files: both must match. If anything differs, stop and tell Chris.
6. Preview `site/index.html` through the "video" server in `.claude/launch.json` (port 8770, the project root), in light and dark (`resize_window` with `colorScheme`; the pane follows the app theme otherwise).
7. Summarize and wait. `git status` should show only the ten `.webp` files, `og-image.png` and `index.html`.
