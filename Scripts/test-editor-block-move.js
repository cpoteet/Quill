'use strict'

// Loads the real editor.html in jsdom and checks moving top-level blocks.

const { test, describe, before, after, afterEach } = require('node:test')
const assert = require('node:assert/strict')
const { JSDOM, VirtualConsole } = require('jsdom')
const fs = require('fs')
const path = require('path')
const nodeCrypto = require('crypto')

const htmlPath = path.resolve(__dirname, '../Sources/QuillKit/Resources/editor.html')

let editor
let win
const sentToSwift = []

before(async () => {
  const html = fs.readFileSync(htmlPath, 'utf8')
  const vc = new VirtualConsole()
  const logs = []
  vc.on('jsdomError', e => logs.push('JSDOM_ERROR: ' + (e.detail?.stack || e.message || e)))

  const dom = new JSDOM(html, {
    runScripts: 'dangerously',
    resources: 'usable',
    pretendToBeVisual: true,
    url: 'file://' + htmlPath,
    virtualConsole: vc,
  })
  win = dom.window

  if (!win.crypto) win.crypto = {}
  if (!win.crypto.randomUUID) win.crypto.randomUUID = () => nodeCrypto.randomUUID()
  if (!win.matchMedia) win.matchMedia = () => ({ matches: false, addEventListener() {}, removeEventListener() {}, addListener() {}, removeListener() {} })
  if (!win.requestAnimationFrame) win.requestAnimationFrame = cb => setTimeout(cb, 0)
  if (!win.ResizeObserver) win.ResizeObserver = class { observe() {} unobserve() {} disconnect() {} }
  // A dispatch scrolls the selection into view, and jsdom gives text no geometry.
  const rect = { top: 0, left: 0, bottom: 0, right: 0, width: 0, height: 0 }
  for (const proto of [win.Text.prototype, win.Range.prototype]) {
    if (proto.getClientRects) continue
    proto.getClientRects = () => Object.assign([rect], { item: () => rect })
    proto.getBoundingClientRect = () => rect
  }
  win.webkit = { messageHandlers: { contentChanged: { postMessage: html => sentToSwift.push(html) } } }

  editor = await new Promise((resolve, reject) => {
    let tries = 0
    const t = setInterval(() => {
      if (win._tiptapEditor) { clearInterval(t); resolve(win._tiptapEditor) }
      else if (++tries > 400) { clearInterval(t); reject(new Error('editor never became ready.\n' + logs.join('\n'))) }
    }, 25)
  })
})

after(() => { if (win) win.close() })

const TRAILING = () => new Set(['table', 'galleryBlock', 'embedBlock', 'gutenbergPassthrough', 'horizontalRule'])
const doc = () => editor.state.doc
const types = () => { const out = []; doc().forEach(n => out.push(n.type.name)); return out }
const saved = () => win.extractFootnotes(win.toWordPressHTML(editor.getHTML())).content

function load(html, footnotes) {
  win.setContent(html, footnotes)
  return doc()
}

// What saving a post freshly loaded in this order produces.
function savedFreshLoad(html, footnotes) {
  load(html, footnotes)
  return saved()
}

function move(from, to, gap) {
  const result = win.moveTopLevelBlocks(editor.state, from, to, gap, TRAILING())
  if (result) editor.view.dispatch(result.tr)
  return result
}

const block = (name, inner, attrs) =>
  `<!-- wp:${name}${attrs ? ' ' + attrs : ''} -->\n${inner}\n<!-- /wp:${name} -->`
const P = text => block('paragraph', `<p>${text}</p>`)
const H = (level, text) => block('heading', `<h${level} class="wp-block-heading">${text}</h${level}>`, level === 2 ? '' : `{"level":${level}}`)
const SEP = block('separator', '<hr class="wp-block-separator has-alpha-channel-opacity"/>')

const ID = 'fn-11111111-2222-4333-8444-555555555555'
const ID2 = 'fn-99999999-8888-4777-8666-555555555555'
const marker = id => `<sup data-fn="${id}" class="fn" id="${id}-link"><a href="#${id}">1</a></sup>`
const FOOTNOTES = '<!-- wp:footnotes /-->'
const META = (...ids) => JSON.stringify(ids.map((id, i) => ({ id, content: `Note ${i + 1}` })))

const B_QUOTE = () => SAMPLES.find(s => s.type === 'blockquote').html
const B_PULLQUOTE = () => SAMPLES.find(s => s.type === 'pullquote').html

const ACCORDION = '<div role="group" class="wp-block-accordion">' +
  '<div class="wp-block-accordion-item">' +
  '<h3 class="wp-block-accordion-heading wp-block-heading"><button type="button" class="wp-block-accordion-heading__toggle"><span class="wp-block-accordion-heading__toggle-title">One</span></button></h3>' +
  '<div role="region" class="wp-block-accordion-panel"><p>First</p></div></div>' +
  '</div>'
const TABS = '<div class="wp-block-tabs">' +
  '<div role="tablist" class="wp-block-tab-list">' +
  '<button type="button" role="tab">Alpha</button><button type="button" role="tab">Beta</button></div>' +
  '<div class="wp-block-tab-panels">' +
  '<section role="tabpanel" tabindex="0" class="wp-block-tab-panel"><p>A body</p></section>' +
  '<section role="tabpanel" tabindex="0" class="wp-block-tab-panel"><p>B body</p></section>' +
  '</div></div>'
const UNSUPPORTED = "<!-- wp:acme/widget {\"a\":1} -->\n<div class='wp-block-acme-widget' data-x='1'>Hi<br/><img src='a.png'/></div>\n<!-- /wp:acme/widget -->"

