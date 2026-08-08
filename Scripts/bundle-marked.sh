#!/usr/bin/env bash
# Bundle the `marked` Markdown parser into a single local IIFE file (window.MarkedBundle).
# Used by window.insertMarkdown() in editor.html for the "Paste as Markdown" command.
#
# Deliberately separate from bundle-tiptap.sh: re-running that script npm-installs
# Tiptap fresh and can drift the editor onto a newer 2.x release, so a change that
# only needs a Markdown parser should not force an editor upgrade.
#
# Usage: ./Scripts/bundle-marked.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUT="$ROOT_DIR/Sources/QuillKit/Resources/marked-bundle.js"
TMP_DIR="$(mktemp -d)"

echo "▶ Installing marked..."
cd "$TMP_DIR"
cat > package.json <<'EOF'
{
  "name": "marked-bundler",
  "private": true,
  "type": "module",
  "dependencies": {
    "marked": "^16",
    "esbuild": "^0.25"
  }
}
EOF

npm install --silent

cat > entry.js <<'EOF'
export { marked } from 'marked'
EOF

echo "▶ Bundling..."
./node_modules/.bin/esbuild entry.js \
  --bundle \
  --format=iife \
  --global-name=MarkedBundle \
  --minify \
  --outfile="$OUT"

echo "▶ Cleaning up..."
cd /
rm -rf "$TMP_DIR"

SIZE=$(du -sh "$OUT" | cut -f1)
echo "✓ Bundle written to Sources/QuillKit/Resources/marked-bundle.js ($SIZE)"
echo "  Rebuild the app to pick up the new bundle."
