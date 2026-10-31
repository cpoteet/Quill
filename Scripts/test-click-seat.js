'use strict'

const { test, describe, before, after } = require('node:test')
const assert = require('node:assert/strict')
const { JSDOM, VirtualConsole } = require('jsdom')
const fs = require('fs')
const path = require('path')
const nodeCrypto = require('crypto')
const { clickSeatTarget } = require('../Sources/QuillKit/Resources/click-seat.js')

const htmlPath = path.resolve(__dirname, '../Sources/QuillKit/Resources/editor.html')

const line = (top, bottom) => ({ first: { top, bottom }, last: { top, bottom } })

describe('clickSeatTarget', () => {
  test('a click on a line is left to WebKit', () => {
    assert.equal(clickSeatTarget([line(100, 120)], 110), null)
  })

  test('a click in the padding above a line seats on that line', () => {
    assert.deepEqual(clickSeatTarget([line(100, 120)], 90), { index: 0, y: 110 })
  })

  test('a click in the padding below a line seats on that line', () => {
    assert.deepEqual(clickSeatTarget([line(100, 120)], 130), { index: 0, y: 110 })
  })

  test('a multi-line block seats on its first line from above and its last line from below', () => {
    const block = { first: { top: 100, bottom: 120 }, last: { top: 140, bottom: 160 } }
    assert.equal(clickSeatTarget([block], 90).y, 110)
    assert.equal(clickSeatTarget([block], 170).y, 150)
    assert.equal(clickSeatTarget([block], 130), null)
  })

  test('a click between two blocks seats on the nearer one', () => {
    const lines = [line(100, 120), line(160, 180)]
    assert.equal(clickSeatTarget(lines, 128).index, 0)
    assert.equal(clickSeatTarget(lines, 152).index, 1)
  })

  test('a click midway between two blocks seats on the later one', () => {
    assert.equal(clickSeatTarget([line(100, 120), line(160, 180)], 140).index, 1)
  })

  test('a click farther than two lines from every line is left to WebKit', () => {
    assert.equal(clickSeatTarget([line(100, 120)], 161), null)
    assert.notEqual(clickSeatTarget([line(100, 120)], 159), null)
  })

  test('a click on any line leaves the whole click to WebKit', () => {
    assert.equal(clickSeatTarget([line(100, 120), line(160, 180)], 170), null)
  })

  test('no candidate lines means nothing to seat', () => {
    assert.equal(clickSeatTarget([], 100), null)
  })

  test('the reach above a block is measured in first-line heights', () => {
    const block = { first: { top: 100, bottom: 120 }, last: { top: 140, bottom: 240 } }
    assert.equal(clickSeatTarget([block], 55), null)
    assert.notEqual(clickSeatTarget([block], 65), null)
  })
})

let win
let editor

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
  const rect = { top: 0, left: 0, bottom: 0, right: 0, width: 0, height: 0 }
  for (const proto of [win.Text.prototype, win.Range.prototype]) {
    if (proto.getClientRects) continue
    proto.getClientRects = () => Object.assign([rect], { item: () => rect })
    proto.getBoundingClientRect = () => rect
  }
  win.webkit = { messageHandlers: { contentChanged: { postMessage() {} } } }
  editor = await new Promise((resolve, reject) => {
    let tries = 0
    const t = setInterval(() => {
      if (win._tiptapEditor) { clearInterval(t); resolve(win._tiptapEditor) }
      else if (++tries > 400) { clearInterval(t); reject(new Error('editor never became ready.\n' + logs.join('\n'))) }
    }, 25)
  })
})

after(() => { if (win) win.close() })

// Two paragraphs: p1 is 0-4 (text 1-3), p2 is 4-8 (text 5-7); the gap between them is position 4.
const LINES = { p1: { top: 100, bottom: 120 }, p2: { top: 160, bottom: 180 } }

function fakeView(first, { box = () => ({ left: 0, right: 800 }) } = {}) {
  win.setContent('<p>aa</p><p>bb</p>')
  return {
    state: editor.state,
    posAtCoords: ({ top }) => first.used ? { pos: top < 140 ? 3 : 7, inside: -1 } : (first.used = true, first.hit),
    coordsAtPos: pos => (pos <= 3 ? LINES.p1 : LINES.p2),
    nodeDOM: pos => ({ getBoundingClientRect: () => box(pos) }),
  }
}

