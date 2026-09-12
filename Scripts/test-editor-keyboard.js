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

describe('image marked as decorative (WP 7.1)', () => {
  before(() => {
    // Absorb the pre-existing one-shot setContent quirk documented on the
    // 'image link-to-full-size' block above.
    editor.commands.setContent('<p></p>', false)
  })

  test('role="none" on the <img> parses into imgRole and round-trips', () => {
    // Real WP 7.1 save() output: "Mark as decorative" emits role="none" and alt="".
    const html = '<figure class="wp-block-image size-large"><img src="http://x/p.jpg" alt="" class="wp-image-99" role="none"><figcaption></figcaption></figure>'
    editor.commands.setContent(html, false)
    const node = editor.state.doc.firstChild
    assert.equal(node.type.name, 'image')
    assert.equal(node.attrs.imgRole, 'none')
    const out = editor.getHTML()
    assert.match(out, /<img[^>]*role="none"/)
  })

  test('role survives the toWordPressHTML save transform', () => {
    const html = '<figure class="wp-block-image size-large"><img src="http://x/p.jpg" alt="" class="wp-image-99" role="none"><figcaption></figcaption></figure>'
    editor.commands.setContent(html, false)
    const out = win.toWordPressHTML(editor.getHTML())
    const doc = new JSDOM('<body>' + out + '</body>').window.document
    const img = doc.querySelector('figure.wp-block-image img')
    assert.ok(img, 'the image figure survived')
    assert.equal(img.getAttribute('role'), 'none')
    assert.equal(img.getAttribute('alt'), '')
    assert.ok(img.classList.contains('wp-image-99'))
  })

  test('an image with no role attribute emits no role on save', () => {
    const html = '<figure class="wp-block-image"><img src="http://x/p.jpg" alt="A cat"><figcaption></figcaption></figure>'
    editor.commands.setContent(html, false)
    assert.equal(editor.state.doc.firstChild.attrs.imgRole, null)
    const out = win.toWordPressHTML(editor.getHTML())
    assert.doesNotMatch(out, /role=/)
  })

  test('role is preserved on a classic linked image with no figure wrapper', () => {
    // The bare img[src] parse rule has no getAttrs, so imgRole must come from
    // its own per-attribute parseHTML fallback.
    editor.commands.setContent('<p><img src="http://x/p.jpg" alt="" role="presentation"></p>', false)
    const imgs = []
    editor.state.doc.descendants(n => { if (n.type.name === 'image') imgs.push(n) })
    assert.equal(imgs.length, 1)
    assert.equal(imgs[0].attrs.imgRole, 'presentation')
    assert.match(editor.getHTML(), /role="presentation"/)
  })

  test('a classic bare img keeps its role through the save transform', () => {
    // The getHTML() assertion above stops short of the save path; role must
    // land on the <img> of the figure toWordPressHTML promotes it into, not
    // on the figure it just created.
    editor.commands.setContent('<p><img src="http://x/p.jpg" alt="" role="presentation"></p>', false)
    const out = win.toWordPressHTML(editor.getHTML())
    const doc = new JSDOM('<body>' + out + '</body>').window.document
    const fig = doc.querySelector('figure.wp-block-image')
    assert.ok(fig, 'promoted to a Gutenberg image figure')
    assert.ok(!fig.hasAttribute('role'), 'role stays on the img, not the figure')
    assert.equal(fig.querySelector(':scope > img').getAttribute('role'), 'presentation')
  })

  test('role stays on the img when the image also links to its full size', () => {
    // renderHTML nests the img inside an <a> for linkTo: 'media'. The role is
    // an image semantic, so it must not migrate onto the anchor.
    const html = '<figure class="wp-block-image size-large">' +
      '<a href="http://x/p-full.jpg"><img src="http://x/p.jpg" alt="" class="wp-image-99" role="none"></a>' +
      '<figcaption></figcaption></figure>'
    editor.commands.setContent(html, false)
    const node = editor.state.doc.firstChild
    assert.equal(node.attrs.imgRole, 'none')
    assert.equal(node.attrs.linkTo, 'media')

    const out = win.toWordPressHTML(editor.getHTML())
    const doc = new JSDOM('<body>' + out + '</body>').window.document
    const a = doc.querySelector('figure.wp-block-image > a')
    assert.ok(a, 'the link wrapper survived')
    assert.equal(a.getAttribute('href'), 'http://x/p-full.jpg')
    assert.ok(!a.hasAttribute('role'), 'role did not migrate onto the anchor')
    const img = a.querySelector(':scope > img')
    assert.ok(img, 'the img is still nested inside the anchor')
    assert.equal(img.getAttribute('role'), 'none')
  })

  test('an empty role attribute is dropped rather than emitted as role=""', () => {
    // Mirrors the empty-href handling for linkHref: '' is falsy, so imgRole
    // parses to null and nothing is written back.
    const html = '<figure class="wp-block-image"><img src="http://x/p.jpg" alt="" role=""><figcaption></figcaption></figure>'
    editor.commands.setContent(html, false)
    assert.equal(editor.state.doc.firstChild.attrs.imgRole, null)
    assert.doesNotMatch(win.toWordPressHTML(editor.getHTML()), /role=/)
  })
})

