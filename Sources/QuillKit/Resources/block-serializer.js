'use strict'

// Tree → post_content. The inverse of @wordpress/block-serialization-default-parser.
// Pure string work, no DOM — shared between editor.html and the Node test harness.

function shortBlockName(name) {
  return name.startsWith('core/') ? name.slice(5) : name
}

// Byte-for-byte serializeAttributes from @wordpress/blocks.
function serializeAttributes(attrs) {
  return JSON.stringify(attrs)
    .replaceAll("\\\\", "\\u005c")
    .replaceAll("--", "\\u002d\\u002d")
    .replaceAll("<", "\\u003c")
    .replaceAll(">", "\\u003e")
    .replaceAll("&", "\\u0026")
    .replaceAll('\\"', "\\u0022")
}

function serializeBlock(block) {
  const { blockName, attrs, innerBlocks, innerContent } = block
  if (!blockName) return innerContent.join('')

  const name = shortBlockName(blockName)
  const attrsStr = attrs && Object.keys(attrs).length ? ' ' + serializeAttributes(attrs) : ''

  let childIndex = 0
  const inner = innerContent
    .map(chunk => (chunk === null ? serializeBlock(innerBlocks[childIndex++]) : chunk))
    .join('')

  if (inner === '') return `<!-- wp:${name}${attrsStr} /-->`
  return `<!-- wp:${name}${attrsStr} -->${inner}<!-- /wp:${name} -->`
}

function serializeBlocks(blocks) {
  return blocks.map(serializeBlock).join('')
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { serializeBlocks, serializeBlock, shortBlockName, serializeAttributes }
}
