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
