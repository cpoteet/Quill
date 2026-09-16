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

const blockSerializer = (typeof module !== 'undefined' && module.exports)
  ? require('./block-serializer.js')
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

// A carried key keeps the position WordPress gave it; see Resources/CLAUDE.md.
function overlayCarried(carried, attrs, ownedKeys) {
  const owned = new Set(ownedKeys || [])
  const next = attrs || {}
  const out = {}
  for (const key of Object.keys(carried || {})) {
    if (key in next) out[key] = next[key]
    else if (!owned.has(key)) out[key] = carried[key]
  }
  for (const key of Object.keys(next)) if (!(key in out)) out[key] = next[key]
  return out
}

function delimiterAttrs(attrs) {
  return Object.keys(attrs).length ? ' ' + blockSerializer.serializeAttributes(attrs) : ''
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

// Given a wp-block-* classed element that gutenbergPassthrough's parse rule
// matched, extracts what's needed to preserve and re-display it. Returns null
// if `el` has no wp-block-* class at all, or if any of its wp-block-* classes
// names a block Quill models natively (which must go to its own node instead).
//
// Checks for immediately-adjacent `<!-- wp:name --> / <!-- /wp:name -->`
// comment siblings (skipping whitespace-only text nodes in between, since
// real Gutenberg source has a newline between a comment and its element).
// Each top-level block paired with a literal slice of `html` where the
// original continues with exactly the serialised bytes, otherwise with the
// serialisation itself. The parser exposes no byte offsets, so the cursor
// walk is what turns a reconstruction into a byte-for-byte copy.
// WordPress's own delimiter pattern, rescanned here because parse() has no offsets.
const BLOCK_DELIMITER = /<!--\s+(\/)?wp:([a-z][a-z0-9_-]*\/)?([a-z][a-z0-9_-]*)\s+({(?:(?!}\s+\/?-->).)*}\s+)?(\/)?-->/g

// Byte ranges of the top-level blocks, or null when the delimiters do not nest.
function topLevelBlockRanges(html) {
  const ranges = []
  let depth = 0
  let start = -1
  let name = null
  BLOCK_DELIMITER.lastIndex = 0
  let match
  while ((match = BLOCK_DELIMITER.exec(html)) !== null) {
    const blockName = (match[2] || 'core/') + match[3]
    if (match[5]) {
      if (depth === 0) ranges.push({ blockName, start: match.index, end: match.index + match[0].length })
      continue
    }
    if (match[1]) {
      if (depth === 0) return null
      depth -= 1
      if (depth === 0) {
        ranges.push({ blockName: name, start, end: match.index + match[0].length })
        start = -1
        name = null
      }
      continue
    }
    if (depth === 0) {
      start = match.index
      name = blockName
    }
    depth += 1
  }
  return depth === 0 && start === -1 ? ranges : null
}