describe('window.insertImage cursor placement', () => {
  before(() => { editor.commands.setContent('<p></p>', false) })

  function selParent() { return editor.state.selection.$from.parent.type.name }

  test('inserting into an empty document leaves the cursor in a paragraph below', () => {
    editor.commands.setContent('<p></p>', false)
    editor.commands.focus()
    win.insertImage('http://x/p.jpg', 800, 600, 42, 'alt text')
    assert.equal(doc(), 'image[] | paragraph()')
    assert.equal(selParent(), 'paragraph')
  })

  test('inserting after existing text appends the paragraph after the image', () => {
    editor.commands.setContent('<p>hello</p>', false)
    editor.commands.setTextSelection(6)
    editor.commands.focus()
    win.insertImage('http://x/p.jpg')
    assert.equal(doc(), 'paragraph("hello") | image[] | paragraph()')
    assert.equal(selParent(), 'paragraph')
  })

  test('the caption is left empty and still holds the image attrs', () => {
    editor.commands.setContent('<p></p>', false)
    editor.commands.focus()
    win.insertImage('http://x/p.jpg', 800, 600, 42, 'alt text')
    const img = editor.state.doc.firstChild
    assert.equal(img.type.name, 'image')
    assert.equal(img.content.size, 0)
    assert.equal(img.attrs.src, 'http://x/p.jpg')
    assert.equal(img.attrs.mediaId, 42)
    assert.equal(img.attrs.alt, 'alt text')
  })

  test('three consecutive inserts stack in order with one trailing paragraph', () => {
    // The real multi-file drop path: PostEditorView posts one .insertMediaURL
    // per uploaded file, so insertImage runs back to back. Each call must land
    // in the paragraph the previous call created, not stack blank paragraphs.
    editor.commands.setContent('<p></p>', false)
    editor.commands.focus()
    win.insertImage('http://x/a.jpg', 100, 50, 1)
    win.insertImage('http://x/b.jpg', 100, 50, 2)
    win.insertImage('http://x/c.jpg', 100, 50, 3)
    assert.equal(doc(), 'image[] | image[] | image[] | paragraph()')
    const srcs = []
    editor.state.doc.descendants(n => { if (n.type.name === 'image') srcs.push(n.attrs.src) })
    assert.deepEqual(srcs, ['http://x/a.jpg', 'http://x/b.jpg', 'http://x/c.jpg'])
    assert.equal(selParent(), 'paragraph')
  })

  test('a multi-image drop saves one wp:image pair per image, in drop order', () => {
    editor.commands.setContent('<p></p>', false)
    editor.commands.focus()
    win.insertImage('http://x/a.jpg', 100, 50, 1)
    win.insertImage('http://x/b.jpg', 100, 50, 2)
    const out = win.toWordPressHTML(editor.getHTML())
    const ids = [...out.matchAll(/<!-- wp:image \{"id":(\d+)\} -->/g)].map(m => m[1])
    assert.deepEqual(ids, ['1', '2'])
    assert.equal((out.match(/<!-- \/wp:image -->/g) || []).length, 2)
    // No blank paragraph wedged between the two figures by the cursor move.
    assert.doesNotMatch(out, /<!-- \/wp:image -->\s*<p><\/p>\s*<!-- wp:image/)
    assert.equal(out, win.toWordPressHTML(out), 'save transform is idempotent')
  })

  test('the saved figure carries no caption and no empty paragraph', () => {
    editor.commands.setContent('<p>before</p>', false)
    editor.commands.focus('end')
    win.insertImage('http://x/r.jpg', 800, 600, 42, 'alt text')
    const out = win.toWordPressHTML(editor.getHTML())
    const figure = out.match(/<figure class="wp-block-image">[\s\S]*?<\/figure>/)[0]
    assert.doesNotMatch(figure, /<figcaption/)
    assert.doesNotMatch(figure, /<p>/)
    assert.match(figure, /<img src="http:\/\/x\/r\.jpg"/)
    // The new paragraph is a sibling after the block, not part of it.
    assert.match(out, /<!-- \/wp:image --><!-- wp:paragraph -->\n<p><\/p>\n<!-- \/wp:paragraph -->$/)
  })

  test('the paragraph below the image accepts typing', () => {
    editor.commands.setContent('<p>before</p>', false)
    editor.commands.focus('end')
    win.insertImage('http://x/r.jpg')
    editor.commands.insertContent('typed')
    assert.equal(doc(), 'paragraph("before") | image[] | paragraph("typed")')
  })

  test('inserting with the cursor in an existing caption appends below, leaving the caption intact', () => {
    editor.commands.setContent('<figure class="wp-block-image"><img src="http://x/o.jpg"><figcaption>cap</figcaption></figure>', false)
    editor.commands.focus('end')
    win.insertImage('http://x/n.jpg')
    assert.equal(doc(), 'image["cap"] | image[] | paragraph()')
    assert.equal(selParent(), 'paragraph')
  })

  test('inserting while an image node is selected replaces it and still lands below', () => {
    editor.commands.setContent('<p>a</p><figure class="wp-block-image"><img src="http://x/old.jpg"></figure><p>b</p>', false)
    editor.commands.setNodeSelection(posOfFirst('image'))
    win.insertImage('http://x/new.jpg')
    assert.equal(doc(), 'paragraph("a") | image[] | paragraph() | paragraph("b")')
    const srcs = []
    editor.state.doc.descendants(n => { if (n.type.name === 'image') srcs.push(n.attrs.src) })
    assert.deepEqual(srcs, ['http://x/new.jpg'])
    assert.equal(selParent(), 'paragraph')
  })

  test('inside a list item the image and its paragraph stay in the item', () => {
    editor.commands.setContent('<ul><li><p>one</p></li></ul>', false)
    editor.commands.focus('end')
    win.insertImage('http://x/l.jpg')
    assert.equal(doc(), 'bulletList(listItem(paragraph("one"),image[],paragraph()))')
    const out = win.toWordPressHTML(editor.getHTML())
    assert.match(out, /<li><p>one<\/p><!-- wp:image -->[\s\S]*<\/figure>\s*<!-- \/wp:image --><p><\/p><\/li>/)
  })

  test('inside a blockquote the image and its paragraph stay in the quote', () => {
    editor.commands.setContent('<blockquote><p>quoted</p></blockquote>', false)
    editor.commands.focus('end')
    win.insertImage('http://x/q.jpg')
    assert.equal(doc(), 'blockquote(paragraph("quoted"),image[],paragraph())')
    const out = win.toWordPressHTML(editor.getHTML())
    assert.match(out, /<blockquote class="wp-block-quote">[\s\S]*<figure class="wp-block-image">[\s\S]*<\/blockquote>/)
  })

  test('inside a table cell the image and its paragraph stay in that cell', () => {
    editor.commands.setContent('<table><tbody><tr><td><p>cell</p></td><td><p>b</p></td></tr></tbody></table>', false)
    editor.commands.focus('end')
    win.insertImage('http://x/t.jpg')
    assert.equal(doc(), 'table(tableRow(tableCell(paragraph("cell")),tableCell(paragraph("b"),image[],paragraph())))')
    assert.equal(selParent(), 'paragraph')
  })

  test('from a code block the image lands after the block, leaving the code untouched', () => {
    editor.commands.setContent('<pre><code>let x = 1</code></pre>', false)
    editor.commands.focus('end')
    win.insertImage('http://x/c2.jpg')
    assert.equal(doc(), 'codeBlock("let x = 1") | image[] | paragraph()')
    assert.equal(selParent(), 'paragraph')
    const out = win.toWordPressHTML(editor.getHTML())
    assert.match(out, /<pre class="wp-block-code"><code>let x = 1<\/code><\/pre>/)
  })

  test('inside a footnote the insert is refused and the document is unchanged', () => {
    editor.commands.setContent('<p>text</p>', false)
    editor.commands.focus('end')
    win.insertFootnote()
    const before = doc()
    assert.equal(win.isInFootnote(), true)
    win.insertImage('http://x/f.jpg')
    assert.equal(doc(), before)
    let hasImage = false
    editor.state.doc.descendants(n => { if (n.type.name === 'image') hasImage = true })
    assert.equal(hasImage, false)
  })
})