const SAMPLES = [
  { name: 'paragraph', type: 'paragraph', html: P('Moved') },
  { name: 'H2', type: 'heading', html: H(2, 'Title') },
  { name: 'bulleted list', type: 'bulletList', html: block('list', '<ul class="wp-block-list"><!-- wp:list-item -->\n<li>one</li>\n<!-- /wp:list-item --></ul>') },
  { name: 'numbered list (start=3)', type: 'orderedList', html: block('list', '<ol start="3" class="wp-block-list"><!-- wp:list-item -->\n<li>three</li>\n<!-- /wp:list-item --></ol>', '{"ordered":true,"start":3}') },
  { name: 'quote', type: 'blockquote', html: block('quote', `<blockquote class="wp-block-quote">${P('Said')}</blockquote>`) },
  { name: 'pullquote', type: 'pullquote', html: block('pullquote', '<figure class="wp-block-pullquote"><blockquote><p>Q</p><cite>Who</cite></blockquote></figure>') },
  { name: 'code', type: 'codeBlock', html: block('code', '<pre class="wp-block-code"><code>let x = 1</code></pre>') },
  { name: 'preformatted', type: 'preformatted', html: block('preformatted', '<pre class="wp-block-preformatted">  spaced</pre>') },
  { name: 'separator', type: 'horizontalRule', html: SEP },
  { name: 'image with caption and alignment', type: 'image', html: block('image', '<figure class="wp-block-image alignright size-large"><img src="https://x.test/a.jpg" alt="Alt" class="wp-image-9"/><figcaption class="wp-element-caption">Cap</figcaption></figure>', '{"id":9,"sizeSlug":"large","align":"right"}') },
  { name: 'gallery', type: 'galleryBlock', html: block('gallery', `<figure class="wp-block-gallery has-nested-images columns-2 is-cropped">${block('image', '<figure class="wp-block-image size-large"><img src="https://x.test/1.jpg" alt="" class="wp-image-1"/></figure>', '{"id":1,"sizeSlug":"large"}')}</figure>`, '{"columns":2,"linkTo":"none"}') },
  { name: 'embed', type: 'embedBlock', html: block('embed', '<figure class="wp-block-embed is-type-video is-provider-youtube wp-block-embed-youtube"><div class="wp-block-embed__wrapper">\nhttps://www.youtube.com/watch?v=abc\n</div></figure>', '{"url":"https://www.youtube.com/watch?v=abc","type":"video","providerNameSlug":"youtube"}') },
  { name: 'table', type: 'table', html: block('table', '<figure class="wp-block-table"><table><tbody><tr><td>a</td><td>b</td></tr></tbody></table></figure>') },
  { name: 'columns', type: 'columnsBlock', html: block('columns', `<div class="wp-block-columns">${block('column', `<div class="wp-block-column">${P('C')}</div>`)}</div>`) },
  { name: 'group', type: 'groupBlock', html: block('group', `<div class="wp-block-group">${P('In group')}</div>`) },
  { name: 'buttons', type: 'buttonsBlock', html: block('buttons', `<div class="wp-block-buttons">${block('button', '<div class="wp-block-button"><a class="wp-block-button__link wp-element-button" href="https://x.test">Go</a></div>')}</div>`) },
  { name: 'details', type: 'detailsBlock', html: block('details', `<details class="wp-block-details"><summary>S</summary>${P('B')}</details>`) },
  { name: 'accordion', type: 'accordionBlock', html: ACCORDION },
  { name: 'tabs', type: 'tabsBlock', html: TABS },
  { name: 'synced pattern card', type: 'gutenbergPassthrough', html: '<!-- wp:block {"ref":968} /-->' },
  { name: 'Custom HTML card', type: 'gutenbergPassthrough', html: "<!-- wp:html -->\n<div class='promo' data-x='1'>Hi<br/><img src='a.png'/></div>\n<!-- /wp:html -->" },
  { name: 'unsupported block', type: 'gutenbergPassthrough', html: UNSUPPORTED },
]

describe('top-level ranges', () => {
  test('movableCount excludes a trailing footnotes list', () => {
    load(`${P('Body' + marker(ID))}\n\n${FOOTNOTES}`, META(ID))
    assert.equal(doc().lastChild.type.name, 'footnotesList')
    assert.equal(win.movableCount(doc()), doc().childCount - 1)
  })

  test('topLevelIndexAt returns -1 inside the footnotes list', () => {
    load(`${P('Body' + marker(ID))}\n\n${FOOTNOTES}`, META(ID))
    assert.equal(win.topLevelIndexAt(doc(), 2), 0)
    assert.equal(win.topLevelIndexAt(doc(), doc().content.size - 2), -1)
  })

  test('sectionEnd: an H2 stops at the next H2 or H1, not at an H3', () => {
    load([H(2, 'A'), P('a'), H(3, 'B'), P('b'), H(2, 'C'), P('c')].join('\n\n'))
    assert.equal(win.sectionEnd(doc(), 0), 4)
    load([H(2, 'A'), P('a'), H(1, 'B'), P('b')].join('\n\n'))
    assert.equal(win.sectionEnd(doc(), 0), 2)
  })

  test('sectionEnd: the last H2 stops before the footnotes list', () => {
    load([P('x'), H(2, 'A'), P('Body' + marker(ID)), FOOTNOTES].join('\n\n'), META(ID))
    assert.equal(types().at(-1), 'footnotesList')
    assert.equal(win.sectionEnd(doc(), 1), win.movableCount(doc()))
    assert.equal(win.sectionEnd(doc(), 1), doc().childCount - 1)
  })

  test('sectionEnd: a heading inside a Group does not start a section', () => {
    load([block('group', `<div class="wp-block-group">${H(2, 'In')}</div>`), P('a'), P('b')].join('\n\n'))
    assert.equal(types()[0], 'groupBlock')
    assert.equal(win.sectionEnd(doc(), 0), 1)
  })

  test('sectionEnd: a non-heading is one block', () => {
    load([P('a'), P('b'), P('c')].join('\n\n'))
    assert.equal(win.sectionEnd(doc(), 1), 2)
  })

  test('isNoOpMove: gaps from..to inclusive are no-ops', () => {
    assert.equal(win.isNoOpMove(2, 4, 2), true)
    assert.equal(win.isNoOpMove(2, 4, 3), true)
    assert.equal(win.isNoOpMove(2, 4, 4), true)
    assert.equal(win.isNoOpMove(2, 4, 1), false)
    assert.equal(win.isNoOpMove(2, 4, 5), false)
  })

  test('adjacentGap: null at the top, null at the bottom, null next to the footnotes list', () => {
    load([P('a'), P('b'), P('c')].join('\n\n'))
    assert.equal(win.adjacentGap(doc(), 0, 'up'), null)
    assert.equal(win.adjacentGap(doc(), 2, 'down'), null)
    assert.equal(win.adjacentGap(doc(), 1, 'up'), 0)
    assert.equal(win.adjacentGap(doc(), 1, 'down'), 3)
    load([P('a'), P('Body' + marker(ID)), FOOTNOTES].join('\n\n'), META(ID))
    assert.equal(win.adjacentGap(doc(), 1, 'down'), null)
  })
})

