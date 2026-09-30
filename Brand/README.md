# Brand assets

Source art for the Quill logo. Nothing here is consumed by `build.sh` or the
Swift build — this is the master kept for reuse (README graphics, the
website, press, future icon work).

| File | What it is |
| --- | --- |
| `quill-logo.svg` | Vector master, 256 × 256, black feather on a transparent background |

Three copies are derived from this file. If the logo changes, regenerate all three:

- `AppIcon.icon/Assets/feather.svg`: the same paths, scaled onto a 1024 canvas and recoloured white for the app icon
- `site/images/quill-icon.svg`: the same paths and scale, black on an `#F4F4F4` square, for the website's favicon, nav and footer
- `Sources/QuillKit/QuillMark.swift`: the same paths as a SwiftUI `Shape`, drawn in the empty states
