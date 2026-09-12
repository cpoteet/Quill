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

  // The Link mark also matches a[href], so without contentElement it claimed
  // the button's anchor: the label saved twice over, and a button with no href
  // lost its label out of the block entirely.
  test('a button emits exactly one anchor', () => {
    editor.commands.setContent(
      '<div class="wp-block-buttons"><div class="wp-block-button">' +
      '<a class="wp-block-button__link wp-element-button" href="https://x.test">Go</a></div></div>', false)
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.equal((out.match(/<a /g) || []).length, 1)
    assert.match(out, /<a class="wp-block-button__link wp-element-button" href="https:\/\/x\.test">Go<\/a>/)
  })

  test('a button with no href keeps its label inside the block', () => {
    editor.commands.setContent(
      '<div class="wp-block-buttons"><div class="wp-block-button">' +
      '<a class="wp-block-button__link wp-element-button">Go</a></div></div>', false)
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<div class="wp-block-button"><a class="wp-block-button__link wp-element-button">Go<\/a><\/div>/)
    assert.doesNotMatch(out.split('<!-- \/wp:buttons -->')[1] || '', /Go/)
  })

  test('two buttons keep their own labels and order', () => {
    editor.commands.setContent(
      '<div class="wp-block-buttons">' +
      '<div class="wp-block-button"><a class="wp-block-button__link wp-element-button" href="https://a.test">Alpha</a></div>' +
      '<div class="wp-block-button"><a class="wp-block-button__link wp-element-button" href="https://b.test">Beta</a></div></div>', false)
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.equal((out.match(/<a /g) || []).length, 2)
    assert.ok(out.indexOf('Alpha') < out.indexOf('Beta'))
    assert.match(out, /href="https:\/\/a\.test">Alpha</)
    assert.match(out, /href="https:\/\/b\.test">Beta</)
  })

  test('a typed button label survives a save and reload', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertButtons()
    editor.commands.insertContent('Contact')
    const first = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(first, /Contact/)
    editor.commands.setContent(first, false)
    const second = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.equal(second, first)
    assert.match(second, /<div class="wp-block-button"><a[^>]*>Contact<\/a><\/div>/)
  })

  // Applying the Link mark inside a button emitted a second, bare anchor beside
  // the button's own and left the button unlinked, so the link picker writes
  // the node's href attribute instead whenever the cursor is in a button.
  test('applyLink inside a button sets the node href, not a mark', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertButtons()
    editor.commands.insertContent('Contact')
    win.applyLink('https://example.test')
    const button = editor.state.doc.child(0).child(0)
    assert.equal(button.attrs.href, 'https://example.test')
    assert.equal(button.child(0).marks.length, 0)
    assert.equal(button.textContent, 'Contact')
  })

  test('a linked button still emits exactly one anchor', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertButtons()
    editor.commands.insertContent('Contact')
    win.applyLink('https://example.test')
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.equal((out.match(/<a /g) || []).length, 1)
    assert.match(out, /<a class="wp-block-button__link wp-element-button" href="https:\/\/example\.test">Contact<\/a>/)
  })

  test('removeLink inside a button clears the href', () => {
    editor.commands.setContent(
      '<div class="wp-block-buttons"><div class="wp-block-button">' +
      '<a class="wp-block-button__link wp-element-button" href="https://x.test">Go</a></div></div>', false)
    editor.commands.setTextSelection(2)
    win.removeLink()
    assert.equal(editor.state.doc.child(0).child(0).attrs.href, null)
    assert.doesNotMatch(win.toWordPressHTML(editor.getHTML(), win.document), /href=/)
  })

  test('a button link survives a save and reload', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertButtons()
    editor.commands.insertContent('Contact')
    win.applyLink('https://example.test')
    const first = win.toWordPressHTML(editor.getHTML(), win.document)
    editor.commands.setContent(first, false)
    assert.equal(win.toWordPressHTML(editor.getHTML(), win.document), first)
    assert.equal(editor.state.doc.child(0).child(0).attrs.href, 'https://example.test')
  })

  test('applyLink outside a button still applies a link mark', () => {
    editor.commands.setContent('<p>plain text</p>', false)
    editor.commands.setTextSelection({ from: 1, to: 6 })
    win.applyLink('https://example.test')
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<a href="https:\/\/example\.test">plain<\/a>/)
  })

  // The earlier link tests called window.applyLink directly, so a broken
  // toolbar control still passed them. These press the actual buttons.
  const pressToolbar = cmd => {
    const sent = []
    win.webkit = { messageHandlers: { showLinkPicker: { postMessage: m => sent.push(m) } } }
    const el = win.document.querySelector(`[data-cmd="${cmd}"]`)
    assert.ok(el, `[data-cmd="${cmd}"] exists`)
    el.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true }))
    el.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }))
    return sent
  }

  test('the Buttons group Link control opens the link picker', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertButtons()
    editor.commands.insertContent('Contact')
    const sent = pressToolbar('buttonLink')
    assert.equal(sent.length, 1)
    assert.equal(sent[0].href, '')
  })

  test('the Buttons group Link control seeds the picker with the current href', () => {
    editor.commands.setContent(
      '<div class="wp-block-buttons"><div class="wp-block-button">' +
      '<a class="wp-block-button__link wp-element-button" href="https://x.test">Go</a></div></div>', false)
    editor.commands.setTextSelection(2)
    const sent = pressToolbar('buttonLink')
    assert.equal(sent.length, 1)
    assert.equal(sent[0].href, 'https://x.test')
  })

  test('the main toolbar link control opens the picker from inside a button', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertButtons()
    editor.commands.insertContent('Contact')
    const sent = pressToolbar('link')
    assert.equal(sent.length, 1)
  })

  const linkBtnActive = () => ({
    main: win.document.querySelector('[data-cmd="link"]').classList.contains('active'),
    group: win.document.querySelector('[data-cmd="buttonLink"]').classList.contains('active'),
  })

  test('a linked button lights up both link controls', () => {
    editor.commands.setContent(
      '<div class="wp-block-buttons"><div class="wp-block-button">' +
      '<a class="wp-block-button__link wp-element-button" href="https://x.test">Go</a></div></div>', false)
    editor.commands.setTextSelection(2)
    assert.deepEqual(linkBtnActive(), { main: true, group: true })
  })

  test('an unlinked button lights up neither', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertButtons()
    editor.commands.insertContent('Contact')
    assert.deepEqual(linkBtnActive(), { main: false, group: false })
  })

  test('the controls follow applyLink and removeLink', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertButtons()
    editor.commands.insertContent('Contact')
    win.applyLink('https://example.test')
    assert.deepEqual(linkBtnActive(), { main: true, group: true })
    win.removeLink()
    assert.deepEqual(linkBtnActive(), { main: false, group: false })
  })

  test('the group control goes dark outside a button', () => {
    editor.commands.setContent('<p><a href="https://x.test">linked text</a></p>', false)
    editor.commands.setTextSelection(3)
    assert.deepEqual(linkBtnActive(), { main: true, group: false })
  })

  test('the button label is plain text, not a link mark', () => {
    editor.commands.setContent(
      '<div class="wp-block-buttons"><div class="wp-block-button">' +
      '<a class="wp-block-button__link wp-element-button" href="https://x.test">Go</a></div></div>', false)
    const button = editor.state.doc.child(0).child(0)
    assert.equal(button.textContent, 'Go')
    assert.equal(button.child(0).marks.length, 0)
    assert.equal(button.attrs.href, 'https://x.test')
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
    assert.equal(twice, once)
    // Not /wp:accordion -->/ — the block carries {"autoclose":true}, and the
    // trailing space keeps this off wp:accordion-item.
    assert.equal((twice.match(/<!-- wp:accordion(?: \{[\s\S]*?\})? -->/g) || []).length, 1)
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

  // The label lives in a span now, so a real pointer lands on the span, not
  // the button the earlier tests click.
  test('clicking a menu item label inserts that block', () => {
    editor.commands.setContent('<p></p>', false)
    openMenu()
    const label = win.document.querySelector('#insert-menu [data-insert="columns"] .heading-menu-label')
    assert.ok(label, 'menu items carry a heading-menu-label span')
    label.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }))
    assert.equal(editor.state.doc.child(0).type.name, 'columnsBlock')
  })

  test('every menu item uses the heading menu label typography', () => {
    const items = Array.from(win.document.querySelectorAll('#insert-menu [data-insert]'))
    assert.equal(items.length, 7)
    for (const el of items) {
      assert.ok(el.querySelector('.heading-menu-label'), `${el.dataset.insert} has no label span`)
    }
  })

  test('the insert button is a labelled pill like the heading dropdown', () => {
    const btn = win.document.getElementById('insert-button')
    assert.ok(btn.querySelector('.insert-current'), 'has a text label')
    assert.equal(btn.querySelectorAll('svg').length, 1, 'one chevron, no icon glyph')
  })

  test('the menu closes after an insertion', () => {
    editor.commands.setContent('<p></p>', false)
    openMenu()
    assert.equal(win.document.getElementById('insert-menu').classList.contains('visible'), true)
    win.document.querySelector('#insert-menu [data-insert="buttons"]').click()
    assert.equal(win.document.getElementById('insert-menu').classList.contains('visible'), false)
  })
})

