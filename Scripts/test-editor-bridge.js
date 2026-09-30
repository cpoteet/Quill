'use strict'

// Loads the real editor.html in jsdom and checks window.flushContent, which Swift
// calls before it saves, previews, switches posts or quits.

const { test, describe, before, after } = require('node:test')
const assert = require('node:assert/strict')
const { JSDOM, VirtualConsole } = require('jsdom')
const fs = require('fs')
const path = require('path')
const nodeCrypto = require('crypto')

const htmlPath = path.resolve(__dirname, '../Sources/QuillKit/Resources/editor.html')

let editor
let win
const sentToSwift = []

const wait = ms => new Promise(resolve => setTimeout(resolve, ms))

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

function typeAtEnd(text) {
  editor.commands.focus('end')
  editor.commands.insertContent(text)
}

describe('flushContent', () => {
  test('returns typing the debounce has not posted yet', () => {
    win.setContent('<p>Start</p>', '')
    typeAtEnd(' typed')
    const snapshot = win.flushContent()
    assert.ok(snapshot, 'expected a snapshot')
    assert.match(snapshot.html, /Start typed/)
    assert.equal(typeof snapshot.footnotes, 'string')
  })

  test('cancels the pending post instead of sending it again', async () => {
    win.setContent('<p>Start</p>', '')
    typeAtEnd(' again')
    const before = sentToSwift.length
    win.flushContent()
    await wait(650)
    assert.equal(sentToSwift.length, before)
  })

  test('returns null when nothing is waiting to be posted', async () => {
    win.setContent('<p>Start</p>', '')
    typeAtEnd(' posted')
    await wait(650)
    assert.equal(win.flushContent(), null)
  })

  test('returns null once setContent has replaced the document', () => {
    win.setContent('<p>Old</p>', '')
    typeAtEnd(' edit')
    win.setContent('<p>New</p>', '')
    assert.equal(win.flushContent(), null)
  })

  test('returns a code-view edit the debounce has not posted yet', () => {
    win.setContent('<p>Start</p>', '')
    const button = win.document.getElementById('btn-code-view')
    button.click()
    const area = win.document.getElementById('code-editor')
    area.value = '<!-- wp:paragraph -->\n<p>From code view</p>\n<!-- /wp:paragraph -->'
    area.dispatchEvent(new win.Event('input'))
    const snapshot = win.flushContent()
    button.click()
    assert.ok(snapshot, 'expected a snapshot')
    assert.match(snapshot.html, /From code view/)
  })
})
