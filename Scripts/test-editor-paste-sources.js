'use strict'

// Real clipboards, as WebKit hands them to the editor, pasted and saved; see fixtures/paste/README.md.

const { test, describe, before, after } = require('node:test')
const assert = require('node:assert/strict')
const { JSDOM, VirtualConsole } = require('jsdom')
const fs = require('fs')
const path = require('path')
const nodeCrypto = require('crypto')

const { problems, resaved, namesIn, close: closeValidator } = require('./wp-validator.js')

const htmlPath = path.resolve(__dirname, '../Sources/QuillKit/Resources/editor.html')
const pasteDir = path.resolve(__dirname, 'fixtures', 'paste')

let editor
let win
const sentToSwift = []
let footnotesMeta = '[]'
const uploads = []

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
  win.webkit = { messageHandlers: {
    contentChanged: { postMessage: html => sentToSwift.push(html) },
    footnotesChanged: { postMessage: json => { footnotesMeta = json } },
    uploadPastedImages: { postMessage: body => uploads.push(...body.images) },
  } }
  editor = await new Promise((resolve, reject) => {
    let tries = 0
    const t = setInterval(() => {
      if (win._tiptapEditor) { clearInterval(t); resolve(win._tiptapEditor) }
      else if (++tries > 400) { clearInterval(t); reject(new Error('editor never became ready.\n' + logs.join('\n'))) }
    }, 25)
  })
})

after(() => { if (win) win.close(); closeValidator() })

function pasteFixture(name, target = '<!-- wp:paragraph -->\n<p></p>\n<!-- /wp:paragraph -->', typed = '') {
  const html = fs.readFileSync(path.join(pasteDir, name + '.html'), 'utf8')
  const text = fs.readFileSync(path.join(pasteDir, name + '.txt'), 'utf8')
  win.setContent(target)
  editor.commands.focus('end')
  if (typed) editor.commands.insertContent(typed)
  const ev = new win.Event('paste', { bubbles: true, cancelable: true })
  const data = { 'text/html': html, 'text/plain': text }
  Object.defineProperty(ev, 'clipboardData', { value: { getData: t => data[t] || '', types: Object.keys(data), files: [] } })
  editor.view.dom.dispatchEvent(ev)
  win.syncContentToSwift()
  const notes = JSON.parse(footnotesMeta || '[]').map(fn => fn.content).join(' ')
  return { saved: sentToSwift.at(-1), text, notes }
}

const ALLOWED_STYLE = [/^(?:width:\d+px;height:(?:\d+px|auto))$/, /^list-style-type:[\w-]+$/, /^text-decoration: ?underline;?$/]
const ALLOWED_ATTRS = new Set(['href', 'src', 'alt', 'title', 'class', 'style', 'colspan', 'rowspan', 'scope', 'start', 'reversed',
  'target', 'rel', 'id', 'data-align', 'data-fn', 'open', 'name', 'controls', 'datetime'])
const ALLOWED_CLASS = /^(?:wp-block-[\w-]+|wp-element-[\w-]+|wp-image-\d+|wp-embed-aspect-[\w-]+|wp-has-aspect-ratio|has-[\w-]+|is-style-[\w-]+|is-resized|is-type-[\w-]+|is-provider-[\w-]+|align\w+|size-[\w-]+|language-[\w-]+|fn)$/

function foreignMarkup(saved) {
  const body = new JSDOM('<body>' + saved + '</body>').window.document.body
  const found = []
  body.querySelectorAll('*').forEach(el => {
    const tag = el.tagName.toLowerCase()
    if (['span', 'font', 'div'].includes(tag) && !el.attributes.length) found.push(`bare <${tag}>`)
    for (const a of el.attributes) {
      if (!ALLOWED_ATTRS.has(a.name)) found.push(`${tag}[${a.name}]`)
      if (a.name === 'style' && !(tag === 'mark' && el.classList.contains('has-inline-color')) && !ALLOWED_STYLE.some(re => re.test(a.value))) found.push(`${tag}[style="${a.value}"]`)
      if (a.name === 'class') a.value.split(/\s+/).filter(c => c && !ALLOWED_CLASS.test(c)).forEach(c => found.push(`${tag}.${c}`))
    }
  })
  body.querySelectorAll('p').forEach(p => { if (!p.textContent.replace(/[\s ]/g, '') && !p.querySelector('img')) found.push('empty <p>') })
  return found
}

const words = s => new Set((s.toLowerCase().normalize('NFKC').match(/[\p{L}\p{N}]{2,}/gu) || []))
function lostWords(saved, text, ignore) {
  const inline = /<\/?(?:sub|sup|strong|em|s|a|span|code|mark|b|i|u|kbd|abbr|small)\b[^>]*>/g
  const body = new JSDOM('<body>' + saved.replace(/<!--[\s\S]*?-->/g, '').replace(inline, '').replace(/<[^>]+>/g, ' ') + '</body>').window.document.body
  const alts = Array.from(new JSDOM('<body>' + saved + '</body>').window.document.querySelectorAll('img')).map(i => i.alt).join(' ')
  const have = words(body.textContent + ' ' + alts)
  return [...words(text)].filter(w => !have.has(w) && !ignore.includes(w))
}