const press = (y, extra = {}) => ({ button: 0, detail: 1, clientX: 400, clientY: y, target: win.document.body, ...extra })

describe('seating a press that lands outside every line', () => {
  test('a click in the gap seats on the nearer block at the click', () => {
    const above = win._seatForPress(fakeView({ hit: { pos: 4, inside: -1 } }), press(128))
    assert.equal(above.pos, 3)
    const below = win._seatForPress(fakeView({ hit: { pos: 4, inside: -1 } }), press(152))
    assert.equal(below.pos, 7)
  })

  test('a click on a line is left to WebKit', () => {
    assert.equal(win._seatForPress(fakeView({ hit: { pos: 2, inside: 0 } }), press(110)), null)
  })

  test('a secondary button, a double click and a modifier are left to WebKit', () => {
    for (const extra of [{ button: 2 }, { detail: 2 }, { shiftKey: true }, { metaKey: true }, { altKey: true }]) {
      assert.equal(win._seatForPress(fakeView({ hit: { pos: 4, inside: -1 } }), press(128, extra)), null, JSON.stringify(extra))
    }
  })

  test('a click on non-editable chrome is left alone', () => {
    const chrome = win.document.createElement('div')
    chrome.setAttribute('contenteditable', 'false')
    win.document.body.append(chrome)
    assert.equal(win._seatForPress(fakeView({ hit: { pos: 4, inside: -1 } }), press(128, { target: chrome })), null)
    chrome.remove()
  })

  test('a click inside a node never seats in a block outside it', () => {
    const seat = win._seatForPress(fakeView({ hit: { pos: 5, inside: 4 } }), press(135))
    assert.equal(seat.pos, 7)
  })

  test('a block that does not span the click horizontally is not a candidate', () => {
    const box = pos => (pos === 0 ? { left: 500, right: 800 } : { left: 0, right: 800 })
    const seat = win._seatForPress(fakeView({ hit: { pos: 4, inside: -1 } }, { box }), press(128))
    assert.equal(seat.pos, 7)
  })

  test('a position that lands outside the chosen block seats nothing', () => {
    const view = fakeView({ hit: { pos: 4, inside: -1 } })
    view.posAtCoords = ({ top }) => (top === 128 ? { pos: 4, inside: -1 } : { pos: 7, inside: -1 })
    assert.equal(win._seatForPress(view, press(128)), null)
  })

  describe('beside a block that keeps WebKit\'s default', () => {
    const BUTTONS = '<!-- wp:paragraph --><p>aa</p><!-- /wp:paragraph --><!-- wp:buttons --><div class="wp-block-buttons"><!-- wp:button --><div class="wp-block-button"><a class="wp-block-button__link wp-element-button">bb</a></div><!-- /wp:button --></div><!-- /wp:buttons -->'

    function buttonView() {
      win.setContent(BUTTONS)
      let button = -1
      editor.state.doc.descendants((node, pos) => { if (node.type.name === 'buttonBlock') button = pos })
      const buttonEnd = button + editor.state.doc.nodeAt(button).nodeSize - 1
      let asked = 0
      return {
        state: editor.state,
        posAtCoords: ({ top }) => (asked++ === 0 ? { pos: 4, inside: -1 } : { pos: top < 140 ? 3 : buttonEnd, inside: -1 }),
        coordsAtPos: pos => (pos <= 3 ? LINES.p1 : LINES.p2),
        nodeDOM: () => ({ getBoundingClientRect: () => ({ left: 0, right: 800 }) }),
      }
    }

    test('a click on its line is not seated in the paragraph above', () => {
      assert.equal(win._seatForPress(buttonView(), press(170))?.pos ?? null, null)
    })

    test('a click nearer to it than to the paragraph above is left to WebKit', () => {
      assert.equal(win._seatForPress(buttonView(), press(152))?.pos ?? null, null)
    })

    test('a click nearer to the paragraph above still seats there', () => {
      assert.equal(win._seatForPress(buttonView(), press(128)).pos, 3)
    })
  })

  test('the seat records the document it was measured against', () => {
    const view = fakeView({ hit: { pos: 4, inside: -1 } })
    assert.equal(win._seatForPress(view, press(128)).doc, view.state.doc)
  })
})
