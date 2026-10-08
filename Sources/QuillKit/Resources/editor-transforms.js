'use strict'

// Pure DOM transform functions shared between editor.html (browser) and
// the Node/jsdom test harness (Scripts/test-editor.js).
//
// toWordPressHTML accepts an optional `doc` argument so tests can supply a
// jsdom document. In the browser the global `document` is used by default.

// block-descriptors.js is a plain global script in the browser and a CommonJS
// module under the Node test harness, so it is resolved both ways.
const blockDescriptorRegistry = (typeof module !== 'undefined' && module.exports)
  ? require('./block-descriptors.js')
  : globalThis

const NODE_FOR_TAG = {
  P: 'paragraph', H1: 'heading', H2: 'heading', H3: 'heading',
  H4: 'heading', H5: 'heading', H6: 'heading',
  UL: 'bulletList', OL: 'orderedList', LI: 'listItem',
  BLOCKQUOTE: 'blockquote', PRE: 'codeBlock', HR: 'horizontalRule',
}

// Container blocks are identified by class, not tag name.
const NODE_FOR_BLOCK_CLASS = [
  ['wp-block-table', 'table'],
  ['wp-block-columns', 'columnsBlock'],
  ['wp-block-column', 'columnBlock'],
  ['wp-block-buttons', 'buttonsBlock'],
  ['wp-block-button', 'buttonBlock'],
  ['wp-block-accordion-heading', 'accordionHeading'],
  ['wp-block-accordion-panel', 'accordionPanel'],
  ['wp-block-accordion-item', 'accordionItem'],
  ['wp-block-accordion', 'accordionBlock'],
  ['wp-block-tab-list', 'tabList'],
  ['wp-block-tab-panels', 'tabPanels'],
  ['wp-block-tab-panel', 'tabPanel'],
  ['wp-block-tabs', 'tabsBlock'],
]

function nodeNameForElement(el) {
  if (el.tagName === 'DETAILS') return 'detailsBlock'
  if (el.classList.contains('wp-block-pullquote'))    return 'pullquote'
  if (el.classList.contains('wp-block-preformatted')) return 'preformatted'
  for (const [cls, node] of NODE_FOR_BLOCK_CLASS) {
    if (el.classList.contains(cls)) return node
  }
  return NODE_FOR_TAG[el.tagName] || null
}