// Words in the plain-text flavor that are UI, not content.
const CHROME_WORDS = {
  chatgpt: ['bash', 'copy', 'code'],
  'claude-ai': ['python', 'copy'],
}

const SOURCES = fs.readdirSync(pasteDir).filter(f => f.endsWith('.html')).map(f => f.slice(0, -5))
  .filter(name => !name.startsWith('webkit-')).sort()

describe('every captured clipboard pastes as valid, clean Gutenberg markup', () => {
  for (const name of SOURCES) {
    test(name, () => {
      const { saved, text, notes } = pasteFixture(name)
      assert.deepEqual(problems(saved), [], saved)
      assert.equal(resaved(saved), saved, 'WordPress would rewrite this markup on its next save')
      assert.deepEqual(foreignMarkup(saved), [], saved)
      assert.deepEqual(lostWords(saved + ' ' + notes, text, CHROME_WORDS[name] || []), [], saved)
    })
  }
})

describe('what each source becomes', () => {
  test('Word lists become nested Gutenberg lists, lettered where Word lettered them', () => {
    const { saved } = pasteFixture('word-native')
    assert.doesNotMatch(saved, /·|&nbsp;/)
    assert.match(saved, /<ul class="wp-block-list"><!-- wp:list-item -->\n<li>First bullet<\/li>/)
    assert.match(saved, /<li>Second bullet<!-- wp:list -->\n<ul class="wp-block-list"><!-- wp:list-item -->\n<li>Nested bullet<\/li>/)
    assert.match(saved, /<!-- wp:list \{"ordered":true\} -->\n<ol class="wp-block-list"><!-- wp:list-item -->\n<li>Step one<\/li>/)
    assert.match(saved, /<!-- wp:list \{"ordered":true,"type":"lower-alpha"\} -->\n<ol style="list-style-type:lower-alpha" class="wp-block-list"><!-- wp:list-item -->\n<li>Sub step<\/li>/)
    assert.match(saved, /<p>Between the lists\.<\/p>/)
  })

  test('Word alignment becomes core text alignment, on paragraphs and table cells', () => {
    const { saved } = pasteFixture('word-native')
    assert.match(saved, /<!-- wp:paragraph \{"style":\{"typography":\{"textAlign":"center"\}\}\} -->\n<p class="has-text-align-center">Centered line<\/p>/)
    assert.match(saved, /<td class="has-text-align-right" data-align="right">42<\/td>/)
  })

  test('Word bookmarks and formatting become plain marks', () => {
    const { saved } = pasteFixture('word-native')
    assert.match(saved, /<h1 class="wp-block-heading">Quarterly report<\/h1>/)
    assert.match(saved, /This is <strong>bold<\/strong>, <em>italic<\/em>, <span style="text-decoration: ?underline;?">underlined<\/span>, <s>struck<\/s>, H<sub>2<\/sub>O, x<sup>2<\/sup> and a <a href="https:\/\/example.com\/page">link<\/a>\./)
  })

  test('a VS Code copy becomes one code block with its indentation', () => {
    const { saved } = pasteFixture('vscode')
    assert.deepEqual([...namesIn(saved)], ['core/code'])
    assert.match(saved, /<code>const a = 1\nif \(a &lt; 2\) \{\n  log\("hi"\)\n\}<\/code>/)
  })

  test('chat-app code blocks keep the code and drop the language label and copy button', () => {
    const gpt = pasteFixture('chatgpt').saved
    assert.match(gpt, /<pre class="wp-block-code language-bash"><code>npm install\nnpm run build<\/code><\/pre>/)
    assert.doesNotMatch(gpt, /Copy code|>bash</)
    const claude = pasteFixture('claude-ai').saved
    assert.match(claude, /<pre class="wp-block-code language-python"><code>def f\(\):\n    return 1<\/code><\/pre>/)
    assert.doesNotMatch(claude, /<p>(?:copy|python)<\/p>/)
  })

  test('Google Docs styling becomes marks, and its not-bold wrapper does not bold everything', () => {
    const { saved } = pasteFixture('google-docs')
    assert.match(saved, /Plain then <strong>bold<\/strong>, <em>italic<\/em>, <s>struck<\/s>, <a href="https:\/\/example.com\/">a link<\/a>\./)
    assert.match(saved, /<li>Bullet one<!-- wp:list -->/)
    assert.match(saved, /<p class="has-text-align-center">Centered line<\/p>/)
  })

  test('WordPress emoji images become the emoji, and block images leave no empty paragraph', () => {
    const { saved } = pasteFixture('web-images')
    assert.match(saved, /WordPress emoji 😀 in text\./)
    assert.doesNotMatch(saved, /class="emoji"/)
  })

  test('a phrase copied from a web page lands inside the paragraph with its word spaces', () => {
    const { saved } = pasteFixture('web-partial-inline', '<!-- wp:paragraph -->\n<p>Existing text</p>\n<!-- /wp:paragraph -->', ' ')
    assert.match(saved, /<p>Existing text Only <strong>these bold<\/strong> words<\/p>/)
  })

  test('a WordPress front-end copy drops render-only classes and turns its YouTube iframe back into an embed', () => {
    const { saved } = pasteFixture('web-wordpress-site')
    assert.doesNotMatch(saved, /is-layout-|wp-container-/)
    assert.match(saved, /<!-- wp:embed \{"url":"https:\/\/www.youtube.com\/watch\?v=dQw4w9WgXcQ"/)
  })
})

describe('paste fallbacks', () => {
  test("WebKit's empty HTML for a closed <details> falls back to the plain text", () => {
    const { saved } = pasteFixture('webkit-closed-details')
    assert.match(saved, /<p>Definition<\/p>/)
    assert.match(saved, /<p>Trailing paragraph\.<\/p>/)
    assert.deepEqual(problems(saved), [], saved)
  })

  test('a short selection with a closed <details> falls back too', () => {
    const { saved } = pasteFixture('webkit-closed-details-short')
    assert.match(saved, /<p>Before<\/p>[\s\S]*<p>After<\/p>/)
  })

  test("WebKit's extra <details> wrapper around an open one is dropped", () => {
    const { saved } = pasteFixture('webkit-open-details')
    assert.match(saved, /^<!-- wp:paragraph -->\n<p>Before<\/p>/)
    assert.match(saved, /<details class="wp-block-details" open><summary>Sum<\/summary><!-- wp:paragraph -->\n<p>Hidden<\/p>\n<!-- \/wp:paragraph --><\/details>/)
    assert.match(saved, /<p>After<\/p>\n<!-- \/wp:paragraph -->$/)
    assert.deepEqual(problems(saved), [], saved)
    assert.equal(resaved(saved), saved)
  })

  function pastePlain(text, target) {
    win.setContent(target)
    editor.commands.focus('end')
    const ev = new win.Event('paste', { bubbles: true, cancelable: true })
    Object.defineProperty(ev, 'clipboardData', { value: { getData: t => (t === 'text/plain' ? text : ''), types: ['text/plain'], files: [] } })
    editor.view.dom.dispatchEvent(ev)
    win.syncContentToSwift()
    return sentToSwift.at(-1)
  }

  test('a YouTube URL pasted into an empty paragraph becomes an embed', () => {
    const saved = pastePlain('https://www.youtube.com/watch?v=dQw4w9WgXcQ\n', '<!-- wp:paragraph -->\n<p></p>\n<!-- /wp:paragraph -->')
    assert.match(saved, /^<!-- wp:embed \{"url":"https:\/\/www.youtube.com\/watch\?v=dQw4w9WgXcQ","type":"video","providerNameSlug":"youtube"/)
    assert.deepEqual(problems(saved), [], saved)
  })

  test('plain text pasted into an empty formatted paragraph keeps that formatting', () => {
    const saved = pastePlain('hello', '<!-- wp:paragraph {"style":{"typography":{"textAlign":"center"}}} -->\n<p class="has-text-align-center"></p>\n<!-- /wp:paragraph -->')
    assert.match(saved, /^<!-- wp:paragraph \{"style":\{"typography":\{"textAlign":"center"\}\}\} -->\n<p class="has-text-align-center">hello<\/p>/)
  })

  test('the same URL pasted into a sentence stays a link', () => {
    const saved = pastePlain('https://www.youtube.com/watch?v=dQw4w9WgXcQ', '<!-- wp:paragraph -->\n<p>Watch </p>\n<!-- /wp:paragraph -->')
    assert.doesNotMatch(saved, /wp:embed/)
    assert.match(saved, /youtube\.com\/watch\?v=dQw4w9WgXcQ/)
  })

  test('a URL no embed provider handles stays a link', () => {
    const saved = pastePlain('https://example.com/page', '<!-- wp:paragraph -->\n<p></p>\n<!-- /wp:paragraph -->')
    assert.doesNotMatch(saved, /wp:embed/)
  })
})

describe('pasted images the site does not host yet', () => {
  const pixel = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='

  function pasteData(data, files = []) {
    win.setContent('<!-- wp:paragraph -->\n<p></p>\n<!-- /wp:paragraph -->')
    editor.commands.focus('end')
    const ev = new win.Event('paste', { bubbles: true, cancelable: true })
    Object.defineProperty(ev, 'clipboardData', { value: { getData: t => data[t] || '', types: Object.keys(data), files } })
    editor.view.dom.dispatchEvent(ev)
  }

  const settle = () => new Promise(resolve => setTimeout(resolve, 50))

  test('a screenshot on the clipboard is sent for upload and nothing is inserted yet', async () => {
    uploads.length = 0
    const bytes = Buffer.from(pixel.split(',')[1], 'base64')
    pasteData({}, [new win.File([bytes], 'Screenshot.png', { type: 'image/png' })])
    await settle()
    assert.equal(uploads.length, 1)
    assert.equal(uploads[0].token, null)
    assert.match(uploads[0].dataURL, /^data:image\/png;base64,/)
    assert.equal(editor.getJSON().content.map(n => n.type).join(' '), 'paragraph')
  })

  test('a data: image inside pasted HTML is sent with a token and swapped for the upload', async () => {
    uploads.length = 0
    pasteData({ 'text/html': `<p>Before</p><p><img src="${pixel}" alt="Chart"></p>`, 'text/plain': 'Before' })
    await settle()
    assert.equal(uploads.length, 1)
    assert.match(uploads[0].token, /^paste-\d+$/)
    win.resolvePastedImage(uploads[0].token, 'https://example.com/wp-content/uploads/chart.png', 321)
    win.syncContentToSwift()
    const saved = sentToSwift.at(-1)
    assert.doesNotMatch(saved, /data:image/)
    assert.match(saved, /<!-- wp:image \{"id":321\} -->\n<figure class="wp-block-image"><img src="https:\/\/example.com\/wp-content\/uploads\/chart.png" alt="Chart" class="wp-image-321"\/><\/figure>/)
    assert.deepEqual(problems(saved), [], saved)
  })

  test('an image Swift gave up on is sent again when it is pasted again', async () => {
    uploads.length = 0
    const html = `<p>Before</p><p><img src="${pixel}" alt="Chart"></p>`
    pasteData({ 'text/html': html, 'text/plain': 'Before' })
    await settle()
    win.forgetPastedImage(uploads[0].token)
    pasteData({ 'text/html': html, 'text/plain': 'Before' })
    await settle()
    assert.equal(uploads.length, 2)
    assert.notEqual(uploads[1].token, uploads[0].token)
    win.forgetPastedImage(uploads[1].token)
  })

  test('one undo after the upload lands takes back the paste, not just the swap to the uploaded file', async () => {
    uploads.length = 0
    pasteData({ 'text/html': `<p>Before</p><p><img src="${pixel}" alt="Chart"></p>`, 'text/plain': 'Before' })
    await settle()
    await new Promise(resolve => setTimeout(resolve, 600))
    win.resolvePastedImage(uploads[0].token, 'https://example.com/wp-content/uploads/chart.png', 321)
    editor.commands.undo()
    win.syncContentToSwift()
    assert.doesNotMatch(sentToSwift.at(-1), /data:image|chart\.png/)
  })

  test('a redo after that brings back the uploaded file, not the base64', () => {
    editor.commands.redo()
    win.syncContentToSwift()
    const saved = sentToSwift.at(-1)
    assert.doesNotMatch(saved, /data:image/)
    assert.match(saved, /<img src="https:\/\/example.com\/wp-content\/uploads\/chart.png" alt="Chart" class="wp-image-321"\/>/)
  })

  test('an image whose file the page cannot read is dropped rather than saved as a dead link', () => {
    pasteData({ 'text/html': '<p>Text</p><p><img src="file:///Users/me/clip_image001.png"></p>', 'text/plain': 'Text' })
    win.syncContentToSwift()
    assert.doesNotMatch(sentToSwift.at(-1), /img|file:/)
  })
})

describe('outside HTML cannot reach Quill internals', () => {
  test('delimiter JSON, event handlers and script links are stripped', () => {
    win.setContent('<!-- wp:paragraph -->\n<p></p>\n<!-- /wp:paragraph -->')
    editor.commands.focus('end')
    const html = '<p data-quill-block-attrs=\'{"className":"injected"}\' onclick="alert(1)">One</p>' +
      '<p><a href="javascript:alert(1)">Two</a> <a href="https://example.com" onmouseover="x()">Three</a></p>'
    const ev = new win.Event('paste', { bubbles: true, cancelable: true })
    const data = { 'text/html': html, 'text/plain': 'One Two Three' }
    Object.defineProperty(ev, 'clipboardData', { value: { getData: t => data[t] || '', types: Object.keys(data), files: [] } })
    editor.view.dom.dispatchEvent(ev)
    win.syncContentToSwift()
    const saved = sentToSwift.at(-1)
    assert.doesNotMatch(saved, /injected|onclick|onmouseover|javascript:/)
    assert.match(saved, /<a href="https:\/\/example.com">Three<\/a>/)
  })
})

describe('pasting into a list item', () => {
  test('pasted blocks become further list items, as the block editor pastes them', () => {
    const target = '<!-- wp:list -->\n<ul class="wp-block-list"><!-- wp:list-item -->\n<li>Item</li>\n<!-- /wp:list-item --></ul>\n<!-- /wp:list -->'
    win.setContent(target)
    editor.commands.focus('end')
    editor.commands.insertContent(' ')
    const ev = new win.Event('paste', { bubbles: true, cancelable: true })
    const data = { 'text/html': '<h2>Heading</h2><p>Para <strong>one</strong>.</p><ul><li>nested item</li></ul><p>Para two.</p>', 'text/plain': 'Heading Para one. nested item Para two.' }
    Object.defineProperty(ev, 'clipboardData', { value: { getData: t => data[t] || '', types: Object.keys(data), files: [] } })
    editor.view.dom.dispatchEvent(ev)
    win.syncContentToSwift()
    const saved = sentToSwift.at(-1)
    assert.doesNotMatch(saved, /<li><p>/)
    assert.match(saved, /<li>Item Heading<\/li>/)
    assert.match(saved, /<li>Para <strong>one<\/strong>\.<\/li>/)
    assert.match(saved, /<li>Para two\.<\/li>/)
    assert.equal(resaved(saved), saved)
    assert.deepEqual(problems(saved), [], saved)
  })
})

describe('pasted table cells hold text, as core cells do', () => {
  test('a list and a nested table inside a cell become lines, and a cell image its alt text', () => {
    win.setContent('<!-- wp:paragraph -->\n<p></p>\n<!-- /wp:paragraph -->')
    editor.commands.focus('end')
    const html = '<table><tbody><tr><td><img src="https://example.com/i.png" alt="Logo"> Name</td>' +
      '<td><p>First</p><ul><li>one</li><li>two</li></ul><table><tr><td>a</td><td>b</td></tr></table></td></tr></tbody></table>'
    const ev = new win.Event('paste', { bubbles: true, cancelable: true })
    const data = { 'text/html': html, 'text/plain': 'Logo Name First one two a b' }
    Object.defineProperty(ev, 'clipboardData', { value: { getData: t => data[t] || '', types: Object.keys(data), files: [] } })
    editor.view.dom.dispatchEvent(ev)
    win.syncContentToSwift()
    const saved = sentToSwift.at(-1)
    assert.match(saved, /<td>Logo Name<\/td><td>First<br>one<br>two<br>a b<\/td>/)
    assert.deepEqual(problems(saved), [], saved)
    assert.equal(resaved(saved), saved)
  })
})

describe('inline <cite>', () => {
  test("a reference list's inline citations stay in their items, and what follows stays out", () => {
    win.setContent('<!-- wp:paragraph -->\n<p></p>\n<!-- /wp:paragraph -->')
    editor.commands.focus('end')
    const html = '<ol><li><a href="#r1" title="Jump up"></a> <cite><a href="https://x.test/">"Codex"</a>. Retrieved 2014.</cite></li>' +
      '<li><cite>Second source</cite></li></ol><h2>External links</h2><p>After.</p>'
    const ev = new win.Event('paste', { bubbles: true, cancelable: true })
    const data = { 'text/html': html, 'text/plain': 'Codex Retrieved 2014 Second source External links After' }
    Object.defineProperty(ev, 'clipboardData', { value: { getData: t => data[t] || '', types: Object.keys(data), files: [] } })
    editor.view.dom.dispatchEvent(ev)
    win.syncContentToSwift()
    const saved = sentToSwift.at(-1)
    assert.equal(editor.getJSON().content.map(n => n.type).join(' '), 'orderedList heading paragraph')
    assert.match(saved, /<li><a href="https:\/\/x.test\/">"Codex"<\/a>\. Retrieved 2014\.<\/li>/)
    assert.doesNotMatch(saved, /<li><\/li>/)
    assert.deepEqual(problems(saved), [], saved)
  })

  test("a quote's citation is still a citation", () => {
    win.setContent('<!-- wp:paragraph -->\n<p></p>\n<!-- /wp:paragraph -->')
    editor.commands.focus('end')
    const ev = new win.Event('paste', { bubbles: true, cancelable: true })
    const data = { 'text/html': '<blockquote><p>Words.</p><cite>Someone</cite></blockquote>', 'text/plain': 'Words. Someone' }
    Object.defineProperty(ev, 'clipboardData', { value: { getData: t => data[t] || '', types: Object.keys(data), files: [] } })
    editor.view.dom.dispatchEvent(ev)
    win.syncContentToSwift()
    assert.match(sentToSwift.at(-1), /<!-- \/wp:paragraph --><cite>Someone<\/cite><\/blockquote>/)
  })
})

describe('block links', () => {
  test('a card link around blocks becomes a link inside each block, with no empty paragraphs', () => {
    win.setContent('<!-- wp:paragraph -->\n<p></p>\n<!-- /wp:paragraph -->')
    editor.commands.focus('end')
    const html = '<div><a href="https://x.test/v1"><div class="details"><div class="title">Get started</div><div>Watch now</div></div></a></div>'
    const ev = new win.Event('paste', { bubbles: true, cancelable: true })
    const data = { 'text/html': html, 'text/plain': 'Get started Watch now' }
    Object.defineProperty(ev, 'clipboardData', { value: { getData: t => data[t] || '', types: Object.keys(data), files: [] } })
    editor.view.dom.dispatchEvent(ev)
    win.syncContentToSwift()
    const saved = sentToSwift.at(-1)
    assert.match(saved, /<p><a href="https:\/\/x.test\/v1">Get started<\/a><\/p>/)
    assert.match(saved, /<p><a href="https:\/\/x.test\/v1">Watch now<\/a><\/p>/)
    assert.doesNotMatch(saved, /<p><\/p>/)
  })
})

describe('custom elements', () => {
  test("a site's custom-element wrappers leave neither empty paragraphs nor broken lines", () => {
    win.setContent('<!-- wp:paragraph -->\n<p></p>\n<!-- /wp:paragraph -->')
    editor.commands.focus('end')
    const html = '<mdn-content><mdn-section><h2>Title</h2><p>Updated <relative-time datetime="2026-01-01">Jan 1</relative-time> by me.</p></mdn-section></mdn-content>'
    const ev = new win.Event('paste', { bubbles: true, cancelable: true })
    const data = { 'text/html': html, 'text/plain': 'Title Updated Jan 1 by me.' }
    Object.defineProperty(ev, 'clipboardData', { value: { getData: t => data[t] || '', types: Object.keys(data), files: [] } })
    editor.view.dom.dispatchEvent(ev)
    win.syncContentToSwift()
    const saved = sentToSwift.at(-1)
    assert.equal(editor.getJSON().content.map(n => n.type).join(' '), 'heading paragraph')
    assert.match(saved, /<p>Updated Jan 1 by me\.<\/p>/)
  })
})

describe('definition lists', () => {
  test('terms become bold paragraphs and definitions keep their own paragraphs', () => {
    win.setContent('<!-- wp:paragraph -->\n<p></p>\n<!-- /wp:paragraph -->')
    editor.commands.focus('end')
    const html = '<dl><dt>Clipboard</dt><dd><p>Reads and writes.</p></dd><dt>Plain term</dt><dd>Plain definition</dd></dl>'
    const ev = new win.Event('paste', { bubbles: true, cancelable: true })
    const data = { 'text/html': html, 'text/plain': 'Clipboard Reads and writes. Plain term Plain definition' }
    Object.defineProperty(ev, 'clipboardData', { value: { getData: t => data[t] || '', types: Object.keys(data), files: [] } })
    editor.view.dom.dispatchEvent(ev)
    win.syncContentToSwift()
    const saved = sentToSwift.at(-1)
    assert.doesNotMatch(saved, /<p><\/p>/)
    assert.match(saved, /<p><strong>Clipboard<\/strong><\/p>[\s\S]*<p>Reads and writes\.<\/p>[\s\S]*<p><strong>Plain term<\/strong><\/p>[\s\S]*<p>Plain definition<\/p>/)
  })
})

function pasteHTML(html, text, target = '<!-- wp:paragraph -->\n<p></p>\n<!-- /wp:paragraph -->', typed = '') {
  win.setContent(target)
  editor.commands.focus('end')
  if (typed) editor.commands.insertContent(typed)
  const ev = new win.Event('paste', { bubbles: true, cancelable: true })
  const data = { 'text/html': html, 'text/plain': text }
  Object.defineProperty(ev, 'clipboardData', { value: { getData: t => data[t] || '', types: Object.keys(data), files: [] } })
  editor.view.dom.dispatchEvent(ev)
  win.syncContentToSwift()
  return sentToSwift.at(-1)
}

const blocksOf = saved => [...saved.matchAll(/<!-- wp:([\w/-]+)/g)].map(m => m[1])

describe('players a source embeds', () => {
  test('a video or audio player becomes a core block, and one the site cannot reach is dropped', () => {
    const saved = pasteHTML('<p>Before</p><figure><video src="https://x.test/v.mp4" autoplay muted></video><figcaption>Clip</figcaption></figure>' +
      '<audio><source src="https://x.test/a.mp3"></audio><video src="file:///Users/me/v.mp4"></video><p>After</p>', 'Before Clip After')
    assert.deepEqual(blocksOf(saved), ['paragraph', 'video', 'audio', 'paragraph'])
    assert.match(saved, /<!-- wp:video -->\n<figure class="wp-block-video"><video controls="" src="https:\/\/x.test\/v.mp4"><\/video><figcaption>Clip<\/figcaption><\/figure>\n<!-- \/wp:video -->/)
    assert.match(saved, /<!-- wp:audio -->\n<figure class="wp-block-audio"><audio controls="" src="https:\/\/x.test\/a.mp3"><\/audio><\/figure>\n<!-- \/wp:audio -->/)
    assert.doesNotMatch(saved, /autoplay|muted|file:/)
  })

  test('Vimeo, privacy-mode YouTube and Spotify players become embeds of their page URL, and any other frame is dropped', () => {
    const saved = pasteHTML('<p>A</p><iframe src="https://player.vimeo.com/video/76979871?h=abc"></iframe>' +
      '<iframe src="https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?rel=0"></iframe>' +
      '<figure><iframe src="https://open.spotify.com/embed/track/4uLU6hMCjMI75M1A2tKUQC"></iframe><figcaption>Song</figcaption></figure>' +
      '<iframe src="https://ads.example.com/frame"></iframe><p>B</p>', 'A Song B')
    assert.deepEqual(blocksOf(saved), ['paragraph', 'embed', 'embed', 'embed', 'paragraph'])
    const urls = [...saved.matchAll(/<!-- wp:embed \{"url":"([^"]+)","type":"(\w+)","providerNameSlug":"(\w+)"/g)].map(m => m.slice(1).join(' '))
    assert.deepEqual(urls, [
      'https://vimeo.com/76979871 video vimeo',
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ video youtube',
      'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC rich spotify',
    ])
    assert.match(saved, /https:\/\/open.spotify.com\/track\/4uLU6hMCjMI75M1A2tKUQC\n<\/div><figcaption>Song<\/figcaption><\/figure>/)
    assert.doesNotMatch(saved, /iframe|ads\.example/)
  })
})

describe('styles a source wrote as preset classes', () => {
  test('colour and size presets become delimiter attributes in core order', () => {
    const saved = pasteHTML('<p>Lead</p><p class="has-primary-color has-accent-background-color has-large-font-size has-text-color has-background">Styled</p>' +
      '<h2 class="has-vivid-red-color has-huge-font-size">Head</h2><ul class="has-luminous-vivid-amber-background-color has-background"><li>one</li></ul>', 'Lead Styled Head one')
    assert.match(saved, /<!-- wp:paragraph \{"backgroundColor":"accent","textColor":"primary","fontSize":"large"\} -->\n<p class="has-primary-color has-accent-background-color has-large-font-size has-text-color has-background">Styled<\/p>/)
    assert.match(saved, /<!-- wp:heading \{"textColor":"vivid-red","fontSize":"huge"\} -->\n<h2 class="has-vivid-red-color has-huge-font-size wp-block-heading">Head<\/h2>/)
    assert.match(saved, /<!-- wp:list \{"backgroundColor":"luminous-vivid-amber"\} -->\n<ul class="has-luminous-vivid-amber-background-color has-background wp-block-list">/)
    assert.deepEqual(problems(saved), [], saved)
  })

  test('the first block pasted into an empty paragraph keeps its attributes and replaces it', () => {
    const saved = pasteHTML('<p class="has-accent-background-color has-background">Styled</p><p>Two</p>', 'Styled Two')
    assert.match(saved, /^<!-- wp:paragraph \{"backgroundColor":"accent"\} -->\n<p class="has-accent-background-color has-background">Styled<\/p>/)
    assert.deepEqual(blocksOf(saved), ['paragraph', 'paragraph'])
    assert.deepEqual(problems(saved), [], saved)
  })

  test('the first block pasted into a paragraph with text still joins it', () => {
    const saved = pasteHTML('<p class="has-accent-background-color has-background">Styled</p><p>Two</p>', 'Styled Two',
      '<!-- wp:paragraph -->\n<p>Start</p>\n<!-- /wp:paragraph -->', ' ')
    assert.match(saved, /^<!-- wp:paragraph -->\n<p>Start Styled<\/p>/)
  })

  test('an inline colour keeps a background, and its own colour only when no preset class names one', () => {
    const saved = pasteHTML('<p>Some <mark style="color:#cf2e2e;font-size:30px" class="has-inline-color">red</mark> and ' +
      '<mark style="background-color:yellow;color:#000" class="has-inline-color has-vivid-red-color">preset</mark>.</p>', 'Some red and preset.')
    assert.match(saved, /<mark style="background-color:rgba\(0, 0, 0, 0\);color:rgb\(207, 46, 46\)" class="has-inline-color">red<\/mark>/)
    assert.match(saved, /<mark style="background-color:yellow" class="has-inline-color has-vivid-red-color">preset<\/mark>/)
  })
})

describe('what a reader never sees', () => {
  test('hidden text is dropped, and a button keeps its label unless it is a copy button', () => {
    const saved = pasteHTML('<p>Visible<span class="screen-reader-text"> one</span><span class="visually-hidden"> two</span>' +
      '<span style="display: none"> three</span><span style="mso-hide:all"> four</span>.</p>' +
      '<p>Version <button>v2.1</button> <button aria-label="Copy to clipboard"><span>⧉</span></button></p>', 'Visible. Version v2.1')
    assert.match(saved, /<p>Visible\.<\/p>/)
    assert.match(saved, /<p>Version v2\.1<\/p>/)
    assert.doesNotMatch(saved, /button|⧉/)
  })

  test("a front-end footnote's back-link is dropped and the note keeps its text", () => {
    footnotesMeta = '[]'
    const saved = pasteHTML('<p>Text<sup data-fn="f1" class="fn"><a href="#f1" id="f1-link">1</a></sup></p>' +
      '<ol class="wp-block-footnotes"><li id="f1">Note. <a href="#f1-link" aria-label="Jump to footnote reference 1">↩︎</a></li></ol>', 'Text1 Note.')
    assert.match(saved, /<!-- wp:footnotes \/-->$/)
    const notes = JSON.parse(footnotesMeta)
    assert.equal(notes.length, 1)
    assert.equal(notes[0].content.trim(), 'Note.')
  })
})

describe('pasted table alignment', () => {
  test("a cell's alignment becomes core's class and data-align, written ahead of scope and colspan", () => {
    const saved = pasteHTML('<p>Lead</p><table><thead><tr><th colspan="2" scope="col" style="text-align:right">H</th></tr></thead>' +
      '<tbody><tr><td align="center">a</td><td><p style="text-align:right">b</p></td></tr></tbody></table>', 'Lead H a b')
    assert.match(saved, /<th class="has-text-align-right" data-align="right" scope="col" colspan="2">H<\/th>/)
    assert.match(saved, /<td class="has-text-align-center" data-align="center">a<\/td><td class="has-text-align-right" data-align="right">b<\/td>/)
    assert.deepEqual(problems(saved), [], saved)
    assert.equal(resaved(saved), saved)
  })
})

describe('Word numbering', () => {
  test('a Word list that starts past one keeps its start number', () => {
    const saved = pasteHTML('<p>Lead</p>' +
      "<p class=MsoListParagraph style='mso-list:l0 level1 lfo1'><span style='mso-list:Ignore'>3.<span>&nbsp;&nbsp;</span></span>Third</p>" +
      "<p class=MsoListParagraph style='mso-list:l0 level1 lfo1'><span style='mso-list:Ignore'>4.<span>&nbsp;&nbsp;</span></span>Fourth</p>", 'Lead 3. Third 4. Fourth')
    assert.match(saved, /<!-- wp:list \{"ordered":true,"start":3\} -->\n<ol start="3" class="wp-block-list"><!-- wp:list-item -->\n<li>Third<\/li>\n<!-- \/wp:list-item -->\n\n<!-- wp:list-item -->\n<li>Fourth<\/li>/)
    assert.deepEqual(problems(saved), [], saved)
  })
})

describe('pasting into a list item, continued', () => {
  const listTarget = '<!-- wp:list -->\n<ul class="wp-block-list"><!-- wp:list-item -->\n<li>Item</li>\n<!-- /wp:list-item --></ul>\n<!-- /wp:list -->'

  test('a single paragraph joins the item it is pasted into', () => {
    const saved = pasteHTML('<p>just <em>this</em></p>', 'just this', listTarget, ' ')
    assert.equal((saved.match(/<li>/g) || []).length, 1)
    assert.match(saved, /<li>Item just <em>this<\/em><\/li>/)
  })

  test("a quote's paragraphs pasted with other blocks become items of their own", () => {
    const saved = pasteHTML('<p>p1</p><blockquote><p>q1</p><p>q2</p></blockquote>', 'p1 q1 q2', listTarget, ' ')
    assert.deepEqual([...saved.matchAll(/<li>([^<]*)<\/li>/g)].map(m => m[1]), ['Item p1', 'q1', 'q2'])
    assert.doesNotMatch(saved, /<blockquote|<li><p>/)
  })

  const items = saved => [...saved.matchAll(/<li>([^<]*)<\/li>/g)].map(m => m[1])

  test('a quote pasted on its own becomes items too', () => {
    const saved = pasteHTML('<blockquote><p>q1</p><p>q2</p></blockquote>', 'q1 q2', listTarget, ' ')
    assert.deepEqual(items(saved), ['Item q1', 'q2'])
    assert.doesNotMatch(saved, /<blockquote|<li><p>/)
  })

  test("a quote's citation, bare text, headings and lists all survive as items", () => {
    assert.deepEqual(items(pasteHTML('<p>Intro</p><blockquote><p>Quoted</p><cite>Author Name</cite></blockquote>', 'Intro Quoted Author Name', listTarget, ' ')),
      ['Item Intro', 'Quoted', 'Author Name'])
    assert.deepEqual(items(pasteHTML('<p>Intro</p><blockquote>Bare quoted text</blockquote>', 'Intro Bare quoted text', listTarget, ' ')),
      ['Item Intro', 'Bare quoted text'])
    assert.deepEqual(items(pasteHTML('<p>Intro</p><blockquote><h3>Head</h3><ul><li>a</li><li>b</li></ul></blockquote>', 'Intro Head a b', listTarget, ' ')),
      ['Item Intro', 'Head', 'a', 'b'])
  })
})
