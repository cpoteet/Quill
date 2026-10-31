// Moving top-level blocks: docs/superpowers/specs/2026-10-31-drag-to-reorder-blocks-design.md.

function movableCount(doc) {
  const last = doc.lastChild
  return last && last.type.name === 'footnotesList' ? doc.childCount - 1 : doc.childCount
}

function topLevelIndexAt(doc, pos) {
  if (doc.childCount === 0) return -1
  const index = Math.min(doc.resolve(Math.max(0, Math.min(pos, doc.content.size))).index(0), doc.childCount - 1)
  return index < movableCount(doc) ? index : -1
}

function topLevelPos(doc, index) {
  let pos = 0
  for (let i = 0; i < index; i++) pos += doc.child(i).nodeSize
  return pos
}

function sectionEnd(doc, index) {
  const node = doc.child(index)
  const count = movableCount(doc)
  if (node.type.name !== 'heading') return index + 1
  for (let i = index + 1; i < count; i++) {
    const next = doc.child(i)
    if (next.type.name === 'heading' && next.attrs.level <= node.attrs.level) return i
  }
  return count
}

function isNoOpMove(from, to, gap) {
  return gap >= from && gap <= to
}

function adjacentGap(doc, index, direction) {
  if (direction === 'up') return index === 0 ? null : index - 1
  return index + 1 >= movableCount(doc) ? null : index + 2
}

function generatedTrailingIndex(doc, trailingAfter) {
  const count = movableCount(doc)
  if (count < 2) return -1
  const last = doc.child(count - 1)
  if (last.type.name !== 'paragraph' || last.content.size !== 0) return -1
  return trailingAfter.has(doc.child(count - 2).type.name) ? count - 1 : -1
}

// Original child indexes in the order a move leaves them.
function _orderAfterMove(childCount, from, to, gap) {
  const all = Array.from({ length: childCount }, (_, i) => i)
  const moved = all.slice(from, to)
  const rest = all.filter(i => i < from || i >= to)
  const at = gap < from ? gap : gap - (to - from)
  return [...rest.slice(0, at), ...moved, ...rest.slice(at)]
}

function moveTopLevelBlocks(state, from, to, gap, trailingAfter) {
  const doc = state.doc
  const generated = generatedTrailingIndex(doc, trailingAfter)
  if (isNoOpMove(from, to, gap)) return null
  if (generated === to && gap === to + 1) return null

  const startPos = topLevelPos(doc, from)
  const endPos = topLevelPos(doc, to)
  const moved = doc.slice(startPos, endPos).content
  const tr = state.tr
  tr.delete(startPos, endPos)
  tr.insert(tr.mapping.map(topLevelPos(doc, gap)), moved)

  const order = _orderAfterMove(doc.childCount, from, to, gap)
  const lastMovable = movableCount(doc) - 1
  const stillTrailing = generated !== -1 && order.indexOf(generated) === lastMovable &&
    trailingAfter.has(doc.child(order[lastMovable - 1]).type.name)
  if (generated !== -1 && !stillTrailing) {
    const index = order.indexOf(generated)
    const pos = topLevelPos(tr.doc, index)
    tr.delete(pos, pos + tr.doc.child(index).nodeSize)
    order.splice(index, 1)
  }
  tr.setMeta('closeHistory$', true)
  return { tr, start: topLevelPos(tr.doc, order.indexOf(from)) }
}

function firstTextblockPos(doc, start) {
  const node = doc.nodeAt(start)
  if (!node) return null
  if (node.isTextblock) return start + 1
  let found = null
  node.descendants((child, pos) => {
    if (found !== null) return false
    if (child.isTextblock) { found = start + 1 + pos + 1; return false }
    return true
  })
  return found
}

function _textMarkers() { return {
  paragraph: ['¶', 'Paragraph'],
  bulletList: ['•', 'Bulleted list'],
  orderedList: ['1.', 'Numbered list'],
  pullquote: ['”', 'Pullquote'],
  codeBlock: ['{}', 'Code'],
  preformatted: ['pre', 'Preformatted'],
  horizontalRule: ['—', 'Separator'],
} }

function _glyphMarkers() { return {
  blockquote: ['quote', 'Quote'],
  image: ['image', 'Image'],
  galleryBlock: ['gallery', 'Gallery'],
  embedBlock: ['embed', 'Embed'],
  table: ['table', 'Table'],
  columnsBlock: ['columns', 'Columns'],
  groupBlock: ['group', 'Group'],
  buttonsBlock: ['buttons', 'Buttons'],
  detailsBlock: ['chevron', 'Details'],
  accordionBlock: ['accordion', 'Accordion'],
  tabsBlock: ['tabs', 'Tabs'],
} }

function _passthroughMarker(node) {
  const source = node.attrs.unsupportedSource
  const blocks = source ? parseBlocks(source).filter(b => b.blockName || b.innerHTML.trim()) : []
  const name = blocks.length === 1 ? blocks[0].blockName : null
  if (name === 'core/block') return { kind: 'glyph', value: 'synced', label: 'Synced pattern' }
  if (name === 'core/html') return { kind: 'glyph', value: 'html', label: 'Custom HTML' }
  return { kind: 'glyph', value: 'html', label: 'Unsupported block' }
}

function blockMarker(node) {
  const name = node.type.name
  if (name === 'heading') return { kind: 'text', value: 'h' + node.attrs.level, label: 'Heading ' + node.attrs.level }
  if (name === 'gutenbergPassthrough') return _passthroughMarker(node)
  const text = _textMarkers()[name]
  if (text) return { kind: 'text', value: text[0], label: text[1] }
  const glyph = _glyphMarkers()[name]
  if (glyph) return { kind: 'glyph', value: glyph[0], label: glyph[1] }
  return { kind: 'glyph', value: 'html', label: 'Unsupported block' }
}
