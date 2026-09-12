'use strict'

// Live Tiptap tests for the container block nodes (columns, details, buttons,
// accordion, tabs) — loads the REAL editor.html in jsdom, same approach as
// test-editor-gallery.js, because a custom node's parseHTML/renderHTML and its
// priority against gutenbergPassthrough can't be exercised through the pure
// editor-transforms.js helpers.

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

describe('columns block', () => {
  before(() => { editor.commands.setContent('<p></p>', false) })

  test('inserts the requested number of columns', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertColumns(3)
    const node = editor.state.doc.child(0)
    assert.equal(node.type.name, 'columnsBlock')
    assert.equal(node.childCount, 3)
  })

  test('typing lands in the targeted column only', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertColumns(2)
    editor.commands.insertContent('Left')
    const cols = editor.state.doc.child(0)
    assert.match(cols.child(0).textContent, /Left/)
    assert.equal(cols.child(1).textContent, '')
  })

  test('parses a real columns block from WordPress markup', () => {
    editor.commands.setContent(
      '<!-- wp:columns --><div class="wp-block-columns">' +
      '<!-- wp:column --><div class="wp-block-column"><p>A</p></div><!-- /wp:column -->' +
      '<!-- wp:column --><div class="wp-block-column"><p>B</p></div><!-- /wp:column -->' +
      '</div><!-- /wp:columns -->', false)
    const node = editor.state.doc.child(0)
    assert.equal(node.type.name, 'columnsBlock')
    assert.equal(node.childCount, 2)
  })

  test('saves with wp:columns and wp:column delimiters', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertColumns(2)
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<!-- wp:columns -->/)
    assert.equal((out.match(/<!-- wp:column -->/g) || []).length, 2)
  })

  test('does not stack delimiters across repeated saves', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertColumns(2)
    const once = win.toWordPressHTML(editor.getHTML(), win.document)
    editor.commands.setContent(once, false)
    const twice = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.equal((twice.match(/<!-- wp:columns -->/g) || []).length, 1)
  })

  test('+Col adds a column to the block the cursor is in', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertColumns(2)
    win.document.querySelector('[data-cmd="addColumnBlock"]')
      .dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true }))
    assert.equal(editor.state.doc.child(0).childCount, 3)
  })

  test('-Col removes the current column but never the last one', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertColumns(2)
    const btn = win.document.querySelector('[data-cmd="deleteColumnBlock"]')
    const click = () => btn.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true }))
    click()
    assert.equal(editor.state.doc.child(0).childCount, 1)
    click()
    assert.equal(editor.state.doc.child(0).childCount, 1)
  })

  test('passthrough does not claim a columns block', () => {
    editor.commands.setContent(
      '<div class="wp-block-columns"><div class="wp-block-column"><p>A</p></div></div>', false)
    assert.equal(editor.state.doc.child(0).type.name, 'columnsBlock')
  })
})

describe('details block', () => {
  before(() => { editor.commands.setContent('<p></p>', false) })

  test('inserts a summary and a body', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertDetails()
    const node = editor.state.doc.child(0)
    assert.equal(node.type.name, 'detailsBlock')
    assert.equal(node.child(0).type.name, 'detailsSummary')
  })

  test('parses WordPress details markup', () => {
    editor.commands.setContent(
      '<!-- wp:details --><details class="wp-block-details">' +
      '<summary>S</summary><p>B</p></details><!-- /wp:details -->', false)
    assert.equal(editor.state.doc.child(0).type.name, 'detailsBlock')
  })

  test('saves with wp:details delimiters', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertDetails()
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<!-- wp:details -->/)
  })

  test('summary text stays in the summary on save', () => {
    editor.commands.setContent(
      '<details class="wp-block-details"><summary>Mine</summary><p>Body</p></details>', false)
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<summary>Mine<\/summary>/)
  })
})