describe('a move saves exactly what loading the post in that order saves', () => {
  for (const sample of SAMPLES) {
    test(sample.name, () => {
      const expected = savedFreshLoad([P('A'), P('B'), sample.html].join('\n\n'))
      load([P('A'), sample.html, P('B')].join('\n\n'))
      assert.equal(types()[1], sample.type)
      assert.ok(move(1, 2, 3))
      assert.equal(win.getContent(), expected)
      if (sample.type === 'gutenbergPassthrough') assert.ok(win.getContent().includes(sample.html), 'source kept byte-exact')
    })
  }
})

describe('footnotes and undo', () => {
  const TWO_NOTES = () => load([P('First' + marker(ID)), P('Second' + marker(ID2)), FOOTNOTES].join('\n\n'), META(ID, ID2))
  const noteIds = () => { win.flushContent(); return JSON.parse(win.getFootnotes()).map(n => n.id) }

  test('moving a paragraph with a footnote reference reorders getFootnotes()', () => {
    TWO_NOTES()
    assert.deepEqual(noteIds(), [ID, ID2])
    move(1, 2, 0)
    assert.deepEqual(noteIds(), [ID2, ID])
    assert.equal(types().at(-1), 'footnotesList')
  })

  test('one undo restores the document and the notes order', () => {
    TWO_NOTES()
    const before = doc().toJSON()
    move(1, 2, 0)
    editor.commands.undo()
    assert.deepEqual(doc().toJSON(), before)
    assert.deepEqual(noteIds(), [ID, ID2])
  })

  test('a move straight after typing in the same block is its own undo step', () => {
    load([P('A'), P('B')].join('\n\n'))
    editor.commands.setTextSelection(2)
    editor.commands.insertContent('x')
    move(0, 1, 2)
    assert.equal(doc().child(1).textContent, 'Ax')
    editor.commands.undo()
    assert.equal(doc().child(0).textContent, 'Ax')
    assert.equal(doc().child(1).textContent, 'B')
  })

  test('moving a final separator up does not leave a saved empty paragraph', () => {
    const expected = savedFreshLoad([SEP, P('A')].join('\n\n'))
    load([P('A'), SEP].join('\n\n'))
    assert.deepEqual(types(), ['paragraph', 'horizontalRule', 'paragraph'])
    assert.ok(move(1, 2, 0))
    assert.equal(win.getContent(), expected)
    assert.deepEqual(types(), ['horizontalRule', 'paragraph'])
  })

  test('moving a last section that ends in a separator drops the generated paragraph', () => {
    const expected = savedFreshLoad([H(2, 'S'), SEP, P('x')].join('\n\n'))
    load([P('x'), H(2, 'S'), SEP].join('\n\n'))
    assert.deepEqual(types(), ['paragraph', 'heading', 'horizontalRule', 'paragraph'])
    assert.ok(move(1, win.sectionEnd(doc(), 1), 0))
    assert.equal(win.getContent(), expected)
    assert.deepEqual(types(), ['heading', 'horizontalRule', 'paragraph'])
  })

  test('a block moved below a final table does not strand the generated paragraph', () => {
    const TABLE = SAMPLES.find(s => s.type === 'table').html
    for (const gap of [2, 3]) {
      const expected = savedFreshLoad([TABLE, P('A')].join('\n\n'))
      load([P('A'), TABLE].join('\n\n'))
      assert.ok(move(0, 1, gap), `gap ${gap}`)
      assert.equal(win.getContent(), expected, `gap ${gap}`)
      assert.deepEqual(types(), ['table', 'paragraph'], `gap ${gap}`)
    }
  })

  test('moving a final table down past only its generated paragraph is a no-op', () => {
    load([P('A'), SAMPLES.find(s => s.type === 'table').html].join('\n\n'))
    assert.deepEqual(types(), ['paragraph', 'table', 'paragraph'])
    assert.equal(win.moveTopLevelBlocks(editor.state, 1, 2, 3, TRAILING()), null)
  })

  test('generatedTrailingIndex finds the generated paragraph before a footnotes list', () => {
    load([P('Body' + marker(ID)), SEP, FOOTNOTES].join('\n\n'), META(ID))
    assert.deepEqual(types(), ['paragraph', 'horizontalRule', 'paragraph', 'footnotesList'])
    assert.equal(win.generatedTrailingIndex(doc(), TRAILING()), 2)
  })

  test('an author\'s empty paragraph after a plain paragraph is not treated as generated', () => {
    load([P('A'), P('')].join('\n\n'))
    assert.deepEqual(types(), ['paragraph', 'paragraph'])
    assert.equal(win.generatedTrailingIndex(doc(), TRAILING()), -1)
  })

  test('the footnotes list stays the last child after any move', () => {
    for (const [from, to, gap] of [[0, 1, 3], [2, 3, 0], [0, 2, 3], [1, 3, 0]]) {
      load([P('First' + marker(ID)), P('Second' + marker(ID2)), P('Third'), FOOTNOTES].join('\n\n'), META(ID, ID2))
      assert.ok(move(from, to, gap), `move ${from}..${to} to ${gap}`)
      assert.equal(types().at(-1), 'footnotesList')
      assert.equal(types().filter(t => t === 'footnotesList').length, 1)
    }
  })

  test('a no-op move returns null and adds no undo step', () => {
    load([P('A'), P('B'), P('C')].join('\n\n'))
    const before = doc().toJSON()
    for (const gap of [1, 2]) assert.equal(win.moveTopLevelBlocks(editor.state, 1, 2, gap, TRAILING()), null)
    assert.deepEqual(doc().toJSON(), before)
    assert.equal(editor.can().undo(), false)
  })
})

