'use strict'

// Live Tiptap tests for unsupported-block preservation — loads the REAL
// editor.html in jsdom, same approach as test-editor-containers.js, because
// the wrap/unwrap path crosses setContent, the passthrough node's parse rule
// and getContent, none of which the pure editor-transforms.js helpers reach.

const { test, describe, before, after } = require('node:test')
const assert = require('node:assert/strict')
const { JSDOM, VirtualConsole } = require('jsdom')
const fs = require('fs')
const path = require('path')
const nodeCrypto = require('crypto')

const htmlPath = path.resolve(__dirname, '../Sources/QuillKit/Resources/editor.html')

let editor
let win

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

  editor = await new Promise((resolve, reject) => {
    let tries = 0
    const t = setInterval(() => {
      if (win._tiptapEditor) { clearInterval(t); resolve(win._tiptapEditor) }
      else if (++tries > 400) { clearInterval(t); reject(new Error('editor never became ready.\n' + logs.join('\n'))) }
    }, 25)
  })
})

after(() => { if (win) win.close() })

describe('block parser and serializer are live in the editor', () => {
  test('window.BlockParser.parse is callable', () => {
    const blocks = win.BlockParser.parse('<!-- wp:paragraph --><p>Hi</p><!-- /wp:paragraph -->')
    assert.equal(blocks.filter(b => b.blockName).length, 1)
  })

  test('window.serializeBlock is callable', () => {
    const src = '<!-- wp:paragraph --><p>Hi</p><!-- /wp:paragraph -->'
    const block = win.BlockParser.parse(src).find(b => b.blockName)
    assert.equal(win.serializeBlock(block), src)
  })
})

describe('unsupported blocks become passthrough cards', () => {
  const load = src => win.setContent(src)

  test('a wrapped shortcode parses into one gutenbergPassthrough node', () => {
    const src = '<!-- wp:shortcode -->[gallery ids="1,2"]<!-- /wp:shortcode -->'
    load(src)
    const node = editor.state.doc.child(0)
    assert.equal(node.type.name, 'gutenbergPassthrough')
    assert.equal(node.attrs.unsupportedSource, src)
    assert.equal(node.attrs.blockLabel, 'Shortcode')
  })

  test('the card shows the label and a peek at the content', () => {
    load('<!-- wp:shortcode -->[gallery ids="1,2"]<!-- /wp:shortcode -->')
    const card = win.document.querySelector('#editor .passthrough-card')
    assert.equal(card.querySelector('.passthrough-card-label').textContent, 'Shortcode')
    assert.match(card.querySelector('.passthrough-card-peek').textContent, /\[gallery ids="1,2"\]/)
  })

  test('the peek is truncated for a long block', () => {
    load('<!-- wp:html --><div>' + 'x'.repeat(400) + '</div><!-- /wp:html -->')
    const peek = win.document.querySelector('#editor .passthrough-card-peek').textContent
    assert.ok(peek.length <= 123, `peek was ${peek.length} chars`)
    assert.match(peek, /…$/)
  })

  test('the peek renders markup as text, never as live DOM', () => {
    load('<!-- wp:html --><div class="promo"><b>Hi</b></div><!-- /wp:html -->')
    const peek = win.document.querySelector('#editor .passthrough-card-peek')
    assert.equal(peek.querySelector('b'), null)
    assert.match(peek.textContent, /<b>Hi<\/b>/)
  })

  test('the card keeps the existing hint line', () => {
    load('<!-- wp:calendar /-->')
    const hint = win.document.querySelector('#editor .passthrough-card-hint').textContent
    assert.equal(hint, 'Not editable in the visual editor; use Code View (</>)')
  })

  test('an ordinary passthrough block still renders a card with no peek', () => {
    win.setContent('<!-- wp:spacer --><div class="wp-block-spacer" style="height:8px"></div><!-- /wp:spacer -->')
    const card = win.document.querySelector('#editor .passthrough-card')
    assert.equal(card.querySelector('.passthrough-card-label').textContent, 'Spacer')
    assert.equal(card.querySelector('.passthrough-card-peek'), null)
  })
})

