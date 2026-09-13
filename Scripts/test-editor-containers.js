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

  test('typing after insert lands in the first tab panel', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertTabs(2)
    editor.commands.insertContent('First')
    const panels = editor.state.doc.child(0).child(1)
    assert.match(panels.child(0).textContent, /First/)
    assert.equal(panels.child(1).textContent, '')
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
                      'tabs-controls', 'image-align-controls', 'block-controls']) {
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
    assert.deepEqual(shown(), ['accordion-controls', 'block-controls', 'settings-accordionItem-controls'])
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
    assert.deepEqual(shown().sort(), ['block-controls', 'buttons-controls', 'columns-controls'])
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

// The heading markup Quill emitted was copied from post 17780, which an older
// WordPress wrote. Current core/accordion-heading save() emits has-icon
// classes and a "+" icon span and never emits wp-block-heading, so the old
// shape matches no registered save or deprecation and Gutenberg rejects it.
// Expected markup verified against wp-includes/js/dist/block-library.js on
// the live site (accordion-heading/save.mjs, showIcon default true,
// iconPosition default right).
describe('accordion headings match current core save markup', () => {
  const save = () => win.toWordPressHTML(editor.getHTML(), win.document)

  const headingOf = out =>
    new JSDOM('<body>' + out + '</body>').window.document
      .querySelector('.wp-block-accordion-heading')

  const wrap = (commentAttrs, headingHTML) =>
    '<!-- wp:accordion -->' +
    '<div role="group" class="wp-block-accordion">' +
    '<!-- wp:accordion-item --><div class="wp-block-accordion-item">' +
    `<!-- wp:accordion-heading${commentAttrs ? ' ' + commentAttrs : ''} -->` +
    headingHTML +
    '<!-- /wp:accordion-heading -->' +
    '<!-- wp:accordion-panel --><div role="region" class="wp-block-accordion-panel"><p>B</p></div><!-- /wp:accordion-panel -->' +
    '</div><!-- /wp:accordion-item --></div><!-- /wp:accordion -->'

  const OLD_FORMAT_HEADING =
    '<h3 class="wp-block-accordion-heading wp-block-heading">' +
    '<button type="button" class="wp-block-accordion-heading__toggle">' +
    '<span class="wp-block-accordion-heading__toggle-title">Title</span></button></h3>'

  before(() => { editor.commands.setContent('<p></p>', false) })

  test('an accordion Quill inserts saves the heading exactly as core writes it', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertAccordion()
    const h = headingOf(save())
    assert.deepEqual([...h.classList].sort(), ['has-icon', 'has-icon-right', 'wp-block-accordion-heading'])
    const btn = h.querySelector('button')
    assert.equal(btn.getAttribute('type'), 'button')
    assert.equal(btn.getAttribute('class'), 'wp-block-accordion-heading__toggle')
    assert.deepEqual([...btn.children].map(c => c.getAttribute('class')), [
      'wp-block-accordion-heading__toggle-title',
      'wp-block-accordion-heading__toggle-icon',
    ])
    const icon = btn.lastElementChild
    assert.equal(icon.getAttribute('aria-hidden'), 'true')
    assert.equal(icon.textContent, '+')
  })

  test('wp-block-heading is never emitted', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertAccordion()
    assert.doesNotMatch(save(), /wp-block-heading/)
  })

  test('an old-format heading is upgraded on an edited save', () => {
    editor.commands.setContent(wrap(null, OLD_FORMAT_HEADING), false)
    editor.commands.insertContent('x')
    const h = headingOf(save())
    assert.equal(h.classList.contains('has-icon'), true)
    assert.equal(h.classList.contains('has-icon-right'), true)
    assert.equal(h.classList.contains('wp-block-heading'), false)
    assert.equal(h.querySelectorAll('.wp-block-accordion-heading__toggle-icon').length, 1)
    assert.equal(h.querySelector('.wp-block-accordion-heading__toggle-title').textContent, 'Title')
  })

  test('showIcon false in the block comment suppresses the icon and its classes', () => {
    editor.commands.setContent(wrap('{"showIcon":false}', OLD_FORMAT_HEADING), false)
    const h = headingOf(save())
    assert.equal(h.classList.contains('has-icon'), false)
    assert.equal(h.classList.contains('has-icon-right'), false)
    assert.equal(h.querySelectorAll('.wp-block-accordion-heading__toggle-icon').length, 0)
    assert.equal(h.querySelector('.wp-block-accordion-heading__toggle-title').textContent, 'Title')
  })

  test('iconPosition left puts the icon before the title, as core does', () => {
    editor.commands.setContent(wrap('{"iconPosition":"left"}', OLD_FORMAT_HEADING), false)
    const h = headingOf(save())
    assert.equal(h.classList.contains('has-icon-left'), true)
    assert.equal(h.classList.contains('has-icon-right'), false)
    assert.deepEqual([...h.querySelector('button').children].map(c => c.getAttribute('class')), [
      'wp-block-accordion-heading__toggle-icon',
      'wp-block-accordion-heading__toggle-title',
    ])
  })

  test('saving a showIcon-false accordion twice is idempotent', () => {
    editor.commands.setContent(wrap('{"showIcon":false}', OLD_FORMAT_HEADING), false)
    const once = save()
    editor.commands.setContent(once, false)
    assert.equal(save(), once)
  })

  // A copy/paste inside the editor re-parses the node's rendered markup with
  // no delimiter comment, so the has-icon class is the only surviving copy.
  test('showIcon false is recovered from the markup when the comment is gone', () => {
    editor.commands.setContent(wrap('{"showIcon":false}', OLD_FORMAT_HEADING), false)
    editor.commands.setContent(save().replace(/<!--[\s\S]*?-->/g, ''), false)
    const h = headingOf(save())
    assert.equal(h.classList.contains('has-icon'), false)
    assert.equal(h.querySelectorAll('.wp-block-accordion-heading__toggle-icon').length, 0)
  })

  test('the icon span is not typed into and the title still takes the text', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertAccordion()
    const hits = []
    editor.state.doc.descendants((node, pos) => { if (node.type.name === 'accordionHeading') hits.push(pos) })
    editor.commands.setTextSelection(hits[0] + 1)
    editor.commands.insertContent('Hello')
    const h = headingOf(save())
    assert.equal(h.querySelector('.wp-block-accordion-heading__toggle-title').textContent, 'Hello')
    assert.equal(h.querySelector('.wp-block-accordion-heading__toggle-icon').textContent, '+')
  })

  test('the editor hides the icon span so the ::after affordance still reads', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertAccordion()
    const icon = win.document.querySelector('#editor .wp-block-accordion-heading__toggle-icon')
    assert.ok(icon)
    const css = fs.readFileSync(htmlPath, 'utf8')
    assert.match(css, /\.wp-block-accordion-heading__toggle-icon\s*\{[^}]*display:\s*none/)
  })
})

