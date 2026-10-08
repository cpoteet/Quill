'use strict'

// Evaluate's Apply against the real editor.html: applyEvaluationFinding and findingStatus.

const { test, describe, before, after } = require('node:test')
const assert = require('node:assert/strict')
const { JSDOM, VirtualConsole } = require('jsdom')
const fs = require('fs')
const path = require('path')
const nodeCrypto = require('crypto')

const htmlPath = path.resolve(__dirname, '../Sources/QuillKit/Resources/editor.html')
const evaluateDir = path.resolve(__dirname, 'fixtures', 'evaluate')

let editor
let win

before(async () => {
  const vc = new VirtualConsole()
  const logs = []
  vc.on('jsdomError', e => logs.push('JSDOM_ERROR: ' + (e.detail?.stack || e.message || e)))
  const dom = new JSDOM(fs.readFileSync(htmlPath, 'utf8'), {
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

function load(html, footnotes) {
  win.setContent(html, footnotes)
}

function body() {
  return editor.getHTML()
}

describe('applyEvaluationFinding', () => {
  test('applies a correction inside a paragraph and keeps surrounding marks', () => {
    load('<p>It <em>feel</em> off in recent years.</p>')
    assert.equal(win.applyEvaluationFinding('It feel off', 'It fell off'), 'applied')
    assert.equal(body(), '<p>It <em>fell</em> off in recent years.</p>')
  })

  test('returns missing after the text was edited', () => {
    load('<p>The numbers tell the story.</p>')
    assert.equal(win.applyEvaluationFinding('the numbers tells', 'the numbers tell'), 'missing')
    assert.equal(body(), '<p>The numbers tell the story.</p>')
  })

  test('returns ambiguous when the original appears twice and changes nothing', () => {
    load('<p>on on this blog</p><p>on on that blog</p>')
    assert.equal(win.applyEvaluationFinding('on on', 'on'), 'ambiguous')
    assert.equal(body(), '<p>on on this blog</p><p>on on that blog</p>')
  })

  test('keeps a link on unchanged words', () => {
    load('<p>See the <a href="https://example.com">docs</a> today.</p>')
    assert.equal(win.applyEvaluationFinding('the docs', 'these docs'), 'applied')
    assert.match(body(), /<p>See these <a[^>]*href="https:\/\/example.com"[^>]*>docs<\/a> today.<\/p>/)
  })

  test('applies across a link boundary', () => {
    load('<p>Read the <a href="https://example.com">fine docs</a> today.</p>')
    assert.equal(win.applyEvaluationFinding('the fine docs today', 'the fine manual now'), 'applied')
    assert.match(body(), /<p>Read the <a[^>]*>fine manual<\/a> now.<\/p>/)
  })

  test('empty replacement deletes the text', () => {
    load('<p>Write every day, honestly, even when it is bad.</p>')
    assert.equal(win.applyEvaluationFinding(' honestly,', ''), 'applied')
    assert.equal(body(), '<p>Write every day, even when it is bad.</p>')
  })

  test('applies inside a caption and a table cell', () => {
    load('<figure class="wp-block-image"><img src="https://example.com/a.jpg"><figcaption>before it feel off</figcaption></figure><table><tbody><tr><td>teh total</td><td>12</td></tr></tbody></table>')
    assert.equal(win.applyEvaluationFinding('it feel off', 'it fell off'), 'applied')
    assert.equal(win.applyEvaluationFinding('teh total', 'the total'), 'applied')
    const html = body()
    assert.match(html, /<figcaption[^>]*>before it fell off<\/figcaption>/)
    assert.match(html, /<td[^>]*>(<p>)?the total(<\/p>)?<\/td>/)
  })

  test('one undo restores the original', async () => {
    load('<p>It <em>feel</em> off, but it gives a window.</p>')
    const before = body()
    // History merges transactions less than 500 ms apart; in the app the load is long past.
    await new Promise(resolve => setTimeout(resolve, 600))
    assert.equal(win.applyEvaluationFinding('It feel off, but it gives', 'It fell off, but they give'), 'applied')
    assert.notEqual(body(), before)
    editor.commands.undo()
    assert.equal(body(), before)
  })

  test('matches through typographic quotes', () => {
    load('<p>It’s been quite a ride.</p>')
    assert.equal(win.applyEvaluationFinding("It's been quite", 'It has been quite'), 'applied')
    assert.equal(body(), '<p>It has been quite a ride.</p>')
  })

  test('does not match across two paragraphs', () => {
    load('<p>Counting</p><p>I started</p>')
    assert.equal(win.applyEvaluationFinding('CountingI', 'Counting I'), 'missing')
  })

  test('is case-sensitive', () => {
    load('<p>WordPress and wordpress</p>')
    assert.equal(win.applyEvaluationFinding('wordpress', 'WordPress'), 'applied')
    assert.equal(body(), '<p>WordPress and WordPress</p>')
  })

  test('an inserted word lands between the right words', () => {
    load('<p>stands out as prime offender</p>')
    assert.equal(win.applyEvaluationFinding('as prime offender', 'as the prime offender'), 'applied')
    assert.equal(body(), '<p>stands out as the prime offender</p>')
  })

  test('keeps a footnote marker inside a changed run', () => {
    const id = 'fn-11111111-2222-4333-8444-555555555555'
    load(`<p>This is very, very important<sup data-fn="${id}" class="fn" id="${id}-link"><a href="#${id}">1</a></sup> for users.</p>\n\n<!-- wp:footnotes /-->`,
      JSON.stringify([{ id, content: 'The note.' }]))
    assert.equal(win.applyEvaluationFinding('This is very, very important for users', 'This matters to users'), 'applied')
    const html = body()
    assert.match(html, new RegExp(`data-fn="${id}"`))
    assert.match(html, /The note\./)
    assert.match(win.document.querySelector('.ProseMirror p').textContent, /^This matters to1? users\.$/)
  })

  test('matches a non-breaking space as a plain one', () => {
    load('<p>Windows&nbsp;11 are great.</p>')
    assert.equal(win.findingStatus(['Windows 11 are great'])[0], 'ok')
    assert.equal(win.applyEvaluationFinding('Windows 11 are great', 'Windows 11 is great'), 'applied')
    assert.match(body(), /<p>Windows(&nbsp;|\u00A0)11 is great\.<\/p>/)
  })

  test('matches whole words only', () => {
    load('<p>The edits and its benefits.</p>')
    assert.equal(win.findingStatus(['its'])[0], 'ok')
    assert.equal(win.applyEvaluationFinding('its', 'their'), 'applied')
    assert.equal(body(), '<p>The edits and their benefits.</p>')
  })

  test('a line break matches a space and is kept', () => {
    load('<p>line one<br>line two is here</p>')
    assert.equal(win.findingStatus(['line one line two'])[0], 'ok')
    assert.equal(win.applyEvaluationFinding('line one line two is here', 'line one line two was here'), 'applied')
    assert.equal(body(), '<p>line one<br>line two was here</p>')
  })

  test('a changed phrase across a line break keeps the break', () => {
    load('<p>The very<br>important matter.</p>')
    assert.equal(win.applyEvaluationFinding('very important', 'critical'), 'applied')
    assert.equal(body(), '<p>The critical<br> matter.</p>')
  })

  test('a non-breaking space typed after a sentence matches two spaces', () => {
    load('<p>This is one.&nbsp; This are wrong.</p>')
    assert.equal(win.findingStatus(['one.  This are wrong'])[0], 'ok')
  })

  test('refuses while code view is open and changes nothing', () => {
    load('<p>It feel off.</p>')
    const toggle = () => win.document.getElementById('btn-code-view').dispatchEvent(new win.Event('click', { bubbles: true }))
    toggle()
    try {
      assert.equal(win.applyEvaluationFinding('It feel off', 'It fell off'), 'code-view')
      assert.equal(body(), '<p>It feel off.</p>')
    } finally {
      toggle()
    }
  })
})

describe('findingStatus', () => {
  test('reports ok, missing and ambiguous without editing', () => {
    load('<p>on on this blog, it feel off.</p><p>on on again</p>')
    const before = body()
    assert.deepEqual(Array.from(win.findingStatus(['it feel off', 'not here', 'on on', ''])), ['ok', 'missing', 'ambiguous', 'missing'])
    assert.equal(body(), before)
  })
})

describe('the editor search text', () => {
  test('matches the Evaluate fixture Swift checks postText against', () => {
    load(fs.readFileSync(path.join(evaluateDir, 'post.html'), 'utf8'), fs.readFileSync(path.join(evaluateDir, 'post.footnotes.json'), 'utf8').trim())
    assert.equal(win._editorSearchText().text, fs.readFileSync(path.join(evaluateDir, 'post.editor-text.txt'), 'utf8'))
  })
})
