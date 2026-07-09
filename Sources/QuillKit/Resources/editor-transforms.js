'use strict'

// Pure DOM transform functions shared between editor.html (browser) and
// the Node/jsdom test harness (Scripts/test-editor.js).
//
// toWordPressHTML accepts an optional `doc` argument so tests can supply a
// jsdom document. In the browser the global `document` is used by default.

function extractAlignment(cls) {
  if (cls.includes('alignleft'))   return 'left'
  if (cls.includes('alignright'))  return 'right'
  if (cls.includes('aligncenter')) return 'center'
  return null
}

function toWordPressHTML(html, doc) {
  if (!doc && typeof document !== 'undefined') doc = document
  const div = doc.createElement('div')
  // Strip existing wp:embed block comments — will re-add fresh ones below.
  div.innerHTML = html
    .replace(/<!-- wp:embed [^\n]*-->\n*/g, '')
    .replace(/\n*<!-- \/wp:embed -->/g, '')
    .replace(/<!-- wp:gallery [^\n]*-->\n*/g, '')
    .replace(/\n*<!-- \/wp:gallery -->/g, '')
    // wp:image comments only ever appear nested inside a gallery today (standalone
    // images aren't comment-wrapped at all — see the images row in CLAUDE.md's
    // Gutenberg-compatibility table), so this strip is gallery-scoped in practice.
    // If a future change routes raw WordPress HTML through toWordPressHTML, revisit —
    // this would strip a standalone image's own wp:image block identity too.
    .replace(/<!-- wp:image [^\n]*-->\n*/g, '')
    .replace(/\n*<!-- \/wp:image -->/g, '')
    // Remove orphaned whitespace-only text nodes that appear between gallery image
    // figures after stripping comments — they interfere with idempotent wrapping.
    .replace(/<\/figure>\s+<figure\s+class="wp-block-image/g, '</figure><figure class="wp-block-image')

  // Re-emit wp-image-{id} class so WordPress can associate images with media library entries
  div.querySelectorAll('img[data-media-id]').forEach(img => {
    const id = img.getAttribute('data-media-id')
    if (id) img.classList.add(`wp-image-${id}`)
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
  div.querySelectorAll('li').forEach(li => {
    const kids = Array.from(li.children)
    if (kids.length === 1 && kids[0].tagName === 'P') {
      li.innerHTML = kids[0].innerHTML
    }
  })

  // Blockquotes → wp-block-quote class
  div.querySelectorAll('blockquote').forEach(el => {
    el.classList.add('wp-block-quote')
  })

  // Strip empty cite elements (user left attribution blank)
  div.querySelectorAll('blockquote cite').forEach(el => {
    if (!el.textContent.trim()) el.remove()
  })

  // Code blocks → wp-block-code class on the <pre> wrapper
  div.querySelectorAll('pre').forEach(el => {
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
    a.textContent = '↩'
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
    const open = doc.createComment(` wp:embed ${JSON.stringify(attrs)} `)
    const close = doc.createComment(' /wp:embed ')
    const parent = figure.parentNode
    const next = figure.nextSibling
    parent.insertBefore(open, figure)
    parent.insertBefore(doc.createTextNode('\n'), figure)
    parent.insertBefore(doc.createTextNode('\n'), next)
    parent.insertBefore(close, next)
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
      const openImg = doc.createComment(` wp:image ${JSON.stringify(imageAttrs)} `)
      const closeImg = doc.createComment(' /wp:image ')
      const afterImg = imgFigure.nextElementSibling
      if (i > 0) figure.insertBefore(doc.createTextNode('\n\n'), imgFigure)
      figure.insertBefore(openImg, imgFigure)
      figure.insertBefore(doc.createTextNode('\n'), imgFigure)
      figure.insertBefore(closeImg, afterImg)
    })
    const galleryAttrs = { ids, columns, linkTo }
    if (!cropped) galleryAttrs.imageCrop = false
    const openGallery = doc.createComment(` wp:gallery ${JSON.stringify(galleryAttrs)} `)
    const closeGallery = doc.createComment(' /wp:gallery ')
    const parent = figure.parentNode
    const next = figure.nextSibling
    parent.insertBefore(openGallery, figure)
    parent.insertBefore(doc.createTextNode('\n'), figure)
    parent.insertBefore(doc.createTextNode('\n'), next)
    parent.insertBefore(closeGallery, next)
  })

  return div.innerHTML
}

function formatHTML(html, doc) {
  if (!doc && typeof document !== 'undefined') doc = document
  const BLOCK = new Set(['p','h1','h2','h3','h4','h5','h6',
    'ul','ol','li','blockquote','pre','figure','figcaption',
    'table','thead','tbody','tfoot','tr','th','td','cite'])
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
    const inner = [...node.childNodes].map(c => serialize(c, 0)).join('')
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
  module.exports = { extractAlignment, toWordPressHTML, formatHTML, countStats, findMatches, findMatchesLoose, fuzzyAnchorRegex, detectEmbedProvider, embedClassFor }
}