// The toggle used to be a narrow hit zone (right 32px of an accordion header,
// left 22px of a details summary) with no cursor affordance, so nothing about
// the row said it could be clicked. The whole row is the target now, with the
// row's own text as the one exception so a title can still be typed into.
// jsdom gives every element a zeroed getBoundingClientRect and empty Range
// client rects, so the geometry half of this is verified in a real browser,
// not here — these cover the parts that do not need measurement.
describe('container rows read as clickable', () => {
  const source = fs.readFileSync(htmlPath, 'utf8')

  const ACCORDION_TWO_ITEMS = '<div role="group" class="wp-block-accordion">' +
    '<div class="wp-block-accordion-item">' +
    '<h3 class="wp-block-accordion-heading has-icon has-icon-right"><button type="button" class="wp-block-accordion-heading__toggle"><span class="wp-block-accordion-heading__toggle-title">One</span><span class="wp-block-accordion-heading__toggle-icon" aria-hidden="true">+</span></button></h3>' +
    '<div role="region" class="wp-block-accordion-panel"><p>First</p></div></div>' +
    '<div class="wp-block-accordion-item">' +
    '<h3 class="wp-block-accordion-heading has-icon has-icon-right"><button type="button" class="wp-block-accordion-heading__toggle"><span class="wp-block-accordion-heading__toggle-title">Two</span><span class="wp-block-accordion-heading__toggle-icon" aria-hidden="true">+</span></button></h3>' +
    '<div role="region" class="wp-block-accordion-panel"><p>Second</p></div></div>' +
    '</div>'

  const ACCORDION_EMPTY_TITLE =
    '<!-- wp:accordion --><div role="group" class="wp-block-accordion">' +
    '<!-- wp:accordion-item --><div class="wp-block-accordion-item">' +
    '<!-- wp:accordion-heading --><h3 class="wp-block-accordion-heading has-icon has-icon-right">' +
    '<button type="button" class="wp-block-accordion-heading__toggle">' +
    '<span class="wp-block-accordion-heading__toggle-title"></span>' +
    '<span class="wp-block-accordion-heading__toggle-icon" aria-hidden="true">+</span>' +
    '</button></h3><!-- /wp:accordion-heading -->' +
    '<!-- wp:accordion-panel --><div role="region" class="wp-block-accordion-panel"><p>B</p></div><!-- /wp:accordion-panel -->' +
    '</div><!-- /wp:accordion-item --></div><!-- /wp:accordion -->'

  const mousedownOn = el =>
    el.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true, clientX: 0, clientY: 0 }))

  before(() => { editor.commands.setContent('<p></p>', false) })

  test('the accordion row cursor sits on the toggle button, which covers the row', () => {
    assert.match(source, /\.wp-block-accordion-heading__toggle\s*\{[^}]*cursor:\s*pointer/)
    assert.doesNotMatch(source, /\.wp-block-accordion-heading__toggle\s*\{[^}]*cursor:\s*text/)
  })

  test('the accordion title keeps a text cursor, because clicking it types', () => {
    assert.match(source, /\.wp-block-accordion-heading__toggle-title\s*\{[^}]*cursor:\s*text/)
  })

  test('only the details arrow is a pointer target, not the summary text', () => {
    assert.match(source, /\.wp-block-details\s*>\s*summary::before\s*\{[^}]*cursor:\s*pointer/)
    assert.match(source, /\.wp-block-details\s*>\s*summary\s*\{[^}]*cursor:\s*text/)
  })

  // Verified in a browser: a clip-path box is hit-tested only where it paints,
  // so the pointer appeared over the triangle alone; a masked box paints the
  // same shape and stays hittable across all of it.
  test('the details arrow box is big enough to hit', () => {
    const rule = source.match(/\.wp-block-details\s*>\s*summary::before\s*\{([^}]*)\}/)[1]
    assert.ok(parseInt(rule.match(/width:\s*(\d+)px/)[1], 10) >= 22, 'arrow box width')
    assert.ok(parseInt(rule.match(/height:\s*(\d+)px/)[1], 10) >= 22, 'arrow box height')
    assert.match(rule, /\bmask:/)
    assert.doesNotMatch(rule, /clip-path/)
  })

  test('an accordion header has no hover tint', () => {
    assert.doesNotMatch(source, /\.wp-block-accordion-heading:hover\s*\{[^}]*background/)
  })

  test('tab labels are pointer targets', () => {
    assert.match(source, /button\[role="tab"\]\s*\{[^}]*cursor:\s*pointer/)
    assert.doesNotMatch(source, /button\[role="tab"\]\s*\{[^}]*cursor:\s*text/)
  })

  test('pressing an accordion header row collapses the item', () => {
    editor.commands.setContent(ACCORDION_TWO_ITEMS, false)
    mousedownOn(win.document.querySelector('#editor .wp-block-accordion-heading'))
    assert.ok(win.document.querySelector('#editor .wp-block-accordion-item.is-collapsed'))
  })

  test('pressing the details arrow collapses it', () => {
    editor.commands.setContent('<details class="wp-block-details"><summary>S</summary><p>Body</p></details>', false)
    mousedownOn(win.document.querySelector('#editor .wp-block-details > summary'))
    assert.ok(win.document.querySelector('#editor details.wp-block-details.is-collapsed'))
  })

  // An empty title has no text to aim at, so the row must yield the click or a
  // new accordion could never be given a name.
  test('pressing a header row with an empty title places the caret instead of collapsing', () => {
    editor.commands.setContent(ACCORDION_EMPTY_TITLE, false)
    mousedownOn(win.document.querySelector('#editor .wp-block-accordion-heading'))
    assert.equal(win.document.querySelectorAll('#editor .wp-block-accordion-item.is-collapsed').length, 0)
  })

  test('collapse state still never reaches saved markup', () => {
    editor.commands.setContent(ACCORDION_TWO_ITEMS, false)
    mousedownOn(win.document.querySelector('#editor .wp-block-accordion-heading'))
    assert.ok(win.document.querySelector('#editor .wp-block-accordion-item.is-collapsed'), 'press collapsed it')
    assert.doesNotMatch(win.toWordPressHTML(editor.getHTML(), win.document), /is-collapsed/)
  })
})

