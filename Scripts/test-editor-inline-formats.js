'use strict'

// Live Tiptap tests for inline formats Quill has no toolbar control for —
// loads the REAL editor.html in jsdom, because the preserve path crosses
// setContent, a mark's parse rule and getContent, none of which the pure
// editor-transforms.js helpers reach.

const { test, describe, before, after } = require('node:test')
const assert = require('node:assert/strict')
const { JSDOM, VirtualConsole } = require('jsdom')
const fs = require('fs')
const path = require('path')
const nodeCrypto = require('crypto')

const htmlPath = path.resolve(__dirname, '../Sources/QuillKit/Resources/editor.html')
const fixturePath = path.resolve(__dirname, 'fixtures/inline-formats.html')

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

// Loads src, makes a visual edit in the first paragraph, returns what Quill saves.
const editAndSave = src => {
  win.setContent(src)
  editor.commands.setTextSelection(1)
  editor.commands.insertContent('X')
  return win.getContent()
}

describe('inline formats Quill has no control for survive an edit', () => {
  test('superscript survives', () => {
    const out = editAndSave('<!-- wp:paragraph -->\n<p>The 1<sup>st</sup> one.</p>\n<!-- /wp:paragraph -->')
    assert.match(out, /1<sup>st<\/sup> one\./)
  })

  test('subscript survives', () => {
    const out = editAndSave('<!-- wp:paragraph -->\n<p>Water is H<sub>2</sub>O.</p>\n<!-- /wp:paragraph -->')
    assert.match(out, /H<sub>2<\/sub>O\./)
  })

  test('keyboard input survives', () => {
    const out = editAndSave('<!-- wp:paragraph -->\n<p>Press <kbd>Cmd+S</kbd> now.</p>\n<!-- /wp:paragraph -->')
    assert.match(out, /<kbd>Cmd\+S<\/kbd>/)
  })

  test('highlight survives with its colour class', () => {
    const src = '<!-- wp:paragraph -->\n<p>A <mark style="background-color:rgba(0,0,0,0);color:#cf2e2e" class="has-inline-color has-vivid-red-color">red</mark> word.</p>\n<!-- /wp:paragraph -->'
    const out = editAndSave(src)
    assert.match(out, /<mark[^>]*>red<\/mark>/)
    assert.match(out, /has-vivid-red-color/)
    // the DOM re-serialises style values, so assert the colour, not its spelling
    assert.match(out, /#cf2e2e|rgb\(207, ?46, ?46\)/)
  })

  test('an abbreviation keeps its title attribute', () => {
    const src = '<!-- wp:paragraph -->\n<p>An <abbr title="HyperText Markup Language">HTML</abbr> tag.</p>\n<!-- /wp:paragraph -->'
    const out = editAndSave(src)
    assert.match(out, /<abbr title="HyperText Markup Language">HTML<\/abbr>/)
  })
})

describe('span-based formats survive an edit', () => {
  test("core/language's lang and dir attributes survive", () => {
    const src = '<!-- wp:paragraph -->\n<p>She said <span lang="fr" dir="ltr">bonjour</span> once.</p>\n<!-- /wp:paragraph -->'
    const out = editAndSave(src)
    assert.match(out, /<span lang="fr" dir="ltr">bonjour<\/span>/)
  })

  test("a third-party format's class survives", () => {
    const src = '<!-- wp:paragraph -->\n<p>A <span class="pluginfmt-glow">glowing</span> word.</p>\n<!-- /wp:paragraph -->'
    const out = editAndSave(src)
    assert.match(out, /<span class="pluginfmt-glow">glowing<\/span>/)
  })

  test('an underline span is not double-wrapped', () => {
    const src = '<!-- wp:paragraph -->\n<p>An <span style="text-decoration: underline;">underlined</span> phrase.</p>\n<!-- /wp:paragraph -->'
    const out = editAndSave(src)
    assert.doesNotMatch(out, /<span[^>]*><span/)
  })

  test('a bare span with no attributes adds no markup', () => {
    const out = editAndSave('<!-- wp:paragraph -->\n<p>Just <span>plain</span> words.</p>\n<!-- /wp:paragraph -->')
    assert.match(out, /Just plain words\./)
  })
})

describe('underline saves the markup Gutenberg wrote', () => {
  test("Gutenberg's underline span is not rewritten to <u>", () => {
    const src = '<!-- wp:paragraph -->\n<p>An <span style="text-decoration: underline;">underlined</span> phrase.</p>\n<!-- /wp:paragraph -->'
    const out = editAndSave(src)
    assert.doesNotMatch(out, /<u>/)
    assert.match(out, /<span style="text-decoration: ?underline;?">underlined<\/span>/)
  })

  test('the underline button still produces core markup', () => {
    win.setContent('<!-- wp:paragraph -->\n<p>Plain words here.</p>\n<!-- /wp:paragraph -->')
    editor.commands.setTextSelection({ from: 1, to: 6 })
    editor.commands.toggleUnderline()
    assert.match(win.getContent(), /<span style="text-decoration: ?underline;?">Plain<\/span>/)
  })
})

describe('the preserve rule does not steal what Quill already models', () => {
  test('a footnote marker still parses as a footnoteMarker node', () => {
    win.setContent('<!-- wp:paragraph -->\n<p>Cited<sup class="fn" data-fn="abc"><a href="#abc"></a></sup>.</p>\n<!-- /wp:paragraph -->')
    const names = []
    editor.state.doc.descendants(n => { names.push(n.type.name) })
    assert.ok(names.includes('footnoteMarker'), 'expected a footnoteMarker node, got: ' + names.join(', '))
  })

  test('a blockquote cite still parses as a cite node', () => {
    win.setContent('<!-- wp:quote -->\n<blockquote class="wp-block-quote"><!-- wp:paragraph -->\n<p>Said it.</p>\n<!-- /wp:paragraph --><cite>Someone</cite></blockquote>\n<!-- /wp:quote -->')
    const names = []
    editor.state.doc.descendants(n => { names.push(n.type.name) })
    assert.ok(names.includes('cite'), 'expected a cite node, got: ' + names.join(', '))
  })

  test('bold, italic, strike, code and links are untouched', () => {
    const src = '<!-- wp:paragraph -->\n<p>a <strong>b</strong> <em>c</em> <s>d</s> <code>e</code> <a href="https://example.com">f</a></p>\n<!-- /wp:paragraph -->'
    const out = editAndSave(src)
    assert.match(out, /<strong>b<\/strong> <em>c<\/em> <s>d<\/s> <code>e<\/code> <a href="https:\/\/example\.com">f<\/a>/)
  })
})

describe('the inline-formats fixture', () => {
  const src = () => fs.readFileSync(fixturePath, 'utf8')

  test('round-trips byte-identically with no edit', () => {
    win.setContent(src())
    assert.equal(win.getContent(), src())
  })

  test('keeps every format after an edit', () => {
    const out = editAndSave(src())
    for (const re of [/<sub>2<\/sub>/, /<sup>st<\/sup>/, /<kbd>Cmd\+S<\/kbd>/, /<mark[^>]*>important<\/mark>/, /<abbr title="HyperText Markup Language">HTML<\/abbr>/]) {
      assert.match(out, re)
    }
    assert.doesNotMatch(out, /<u>/)
  })
})