describe('contextual toolbar row', () => {
  const row = () => win.document.getElementById('toolbar-row2')
  const rowVisible = () => row().classList.contains('visible')
  const shown = () => Array.from(row().children)
    .filter(el => el.style.display !== 'none').map(el => el.id)

  test('every contextual group lives in row 2, not the main toolbar', () => {
    for (const id of ['blockquote-controls', 'table-controls', 'columns-controls',
                      'buttons-controls', 'accordion-controls', 'details-controls',
                      'tabs-controls', 'image-align-controls']) {
      const el = win.document.getElementById(id)
      assert.ok(el, `${id} exists`)
      assert.equal(el.parentElement.id, 'toolbar-row2', `${id} is in row 2`)
    }
  })

  test('the row is hidden in ordinary prose', () => {
    editor.commands.setContent('<p>plain</p>', false)
    editor.commands.setTextSelection(2)
    assert.equal(rowVisible(), false)
    assert.deepEqual(shown(), [])
  })

  test('the row appears for a container and names only that group', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertAccordion()
    assert.equal(rowVisible(), true)
    assert.deepEqual(shown(), ['accordion-controls'])
  })

  test('the row disappears again when the cursor leaves', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertAccordion()
    assert.equal(rowVisible(), true)
    editor.commands.setContent('<p>plain</p>', false)
    editor.commands.setTextSelection(2)
    assert.equal(rowVisible(), false)
  })

  test('nested containers show both groups at once', () => {
    editor.commands.setContent(
      '<div class="wp-block-columns"><div class="wp-block-column">' +
      '<div class="wp-block-buttons"><div class="wp-block-button">' +
      '<a class="wp-block-button__link wp-element-button">Go</a></div></div>' +
      '</div></div>', false)
    editor.commands.setTextSelection(4)
    assert.equal(rowVisible(), true)
    assert.deepEqual(shown().sort(), ['buttons-controls', 'columns-controls'])
  })

  test('the main toolbar keeps the groups that are not cursor-contextual', () => {
    const main = win.document.getElementById('toolbar')
    assert.ok(main.querySelector('#ai-toolbar-group'), 'AI group stays in row 1')
    assert.ok(main.querySelector('#insert-button'), 'insert menu stays in row 1')
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

describe('block attributes survive an edit', () => {
  before(() => { editor.commands.setContent('<p></p>', false) })

  test('accordion autoclose survives an edit', () => {
    const src = fs.readFileSync(
      path.resolve(__dirname, 'fixtures/accordion-block.html'), 'utf8')
    editor.commands.setContent(src, false)
    editor.commands.insertContent('x')
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<!-- wp:accordion \{"autoclose":true\} -->/)
  })

  test('a column width survives an edit', () => {
    editor.commands.setContent(
      '<!-- wp:columns --><div class="wp-block-columns">' +
      '<!-- wp:column {"width":"33.33%"} --><div class="wp-block-column"><p>A</p></div><!-- /wp:column -->' +
      '</div><!-- /wp:columns -->', false)
    editor.commands.insertContent('x')
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<!-- wp:column \{"width":"33\.33%"\} -->/)
  })

  test('an attribute Quill does not model is still preserved', () => {
    editor.commands.setContent(
      '<!-- wp:details {"showContent":true,"metadata":{"name":"FAQ"}} -->' +
      '<details class="wp-block-details"><summary>S</summary><p>B</p></details>' +
      '<!-- /wp:details -->', false)
    editor.commands.insertContent('x')
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /"metadata":\{"name":"FAQ"\}/)
  })
})