describe('empty titles show a hint', () => {
  const source = fs.readFileSync(htmlPath, 'utf8')

  const EMPTY_ACCORDION = '<div role="group" class="wp-block-accordion">' +
    '<div class="wp-block-accordion-item">' +
    '<h3 class="wp-block-accordion-heading has-icon has-icon-right"><button type="button" class="wp-block-accordion-heading__toggle"><span class="wp-block-accordion-heading__toggle-title"></span></button></h3>' +
    '<div role="region" class="wp-block-accordion-panel"><p>Body</p></div></div></div>'

  const EMPTY_DETAILS = '<details class="wp-block-details"><summary></summary><p>Body</p></details>'

  const hinted = () => Array.from(win.document.querySelectorAll('#editor .is-untitled'))

  const tick = () => new Promise(r => setTimeout(r, 80))

  before(() => { editor.commands.setContent('<p></p>', false) })

  test('a freshly inserted accordion marks its own title as untitled', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertAccordion()
    assert.deepEqual(hinted().map(el => el.tagName), ['H3'])
  })

  test('a freshly inserted details marks its own title as untitled', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertDetails()
    assert.deepEqual(hinted().map(el => el.tagName), ['SUMMARY'])
  })

  test('a loaded title with text is not marked', () => {
    editor.commands.setContent(
      '<details class="wp-block-details"><summary>Named</summary><p>Body</p></details>', false)
    assert.equal(hinted().length, 0)
  })

  test('typing a title clears the mark and an empty one brings it back', () => {
    editor.commands.setContent(EMPTY_ACCORDION, false)
    const pos = []
    editor.state.doc.descendants((node, at) => { if (node.type.name === 'accordionHeading') pos.push(at) })
    editor.commands.insertContentAt(pos[0] + 1, 'Features')
    assert.equal(hinted().length, 0)
    editor.commands.setContent(EMPTY_ACCORDION, false)
    assert.equal(hinted().length, 1)
  })

  test('every empty title in a multi-item accordion is marked, not just the focused one', () => {
    const item = EMPTY_ACCORDION.match(/<div class="wp-block-accordion-item">[\s\S]*<\/div>/)[0]
    editor.commands.setContent(EMPTY_ACCORDION.replace(item, item + item), false)
    assert.equal(hinted().length, 2)
  })

  test('the mark is decoration only and never reaches saved markup', () => {
    editor.commands.setContent(EMPTY_ACCORDION, false)
    assert.equal(hinted().length, 1, 'mark is present')
    assert.doesNotMatch(win.toWordPressHTML(editor.getHTML(), win.document), /is-untitled/)
  })

  // A widget decoration here put a contenteditable=false node beside the caret,
  // and WebKit then dropped every keystroke aimed at the title — the hint has to
  // stay generated content.
  test('the hint is drawn in CSS, never inserted into the document', () => {
    assert.match(source, /\.wp-block-accordion-heading\.is-untitled[^{]*::before/)
    assert.match(source, /summary\.is-untitled::after/)
    assert.doesNotMatch(source, /Decoration\.widget\([^)]*title/i)
  })

  test('the hint names each block', () => {
    assert.match(source, /content:\s*'Accordion title'/)
    assert.match(source, /content:\s*'Details title'/)
  })

  test('the hint cannot swallow the click that would place the caret in it', () => {
    const rule = source.match(
      /\.wp-block-details > summary\.is-untitled::after,?[\s\S]*?\{([^}]*)\}/)[1]
    assert.match(rule, /pointer-events:\s*none/)
  })

  test('the hint is out of flow, so an untitled row is no taller', () => {
    const rule = source.match(
      /\.wp-block-details > summary\.is-untitled::after,?[\s\S]*?\{([^}]*)\}/)[1]
    assert.match(rule, /position:\s*absolute/)
  })

  test('the hint is legible in dark mode too', () => {
    assert.match(source, /body\.dark [\s\S]{0,400}?summary\.is-untitled::after\s*\{[^}]*color:/)
  })

  // The summary's own ::after draws the hint, so the status badge had to move
  // onto the box; left where it was, the two collided.
  test('the details status badge is drawn on the box, not the summary', () => {
    assert.match(source, /\.wp-block-details:not\(\.shows-content\)::after\s*\{[^}]*'closed on the site'/)
    assert.doesNotMatch(source, /summary::after\s*\{[^}]*'closed on the site'/)
  })

  test('pressing an untitled accordion row seats the caret in the title, not the panel', async () => {
    editor.commands.setContent(EMPTY_ACCORDION, false)
    win.document.querySelector('#editor .wp-block-accordion-heading__toggle')
      .dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true, clientX: 60, clientY: 0 }))
    await tick()
    assert.equal(editor.state.selection.$head.parent.type.name, 'accordionHeading')
    editor.commands.insertContent('Typed')
    assert.match(win.toWordPressHTML(editor.getHTML(), win.document), /toggle-title">Typed</)
  })

  test('pressing an untitled details summary seats the caret in the summary', async () => {
    editor.commands.setContent(EMPTY_DETAILS, false)
    win.document.querySelector('#editor .wp-block-details > summary')
      .dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true, clientX: 200, clientY: 0 }))
    await tick()
    assert.equal(editor.state.selection.$head.parent.type.name, 'detailsSummary')
  })

  // The arrow keeps its job, or an untitled details could never be collapsed.
  test('the details arrow still collapses an untitled details', async () => {
    editor.commands.setContent(EMPTY_DETAILS, false)
    win.document.querySelector('#editor .wp-block-details > summary')
      .dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true, clientX: 0, clientY: 0 }))
    await tick()
    assert.ok(win.document.querySelector('#editor details.wp-block-details.is-collapsed'))
  })
})

