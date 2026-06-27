#!/usr/bin/env bash
# Bundle all Tiptap dependencies into a single local IIFE file (window.TiptapBundle).
# Run this once after install, and again whenever you want to update Tiptap.
# Requires: node (brew install node)
#
# Usage: ./Scripts/bundle-tiptap.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUT="$ROOT_DIR/Sources/QuillKit/Resources/tiptap-bundle.js"
TMP_DIR="$(mktemp -d)"

echo "▶ Installing Tiptap packages..."
cd "$TMP_DIR"
cat > package.json <<'EOF'
{
  "name": "tiptap-bundler",
  "private": true,
  "type": "module",
  "dependencies": {
    "@tiptap/core": "^2",
    "@tiptap/starter-kit": "^2",
    "@tiptap/extension-underline": "^2",
    "@tiptap/extension-table": "^2",
    "@tiptap/extension-table-row": "^2",
    "@tiptap/extension-table-cell": "^2",
    "@tiptap/extension-table-header": "^2",
    "@tiptap/extension-image": "^2",
    "@tiptap/extension-link": "^2",
    "@tiptap/extension-task-list": "^2",
    "@tiptap/extension-task-item": "^2",
    "@tiptap/extension-placeholder": "^2",
    "@tiptap/extension-blockquote": "^2",
    "@tiptap/extension-paragraph": "^2",
    "@tiptap/extension-heading": "^2",
    "@tiptap/extension-bullet-list": "^2",
    "@tiptap/extension-ordered-list": "^2",
    "@tiptap/extension-list-item": "^2",
    "@tiptap/extension-code-block": "^2",
    "@tiptap/pm": "^2",
    "esbuild": "^0.25"
  }
}
EOF

npm install --silent

cat > entry.js <<'EOF'
export { Editor, Extension }           from '@tiptap/core'
export { Node as TiptapNode }          from '@tiptap/core'
export { default as StarterKit }       from '@tiptap/starter-kit'
export { default as Underline }        from '@tiptap/extension-underline'
export { default as Table }            from '@tiptap/extension-table'
export { default as TableRow }         from '@tiptap/extension-table-row'
export { default as TableCell }        from '@tiptap/extension-table-cell'
export { default as TableHeader }      from '@tiptap/extension-table-header'
export { Image as TiptapImage }        from '@tiptap/extension-image'
export { default as Blockquote }       from '@tiptap/extension-blockquote'
export { default as Paragraph }        from '@tiptap/extension-paragraph'
export { default as Heading }          from '@tiptap/extension-heading'
export { default as BulletList }       from '@tiptap/extension-bullet-list'
export { default as OrderedList }      from '@tiptap/extension-ordered-list'
export { default as ListItem }         from '@tiptap/extension-list-item'
export { default as CodeBlock }        from '@tiptap/extension-code-block'
export { default as HorizontalRule }   from '@tiptap/extension-horizontal-rule'
export { default as Link }             from '@tiptap/extension-link'
export { default as TaskList }         from '@tiptap/extension-task-list'
export { default as TaskItem }         from '@tiptap/extension-task-item'
export { default as Placeholder }      from '@tiptap/extension-placeholder'
export { Plugin, PluginKey }           from '@tiptap/pm/state'
export { DecorationSet, Decoration }   from '@tiptap/pm/view'
EOF

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