function blockSourceSlices(html, parse, serializeBlock) {
  const blocks = parse(html)
  const attrsOf = block => block.attrs && Object.keys(block.attrs).length ? JSON.stringify(block.attrs) : null
  const ranges = topLevelBlockRanges(html)
  const named = blocks.filter(b => b.blockName)
  const agrees = ranges && ranges.length === named.length &&
    ranges.every((r, i) => r.blockName === named[i].blockName)

  if (agrees) {
    const out = []
    let cursor = 0
    let next = 0
    for (const block of blocks) {
      if (!block.blockName) {
        const end = next < ranges.length ? ranges[next].start : html.length
        out.push({ blockName: null, attrsJSON: null, source: html.slice(cursor, end), exact: true })
        cursor = end
        continue
      }
      const range = ranges[next++]
      if (range.start > cursor) {
        out.push({ blockName: null, attrsJSON: null, source: html.slice(cursor, range.start), exact: true })
      }
      out.push({ blockName: block.blockName, attrsJSON: attrsOf(block), source: html.slice(range.start, range.end), exact: true })
      cursor = range.end
    }
    if (cursor < html.length) {
      out.push({ blockName: null, attrsJSON: null, source: html.slice(cursor), exact: true })
    }
    return out
  }

  const out = []
  let cursor = 0
  for (const block of blocks) {
    const text = serializeBlock(block)
    const exact = html.startsWith(text, cursor)
    if (exact) {
      out.push({ blockName: block.blockName, attrsJSON: attrsOf(block), source: html.slice(cursor, cursor + text.length), exact: true })
      cursor += text.length
    } else {
      // Advance past the block's real bytes, not the reconstruction's, or every later block misaligns.
      const found = html.indexOf('<!-- /wp:', cursor)
      out.push({ blockName: block.blockName, attrsJSON: attrsOf(block), source: text, exact: false })
      cursor = found === -1 ? cursor + text.length : html.indexOf('-->', found) + 3
    }
  }
  return out
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

function wrapUnsupportedBlocks(html, parse, serializeBlock, doc) {
  const slices = blockSourceSlices(html, parse, serializeBlock)
  if (!slices.some(s => blockNeedsWrapping(s, doc))) return html
  return slices.map(slice => {
    if (!blockNeedsWrapping(slice, doc)) return slice.source
    const el = doc.createElement('div')
    el.className = 'wp-block-quill-unsupported'
    el.setAttribute('data-quill-unsupported-source', slice.source)
    el.setAttribute('data-quill-unsupported-label', passthroughLabelFromBlockName(slice.blockName))
    return el.outerHTML
  }).join('')
}

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
      sourceHTML: el.outerHTML,
    }
  }

  return {
    blockLabel: passthroughLabelFromClass(wpClass),
    blockName: null,
    attrsJSON: null,
    sourceHTML: el.outerHTML,
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

function imageBlockAttrs(figure, img) {
  const attrs = {}
  const id = (img.getAttribute('class') || '').match(/wp-image-(\d+)/)
  if (id) attrs.id = parseInt(id[1], 10)
  const style = img.getAttribute('style') || ''
  const width = style.match(styleDimensionRegex('width'))
  if (width) attrs.width = width[1] + 'px'
  const height = style.match(styleDimensionRegex('height'))
  if (height) attrs.height = height[1] + 'px'
  const size = (figure.getAttribute('class') || '').match(/(?:^|\s)size-([\w-]+)/)
  if (size) attrs.sizeSlug = size[1]
  const align = ['left', 'right', 'center'].find(a => figure.classList.contains('align' + a))
  if (align) attrs.align = align
  if (img.parentNode && img.parentNode.tagName === 'A') {
    // A destination core set wins; inferring turns a custom URL into a media link.
    const carried = (carriedBlockAttrs(figure) || {}).linkDestination
    attrs.linkDestination = (carried && carried !== 'none') ? carried : 'media'
  }
  const role = img.getAttribute('role')
  if (role === 'none' || role === 'presentation') attrs.isDecorative = true
  return attrs
}

function toWordPressHTML(html, doc) {
  if (!doc && typeof document !== 'undefined') doc = document
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

  // The editor keeps an empty paragraph after a trailing table/figure so the
  // caret has somewhere to land; it is chrome, not content.
  const tail = div.lastElementChild
  if (tail && tail.tagName === 'P' && div.children.length > 1 &&
      !tail.children.length && !tail.textContent.trim()) tail.remove()

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

  // Standalone images → wp:image block comments. Without them WordPress parses
  // the figure as classic HTML rather than a core/image block, so the block
  // editor offers no image controls for it. Gallery-nested images are skipped —
  // the gallery pass below wraps those itself, in the same save.
  div.querySelectorAll('figure.wp-block-image').forEach(figure => {
    if (figure.closest('.wp-block-gallery')) return
    const img = figure.querySelector('img')
    if (!img) return
    const attrs = mergeCarried(figure, imageBlockAttrs(figure, img),
      ['id', 'sizeSlug', 'width', 'height', 'align', 'linkDestination', 'isDecorative'])
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
    if (first && first.nodeType === 3) first.textContent = first.textContent.replace(/^\s+/, '')
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
    const columns = columnsMatch ? parseInt(columnsMatch[1], 10) : 3
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
    const ids = []
    let linkTo = 'none'
    imageFigures.forEach((imgFigure, i) => {
      const img = imgFigure.querySelector('img')
      if (!img) return
      const idMatch = img.className.match(/wp-image-(\d+)/)
      const id = idMatch ? parseInt(idMatch[1], 10) : null
      if (id !== null) ids.push(id)
      const linkedToMedia = img.parentElement.tagName === 'A'
      if (i === 0) linkTo = linkedToMedia ? 'media' : 'none'
      // Read the real size slug from the image figure's own class rather than
      // hardcoding "large" — this matters once galleryBlock can round-trip an
      // existing gallery's original figure verbatim (Task 2's sourceHTML attr),
      // where the true sizeSlug may not be "large".
      const sizeMatch = imgFigure.className.match(/size-(\S+)/)
      const sizeSlug = sizeMatch ? sizeMatch[1] : 'large'
      const imageAttrs = {}
      if (id !== null) imageAttrs.id = id
      imageAttrs.sizeSlug = sizeSlug
      imageAttrs.linkDestination = linkedToMedia ? 'media' : 'none'
      if (i > 0) figure.insertBefore(doc.createTextNode('\n\n'), imgFigure)
      wrapElementWithComments(doc, imgFigure, ` wp:image${delimiterAttrs(imageAttrs)} `, ' /wp:image ')
    })
    const galleryAttrs = { ids, columns, linkTo }
    if (!cropped) galleryAttrs.imageCrop = false
    const mergedGallery = mergeCarried(figure, galleryAttrs,
      ['columns', 'imageCrop', 'linkTo', 'sizeSlug', 'ids'])
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

  // Strip the generic passthrough marker (set unconditionally in renderHTML,
  // independent of blockName) so it never appears in saved HTML.
  div.querySelectorAll('[data-quill-passthrough]').forEach(el => {
    el.removeAttribute('data-quill-passthrough')
  })

  div.querySelectorAll('[data-quill-block-attrs]').forEach(el => {
    el.removeAttribute('data-quill-block-attrs')
  })

  // A text node would escape the stored markup, so each wrapper leaves an
  // alphanumeric sentinel innerHTML won't touch, substituted back afterwards.
  const unsupported = []
  div.querySelectorAll('[data-quill-unsupported-source]').forEach(el => {
    const token = `QUILLUNSUPPORTED${unsupported.length}QUILLEND`
    unsupported.push(el.getAttribute('data-quill-unsupported-source'))
    el.replaceWith(doc.createTextNode(token))
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
  unsupported.forEach((source, i) => {
    out = out.replace(`QUILLUNSUPPORTED${i}QUILLEND`, () => source)
  })
  return out
}

function formatHTML(html, doc) {
  if (!doc && typeof document !== 'undefined') doc = document
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

// Returns { content, footnotes } -- the list swapped for the delimiter, and the
// bodies to store in meta.
function extractFootnotes(html, doc) {
  doc = doc || document
  const div = doc.createElement('div')
  div.innerHTML = html || ''
  const list = div.querySelector('ol.wp-block-footnotes')
  if (!list) return { content: html || '', footnotes: [] }

  const footnotes = []
  Array.from(list.children).forEach(li => {
    if (!li.id) return
    li.querySelectorAll('.footnote-backref').forEach(a => a.remove())
    footnotes.push({ id: li.id, content: li.innerHTML.trim() })
  })
  list.replaceWith(doc.createComment(' wp:footnotes /'))
  return { content: div.innerHTML, footnotes }
}

// Rebuilds the editable list from meta. A post whose meta is empty keeps the
// bare delimiter, which wrapUnsupportedBlocks then preserves as a card.
function inlineFootnotes(html, footnotes, doc) {
  doc = doc || document
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
  comment.replaceWith(ol)
  return div.innerHTML
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
  module.exports = { extractAlignment, toWordPressHTML, mergeClassNames, mergeCarried, blockSourceSlices, blockNeedsWrapping, wrapUnsupportedBlocks, unrepresentedBlockNames, countBlockNames, formatHTML, countStats, findMatches, findMatchesLoose, fuzzyAnchorRegex, detectEmbedProvider, embedClassFor, passthroughLabelFromClass, passthroughLabelFromBlockName, parsePassthroughBlock, isModeledFigure, QUILL_MODELED_FIGURE_CLASSES, extractFootnotes, inlineFootnotes }
}