describe('buttons block', () => {
  before(() => { editor.commands.setContent('<p></p>', false) })

  test('inserts one button by default', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertButtons()
    const node = editor.state.doc.child(0)
    assert.equal(node.type.name, 'buttonsBlock')
    assert.equal(node.childCount, 1)
  })

  test('parses WordPress buttons markup', () => {
    editor.commands.setContent(
      '<div class="wp-block-buttons">' +
      '<div class="wp-block-button"><a class="wp-block-button__link">Go</a></div></div>', false)
    assert.equal(editor.state.doc.child(0).type.name, 'buttonsBlock')
  })

  test('preserves the button href on save', () => {
    editor.commands.setContent(
      '<div class="wp-block-buttons"><div class="wp-block-button">' +
      '<a class="wp-block-button__link" href="https://x.test">Go</a></div></div>', false)
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /href="https:\/\/x\.test"/)
  })

  test('saves with wp:buttons and wp:button delimiters', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertButtons()
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<!-- wp:buttons -->/)
    assert.match(out, /<!-- wp:button -->/)
  })
})

describe('buttons toolbar controls', () => {
  const press = cmd => win.document.querySelector(`[data-cmd="${cmd}"]`)
    .dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true }))

  test('+Button adds a button and -Button never removes the last', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertButtons()
    press('addButton')
    assert.equal(editor.state.doc.child(0).childCount, 2)
    press('deleteButton')
    assert.equal(editor.state.doc.child(0).childCount, 1)
    press('deleteButton')
    assert.equal(editor.state.doc.child(0).childCount, 1)
  })
})

describe('accordion block', () => {
  before(() => { editor.commands.setContent('<p></p>', false) })

  test('inserts one item with a heading and a panel', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertAccordion()
    const node = editor.state.doc.child(0)
    assert.equal(node.type.name, 'accordionBlock')
    assert.equal(node.child(0).type.name, 'accordionItem')
    assert.equal(node.child(0).child(0).type.name, 'accordionHeading')
    assert.equal(node.child(0).child(1).type.name, 'accordionPanel')
  })

  test('parses the real accordion fixture', () => {
    const src = fs.readFileSync(
      path.resolve(__dirname, 'fixtures/accordion-block.html'), 'utf8')
    editor.commands.setContent(src, false)
    const node = editor.state.doc.child(0)
    assert.equal(node.type.name, 'accordionBlock')
    assert.equal(node.childCount, 2)
  })

  test('heading text round-trips', () => {
    const src = fs.readFileSync(
      path.resolve(__dirname, 'fixtures/accordion-block.html'), 'utf8')
    editor.commands.setContent(src, false)
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /Features/)
  })

  test('saves with all four delimiter types', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertAccordion()
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    for (const n of ['accordion', 'accordion-item', 'accordion-heading', 'accordion-panel']) {
      assert.match(out, new RegExp(`<!-- wp:${n}[ -]`))
    }
  })

  test('does not stack delimiters across repeated saves', () => {
    const src = fs.readFileSync(
      path.resolve(__dirname, 'fixtures/accordion-block.html'), 'utf8')
    editor.commands.setContent(src, false)
    const once = win.toWordPressHTML(editor.getHTML(), win.document)
    editor.commands.setContent(once, false)
    const twice = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.equal((twice.match(/<!-- wp:accordion -->/g) || []).length, 1)
  })
})

describe('accordion toolbar controls', () => {
  const press = cmd => win.document.querySelector(`[data-cmd="${cmd}"]`)
    .dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true }))

  test('+Item adds a section and -Item never removes the last', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertAccordion()
    press('addAccordionItem')
    assert.equal(editor.state.doc.child(0).childCount, 2)
    press('deleteAccordionItem')
    assert.equal(editor.state.doc.child(0).childCount, 1)
    press('deleteAccordionItem')
    assert.equal(editor.state.doc.child(0).childCount, 1)
  })
})