describe('blockMarker', () => {
  const EXPECTED = {
    paragraph: ['text', '¶', 'Paragraph'],
    heading: ['text', 'h2', 'Heading 2'],
    bulletList: ['text', '•', 'Bulleted list'],
    orderedList: ['text', '1.', 'Numbered list'],
    blockquote: ['glyph', 'quote', 'Quote'],
    pullquote: ['text', '”', 'Pullquote'],
    codeBlock: ['text', '{}', 'Code'],
    preformatted: ['text', 'pre', 'Preformatted'],
    horizontalRule: ['text', '—', 'Separator'],
    image: ['glyph', 'image', 'Image'],
    galleryBlock: ['glyph', 'gallery', 'Gallery'],
    embedBlock: ['glyph', 'embed', 'Embed'],
    table: ['glyph', 'table', 'Table'],
    columnsBlock: ['glyph', 'columns', 'Columns'],
    groupBlock: ['glyph', 'group', 'Group'],
    buttonsBlock: ['glyph', 'buttons', 'Buttons'],
    detailsBlock: ['glyph', 'chevron', 'Details'],
    accordionBlock: ['glyph', 'accordion', 'Accordion'],
    tabsBlock: ['glyph', 'tabs', 'Tabs'],
  }

  test('maps every top-level node type to the spec marker', () => {
    for (const sample of SAMPLES.filter(s => s.type !== 'gutenbergPassthrough')) {
      load([P('A'), sample.html].join('\n\n'))
      const node = doc().child(1)
      assert.equal(node.type.name, sample.type, sample.name)
      const [kind, value, label] = EXPECTED[sample.type]
      assert.deepEqual({ ...win.blockMarker(node) }, { kind, value, label }, sample.name)
    }
  })

  test('headings use h1..h6 and a "Heading N" label', () => {
    for (let level = 1; level <= 6; level++) {
      load(H(level, 'T'))
      assert.deepEqual({ ...win.blockMarker(doc().child(0)) }, { kind: 'text', value: `h${level}`, label: `Heading ${level}` })
    }
  })

  test('tells synced pattern, Custom HTML and unsupported cards apart', () => {
    const markerOf = name => {
      load([P('A'), SAMPLES.find(s => s.name === name).html].join('\n\n'))
      return { ...win.blockMarker(doc().child(1)) }
    }
    assert.deepEqual(markerOf('synced pattern card'), { kind: 'glyph', value: 'synced', label: 'Synced pattern' })
    assert.deepEqual(markerOf('Custom HTML card'), { kind: 'glyph', value: 'html', label: 'Custom HTML' })
    assert.deepEqual(markerOf('unsupported block'), { kind: 'glyph', value: 'html', label: 'Unsupported block' })
  })
})

describe('moveBlock', () => {
  const texts = () => { const out = []; doc().forEach(n => out.push(n.textContent)); return out }
  const caretIn = text => {
    let at = null
    doc().descendants((node, pos) => { if (at === null && node.isText && node.text.includes(text)) at = pos + node.text.indexOf(text) })
    return at
  }

  test('moves the caret block up one place and keeps the caret offset', () => {
    load([P('One'), P('Two'), P('Three')].join('\n\n'))
    editor.commands.setTextSelection(caretIn('wo'))
    assert.equal(win.moveBlock('up'), true)
    assert.deepEqual(texts(), ['Two', 'One', 'Three'])
    assert.equal(editor.state.selection.from, caretIn('wo'))
    assert.equal(editor.state.selection.empty, true)
  })

  test('moves a node-selected embed down and keeps it node-selected', () => {
    load([P('A'), SAMPLES.find(s => s.type === 'embedBlock').html, P('B')].join('\n\n'))
    editor.commands.setNodeSelection(win.topLevelPos(doc(), 1))
    assert.equal(win.moveBlock('down'), true)
    assert.deepEqual(types().slice(0, 3), ['paragraph', 'paragraph', 'embedBlock'])
    assert.equal(editor.state.selection.node?.type.name, 'embedBlock')
    assert.equal(editor.state.selection.from, win.topLevelPos(doc(), 2))
  })

  test('moves a whole Group past its neighbour as one unit', () => {
    load([P('A'), block('group', `<div class="wp-block-group">${P('G1')}\n\n${P('G2')}</div>`), P('B')].join('\n\n'))
    editor.commands.setTextSelection(caretIn('G2'))
    assert.equal(win.moveBlock('down'), true)
    assert.deepEqual(types(), ['paragraph', 'paragraph', 'groupBlock'])
    assert.deepEqual(texts(), ['A', 'B', 'G1G2'])
    assert.equal(editor.state.selection.from, caretIn('G2'))
  })

  test('does nothing at the top, at the bottom, or above the footnotes list', () => {
    load([P('One'), P('Two')].join('\n\n'))
    editor.commands.setTextSelection(caretIn('One'))
    assert.equal(win.moveBlock('up'), false)
    editor.commands.setTextSelection(caretIn('Two'))
    assert.equal(win.moveBlock('down'), false)
    assert.deepEqual(texts(), ['One', 'Two'])
    load([P('One'), P('Two' + marker(ID)), FOOTNOTES].join('\n\n'), META(ID))
    editor.commands.setTextSelection(caretIn('Two'))
    assert.equal(win.moveBlock('down'), false)
    editor.commands.setTextSelection(doc().content.size - 2)
    assert.equal(win.moveBlock('up'), false)
    assert.equal(types().at(-1), 'footnotesList')
  })

  test('does nothing from the generated paragraph after a final table', () => {
    load([P('A'), SAMPLES.find(s => s.type === 'table').html].join('\n\n'))
    editor.commands.setTextSelection(doc().content.size - 1)
    assert.equal(editor.state.selection.$from.parent.type.name, 'paragraph')
    assert.equal(win.moveBlock('up'), false)
    assert.deepEqual(types(), ['paragraph', 'table', 'paragraph'])
  })

  test('keeps a node-selected image node-selected', () => {
    load([P('A'), SAMPLES.find(s => s.type === 'image').html, P('B')].join('\n\n'))
    editor.commands.setNodeSelection(win.topLevelPos(doc(), 1))
    assert.equal(editor.state.selection.node?.type.name, 'image')
    assert.equal(win.moveBlock('up'), true)
    assert.equal(editor.state.selection.node?.type.name, 'image')
    assert.equal(editor.state.selection.from, 0)
  })

  test('keeps a nested node selection on the nested node', () => {
    load([P('A'), block('group', `<div class="wp-block-group">${P('G')}\n\n${SEP}</div>`)].join('\n\n'))
    let hrPos = null
    doc().descendants((node, pos) => { if (node.type.name === 'horizontalRule') hrPos = pos })
    editor.commands.setNodeSelection(hrPos)
    assert.equal(win.moveBlock('up'), true)
    assert.equal(types()[0], 'groupBlock')
    assert.equal(editor.state.selection.node?.type.name, 'horizontalRule')
  })

  test('does nothing in code view', () => {
    load([P('One'), P('Two')].join('\n\n'))
    editor.commands.setTextSelection(caretIn('Two'))
    win.document.getElementById('btn-code-view').dispatchEvent(new win.MouseEvent('click', { bubbles: true }))
    assert.equal(win.moveBlock('up'), false)
    assert.deepEqual(texts(), ['One', 'Two'])
  })

  test('does nothing while an AI operation is pending', () => {
    load([P('One'), P('Two is long enough')].join('\n\n'))
    const from = caretIn('Two')
    editor.commands.setTextSelection({ from, to: from + 15 })
    assert.ok(win.beginAIOperation())
    assert.equal(win.moveBlock('up'), false)
    assert.deepEqual(texts(), ['One', 'Two is long enough'])
  })

  test('does nothing while the find bar is open', () => {
    load([P('One'), P('Two')].join('\n\n'))
    editor.commands.setTextSelection(caretIn('Two'))
    win.openFindBar()
    assert.equal(win.moveBlock('up'), false)
    assert.deepEqual(texts(), ['One', 'Two'])
  })

  test('a move sends contentChanged to Swift', async () => {
    load([P('One'), P('Two')].join('\n\n'))
    editor.commands.setTextSelection(caretIn('Two'))
    const before = sentToSwift.length
    assert.equal(win.moveBlock('up'), true)
    await new Promise(resolve => setTimeout(resolve, 650))
    assert.ok(sentToSwift.length > before)
    assert.match(sentToSwift.at(-1), /Two[\s\S]*One/)
  })

  test('typing straight after a move is its own undo step', () => {
    load([P('A'), P('B')].join('\n\n'))
    editor.commands.setTextSelection(caretIn('A') + 1)
    assert.equal(win.moveBlock('down'), true)
    editor.commands.insertContent('x')
    assert.deepEqual(texts(), ['B', 'Ax'])
    editor.commands.undo()
    assert.deepEqual(texts(), ['B', 'A'])
  })
})

