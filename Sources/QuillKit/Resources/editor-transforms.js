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
  div.innerHTML = html

  // Re-emit wp-image-{id} class so WordPress can associate images with media library entries
  div.querySelectorAll('img[data-media-id]').forEach(img => {
    const id = img.getAttribute('data-media-id')
    if (id) img.classList.add(`wp-image-${id}`)
  })

  // Image figures: renderHTML produces <figure><img ...><figcaption/></figure>.
  // Add wp-block-image class, move alignment from img to figure, handle caption.
  div.querySelectorAll('figure:not(.wp-block-table)').forEach(figure => {
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

  // Lists → wp-block-list class (task lists excluded — they use data-type)
  div.querySelectorAll('ul:not([data-type="taskList"]), ol').forEach(el => {
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

  // Task items: Tiptap wraps content in <div><p>text</p></div> inside each task <li>.
  // Strip the inner <p> from that div so we get <div>text</div>.
  div.querySelectorAll('li[data-type="taskItem"] > div').forEach(wrapper => {
    const kids = Array.from(wrapper.children)
    if (kids.length === 1 && kids[0].tagName === 'P') {
      wrapper.innerHTML = kids[0].innerHTML
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

  return div.innerHTML
}

function formatHTML(html, doc) {
  if (!doc && typeof document !== 'undefined') doc = document
  const BLOCK = new Set(['p','h1','h2','h3','h4','h5','h6',
    'ul','ol','li','blockquote','pre','figure','figcaption',
    'table','thead','tbody','tfoot','tr','th','td','cite'])
  const VOID = new Set(['img','br','hr','input','meta','link',
    'wbr','area','base','col','embed','param','source','track'])

  function attrStr(el) {
    return Array.from(el.attributes).map(a => ` ${a.name}="${a.value}"`).join('')
  }

  function serialize(node, depth) {
    const pad = '  '.repeat(depth)
    if (node.nodeType === 3) return node.textContent
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

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { extractAlignment, toWordPressHTML, formatHTML }
}
