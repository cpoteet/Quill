'use strict'

// Live keyboard-handler tests for the Tiptap editor.
//
// Unlike test-editor.js (which exercises the pure editor-transforms.js helpers),
// this suite loads the REAL Sources/QuillKit/Resources/editor.html inside jsdom,
// instantiates the live editor, dispatches actual keydown events, and asserts on
// the resulting ProseMirror document. This is the only automated coverage of the
// Enter/Backspace/Shift-Enter handlers — the exact code paths that produced a
// chain of regressions in June 2026 (the fn()-no-args keymap crash in 941114d,
// the footnote Backspace swallow in daee820, the footnote-Enter text loss fixed
// in cbf3e8d, and the image-caption-Enter misplacement fixed in 91679d2).
//
// jsdom caveat: ProseMirror only keymap-binds Backspace at NODE BOUNDARIES
// (joinBackward / lift). Mid-text character deletion is the browser's native
// beforeinput handling, which jsdom does not emit — so only boundary Backspace is
// asserted here.

const { test, describe, before, after } = require('node:test')
const assert = require('node:assert/strict')
const { JSDOM, VirtualConsole } = require('jsdom')
const fs = require('fs')
const path = require('path')
const nodeCrypto = require('crypto')

const htmlPath = path.resolve(__dirname, '../Sources/QuillKit/Resources/editor.html')

let editor
let win

function key(view, k, mods = {}) {
  const code = { Enter: 13, Backspace: 8, Delete: 46 }
  const ev = new win.KeyboardEvent('keydown', {
    key: k, code: k, keyCode: code[k] || 0, which: code[k] || 0,
    bubbles: true, cancelable: true,
    shiftKey: !!mods.shift, metaKey: !!mods.meta, ctrlKey: !!mods.ctrl,
  })
  view.dom.dispatchEvent(ev)
}

// Compact, readable structural summary of a ProseMirror JSON doc.
function summarize(json) {
  function walk(n) {
    if (n.type === 'text') return JSON.stringify(n.text)
    if (n.type === 'hardBreak') return 'BR'
    if (n.type === 'footnoteMarker') return 'MARKER'
    if (n.type === 'image') return 'image[' + (n.content || []).map(walk).join(',') + ']'
    return n.type + '(' + (n.content || []).map(walk).join(',') + ')'
  }
  return (json.content || []).map(walk).join(' | ')
}

function doc() { return summarize(editor.getJSON()) }

function posOfFirst(typeName) {
  let found = null
  editor.state.doc.descendants((n, pos) => { if (found === null && n.type.name === typeName) found = pos })
  return found
}

function paragraphStarts() {
  const out = []
  editor.state.doc.descendants((n, pos) => { if (n.type.name === 'paragraph') out.push(pos + 1) })
  return out
}

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

  // Polyfills the editor / ProseMirror touch but jsdom lacks.
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

describe('plain paragraphs', () => {
  test('Enter at end of paragraph creates an empty paragraph below', () => {
    editor.commands.setContent('<p>hello</p>')
    editor.commands.focus('end')
    key(editor.view, 'Enter')
    assert.equal(doc(), 'paragraph("hello") | paragraph()')
  })

  test('Enter mid-word splits the paragraph cleanly', () => {
    editor.commands.setContent('<p>hello</p>')
    editor.commands.setTextSelection(4) // after "hel"
    key(editor.view, 'Enter')
    assert.equal(doc(), 'paragraph("hel") | paragraph("lo")')
  })

  test('Backspace at start of 2nd paragraph merges into the first (joinBackward)', () => {
    editor.commands.setContent('<p>foo</p><p>bar</p>')
    editor.commands.setTextSelection(paragraphStarts()[1])
    key(editor.view, 'Backspace')
    assert.equal(doc(), 'paragraph("foobar")')
  })

  test('Shift+Enter inserts a hard break, not a new paragraph', () => {
    editor.commands.setContent('<p>line</p>')
    editor.commands.focus('end')
    key(editor.view, 'Enter', { shift: true })
    assert.equal(doc(), 'paragraph("line",BR)')
  })
})

describe('headings', () => {
  test('Enter at end of a heading drops to a paragraph (not another heading)', () => {
    editor.commands.setContent('<h2>Title</h2>')
    editor.commands.focus('end')
    key(editor.view, 'Enter')
    assert.equal(doc(), 'heading("Title") | paragraph()')
  })
})

