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

function wrapBlock(doc, el, name, attrs) {
  if (alreadyDelimited(el, name)) return
  const attrsStr = attrs && Object.keys(attrs).length ? ' ' + JSON.stringify(attrs) : ''
  wrapElementWithComments(doc, el, ` wp:${name}${attrsStr} `, ` /wp:${name} `)
}

function wrapListItems(doc, listEl) {
  Array.from(listEl.children).forEach(li => {
    if (li.tagName !== 'LI') return
    Array.from(li.children).forEach(child => {
      if (child.tagName !== 'UL' && child.tagName !== 'OL') return
      wrapListItems(doc, child)
      const nested = blockDescriptorRegistry.descriptorFor(NODE_FOR_TAG[child.tagName])
      wrapBlock(doc, child, shortBlockName(nested.blockName), nested.attrsFrom(child))
    })
    wrapBlock(doc, li, 'list-item', {})
  })
}

// core/quote holds inner paragraph blocks, not bare markup, so its prose is
// delimited too — an undelimited <p> inside makes Gutenberg flag the quote.
function wrapQuoteParagraphs(doc, quoteEl) {
  Array.from(quoteEl.children).forEach(child => {
    if (child.tagName !== 'P') return
    wrapBlock(doc, child, 'paragraph', {})
  })
}

function wrapInDelimiters(root, doc) {
  Array.from(root.children).forEach(el => {
    if (el.hasAttribute('data-quill-passthrough-placeholder')) return
    if (el.classList.contains('wp-block-footnotes')) return

    const nodeName = nodeNameForElement(el)
    const descriptor = nodeName ? blockDescriptorRegistry.descriptorFor(nodeName) : null
    if (!descriptor) return

    if (descriptor.childBlockName === 'core/list-item') wrapListItems(doc, el)
    if (nodeName === 'blockquote') wrapQuoteParagraphs(doc, el)
    if (descriptor.shape === 'container' && descriptor.blockName !== 'core/list') wrapInDelimiters(el, doc)

    wrapBlock(doc, el, shortBlockName(descriptor.blockName), descriptor.attrsFrom(el))
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
function imageBlockAttrs(figure, img) {
  const attrs = {}
  const id = (img.getAttribute('class') || '').match(/wp-image-(\d+)/)
  if (id) attrs.id = parseInt(id[1], 10)
  const size = (figure.getAttribute('class') || '').match(/(?:^|\s)size-([\w-]+)/)
  if (size) attrs.sizeSlug = size[1]
  const align = ['left', 'right', 'center'].find(a => figure.classList.contains('align' + a))
  if (align) attrs.align = align
  if (img.parentNode && img.parentNode.tagName === 'A') attrs.linkDestination = 'media'
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
    if (align) {
      figure.classList.add('wp-block-image', align)
      img.classList.remove(align)
    } else {
      figure.classList.add('wp-block-image')
    }
    const caption = figure.querySelector('figcaption')
    if (caption) {
      if (caption.textContent.trim()) {
        caption.classList.add('wp-element-caption')
      } else {
        caption.remove()
      }
    }
  })

  // Standalone images → wp:image block comments. Without them WordPress parses
  // the figure as classic HTML rather than a core/image block, so the block
  // editor offers no image controls for it. Gallery-nested images are skipped —
  // the gallery pass below wraps those itself, in the same save.
  div.querySelectorAll('figure.wp-block-image').forEach(figure => {
    if (figure.closest('.wp-block-gallery')) return
    const img = figure.querySelector('img')
    if (!img) return
    const attrs = imageBlockAttrs(figure, img)
    const open = Object.keys(attrs).length
      ? ` wp:image ${JSON.stringify(attrs)} `
      : ' wp:image '
    wrapElementWithComments(doc, figure, open, ' /wp:image ')
  })

  // Headings → wp-block-heading class
  div.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach(el => {
    el.classList.add('wp-block-heading')
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

  // Code blocks → wp-block-code class on the <pre> wrapper
  div.querySelectorAll('pre').forEach(el => {
    if (el.classList.contains('wp-block-preformatted')) return
    el.classList.add('wp-block-code')
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

  // Tables: move first all-<th> row from <tbody> into a proper <thead>
  div.querySelectorAll('table').forEach(table => {
    if (table.querySelector('thead')) return
    const tbody = table.querySelector('tbody')
    if (!tbody) return
    const firstRow = tbody.querySelector('tr:first-child')
    if (!firstRow) return
    const cells = Array.from(firstRow.children)
    if (cells.length > 0 && cells.every(c => c.tagName === 'TH')) {
      const thead = doc.createElement('thead')
      table.insertBefore(thead, tbody)
      thead.appendChild(firstRow)
    }
  })

  // Tables → Gutenberg figure wrapper
  div.querySelectorAll('table').forEach(table => {
    if (table.parentElement?.classList.contains('wp-block-table')) return
    const figure = doc.createElement('figure')
    figure.className = 'wp-block-table'
    table.parentNode.insertBefore(figure, table)
    figure.appendChild(table)
  })

  // Footnote markers: write 1-based numbers into anchors in document order.
  // The editor leaves anchors empty (CSS counters display numbers live);
  // the saved HTML carries real text so it renders anywhere.
  div.querySelectorAll('sup.fn[data-fn] > a').forEach((a, i) => {
    a.textContent = String(i + 1)
  })

  // Footnote backrefs: give each marker sup an id and add a return link to
  // its matching list item so published WordPress posts have working ↩ anchors.
  div.querySelectorAll('sup.fn[data-fn]').forEach(sup => {
    sup.id = 'ref-' + sup.getAttribute('data-fn')
  })
  div.querySelectorAll('ol.wp-block-footnotes > li[id]').forEach(li => {
    if (li.querySelector('.footnote-backref')) return
    const a = doc.createElement('a')
    a.href = '#ref-' + li.id
    a.className = 'footnote-backref'
    a.setAttribute('aria-label', 'Back to content')
    a.textContent = '↩︎'
    li.appendChild(a)
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
    wrapElementWithComments(doc, figure, ` wp:embed ${JSON.stringify(attrs)} `, ' /wp:embed ')
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
      wrapElementWithComments(doc, imgFigure, ` wp:image ${JSON.stringify(imageAttrs)} `, ' /wp:image ')
    })
    const galleryAttrs = { ids, columns, linkTo }
    if (!cropped) galleryAttrs.imageCrop = false
    wrapElementWithComments(doc, figure, ` wp:gallery ${JSON.stringify(galleryAttrs)} `, ' /wp:gallery ')
  })

  wrapInDelimiters(div, doc)

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

  // Strip the generic passthrough marker (set unconditionally in renderHTML,
  // independent of blockName) so it never appears in saved HTML.
  div.querySelectorAll('[data-quill-passthrough]').forEach(el => {
    el.removeAttribute('data-quill-passthrough')
  })

  return div.innerHTML
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
  module.exports = { extractAlignment, toWordPressHTML, formatHTML, countStats, findMatches, findMatchesLoose, fuzzyAnchorRegex, detectEmbedProvider, embedClassFor, passthroughLabelFromClass, passthroughLabelFromBlockName, parsePassthroughBlock, isModeledFigure, QUILL_MODELED_FIGURE_CLASSES }
}