describe('the attribute carrier never reaches saved HTML', () => {
  const FIXTURES = ['accordion-block.html', 'tabs-block.html', 'gallery-block.html', 'post-17780.html']

  before(() => { editor.commands.setContent('<p></p>', false) })

  for (const name of FIXTURES) {
    test(`${name} round-trips byte-identically with no edit`, () => {
      const src = fs.readFileSync(path.resolve(__dirname, 'fixtures', name), 'utf8')
      win.setContent(src)
      assert.equal(win.getContent(), src)
    })

    test(`${name} leaks no carrier attribute after an edit`, () => {
      const src = fs.readFileSync(path.resolve(__dirname, 'fixtures', name), 'utf8')
      win.setContent(src)
      editor.commands.insertContent('x')
      const out = win.toWordPressHTML(editor.getHTML(), win.document)
      assert.equal(out.includes('data-quill-block-attrs'), false)
    })
  }
})

// WordPress writes accordion's autoclose only into the block comment (verified
// against gutenberg accordion/save.jsx, which emits no attribute for it), so
// the carrier is the only copy on load and data-autoclose is Quill-internal.
describe('accordion autoclose is a real attribute', () => {
  const SRC =
    '<!-- wp:accordion {"autoclose":true} -->' +
    '<div role="group" class="wp-block-accordion">' +
    '<!-- wp:accordion-item --><div class="wp-block-accordion-item">' +
    '<!-- wp:accordion-heading --><h3 class="wp-block-accordion-heading wp-block-heading">H</h3><!-- /wp:accordion-heading -->' +
    '<!-- wp:accordion-panel --><div role="region" class="wp-block-accordion-panel"><p>B</p></div><!-- /wp:accordion-panel -->' +
    '</div><!-- /wp:accordion-item --></div><!-- /wp:accordion -->'

  before(() => { editor.commands.setContent('<p></p>', false) })

  test('autoclose is parsed from the block comment, not data-autoclose', () => {
    editor.commands.setContent(SRC, false)
    assert.equal(editor.state.doc.child(0).attrs.autoclose, true)
  })

  test('autoclose renders into the editor DOM so attrsFrom can read it', () => {
    editor.commands.setContent(SRC, false)
    assert.match(editor.getHTML(), /data-autoclose/)
  })

  test('toggling autoclose off clears the node attribute', () => {
    editor.commands.setContent(SRC, false)
    editor.commands.command(({ commands }) => commands.toggleAccordionAutoclose())
    assert.equal(editor.state.doc.child(0).attrs.autoclose, false)
  })

  test('toggling autoclose on sets the node attribute', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertAccordion()
    assert.equal(editor.state.doc.child(0).attrs.autoclose, false)
    editor.commands.command(({ commands }) => commands.toggleAccordionAutoclose())
    assert.equal(editor.state.doc.child(0).attrs.autoclose, true)
  })

  test('data-autoclose never reaches saved HTML', () => {
    editor.commands.setContent(SRC, false)
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.equal(out.includes('data-autoclose'), false)
    assert.match(out, /<!-- wp:accordion \{"autoclose":true\} -->/)
  })
})

