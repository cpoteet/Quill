#!/usr/bin/env bash
# Bundle WordPress's standalone block parser into a local IIFE (window.BlockParser).
# Separate from bundle-tiptap.sh so a parser bump never drifts the editor's Tiptap version.
#
# Usage: ./Scripts/bundle-block-parser.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUT="$ROOT_DIR/Sources/QuillKit/Resources/block-parser-bundle.js"
TMP_DIR="$(mktemp -d)"

echo "▶ Installing @wordpress/block-serialization-default-parser..."
cd "$TMP_DIR"
cat > package.json <<'EOF'
{
  "name": "block-parser-bundler",
  "private": true,
  "type": "module",
  "dependencies": {
    "@wordpress/block-serialization-default-parser": "^5",
    "esbuild": "^0.25"
  }
}
EOF

npm install --silent

cat > entry.js <<'EOF'
export { parse } from '@wordpress/block-serialization-default-parser'
EOF

echo "▶ Bundling..."
./node_modules/.bin/esbuild entry.js \
  --bundle \
  --format=iife \
  --global-name=BlockParser \
  --minify \
  --outfile="$OUT"

echo "▶ Cleaning up..."
cd /
rm -rf "$TMP_DIR"

SIZE=$(du -sh "$OUT" | cut -f1)
echo "✓ Bundle written to Sources/QuillKit/Resources/block-parser-bundle.js ($SIZE)"
echo "  Rebuild the app to pick up the new bundle."
