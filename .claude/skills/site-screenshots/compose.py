#!/usr/bin/env python3
"""Turn a native `screencapture -l` PNG of Quill's window into a site image, and check it.

    python3 compose.py <shot> <capture.png> <out.webp>
    python3 compose.py hero-editor <capture.png> <out.webp> --badge-from <published-capture.png> [--hero-offset X,Y]
    python3 compose.py check <out.webp> <shot>
    python3 compose.py steady <out.png> <frame1.png> <frame2.png> ...
    python3 compose.py edges <capture.png> <name>:<x0>,<y0>,<x1>,<y1>[,<band>] ...

steady: from a burst of captures of the same state, writes the frame in which the blinking text
caret is off. It refuses if something bigger than a caret changed between frames (a spinner, a
toast), and warns if nothing blinked at all.

edges: fails if content crosses the top or bottom edge of any named box (window points, from the
window's top-left corner), so no line of text, row or thumbnail is cut off there. <band> is how many
points inside each edge must be clear (default 1): use about 12 for a list, so a whole row shows,
not just the gap between two lines of one row.

<shot> is one of the names in SHOTS. Needs Pillow (in the user site-packages, so do not run
python3 with -I) and cwebp (Homebrew `webp`).

Window shots: the capture is scaled so the window is exactly the width style.css expects, then
placed on a transparent canvas of the size index.html declares, with the window's top-left
corner where the old image had it. The native shadow comes along; whatever falls outside the
canvas is clipped and reported.

Hero: an opaque crop at native 2x, 1720x1124, starting --hero-offset native pixels right of and
below the window's top-left corner (just inside the left edge, just below the toolbar buttons).
The hero is a local draft, which shows the purple local-draft badge; --badge-from swaps in the
green Published check from a capture of a published post taken with the sidebar hidden in the
same appearance (the evaluate-view capture). The status icon sits at the same place from the
window's top-left corner whatever the window's size, so the same box is copied across.

Every capture must be of the active window: an inactive one has grey traffic lights, a grey
sidebar selection and a smaller shadow. compose.py refuses one whose close button isn't red.
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image

# canvas size, window rect (left, top, width, height) inside the canvas, and the window size in
# points that produces that rect from a 2x capture (shadow 112/76/112/148 native px). Quill's
# minimum window is 900x652 points (ContentView), so no shot can be shorter than 652.
SHOTS = {
    "blocks-view":   {"canvas": (2200, 1294), "window": (93, 63, 2014, 1108), "points": (1290, 710)},
    # Evaluate: 1094x663 with the panel at its default width; 1170x709 (same proportions) only when
    # that run's feedback doesn't fit and the panel has to be widened to 400pt.
    "evaluate-view": {"canvas": (1400, 899),  "window": (65, 44, 1270, 770),  "points": [(1094, 663), (1170, 709)]},
    "draft-view":    {"canvas": (1400, 815),  "window": (65, 40, 1270, 698),  "points": (1186, 652)},
    "media-view":    {"canvas": (1400, 815),  "window": (65, 40, 1270, 698),  "points": (1186, 652)},
    "hero-editor":   {"canvas": (1720, 1124), "hero": True,                   "points": (900, 680)},
}
HERO_OFFSET_DEFAULT = (4, 100)  # native px from the window's top-left corner to the crop's
BADGE_BOX = (22, 26, 78, 80)    # the status icon, in hero-crop px; the title text starts at ~88
CLOSE_BUTTON = (52, 52)         # native px from the window's top-left corner
TOLERANCE = 2                   # px, edge positions in the check


def window_bbox(img):
    """The fully opaque window inside a capture or composed image."""
    bbox = img.getchannel("A").point(lambda v: 255 if v > 250 else 0).getbbox()
    if not bbox:
        sys.exit("No opaque window found: is this a screencapture -l PNG with its shadow?")
    return bbox


def open_capture(path):
    """A capture and its window box, refusing an inactive window."""
    img = Image.open(path).convert("RGBA")
    x0, y0, x1, y1 = window_bbox(img)
    r, g, _, _ = img.getpixel((x0 + CLOSE_BUTTON[0], y0 + CLOSE_BUTTON[1]))
    if r - g < 60:
        sys.exit(f"{path}: the window was inactive (grey close button). Click Quill's empty top bar "
                 "to activate it, then capture again.")
    return img, (x0, y0, x1, y1)


def encode(img, out, has_alpha):
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        img.save(tmp.name)
    args = ["cwebp", "-quiet", "-m", "6", "-q", "90"]
    if has_alpha:
        args += ["-alpha_q", "100"]
    subprocess.run(args + [tmp.name, "-o", out], check=True)
    os.unlink(tmp.name)


def compose_window(spec, capture, out):
    cw, ch = spec["canvas"]
    left, top, ww, wh = spec["window"]
    img, (x0, y0, x1, y1) = open_capture(capture)
    sizes = spec["points"] if isinstance(spec["points"], list) else [spec["points"]]
    if not any(abs((x1 - x0) - 2 * pw) <= 4 and abs((y1 - y0) - 2 * ph) <= 4 for pw, ph in sizes):
        want = " or ".join(f"{pw}x{ph}" for pw, ph in sizes)
        sys.exit(f"Window is {(x1 - x0) / 2:g}x{(y1 - y0) / 2:g} points, need {want}: resize it and capture again.")
    scale = ww / (x1 - x0)
    img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    sx0, sy0 = round(x0 * scale), round(y0 * scale)
    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    canvas.paste(img, (left - sx0, top - sy0))
    clipped = [name for name, gone in (
        ("left", sx0 - left), ("top", sy0 - top),
        ("right", (img.width - sx0) - (cw - left)), ("bottom", (img.height - sy0) - (ch - top)),
    ) if gone > 0]
    encode(canvas, out, has_alpha=True)
    print(f"wrote {out} {cw}x{ch}; shadow clipped at: {', '.join(clipped) or 'none'}")


def ring_difference(a, b):
    """Mean per-channel difference along the edge pixels of two same-size patches."""
    w, h = a.size
    edge = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    return sum(abs(p - q) for xy in edge for p, q in zip(a.getpixel(xy)[:3], b.getpixel(xy)[:3])) / (3 * len(edge))


def is_green(patch):
    return sum(1 for r, g, b in patch.getdata() if g > r + 40 and g > b + 20) > 200


def compose_hero(spec, capture, out, offset, badge_from):
    cw, ch = spec["canvas"]
    img, (x0, y0, x1, y1) = open_capture(capture)
    dx, dy = offset
    box = (x0 + dx, y0 + dy, x0 + dx + cw, y0 + dy + ch)
    if box[2] > x1 or box[3] > y1:
        sys.exit(f"Crop {box} runs past the window {(x0, y0, x1, y1)}: make the window bigger.")
    hero = img.crop(box).convert("RGB")
    if badge_from:
        src, (sx0, sy0, _, _) = open_capture(badge_from)
        bx0, by0, bx1, by1 = BADGE_BOX
        badge = src.crop((sx0 + dx + bx0, sy0 + dy + by0, sx0 + dx + bx1, sy0 + dy + by1)).convert("RGB")
        if not is_green(badge):
            sys.exit(f"{badge_from}: no green Published check in the badge box. Is it a published post "
                     "with the sidebar hidden?")
        diff = ring_difference(badge, hero.crop(BADGE_BOX))
        if diff > 3:
            sys.exit(f"The pixels around the badge differ by {diff:.1f}: the two captures don't line up "
                     "(sidebar shown? different appearance?).")
        hero.paste(badge, BADGE_BOX[:2])
    elif not is_green(hero.crop(BADGE_BOX)):
        print("warning: the hero shows no green Published check; pass --badge-from")
    encode(hero, out, has_alpha=False)
    print(f"wrote {out} {cw}x{ch} from window crop {box}{', badge from ' + badge_from if badge_from else ''}")


def steady(out, frames):
    """Write the frame in which the caret is off."""
    from PIL import ImageChops
    originals = [Image.open(f) for f in frames]  # saved untouched, so the shadow's alpha survives
    images = [img.convert("RGB") for img in originals]
    changed = Image.new("L", images[0].size, 0)
    for img in images[1:]:
        changed = ImageChops.lighter(changed, ImageChops.difference(images[0], img).convert("L"))
    box = changed.point(lambda v: 255 if v > 40 else 0).getbbox()
    if not box:
        originals[0].save(out)
        print(f"warning: nothing blinked across {len(frames)} frames; check by eye that no caret shows. Wrote {out}")
        return
    w, h = box[2] - box[0], box[3] - box[1]
    if w > 16 or h > 120:
        sys.exit(f"Something bigger than a caret changed between frames ({w}x{h}px at {box[:2]}): "
                 "wait for it to settle and capture again.")
    # The caret is amber (the accent) and fades rather than switching off, so score each pixel by
    # how amber it is (red minus blue). Text is black, white or grey, and amber link text doesn't
    # change between frames, so it adds the same to every frame.
    crops = [[max(0, r - b) for r, _, b in img.crop(box).getdata()] for img in images]
    least = [min(values) for values in zip(*crops)]
    best = min(range(len(crops)), key=lambda i: sum(crops[i]))
    residue = sum(a - m for a, m in zip(crops[best], least))
    if residue > 200:
        sys.exit(f"No frame catches the caret fully faded out (residue {residue}): take a longer burst "
                 "(more frames, shorter gaps) and run steady again.")
    originals[best].save(out)
    print(f"wrote {out}: frame {best + 1} of {len(frames)}, caret fully off at {box[:2]} (residue {residue})")


def edges(capture, boxes):
    """Fail if content crosses the top or bottom edge of any named box."""
    img = Image.open(capture).convert("RGB")
    x0, y0, _, _ = window_bbox(Image.open(capture).convert("RGBA"))
    problems = []
    for spec in boxes:
        name, coords = spec.split(":")
        values = [int(v) for v in coords.split(",")]
        bx0, by0, bx1, by1 = (v * 2 for v in values[:4])
        band = values[4] * 2 if len(values) > 4 else 2  # px that must be clear inside each edge
        for edge, ys in (("top", range(y0 + by0, y0 + by0 + band)),
                         ("bottom", range(y0 + by1 - band, y0 + by1))):
            worst = 0
            for y in ys:
                row = [img.getpixel((x, y)) for x in range(x0 + bx0, x0 + bx1)]
                counts = {}
                for px in row:
                    key = tuple(v // 8 for v in px)
                    counts[key] = counts.get(key, 0) + 1
                mode = [v * 8 + 4 for v in max(counts, key=counts.get)]
                worst = max(worst, sum(1 for px in row if sum(abs(p - q) for p, q in zip(px, mode)) > 30))
            if worst > 2:
                problems.append(f"{name} {edge}: {worst} px of content within {band // 2}pt of the edge")
    print("edges OK" if not problems else "edges FAIL: " + "; ".join(problems))
    return not problems


def check(out, name):
    spec = SHOTS[name]
    img = Image.open(out).convert("RGBA")
    problems = []
    if img.size != spec["canvas"]:
        problems.append(f"size {img.size}, want {spec['canvas']}")
    if spec.get("hero"):
        if img.getchannel("A").getextrema()[0] < 255:
            problems.append("hero has transparent pixels")
    else:
        if img.getpixel((0, 0))[3] != 0:
            problems.append("corner is not transparent")
        left, top, ww, wh = spec["window"]
        want = (left, top, left + ww, top + wh)
        got = window_bbox(img)
        if any(abs(g - w) > TOLERANCE for g, w in zip(got, want)):
            problems.append(f"window at {got}, want {want}")
    print(f"{out}: {'OK' if not problems else 'FAIL ' + '; '.join(problems)}")
    return not problems


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "check":
        sys.exit(0 if check(args[1], args[2]) else 1)
    if args and args[0] == "stable":  # exit 0 if two captures differ by no more than a caret
        from PIL import ImageChops
        a, b = (Image.open(p).convert("RGB") for p in args[1:3])
        box = a.size == b.size and ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > 40 else 0).getbbox()
        sys.exit(0 if a.size == b.size and (not box or (box[2] - box[0] <= 16 and box[3] - box[1] <= 120)) else 1)
    if args and args[0] == "steady":
        steady(args[1], args[2:])
        sys.exit(0)
    if args and args[0] == "edges":
        sys.exit(0 if edges(args[1], args[2:]) else 1)
    if len(args) < 3 or args[0] not in SHOTS:
        sys.exit(__doc__)
    name, capture, out = args[:3]
    offset = (tuple(int(v) for v in args[args.index("--hero-offset") + 1].split(","))
              if "--hero-offset" in args else HERO_OFFSET_DEFAULT)
    badge_from = args[args.index("--badge-from") + 1] if "--badge-from" in args else None
    if SHOTS[name].get("hero"):
        compose_hero(SHOTS[name], capture, out, offset, badge_from)
    else:
        compose_window(SHOTS[name], capture, out)
    check(out, name)