// Real WP 7.1 structure: tabs > tab-list (a button per tab) + tab-panels >
// tab-panel. The label is stored twice — as the button's text and as each
// panel's `label` attribute — so the save transform keeps the two in sync.
describe('tabs block', () => {
  const tabsFixture = fs.readFileSync(
    path.resolve(__dirname, 'fixtures/tabs-block.html'), 'utf8')

  before(() => { editor.commands.setContent('<p></p>', false) })

  test('inserts the requested number of tabs', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertTabs(2)
    const node = editor.state.doc.child(0)
    assert.equal(node.type.name, 'tabsBlock')
    assert.equal(node.child(0).type.name, 'tabList')
    assert.equal(node.child(1).type.name, 'tabPanels')
    assert.equal(node.child(0).childCount, 2)
    assert.equal(node.child(1).childCount, 2)
  })

  test('parses the real fixture into editable nodes', () => {
    editor.commands.setContent(tabsFixture, false)
    const node = editor.state.doc.child(0)
    assert.equal(node.type.name, 'tabsBlock')
    assert.equal(node.child(0).childCount, 2)
    assert.equal(node.child(0).child(0).textContent, 'Tab 1')
    assert.match(node.child(1).child(1).textContent, /tab 2 content/)
  })

  test('round-trips the fixture through the save transform', () => {
    editor.commands.setContent(tabsFixture, false)
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<!-- wp:tabs/)
    assert.match(out, /<!-- wp:tab-list -->/)
    assert.match(out, /<!-- wp:tab-panels -->/)
    assert.equal((out.match(/<!-- wp:tab-panel /g) || []).length, 2)
    assert.match(out, /<button type="button" role="tab">Tab 1<\/button>/)
  })

  test('a panel label follows its tab button text', () => {
    editor.commands.setContent(tabsFixture, false)
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<!-- wp:tab-panel \{"label":"Tab 1"\} -->/)
    assert.match(out, /<!-- wp:tab-panel \{"label":"tab 2"\} -->/)
  })

  test('does not stack delimiters across repeated saves', () => {
    editor.commands.setContent(tabsFixture, false)
    const once = win.toWordPressHTML(editor.getHTML(), win.document)
    editor.commands.setContent(once, false)
    const twice = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.equal((twice.match(/<!-- wp:tabs/g) || []).length, 1)
    assert.equal((twice.match(/<!-- wp:tab-panel /g) || []).length, 2)
  })

  test('passthrough does not claim a tabs block', () => {
    editor.commands.setContent(tabsFixture, false)
    assert.equal(editor.state.doc.child(0).type.name, 'tabsBlock')
  })
})

describe('tabs toolbar controls', () => {
  const press = cmd => win.document.querySelector(`[data-cmd="${cmd}"]`)
    .dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true }))

  test('+Tab adds a button and a panel together', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertTabs(2)
    press('addTab')
    const node = editor.state.doc.child(0)
    assert.equal(node.child(0).childCount, 3)
    assert.equal(node.child(1).childCount, 3)
  })

  test('-Tab removes the pair and never the last tab', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertTabs(2)
    press('deleteTab')
    let node = editor.state.doc.child(0)
    assert.equal(node.child(0).childCount, 1)
    assert.equal(node.child(1).childCount, 1)
    press('deleteTab')
    node = editor.state.doc.child(0)
    assert.equal(node.child(0).childCount, 1)
  })
})

describe('insert menu', () => {
  const openMenu = () => win.document.getElementById('insert-button')
    .dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }))

  test('the toolbar exposes an insert button', () => {
    assert.ok(win.document.getElementById('insert-button'))
  })

  test('the menu lists every container block', () => {
    const items = Array.from(win.document.querySelectorAll('#insert-menu [data-insert]'))
      .map(el => el.dataset.insert)
    for (const n of ['columns', 'accordion', 'tabs', 'details', 'buttons']) {
      assert.ok(items.includes(n), `missing ${n}`)
    }
  })

  test('clicking a menu item inserts that block', () => {
    editor.commands.setContent('<p></p>', false)
    openMenu()
    win.document.querySelector('#insert-menu [data-insert="details"]').click()
    assert.equal(editor.state.doc.child(0).type.name, 'detailsBlock')
  })

  test('the menu closes after an insertion', () => {
    editor.commands.setContent('<p></p>', false)
    openMenu()
    assert.equal(win.document.getElementById('insert-menu').classList.contains('visible'), true)
    win.document.querySelector('#insert-menu [data-insert="buttons"]').click()
    assert.equal(win.document.getElementById('insert-menu').classList.contains('visible'), false)
  })
})