function shortBlockName(blockName) {
  return blockName.replace(/^core\//, '')
}

// The element's nearest preceding sibling that is not whitespace-only text.
function precedingSignificantNode(el) {
  let node = el.previousSibling
  while (node && node.nodeType === 3 && node.textContent.trim() === '') {
    node = node.previousSibling
  }
  return node
}

// Post markup parsed here never loads an image or runs a handler: docs/gotchas.md (script sink).
function inertDocument() {
  if (!inertDocument.doc) inertDocument.doc = document.implementation.createHTMLDocument('')
  return inertDocument.doc
}

function alreadyDelimited(el, name) {
  const node = precedingSignificantNode(el)
  if (!node || node.nodeType !== 8) return false
  const text = node.textContent.trim()
  return text === `wp:${name}` || text.startsWith(`wp:${name} `)
}

// Attributes WordPress wrote into the block comment, carried through the
// Tiptap round-trip on the element. Node-owned attributes override them.
function carriedBlockAttrs(el) {
  const raw = el.getAttribute && el.getAttribute('data-quill-block-attrs')
  if (!raw) return null
  try {
    const parsed = JSON.parse(raw)
    return (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) ? parsed : null
  } catch (e) {
    return null
  }
}

// The image, gallery and embed passes rebuild their attrs from the rendered
// figure instead of going through wrapBlock, so the carrier is merged in here.
function mergeCarried(el, attrs, ownedKeys) {
  return overlayCarried(carriedBlockAttrs(el), attrs, ownedKeys)
}

// Attributes core's block supports register, which it serializes after a block's own.
const SUPPORTS_KEYS = new Set(['align', 'anchor', 'className', 'style', 'backgroundColor', 'textColor', 'gradient', 'fontFamily', 'fontSize', 'borderColor', 'layout', 'lock', 'metadata'])

// A carried key keeps the position WordPress gave it; see Resources/CLAUDE.md.
function overlayCarried(carried, attrs, ownedKeys) {
  const owned = new Set(ownedKeys || [])
  const next = attrs || {}
  const kept = Object.keys(carried || {}).filter(key => key in next || !owned.has(key))
  const added = Object.keys(next).filter(key => !kept.includes(key))
  const firstSupports = kept.findIndex(key => SUPPORTS_KEYS.has(key))
  const split = firstSupports === -1 ? kept.length : firstSupports
  const order = [
    ...kept.slice(0, split),
    ...added.filter(key => !SUPPORTS_KEYS.has(key)),
    ...kept.slice(split),
    ...added.filter(key => SUPPORTS_KEYS.has(key)),
  ]
  const out = {}
  for (const key of order) out[key] = key in next ? next[key] : carried[key]
  return out
}

function unicodeEscape(ch) {
  return '\\u' + ch.charCodeAt(0).toString(16).padStart(4, '0')
}

// JSON that cannot end or break its HTML comment, escaped as WordPress writes it (measured in Scripts/test-block-serializer.js).
function serializeAttributes(attrs) {
  return JSON.stringify(attrs).replace(/\\[\\"]|--|[<>&]/g, token =>
    token[0] === '\\' ? unicodeEscape(token[1]) : Array.from(token, unicodeEscape).join(''))
}

function delimiterAttrs(attrs) {
  return Object.keys(attrs).length ? ' ' + serializeAttributes(attrs) : ''
}

function mergeClassNames(existing, extra) {
  const seen = new Set(String(existing || '').split(/\s+/).filter(Boolean))
  for (const token of String(extra || '').split(/\s+/)) if (token) seen.add(token)
  return Array.from(seen).join(' ')
}

function wrapBlock(doc, el, name, attrs, ownedAttrs) {
  if (alreadyDelimited(el, name)) return
  const merged = overlayCarried(carriedBlockAttrs(el), attrs, ownedAttrs)
  wrapElementWithComments(doc, el, ` wp:${name}${delimiterAttrs(merged)} `, ` /wp:${name} `)
}

function wrapListItems(doc, listEl) {
  Array.from(listEl.children).forEach(li => {
    if (li.tagName !== 'LI') return
    Array.from(li.children).forEach(child => {
      if (child.tagName !== 'UL' && child.tagName !== 'OL') return
      wrapListItems(doc, child)
      const nestedName = NODE_FOR_TAG[child.tagName]
      const nested = blockDescriptorRegistry.descriptorFor(nestedName)
      wrapBlock(doc, child, shortBlockName(nested.blockName), descriptorAttrs(nestedName, nested, child),
        blockDescriptorRegistry.ownedAttrsFor(nestedName))
    })
    wrapBlock(doc, li, 'list-item', {})
  })
}

function descriptorAttrs(nodeName, descriptor, el) {
  return {
    ...descriptor.attrsFrom(el),
    ...blockDescriptorRegistry.attrsFromSettings(nodeName, el),
    ...supportAttrs(descriptor, el),
  }
}

// Classes a block's own save() or its style supports draw; anything else on the root is a custom class.
const GENERATED_CLASS = /^(wp-block-|has-|is-(?!style-)|are-|items-justified-|wp-elements-|wp-container-|align(left|right|center|wide|full|none)$)/

// core's anchor and customClassName supports, which a block from outside Gutenberg carries only in its markup.
function supportAttrs(descriptor, el) {
  const carried = carriedBlockAttrs(el) || {}
  const attrs = {}
  const id = el.getAttribute('id')
  if (id && !descriptor.noAnchor && !('anchor' in carried)) attrs.anchor = id
  const custom = (el.getAttribute('class') || '').split(/\s+/).filter(c => c && !GENERATED_CLASS.test(c))
  if (custom.length && !('className' in carried)) attrs.className = custom.join(' ')
  return attrs
}

function wrapInDelimiters(root, doc) {
  Array.from(root.children).forEach(el => {
    if (el.hasAttribute('data-quill-passthrough-placeholder')) return
    if (el.classList.contains('wp-block-footnotes')) return

    const nodeName = nodeNameForElement(el)
    const descriptor = nodeName ? blockDescriptorRegistry.descriptorFor(nodeName) : null
    if (!descriptor) return

    if (descriptor.childBlockName === 'core/list-item') wrapListItems(doc, el)
    if (descriptor.shape === 'container' && descriptor.blockName !== 'core/list') wrapInDelimiters(el, doc)

    wrapBlock(doc, el, shortBlockName(descriptor.blockName), descriptorAttrs(nodeName, descriptor, el),
      blockDescriptorRegistry.ownedAttrsFor(nodeName))
  })
}

function extractAlignment(cls) {
  if (cls.includes('alignleft'))   return 'left'
  if (cls.includes('alignright'))  return 'right'
  if (cls.includes('aligncenter')) return 'center'
  return null
}

function titleCaseHyphenated(str) {
  return str.split('-').filter(Boolean)
    .map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ')
}

function passthroughLabelFromClass(cls) {
  return titleCaseHyphenated(cls.replace(/^wp-block-/, ''))
}

function passthroughLabelFromBlockName(name) {
  if (name === 'core/html') return 'Custom HTML'
  const base = name.includes('/') ? name.split('/').pop() : name
  return titleCaseHyphenated(base)
}

// Gutenberg blocks Quill models with a dedicated Tiptap node whose parse rule
// matches a *non-figure* tag. gutenbergPassthrough's rule out-ranks the core
// nodes (priority 200, above bulletList/codeBlock/blockquote/etc. at 100 and
// the footnote nodes at 110) — otherwise an unmodeled block that happens to
// live on a shared tag, like a wp-block-social-links <ul>, is claimed by the
// generic 'ul' rule and its non-list children (<a>, <svg>) are destroyed on
// the next save. Out-ranking everything means passthrough must instead opt
// *out* explicitly, which is what this set is for.
//
// Figure-rooted blocks are listed separately in QUILL_MODELED_FIGURE_CLASSES,
// which the passthrough node's second (figure-only) parse rule consults.
const QUILL_MODELED_BLOCK_CLASSES = new Set([
  'wp-block-heading',
  'wp-block-list',
  'wp-block-footnotes',
  'wp-block-quote',
  'wp-block-code',
  'wp-block-separator',
])

// Figure-rooted Gutenberg blocks Quill already handles. Image, gallery and
// embed each have their own `figure.wp-block-*` parse rule. Table has none —
// it relies on the parser descending past the figure so Tiptap's bare `table`
// rule claims the inner element, with toWordPressHTML re-wrapping the figure
// on save — so it must be listed here too, or passthrough (priority 200)
// would claim the whole figure as an atom and freeze every table into a
// non-editable card. Every *other* wp-block-* figure (audio, video,
// pullquote, playlist, …) has no rule of its own, so the generic parser
// shreds it: the wrapper and its block comments are dropped, <audio>/<video>
// children vanish entirely, and a pullquote is silently rewritten as a plain
// quote. gutenbergPassthrough claims those instead; this set is how the
// blocks Quill really does model opt back out.
const QUILL_MODELED_FIGURE_CLASSES = new Set([
  'wp-block-image',
  'wp-block-gallery',
  'wp-block-embed',
  'wp-block-table',
  'wp-block-pullquote',
])

// True when `el` is a <figure> rooted at a block Quill models natively, and
// so must be left to that block's own parse rule.
function isModeledFigure(el) {
  if (!el || el.tagName !== 'FIGURE') return false
  return Array.from(el.classList).some(c => QUILL_MODELED_FIGURE_CLASSES.has(c))
}

function missingClosers(block) {
  const names = []
  for (let b = block; b && b.closed === false; b = b.innerBlocks[b.innerBlocks.length - 1]) {
    names.unshift(shortBlockName(b.blockName))
  }
  return names.map(name => `<!-- /wp:${name} -->`).join('')
}

function blockSourceSlices(html, parse) {
  return parse(html).map(block => ({
    blockName: block.blockName,
    attrsJSON: block.attrs && Object.keys(block.attrs).length ? JSON.stringify(block.attrs) : null,
    source: html.slice(block.start, block.end) + missingClosers(block),
  }))
}

// One preservation path per CLAUDE.md: freeform is prose, everything unmodeled wraps.
function blockNeedsWrapping(slice, doc) {
  if (!slice.blockName) return false
  if (!blockDescriptorRegistry.modelsBlockName(slice.blockName)) return true
  // A modeled name that saved no markup has nothing for its node to parse.
  const probe = doc.createElement('div')
  probe.innerHTML = slice.source.replace(/<!--[\s\S]*?-->/g, '')
  return probe.children.length === 0
}

// Every block at every depth: a heading lost from inside a quote is still lost.
function countBlockNames(blocks, into) {
  const counts = into || new Map()
  for (const block of blocks || []) {
    if (block.blockName) {
      const short = shortBlockName(block.blockName)
      counts.set(short, (counts.get(short) || 0) + 1)
    }
    countBlockNames(block.innerBlocks, counts)
  }
  return counts
}

// Verifies the outcome rather than the wrap, so a bug in the wrap surfaces as
// a warning instead of silent loss. Counts, so one copy cannot cover for another.
function unrepresentedBlockNames(expectedCounts, accountedCounts) {
  const missing = []
  for (const [name, expected] of expectedCounts) {
    if ((accountedCounts.get(name) || 0) < expected) missing.push(name)
  }
  return missing
}

function unsupportedWrapper(doc, source, blockName) {
  const el = doc.createElement('div')
  el.className = 'wp-block-quill-unsupported'
  el.setAttribute('data-quill-unsupported-source', source)
  el.setAttribute('data-quill-unsupported-label', passthroughLabelFromBlockName(blockName))
  return el
}

// Top-level tags outside any block that the editor turns into prose without losing anything.
const FREEFORM_PROSE_TAGS = new Set([
  'P', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'UL', 'OL', 'BLOCKQUOTE', 'PRE', 'HR',
  'TABLE', 'FIGURE', 'IMG', 'DETAILS', 'BR', 'WBR',
  'A', 'ABBR', 'B', 'BDI', 'BDO', 'CITE', 'CODE', 'DATA', 'DEL', 'DFN', 'EM', 'I', 'INS',
  'KBD', 'MARK', 'Q', 'S', 'SAMP', 'SMALL', 'SPAN', 'STRONG', 'SUB', 'SUP', 'TIME', 'U', 'VAR',
])

// Grouping tags with no meaning of their own: bare, the editor unwraps them harmlessly.
const FREEFORM_GROUPING_TAGS = new Set(['DIV', 'SECTION', 'ARTICLE', 'ASIDE', 'HEADER', 'FOOTER', 'MAIN', 'NAV'])

// Kept as Custom HTML, as Gutenberg's Convert to Blocks does: docs/block-model.md.
function freeformElementsToKeep(parent, into) {
  for (const el of Array.from(parent.children)) {
    if (FREEFORM_PROSE_TAGS.has(el.tagName)) continue
    if (Array.from(el.classList).some(c => c.startsWith('wp-block-'))) continue
    if (FREEFORM_GROUPING_TAGS.has(el.tagName) && el.attributes.length === 0) freeformElementsToKeep(el, into)
    else into.push(el)
  }
  return into
}

function wrapFreeformHTML(source, doc) {
  const container = doc.createElement('div')
  container.innerHTML = source
  const keep = freeformElementsToKeep(container, [])
  if (!keep.length) return source
  for (const el of keep) {
    el.replaceWith(unsupportedWrapper(doc, `<!-- wp:html -->\n${el.outerHTML}\n<!-- /wp:html -->`, 'core/html'))
  }
  return container.innerHTML
}

// Sliced from the source, not the parser's innerHTML, which leaves out nested blocks.
function customHTMLBlock(source, parse) {
  const blocks = parse(source).filter(b => b.blockName || b.innerHTML.trim())
  if (blocks.length !== 1 || blocks[0].blockName !== 'core/html') return null
  const text = source.slice(blocks[0].start, blocks[0].end)
  const openerEnd = text.indexOf('-->') + 3
  const opener = text.slice(0, openerEnd)
  if (opener.endsWith('/-->')) return { html: '', opener: opener.slice(0, -4).trimEnd() + ' -->' }
  const closeAt = text.lastIndexOf('<!-- /wp:html')
  const body = text.slice(openerEnd, closeAt < openerEnd ? text.length : closeAt)
  return { html: body.replace(/^\n/, '').replace(/\n$/, ''), opener }
}

function customHTMLSource(html, opener = '<!-- wp:html -->') {
  return `${opener}\n${html}\n<!-- /wp:html -->`
}

function wrapUnsupportedBlocks(html, parse, doc) {
  doc = doc || inertDocument()
  const slices = blockSourceSlices(html, parse)
  const wrapped = slices.map(slice => {
    if (!slice.blockName) return wrapFreeformHTML(slice.source, doc)
    if (!blockNeedsWrapping(slice, doc)) return slice.source
    return unsupportedWrapper(doc, slice.source, slice.blockName).outerHTML
  })
  return wrapped.some((s, i) => s !== slices[i].source) ? wrapped.join('') : html
}

// The element as authored, without the marker ProseMirror adds to copied HTML.
function sourceHTMLOf(el) {
  if (!el.hasAttribute('data-pm-slice')) return el.outerHTML
  const copy = el.cloneNode(true)
  copy.removeAttribute('data-pm-slice')
  return copy.outerHTML
}

// Given a wp-block-* classed element that gutenbergPassthrough's parse rule
// matched, extracts what's needed to preserve and re-display it. Returns null
// if `el` has no wp-block-* class at all, or if any of its wp-block-* classes
// names a block Quill models natively (which must go to its own node instead).
//
// Checks for immediately-adjacent `<!-- wp:name --> / <!-- /wp:name -->`
// comment siblings (skipping whitespace-only text nodes in between, since
// real Gutenberg source has a newline between a comment and its element).
// If found and their names match, blockName/attrsJSON are populated from the
// comment text verbatim so toWordPressHTML can regenerate identical comments
// on save. If not found, this is class-only markup (e.g. a live page's
// rendered HTML) — blockName/attrsJSON stay null and no comments are
// synthesized later.
function parsePassthroughBlock(el) {
  const wpClasses = Array.from(el.classList).filter(c => c.startsWith('wp-block-'))
  const wpClass = wpClasses[0]
  if (!wpClass) return null
  // Check every wp-block-* class, not just the first: a modeled class anywhere
  // on the element hands it back to its own node, so an ordinary list/heading
  // can never be swallowed by the catch-all.
  if (wpClasses.some(c => QUILL_MODELED_BLOCK_CLASSES.has(c))) return null
  // Quill's own table render, arriving through a copy inside the editor.
  if (el.tagName === 'TABLE' && el.hasAttribute('data-quill-fixed-layout')) return null

  function adjacentComment(node, direction) {
    let n = node[direction]
    while (n && n.nodeType === 3 && n.textContent.trim() === '') n = n[direction]
    return (n && n.nodeType === 8) ? n : null
  }

  const openComment = adjacentComment(el, 'previousSibling')
  const closeComment = adjacentComment(el, 'nextSibling')
  const openMatch = openComment && openComment.nodeValue.match(/^\s*wp:(\S+?)(?:\s+(\{[\s\S]*\}))?\s*$/)
  const closeMatch = closeComment && closeComment.nodeValue.match(/^\s*\/wp:(\S+)\s*$/)

  if (openMatch && closeMatch && openMatch[1] === closeMatch[1]) {
    return {
      blockLabel: passthroughLabelFromBlockName(openMatch[1]),
      blockName: openMatch[1],
      attrsJSON: openMatch[2] || null,
      sourceHTML: sourceHTMLOf(el),
    }
  }

  return {
    blockLabel: passthroughLabelFromClass(wpClass),
    blockName: null,
    attrsJSON: null,
    sourceHTML: sourceHTMLOf(el),
  }
}

// Wraps `el` with a pair of HTML comments (open/close), each separated from
// the element by its own newline text node, via DOM sibling insertion rather
// than string replace — so repeated saves and duplicate content don't
// double-wrap. Shared by the embed/gallery/passthrough wp:name comment
// wrapping below.
// Gutenberg's serializer joins sibling blocks with a blank line, at every level.
// One pass over the finished tree rather than a step inside each wrap, because
// the wrapping passes do not run in document order — an image figure is wrapped
// before the separator above it is, so a backwards-looking check there sees a
// bare <hr> on the first save and a close comment on the second. The whitespace
// between the two comments is replaced, not added to, so repeated saves cannot
// stack a second blank line on the first.
// A wrapper is a whole block in one element, so it both ends and begins one.
function isUnsupportedWrapper(node) {
  return node.nodeType === 1 && node.hasAttribute('data-quill-unsupported-source')
}

function opensBlock(node) {
  return isUnsupportedWrapper(node) ||
    (node.nodeType === 8 && node.textContent.trim().startsWith('wp:'))
}

function closesBlock(node) {
  return isUnsupportedWrapper(node) ||
    (node.nodeType === 8 && node.textContent.trim().startsWith('/wp:'))
}

function separateSiblingBlocks(root, doc) {
  for (const parent of [root, ...root.querySelectorAll('*')]) {
    for (const node of Array.from(parent.childNodes)) {
      if (!opensBlock(node)) continue
      const prev = precedingSignificantNode(node)
      if (!prev || !closesBlock(prev)) continue
      let cursor = node.previousSibling
      while (cursor && cursor !== prev) {
        const before = cursor.previousSibling
        cursor.remove()
        cursor = before
      }
      parent.insertBefore(doc.createTextNode('\n\n'), node)
    }
  }
}

function wrapElementWithComments(doc, el, openText, closeText) {
  const open = doc.createComment(openText)
  const close = doc.createComment(closeText)
  const parent = el.parentNode
  const next = el.nextSibling
  parent.insertBefore(open, el)
  parent.insertBefore(doc.createTextNode('\n'), el)
  parent.insertBefore(doc.createTextNode('\n'), next)
  parent.insertBefore(close, next)
}

// Attributes WordPress writes on a core/image block comment. Each key is
// omitted when it can't be determined from the figure, which is what core does
// too — an image with no attributes saves as a bare `<!-- wp:image -->`.
// Pixel dimension from either the legacy width/height attribute or the inline
// style core now writes. `auto` and percentages yield null, matching core's
// treatment of an unset dimension.
function imgPixelDimension(img, prop) {
  const attr = img.getAttribute(prop)
  if (attr) {
    const n = parseInt(attr, 10)
    if (n) return n
  }
  const m = (img.getAttribute('style') || '').match(styleDimensionRegex(prop))
  return m ? Math.round(parseFloat(m[1])) : null
}

function styleDimensionRegex(prop) {
  return new RegExp('(?:^|;)\\s*' + prop + '\\s*:\\s*([0-9.]+)px', 'i')
}

// core/image's save() renders dimensions as an inline style plus an is-resized
// class on the figure, never as HTML width/height attributes. Markup carrying
// either form without the other fails Gutenberg's block validation, so the two
// are rebuilt together here from whichever form the editor produced.
function applyImageDimensions(figure, img) {
  const width = imgPixelDimension(img, 'width')
  const height = imgPixelDimension(img, 'height')
  img.removeAttribute('width')
  img.removeAttribute('height')
  figure.classList.remove('is-resized')
  // Only the dimensions are Quill's; the carried style is spliced back around them.
  const parts = (img.getAttribute('data-quill-style') || '')
    .split(';').map(d => d.trim()).filter(d => d && !/^(width|height)\s*:/.test(d))
  img.removeAttribute('data-quill-style')
  img.removeAttribute('style')
  if (width != null) parts.push(`width:${width}px`)
  if (width != null || height != null) parts.push(height != null ? `height:${height}px` : 'height:auto')
  if (parts.length) img.setAttribute('style', parts.join(';'))
  if (width != null || height != null) figure.classList.add('is-resized')
}

// WordPress names every size of one upload after it: p.jpg, p-scaled.jpg, p-1024x683.jpg.
function uploadStem(url) {
  return String(url || '').split(/[?#]/)[0].replace(/(?:-(?:\d+x\d+|scaled|rotated))+(?=\.\w+$)/, '')
}

function imageBlockAttrs(figure, img) {
  const attrs = {}
  const id = (img.getAttribute('class') || '').match(/wp-image-(\d+)/)
  if (id) attrs.id = parseInt(id[1], 10)
  const style = img.getAttribute('style') || ''
  const width = style.match(styleDimensionRegex('width'))
  if (width) attrs.width = width[1] + 'px'
  const height = style.match(styleDimensionRegex('height'))
  if (height) attrs.height = height[1] + 'px'
  // Pre-9.47 block editors rebuild the style from the comment: docs/editor-gotchas.md
  else if (/(?:^|;)\s*height\s*:\s*auto\b/i.test(style)) attrs.height = 'auto'
  const size = (figure.getAttribute('class') || '').match(/(?:^|\s)size-([\w-]+)/)
  if (size) attrs.sizeSlug = size[1]
  const carried = (carriedBlockAttrs(figure) || {}).linkDestination
  if (img.parentNode && img.parentNode.tagName === 'A') {
    // A destination core set wins; inferring turns a custom URL into a media link.
    const toImageFile = uploadStem(img.parentNode.getAttribute('href')) === uploadStem(img.getAttribute('src'))
    attrs.linkDestination = (carried && carried !== 'none') ? carried : (toImageFile ? 'media' : 'custom')
  } else if (carried === 'none') {
    attrs.linkDestination = 'none'
  }
  // After linkDestination: core serializes its keys in block.json order.
  const align = ['left', 'right', 'center'].find(a => figure.classList.contains('align' + a))
  if (align) attrs.align = align
  const role = img.getAttribute('role')
  if (role === 'none' || role === 'presentation') attrs.isDecorative = true
  return attrs
}

function toWordPressHTML(html, doc) {
  if (!doc && typeof document !== 'undefined') doc = inertDocument()
  const div = doc.createElement('div')
  // Strip existing wp:embed block comments — will re-add fresh ones below.
  // The attrs-matching group is non-greedy (`[\s\S]*?`) and stops at the first
  // `-->`: a loaded gallery's `sourceHTML` re-emits its nested `<!-- wp:image -->`
  // comments verbatim with no guaranteed newline between them (unlike this
  // function's own wrap step below, which always inserts one), so a greedy
  // `[^\n]*` here would span past the first comment's close and swallow the
  // image figure(s) in between. `[\s\S]*?` (not `.*?`) because JS `.` excludes
  // ALL line terminators (\n, \r, U+2028, U+2029), not just \n — a `.*?` group
  // would fail to match at all if a stray \r ever landed inside a comment's
  // attrs before its own `-->`.
  div.innerHTML = html

  // The editor keeps an empty paragraph after a block with nowhere to click
  // past it so the caret has somewhere to land; it is chrome, not content.
  // Scoped to exactly TRAILING_PARAGRAPH_AFTER's shapes (editor.html), or an
  // empty paragraph the author wrote at the end of a post is deleted too.
  const tail = div.lastElementChild
  const beforeTail = tail && tail.previousElementSibling
  if (tail && tail.tagName === 'P' && beforeTail &&
      !tail.children.length && !tail.textContent.trim() &&
      beforeTail.matches('table, figure, hr, [data-quill-unsupported-source], [data-quill-passthrough]')) {
    tail.remove()
  }

  // Passthrough (gutenbergPassthrough) elements must survive this entire
  // function byte-for-byte — not just the comment-strip regex below, but
  // every other unconditional div.querySelectorAll(...) pass further down
  // (heading/list/blockquote/cite/figure/table/footnote normalization). Those
  // passes have no concept of "this subtree belongs to an opaque passthrough
  // node" and would otherwise reach into a passthrough element's nested
  // content (e.g. add wp-block-heading to a nested <h3>, or delete a nested
  // empty <cite>/<figcaption>) even though it's supposed to be preserved
  // verbatim. So passthrough elements are pulled out and replaced with
  // placeholders here, before ANY transform pass runs, and only spliced back
  // in — completely untouched — right before the wp:name comment
  // regeneration pass far below, after every other whole-tree pass has run.
  const passthroughStash = []
  div.querySelectorAll('[data-quill-passthrough]').forEach(el => {
    const placeholder = doc.createElement('div')
    placeholder.setAttribute('data-quill-passthrough-placeholder', String(passthroughStash.length))
    passthroughStash.push(el)
    el.replaceWith(placeholder)
  })

  // The strip below deletes a gallery's nested wp:image comments, so their attrs move onto the figure first.
  div.querySelectorAll('figure.wp-block-gallery > figure.wp-block-image:not([data-quill-block-attrs])').forEach(figure => {
    const comment = precedingSignificantNode(figure)
    const match = comment && comment.nodeType === 8 && comment.nodeValue.match(/^\s*wp:image\s+(\{[\s\S]*\})\s*$/)
    if (match) figure.setAttribute('data-quill-block-attrs', match[1])
  })

  div.innerHTML = div.innerHTML
    .replace(/<!-- wp:embed [\s\S]*?-->\n?/g, '')
    .replace(/\n?<!-- \/wp:embed -->/g, '')
    .replace(/<!-- wp:gallery [\s\S]*?-->\n?/g, '')
    .replace(/\n?<!-- \/wp:gallery -->/g, '')
    // Both standalone and gallery-nested images are comment-wrapped further down,
    // so this strip clears the previous save's pairs before fresh ones are added
    // — the same strip-then-rewrap cycle the gallery and embed passes rely on for
    // idempotency.
    // Passthrough content (which could route raw WordPress HTML with standalone
    // wp:image comments through here) is shielded from this strip via the stash
    // above — it's pulled out of the tree entirely before this regex runs.
    .replace(/<!-- wp:image [\s\S]*?-->\n?/g, '')
    .replace(/\n?<!-- \/wp:image -->/g, '')

  // Re-emit wp-image-{id} class so WordPress can associate images with media library entries
  div.querySelectorAll('img[data-media-id]').forEach(img => {
    const id = img.getAttribute('data-media-id')
    if (id) img.classList.add(`wp-image-${id}`)
    // Editor-internal attribute — the class carries the id from here on, and
    // ResizableImage's mediaId parseHTML reads it back off that class on load.
    img.removeAttribute('data-media-id')
  })

  // Image figures: renderHTML produces <figure><img ...><figcaption/></figure>.
  // Add wp-block-image class, move alignment from img to figure, handle caption.
  div.querySelectorAll('figure:not(.wp-block-table):not(.wp-block-embed):not(.wp-block-gallery)').forEach(figure => {
    const img = figure.querySelector('img')
    if (!img) return
    const align = ['alignleft', 'alignright', 'aligncenter']
      .find(c => img.classList.contains(c))
    // Core writes wp-block-image first; classList.add would append it instead.
    if (!figure.classList.contains('wp-block-image')) {
      figure.setAttribute('class', ['wp-block-image', figure.getAttribute('class') || ''].filter(Boolean).join(' '))
    }
    if (align) {
      figure.classList.add(align)
      img.classList.remove(align)
    }
    const caption = figure.querySelector('figcaption')
    if (caption) {
      if (caption.textContent.trim()) {
        caption.classList.add('wp-element-caption')
      } else {
        caption.remove()
      }
    }
    applyImageDimensions(figure, img)
  })

  const IMAGE_OWNED_ATTRS = ['id', 'sizeSlug', 'width', 'height', 'align', 'linkDestination', 'isDecorative']

  // Standalone images → wp:image block comments. Without them WordPress parses
  // the figure as classic HTML rather than a core/image block, so the block
  // editor offers no image controls for it. Gallery-nested images are skipped —
  // the gallery pass below wraps those itself, in the same save.
  div.querySelectorAll('figure.wp-block-image').forEach(figure => {
    if (figure.closest('.wp-block-gallery')) return
    const img = figure.querySelector('img')
    if (!img) return
    const attrs = mergeCarried(figure, imageBlockAttrs(figure, img), IMAGE_OWNED_ATTRS)
    const open = ` wp:image${delimiterAttrs(attrs)} `
    wrapElementWithComments(doc, figure, open, ' /wp:image ')
  })

  // Headings → wp-block-heading class (core/accordion-heading is its own block
  // and core's save never puts wp-block-heading on it)
  const HEADING_TAGS = 'h1, h2, h3, h4, h5, h6'
  div.querySelectorAll(HEADING_TAGS).forEach(el => {
    if (!el.classList.contains('wp-block-accordion-heading')) el.classList.add('wp-block-heading')
  })

  // Lists → wp-block-list class (footnotes list excluded — it has its own class)
  div.querySelectorAll('ul, ol:not(.wp-block-footnotes)').forEach(el => {
    el.classList.add('wp-block-list')
  })

  // Strip Tiptap's paragraph wrapper inside list items: <li><p>text</p></li> → <li>text</li>
  // Only unwrap when there is exactly one child element and it is a <p> (multi-paragraph
  // list items are left as-is so their content is not mangled).
  // A nested item serializes as <li><p>text</p><ul>…</ul></li>, so the leading <p> is
  // also unwrapped when everything after it is a nested list — Gutenberg writes those
  // as <li>text<ul>…</ul></li>. Without that case, opening any post containing a nested
  // list and saving it rewrote the markup even when the list was never touched.
  // replaceWith (not innerHTML =) so the nested list survives the unwrap.
  div.querySelectorAll('li').forEach(li => {
    const kids = Array.from(li.children)
    if (!kids.length || kids[0].tagName !== 'P') return
    const restAreLists = kids.slice(1).every(el => el.tagName === 'UL' || el.tagName === 'OL')
    if (!restAreLists) return
    kids[0].replaceWith(...kids[0].childNodes)
  })

  // Blockquotes → wp-block-quote class. A pullquote's own blockquote is part
  // of core/pullquote's markup, not a nested core/quote.
  div.querySelectorAll('blockquote').forEach(el => {
    if (el.closest('figure.wp-block-pullquote')) return
    el.classList.add('wp-block-quote')
  })

  // Strip empty cite elements (user left attribution blank)
  div.querySelectorAll('blockquote cite').forEach(el => {
    if (!el.textContent.trim()) el.remove()
  })

  // Code blocks → wp-block-code class on the <pre> wrapper. core/code's save()
  // draws no class on <code>, so a language class moves up to the block.
  div.querySelectorAll('pre').forEach(el => {
    if (el.classList.contains('wp-block-preformatted')) return
    el.classList.add('wp-block-code')
    const code = el.querySelector(':scope > code[class]')
    if (!code) return
    el.className = mergeClassNames(el.className, code.className)
    code.removeAttribute('class')
  })

  // Top-level bare text parses with its leading newline as a space, which a reload then drops.
  div.querySelectorAll(':scope > p').forEach(p => {
    const first = p.firstChild
    if (first && first.nodeType === 3) first.textContent = first.textContent.replace(/^[\n\r\t ]+/, '')
  })

  // Horizontal rules → wp-block-separator
  div.querySelectorAll('hr').forEach(el => {
    el.classList.add('wp-block-separator', 'has-alpha-channel-opacity')
  })

  // Tables: strip Tiptap-specific artifacts that WordPress doesn't use
  div.querySelectorAll('table').forEach(table => {
    table.removeAttribute('style')
    table.querySelectorAll('colgroup').forEach(cg => cg.remove())
    table.querySelectorAll('th, td').forEach(cell => {
      if (cell.getAttribute('colspan') === '1') cell.removeAttribute('colspan')
      if (cell.getAttribute('rowspan') === '1') cell.removeAttribute('rowspan')
      const kids = Array.from(cell.children)
      if (kids.length === 1 && kids[0].tagName === 'P') {
        cell.innerHTML = kids[0].innerHTML
      }
    })
  })

  // Tables: regroup rows into core's fixed head-body-foot order. A row that
  // declares a section is authoritative; an all-<th> first row that declares
  // nothing is the header, which is what a classic table and a table Quill
  // created itself both look like.
  div.querySelectorAll('table').forEach(table => {
    const rows = Array.from(table.querySelectorAll('tr'))
    if (!rows.length) return
    const types = rows.map(tr => {
      const type = tr.getAttribute('data-quill-row') || 'body'
      tr.removeAttribute('data-quill-row')
      return type
    })
    // Decided per row, not per table: a Quill-inserted table's header is an
    // all-<th> first row that declares nothing, and it stays a header even once
    // a footer beneath it declares one.
    if (types[0] === 'body' && !types.includes('head')) {
      const cells = Array.from(rows[0].children)
      if (cells.length > 0 && cells.every(c => c.tagName === 'TH')) types[0] = 'head'
    }
    const grouped = { head: [], body: [], foot: [] }
    rows.forEach((tr, i) => grouped[types[i]].push(tr))

    Array.from(table.children).forEach(child => child.remove())
    for (const [section, tag] of [['head', 'thead'], ['body', 'tbody'], ['foot', 'tfoot']]) {
      if (!grouped[section].length) continue
      const el = doc.createElement(tag)
      grouped[section].forEach(tr => el.appendChild(tr))
      table.appendChild(el)
    }
  })

  // Tables → Gutenberg figure wrapper. The block's classes, its carried
  // delimiter attributes and its caption all belong on the figure, but reach
  // here on the <table> because that is the element Tiptap renders.
  div.querySelectorAll('table').forEach(table => {
    if (table.parentElement?.classList.contains('wp-block-table')) return
    const figure = doc.createElement('figure')
    const blockClasses = String(table.getAttribute('class') || '').replace(/(^|\s)has-fixed-layout(?=\s|$)/g, ' ')
    figure.className = mergeClassNames('wp-block-table', blockClasses)
    const fixedLayout = table.getAttribute('data-quill-fixed-layout') !== 'false'
    table.removeAttribute('data-quill-fixed-layout')
    const carried = table.getAttribute('data-quill-block-attrs')
    if (carried) figure.setAttribute('data-quill-block-attrs', carried)
    const caption = table.getAttribute('data-quill-caption')
    table.removeAttribute('class')
    table.removeAttribute('data-quill-block-attrs')
    table.removeAttribute('data-quill-caption')
    table.parentNode.insertBefore(figure, table)
    figure.appendChild(table)
    if (fixedLayout) table.setAttribute('class', 'has-fixed-layout')
    if (caption) {
      const el = doc.createElement('figcaption')
      el.className = 'wp-element-caption'
      el.innerHTML = caption
      figure.appendChild(el)
    }
  })

  // Footnote markers: write 1-based numbers into anchors in document order.
  // The editor leaves anchors empty (CSS counters display numbers live);
  // the saved HTML carries real text so it renders anywhere.
  div.querySelectorAll('sup.fn[data-fn] > a').forEach((a, i) => {
    a.textContent = String(i + 1)
  })

  // Footnote markers carry core's `<fnId>-link` id, which is the anchor
  // core/footnotes' server-side render points its ↩︎ backref at. The backref
  // itself is never written here -- WordPress builds it from post meta.
  div.querySelectorAll('sup.fn[data-fn]').forEach(sup => {
    sup.id = sup.getAttribute('data-fn') + '-link'
  })

  // Wrap embed figures with Gutenberg block comments so WordPress enqueues
  // the embed block CSS (required for responsive aspect-ratio behaviour).
  // DOM-level insertion avoids the String.replace() first-occurrence-only bug
  // that double-wraps duplicate embed URLs.
  div.querySelectorAll('figure.wp-block-embed').forEach(figure => {
    const wrapper = figure.querySelector('.wp-block-embed__wrapper')
    const url = wrapper ? wrapper.textContent.trim() : ''
    if (!url) return
    const p = detectEmbedProvider(url)
    const attrs = { url }
    if (p) {
      attrs.type = p.type
      attrs.providerNameSlug = p.slug
    }
    attrs.responsive = true
    if (p && p.aspect) attrs.className = 'wp-embed-aspect-16-9 wp-has-aspect-ratio'
    const merged = mergeCarried(figure, attrs, ['url', 'type', 'providerNameSlug'])
    wrapElementWithComments(doc, figure, ` wp:embed${delimiterAttrs(merged)} `, ' /wp:embed ')
  })

  // Wrap gallery figures with Gutenberg block comments: one wp:gallery pair
  // around the whole figure, one wp:image pair per nested image figure.
  // Mirrors the embed-wrapping approach above — DOM-level insertion, not
  // string replace, so repeated saves and duplicate content don't double-wrap.
  div.querySelectorAll('figure.wp-block-gallery').forEach(figure => {
    const columnsMatch = figure.className.match(/columns-(\d+)/)
    const columns = columnsMatch ? parseInt(columnsMatch[1], 10) : null
    const cropped = figure.classList.contains('is-cropped')
    const imageFigures = Array.from(figure.children).filter(
      c => c.tagName === 'FIGURE' && c.classList.contains('wp-block-image')
    )
    // Remove whitespace-only text node children of the gallery figure before
    // wrapping. On a re-save, the strip step above can leave an orphaned
    // whitespace-only text node between two image figures (the "\n\n"
    // separator inserted below is never adjacent to either comment tag on its
    // own, so neither strip regex consumes it). Cleaning it up here — scoped
    // to only this gallery figure's direct children, and only whitespace-only
    // text nodes — restores the pristine adjacency the forEach loop below
    // expects, so wrapping stays idempotent across repeated saves.
    Array.from(figure.childNodes).forEach(node => {
      if (node.nodeType === 3 && node.textContent.trim() === '') {
        figure.removeChild(node)
      }
    })
    const carried = carriedBlockAttrs(figure) || {}
    const sizes = new Set()
    let linkTo = carried.linkTo || 'none'
    imageFigures.forEach((imgFigure, i) => {
      const img = imgFigure.querySelector('img')
      if (!img) return
      const imageAttrs = mergeCarried(imgFigure, imageBlockAttrs(imgFigure, img), IMAGE_OWNED_ATTRS)
      if (!imageAttrs.linkDestination) imageAttrs.linkDestination = 'none'
      sizes.add(imageAttrs.sizeSlug)
      if (i === 0 && !carried.linkTo && imageAttrs.linkDestination !== 'none') linkTo = 'media'
      if (i > 0) figure.insertBefore(doc.createTextNode('\n\n'), imgFigure)
      wrapElementWithComments(doc, imgFigure, ` wp:image${delimiterAttrs(imageAttrs)} `, ' /wp:image ')
    })
    const galleryAttrs = columns === null ? { linkTo } : { columns, linkTo }
    if (!cropped) galleryAttrs.imageCrop = false
    // Core omits the default size, and core never writes ids for a gallery of nested images.
    const [size] = sizes
    if (!('sizeSlug' in carried) && sizes.size === 1 && size && size !== 'large') galleryAttrs.sizeSlug = size
    const mergedGallery = mergeCarried(figure, galleryAttrs, ['columns', 'imageCrop', 'linkTo'])
    wrapElementWithComments(doc, figure, ` wp:gallery${delimiterAttrs(mergedGallery)} `, ' /wp:gallery ')
  })

  wrapInDelimiters(div, doc)

  // Quill-internal: WordPress stores autoclose only in the block comment, so
  // the editor DOM carries it just long enough for attrsFrom to read it above.
  // <details open> is the opposite case and stays -- WordPress saves it.
  div.querySelectorAll('.wp-block-accordion[data-autoclose]').forEach(el => {
    el.removeAttribute('data-autoclose')
  })

  // Splice the passthrough elements stashed out at the top of this function
  // back in now, completely untouched by every pass above (media-id class,
  // image/heading/list/blockquote/cite/table/footnote/embed/gallery
  // normalization) — this is what makes passthrough content survive
  // byte-for-byte instead of being reached into by those unconditional
  // div.querySelectorAll(...) passes.
  div.querySelectorAll('[data-quill-passthrough-placeholder]').forEach(placeholder => {
    const i = Number(placeholder.getAttribute('data-quill-passthrough-placeholder'))
    placeholder.replaceWith(passthroughStash[i])
  })

  // Regenerate wp:name block comments for passthrough (unmodeled Gutenberg
  // block) elements. gutenbergPassthrough's renderHTML smuggles the original
  // comment's name/attrs through as temporary data-quill-passthrough-*
  // attributes (mirroring the data-media-id -> wp-image-{id} class
  // conversion above); this pass wraps the element in fresh
  // <!-- wp:name --> comments using those attributes (if the original had
  // none, no comments are added — see the "no data-quill-passthrough-name"
  // test), then strips the temporary attributes so they never appear in the
  // saved HTML. DOM-level insertion, not string replace, so repeated saves
  // don't double-wrap — same approach as the embed/gallery wrapping above.
  div.querySelectorAll('[data-quill-passthrough-name]').forEach(el => {
    const name = el.getAttribute('data-quill-passthrough-name')
    const attrsJSON = el.getAttribute('data-quill-passthrough-attrs')
    el.removeAttribute('data-quill-passthrough-name')
    el.removeAttribute('data-quill-passthrough-attrs')
    wrapElementWithComments(doc, el, attrsJSON ? ` wp:${name} ${attrsJSON} ` : ` wp:${name} `, ` /wp:${name} `)
  })

  separateSiblingBlocks(div, doc)

  div.querySelectorAll('[data-quill-block-attrs]').forEach(el => {
    el.removeAttribute('data-quill-block-attrs')
  })

  // A text node would escape the stored markup, so each wrapper leaves an
  // alphanumeric sentinel innerHTML won't touch, substituted back afterwards.
  // The nonce is per-save: a fixed token can be typed into a post, and the
  // first-occurrence replace then moved the preserved bytes to that text.
  const nonce = 'QUILL' + Math.random().toString(36).slice(2).toUpperCase() +
    Date.now().toString(36).toUpperCase() + 'END'
  const unsupported = []
  const stash = (el, source) => {
    unsupported.push(source)
    el.replaceWith(doc.createTextNode(`${nonce}${unsupported.length - 1}${nonce}`))
  }
  div.querySelectorAll('[data-quill-unsupported-source]').forEach(el => {
    stash(el, el.getAttribute('data-quill-unsupported-source'))
  })
  // Same stash for the passthrough card, whose markup is preserved verbatim:
  // the style and void-element passes below would otherwise rewrite it. The
  // generic marker renderHTML sets goes here rather than in its own pass.
  div.querySelectorAll('[data-quill-passthrough]').forEach(el => {
    el.removeAttribute('data-quill-passthrough')
    stash(el, el.outerHTML)
  })
  // ProseMirror serializes a style attribute through element.style, which
  // respaces it; core writes the compact form, so put it back.
  div.querySelectorAll('[style]').forEach(el => {
    el.setAttribute('style', el.getAttribute('style').replace(/;\s*$/, '').replace(/:\s+/g, ':').replace(/;\s+/g, ';'))
  })
  // Rename the carried style back in place, keeping its position; see Resources/CLAUDE.md.
  div.querySelectorAll('[data-quill-style]').forEach(el => {
    const attrs = Array.from(el.attributes).map(a => [a.name, a.value])
    attrs.forEach(([name]) => el.removeAttribute(name))
    attrs.forEach(([name, value]) => el.setAttribute(name === 'data-quill-style' ? 'style' : name, value))
  })
  // A boolean attribute set through the DOM serializes as name="", never bare.
  // Core self-closes img and hr but not br; runs before the source substitution.
  let out = div.innerHTML
    .replace(/<[a-z][^>]*>/gi, tag => tag.replace(/ (open|reversed)=""/g, ' $1'))
    .replace(/<(img|hr)((?:"[^"]*"|'[^']*'|[^>"'])*)>/gi, (m, tag, attrs) => `<${tag}${attrs.replace(/\/\s*$/, '')}/>`)
  if (unsupported.length) {
    out = out.replace(new RegExp(nonce + '(\\d+)' + nonce, 'g'), (m, i) => unsupported[Number(i)])
  }
  return out
}

function formatHTML(html, doc) {
  if (!doc && typeof document !== 'undefined') doc = inertDocument()
  const BLOCK = new Set(['p','h1','h2','h3','h4','h5','h6',
    'ul','ol','li','blockquote','pre','figure','figcaption',
    'table','thead','tbody','tfoot','tr','th','td','cite','div'])
  const VOID = new Set(['img','br','hr','input','meta','link',
    'wbr','area','base','col','embed','param','source','track'])

  function escapeAttr(v) { return v.replace(/&/g, '&amp;').replace(/"/g, '&quot;') }
  function escapeText(v) { return v.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;') }

  function attrStr(el) {
    return Array.from(el.attributes).map(a => ` ${a.name}="${escapeAttr(a.value)}"`).join('')
  }

  function serialize(node, depth) {
    const pad = '  '.repeat(depth)
    if (node.nodeType === 3) return escapeText(node.textContent)
    if (node.nodeType === 8) return `<!--${node.nodeValue}-->`
    if (node.nodeType !== 1) return ''
    const tag = node.tagName.toLowerCase()
    const at = attrStr(node)
    if (VOID.has(tag)) return `${pad}<${tag}${at}>`
    if (tag === 'pre') return `${pad}<${tag}${at}>${node.innerHTML}</${tag}>`
    const hasBlockChild = [...node.childNodes].some(
      c => c.nodeType === 1 && (BLOCK.has(c.tagName.toLowerCase()) || VOID.has(c.tagName.toLowerCase()))
    )
    if (BLOCK.has(tag) && hasBlockChild) {
      const inner = [...node.childNodes]
        .map(c => serialize(c, depth + 1))
        .filter(s => s.trim() !== '')
        .join('\n')
      return `${pad}<${tag}${at}>\n${inner}\n${pad}</${tag}>`
    }
    // A block tag with no element children at all (pure text content, e.g.
    // EmbedBlock's wrapper div whose text node is a literal '\n'+url+'\n')
    // gets its text trimmed so embedded raw newlines don't push the content
    // and closing tag onto unindented lines below the opening tag.
    const isTextOnly = [...node.childNodes].every(c => c.nodeType !== 1)
    let inner = [...node.childNodes].map(c => serialize(c, 0)).join('')
    if (isTextOnly) inner = inner.trim()
    return BLOCK.has(tag)
      ? `${pad}<${tag}${at}>${inner}</${tag}>`
      : `<${tag}${at}>${inner}</${tag}>`
  }

  const container = doc.createElement('div')
  container.innerHTML = html
  return [...container.childNodes]
    .map(n => serialize(n, 0))
    .filter(s => s.trim() !== '')
    .join('\n\n')
}

// Non-overlapping substring matches for find & replace. Returns JS string
// indices ({ start, end }) on the original text; the editor maps them to
// ProseMirror positions. Query is matched literally (regex chars escaped).
function findMatches(text, query, caseSensitive) {
  if (!query) return []
  const escaped = query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const re = new RegExp(escaped, caseSensitive ? 'g' : 'gi')
  const out = []
  let m
  while ((m = re.exec(text)) !== null) {
    out.push({ start: m.index, end: m.index + m[0].length })
  }
  return out
}

// Build a whitespace-tolerant regex source from a query string. Used for anchor
// navigation (jump-to-finding), where Claude's verbatim "anchor" can disagree
// with the editor text on spacing around punctuation — e.g. the editor holds
// "DSPM , Content" (a flagged readability issue) but Claude returns the cleaned
// "DSPM, Content". The regex collapses each run of query whitespace to `\s+`,
// and lets whitespace around any punctuation char be optional (`\s*` on both
// sides), so spacing differences near commas/periods/etc. no longer break the
// match. Character positions in the searched text are preserved because the
// regex runs against the original text (no normalization that shifts offsets).
function fuzzyAnchorRegex(query) {
  const PUNCT = /[,.;:!?'"“”‘’()[\]{}…—–-]/
  let out = ''
  let pendingSpace = false   // saw whitespace since the last emitted char
  let lastWasPunct = false   // last emitted char was punctuation
  for (const ch of query) {
    if (/\s/.test(ch)) { pendingSpace = true; continue }
    const esc = ch.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    if (PUNCT.test(ch)) {
      out += '\\s*' + esc      // optional whitespace before punctuation
      lastWasPunct = true
    } else {
      if (lastWasPunct) out += '\\s*'        // optional whitespace after punctuation
      else if (pendingSpace) out += '\\s+'   // required gap between plain words
      out += esc
      lastWasPunct = false
    }
    pendingSpace = false
  }
  return out
}

// Like findMatches, but whitespace-tolerant around punctuation (see
// fuzzyAnchorRegex). Used only as an anchor-navigation fallback when the exact
// match fails, so a single best-effort match is sufficient.
function findMatchesLoose(text, query, caseSensitive) {
  if (!query || !query.trim()) return []
  const re = new RegExp(fuzzyAnchorRegex(query), caseSensitive ? 'g' : 'gi')
  const out = []
  let m
  while ((m = re.exec(text)) !== null) {
    out.push({ start: m.index, end: m.index + m[0].length })
    if (m.index === re.lastIndex) re.lastIndex++   // avoid zero-width infinite loop
  }
  return out
}

// Word/character counts for the stats display. Words are whitespace-separated
// tokens; characters are Unicode code points (so emoji count as 1).
function countStats(text) {
  const t = text || ''
  const trimmed = t.trim()
  return {
    words: trimmed ? trimmed.split(/\s+/).length : 0,
    characters: Array.from(t).length,
  }
}

// core/footnotes is a dynamic block: WordPress keeps the footnote bodies in the
// post's `footnotes` meta and renders the <ol> itself, so post_content carries
// only the self-closing delimiter. These two functions are that split and its
// inverse -- the editor edits a real list, the wire format never sees one.

function footnotesComment(root) {
  return Array.from(root.childNodes).find(
    n => n.nodeType === 8 && n.textContent.trim() === 'wp:footnotes /') || null
}

// Returns { content, footnotes, found } -- the list swapped for the delimiter (or dropped
// beside an existing one), the bodies to store in meta, and whether there was a list.
function extractFootnotes(html, doc) {
  doc = doc || inertDocument()
  const div = doc.createElement('div')
  div.innerHTML = html || ''
  const list = div.querySelector('ol.wp-block-footnotes')
  if (!list) return { content: html || '', footnotes: [], found: false }
  const hasDelimiter = footnotesComment(div) !== null

  const footnotes = []
  Array.from(list.children).forEach(li => {
    if (!li.id) return
    li.querySelectorAll('.footnote-backref').forEach(a => a.remove())
    footnotes.push({ id: li.id, content: li.innerHTML.trim() })
  })
  // Spliced out of the string: re-serializing the DOM would undo the save's self-closed <hr/> and <img/>.
  const at = /\s*<ol\b[^>]*\bclass="[^"]*\bwp-block-footnotes\b[^"]*"[^>]*>[\s\S]*?<\/ol>/.exec(html)
  if (!at) {
    if (hasDelimiter) list.remove()
    else list.replaceWith(doc.createComment(' wp:footnotes /'))
    return { content: div.innerHTML, footnotes, found: true }
  }
  const before = html.slice(0, at.index)
  const after = html.slice(at.index + at[0].length)
  if (hasDelimiter) return { content: before + after, footnotes, found: true }
  return { content: before + (before ? '\n\n' : '') + '<!-- wp:footnotes /-->' + after, footnotes, found: true }
}

// Rebuilds the editable list from meta. A post whose meta is empty keeps the
// bare delimiter, which wrapUnsupportedBlocks then preserves as a card.
function inlineFootnotes(html, footnotes, doc) {
  doc = doc || inertDocument()
  if (!Array.isArray(footnotes) || footnotes.length === 0) return html || ''
  const div = doc.createElement('div')
  div.innerHTML = html || ''
  const comment = footnotesComment(div)
  if (!comment) return html || ''

  const ol = doc.createElement('ol')
  ol.className = 'wp-block-footnotes'
  footnotes.forEach(fn => {
    if (!fn || !fn.id) return
    const li = doc.createElement('li')
    li.id = fn.id
    li.innerHTML = fn.content || ''
    ol.appendChild(li)
  })
  // Spliced into the string, as extractFootnotes splices it out: re-serializing the post would
  // rewrite the unsupported-block source that must be saved byte for byte.
  const delimiters = Array.from(html.matchAll(/<!--\s*wp:footnotes \/\s*-->/g)).filter(m => liesOutsideTags(html, m.index))
  const comments = []
  const SHOW_COMMENT = 128
  const walker = doc.createTreeWalker(div, SHOW_COMMENT)
  while (walker.nextNode()) if (walker.currentNode.textContent.trim() === 'wp:footnotes /') comments.push(walker.currentNode)
  const at = delimiters.length === comments.length ? delimiters[comments.indexOf(comment)] : null
  if (!at) {
    comment.replaceWith(ol)
    return div.innerHTML
  }
  return html.slice(0, at.index) + ol.outerHTML + html.slice(at.index + at[0].length)
}

// False when index falls inside a tag (an attribute value), a comment, or a raw-text element's contents.
function liesOutsideTags(html, index) {
  const token = /<!--[\s\S]*?(?:--!?>|$)|<(script|style|textarea|title|xmp|iframe|noembed|noframes)\b(?:"[^"]*"|'[^']*'|[^'">])*>[\s\S]*?(?:<\/\1\s*>|$)|<[A-Za-z\/!?](?:"[^"]*"|'[^']*'|[^'">])*>?/gi
  let m
  while ((m = token.exec(html)) && m.index < index) {
    if (m.index + m[0].length > index) return false
  }
  return true
}

// ── Paste cleanup (docs/paste.md) ─────────────────

const PASTE_DROP = 'script, style, meta, link, title, xml, noscript, template, object, embed, applet, ' +
  'input, select, textarea, option, svg, canvas, map, head, ' +
  // Text a sighted reader never sees; aria-hidden text is the reverse, visible and kept.
  '[class*="screen-reader-text"], [class*="visually-hidden"], [class*="sr-only"]'

const PASTE_KEEP_CLASS = /^(?:wp-block-[\w-]+|wp-element-[\w-]+|wp-image-\d+|wp-embed-aspect-[\w-]+|wp-has-aspect-ratio|has-[\w-]+|is-style-[\w-]+|is-resized|is-cropped|is-open|is-not-stacked-on-mobile|is-type-[\w-]+|is-provider-[\w-]+|align(?:left|right|center|wide|full|none)|size-[\w-]+|columns-\d+|language-[\w-]+|fn)$/

// Classes the front end adds when it renders a block; saved markup never has them.
const PASTE_RENDER_CLASS = /(?:^|-)is-layout-|^wp-container-|^wp-elements-|^wp-block-post-|^wp-block-paragraph$|^is-content-justification-|^has-global-padding$|^has-text-align-(?:start|end|justify)$/

const PASTE_KEEP_ATTRS = {
  A: ['href', 'target', 'rel', 'title'],
  IMG: ['src', 'alt', 'title', 'width', 'height'],
  TD: ['colspan', 'rowspan', 'data-align'],
  TH: ['colspan', 'rowspan', 'scope', 'data-align'],
  OL: ['start', 'reversed'],
  LI: ['id'],
  H1: ['id'], H2: ['id'], H3: ['id'], H4: ['id'], H5: ['id'], H6: ['id'],
  DETAILS: ['open', 'name'],
  VIDEO: ['src', 'controls'],
  AUDIO: ['src', 'controls'],
  SUP: ['data-fn'],
  ABBR: ['title'],
  TIME: ['datetime'],
}

const PASTE_BLOCK_TAGS = new Set(['P', 'DIV', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'UL', 'OL', 'LI', 'BLOCKQUOTE',
  'PRE', 'TABLE', 'FIGURE', 'HR', 'DETAILS', 'DL', 'SECTION', 'ARTICLE', 'HEADER', 'FOOTER', 'MAIN', 'ASIDE',
  'NAV', 'ADDRESS', 'FIELDSET', 'FORM'])

const PASTE_MONO_FONT = /monospace|menlo|monaco|consolas|courier|sf mono|source code|fira code|jetbrains mono/i

function cleanPastedHTML(html, doc) {
  if (!doc && typeof document !== 'undefined') doc = inertDocument()
  const root = doc.createElement('div')
  root.innerHTML = html

  const keepStyle = new Set()
  const listFormats = wordListFormats(root)
  removePasteChrome(root)
  // A copy button is chrome; any other button's label is content (MDN puts version numbers in them).
  root.querySelectorAll('button').forEach(b => {
    if (/\bcop(?:y|ied)\b|clipboard/i.test(b.textContent + ' ' + (b.getAttribute('aria-label') || '') + ' ' + (b.getAttribute('title') || ''))) b.remove()
    else unwrapElement(b)
  })
  // Core's table cells and list items hold text, not image blocks.
  root.querySelectorAll('td img, th img, li img').forEach(img => img.replaceWith(doc.createTextNode(img.getAttribute('alt') || '')))
  root.querySelectorAll('span.Apple-converted-space').forEach(s => s.replaceWith(doc.createTextNode(' ')))
  unwrapPasteWrappers(root)
  convertWordLists(root, listFormats, keepStyle)
  normalizePastedCode(root, doc)
  convertPastedMedia(root, doc)
  root.querySelectorAll('img:not([alt])').forEach(img => img.setAttribute('alt', ''))
  // The front end appends a back-link to each footnote; Quill draws its own.
  root.querySelectorAll('ol.wp-block-footnotes li a').forEach(a => { if (/^[\s\u21a9\ufe0e\ufe0f]*$/.test(a.textContent)) a.remove() })
  root.querySelectorAll('img.emoji, img.wp-smiley').forEach(img => img.replaceWith(doc.createTextNode(img.getAttribute('alt') || '')))
  pasteStylesToTags(root, doc)
  convertPastedAlignment(root)
  flattenPastedCells(root, doc)
  convertPresetClasses(root)
  convertDefinitionLists(root, doc)
  stripPasteAttributes(root, keepStyle)
  unwrapAll(root, 'span:not([class]):not([style]), font, a:not([href])')
  pushLinksIntoBlocks(root)
  flattenPastedDivs(root, doc)
  hoistBlockImages(root, doc)
  removeEmptyPastedBlocks(root)
  return root.innerHTML.trim()
}

function unwrapElement(el) {
  el.replaceWith(...Array.from(el.childNodes))
}

function unwrapAll(root, selector) {
  Array.from(root.querySelectorAll(selector)).reverse().forEach(unwrapElement)
}

function removePasteChrome(root) {
  root.querySelectorAll(PASTE_DROP + ', br.Apple-interchange-newline').forEach(el => el.remove())
  root.querySelectorAll('[style]').forEach(el => {
    const style = el.getAttribute('style')
    if (/display:\s*none|mso-hide:\s*all|mso-element:\s*comment/i.test(style)) el.remove()
  })
  // Only an image the page can read survives: a local file:// or cid: source is unreachable once pasted.
  root.querySelectorAll('img').forEach(img => { if (!/^\s*(?:https?:|data:image\/|blob:|\/)/i.test(img.getAttribute('src') || '')) img.remove() })
  // Block delimiters survive; Word's conditional comments and everything else do not.
  const walker = root.ownerDocument.createTreeWalker(root, 128)
  const comments = []
  while (walker.nextNode()) comments.push(walker.currentNode)
  comments.forEach(c => { if (!/^\s*\/?wp:/.test(c.data)) c.remove() })
  root.querySelectorAll('*').forEach(el => {
    for (const attr of Array.from(el.attributes)) {
      if (attr.name.startsWith('data-quill-')) el.removeAttribute(attr.name)
    }
  })
}

function unwrapPasteWrappers(root) {
  // WebKit wraps a selection holding an open <details> in a second one with no summary.
  unwrapAll(root, 'details:not(:has(> summary))')
  // HTML's <details> is core/details, its attributes in core's order since the carrier keeps source order.
  root.querySelectorAll('details').forEach(d => {
    const name = d.getAttribute('name')
    const open = d.hasAttribute('open')
    d.removeAttribute('name')
    d.removeAttribute('open')
    d.classList.add('wp-block-details')
    if (name !== null) d.setAttribute('name', name)
    if (open) d.setAttribute('open', '')
  })
  // Google Docs wraps the whole selection in a <b> that is explicitly not bold.
  unwrapAll(root, 'b[id^="docs-internal-guid"]')
  // Word's bookmarks and its footnote and comment anchors point nowhere once pasted.
  unwrapAll(root, 'a[name]:not([href]), a[href^="#_ftn"], a[href^="#_edn"], a[href^="#_msocom"]')
  root.querySelectorAll('*').forEach(el => { if (el.tagName === 'O:P' || el.tagName.startsWith('V:')) el.remove() })
  // Quill's cite is a quote's citation block; an inline <cite> (a reference, a title) is just its text.
  Array.from(root.querySelectorAll('cite')).reverse().forEach(c => { if (!c.parentElement || c.parentElement.tagName !== 'BLOCKQUOTE') unwrapElement(c) })
}

// Word lists: one paragraph per item, level and list id in `mso-list`, format in the <style>.
function wordListFormats(root) {
  const formats = {}
  root.querySelectorAll('style').forEach(style => {
    const re = /@list\s+(l\d+):level(\d+)\s*\{([^}]*)\}/g
    let m
    while ((m = re.exec(style.textContent))) {
      const format = /mso-level-number-format:\s*([\w-]+)/.exec(m[3])
      formats[`${m[1]}:${m[2]}`] = format ? format[1] : 'decimal'
    }
  })
  return formats
}

const WORD_LIST_TYPE = { 'alpha-lower': 'lower-alpha', 'alpha-upper': 'upper-alpha', 'roman-lower': 'lower-roman', 'roman-upper': 'upper-roman' }

function wordListMarker(el) {
  const marker = Array.from(el.querySelectorAll('span')).find(s => /mso-list:\s*ignore/i.test(s.getAttribute('style') || ''))
  const text = marker ? marker.textContent.replace(/[\s ]+/g, ' ').trim() : ''
  if (marker) marker.remove()
  return text
}

function wordListFormatFromMarker(text) {
  if (/^\d+[.)]?$/.test(text)) return 'decimal'
  if (/^[ivxlc]+[.)]$/.test(text)) return 'roman-lower'
  if (/^[IVXLC]+[.)]$/.test(text)) return 'roman-upper'
  if (/^[a-z][.)]$/.test(text)) return 'alpha-lower'
  if (/^[A-Z][.)]$/.test(text)) return 'alpha-upper'
  return 'bullet'
}

