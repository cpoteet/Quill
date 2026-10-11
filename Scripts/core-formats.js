// Core's inline formats (@wordpress/format-library), run in their own jsdom so
// tests can compare Quill's inline markup with what the block editor writes.
const { JSDOM, VirtualConsole } = require('jsdom')

let richText = null

function load() {
  if (richText) return richText
  const dom = new JSDOM('<!doctype html><body></body>', { pretendToBeVisual: true, virtualConsole: new VirtualConsole() })
  for (const name of ['window', 'document', 'Node', 'MutationObserver', 'HTMLElement', 'Element', 'getComputedStyle', 'requestAnimationFrame', 'DOMParser']) {
    try { global[name] = name === 'window' ? dom.window : dom.window[name] } catch (e) {}
  }
  richText = require('@wordpress/rich-text')
  require('@wordpress/format-library')
  return richText
}

// The inline image popover's Apply, as format-library's image/index.tsx writes it.
function applyInlineImage(html, width, alt) {
  const rt = load()
  const value = rt.create({ html })
  const start = value.replacements.findIndex(r => r && r.type === 'core/image')
  const replacements = value.replacements.slice()
  replacements[start] = {
    type: 'core/image',
    attributes: { ...value.replacements[start].attributes, style: width ? `width: ${width}px;` : '', alt: alt ?? '' },
  }
  return rt.toHTMLString({ value: { ...value, replacements } })
}

module.exports = { applyInlineImage }
