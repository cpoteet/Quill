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
    .replace(/<!-- wp:embed [^\n]*-->\n?/g, '')
    .replace(/\n?<!-- \/wp:embed -->/g, '')

  // Re-emit wp-image-{id} class so WordPress can associate images with media library entries
  div.querySelectorAll('img[data-media-id]').forEach(img => {
    const id = img.getAttribute('data-media-id')
    if (id) img.classList.add(`wp-image-${id}`)
  })

  // Image figures: renderHTML produces <figure><img ...><figcaption/></figure>.
  // Add wp-block-image class, move alignment from img to figure, handle caption.
  div.querySelectorAll('figure:not(.wp-block-table):not(.wp-block-embed)').forEach(figure => {
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
  module.exports = { extractAlignment, toWordPressHTML, formatHTML, countStats, findMatches, detectEmbedProvider, embedClassFor }
}