// core/details is the opposite case: gutenberg details/save.jsx renders
// open={showContent}, so `open` is real saved markup and must survive.
describe('details showContent is a real attribute', () => {
  const COMMENT_ONLY =
    '<!-- wp:details {"showContent":true} -->' +
    '<details class="wp-block-details"><summary>S</summary><p>B</p></details>' +
    '<!-- /wp:details -->'
  const AS_WORDPRESS_SAVES_IT =
    '<!-- wp:details {"showContent":true} -->' +
    '<details class="wp-block-details" open><summary>S</summary><p>B</p></details>' +
    '<!-- /wp:details -->'

  before(() => { editor.commands.setContent('<p></p>', false) })

  test('showContent is parsed from the block comment', () => {
    editor.commands.setContent(COMMENT_ONLY, false)
    assert.equal(editor.state.doc.child(0).attrs.showContent, true)
  })

  test('showContent is parsed from the open attribute WordPress saves', () => {
    editor.commands.setContent(AS_WORDPRESS_SAVES_IT, false)
    assert.equal(editor.state.doc.child(0).attrs.showContent, true)
  })

  test('showContent renders open into the editor DOM so attrsFrom can read it', () => {
    editor.commands.setContent(AS_WORDPRESS_SAVES_IT, false)
    assert.match(editor.getHTML(), /<details[^>]*\bopen\b/)
  })

  test('toggling showContent off clears the node attribute', () => {
    editor.commands.setContent(AS_WORDPRESS_SAVES_IT, false)
    editor.commands.command(({ commands }) => commands.toggleDetailsOpen())
    assert.equal(editor.state.doc.child(0).attrs.showContent, false)
  })

  test('toggling showContent on sets the node attribute', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertDetails()
    assert.equal(editor.state.doc.child(0).attrs.showContent, false)
    editor.commands.command(({ commands }) => commands.toggleDetailsOpen())
    assert.equal(editor.state.doc.child(0).attrs.showContent, true)
  })

  test('open stays in saved HTML when showContent is true', () => {
    editor.commands.setContent(AS_WORDPRESS_SAVES_IT, false)
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<details[^>]*\bopen\b/)
    assert.match(out, /<!-- wp:details \{"showContent":true\} -->/)
  })

  test('no open attribute is saved once showContent is turned off', () => {
    editor.commands.setContent(AS_WORDPRESS_SAVES_IT, false)
    editor.commands.command(({ commands }) => commands.toggleDetailsOpen())
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.doesNotMatch(out, /<details[^>]*\bopen\b/)
  })
})