function convertWordLists(root, formats, keepStyle) {
  const isItem = el => /mso-list:\s*l\d+\s+level\d+/i.test(el.getAttribute('style') || '')
  const items = Array.from(root.querySelectorAll('p, h1, h2, h3, h4, h5, h6, div')).filter(isItem)
  const done = new Set()
  for (const first of items) {
    if (done.has(first)) continue
    const run = [first]
    for (let next = first.nextElementSibling; next && isItem(next); next = next.nextElementSibling) run.push(next)
    run.forEach(el => done.add(el))
    buildWordList(run, formats, keepStyle)
  }
}

function buildWordList(run, formats, keepStyle) {
  const doc = run[0].ownerDocument
  const stack = []
  const tops = []
  for (const p of run) {
    const [, id, levelText] = /mso-list:\s*(l\d+)\s+level(\d+)/i.exec(p.getAttribute('style'))
    const level = parseInt(levelText, 10)
    const markerText = wordListMarker(p)
    const format = formats[`${id}:${level}`] || wordListFormatFromMarker(markerText)
    const ordered = format !== 'bullet' && format !== 'image' && format !== 'none'
    while (stack.length && stack[stack.length - 1].level > level) stack.pop()
    const top = stack[stack.length - 1]
    if (top && top.level === level && (top.id !== id || top.ordered !== ordered)) stack.pop()
    if (!stack.length || stack[stack.length - 1].level < level) {
      const list = doc.createElement(ordered ? 'ol' : 'ul')
      const type = WORD_LIST_TYPE[format]
      if (type) {
        list.setAttribute('style', `list-style-type:${type}`)
        list.setAttribute('data-quill-block-attrs', JSON.stringify({ ordered: true, type }))
        keepStyle.add(list)
      }
      const start = ordered && format === 'decimal' ? parseInt(markerText, 10) : NaN
      if (start > 1) list.setAttribute('start', String(start))
      const parent = stack[stack.length - 1]
      if (parent) {
        let li = parent.list.lastElementChild
        if (!li) { li = doc.createElement('li'); parent.list.appendChild(li) }
        li.appendChild(list)
      } else {
        tops.push(list)
      }
      stack.push({ level, id, ordered, list })
    }
    const li = doc.createElement('li')
    while (p.firstChild) li.appendChild(p.firstChild)
    stack[stack.length - 1].list.appendChild(li)
  }
  run[0].before(...tops)
  run.forEach(p => p.remove())
}

