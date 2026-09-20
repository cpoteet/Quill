# Brand assets

Source art for the Quill logo. Nothing here is consumed by `build.sh` or the
Swift build — these are the masters kept for reuse (README graphics, the
website, press, future icon work).

| File | What it is |
| --- | --- |
| `quill-logo.svg` | Vector master, 2964 × 2964, feather on an off-white background |
| `quill-logo.eps` | Same artwork as EPS (Cairo-generated), for print and Illustrator |
| `quill-logo-1920.jpg` | Flattened 1920 × 1920 raster, for anywhere vector isn't accepted |

The feather path in `AppIcon.icon/Assets/feather.svg` is this same outline,
scaled and recoloured white for the app icon. If the logo ever changes, that
file has to be regenerated from the new master.

Note: the SVG and EPS both include the off-white background as a drawn
rectangle, so neither is transparent. Delete the two background paths if you
need the mark on its own.
