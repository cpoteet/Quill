#!/usr/bin/env bash
# Bundle the `marked` Markdown parser into a single local IIFE file (window.MarkedBundle).
# Used by window.insertMarkdown() in editor.html for the "Paste as Markdown" command.
# Installs from Scripts/marked-bundle/package-lock.json with `npm ci`, so the same
# lockfile always produces the same bundle.
#
# Separate from bundle-tiptap.sh so that updating the Markdown parser never touches
# the editor bundle.
#
# Usage: ./Scripts/bundle-marked.sh
#
# To update marked: change the version in Scripts/marked-bundle/package.json, run
# `npm install --package-lock-only` in that directory, then run this script.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUT="$ROOT_DIR/Sources/QuillKit/Resources/marked-bundle.js"
TMP_DIR="$(mktemp -d)"

echo "▶ Installing marked..."
cp "$SCRIPT_DIR/marked-bundle/package.json" "$SCRIPT_DIR/marked-bundle/package-lock.json" \
  "$SCRIPT_DIR/marked-bundle/entry.js" "$TMP_DIR/"
cd "$TMP_DIR"
npm ci --silent

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