describe('lists', () => {
  test('Enter at end of a list item creates a new item', () => {
    editor.commands.setContent('<ul><li><p>one</p></li></ul>')
    editor.commands.focus('end')
    key(editor.view, 'Enter')
    assert.equal(doc(), 'bulletList(listItem(paragraph("one")),listItem(paragraph()))')
  })

  test('Enter in an empty trailing item exits the list', () => {
    editor.commands.setContent('<ul><li><p>one</p></li><li><p></p></li></ul>')
    const starts = paragraphStarts()
    editor.commands.setTextSelection(starts[starts.length - 1])
    key(editor.view, 'Enter')
    assert.equal(doc(), 'bulletList(listItem(paragraph("one"))) | paragraph()')
  })

  test('Backspace at start of the sole list item lifts it to a paragraph', () => {
    editor.commands.setContent('<ul><li><p>only</p></li></ul>')
    editor.commands.setTextSelection(posOfFirst('paragraph') + 1)
    key(editor.view, 'Backspace')
    assert.equal(doc(), 'paragraph("only")')
  })
})

describe('blockquotes & cite', () => {
  test('Enter in a blockquote creates a paragraph inside the quote', () => {
    editor.commands.setContent('<blockquote><p>quoted</p></blockquote>')
    editor.commands.focus('end')
    key(editor.view, 'Enter')
    assert.equal(doc(), 'blockquote(paragraph("quoted"),paragraph())')
  })

  test('Enter on an empty paragraph inside a blockquote lifts out', () => {
    editor.commands.setContent('<blockquote><p>q</p><p></p></blockquote>')
    const starts = paragraphStarts()
    editor.commands.setTextSelection(starts[starts.length - 1])
    key(editor.view, 'Enter')
    assert.equal(doc(), 'blockquote(paragraph("q")) | paragraph()')
  })

  test('Enter with a selection deletes it before splitting (regression: 8a4f00f)', () => {
    editor.commands.setContent('<blockquote><p>abcdef</p></blockquote>')
    const p = posOfFirst('paragraph')
    editor.commands.setTextSelection({ from: p + 3, to: p + 5 }) // select "cd"
    key(editor.view, 'Enter')
    assert.equal(doc(), 'blockquote(paragraph("ab"),paragraph("ef"))')
  })

  test('Enter inside a cite exits the blockquote to a new paragraph', () => {
    editor.commands.setContent('<blockquote><p>q</p><cite>src</cite></blockquote>')
    const citePos = posOfFirst('cite')
    assert.notEqual(citePos, null, 'cite should parse')
    editor.commands.setTextSelection(citePos + 1)
    editor.commands.focus()
    key(editor.view, 'Enter')
    assert.equal(doc(), 'blockquote(paragraph("q"),cite("src")) | paragraph()')
  })
})

describe('footnotes', () => {
  test('Enter in a footnote entry inserts a soft break and keeps text (regression: cbf3e8d)', () => {
    editor.commands.setContent('<p>body</p>')
    editor.commands.focus('end')
    win.insertFootnote()
    editor.commands.insertContent('note')
    key(editor.view, 'Enter')
    editor.commands.insertContent('more')
    let fl = null
    editor.state.doc.descendants(n => { if (n.type.name === 'footnotesList') fl = n })
    assert.notEqual(fl, null, 'footnotes list should exist')
    assert.equal(summarize({ content: [fl.toJSON()] }), 'footnotesList(footnoteItem("note",BR,"more"))')
  })

  test('Backspace at the start of a footnote entry does not corrupt the doc (regression: daee820)', () => {
    editor.commands.setContent('<p>body</p>')
    editor.commands.focus('end')
    win.insertFootnote()
    editor.commands.insertContent('x')
    editor.commands.setTextSelection(posOfFirst('footnoteItem') + 1)
    key(editor.view, 'Backspace')
    assert.equal(doc(), 'paragraph("body",MARKER) | footnotesList(footnoteItem("x"))')
  })
})

describe('image captions', () => {
  test('Enter in an image caption exits to a new paragraph below (regression: 91679d2)', () => {
    editor.commands.setContent('<figure class="wp-block-image"><img src="x.png"><figcaption>cap</figcaption></figure>')
    editor.commands.setTextSelection(posOfFirst('image') + 1)
    editor.commands.focus()
    key(editor.view, 'Enter')
    assert.equal(doc(), 'image["cap"] | paragraph()')
  })

  test('Enter in an image caption inside a blockquote stays well-formed (no image duplication)', () => {
    editor.commands.setContent('<blockquote><figure class="wp-block-image"><img src="x.png"><figcaption>cap</figcaption></figure></blockquote>')
    const imgPos = posOfFirst('image')
    assert.notEqual(imgPos, null, 'image should parse inside blockquote')
    editor.commands.setTextSelection(imgPos + 1)
    editor.commands.focus()
    key(editor.view, 'Enter')
    assert.equal(doc(), 'blockquote(image["cap"],paragraph())')
  })
})

