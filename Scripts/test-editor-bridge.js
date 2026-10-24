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

  test('returns null once syncContentToSwift has posted the typing', () => {
    win.setContent('<p>Start</p>', '')
    typeAtEnd(' synced')
    win.syncContentToSwift()
    assert.equal(win.flushContent(), null)
  })

  test('the snapshot is exactly what the debounce would have posted', () => {
    win.setContent('<!-- wp:paragraph -->\n<p>Start</p>\n<!-- /wp:paragraph -->', '')
    typeAtEnd(' typed')
    const snapshot = win.flushContent()
    win.syncContentToSwift()
    assert.equal(snapshot.html, sentToSwift.at(-1))
  })

  test('the snapshot splits footnotes out: the delimiter in the HTML, the bodies in the meta', () => {
    const id = 'fn-11111111-2222-4333-8444-555555555555'
    const marker = `<sup data-fn="${id}" class="fn" id="${id}-link"><a href="#${id}">1</a></sup>`
    win.setContent(`<!-- wp:paragraph -->\n<p>Body${marker}</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`,
      JSON.stringify([{ id, content: 'A note.' }]))
    editor.commands.insertContentAt(1, 'x')
    const snapshot = win.flushContent()
    assert.match(snapshot.html, /^<!-- wp:paragraph -->\n<p>xBody<sup/)
    assert.ok(snapshot.html.endsWith('\n\n<!-- wp:footnotes /-->'), snapshot.html)
    assert.doesNotMatch(snapshot.html, /wp-block-footnotes/)
    assert.deepEqual(JSON.parse(snapshot.footnotes), [{ id, content: 'A note.' }])
  })

  test('returns a code-view edit the debounce has not posted yet', () => {
    win.setContent('<p>Start</p>', '')
    const button = win.document.getElementById('btn-code-view')
    button.click()
    const area = win.document.getElementById('code-editor')
    const typed = '<!-- wp:paragraph -->\n<p>From code view</p>\n<!-- /wp:paragraph -->'
    area.value = typed
    area.dispatchEvent(new win.Event('input'))
    const snapshot = win.flushContent()
    button.click()
    assert.ok(snapshot, 'expected a snapshot')
    assert.equal(snapshot.html, typed)
  })
})

function _depthOf($pos, typeName) {
  for (let d = $pos.depth; d > 0; d--) if ($pos.node(d).type.name === typeName) return d
  return -1
}

describe('insertImage with a library caption', () => {
  const images = () => {
    const found = []
    editor.state.doc.descendants(n => { if (n.type.name === 'image') found.push(n) })
    return found
  }
  const insert = caption => {
    win.setContent('<p></p>', '')
    win.insertImage('https://example.com/a.jpg', 7, 'Alt', 800, caption)
    return win.getContent()
  }

  test('links and bold in the caption are kept', () => {
    const html = insert('Photo by <a href="https://example.com/jane">Jane</a> and <strong>friends</strong>')
    assert.match(html, /<figcaption class="wp-element-caption">Photo by <a href="https:\/\/example\.com\/jane">Jane<\/a> and <strong>friends<\/strong><\/figcaption>/)
    assert.equal(images().length, 1)
  })

  test('the caret ends in a paragraph after the image, not in the caption', () => {
    insert('A caption')
    const { $from } = editor.state.selection
    assert.equal($from.parent.type.name, 'paragraph')
    assert.equal(_depthOf($from, 'image'), -1)
  })

  test('block markup in a caption stays inside one image', () => {
    insert('<p>One</p><p>Two</p>')
    const found = images()
    assert.equal(found.length, 1)
    assert.match(found[0].textContent, /One/)
    assert.match(found[0].textContent, /Two/)
  })

  test('a script handler in the caption is not carried', () => {
    const html = insert('<a href="https://example.com" onclick="window.ran = true">Credit</a>')
    assert.match(html, />Credit<\/a>/)
    assert.doesNotMatch(html, /onclick/)
  })

  test('inserted partway through a paragraph, the caption goes in the image, not the text after it', () => {
    win.setContent('<p>Hello world</p>', '')
    editor.commands.setTextSelection(4)
    win.insertImage('https://example.com/a.jpg', 7, 'Alt', 800, 'NEWCAP')
    const found = images()
    assert.equal(found.length, 1)
    assert.equal(found[0].textContent, 'NEWCAP')
    assert.doesNotMatch(editor.state.doc.textContent.replace('NEWCAP', ''), /NEWCAP/)
    assert.match(editor.state.doc.textContent, /Hel/)
    assert.match(editor.state.doc.textContent, /lo world/)
  })

  test('no caption leaves no figcaption', () => {
    assert.doesNotMatch(insert(null), /<figcaption/)
    assert.doesNotMatch(insert(''), /<figcaption/)
  })
})