describe('grip overlay', () => {
  const grip = () => win.document.getElementById('block-grip')
  const visible = () => grip().classList.contains('visible')
  const handle = () => win._blockGrip

  test('#block-grip exists outside .ProseMirror and is aria-hidden', () => {
    assert.ok(grip())
    assert.equal(grip().closest('.ProseMirror'), null)
    assert.ok(grip().closest('#editor-wrap'))
    assert.equal(grip().getAttribute('aria-hidden'), 'true')
    assert.equal(grip().hasAttribute('tabindex'), false)
  })

  test('getContent() never contains block-grip markup after hovering', () => {
    load([H(2, 'Title'), P('One')].join('\n\n'))
    handle().showFor(0)
    assert.equal(visible(), true)
    editor.commands.setTextSelection(caretAt('One'))
    editor.commands.insertContent('x')
    handle().showFor(1)
    assert.doesNotMatch(editor.getHTML(), /block-grip/)
    assert.doesNotMatch(win.getContent(), /block-grip/)
  })

  test('blockGlyphSVG returns an <svg> for every glyph id blockMarker can return', () => {
    for (const id of ['image', 'gallery', 'embed', 'table', 'columns', 'group', 'buttons', 'chevron', 'accordion', 'tabs', 'synced', 'html', 'quote']) {
      assert.match(win.blockGlyphSVG(id), /^<svg [^>]*>[\s\S]+<\/svg>$/, id)
    }
  })

  test('Quote is drawn, so it cannot be mistaken for the Pullquote mark', () => {
    load([B_QUOTE(), B_PULLQUOTE()].join('\n\n'))
    assert.equal(win.blockMarker(doc().child(0)).kind, 'glyph')
    assert.equal(win.blockMarker(doc().child(1)).kind, 'text')
  })

  test('Details and Accordion get different glyphs', () => {
    assert.notEqual(win.blockGlyphSVG('accordion'), win.blockGlyphSVG('chevron'))
    assert.notEqual(win.blockGlyphSVG('accordion'), win.blockGlyphSVG('html'))
  })

  test('the bulleted-list marker has its own size class', () => {
    load([P('A'), SAMPLES.find(s => s.type === 'bulletList').html].join('\n\n'))
    handle().showFor(1)
    assert.ok(grip().querySelector('.block-grip-mark-bullet'))
  })

  test('the grip shows the block marker', () => {
    load([H(3, 'Title'), SAMPLES.find(s => s.type === 'table').html].join('\n\n'))
    handle().showFor(0)
    assert.equal(grip().textContent, 'h3')
    handle().showFor(1)
    assert.match(grip().innerHTML, /<svg/)
  })

  test('the grip hides on keydown', () => {
    load([P('One'), P('Two')].join('\n\n'))
    handle().showFor(0)
    editor.view.dom.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'a', bubbles: true }))
    assert.equal(visible(), false)
  })

  test('a ⌘ keydown leaves the grip visible', () => {
    load([H(2, 'One'), P('Two')].join('\n\n'))
    handle().showFor(0)
    editor.view.dom.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Meta', metaKey: true, bubbles: true }))
    assert.equal(visible(), true)
    editor.view.dom.dispatchEvent(new win.KeyboardEvent('keyup', { key: 'Meta', bubbles: true }))
  })

  test('the grip hides when the document changes', () => {
    load([P('One'), P('Two')].join('\n\n'))
    handle().showFor(1)
    editor.commands.setTextSelection(caretAt('Two'))
    win.moveBlock('up')
    assert.equal(visible(), false)
  })

  test('the grip stays hidden in code view, during an AI operation, and with the find bar open', () => {
    load([P('One'), P('Two is long enough')].join('\n\n'))
    win.document.getElementById('btn-code-view').dispatchEvent(new win.MouseEvent('click', { bubbles: true }))
    handle().showFor(0)
    assert.equal(visible(), false, 'code view')

    load([P('One'), P('Two is long enough')].join('\n\n'))
    const from = caretAt('Two')
    editor.commands.setTextSelection({ from, to: from + 15 })
    assert.ok(win.beginAIOperation())
    handle().showFor(0)
    assert.equal(visible(), false, 'AI operation')

    load([P('One'), P('Two')].join('\n\n'))
    win.openFindBar()
    handle().showFor(0)
    assert.equal(visible(), false, 'find bar')
  })

  test('no grip for the footnotes list or the generated trailing paragraph', () => {
    load([P('Body' + marker(ID)), FOOTNOTES].join('\n\n'), META(ID))
    handle().showFor(doc().childCount - 1)
    assert.equal(visible(), false, 'footnotes list')
    load([P('A'), SEP].join('\n\n'))
    handle().showFor(2)
    assert.equal(visible(), false, 'generated paragraph')
  })

  test('clicking the grip on a paragraph puts the caret at its start', () => {
    load([P('One'), P('Two')].join('\n\n'))
    handle().showFor(1)
    handle().click()
    assert.equal(editor.state.selection.empty, true)
    assert.equal(editor.state.selection.from, win.topLevelPos(doc(), 1) + 1)
  })

  test('clicking the grip on a list puts the caret in its first item', () => {
    load([P('One'), SAMPLES.find(s => s.type === 'bulletList').html].join('\n\n'))
    handle().showFor(1)
    handle().click()
    assert.equal(editor.state.selection.empty, true)
    assert.equal(editor.state.selection.$from.parent.isTextblock, true)
    assert.equal(editor.state.selection.$from.parent.textContent, 'one')
  })

  test('clicking the grip on an embed node-selects it', () => {
    load([P('One'), SAMPLES.find(s => s.type === 'embedBlock').html].join('\n\n'))
    handle().showFor(1)
    handle().click()
    assert.equal(editor.state.selection.node?.type.name, 'embedBlock')
  })
})