describe('class preservation through schema round-trip', () => {
  function htmlRoundTrip(html) {
    editor.commands.setContent(html, false)
    return editor.getHTML()
  }

  test('custom class on paragraph survives setContent/getHTML round-trip', () => {
    const out = htmlRoundTrip('<p class="my-custom">hello</p>')
    assert.match(out, /class="my-custom"/)
  })

  test('custom class on heading survives round-trip', () => {
    const out = htmlRoundTrip('<h2 class="my-heading-style">title</h2>')
    assert.match(out, /my-heading-style/)
  })

  test('custom class on image figure survives round-trip', () => {
    const out = htmlRoundTrip('<figure class="wp-block-image size-large my-figure-class"><img src="x.png"><figcaption></figcaption></figure>')
    assert.match(out, /my-figure-class/)
  })

  test('custom id on image figure survives round-trip', () => {
    const out = htmlRoundTrip('<figure class="wp-block-image" id="hero-img"><img src="x.png"><figcaption></figcaption></figure>')
    assert.match(out, /id="hero-img"/)
  })

  test('custom class on code block survives round-trip', () => {
    const out = htmlRoundTrip('<pre class="language-js"><code>const x = 1</code></pre>')
    assert.match(out, /language-js/)
  })

  test('custom class on list survives round-trip', () => {
    const out = htmlRoundTrip('<ul class="custom-list"><li><p>item</p></li></ul>')
    assert.match(out, /custom-list/)
  })

  test('custom class on blockquote survives round-trip', () => {
    const out = htmlRoundTrip('<blockquote class="pullquote"><p>quote</p></blockquote>')
    assert.match(out, /pullquote/)
  })

  test('custom class on table element survives round-trip', () => {
    const out = htmlRoundTrip('<table class="striped"><tbody><tr><td><p>cell</p></td></tr></tbody></table>')
    assert.match(out, /striped/)
  })

  test('wp-block-image class on figure is filtered from figureClass (not duplicated)', () => {
    editor.commands.setContent('<figure class="wp-block-image aligncenter size-large my-class"><img src="x.png"><figcaption></figcaption></figure>', false)
    const node = editor.state.doc.firstChild
    assert.equal(node.attrs.figureClass, 'size-large my-class')
    assert.equal(node.attrs.alignment, 'center')
  })

  test('custom class on img element survives round-trip', () => {
    const out = htmlRoundTrip('<figure class="wp-block-image"><img src="x.png" class="my-img-style wp-image-123 aligncenter"><figcaption></figcaption></figure>')
    assert.match(out, /my-img-style/)
  })

  test('managed img classes (alignment, wp-image) are not duplicated in imgClass', () => {
    editor.commands.setContent('<figure class="wp-block-image aligncenter"><img src="x.png" class="wp-image-99 custom"><figcaption></figcaption></figure>', false)
    const node = editor.state.doc.firstChild
    assert.equal(node.attrs.imgClass, 'custom')
    assert.equal(node.attrs.alignment, 'center')
    assert.equal(node.attrs.mediaId, 99)
  })

  test('custom class on cite survives round-trip', () => {
    const out = htmlRoundTrip('<blockquote><p>quote</p><cite class="author-name">Someone</cite></blockquote>')
    assert.match(out, /author-name/)
  })

  test('custom class on link survives round-trip', () => {
    const out = htmlRoundTrip('<p><a href="https://example.com" class="btn cta">Click</a></p>')
    assert.match(out, /btn/)
    assert.match(out, /cta/)
  })

  test('custom class is not copied to new node on Enter (keepOnSplit)', () => {
    editor.commands.setContent('<h2 class="section-title">Title</h2>')
    editor.commands.focus('end')
    key(editor.view, 'Enter')
    const out = editor.getHTML()
    assert.match(out, /section-title/)
    const paragraphs = out.match(/<p[^>]*>/g)
    assert.ok(paragraphs.every(p => !p.includes('section-title')), 'new paragraph should not inherit heading class')
  })

  test('applyLink preserves existing link classes', () => {
    editor.commands.setContent('<p><a href="https://old.com" class="btn">Click</a></p>', false)
    editor.commands.setTextSelection(2)
    win.applyLink('https://new.com')
    const out = editor.getHTML()
    assert.match(out, /https:\/\/new\.com/)
    assert.match(out, /btn/)
  })
})

