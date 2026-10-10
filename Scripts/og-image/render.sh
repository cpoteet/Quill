#!/usr/bin/env bash
# Render the site's link-preview card (og:image) from og.html with headless Chrome.
#
# Usage: ./Scripts/og-image/render.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
OUT="$ROOT_DIR/site/images/og-image.png"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

"$CHROME" --headless --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1 --window-size=1200,630 \
  --virtual-time-budget=8000 \
  --screenshot="$OUT" "file://$SCRIPT_DIR/og.html" 2>/dev/null

echo "✓ Wrote $OUT"