function caretAt(text) {
  let at = null
  doc().descendants((node, pos) => { if (at === null && node.isText && node.text.includes(text)) at = pos + node.text.indexOf(text) })
  return at
}

describe('grip drag', () => {
  const stubTransfer = () => {
    const calls = { clearData: 0, setData: 0, setDragImage: [] }
    return {
      calls,
      dataTransfer: {
        effectAllowed: 'uninitialized',
        dropEffect: 'none',
        clearData() { calls.clearData++ },
        setData() { calls.setData++ },
        setDragImage(el, x, y) { calls.setDragImage.push([el, x, y]) },
      },
    }
  }
  const blockMovePlugin = () => editor.state.plugins.find(p => p.key.startsWith('blockMove$'))
  const dropEvent = clientY => ({ clientY, clientX: 0, preventDefault() {}, dataTransfer: stubTransfer().dataTransfer })
  const texts = () => { const out = []; doc().forEach(n => out.push(n.textContent)); return out }

  test('gripDragStart clears the pasteboard and never sets data', () => {
    load([P('One'), P('Two')].join('\n\n'))
    const { calls, dataTransfer } = stubTransfer()
    win.gripDragStart(editor.view, { dataTransfer }, { from: 1, to: 2 })
    assert.equal(calls.clearData, 1)
    assert.equal(calls.setData, 0)
    assert.equal(calls.setDragImage.length, 1)
    assert.ok(calls.setDragImage[0][0] instanceof win.HTMLElement)
    win.endGripDrag(editor.view)
  })

  test('gripDragStart sets view.dragging with move: true and the block slice', () => {
    load([P('One'), SAMPLES.find(s => s.type === 'table').html, P('Two')].join('\n\n'))
    win.gripDragStart(editor.view, stubTransfer(), { from: 1, to: 2 })
    assert.equal(editor.view.dragging.move, true)
    const expected = doc().slice(win.topLevelPos(doc(), 1), win.topLevelPos(doc(), 2)).content
    assert.ok(editor.view.dragging.slice.content.eq(expected))
    win.endGripDrag(editor.view)
    assert.equal(editor.view.dragging, null)
  })

  test('gripDragStart with a section range carries every block in the section', () => {
    load([P('x'), H(2, 'S'), P('a'), H(3, 'T'), P('b'), H(2, 'U')].join('\n\n'))
    win.gripDragStart(editor.view, stubTransfer(), { from: 1, to: win.sectionEnd(doc(), 1) })
    const slice = editor.view.dragging.slice.content
    assert.equal(slice.childCount, 4)
    assert.deepEqual([0, 1, 2, 3].map(i => slice.child(i).textContent), ['S', 'a', 'T', 'b'])
    win.endGripDrag(editor.view)
  })

  test('the drag card shows the marker, the first line and "+ N more" for a section', () => {
    load([P('x'), H(2, 'Section title'), P('a'), P('b')].join('\n\n'))
    const { calls, dataTransfer } = stubTransfer()
    win.gripDragStart(editor.view, { dataTransfer }, { from: 1, to: 4 })
    const card = calls.setDragImage[0][0]
    assert.match(card.textContent, /h2/)
    assert.match(card.textContent, /Section title/)
    assert.match(card.textContent, /\+ 2 more/)
    assert.equal(card.closest('.ProseMirror'), null)
    win.endGripDrag(editor.view)
  })

  test('handleDrop returns false for a drag the grip did not start', () => {
    load([P('One'), P('Two')].join('\n\n'))
    win.endGripDrag(editor.view)
    assert.equal(blockMovePlugin().props.handleDrop(editor.view, dropEvent(100), null, true), false)
    assert.deepEqual(texts(), ['One', 'Two'])
  })

  test('handleDrop for a grip drag moves the block and returns true', () => {
    load([P('One'), P('Two'), P('Three')].join('\n\n'))
    win.gripDragStart(editor.view, stubTransfer(), { from: 0, to: 1 })
    assert.equal(blockMovePlugin().props.handleDrop(editor.view, dropEvent(100), null, true), true)
    assert.deepEqual(texts(), ['Two', 'Three', 'One'])
    assert.equal(editor.view.dragging, null)
    editor.commands.undo()
    assert.deepEqual(texts(), ['One', 'Two', 'Three'])
  })

  test('a grip drop on a no-op gap changes nothing and adds no undo step', () => {
    load([P('One'), P('Two'), P('Three')].join('\n\n'))
    win.gripDragStart(editor.view, stubTransfer(), { from: 2, to: 3 })
    assert.equal(blockMovePlugin().props.handleDrop(editor.view, dropEvent(100), null, true), true)
    assert.deepEqual(texts(), ['One', 'Two', 'Three'])
    assert.equal(editor.can().undo(), false)
  })

  test('a grip drop released over the margin moves the block once', () => {
    load([P('One'), P('Two'), P('Three')].join('\n\n'))
    win.gripDragStart(editor.view, stubTransfer(), { from: 0, to: 1 })
    const drop = new win.Event('drop', { bubbles: true, cancelable: true })
    Object.defineProperty(drop, 'clientY', { value: 100 })
    win.document.getElementById('editor-wrap').dispatchEvent(drop)
    assert.equal(drop.defaultPrevented, true)
    assert.deepEqual(texts(), ['Two', 'Three', 'One'])
    editor.commands.undo()
    assert.deepEqual(texts(), ['One', 'Two', 'Three'])
  })

  test('nearestGap picks the closest gap, ties go to the earlier one', () => {
    assert.equal(win.nearestGap([0, 10, 20], 5), 0)
    assert.equal(win.nearestGap([0, 10, 20], 6), 1)
    assert.equal(win.nearestGap([0, 10, 20], 14), 1)
    assert.equal(win.nearestGap([0, 10, 20], -50), 0)
    assert.equal(win.nearestGap([0, 10, 20], 500), 2)
  })

  test('gapYs has one entry per gap, none after the footnotes list', () => {
    load([P('One' + marker(ID)), P('Two'), FOOTNOTES].join('\n\n'), META(ID))
    assert.equal(win.gapYs(editor.view).length, win.movableCount(doc()) + 1)
  })
})