describe('attribute toggles in the contextual toolbar', () => {
  const press = cmd => win.document.querySelector(`[data-cmd="${cmd}"]`)
    .dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true }))

  test('the autoclose button flips the accordion attribute', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertAccordion()
    press('toggleAccordionAutoclose')
    assert.equal(editor.state.doc.child(0).attrs.autoclose, true)
    press('toggleAccordionAutoclose')
    assert.equal(editor.state.doc.child(0).attrs.autoclose, false)
  })

  test('the open button flips the details attribute', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertDetails()
    press('toggleDetailsOpen')
    assert.equal(editor.state.doc.child(0).attrs.showContent, true)
    press('toggleDetailsOpen')
    assert.equal(editor.state.doc.child(0).attrs.showContent, false)
  })

  test('each control group is revealed only inside its own block', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertAccordion()
    assert.equal(win.document.getElementById('accordion-controls').style.display, 'inline-flex')
    assert.equal(win.document.getElementById('details-controls').style.display, 'none')
    editor.commands.setContent('<p></p>', false)
    win.insertDetails()
    assert.equal(win.document.getElementById('details-controls').style.display, 'inline-flex')
    assert.equal(win.document.getElementById('accordion-controls').style.display, 'none')
  })
})

// The carrier preserves every attribute the delimiter held, which is what keeps
// unmodeled attributes safe -- but it also means attrsFrom returning {} cannot
// be told apart from "this block has no such attribute". A descriptor names the
// keys it owns; those are dropped from the carrier before the DOM values merge.
describe('a descriptor owns its declared attributes', () => {
  const ACCORDION_WITH_AUTOCLOSE =
    '<!-- wp:accordion {"autoclose":true} -->' +
    '<div role="group" class="wp-block-accordion">' +
    '<!-- wp:accordion-item --><div class="wp-block-accordion-item">' +
    '<!-- wp:accordion-heading --><h3 class="wp-block-accordion-heading wp-block-heading">H</h3><!-- /wp:accordion-heading -->' +
    '<!-- wp:accordion-panel --><div role="region" class="wp-block-accordion-panel"><p>B</p></div><!-- /wp:accordion-panel -->' +
    '</div><!-- /wp:accordion-item --></div><!-- /wp:accordion -->'

  before(() => { editor.commands.setContent('<p></p>', false) })

  test('turning off an owned attribute removes it from the saved delimiter', () => {
    editor.commands.setContent(ACCORDION_WITH_AUTOCLOSE, false)
    editor.commands.command(({ commands }) => commands.toggleAccordionAutoclose())
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.doesNotMatch(out, /"autoclose"/)
  })

  test('an unowned attribute is still preserved when an owned one changes', () => {
    editor.commands.setContent(
      '<!-- wp:details {"showContent":true,"metadata":{"name":"FAQ"}} -->' +
      '<details class="wp-block-details"><summary>S</summary><p>B</p></details>' +
      '<!-- /wp:details -->', false)
    editor.commands.command(({ commands }) => commands.toggleDetailsOpen())
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.doesNotMatch(out, /"showContent"/)
    assert.match(out, /"metadata":\{"name":"FAQ"\}/)
  })

  test('turning an owned attribute back on restores it', () => {
    editor.commands.setContent(ACCORDION_WITH_AUTOCLOSE, false)
    editor.commands.command(({ commands }) => commands.toggleAccordionAutoclose())
    editor.commands.command(({ commands }) => commands.toggleAccordionAutoclose())
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<!-- wp:accordion \{"autoclose":true\} -->/)
  })

  // Quill has no column-width UI, so the carried value is the only copy.
  test('a column width is not owned and survives an edit', () => {
    editor.commands.setContent(
      '<!-- wp:columns --><div class="wp-block-columns">' +
      '<!-- wp:column {"width":"33.33%"} --><div class="wp-block-column"><p>A</p></div><!-- /wp:column -->' +
      '</div><!-- /wp:columns -->', false)
    editor.commands.insertContent('x')
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<!-- wp:column \{"width":"33\.33%"\} -->/)
  })
})

