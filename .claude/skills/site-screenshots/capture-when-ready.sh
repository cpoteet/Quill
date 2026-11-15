#!/bin/bash
# Captures one shot in both appearances from a single framing. Run it in the background, then ask
# Chris to frame the shot in Quill and hold still; then to flip Light/Dark and hold still again.
#
#   bash capture-when-ready.sh <scratch dir> <shot> [edge boxes...]
#
# 1. Waits for Quill to come to the front, then for its window to stop changing (apart from the
#    caret) for about 3 seconds, and captures a 16-frame burst in the current appearance.
# 2. Waits for the system appearance to flip, then for the window to settle again, and captures the
#    other appearance the same way.
# Each capture keeps the caret-free frame, checks the edges and composes the image (the hero is
# composed afterwards with --badge-from). A FAIL line says what to re-frame.
set -u
S="$1"; SHOT="$2"; shift 2
K="$(cd "$(dirname "$0")" && pwd)"
frontmost() { osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true'; }
appearance() { [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = Dark ] && echo dark || echo light; }
ID=$("$S/winid" Quill | head -1 | cut -d' ' -f1)

wait_until_settled() {   # Quill in front and the window unchanged (but for a caret) for ~3 seconds
  local still=0
  for _ in $(seq 1 400); do
    screencapture -l"$ID" -x "$S/watch-a.png"; sleep 1.5; screencapture -l"$ID" -x "$S/watch-b.png"
    if [ "$(frontmost)" = "Quill" ] && python3 "$K/compose.py" stable "$S/watch-a.png" "$S/watch-b.png"; then
      still=$((still + 1)); [ $still -ge 2 ] && return 0
    else
      still=0
    fi
  done
  echo "Quill never settled; nothing captured."; exit 1
}

capture() {   # $1 = light|dark
  rm -f "$S"/burst-*.png
  for i in $(seq 1 16); do screencapture -l"$ID" -x "$S/burst-$i.png"; done
  local raw="$S/raw/$SHOT-$1.png"
  python3 "$K/compose.py" steady "$raw" "$S"/burst-*.png || return 1
  [ $# -gt 0 ] && [ ${#EDGES[@]} -gt 0 ] && python3 "$K/compose.py" edges "$raw" "${EDGES[@]}"
  [ "$SHOT" = hero-editor ] && return 0
  python3 "$K/compose.py" "$SHOT" "$raw" "$S/out/$SHOT$([ "$1" = dark ] && echo -dark).webp" 2>&1 | grep -v iCCP
}
EDGES=("$@")

# Fire on Quill *coming* to the front, so Chris has time to switch to it and frame.
while [ "$(frontmost)" = "Quill" ]; do sleep 1; done
for _ in $(seq 1 600); do [ "$(frontmost)" = "Quill" ] && break; sleep 1; done
wait_until_settled
FIRST=$(appearance)
echo "== $FIRST"; capture "$FIRST"
echo "Captured $FIRST. Waiting for the appearance to flip…"
for _ in $(seq 1 600); do [ "$(appearance)" != "$FIRST" ] && break; sleep 1; done
[ "$(appearance)" != "$FIRST" ] || { echo "The appearance never flipped."; exit 1; }
sleep 2
wait_until_settled
SECOND=$(appearance)
echo "== $SECOND"; capture "$SECOND"