describe('image link-to-full-size', () => {
  before(() => {
    // Pre-existing jsdom/Tiptap quirk (reproduces on main, unrelated to linkTo/linkHref):
    // the first setContent(figureHTML) call immediately after an
    // editor.chain().extendMarkRange('link')...run() that extends over an *existing*
    // link mark silently produces an empty <p></p> instead of parsing the content. The
    // preceding 'applyLink preserves existing link classes' test above exercises exactly
    // that pattern, so absorb the one-shot quirk here before asserting on real content.
    editor.commands.setContent('<p></p>', false)
  })

  test('image wrapped in <a> parses to linkTo media with linkHref, and round-trips', () => {
    const html = '<figure class="wp-block-image"><a href="https://example.com/full.jpg"><img src="https://example.com/thumb.jpg"></a><figcaption></figcaption></figure>'
    editor.commands.setContent(html, false)
    const node = editor.state.doc.firstChild
    assert.equal(node.attrs.linkTo, 'media')
    assert.equal(node.attrs.linkHref, 'https://example.com/full.jpg')
    const out = editor.getHTML()
    assert.match(out, /<a href="https:\/\/example\.com\/full\.jpg"><img[^>]*><\/a>/)
  })

  test('image without a link wrapper defaults to linkTo none and omits <a> from output', () => {
    const html = '<figure class="wp-block-image"><img src="https://example.com/thumb.jpg"><figcaption></figcaption></figure>'
    editor.commands.setContent(html, false)
    const node = editor.state.doc.firstChild
    assert.equal(node.attrs.linkTo, 'none')
    assert.equal(node.attrs.linkHref, null)
    const out = editor.getHTML()
    assert.doesNotMatch(out, /<a /)
  })

  test('linked image preserves alignment, custom class, and mediaId alongside the link', () => {
    const html = '<figure class="wp-block-image alignleft my-figure-class"><a href="https://example.com/full.jpg"><img src="https://example.com/thumb.jpg" class="wp-image-42"></a><figcaption>cap</figcaption></figure>'
    editor.commands.setContent(html, false)
    const node = editor.state.doc.firstChild
    assert.equal(node.attrs.linkTo, 'media')
    assert.equal(node.attrs.linkHref, 'https://example.com/full.jpg')
    assert.equal(node.attrs.alignment, 'left')
    assert.equal(node.attrs.figureClass, 'my-figure-class')
    assert.equal(node.attrs.mediaId, 42)
    const out = editor.getHTML()
    assert.match(out, /alignleft/)
    assert.match(out, /my-figure-class/)
    assert.match(out, /data-media-id="42"/)
    assert.match(out, /<a href="https:\/\/example\.com\/full\.jpg">/)
  })

  test('toggling linkTo to media via setNodeMarkup produces the <a> wrapper on save', () => {
    editor.commands.setContent('<figure class="wp-block-image"><img src="https://example.com/thumb.jpg"><figcaption></figcaption></figure>', false)
    const pos = posOfFirst('image')
    const node = editor.state.doc.nodeAt(pos)
    const { state, dispatch } = editor.view
    dispatch(state.tr.setNodeMarkup(pos, null, { ...node.attrs, linkTo: 'media', linkHref: 'https://example.com/full.jpg' }))
    const out = editor.getHTML()
    assert.match(out, /<a href="https:\/\/example\.com\/full\.jpg">/)
  })

  test('toggling linkTo back to none via setNodeMarkup clears linkHref too', () => {
    editor.commands.setContent('<figure class="wp-block-image"><a href="https://example.com/full.jpg"><img src="https://example.com/thumb.jpg"></a><figcaption></figcaption></figure>', false)
    const pos = posOfFirst('image')
    const node = editor.state.doc.nodeAt(pos)
    assert.equal(node.attrs.linkTo, 'media')
    const { state, dispatch } = editor.view
    dispatch(state.tr.setNodeMarkup(pos, null, { ...node.attrs, linkTo: 'none', linkHref: null }))
    const after = editor.state.doc.nodeAt(pos)
    assert.equal(after.attrs.linkHref, null)
    const out = editor.getHTML()
    assert.doesNotMatch(out, /<a /)
  })

  test('classic (non-figure) linked image is detected via the bare img[src] parse rule', () => {
    const html = '<a href="https://example.com/full.jpg"><img src="https://example.com/thumb.jpg"></a>'
    editor.commands.setContent(html, false)
    const node = editor.state.doc.firstChild
    assert.equal(node.attrs.linkTo, 'media')
    assert.equal(node.attrs.linkHref, 'https://example.com/full.jpg')
    const out = editor.getHTML()
    assert.match(out, /<a href="https:\/\/example\.com\/full\.jpg"><img[^>]*><\/a>/)
  })

  test('an <a> wrapper with an empty href is not treated as a full-image link', () => {
    const html = '<figure class="wp-block-image"><a href=""><img src="https://example.com/thumb.jpg"></a><figcaption></figcaption></figure>'
    editor.commands.setContent(html, false)
    const node = editor.state.doc.firstChild
    assert.equal(node.attrs.linkTo, 'none')
    assert.equal(node.attrs.linkHref, null)
  })
})