// Accordion, tabs and details carry editor-only chrome: a forced-open
// <details>, a collapsed-for-preview class, the active tab. All of it is
// applied as ProseMirror decorations, which live outside the document —
// these tests are the guard that none of it can reach a save.
describe('editor chrome stays out of saved markup', () => {
  const ACCORDION = '<div role="group" class="wp-block-accordion">' +
    '<div class="wp-block-accordion-item">' +
    '<h3 class="wp-block-accordion-heading wp-block-heading"><button type="button" class="wp-block-accordion-heading__toggle"><span class="wp-block-accordion-heading__toggle-title">One</span></button></h3>' +
    '<div role="region" class="wp-block-accordion-panel"><p>First</p></div></div>' +
    '<div class="wp-block-accordion-item">' +
    '<h3 class="wp-block-accordion-heading wp-block-heading"><button type="button" class="wp-block-accordion-heading__toggle"><span class="wp-block-accordion-heading__toggle-title">Two</span></button></h3>' +
    '<div role="region" class="wp-block-accordion-panel"><p>Second</p></div></div>' +
    '</div>'

  const TABS = '<div class="wp-block-tabs">' +
    '<div role="tablist" class="wp-block-tab-list">' +
    '<button type="button" role="tab">Alpha</button><button type="button" role="tab">Beta</button></div>' +
    '<div class="wp-block-tab-panels">' +
    '<section role="tabpanel" tabindex="0" class="wp-block-tab-panel"><p>A body</p></section>' +
    '<section role="tabpanel" tabindex="0" class="wp-block-tab-panel"><p>B body</p></section>' +
    '</div></div>'

  const save = () => win.toWordPressHTML(editor.getHTML(), win.document)

  const posInside = (typeName, index = 0) => {
    const hits = []
    editor.state.doc.descendants((node, pos) => { if (node.type.name === typeName) hits.push(pos) })
    return hits[index] + 1
  }

  before(() => { editor.commands.setContent('<p></p>', false) })

  test('a details block is open in the DOM even when showContent is false', () => {
    editor.commands.setContent('<details class="wp-block-details"><summary>S</summary><p>Body</p></details>', false)
    const dom = win.document.querySelector('#editor details.wp-block-details')
    assert.ok(dom, 'details rendered')
    assert.ok(dom.hasAttribute('open'), 'forced open so the body stays editable')
    assert.doesNotMatch(save(), /<details[^>]*\sopen/)
  })

  test('showContent true still saves the open attribute', () => {
    editor.commands.setContent('<details class="wp-block-details" open><summary>S</summary><p>Body</p></details>', false)
    assert.match(save(), /<details[^>]*\sopen/)
  })

  test('collapsing an accordion item changes the DOM and not the document', () => {
    editor.commands.setContent(ACCORDION, false)
    const before = save()
    editor.commands.setTextSelection(posInside('accordionHeading', 0))
    editor.commands.toggleContainerCollapse()
    assert.ok(win.document.querySelector('#editor .wp-block-accordion-item.is-collapsed'), 'item collapsed in the DOM')
    assert.equal(save(), before)
    assert.doesNotMatch(save(), /is-collapsed/)
  })

  test('collapsing is a toggle', () => {
    editor.commands.setContent(ACCORDION, false)
    editor.commands.setTextSelection(posInside('accordionHeading', 0))
    editor.commands.toggleContainerCollapse()
    editor.commands.toggleContainerCollapse()
    assert.equal(win.document.querySelectorAll('#editor .wp-block-accordion-item.is-collapsed').length, 0)
  })

  test('collapsing one item leaves its sibling expanded', () => {
    editor.commands.setContent(ACCORDION, false)
    editor.commands.setTextSelection(posInside('accordionHeading', 1))
    editor.commands.toggleContainerCollapse()
    const items = win.document.querySelectorAll('#editor .wp-block-accordion-item')
    assert.equal(items[0].classList.contains('is-collapsed'), false)
    assert.equal(items[1].classList.contains('is-collapsed'), true)
  })

  test('a details block collapses for preview the same way', () => {
    editor.commands.setContent('<details class="wp-block-details"><summary>S</summary><p>Body</p></details>', false)
    editor.commands.setTextSelection(posInside('detailsSummary', 0))
    editor.commands.toggleContainerCollapse()
    const dom = win.document.querySelector('#editor details.wp-block-details')
    assert.ok(dom.classList.contains('is-collapsed'))
    assert.ok(dom.hasAttribute('open'), 'still open in the DOM; CSS does the hiding')
    assert.doesNotMatch(save(), /is-collapsed/)
  })

  test('the first tab is active when the cursor is elsewhere', () => {
    editor.commands.setContent('<p>outside</p>' + TABS, false)
    editor.commands.setTextSelection(1)
    const btns = win.document.querySelectorAll('#editor .wp-block-tab-list button[role="tab"]')
    assert.equal(btns[0].classList.contains('is-active-tab'), true)
    assert.equal(btns[1].classList.contains('is-active-tab'), false)
  })

  test('putting the cursor in a tab panel activates that tab', () => {
    editor.commands.setContent(TABS, false)
    editor.commands.setTextSelection(posInside('tabPanel', 1) + 1)
    const btns = win.document.querySelectorAll('#editor .wp-block-tab-list button[role="tab"]')
    const panels = win.document.querySelectorAll('#editor .wp-block-tab-panel')
    assert.equal(btns[1].classList.contains('is-active-tab'), true)
    assert.equal(panels[1].classList.contains('is-active-tab'), true)
    assert.equal(panels[0].classList.contains('is-active-tab'), false)
  })

  test('putting the cursor in a tab label activates that tab', () => {
    editor.commands.setContent(TABS, false)
    editor.commands.setTextSelection(posInside('tabButton', 1))
    const panels = win.document.querySelectorAll('#editor .wp-block-tab-panel')
    assert.equal(panels[1].classList.contains('is-active-tab'), true)
  })

  test('the active tab class never reaches saved markup', () => {
    editor.commands.setContent(TABS, false)
    editor.commands.setTextSelection(posInside('tabPanel', 1) + 1)
    assert.doesNotMatch(save(), /is-active-tab/)
  })

  test('an accordion survives collapse, edit and save without losing an item', () => {
    editor.commands.setContent(ACCORDION, false)
    editor.commands.setTextSelection(posInside('accordionHeading', 0))
    editor.commands.toggleContainerCollapse()
    editor.commands.setTextSelection(posInside('accordionPanel', 1) + 1)
    editor.commands.insertContent('edited')
    const out = save()
    assert.equal((out.match(/wp-block-accordion-item/g) || []).length, 2)
    assert.match(out, /edited/)
    assert.doesNotMatch(out, /is-collapsed|is-active-tab/)
  })
})
