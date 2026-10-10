# Quill intro video

A 60-second intro for the GitHub README and release pages. The stage is an HTML page that runs Quill's real `editor.html` inside a rebuilt window. Everything on screen is a function of one time value, `window.seek(t)`, so any frame can be rendered on its own. Design: `docs/superpowers/specs/2026-10-09-intro-video-design.md`.

## Files

- `index.html`, `stage.css`: the stage, captions and rebuilt window chrome
- `timeline.js`: beats, camera, pointer path, keycaps, toasts and audio cues
- `editor-driver.js`: drives the real editor in its iframe (document, caret, selection overlay, menus)
- `motion.js`: easing, keyframes and typing rhythm
- `photos.js`: generated landscape images for the post and the media library
- `preview.html`: scrubber for reviewing in a browser (serve the repo root; the `video` entry in `.claude/launch.json` does this)
- `render/`: Swift renderer (WKWebView snapshots → AVAssetWriter, synthesized UI sounds, music mix, mux)

## Render

```bash
swiftc -O render/*.swift -o out/render
./out/render .. out/quill-intro-silent.mp4
./out/render .. out/quill-intro.mp4 --mux out/quill-intro-silent.mp4 --music assets/<track>
```

- `--stills 9.5,20 --stills-dir out/stills`: PNG frames for review.
- `--music-gain` (default 0.55) and `--effects-gain` (default 2) balance the music against the UI sounds.

The video render takes about 15 minutes; re-muxing audio takes seconds. Output goes to `out/`, which is gitignored.

The music track, `assets/audio.mp3`, is licensed and gitignored so it is never published with the repo. Keep a local copy; the final mux needs it.