describe('the wrap applies at post_content entry points only', () => {
  const SHORTCODE = '<!-- wp:shortcode -->[gallery ids="1,2"]<!-- /wp:shortcode -->'

  test('setContent wraps, so an edit elsewhere cannot destroy the block', () => {
    win.setContent('<p>Intro</p>' + SHORTCODE)
    editor.commands.setTextSelection(2)
    editor.commands.insertContent('X')
    assert.match(win.getContent(), /<!-- wp:shortcode -->\[gallery ids="1,2"\]<!-- \/wp:shortcode -->/)
  })

  test('an unedited post still round-trips byte-identically', () => {
    const src = '<p>Intro</p>' + SHORTCODE
    win.setContent(src)
    assert.equal(win.getContent(), src)
  })

  test('code view shows the real source, not the wrapper', () => {
    win.setContent(SHORTCODE)
    win.document.getElementById('btn-code-view').dispatchEvent(new win.MouseEvent('click', { bubbles: true }))
    const shown = win.document.getElementById('code-editor').value
    assert.match(shown, /\[gallery ids="1,2"\]/)
    assert.doesNotMatch(shown, /quill-unsupported/)
    win.document.getElementById('btn-code-view').dispatchEvent(new win.MouseEvent('click', { bubbles: true }))
  })

  test('a block hand-edited in code view is re-wrapped on exit', () => {
    win.setContent(SHORTCODE)
    win.document.getElementById('btn-code-view').dispatchEvent(new win.MouseEvent('click', { bubbles: true }))
    const ta = win.document.getElementById('code-editor')
    ta.value = '<!-- wp:shortcode -->[gallery ids="9,9"]<!-- /wp:shortcode -->'
    ta.dispatchEvent(new win.Event('input', { bubbles: true }))
    win.document.getElementById('btn-code-view').dispatchEvent(new win.MouseEvent('click', { bubbles: true }))
    assert.equal(editor.state.doc.child(0).type.name, 'gutenbergPassthrough')
    editor.commands.setTextSelection(1)
    assert.match(win.getContent(), /\[gallery ids="9,9"\]/)
  })

  test('the AI reject path does not double-wrap', () => {
    win.setContent(SHORTCODE)
    const internal = editor.getHTML()
    editor.commands.setContent(internal, false)
    assert.equal(editor.state.doc.child(0).type.name, 'gutenbergPassthrough')
    assert.equal((editor.getHTML().match(/wp-block-quill-unsupported/g) || []).length, 1)
  })
})

describe('the unsupported-block corpus survives an edit', () => {
  const src = fs.readFileSync(path.resolve(__dirname, 'fixtures/unsupported-blocks.html'), 'utf8')
  const editSomewhereElse = () => {
    editor.commands.setTextSelection(2)
    editor.commands.insertContent('X')
  }

  test('round-trips byte-identically with no edit', () => {
    win.setContent(src)
    assert.equal(win.getContent(), src)
  })

  test('every unsupported block survives an edit elsewhere', () => {
    win.setContent(src)
    editSomewhereElse()
    const out = win.getContent()
    for (const marker of [
      'wp:html', 'wp:shortcode', 'wp:calendar', 'wp:navigation',
      'wp:block {"ref":1234}', 'wp:nextpage', 'wp:more', 'wp:acme/widget',
    ]) {
      assert.ok(out.includes('<!-- ' + marker), `lost ${marker}`)
    }
    assert.match(out, /<div class="promo"><b>Hi<\/b><\/div>/)
    assert.match(out, /\[gallery ids="1284,1285"\]/)
    assert.match(out, /<div class="acme-widget" data-x="1">Widget<\/div>/)
  })

  test('the edit itself lands in the prose', () => {
    win.setContent(src)
    editSomewhereElse()
    assert.match(win.getContent(), /<p>OXpening prose\.<\/p>/)
  })

  test('saving twice is idempotent', () => {
    win.setContent(src)
    editSomewhereElse()
    const once = win.getContent()
    win.setContent(once)
    assert.equal(win.getContent(), once)
  })

  test('no wrapper markup reaches the saved output', () => {
    win.setContent(src)
    editSomewhereElse()
    assert.doesNotMatch(win.getContent(), /quill-unsupported/)
  })

  test('each unsupported block renders its own card', () => {
    win.setContent(src)
    const labels = Array.from(win.document.querySelectorAll('#editor .passthrough-card-label'))
      .map(el => el.textContent)
    assert.equal(labels.length, 8)
  })
})

describe('the alarm reports only genuine loss', () => {
  const posted = []
  const corpus = () => fs.readFileSync(path.resolve(__dirname, 'fixtures/unsupported-blocks.html'), 'utf8')

  before(() => {
    win.webkit = win.webkit || {}
    win.webkit.messageHandlers = Object.assign({}, win.webkit.messageHandlers, {
      blocksAtRisk: { postMessage: m => posted.push(m) },
    })
  })

  test('the transform helpers the editor needs are on window', () => {
    for (const name of ['blockSourceSlices', 'wrapUnsupportedBlocks', 'unrepresentedBlockNames', 'shortBlockName']) {
      assert.equal(typeof win[name], 'function', `window.${name}`)
    }
  })

  test('a fully preserved post posts nothing', () => {
    posted.length = 0
    win.setContent(corpus())
    assert.deepEqual(posted, [])
  })

  test('an ordinary post posts nothing', () => {
    posted.length = 0
    win.setContent('<!-- wp:paragraph --><p>A</p><!-- /wp:paragraph -->')
    assert.deepEqual(posted, [])
  })

  test('every real fixture posts nothing', () => {
    const dir = path.resolve(__dirname, 'fixtures')
    for (const name of fs.readdirSync(dir).filter(f => f.endsWith('.html'))) {
      posted.length = 0
      win.setContent(fs.readFileSync(path.join(dir, name), 'utf8'))
      assert.deepEqual(posted, [], name)
    }
  })

  // The check must not share the wrap's assumptions, or it goes green in
  // exactly the case it exists to catch.
  test('a post whose block the wrap missed is reported', () => {
    const real = win.wrapUnsupportedBlocks
    win.wrapUnsupportedBlocks = html => html
    try {
      posted.length = 0
      win.setContent(corpus())
    } finally {
      win.wrapUnsupportedBlocks = real
    }
    assert.equal(posted.length, 1)
    assert.deepEqual(Array.from(posted[0].names).sort(), ['acme/widget', 'block', 'calendar', 'html', 'more', 'navigation', 'nextpage', 'shortcode'])
  })

  test('the tripwire goes quiet again once the wrap is restored', () => {
    posted.length = 0
    win.setContent(corpus())
    assert.deepEqual(posted, [])
  })
})