describe('pullquote and preformatted', () => {
  before(() => { editor.commands.setContent('<p></p>', false) })

  test('setPullquote produces a pullquote node', () => {
    editor.commands.setContent('<p>Q</p>', false)
    editor.chain().focus().setPullquote().run()
    assert.equal(editor.state.doc.child(0).type.name, 'pullquote')
  })

  test('a pullquote saves with wp:pullquote delimiters', () => {
    editor.commands.setContent(
      '<figure class="wp-block-pullquote"><blockquote><p>Q</p></blockquote></figure>', false)
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<!-- wp:pullquote -->/)
  })

  test('setPreformatted produces a preformatted node', () => {
    editor.commands.setContent('<p>X</p>', false)
    editor.chain().focus().setPreformatted().run()
    assert.equal(editor.state.doc.child(0).type.name, 'preformatted')
  })

  test('preformatted saves with wp:preformatted delimiters', () => {
    editor.commands.setContent('<pre class="wp-block-preformatted">X</pre>', false)
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<!-- wp:preformatted -->/)
  })

  test('a pullquote is not claimed by passthrough', () => {
    editor.commands.setContent(
      '<figure class="wp-block-pullquote"><blockquote><p>Q</p></blockquote></figure>', false)
    assert.equal(editor.state.doc.child(0).type.name, 'pullquote')
  })
})

describe('pullquote and preformatted round-trips', () => {
  before(() => { editor.commands.setContent('<p></p>', false) })

  const PULLQUOTE =
    '<figure class="wp-block-pullquote"><blockquote><p>Big idea</p>' +
    '<cite>Someone</cite></blockquote></figure>'

  const save = () => win.toWordPressHTML(editor.getHTML(), win.document)

  test('a pullquote wraps its content in exactly one blockquote', () => {
    editor.commands.setContent(PULLQUOTE, false)
    const doc = new JSDOM('<body>' + save() + '</body>').window.document
    const fig = doc.querySelector('figure.wp-block-pullquote')
    assert.ok(fig)
    assert.equal(fig.querySelectorAll('blockquote').length, 1)
    assert.equal(fig.querySelector('blockquote > p').textContent, 'Big idea')
    assert.equal(fig.querySelector('blockquote > cite').textContent, 'Someone')
  })

  test('a pullquote is not stamped with wp-block-quote', () => {
    editor.commands.setContent(PULLQUOTE, false)
    const doc = new JSDOM('<body>' + save() + '</body>').window.document
    assert.equal(doc.querySelector('.wp-block-quote'), null)
  })

  test('repeated save cycles do not grow the pullquote', () => {
    editor.commands.setContent(PULLQUOTE, false)
    const first = save()
    for (let i = 0; i < 3; i++) {
      editor.commands.setContent(first, false)
      assert.equal(save(), first, `save cycle ${i + 2} drifted`)
    }
  })

  test('preformatted is not stamped with wp-block-code', () => {
    editor.commands.setContent('<pre class="wp-block-preformatted">a\n  b</pre>', false)
    const doc = new JSDOM('<body>' + save() + '</body>').window.document
    const pre = doc.querySelector('pre.wp-block-preformatted')
    assert.ok(pre)
    assert.equal(pre.classList.contains('wp-block-code'), false)
  })

  test('preformatted keeps its whitespace through a save cycle', () => {
    editor.commands.setContent('<pre class="wp-block-preformatted">a\n  b\n    c</pre>', false)
    const first = save()
    assert.match(first, /a\n {2}b\n {4}c/)
    editor.commands.setContent(first, false)
    assert.equal(save(), first)
  })
})