describe('grip drag from the grip element', () => {
  const grip = () => win.document.getElementById('block-grip')
  const stubTransfer = () => ({ effectAllowed: 'uninitialized', dropEffect: 'none', clearData() {}, setData() {}, setDragImage() {} })
  const dragstart = (modifiers = {}) => {
    const e = new win.Event('dragstart', { bubbles: true, cancelable: true })
    Object.defineProperty(e, 'dataTransfer', { value: stubTransfer() })
    for (const [key, value] of Object.entries(modifiers)) Object.defineProperty(e, key, { value })
    grip().dispatchEvent(e)
  }
  const blockMovePlugin = () => editor.state.plugins.find(p => p.key.startsWith('blockMove$'))

  test('⌘ read from the mouse drags the section even when the web view never saw the key', () => {
    load([P('x'), H(2, 'S'), P('a'), H(2, 'T')].join('\n\n'))
    win._blockGrip.showFor(1)
    grip().dispatchEvent(new win.MouseEvent('mouseenter'))
    grip().dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, metaKey: true }))
    dragstart({ metaKey: true })
    assert.equal(editor.view.dragging.slice.content.childCount, 2)
    grip().dispatchEvent(new win.Event('dragend', { bubbles: true }))
    assert.equal(win.activeGripDrag(), null)
    grip().dispatchEvent(new win.MouseEvent('mousemove', { bubbles: true, metaKey: false }))
  })

  // WebKit never starts a drag on a ⇧-press (EventHandler::handleMousePressEvent), so ⇧ must not be the section key.
  test('⇧ does not select the section', () => {
    load([P('x'), H(2, 'S'), P('a'), H(2, 'T')].join('\n\n'))
    win._blockGrip.showFor(1)
    grip().dispatchEvent(new win.MouseEvent('mouseenter'))
    editor.view.dom.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Shift', shiftKey: true, bubbles: true }))
    grip().dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, shiftKey: true }))
    assert.equal(grip().classList.contains('section'), false)
    dragstart({ shiftKey: true })
    assert.equal(editor.view.dragging.slice.content.childCount, 1)
    grip().dispatchEvent(new win.Event('dragend', { bubbles: true }))
    editor.view.dom.dispatchEvent(new win.KeyboardEvent('keyup', { key: 'Shift', bubbles: true }))
  })

  test('window.setSectionKey shows the section while the pointer is on a heading\'s grip', () => {
    load([P('x'), H(2, 'S'), P('a'), H(2, 'T')].join('\n\n'))
    win._blockGrip.showFor(1)
    grip().dispatchEvent(new win.MouseEvent('mouseenter'))
    win.setSectionKey(true)
    assert.equal(grip().classList.contains('section'), true)
    win.setSectionKey(false)
    assert.equal(grip().classList.contains('section'), false)
  })

  test('a mousedown elsewhere ends a grip drag whose dragend never came', () => {
    load([P('One'), P('Two')].join('\n\n'))
    win.gripDragStart(editor.view, { dataTransfer: stubTransfer() }, { from: 0, to: 1 })
    editor.view.dom.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true }))
    assert.equal(win.activeGripDrag(), null)
    assert.equal(blockMovePlugin().props.handleDrop(editor.view, { clientY: 100 }, null, true), false)
  })

  test('autoscroll during a grip drag does not hide the drag source', () => {
    load([P('One'), P('Two')].join('\n\n'))
    win._blockGrip.showFor(0)
    win.gripDragStart(editor.view, { dataTransfer: stubTransfer() }, { from: 0, to: 1 })
    win.document.getElementById('editor-wrap').dispatchEvent(new win.Event('scroll'))
    assert.equal(grip().classList.contains('visible'), true)
    win.endGripDrag(editor.view)
  })
})

describe('the section range is fixed at mousedown', () => {
  test('letting go of ⌘ between mousedown and dragstart still drags the section', () => {
    const grip = win.document.getElementById('block-grip')
    load([P('x'), H(2, 'S'), P('a'), H(2, 'T')].join('\n\n'))
    win._blockGrip.showFor(1)
    grip.dispatchEvent(new win.MouseEvent('mouseenter'))
    grip.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, metaKey: true }))
    grip.dispatchEvent(new win.MouseEvent('mousemove', { bubbles: true, buttons: 1, metaKey: false }))
    const e = new win.Event('dragstart', { bubbles: true, cancelable: true })
    Object.defineProperty(e, 'dataTransfer', { value: { clearData() {}, setData() {}, setDragImage() {} } })
    Object.defineProperty(e, 'metaKey', { value: false })
    grip.dispatchEvent(e)
    assert.equal(editor.view.dragging.slice.content.childCount, 2)
    grip.dispatchEvent(new win.Event('dragend', { bubbles: true }))
    grip.dispatchEvent(new win.MouseEvent('mousemove', { bubbles: true, metaKey: false }))
  })
})

describe('Dropcursor during a grip drag', () => {
  test('the CSS hides ProseMirror\'s drop cursor while body.block-dragging is set', () => {
    const css = [...win.document.querySelectorAll('style')].map(s => s.textContent).join('\n')
    assert.match(css, /body\.block-dragging \.prosemirror-dropcursor-block,\s*body\.block-dragging \.prosemirror-dropcursor-inline\s*\{\s*display:\s*none;?\s*\}/)
  })

  test('a drag from the grip sets body.block-dragging until dragend', () => {
    const grip = win.document.getElementById('block-grip')
    load([P('One'), P('Two')].join('\n\n'))
    win._blockGrip.showFor(0)
    const e = new win.Event('dragstart', { bubbles: true, cancelable: true })
    Object.defineProperty(e, 'dataTransfer', { value: { clearData() {}, setData() {}, setDragImage() {} } })
    grip.dispatchEvent(e)
    assert.equal(win.document.body.classList.contains('block-dragging'), true)
    grip.dispatchEvent(new win.Event('dragend', { bubbles: true }))
    assert.equal(win.document.body.classList.contains('block-dragging'), false)
  })
})