// Code: one <pre><code> holding only the code's text, whatever chrome the source drew around it.
function normalizePastedCode(root, doc) {
  const isCodeBox = el => {
    const style = el.getAttribute('style') || ''
    return /white-space:\s*pre/i.test(style) && PASTE_MONO_FONT.test(style)
  }
  Array.from(root.querySelectorAll('div, p')).filter(isCodeBox).forEach(el => {
    if (el.closest('pre')) return
    for (let up = el.parentElement; up && up !== root; up = up.parentElement) if (isCodeBox(up)) return
    const pre = doc.createElement('pre')
    const code = doc.createElement('code')
    code.textContent = textWithBreaks(el)
    pre.appendChild(code)
    el.replaceWith(pre)
  })
  root.querySelectorAll('pre').forEach(pre => {
    const inner = pre.querySelector('code')
    const lang = inner && Array.from(inner.classList).find(c => /^language-[\w-]+$/.test(c))
    const code = doc.createElement('code')
    if (lang) code.className = lang
    code.textContent = textWithBreaks(inner || pre)
    pre.replaceChildren(code)
    if (lang) removeLanguageLabel(root, pre, lang.slice('language-'.length))
  })
  root.querySelectorAll('span, font').forEach(el => {
    if (el.closest('pre, code')) return
    const font = (el.getAttribute('style') || '') + ' ' + (el.getAttribute('face') || '')
    if (!/font-family/i.test(font) && !el.hasAttribute('face')) return
    if (!PASTE_MONO_FONT.test(font) || !el.textContent.trim()) return
    const code = doc.createElement('code')
    code.textContent = el.textContent
    el.replaceWith(code)
  })
}

