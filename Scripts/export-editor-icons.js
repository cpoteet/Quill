#!/usr/bin/env node
// Rebuilds site/images/editor/*.svg, the formatting-toolbar icons the user
// guide shows, copied straight out of the editor's own markup so the two can't
// drift apart.
//
//   node Scripts/export-editor-icons.js
//
// The editor draws its toolbar icons as line art: `#toolbar svg` in
// editor.html sets stroke: currentColor, stroke-width 1.9, round caps and
// joins, and fill: none. Each exported file carries those as attributes, in
// black, because the guide uses it as a CSS mask filled with the text colour.
// The buttons drawn as text (B, I, S, A, {}, *, ABC, </>, P) have no SVG; the
// guide draws those with .docs-glyph spans in site/style.css instead.
//
// EXPECTED names every icon the guide uses. A button that loses its SVG or
// changes its data-cmd/id makes this script fail instead of quietly dropping
// an icon from the guide.

'use strict'
const fs = require('fs')
const path = require('path')

const root = path.resolve(__dirname, '..')
const editorPath = path.join(root, 'Sources/QuillKit/Resources/editor.html')
const outDir = path.join(root, 'site/images/editor')

// data-cmd or id of the button → file name in site/images/editor/
const EXPECTED = {
  undo: 'undo',
  redo: 'redo',
  'heading-button': 'menu-chevron',
  link: 'link',
  bulletList: 'bullet-list',
  orderedList: 'number-list',
  blockquote: 'blockquote',
  image: 'image',
  gallery: 'gallery',
  insertTable: 'table',
  'embed-button': 'embed',
  'btn-evaluate': 'evaluate',
  'btn-generate': 'generate',
  alignLeft: 'align-left',
  alignCenter: 'align-center',
  alignRight: 'align-right',
}

function fail(message) {
  console.error(`export-editor-icons: ${message}`)
  process.exit(1)
}

const html = fs.readFileSync(editorPath, 'utf8')
const start = html.indexOf('<div id="toolbar">')
const end = html.indexOf('<div id="heading-menu"')
if (start < 0 || end < start) fail('could not find the toolbar markup in editor.html')
const toolbar = html.slice(start, end)

const found = {}
for (const [, attrs, inner] of toolbar.matchAll(/<button\b([^>]*)>([\s\S]*?)<\/button>/g)) {
  const key = (attrs.match(/\bdata-cmd="([^"]+)"/) || attrs.match(/\bid="([^"]+)"/) || [])[1]
  const svg = inner.match(/<svg\b([^>]*)>([\s\S]*?)<\/svg>/)
  if (key && svg && key in EXPECTED) found[key] = svg
}

const missing = Object.keys(EXPECTED).filter(key => !found[key])
if (missing.length) fail(`no SVG icon for ${missing.join(', ')} in editor.html`)

// Every file is built before the folder is touched, so a failure leaves the old icons in place.
const files = Object.entries(EXPECTED).map(([key, name]) => {
  const [, attrs, inner] = found[key]
  const viewBox = (attrs.match(/\bviewBox="([^"]+)"/) || [])[1]
  if (!viewBox) fail(`${key}'s icon has no viewBox`)
  // The menu chevrons are drawn thinner, by `#heading-button svg`.
  const strokeWidth = key === 'heading-button' ? '2' : '1.9'
  const body = inner.trim().replace(/fill="currentColor"/g, 'fill="black"')
  return [`${name}.svg`, `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox}" width="16" height="16" fill="none" stroke="black" stroke-width="${strokeWidth}" stroke-linecap="round" stroke-linejoin="round">
<!-- Quill's ${key} toolbar icon. Generated from editor.html by Scripts/export-editor-icons.js; do not edit by hand. -->
${body}
</svg>
`]
})

fs.rmSync(outDir, { recursive: true, force: true })
fs.mkdirSync(outDir, { recursive: true })
for (const [file, out] of files) fs.writeFileSync(path.join(outDir, file), out)
console.log(`wrote ${Object.keys(EXPECTED).length} icons to ${outDir}`)