describe('the press fixes the section range', () => {
  const grip = () => win.document.getElementById('block-grip')
  const dragstart = (modifiers = {}) => {
    const e = new win.Event('dragstart', { bubbles: true, cancelable: true })
    Object.defineProperty(e, 'dataTransfer', { value: { clearData() {}, setData() {}, setDragImage() {} } })
    for (const [key, value] of Object.entries(modifiers)) Object.defineProperty(e, key, { value })
    grip().dispatchEvent(e)
  }
  const press = () => {
    load([P('x'), H(2, 'S'), P('a'), H(2, 'T')].join('\n\n'))
    win._blockGrip.showFor(1)
    grip().dispatchEvent(new win.MouseEvent('mouseenter'))
    grip().dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, metaKey: true }))
  }
  const finish = () => {
    const count = editor.view.dragging.slice.content.childCount
    grip().dispatchEvent(new win.Event('dragend', { bubbles: true }))
    win.setSectionKey(false)
    return count
  }

  test('leaving the grip between mousedown and dragstart still drags the section', () => {
    press()
    grip().dispatchEvent(new win.MouseEvent('mouseleave', { metaKey: true, buttons: 1 }))
    dragstart({ metaKey: true })
    assert.equal(finish(), 2)
  })

  test('a ⌘ key-up between mousedown and dragstart still drags the section', () => {
    press()
    editor.view.dom.dispatchEvent(new win.KeyboardEvent('keyup', { key: 'Meta', bubbles: true }))
    win.setSectionKey(false)
    dragstart({ metaKey: false })
    assert.equal(finish(), 2)
  })
})

describe('hover beside a floated image', () => {
  const grip = () => win.document.getElementById('block-grip')
  const wrap = () => win.document.getElementById('editor-wrap')
  const rect = (top, bottom, left = 100, right = 600) => ({ top, bottom, left, right, width: right - left, height: bottom - top, x: left, y: top })
  const IMAGE = SAMPLES.find(s => s.type === 'image').html
  let stubbed = []

  // ProseMirror reuses DOM nodes across loads, so the stubs must not outlive the test.
  afterEach(() => {
    stubbed.forEach(el => { delete el.getBoundingClientRect })
    stubbed = []
  })

  function layout() {
    load([P('Before'), IMAGE, P('Wraps beside the image'), P('After')].join('\n\n'))
    const dom = i => editor.view.nodeDOM(win.topLevelPos(doc(), i))
    const rects = [rect(0, 30), rect(40, 200, 400, 600), rect(40, 80), rect(210, 240)]
    rects.forEach((r, i) => { dom(i).getBoundingClientRect = () => r; stubbed.push(dom(i)) })
    return dom
  }

  function hover(x, y, target) {
    const original = win.document.elementFromPoint
    win.document.elementFromPoint = () => target
    wrap().dispatchEvent(new win.MouseEvent('mousemove', { bubbles: true, clientX: x, clientY: y }))
    win.document.elementFromPoint = original
  }

  test('the wrapped paragraph gets its grip from the margin', () => {
    layout()
    win._blockGrip.hide()
    hover(50, 60, wrap())
    assert.equal(grip().dataset.label, 'Paragraph')
    assert.equal(grip().classList.contains('visible'), true)
  })

  test('pointing at the image itself shows the image grip', () => {
    const dom = layout()
    win._blockGrip.hide()
    hover(500, 150, dom(1))
    assert.equal(grip().dataset.label, 'Image')
  })
})

describe('review fixes', () => {
  const grip = () => win.document.getElementById('block-grip')
  const texts = () => { const out = []; doc().forEach(n => out.push(n.textContent)); return out }
  const transfer = () => ({ calls: [], clearData() {}, setData() {}, setDragImage(el) { this.calls.push(el) } })
  const blockMovePlugin = () => editor.state.plugins.find(p => p.key.startsWith('blockMove$'))

  test('a grip drop after the document changed mid-drag moves nothing', () => {
    load([P('One'), P('Two'), P('Three')].join('\n\n'))
    win.gripDragStart(editor.view, { dataTransfer: transfer() }, { from: 0, to: 1 })
    editor.commands.setTextSelection(2)
    editor.commands.insertContent('x')
    const before = texts()
    assert.equal(blockMovePlugin().props.handleDrop(editor.view, { clientY: 100 }, null, true), true)
    assert.deepEqual(texts(), before)
    assert.equal(win.activeGripDrag(), null)
  })

  test('a last section does not count the generated trailing paragraph', () => {
    load([P('x'), H(2, 'S'), SEP].join('\n\n'))
    assert.deepEqual(types(), ['paragraph', 'heading', 'horizontalRule', 'paragraph'])
    win._blockGrip.showFor(1)
    grip().dispatchEvent(new win.MouseEvent('mouseenter'))
    grip().dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, metaKey: true }))
    const dataTransfer = transfer()
    const e = new win.Event('dragstart', { bubbles: true, cancelable: true })
    Object.defineProperty(e, 'dataTransfer', { value: dataTransfer })
    Object.defineProperty(e, 'metaKey', { value: true })
    grip().dispatchEvent(e)
    assert.equal(editor.view.dragging.slice.content.childCount, 2)
    assert.match(dataTransfer.calls[0].textContent, /\+ 1 more/)
    grip().dispatchEvent(new win.Event('dragend', { bubbles: true }))
    win.setSectionKey(false)
  })

  test('a mousedown in the text hides the grip', () => {
    load([P('One'), P('Two')].join('\n\n'))
    win._blockGrip.showFor(0)
    editor.view.dom.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true }))
    assert.equal(grip().classList.contains('visible'), false)
  })

  for (const type of ['codeBlock', 'preformatted', 'blockquote', 'pullquote']) {
    test(`clicking the grip on a ${type} puts the caret in its text`, () => {
      load([P('One'), SAMPLES.find(s => s.type === type).html].join('\n\n'))
      win._blockGrip.showFor(1)
      win._blockGrip.click()
      assert.equal(editor.state.selection.empty, true)
      assert.equal(editor.state.selection.$from.parent.isTextblock, true)
      assert.equal(win.topLevelIndexAt(doc(), editor.state.selection.from), 1)
    })
  }
})
