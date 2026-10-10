# Quill intro video — design

## Purpose

A 60-second silent MP4 that introduces Quill to people who reached the GitHub repo or a release page. It plays inline from a GitHub upload (no autoplay, 10 MB limit), so everything is said in on-screen type. Viewers are already curious, so it can show several features.

## Story

One post goes from a blank page to published. Each feature appears as the next step in writing it.

| Time | Beat | On screen | Headline / subline |
|---|---|---|---|
| 0:00–0:05 | Open | Amber caret on the stage types "Quill" in Plex Serif; the app icon settles beside it. | **Quill** / A native Mac app for your WordPress site. |
| 0:05–0:16 | Write | The window grows out of the icon. A title is typed; `## ` becomes a heading through the real Markdown input rule; a paragraph follows; an Accordion block is inserted and opens. Keycap overlay shows `##`. | **A full editor. No browser.** / Markdown shortcuts, Columns, Tabs and Accordions, saved in WordPress's block format. |
| 0:16–0:25 | Media | A photo is dragged in; an amber upload ring fills; it settles as a captioned figure. Cut to the Media tab grid. | **Drop in a photo. It uploads.** / Browse and filter your site's whole media library. |
| 0:25–0:36 | Claude | A paragraph is selected (amber selection), **Shorter** is picked, the text rewrites in place. The Evaluate panel slides in with two or three findings. | **Review it with Claude.** / Optional, using your own Anthropic API key. |
| 0:36–0:46 | Post settings | The inspector opens; two categories are ticked; a typed tag becomes a token; a featured image is picked; the Schedule toggle is flicked. | **Categories, tags, featured image.** / Set everything WordPress needs before you publish. |
| 0:46–0:54 | Offline → publish | Autosave tick while offline; keycap `⇧⌘P`; status becomes Published with the green check. | **Write offline. Publish when you're ready.** / Drafts stay on your Mac until you send them. |
| 0:54–1:00 | Close | The window shrinks back into the icon. | **Quill** / Free · macOS 27 · quill.siolon.com |

Each beat ends with a ~1.5 s hold so the caption can be read.

## Look

- **Stage:** charcoal `#161616`; the light-mode window sits on it with a soft, wide shadow. Reads the same in GitHub's light and dark themes.
- **Frame:** 1920×1080. Caption column on the left (~30%); window on the right, allowed to bleed off the edge during push-ins. Captions never cover UI.
- **Type:** headline IBM Plex Serif 500, ~64 px, off-white; subline IBM Plex Sans 400, ~26 px, 60% opacity. No italics.
- **Colour:** amber only where the app uses it (caret, selection, checkboxes, upload ring, publish button), using the values in `editor.html` and `Assets.xcassets`. Captions never use amber.
- **Content:** a fictional post about a hiking trip, one landscape photo, five or six plausible sidebar titles of the same kind. No real post titles or personal data.

## Motion

- UI panels and sheets: damped ease with no overshoot, matching macOS. The only overshoot is the icon settling at open and close.
- Camera: a virtual camera pushes the window to 1.3–1.5× on the region of action and pulls back to the full window between beats.
- Captions: headline lines rise ~16 px and fade in, staggered; subline follows 200 ms later; the outgoing caption fades as the beat changes.
- Pointer: recreated macOS arrow on eased curves; buttons show their pressed state. No click ripples.
- Keycaps: small overlay near the window's bottom edge for `##` and `⇧⌘P`.

## Build

```
video/
  index.html        stage: caption column, window chrome, editor iframe, pointer, keycaps
  stage.css
  timeline.js       beat/keyframe data and seek(t); every visual state is a function of t
  editor-driver.js  drives the real editor.html in the iframe (content, selection, input rules)
  bridge-stub.js    stands in for window.webkit.messageHandlers inside the iframe
  preview.html      play/pause + scrubber for review in a browser
  preview.js
  render.swift      WKWebView → seek per frame → snapshot → AVAssetWriter (H.264)
  fonts/            IBM Plex Serif + Sans, OFL
  assets/           photo, icon (from Brand/)
  out/              rendered MP4, gitignored
```

- **Real editor:** `Sources/QuillKit/Resources/editor.html` loaded unmodified in an iframe. Chrome around it (sidebar, toolbar, inspector, Media grid, Evaluate panel) is rebuilt in HTML/CSS from the screenshots in `site/images/`.
- **Determinism:** no CSS animations or timers drive visuals. `seek(t)` sets every property; the editor driver rebuilds editor state for `t` (typed prefix, selection, inserted blocks) so frames can be rendered in any order.
- **Render:** a Swift script loads `index.html` in an offscreen WKWebView at 1920×1080, calls `seek(t)` for each of 3,600 frames at 60 fps, snapshots, and appends to an AVAssetWriter H.264 stream. WebKit is the engine the app runs on, so the editor renders as it does in Quill. No ffmpeg or Chromium needed.
- **Output:** `video/out/quill-intro.mp4`, under 10 MB. If 60 fps can't reach that at acceptable quality, drop to 30 fps.

## Verification

- Review timing and copy in `preview.html` in the browser pane before the first full render.
- Render stills at each beat's midpoint and hold to check framing and legibility.
- After the full render: check the duration (60 s ± 0.5), file size (< 10 MB), and watch it end to end.

## Out of scope

Audio, dark-mode footage, localisation, a GIF version.