// Banner state 4: after a save that removed a block, reopening the post must
// be quiet — the block is gone from the content, so nothing is missing.
describe('reopening a post that already lost a block is quiet', () => {
  const posted = []
  before(() => {
    win.webkit = win.webkit || {}
    win.webkit.messageHandlers = Object.assign({}, win.webkit.messageHandlers, {
      blocksAtRisk: { postMessage: m => posted.push(m) },
    })
  })

  test('content saved with the wrap disabled reloads with no alarm', () => {
    const src = fs.readFileSync(path.resolve(__dirname, 'fixtures/unsupported-blocks.html'), 'utf8')
    const real = win.wrapUnsupportedBlocks
    win.wrapUnsupportedBlocks = html => html
    let squashed
    try {
      win.setContent(src)
      editor.commands.setTextSelection(2)
      editor.commands.insertContent('X')
      squashed = win.getContent()
    } finally {
      win.wrapUnsupportedBlocks = real
    }
    assert.doesNotMatch(squashed, /wp:calendar/)
    posted.length = 0
    win.setContent(squashed)
    assert.deepEqual(posted, [])
  })
})

// A modeled block name is not a guarantee a node can hold it: a self-closing
// separator saves no markup, so it used to be dropped on the first edit and
// the alarm caught it. It is now wrapped like any other unsupported block.
describe('a modeled block that saves no markup is preserved, not reported', () => {
  const posted = []
  const SRC = '<p>Intro</p><!-- wp:separator /-->'

  before(() => {
    win.webkit = win.webkit || {}
    win.webkit.messageHandlers = Object.assign({}, win.webkit.messageHandlers, {
      blocksAtRisk: { postMessage: m => posted.push(m) },
    })
  })

  test('it raises no alarm on load', () => {
    posted.length = 0
    win.setContent(SRC)
    assert.deepEqual(posted, [])
  })

  test('it survives an edit elsewhere', () => {
    win.setContent(SRC)
    editor.commands.setTextSelection(2)
    editor.commands.insertContent('X')
    const out = win.getContent()
    assert.match(out, /<!-- wp:separator \/-->/)
    assert.doesNotMatch(out, /quill-unsupported/)
  })

  test('a separator WordPress actually wrote stays an editable rule', () => {
    win.setContent('<!-- wp:separator --><hr class="wp-block-separator has-alpha-channel-opacity"/><!-- /wp:separator -->')
    assert.equal(editor.state.doc.child(0).type.name, 'horizontalRule')
  })
})

// Harness-only: verified not to reproduce in the app, where loading a post
// leaves no NodeSelection on the atom. Kept so these suites can drive the real
// window.setContent instead of each one prefixing a reset of its own.
describe('loading an image post after an atom-only post', () => {
  const IMG = '<!-- wp:image {"id":9} -->\n<figure class="wp-block-image"><img src="https://x.test/a.jpg" alt="" class="wp-image-9"/></figure>\n<!-- /wp:image -->'
  const firstType = () => editor.state.doc.child(0).type.name

  test('an image loads after a gallery-only post', () => {
    win.setContent(fs.readFileSync(path.resolve(__dirname, 'fixtures/gallery-block.html'), 'utf8'))
    win.setContent(IMG)
    assert.equal(firstType(), 'image')
  })

  test('an image loads after an embed-only post', () => {
    win.setContent(fs.readFileSync(path.resolve(__dirname, 'fixtures/settings-embed.html'), 'utf8'))
    win.setContent(IMG)
    assert.equal(firstType(), 'image')
  })

  test('the gallery-only post itself still loads', () => {
    win.setContent(IMG)
    win.setContent(fs.readFileSync(path.resolve(__dirname, 'fixtures/gallery-block.html'), 'utf8'))
    assert.equal(firstType(), 'galleryBlock')
  })
})