// One rule for every container: the minus buttons remove one part, the ✕
// removes the whole block. The ✕ is a single shared control, so a block type
// can only be forgotten by leaving it out of DELETABLE_BLOCKS.
describe('delete block control', () => {
  const press = cmd => win.document.querySelector(`[data-cmd="${cmd}"]`)
    .dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true }))

  const deleteKey = () => win.document.querySelector('#block-controls [data-cmd="deleteBlock"]')

  // jsdom has no Range.getClientRects, so any dispatch made while the view
  // really holds focus dies inside ProseMirror's scroll-into-view.
  before(() => { editor.view.dom.blur() })

  const blocks = {
    columns:      () => win.insertColumns(2),
    tabs:         () => win.insertTabs(2),
    accordion:    () => win.insertAccordion(),
    buttons:      () => win.insertButtons(),
    details:      () => win.insertDetails(),
    table:        () => editor.chain().focus().insertTable({ rows: 2, cols: 2 }).run(),
    pullquote:    () => editor.chain().setPullquote().run(),
    preformatted: () => editor.chain().setPreformatted().run(),
    blockquote:   () => editor.chain().toggleBlockquote().run(),
    codeBlock:    () => editor.chain().toggleCodeBlock().run(),
  }

  const names = {
    columns: 'columnsBlock', tabs: 'tabsBlock', accordion: 'accordionBlock',
    buttons: 'buttonsBlock', details: 'detailsBlock', table: 'table',
    pullquote: 'pullquote', preformatted: 'preformatted',
    blockquote: 'blockquote', codeBlock: 'codeBlock',
  }

  for (const [label, insert] of Object.entries(blocks)) {
    test(`the ✕ deletes a ${label} block`, () => {
      editor.commands.setContent('<p>x</p>', false)
      insert()
      let found = false
      editor.state.doc.descendants(n => { if (n.type.name === names[label]) found = true })
      assert.ok(found, `${label} was never inserted`)
      press('deleteBlock')
      let still = false
      editor.state.doc.descendants(n => { if (n.type.name === names[label]) still = true })
      assert.equal(still, false)
    })

    test(`the ✕ is offered inside a ${label} block`, () => {
      editor.commands.setContent('<p></p>', false)
      insert()
      assert.notEqual(win.document.getElementById('block-controls').style.display, 'none')
    })
  }

  test('the ✕ is hidden in ordinary body text', () => {
    editor.commands.setContent('<p>plain</p>', false)
    editor.commands.setTextSelection(2)
    assert.equal(win.document.getElementById('block-controls').style.display, 'none')
  })

  test('the table group no longer carries its own delete button', () => {
    assert.equal(win.document.querySelector('#table-controls [data-cmd="deleteTable"]'), null)
  })

  test('the ✕ names the block it will remove', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertTabs(2)
    assert.match(deleteKey().title, /tabs/i)
    editor.commands.setContent('<p></p>', false)
    editor.chain().focus().insertTable({ rows: 2, cols: 2 }).run()
    assert.match(deleteKey().title, /table/i)
  })

  test('a nested block is removed before the one holding it', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertColumns(2)
    editor.chain().focus().insertTable({ rows: 2, cols: 2 }).run()
    press('deleteBlock')
    let hasTable = false, hasColumns = false
    editor.state.doc.descendants(n => {
      if (n.type.name === 'table') hasTable = true
      if (n.type.name === 'columnsBlock') hasColumns = true
    })
    assert.equal(hasTable, false)
    assert.equal(hasColumns, true)
    press('deleteBlock')
    let stillColumns = false
    editor.state.doc.descendants(n => { if (n.type.name === 'columnsBlock') stillColumns = true })
    assert.equal(stillColumns, false)
  })

  test('the cursor lands in the block after the deleted one', () => {
    editor.commands.setContent('<p>before</p><p>after</p>', false)
    editor.commands.setTextSelection(8)
    win.insertTabs(2)
    press('deleteBlock')
    assert.equal(editor.state.selection.$head.parent.textContent, 'after')
  })

  test('the cursor falls back to the block before when nothing follows', () => {
    editor.commands.setContent('<p>before</p>', false)
    editor.commands.setTextSelection(editor.state.doc.content.size - 1)
    win.insertTabs(2)
    press('deleteBlock')
    assert.equal(editor.state.selection.$head.parent.textContent, 'before')
  })

  test('deleting the only block leaves an empty paragraph to type in', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertTabs(2)
    press('deleteBlock')
    assert.equal(editor.state.doc.childCount, 1)
    assert.equal(editor.state.doc.child(0).type.name, 'paragraph')
    editor.commands.insertContent('typed')
    assert.equal(editor.state.doc.child(0).textContent, 'typed')
  })

  test('⌘⇧⌫ removes the block the cursor is in', () => {
    editor.commands.setContent('<p>before</p>', false)
    editor.commands.setTextSelection(editor.state.doc.content.size - 1)
    win.insertAccordion()
    const ev = new win.KeyboardEvent('keydown', {
      key: 'Backspace', code: 'Backspace', keyCode: 8, which: 8,
      bubbles: true, cancelable: true, metaKey: true, shiftKey: true,
    })
    editor.view.dom.dispatchEvent(ev)
    let still = false
    editor.state.doc.descendants(n => { if (n.type.name === 'accordionBlock') still = true })
    assert.equal(still, false)
  })

  test('⌘⇧⌫ leaves ordinary body text alone', () => {
    editor.commands.setContent('<p>plain text</p>', false)
    editor.commands.setTextSelection(3)
    const ev = new win.KeyboardEvent('keydown', {
      key: 'Backspace', code: 'Backspace', keyCode: 8, which: 8,
      bubbles: true, cancelable: true, metaKey: true, shiftKey: true,
    })
    editor.view.dom.dispatchEvent(ev)
    assert.equal(editor.state.doc.child(0).textContent, 'plain text')
  })

  test('the minus buttons still refuse to remove the last part', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertAccordion()
    press('deleteAccordionItem')
    assert.equal(editor.state.doc.child(0).childCount, 1)
  })
})

