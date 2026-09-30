#!/usr/bin/env bash
# Bundle all Tiptap dependencies into a single local IIFE file (window.TiptapBundle).
# Installs from Scripts/tiptap-bundle/package-lock.json with `npm ci`, so the same
# lockfile always produces the same bundle.
# Requires: node (brew install node)
#
# Usage: ./Scripts/bundle-tiptap.sh
#
# To update Tiptap: change the versions in Scripts/tiptap-bundle/package.json, run
# `npm install --package-lock-only` in that directory, then run this script.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUT="$ROOT_DIR/Sources/QuillKit/Resources/tiptap-bundle.js"
TMP_DIR="$(mktemp -d)"

echo "▶ Installing Tiptap packages..."
cp "$SCRIPT_DIR/tiptap-bundle/package.json" "$SCRIPT_DIR/tiptap-bundle/package-lock.json" \
  "$SCRIPT_DIR/tiptap-bundle/entry.js" "$TMP_DIR/"
cd "$TMP_DIR"
npm ci --silent

echo "▶ Bundling..."
./node_modules/.bin/esbuild entry.js \
  --bundle \
  --format=iife \
  --global-name=TiptapBundle \
  --minify \
  --outfile="$OUT"

echo "▶ Cleaning up..."
cd /
rm -rf "$TMP_DIR"

SIZE=$(du -sh "$OUT" | cut -f1)
echo "✓ Bundle written to Sources/QuillKit/Resources/tiptap-bundle.js ($SIZE)"
echo "  Rebuild the app to pick up the new bundle."