function textWithBreaks(el) {
  let out = ''
  const walk = node => {
    if (node.nodeType === 3) { out += node.data; return }
    if (node.nodeType !== 1) return
    if (node.tagName === 'BR') { out += '\n'; return }
    const block = /^(?:DIV|P|LI|TR|H[1-6])$/.test(node.tagName)
    if (block && out && !out.endsWith('\n')) out += '\n'
    node.childNodes.forEach(walk)
    if (block && out && !out.endsWith('\n')) out += '\n'
  }
  el.childNodes.forEach(walk)
  return out.replace(/ /g, ' ').replace(/\n+$/, '')
}

// Chat apps label a code block with its language just above it.
function removeLanguageLabel(root, pre, lang) {
  let el = pre
  for (let depth = 0; depth < 4 && el && el !== root; depth++, el = el.parentElement) {
    for (let sib = el.previousElementSibling, seen = 0; sib && seen < 3; sib = sib.previousElementSibling, seen++) {
      const text = sib.textContent.trim().toLowerCase()
      if (!text) continue
      if (text === lang.toLowerCase() && !sib.querySelector('img, pre, table, ul, ol')) sib.remove()
      return
    }
  }
}

// An embedded player's src, back to the page URL WordPress embeds from.
function embedURLFromFrame(src) {
  let url
  try { url = new URL(src, 'https://example.com') } catch (_) { return null }
  const host = url.hostname.replace(/^www\./, '')
  let m
  if ((host === 'youtube.com' || host === 'youtube-nocookie.com') && (m = url.pathname.match(/^\/embed\/([\w-]{6,})/))) return `https://www.youtube.com/watch?v=${m[1]}`
  if (host === 'player.vimeo.com' && (m = url.pathname.match(/^\/video\/(\d+)/))) return `https://vimeo.com/${m[1]}`
  if (host === 'open.spotify.com' && (m = url.pathname.match(/^\/embed\/(\w+)\/(\w+)/))) return `https://open.spotify.com/${m[1]}/${m[2]}`
  return null
}