// Every container used to answer a double-Enter differently — details and the
// last tab panel escaped, an earlier tab panel piled up empty paragraphs, and a
// column split itself in two. Esc is the one gesture that always leaves.
describe('leaving a container block', () => {
  const key = (k, mods = {}) => {
    const code = { Enter: 13, Escape: 27, Backspace: 8 }
    editor.view.dom.dispatchEvent(new win.KeyboardEvent('keydown', {
      key: k, code: k, keyCode: code[k] || 0, which: code[k] || 0,
      bubbles: true, cancelable: true,
      shiftKey: !!mods.shift, metaKey: !!mods.meta,
    }))
  }

  const enter = (n = 1) => { for (let i = 0; i < n; i++) key('Enter') }

  // Inside the first text position of the nth node of this type.
  const into = (typeName, index = 0) => {
    let seen = -1, target = null
    editor.state.doc.descendants((n, p) => {
      if (n.type.name === typeName) { seen++; if (seen === index && target === null) target = p + 2 }
    })
    editor.commands.setTextSelection(target)
  }

  const countOf = typeName => {
    let n = 0
    editor.state.doc.descendants(node => { if (node.type.name === typeName) n++ })
    return n
  }

  const CONTAINERS = new Set(['table', 'tabsBlock', 'accordionBlock', 'detailsBlock',
                              'columnsBlock', 'buttonsBlock', 'pullquote', 'preformatted',
                              'blockquote', 'codeBlock'])
  const atTopLevel = () => {
    const $h = editor.state.selection.$head
    for (let d = $h.depth; d > 0; d--) if (CONTAINERS.has($h.node(d).type.name)) return false
    return true
  }
  const caretText = () => editor.state.selection.$head.parent.textContent

  before(() => { editor.view.dom.blur() })

  test('Esc leaves a tab panel for the body below', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertTabs(2)
    key('Escape')
    assert.equal(atTopLevel(), true)
    assert.equal(countOf('tabsBlock'), 1)
  })

  test('Esc leaves the first tab panel, not just the last', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertTabs(3)
    into('tabPanel', 0)
    key('Escape')
    assert.equal(atTopLevel(), true)
    assert.equal(countOf('tabPanel'), 3)
  })

  test('Esc leaves a column without breaking the columns block apart', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertColumns(2)
    into('columnBlock', 0)
    key('Escape')
    assert.equal(atTopLevel(), true)
    assert.equal(countOf('columnsBlock'), 1)
    assert.equal(countOf('columnBlock'), 2)
  })

  test('Esc leaves a table', () => {
    editor.commands.setContent('<p></p>', false)
    editor.chain().insertTable({ rows: 2, cols: 2 }).run()
    into('tableCell', 0)
    key('Escape')
    assert.equal(atTopLevel(), true)
    assert.equal(countOf('table'), 1)
  })

  test('Esc leaves a preformatted block', () => {
    editor.commands.setContent('<p></p>', false)
    editor.chain().setPreformatted().run()
    editor.commands.insertContent('code')
    key('Escape')
    assert.equal(atTopLevel(), true)
    assert.equal(countOf('preformatted'), 1)
    assert.equal(editor.state.doc.child(0).textContent, 'code')
  })

  test('Esc leaves a details body', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertDetails()
    key('Escape')
    assert.equal(atTopLevel(), true)
    assert.equal(countOf('detailsBlock'), 1)
  })

  test('Esc makes the paragraph to land in when the block is last', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertTabs(2)
    assert.equal(editor.state.doc.childCount, 1)
    key('Escape')
    assert.equal(editor.state.doc.childCount, 2)
    assert.equal(editor.state.doc.child(1).type.name, 'paragraph')
    editor.commands.insertContent('after')
    assert.equal(editor.state.doc.child(1).textContent, 'after')
  })

  test('Esc reuses the paragraph already below instead of stacking a blank one', () => {
    editor.commands.setContent('<p>x</p><p>below</p>', false)
    editor.commands.setTextSelection(2)
    win.insertTabs(2)
    const before = editor.state.doc.childCount
    into('tabPanel', 0)
    key('Escape')
    assert.equal(editor.state.doc.childCount, before)
    assert.equal(caretText(), 'below')
  })

  test('Esc steps out one container at a time when nested', () => {
    editor.commands.setContent(
      '<div class="wp-block-columns"><div class="wp-block-column">' +
      '<table><tbody><tr><td><p>A</p></td></tr></tbody></table></div>' +
      '<div class="wp-block-column"><p>B</p></div></div>', false)
    into('tableCell', 0)
    assert.equal(editor.state.selection.$head.node(-4).type.name, 'columnBlock')
    key('Escape')
    assert.equal(atTopLevel(), false)
    assert.equal(editor.state.selection.$head.node(-1).type.name, 'columnBlock')
    key('Escape')
    assert.equal(atTopLevel(), true)
    assert.equal(countOf('columnsBlock'), 1)
  })

  test('Esc leaves a blockquote', () => {
    editor.commands.setContent('<blockquote><p>quoted</p></blockquote>', false)
    editor.commands.setTextSelection(4)
    key('Escape')
    assert.equal(atTopLevel(), true)
    assert.equal(countOf('blockquote'), 1)
    assert.equal(editor.state.doc.child(0).textContent, 'quoted')
  })

  test('Esc leaves a code block', () => {
    editor.commands.setContent('<pre><code>x = 1</code></pre>', false)
    editor.commands.setTextSelection(3)
    key('Escape')
    assert.equal(atTopLevel(), true)
    assert.equal(countOf('codeBlock'), 1)
    assert.equal(editor.state.doc.child(0).textContent, 'x = 1')
  })

  test('Enter twice still lifts out of a blockquote', () => {
    editor.commands.setContent('<blockquote><p>q</p></blockquote>', false)
    editor.commands.setTextSelection(3)
    enter(2)
    assert.equal(atTopLevel(), true)
    assert.equal(countOf('blockquote'), 1)
    assert.equal(editor.state.doc.child(0).childCount, 1)
  })

  test('three Enters still leave a code block', () => {
    editor.commands.setContent('<pre><code>x</code></pre>', false)
    editor.commands.setTextSelection(2)
    enter(3)
    assert.equal(atTopLevel(), true)
    assert.equal(editor.state.doc.child(0).textContent, 'x')
  })

  test('Esc does nothing in ordinary body text', () => {
    editor.commands.setContent('<p>plain</p>', false)
    editor.commands.setTextSelection(3)
    key('Escape')
    assert.equal(editor.state.doc.childCount, 1)
    assert.equal(editor.state.selection.head, 3)
  })

  test('Esc closes an open menu rather than leaving the block', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertTabs(2)
    win.document.getElementById('insert-menu').classList.add('visible')
    key('Escape')
    assert.equal(atTopLevel(), false)
    win.document.getElementById('insert-menu').classList.remove('visible')
  })

  test('Enter twice leaves the first tab panel', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertTabs(2)
    editor.commands.insertContent('one')
    enter(2)
    assert.equal(atTopLevel(), true)
    assert.equal(countOf('tabPanel'), 2)
    assert.equal(countOf('paragraph'), 3)
  })

  test('Enter twice leaves a column with the columns block intact', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertColumns(2)
    editor.commands.insertContent('left')
    enter(2)
    assert.equal(atTopLevel(), true)
    assert.equal(countOf('columnsBlock'), 1)
    assert.equal(countOf('columnBlock'), 2)
  })

  test('Enter twice still leaves a details body', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertDetails()
    editor.commands.insertContent('body')
    enter(2)
    assert.equal(atTopLevel(), true)
    assert.equal(countOf('detailsBlock'), 1)
  })

  test('Enter twice still leaves an accordion panel', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertAccordion()
    into('accordionPanel', 0)
    editor.commands.insertContent('body')
    enter(2)
    assert.equal(atTopLevel(), true)
    assert.equal(countOf('accordionBlock'), 1)
  })

  test('Enter on a panel’s only empty paragraph leaves without emptying it', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertTabs(2)
    into('tabPanel', 0)
    key('Enter')
    assert.equal(atTopLevel(), true)
    let panel = null
    editor.state.doc.descendants(n => { if (!panel && n.type.name === 'tabPanel') panel = n })
    assert.equal(panel.childCount, 1)
  })

  test('Enter in a table cell still just adds a paragraph', () => {
    editor.commands.setContent('<p></p>', false)
    editor.chain().insertTable({ rows: 2, cols: 2 }).run()
    into('tableCell', 0)
    enter(2)
    assert.equal(atTopLevel(), false)
    assert.equal(countOf('table'), 1)
  })

  test('Enter mid-panel still splits the paragraph normally', () => {
    editor.commands.setContent('<p></p>', false)
    win.insertTabs(2)
    editor.commands.insertContent('one')
    editor.commands.setTextSelection(editor.state.selection.head - 1)
    key('Enter')
    assert.equal(atTopLevel(), false)
    let panel = null
    editor.state.doc.descendants(n => { if (!panel && n.type.name === 'tabPanel') panel = n })
    assert.equal(panel.childCount, 2)
  })

  test('Enter in a preformatted block adds a line, not a paragraph', () => {
    editor.commands.setContent('<p></p>', false)
    editor.chain().setPreformatted().run()
    editor.commands.insertContent('one')
    key('Enter')
    editor.commands.insertContent('two')
    assert.equal(countOf('preformatted'), 1)
    assert.equal(editor.state.doc.child(0).textContent, 'one\ntwo')
  })

  test('three Enters leave a preformatted block, trailing blank lines trimmed', () => {
    editor.commands.setContent('<p></p>', false)
    editor.chain().setPreformatted().run()
    editor.commands.insertContent('code')
    enter(3)
    assert.equal(atTopLevel(), true)
    assert.equal(editor.state.doc.child(0).textContent, 'code')
  })

  test('Enter in a pullquote makes a paragraph, never a citation', () => {
    editor.commands.setContent(
      '<figure class="wp-block-pullquote"><blockquote><p>Q</p></blockquote></figure>', false)
    editor.commands.setTextSelection(4)
    key('Enter')
    assert.equal(countOf('cite'), 0)
    assert.equal(editor.state.doc.child(0).childCount, 2)
    assert.equal(editor.state.doc.child(0).child(1).type.name, 'paragraph')
  })

  test('Enter twice leaves a pullquote', () => {
    editor.commands.setContent(
      '<figure class="wp-block-pullquote"><blockquote><p>Q</p></blockquote></figure>', false)
    editor.commands.setTextSelection(4)
    enter(2)
    assert.equal(atTopLevel(), true)
    assert.equal(countOf('pullquote'), 1)
  })
})