function embedFigure(doc, url, caption) {
  const figure = doc.createElement('figure')
  figure.className = embedClassFor(url)
  const wrapper = doc.createElement('div')
  wrapper.className = 'wp-block-embed__wrapper'
  wrapper.textContent = `\n${url}\n`
  figure.appendChild(wrapper)
  if (caption) figure.appendChild(caption)
  return figure
}

function convertPastedMedia(root, doc) {
  root.querySelectorAll('iframe').forEach(frame => {
    const url = embedURLFromFrame(frame.getAttribute('src') || '')
    const figure = frame.closest('figure')
    const target = figure || frame
    if (!url) { target.remove(); return }
    const caption = figure && figure.querySelector('figcaption')
    target.replaceWith(embedFigure(doc, url, caption))
  })
  root.querySelectorAll('figure.wp-block-embed').forEach(figure => {
    const wrapper = figure.querySelector('.wp-block-embed__wrapper')
    const url = wrapper && wrapper.textContent.trim()
    if (!url || !/^https?:\/\//.test(url)) figure.remove()
  })
  // core/video and core/audio have no Quill node; with their delimiters they are preserved as blocks.
  root.querySelectorAll('video, audio').forEach(media => {
    const kind = media.tagName.toLowerCase()
    const source = media.getAttribute('src') || (media.querySelector('source[src]') || { getAttribute: () => '' }).getAttribute('src')
    const figure = media.closest('figure')
    const target = figure || media
    if (!/^https?:\/\//.test(source || '')) { target.remove(); return }
    const out = doc.createElement('figure')
    out.className = `wp-block-${kind}`
    const player = doc.createElement(kind)
    player.setAttribute('controls', '')
    player.setAttribute('src', source)
    out.appendChild(player)
    const caption = figure && figure.querySelector('figcaption')
    if (caption) out.appendChild(caption)
    target.replaceWith(doc.createComment(` wp:${kind} `), out, doc.createComment(` /wp:${kind} `))
  })
}

// Formatting a source drew with CSS becomes the tag Quill models, before the CSS goes.
function pasteStylesToTags(root, doc) {
  Array.from(root.querySelectorAll('b, strong')).reverse().forEach(el => {
    if (/^(?:normal|lighter|[1-4]00)$/.test(el.style.fontWeight)) unwrapElement(el)
  })
  root.querySelectorAll('span, font').forEach(el => {
    const s = el.style
    const wraps = []
    const weight = s.fontWeight
    if ((weight === 'bold' || weight === 'bolder' || parseInt(weight, 10) >= 600) && !el.closest('b, strong, h1, h2, h3, h4, h5, h6, th')) wraps.push('strong')
    if (/italic|oblique/.test(s.fontStyle) && !el.closest('i, em')) wraps.push('em')
    const decoration = `${s.textDecoration} ${s.textDecorationLine}`
    if (/line-through/.test(decoration) && !el.closest('s, del, strike')) wraps.push('s')
    if (/underline/.test(decoration) && !el.closest('u, a')) wraps.push('u')
    if (s.verticalAlign === 'super' && !el.closest('sup')) wraps.push('sup')
    if (s.verticalAlign === 'sub' && !el.closest('sub')) wraps.push('sub')
    for (const tag of wraps) {
      const wrap = doc.createElement(tag)
      while (el.firstChild) wrap.appendChild(el.firstChild)
      el.appendChild(wrap)
    }
  })
}

function pasteAlignment(el) {
  const value = String(el.style.textAlign || el.getAttribute('align') || '').toLowerCase()
  return /^(?:left|center|right)$/.test(value) ? value : null
}

// Core's own paste handler turns text-align into these; Word puts a cell's alignment on its paragraph.
function convertPastedAlignment(root) {
  root.querySelectorAll('td, th').forEach(cell => {
    const only = cell.children.length === 1 && /^(?:P|DIV)$/.test(cell.firstElementChild.tagName) ? cell.firstElementChild : null
    const align = pasteAlignment(cell) || (only && pasteAlignment(only))
    if (align) {
      cell.classList.add('has-text-align-' + align)
      cell.setAttribute('data-align', align)
    }
    // Core writes class and data-align ahead of scope and spans; the carrier keeps source order.
    for (const name of ['scope', 'colspan', 'rowspan']) {
      if (!cell.hasAttribute(name)) continue
      const value = cell.getAttribute(name)
      cell.removeAttribute(name)
      cell.setAttribute(name, value)
    }
  })
  root.querySelectorAll('p, h1, h2, h3, h4, h5, h6').forEach(el => {
    if (el.closest('td, th, li')) return
    const fromClass = /(?:^|\s)has-text-align-(center|right)(?:\s|$)/.exec(el.className)
    const align = pasteAlignment(el) || (fromClass && fromClass[1])
    if (align !== 'center' && align !== 'right') return
    el.classList.add('has-text-align-' + align)
    el.setAttribute('data-quill-block-attrs', JSON.stringify({ style: { typography: { textAlign: align } } }))
  })
}

// Core's table cells are rich text, so blocks inside a pasted cell become lines.
function flattenPastedCells(root, doc) {
  const linesOf = container => {
    const lines = []
    let current = []
    const flush = () => {
      if (current.some(n => n.nodeType === 1 || n.textContent.trim())) lines.push(current)
      current = []
    }
    for (const node of Array.from(container.childNodes)) {
      if (node.nodeType !== 1) { current.push(node); continue }
      if (node.tagName === 'BR') { flush(); continue }
      if (node.tagName === 'TABLE') {
        flush()
        node.querySelectorAll('tr').forEach(tr => {
          const text = Array.from(tr.children).map(c => c.textContent.trim()).filter(Boolean).join(' ')
          if (text) lines.push([doc.createTextNode(text)])
        })
        continue
      }
      if (PASTE_BLOCK_TAGS.has(node.tagName)) { flush(); lines.push(...linesOf(node)); continue }
      current.push(node)
    }
    flush()
    return lines
  }
  Array.from(root.querySelectorAll('td, th')).reverse().forEach(cell => {
    const blocks = Array.from(cell.children).filter(c => PASTE_BLOCK_TAGS.has(c.tagName))
    if (!blocks.length || (cell.children.length === 1 && blocks[0].tagName === 'P')) return
    const lines = linesOf(cell)
    cell.replaceChildren(...lines.flatMap((line, i) => (i ? [doc.createElement('br'), ...line] : line)))
  })
}

// A preset class becomes the delimiter attribute core draws it from, keys in core's order.
function convertPresetClasses(root) {
  root.querySelectorAll('p, h1, h2, h3, h4, h5, h6, ul, ol, blockquote').forEach(el => {
    const attrs = {}
    for (const c of el.classList) {
      let m
      if ((m = /^has-([\w-]+)-background-color$/.exec(c))) attrs.backgroundColor = m[1]
      else if ((m = /^has-([\w-]+)-gradient-background$/.exec(c))) attrs.gradient = m[1]
      else if ((m = /^has-([\w-]+)-font-size$/.exec(c))) attrs.fontSize = m[1]
      else if ((m = /^has-([\w-]+)-font-family$/.exec(c))) attrs.fontFamily = m[1]
      else if ((m = /^has-([\w-]+)-color$/.exec(c)) && !/^(?:text|link|background|inline|border)$/.test(m[1])) attrs.textColor = m[1]
    }
    if (!Object.keys(attrs).length) return
    const carried = JSON.parse(el.getAttribute('data-quill-block-attrs') || '{}')
    const ordered = {}
    for (const key of ['backgroundColor', 'textColor', 'gradient', 'fontFamily', 'fontSize']) if (attrs[key]) ordered[key] = attrs[key]
    el.setAttribute('data-quill-block-attrs', JSON.stringify({ ...ordered, ...carried }))
  })
}

function convertDefinitionLists(root, doc) {
  root.querySelectorAll('dt, dd').forEach(item => {
    // An item that already holds paragraphs keeps them; wrapping them would nest a <p> in a <p>.
    if (Array.from(item.children).some(c => PASTE_BLOCK_TAGS.has(c.tagName))) { unwrapElement(item); return }
    const p = doc.createElement('p')
    if (item.tagName === 'DT') {
      const strong = doc.createElement('strong')
      while (item.firstChild) strong.appendChild(item.firstChild)
      p.appendChild(strong)
    } else {
      while (item.firstChild) p.appendChild(item.firstChild)
    }
    item.replaceWith(p)
  })
  unwrapAll(root, 'dl')
}

// Core's inline colour: a transparent background, and a colour only when no preset class names one.
function normalizeInlineColor(mark) {
  const background = mark.style.backgroundColor || 'rgba(0, 0, 0, 0)'
  const preset = Array.from(mark.classList).some(c => /^has-[\w-]+-color$/.test(c) && c !== 'has-inline-color')
  const color = mark.style.color
  mark.setAttribute('style', `background-color:${background}` + (!preset && color ? `;color:${color}` : ''))
}

function stripPasteAttributes(root, keepStyle) {
  root.querySelectorAll('mark.has-inline-color').forEach(normalizeInlineColor)
  root.querySelectorAll('*').forEach(el => {
    // Only a footnote entry needs its id; anywhere else it becomes a stray anchor.
    let keep = el.tagName === 'LI' && !el.closest('ol.wp-block-footnotes') ? [] : PASTE_KEEP_ATTRS[el.tagName] || []
    if (el.tagName === 'A' && el.closest('sup[data-fn]')) keep = [...keep, 'id']
    const inlineColor = el.tagName === 'MARK' && el.classList.contains('has-inline-color')
    for (const attr of Array.from(el.attributes)) {
      const name = attr.name
      if (name === 'class') continue
      if (name === 'style' && (keepStyle.has(el) || inlineColor)) continue
      if (name === 'data-quill-block-attrs') continue
      if (keep.includes(name) && !(name === 'href' && /^\s*(?:javascript|vbscript|data):/i.test(attr.value))) continue
      el.removeAttribute(name)
    }
    if (el.hasAttribute('class')) {
      const kept = Array.from(el.classList).filter(c => PASTE_KEEP_CLASS.test(c) && !PASTE_RENDER_CLASS.test(c))
      if (kept.length) el.setAttribute('class', kept.join(' '))
      else el.removeAttribute('class')
    }
  })
}

function keepsPastedDiv(div) {
  if (div.closest('figure')) return true
  return Array.from(div.classList).some(c => c.startsWith('wp-block-') &&
    blockDescriptorRegistry.modelsBlockName('core/' + c.slice('wp-block-'.length)))
}

// A link around blocks (a card) becomes the same link inside each innermost block.
function pushLinksIntoBlocks(root) {
  const isBlock = el => PASTE_BLOCK_TAGS.has(el.tagName)
  Array.from(root.querySelectorAll('a[href]')).reverse().forEach(a => {
    const blocks = Array.from(a.querySelectorAll('*')).filter(el => isBlock(el) && !Array.from(el.children).some(isBlock))
    if (!blocks.length) return
    for (const block of blocks) {
      const link = a.cloneNode(false)
      link.append(...Array.from(block.childNodes))
      block.appendChild(link)
    }
    unwrapElement(a)
  })
}

// A div is either a block Quill models, a wrapper around blocks, or a line of text.
function flattenPastedDivs(root, doc) {
  const wrappers = new Set(['DIV', 'SECTION', 'ARTICLE', 'HEADER', 'FOOTER', 'MAIN', 'ASIDE', 'NAV', 'ADDRESS', 'FIELDSET', 'FORM', 'CENTER'])
  // Custom elements (a hyphen in the tag) are a site's own wrappers, inline or block.
  const custom = el => el.tagName.includes('-')
  Array.from(root.querySelectorAll('*')).filter(el => wrappers.has(el.tagName) || custom(el)).reverse().forEach(div => {
    if (custom(div)) { unwrapElement(div); return }
    if (div.tagName === 'DIV' && keepsPastedDiv(div)) return
    const hasBlock = Array.from(div.children).some(c => PASTE_BLOCK_TAGS.has(c.tagName))
    if (!hasBlock) {
      if (!div.textContent.trim() && !div.querySelector('img')) { div.remove(); return }
      const p = doc.createElement('p')
      while (div.firstChild) p.appendChild(div.firstChild)
      div.replaceWith(p)
      return
    }
    let run = null
    Array.from(div.childNodes).forEach(node => {
      if (node.nodeType === 1 && PASTE_BLOCK_TAGS.has(node.tagName)) { run = null; return }
      if (node.nodeType === 3 && !node.data.trim() && !run) { node.remove(); return }
      if (!run) { run = doc.createElement('p'); node.before(run) }
      run.appendChild(node)
    })
    unwrapElement(div)
  })
}

// An image is a block in Quill; left inside a <p>, the parser splits the <p> and leaves an empty one behind.
function hoistBlockImages(root, doc) {
  root.querySelectorAll('p').forEach(p => {
    if (!p.querySelector('img, figure')) return
    const parts = []
    let run = doc.createElement('p')
    const flush = () => {
      if (run.textContent.trim()) parts.push(run)
      run = doc.createElement('p')
    }
    Array.from(p.childNodes).forEach(child => {
      const isImage = child.nodeName === 'IMG' || child.nodeName === 'FIGURE' ||
        (child.nodeName === 'A' && child.querySelector('img') && !child.textContent.trim())
      if (isImage) { flush(); parts.push(child) }
      else run.appendChild(child)
    })
    flush()
    p.replaceWith(...parts)
  })
}

function removeEmptyPastedBlocks(root) {
  root.querySelectorAll('p, h1, h2, h3, h4, h5, h6').forEach(el => {
    if (el.querySelector('img, figure, iframe, video, audio')) return
    if (!el.textContent.replace(/[\s ​]/g, '')) el.remove()
  })
  // Whitespace between blocks becomes a blank paragraph; between inline runs it is a word space.
  const isBlock = n => n && n.nodeType === 1 && PASTE_BLOCK_TAGS.has(n.tagName)
  Array.from(root.childNodes).forEach(node => {
    const betweenBlocks = isBlock(node.previousSibling) || isBlock(node.nextSibling)
    if ((node.nodeName === 'BR' || (node.nodeType === 3 && !node.data.trim())) && betweenBlocks) node.remove()
  })
}

// Blocks pasted into a list item become further items, as the block editor pastes them.
function pastedBlocksAsListItems(html, doc) {
  if (!doc && typeof document !== 'undefined') doc = inertDocument()
  const root = doc.createElement('div')
  root.innerHTML = html
  const blocks = Array.from(root.children)
  const strayText = Array.from(root.childNodes).some(n => n.nodeType === 3 && n.data.trim())
  if (strayText || blocks.length === 0) return html
  if (blocks.length === 1 && !/^(?:UL|OL|BLOCKQUOTE)$/.test(blocks[0].tagName)) return html
  if (!blocks.every(el => /^(?:P|H[1-6]|UL|OL|BLOCKQUOTE)$/.test(el.tagName))) return html
  const list = doc.createElement('ul')
  const item = from => {
    const li = doc.createElement('li')
    li.append(...Array.from(from.childNodes))
    list.appendChild(li)
  }
  const add = el => {
    if (el.tagName === 'UL' || el.tagName === 'OL') Array.from(el.children).forEach(li => list.appendChild(li))
    else if (el.tagName === 'BLOCKQUOTE' && Array.from(el.childNodes).every(n =>
      (n.nodeType === 3 && !n.data.trim()) || /^(?:P|H[1-6]|UL|OL|BLOCKQUOTE|CITE)$/.test(n.nodeName))) Array.from(el.children).forEach(add)
    else item(el)
  }
  blocks.forEach(add)
  return list.outerHTML
}

// Embed provider table. `aspect: true` providers get Gutenberg's 16:9 classes.
const EMBED_PROVIDERS = [
  { slug: 'youtube',    type: 'video', aspect: true,  hosts: ['youtube.com', 'www.youtube.com', 'm.youtube.com', 'youtu.be'] },
  { slug: 'vimeo',      type: 'video', aspect: true,  hosts: ['vimeo.com', 'www.vimeo.com', 'player.vimeo.com'] },
  { slug: 'twitter',    type: 'rich',  aspect: false, hosts: ['twitter.com', 'www.twitter.com', 'x.com', 'www.x.com'] },
  { slug: 'spotify',    type: 'rich',  aspect: false, hosts: ['open.spotify.com', 'spotify.com'] },
  { slug: 'soundcloud', type: 'rich',  aspect: false, hosts: ['soundcloud.com', 'www.soundcloud.com'] },
  { slug: 'tiktok',     type: 'video', aspect: false, hosts: ['tiktok.com', 'www.tiktok.com'] },
  { slug: 'instagram',  type: 'rich',  aspect: false, hosts: ['instagram.com', 'www.instagram.com'] },
]

function detectEmbedProvider(url) {
  let host
  try { host = new URL(url).hostname.toLowerCase() } catch (_) { return null }
  for (const p of EMBED_PROVIDERS) {
    if (p.hosts.includes(host)) return p
  }
  return null
}

// Gutenberg figure class for an embed URL — class order matches what the
// block editor emits. Unknown providers get the bare class; WordPress still
// resolves those via oEmbed at render time.
function embedClassFor(url) {
  const p = detectEmbedProvider(url)
  if (!p) return 'wp-block-embed'
  let cls = `wp-block-embed is-type-${p.type} is-provider-${p.slug} wp-block-embed-${p.slug}`
  if (p.aspect) cls += ' wp-embed-aspect-16-9 wp-has-aspect-ratio'
  return cls
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { extractAlignment, toWordPressHTML, serializeAttributes, mergeClassNames, mergeCarried, blockSourceSlices, blockNeedsWrapping, wrapUnsupportedBlocks, customHTMLBlock, customHTMLSource, unrepresentedBlockNames, countBlockNames, formatHTML, countStats, findMatches, findMatchesLoose, fuzzyAnchorRegex, detectEmbedProvider, embedClassFor, passthroughLabelFromClass, passthroughLabelFromBlockName, parsePassthroughBlock, isModeledFigure, QUILL_MODELED_FIGURE_CLASSES, extractFootnotes, inlineFootnotes, cleanPastedHTML, embedURLFromFrame, pastedBlocksAsListItems }
}