// The citation control was written against blockquote only, so a pullquote —
// whose schema allows a cite just the same — had no way to get one.
describe('citation control', () => {
  const citeBtn = () => win.document.getElementById('btn-toggle-cite')
  const press = () => citeBtn().dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }))
  const group = () => win.document.getElementById('blockquote-controls')

  const countOf = typeName => {
    let n = 0
    editor.state.doc.descendants(node => { if (node.type.name === typeName) n++ })
    return n
  }

  const PULLQUOTE = '<figure class="wp-block-pullquote"><blockquote><p>Q</p></blockquote></figure>'

  before(() => { editor.view.dom.blur() })

  test('the control reads Cite rather than showing an icon', () => {
    assert.equal(citeBtn().textContent.trim(), 'Cite')
    assert.equal(citeBtn().querySelector('svg'), null)
  })

  test('the control is offered inside a pullquote', () => {
    editor.commands.setContent(PULLQUOTE, false)
    editor.commands.setTextSelection(4)
    assert.notEqual(group().style.display, 'none')
  })

  test('it adds a citation to a pullquote', () => {
    editor.commands.setContent(PULLQUOTE, false)
    editor.commands.setTextSelection(4)
    press()
    const pq = editor.state.doc.child(0)
    assert.equal(pq.lastChild.type.name, 'cite')
    assert.equal(countOf('cite'), 1)
  })

  test('the caret lands in the pullquote citation ready to type', () => {
    editor.commands.setContent(PULLQUOTE, false)
    editor.commands.setTextSelection(4)
    press()
    editor.commands.insertContent('Someone')
    assert.equal(editor.state.doc.child(0).lastChild.textContent, 'Someone')
  })

  test('it removes a pullquote citation again', () => {
    editor.commands.setContent(PULLQUOTE, false)
    editor.commands.setTextSelection(4)
    press()
    assert.equal(countOf('cite'), 1)
    press()
    assert.equal(countOf('cite'), 0)
    assert.equal(editor.state.doc.child(0).type.name, 'pullquote')
  })

  test('a pullquote citation saves inside the blockquote', () => {
    editor.commands.setContent(PULLQUOTE, false)
    editor.commands.setTextSelection(4)
    press()
    editor.commands.insertContent('Someone')
    const out = win.toWordPressHTML(editor.getHTML(), win.document)
    assert.match(out, /<!-- wp:pullquote -->/)
    assert.match(out, /<cite>Someone<\/cite>\s*<\/blockquote>/)
  })

  test('Enter in a pullquote citation leaves the pullquote', () => {
    editor.commands.setContent(PULLQUOTE, false)
    editor.commands.setTextSelection(4)
    press()
    editor.commands.insertContent('Someone')
    citeBtn().dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }))
    editor.commands.setContent(PULLQUOTE, false)
    editor.commands.setTextSelection(4)
    press()
    editor.view.dom.dispatchEvent(new win.KeyboardEvent('keydown', {
      key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true,
    }))
    assert.equal(editor.state.selection.$head.depth, 1)
    assert.equal(countOf('pullquote'), 1)
    assert.equal(countOf('cite'), 1)
  })

  test('it still adds and removes a blockquote citation', () => {
    editor.commands.setContent('<blockquote><p>Q</p></blockquote>', false)
    editor.commands.setTextSelection(4)
    press()
    assert.equal(countOf('cite'), 1)
    press()
    assert.equal(countOf('cite'), 0)
  })

  test('the control stays hidden in ordinary body text', () => {
    editor.commands.setContent('<p>plain</p>', false)
    editor.commands.setTextSelection(3)
    assert.equal(group().style.display, 'none')
  })
})
