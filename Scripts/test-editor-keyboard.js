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
  const code = { Enter: 13, Escape: 27, Backspace: 8, Delete: 46, ArrowLeft: 37, ArrowRight: 39 }
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
  // ProseMirror's arrow handling measures the caret to find the text direction.
  const rect = { top: 0, left: 0, bottom: 0, right: 0, width: 0, height: 0 }
  for (const proto of [win.Text.prototype, win.Range.prototype]) {
    if (proto.getClientRects) continue
    proto.getClientRects = () => Object.assign([rect], { item: () => rect })
    proto.getBoundingClientRect = () => rect
  }

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

describe('⌘← / ⌘→ beside a card', () => {
  test('⌘→ at the end of a paragraph before a card keeps the caret in the paragraph', () => {
    editor.commands.setContent('<p>hello</p><hr><p>after</p>')
    editor.commands.setTextSelection(6)
    key(editor.view, 'ArrowRight', { meta: true })
    assert.equal(editor.state.selection.node?.type.name, undefined)
    assert.equal(editor.state.selection.head, 6)
  })

  test('⌘← at the start of a paragraph after a card keeps the caret in the paragraph', () => {
    editor.commands.setContent('<p>hello</p><hr><p>after</p>')
    const start = paragraphStarts()[1]
    editor.commands.setTextSelection(start)
    key(editor.view, 'ArrowLeft', { meta: true })
    assert.equal(editor.state.selection.node?.type.name, undefined)
    assert.equal(editor.state.selection.head, start)
  })

  test('a plain → at the end of the paragraph still selects the card', () => {
    editor.commands.setContent('<p>hello</p><hr><p>after</p>')
    editor.commands.setTextSelection(6)
    key(editor.view, 'ArrowRight')
    assert.equal(editor.state.selection.node?.type.name, 'horizontalRule')
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

describe('Tab outside lists and tables', () => {
  function tab(mods = {}) {
    const ev = new win.KeyboardEvent('keydown', { key: 'Tab', code: 'Tab', keyCode: 9, which: 9, bubbles: true, cancelable: true, shiftKey: !!mods.shift })
    editor.view.dom.dispatchEvent(ev)
    return ev
  }

  test('Tab in a paragraph is kept from moving focus and changes nothing', () => {
    editor.commands.setContent('<p>text</p>')
    editor.commands.focus('end')
    assert.equal(tab().defaultPrevented, true)
    assert.equal(doc(), 'paragraph("text")')
  })

  test('Shift-Tab in a paragraph is kept from moving focus and changes nothing', () => {
    editor.commands.setContent('<p>text</p>')
    editor.commands.focus('end')
    assert.equal(tab({ shift: true }).defaultPrevented, true)
    assert.equal(doc(), 'paragraph("text")')
  })

  test('Tab in a code block inserts a tab character', () => {
    editor.commands.setContent('<pre><code>x</code></pre>')
    editor.commands.setTextSelection(posOfFirst('codeBlock') + 1)
    tab()
    assert.equal(doc(), 'codeBlock("\\tx")')
  })

  test('Tab in a preformatted block inserts a tab character', () => {
    editor.commands.setContent('<pre class="wp-block-preformatted">x</pre>')
    editor.commands.setTextSelection(posOfFirst('preformatted') + 1)
    tab()
    assert.equal(doc(), 'preformatted("\\tx")')
  })

  test('Tab in a second list item still nests it', () => {
    editor.commands.setContent('<ul><li><p>one</p></li><li><p>two</p></li></ul>')
    editor.commands.focus('end')
    tab()
    assert.equal(doc(), 'bulletList(listItem(paragraph("one"),bulletList(listItem(paragraph("two")))))')
  })

  test('Tab in a table cell still moves to the next cell', () => {
    editor.commands.setContent('<table><tbody><tr><td><p>a</p></td><td><p>b</p></td></tr></tbody></table>')
    editor.commands.setTextSelection(posOfFirst('paragraph') + 1)
    tab()
    assert.equal(editor.state.selection.$from.parent.textContent, 'b')
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

  test('Enter on an empty paragraph just before the cite leaves the quote below the cite', () => {
    editor.commands.setContent('<blockquote><p>q</p><p></p><cite>src</cite></blockquote>')
    editor.commands.setTextSelection(paragraphStarts()[1])
    key(editor.view, 'Enter')
    assert.equal(doc(), 'blockquote(paragraph("q"),cite("src")) | paragraph()')
    assert.equal(editor.state.selection.$from.depth, 1)
  })

  test('Enter on the only, empty paragraph of a quote with a cite leaves the quote and keeps its line', () => {
    editor.commands.setContent('<blockquote><p></p><cite>src</cite></blockquote>')
    editor.commands.setTextSelection(paragraphStarts()[0])
    key(editor.view, 'Enter')
    assert.equal(doc(), 'blockquote(paragraph(),cite("src")) | paragraph()')
    assert.equal(editor.state.selection.$from.depth, 1)
  })

  test('Enter on an empty paragraph just before a pullquote cite leaves the pullquote below the cite', () => {
    editor.commands.setContent('<figure class="wp-block-pullquote"><blockquote><p>q</p><p></p><cite>src</cite></blockquote></figure>')
    editor.commands.setTextSelection(paragraphStarts()[1])
    key(editor.view, 'Enter')
    assert.equal(doc(), 'pullquote(paragraph("q"),cite("src")) | paragraph()')
    assert.equal(editor.state.selection.$from.depth, 1)
  })

  test('Enter on the only, empty paragraph of a pullquote with a cite leaves it and keeps its line', () => {
    editor.commands.setContent('<figure class="wp-block-pullquote"><blockquote><p></p><cite>src</cite></blockquote></figure>')
    editor.commands.setTextSelection(paragraphStarts()[0])
    key(editor.view, 'Enter')
    assert.equal(doc(), 'pullquote(paragraph(),cite("src")) | paragraph()')
    assert.equal(editor.state.selection.$from.depth, 1)
  })
  // cpoteet/Quill#24 bug 6: the cite's Backspace removed it and left the caret after the quote.
  test('Backspace in an empty cite removes it and leaves the caret at the end of the quote', () => {
    for (const html of ['<blockquote><p>Q</p><cite></cite></blockquote><p>After</p>',
                        '<figure class="wp-block-pullquote"><blockquote><p>Q</p><cite></cite></blockquote></figure><p>After</p>']) {
      editor.commands.setContent(html, { emitUpdate: false })
      editor.commands.setTextSelection(posOfFirst('cite') + 1)
      key(editor.view, 'Backspace')
      editor.view.dispatch(editor.state.tr.insertText('X'))
      assert.equal(doc(), (html.includes('pullquote') ? 'pullquote' : 'blockquote') + '(paragraph("QX")) | paragraph("After")')
    }
  })

  // The join into the quote must not take the place of Backspace's undo of a Markdown rule.
  test('Backspace right after "# " below a quote with a cite undoes the rule', () => {
    editor.commands.setContent('<blockquote><p>Q</p><cite>Who</cite></blockquote><p></p>', { emitUpdate: false })
    let at = null
    editor.state.doc.descendants((n, pos) => { if (n.type.name === 'paragraph' && n.content.size === 0) at = pos + 1 })
    editor.commands.setTextSelection(at)
    for (const ch of '# ') {
      const { from, to } = editor.state.selection
      if (!editor.view.someProp('handleTextInput', f => f(editor.view, from, to, ch))) editor.view.dispatch(editor.state.tr.insertText(ch, from, to))
    }
    const typed = doc()
    key(editor.view, 'Backspace')
    assert.deepEqual([typed, doc()], ['blockquote(paragraph("Q"),cite("Who")) | heading()', 'blockquote(paragraph("Q"),cite("Who")) | paragraph("# ")'])
  })

  // The same issue's mirror cases: a citation's edges never join the quote's text or the next line.
  test('a citation keeps its text at either edge', () => {
    const quote = 'blockquote(paragraph("Q"),cite("Who")) | paragraph("After")'
    const html = '<blockquote><p>Q</p><cite>Who</cite></blockquote><p>After</p>'
    const press = (pos, k) => {
      editor.commands.setContent(html, { emitUpdate: false })
      editor.commands.setTextSelection(pos())
      const ev = new win.KeyboardEvent('keydown', { key: k, code: k, keyCode: k === 'Delete' ? 46 : 8, bubbles: true, cancelable: true })
      editor.view.dom.dispatchEvent(ev)
      return doc() + (ev.defaultPrevented ? '' : ' NOT CONSUMED')
    }
    assert.deepEqual({
      backspaceAtCiteStart: press(() => posOfFirst('cite') + 1, 'Backspace'),
      deleteAtCiteEnd: press(() => posOfFirst('cite') + 4, 'Delete'),
      deleteAtQuoteLineEnd: press(() => posOfFirst('paragraph') + 2, 'Delete'),
    }, { backspaceAtCiteStart: quote, deleteAtCiteEnd: quote, deleteAtQuoteLineEnd: quote })
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
  // cpoteet/Quill#24 bugs 8 and 9: with the wrapper read-only and the caption read-write, every
  // caption was an editing host of its own, so a click there focused the figcaption instead of the
  // editor. ProseMirror's hasFocus() was false, it ignored the caret moves (⌘←, →) and kept a stale
  // selection, and WebKit's own Backspace then ran and dropped the caret. The frame's
  // contenteditable=false is what keeps the image itself uneditable. jsdom does no editing hosts,
  // so this asserts the rule; checked in WebKit on 2026-11-13.
  // With the caption no longer its own editing host, WebKit's arrow keys can park the caret in the
  // wrapper itself, beside the image frame, where ProseMirror reads it as the caption's start or end
  // but the node view ignores what is typed: the text was drawn and never saved. The caret is put
  // back inside the caption. jsdom never moves a caret, so the test places it and fires the event.
  test('a caret WebKit leaves beside the image frame is moved into the caption', () => {
    editor.commands.setContent('<p>Alpha</p><figure class="wp-block-image"><img src="x.png"><figcaption>cap</figcaption></figure><p>Omega</p>', { emitUpdate: false })
    const wrapper = win.document.querySelector('.image-wrapper')
    const caption = wrapper.querySelector('figcaption')
    const place = offset => {
      const range = win.document.createRange()
      range.setStart(wrapper, offset)
      range.collapse(true)
      const sel = win.getSelection()
      sel.removeAllRanges()
      sel.addRange(range)
      win.document.dispatchEvent(new win.Event('selectionchange'))
      const now = win.getSelection()
      const inCaption = caption.contains(now.anchorNode)
      const atEnd = inCaption && now.anchorNode.nodeType === 3 ? now.anchorOffset === now.anchorNode.data.length : now.anchorOffset > 0
      return inCaption ? (atEnd ? 'caption end' : 'caption start') : 'outside the caption'
    }
    assert.deepEqual([place(0), place(1), place(2)], ['caption start', 'caption start', 'caption end'])
  })

  test('a caption is part of the editor, not an editing host of its own', () => {
    const source = fs.readFileSync(htmlPath, 'utf8')
    assert.doesNotMatch(source, /-webkit-user-modify/)
    assert.match(source, /this\.frame\.contentEditable = 'false'/)
  })

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
    editor.commands.setContent(html, { emitUpdate: false })
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
    editor.commands.setContent('<figure class="wp-block-image aligncenter size-large my-class"><img src="x.png"><figcaption></figcaption></figure>', { emitUpdate: false })
    const node = editor.state.doc.firstChild
    assert.equal(node.attrs.figureClass, 'size-large my-class')
    assert.equal(node.attrs.alignment, 'center')
  })

  test('custom class on img element survives round-trip', () => {
    const out = htmlRoundTrip('<figure class="wp-block-image"><img src="x.png" class="my-img-style wp-image-123 aligncenter"><figcaption></figcaption></figure>')
    assert.match(out, /my-img-style/)
  })

  test('managed img classes (alignment, wp-image) are not duplicated in imgClass', () => {
    editor.commands.setContent('<figure class="wp-block-image aligncenter"><img src="x.png" class="wp-image-99 custom"><figcaption></figcaption></figure>', { emitUpdate: false })
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
    editor.commands.setContent('<p><a href="https://old.com" class="btn">Click</a></p>', { emitUpdate: false })
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
    editor.commands.setContent('<p></p>', { emitUpdate: false })
  })

  test('image wrapped in <a> parses to linkTo media with linkHref, and round-trips', () => {
    const html = '<figure class="wp-block-image"><a href="https://example.com/full.jpg"><img src="https://example.com/thumb.jpg"></a><figcaption></figcaption></figure>'
    editor.commands.setContent(html, { emitUpdate: false })
    const node = editor.state.doc.firstChild
    assert.equal(node.attrs.linkTo, 'media')
    assert.equal(node.attrs.linkHref, 'https://example.com/full.jpg')
    const out = editor.getHTML()
    assert.match(out, /<a href="https:\/\/example\.com\/full\.jpg"><img[^>]*><\/a>/)
  })

  test('image without a link wrapper defaults to linkTo none and omits <a> from output', () => {
    const html = '<figure class="wp-block-image"><img src="https://example.com/thumb.jpg"><figcaption></figcaption></figure>'
    editor.commands.setContent(html, { emitUpdate: false })
    const node = editor.state.doc.firstChild
    assert.equal(node.attrs.linkTo, 'none')
    assert.equal(node.attrs.linkHref, null)
    const out = editor.getHTML()
    assert.doesNotMatch(out, /<a /)
  })

  test('linked image preserves alignment, custom class, and mediaId alongside the link', () => {
    const html = '<figure class="wp-block-image alignleft my-figure-class"><a href="https://example.com/full.jpg"><img src="https://example.com/thumb.jpg" class="wp-image-42"></a><figcaption>cap</figcaption></figure>'
    editor.commands.setContent(html, { emitUpdate: false })
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
    editor.commands.setContent('<figure class="wp-block-image"><img src="https://example.com/thumb.jpg"><figcaption></figcaption></figure>', { emitUpdate: false })
    const pos = posOfFirst('image')
    const node = editor.state.doc.nodeAt(pos)
    const { state, dispatch } = editor.view
    dispatch(state.tr.setNodeMarkup(pos, null, { ...node.attrs, linkTo: 'media', linkHref: 'https://example.com/full.jpg' }))
    const out = editor.getHTML()
    assert.match(out, /<a href="https:\/\/example\.com\/full\.jpg">/)
  })

  test('toggling linkTo back to none via setNodeMarkup clears linkHref too', () => {
    editor.commands.setContent('<figure class="wp-block-image"><a href="https://example.com/full.jpg"><img src="https://example.com/thumb.jpg"></a><figcaption></figcaption></figure>', { emitUpdate: false })
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
    editor.commands.setContent(html, { emitUpdate: false })
    const node = editor.state.doc.firstChild
    assert.equal(node.attrs.linkTo, 'media')
    assert.equal(node.attrs.linkHref, 'https://example.com/full.jpg')
    const out = editor.getHTML()
    assert.match(out, /<a href="https:\/\/example\.com\/full\.jpg"><img[^>]*><\/a>/)
  })

  test('an <a> wrapper with an empty href is not treated as a full-image link', () => {
    const html = '<figure class="wp-block-image"><a href=""><img src="https://example.com/thumb.jpg"></a><figcaption></figcaption></figure>'
    editor.commands.setContent(html, { emitUpdate: false })
    const node = editor.state.doc.firstChild
    assert.equal(node.attrs.linkTo, 'none')
    assert.equal(node.attrs.linkHref, null)
  })
})

describe('image marked as decorative (WP 7.1)', () => {
  before(() => {
    // Absorb the pre-existing one-shot setContent quirk documented on the
    // 'image link-to-full-size' block above.
    editor.commands.setContent('<p></p>', { emitUpdate: false })
  })

  test('role="none" on the <img> parses into imgRole and round-trips', () => {
    // Real WP 7.1 save() output: "Mark as decorative" emits role="none" and alt="".
    const html = '<figure class="wp-block-image size-large"><img src="http://x/p.jpg" alt="" class="wp-image-99" role="none"><figcaption></figcaption></figure>'
    editor.commands.setContent(html, { emitUpdate: false })
    const node = editor.state.doc.firstChild
    assert.equal(node.type.name, 'image')
    assert.equal(node.attrs.imgRole, 'none')
    const out = editor.getHTML()
    assert.match(out, /<img[^>]*role="none"/)
  })

  test('role survives the toWordPressHTML save transform', () => {
    const html = '<figure class="wp-block-image size-large"><img src="http://x/p.jpg" alt="" class="wp-image-99" role="none"><figcaption></figcaption></figure>'
    editor.commands.setContent(html, { emitUpdate: false })
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
    editor.commands.setContent(html, { emitUpdate: false })
    assert.equal(editor.state.doc.firstChild.attrs.imgRole, null)
    const out = win.toWordPressHTML(editor.getHTML())
    assert.doesNotMatch(out, /role=/)
  })

  test('role is preserved on a classic linked image with no figure wrapper', () => {
    // The bare img[src] parse rule has no getAttrs, so imgRole must come from
    // its own per-attribute parseHTML fallback.
    editor.commands.setContent('<p><img src="http://x/p.jpg" alt="" role="presentation"></p>', { emitUpdate: false })
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
    editor.commands.setContent('<p><img src="http://x/p.jpg" alt="" role="presentation"></p>', { emitUpdate: false })
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
    editor.commands.setContent(html, { emitUpdate: false })
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
    editor.commands.setContent(html, { emitUpdate: false })
    assert.equal(editor.state.doc.firstChild.attrs.imgRole, null)
    assert.doesNotMatch(win.toWordPressHTML(editor.getHTML()), /role=/)
  })

  test('role="none" sets isDecorative in the wp:image comment attributes', () => {
    // Without it, save() regenerates no role and Gutenberg rejects the block.
    const html = '<figure class="wp-block-image size-large"><img src="http://x/p.jpg" alt="" class="wp-image-99" role="none"><figcaption>cap</figcaption></figure>'
    editor.commands.setContent(html, { emitUpdate: false })
    const out = win.toWordPressHTML(editor.getHTML())
    assert.equal(JSON.parse(out.match(/<!-- wp:image ([\s\S]*?) -->/)[1]).isDecorative, true)
  })
})

describe('image dimensions round-trip', () => {
  before(() => { editor.commands.setContent('<p></p>', { emitUpdate: false }) })

  const save = () => win.toWordPressHTML(editor.getHTML())
  const attrsOf = out => JSON.parse(out.match(/<!-- wp:image ([\s\S]*?) -->/)[1])
  const docOf = out => new JSDOM('<body>' + out + '</body>').window.document

  // Real core/image save() output for a resized image.
  const RESIZED = '<figure class="wp-block-image size-full is-resized">'
    + '<img src="http://x/p.jpg" alt="" class="wp-image-99" style="width:640px;height:auto">'
    + '<figcaption class="wp-element-caption">cap</figcaption></figure>'

  test('a style width on the img parses into the width attr', () => {
    editor.commands.setContent(RESIZED, { emitUpdate: false })
    assert.equal(editor.state.doc.firstChild.attrs.width, 640)
  })

  test('height:auto parses as no height', () => {
    editor.commands.setContent(RESIZED, { emitUpdate: false })
    assert.equal(editor.state.doc.firstChild.attrs.height, null)
  })

  test('a resized image saves back with its style and is-resized intact', () => {
    editor.commands.setContent(RESIZED, { emitUpdate: false })
    const doc = docOf(save())
    assert.equal(doc.querySelector('img').getAttribute('style'), 'width:640px;height:auto')
    assert.ok(doc.querySelector('figure').classList.contains('is-resized'))
  })

  test('a resized image saves its dimensions into the comment attributes', () => {
    editor.commands.setContent(RESIZED, { emitUpdate: false })
    assert.equal(attrsOf(save()).width, '640px')
  })

  test('the saved img carries no width or height attribute', () => {
    editor.commands.setContent(RESIZED, { emitUpdate: false })
    const img = docOf(save()).querySelector('img')
    assert.ok(!img.hasAttribute('width') && !img.hasAttribute('height'))
  })

  test('is-resized is dropped when the image loses its dimensions', () => {
    editor.commands.setContent(RESIZED, { emitUpdate: false })
    const pos = 0
    editor.view.dispatch(editor.state.tr.setNodeMarkup(pos, null, {
      ...editor.state.doc.firstChild.attrs, width: null, height: null,
    }))
    const out = save()
    assert.ok(!docOf(out).querySelector('figure').classList.contains('is-resized'))
    assert.ok(!('width' in attrsOf(out)))
  })

  test('is-resized is not carried as a stale figure class', () => {
    editor.commands.setContent(RESIZED, { emitUpdate: false })
    assert.ok(!(editor.state.doc.firstChild.attrs.figureClass || '').includes('is-resized'))
  })

  test('a resized image round-trips idempotently', () => {
    editor.commands.setContent(RESIZED, { emitUpdate: false })
    const once = save()
    editor.commands.setContent(once, { emitUpdate: false })
    assert.equal(save(), once)
  })

  test('legacy width/height attributes are converted to a style on save', () => {
    const legacy = '<figure class="wp-block-image size-large"><img src="http://x/p.jpg" alt="" class="wp-image-99" width="640" height="480"><figcaption></figcaption></figure>'
    editor.commands.setContent(legacy, { emitUpdate: false })
    const doc = docOf(save())
    assert.equal(doc.querySelector('img').getAttribute('style'), 'width:640px;height:480px')
    assert.ok(!doc.querySelector('img').hasAttribute('width'))
  })

  test('an image inserted by Quill saves no dimensions, as core does', () => {
    editor.commands.setContent('<p></p>', { emitUpdate: false })
    win.insertImage('http://x/p.jpg', 99, 'alt text')
    const out = save()
    const img = docOf(out).querySelector('img')
    assert.ok(!img.hasAttribute('style') && !img.hasAttribute('width') && !img.hasAttribute('height'))
    assert.ok(!docOf(out).querySelector('figure').classList.contains('is-resized'))
    assert.deepEqual(attrsOf(out), { id: 99 })
  })

  // jsdom lays nothing out, so the drag starts from the handler's 300×200 fallback.
  function drag(handle, dx, dy, natural = [1200, 800]) {
    editor.commands.setContent('<figure><img src="http://x/p.jpg" alt=""></figure>', { emitUpdate: false })
    const img = editor.view.dom.querySelector('.image-frame img')
    Object.defineProperty(img, 'naturalWidth', { value: natural[0] })
    Object.defineProperty(img, 'naturalHeight', { value: natural[1] })
    editor.view.dom.querySelector('.resize-handle.' + handle)
      .dispatchEvent(new win.MouseEvent('mousedown', { clientX: 0, clientY: 0, bubbles: true }))
    win.document.dispatchEvent(new win.MouseEvent('mousemove', { clientX: dx, clientY: dy }))
    win.document.dispatchEvent(new win.MouseEvent('mouseup', {}))
    return editor.state.doc.firstChild.attrs
  }

  test('a proportional drag saves the width with height:auto, as core does', () => {
    assert.equal(drag('se', 100, 0).height, null)
    const out = save()
    assert.equal(docOf(out).querySelector('img').getAttribute('style'), 'width:400px;height:auto')
    assert.equal(attrsOf(out).width, '400px')
    assert.equal(attrsOf(out).height, 'auto')
  })

  const sizeBtn = slug => win.document.querySelector(`#image-toolbar [data-size="${slug}"]`)
  function withSizes(sizes, fn) {
    editor.commands.setContent(RESIZED, { emitUpdate: false })
    editor.commands.setNodeSelection(0)
    for (const [slug, data] of Object.entries(sizes)) sizeBtn(slug)._sizeData = data
    try { fn() } finally { for (const slug of Object.keys(sizes)) sizeBtn(slug)._sizeData = null }
  }

  test('picking a size swaps the URL and size class and keeps the width, as core does', () => {
    withSizes({ medium: { url: 'http://x/p-300.jpg', width: 300, height: 200 } }, () => sizeBtn('medium').click())
    const out = save()
    const img = docOf(out).querySelector('img')
    assert.equal(img.getAttribute('src'), 'http://x/p-300.jpg')
    assert.equal(img.getAttribute('style'), 'width:640px;height:auto')
    assert.equal(attrsOf(out).sizeSlug, 'medium')
    assert.equal(attrsOf(out).width, '640px')
    assert.ok(!docOf(out).querySelector('figure').classList.contains('size-full'))
  })

  test('Reset restores the full-size URL and clears the dimensions', () => {
    withSizes({ full: { url: 'http://x/p-orig.jpg', width: 4000, height: 3000 } }, () => {
      win.document.getElementById('img-tb-reset').click()
    })
    const out = save()
    const img = docOf(out).querySelector('img')
    assert.equal(img.getAttribute('src'), 'http://x/p-orig.jpg')
    assert.ok(!img.hasAttribute('style'))
    assert.equal(attrsOf(out).sizeSlug, 'full')
    assert.ok(!('width' in attrsOf(out)) && !('height' in attrsOf(out)))
  })

  test('pressing Reset twice leaves the natural size in the W and H fields', () => {
    selectWithNaturalSize(RESIZED, [4000, 3000])
    sizeBtn('full')._sizeData = { url: 'http://x/p-orig.jpg', width: 4000, height: 3000 }
    try {
      win.document.getElementById('img-tb-reset').click()
      win.document.getElementById('img-tb-reset').click()
    } finally { sizeBtn('full')._sizeData = null }
    assert.equal(win.document.getElementById('img-tb-w').value, '4000')
    assert.equal(win.document.getElementById('img-tb-h').value, '3000')
  })

  test('a drag that stretches the image off its natural ratio keeps an explicit height', () => {
    const attrs = drag('e', 100, 0)
    assert.equal(attrs.width, 400)
    assert.equal(attrs.height, 200)
  })

  function selectWithNaturalSize(html, natural) {
    editor.commands.setContent('<p></p>', { emitUpdate: false })
    editor.commands.setContent(html, { emitUpdate: false })
    const img = editor.view.dom.querySelector('.image-frame img')
    Object.defineProperty(img, 'naturalWidth', { value: natural[0], configurable: true })
    Object.defineProperty(img, 'naturalHeight', { value: natural[1], configurable: true })
    editor.commands.setNodeSelection(0)
  }

  function typeHeight(value) {
    const field = win.document.getElementById('img-tb-h')
    field.value = String(value)
    field.dispatchEvent(new win.Event('change'))
    return editor.state.doc.firstChild.attrs
  }

  test('the height field shows the height a width-only image implies', () => {
    selectWithNaturalSize(RESIZED, [1280, 800])
    assert.equal(win.document.getElementById('img-tb-w').value, '640')
    assert.equal(win.document.getElementById('img-tb-h').value, '400')
  })

  test('typing a height on a width-only image keeps its ratio', () => {
    selectWithNaturalSize(RESIZED, [1280, 800])
    const attrs = typeHeight(200)
    assert.equal(attrs.width, 320)
    assert.equal(attrs.height, 200)
    assert.equal(win.document.getElementById('img-tb-w').value, '320')
  })

  test('typing a height on an unresized image scales from its natural size', () => {
    selectWithNaturalSize('<figure class="wp-block-image"><img src="http://x/p.jpg" alt=""></figure>', [1200, 800])
    assert.equal(win.document.getElementById('img-tb-w').value, '1200')
    assert.equal(win.document.getElementById('img-tb-h').value, '800')
    const attrs = typeHeight(400)
    assert.equal(attrs.width, 600)
    assert.equal(attrs.height, 400)
  })
})

describe('image toolbar visibility', () => {
  const tb = () => win.document.getElementById('image-toolbar')
  const wait = ms => new Promise(r => setTimeout(r, ms))

  function selectImage() {
    editor.commands.setContent('<figure class="wp-block-image"><img src="http://x/p.jpg" alt=""></figure><p>after</p>', { emitUpdate: false })
    editor.commands.setNodeSelection(0)
    assert.equal(tb().style.display, 'flex')
  }

  test('committing alt text keeps the image selected', () => {
    selectImage()
    const alt = win.document.getElementById('img-tb-alt')
    alt.focus()
    alt.value = 'a photo'
    alt.dispatchEvent(new win.Event('blur'))
    assert.equal(editor.state.selection.node?.attrs.alt, 'a photo')
  })

  test('moving the caret out after editing alt text hides the toolbar', async () => {
    selectImage()
    const alt = win.document.getElementById('img-tb-alt')
    alt.focus()
    alt.value = 'a photo'
    alt.dispatchEvent(new win.Event('blur'))
    await wait(100)
    editor.commands.focus()
    editor.commands.setTextSelection(editor.state.doc.content.size - 2)
    await wait(100)
    assert.equal(tb().style.display, 'none')
  })

  test('the Link to Full Image toggle keeps the image selected', () => {
    selectImage()
    win.document.getElementById('img-tb-link').click()
    assert.equal(editor.state.selection.node?.attrs.linkTo, 'media')
  })

  function withWrapperBottom(bottom, fn) {
    const proto = win.HTMLElement.prototype
    const original = proto.getBoundingClientRect
    proto.getBoundingClientRect = function () {
      return this.classList.contains('image-wrapper') ? { left: 40, top: bottom - 100, bottom, right: 340, width: 300, height: 100 } : original.call(this)
    }
    try { fn() } finally { proto.getBoundingClientRect = original }
  }

  test('the toolbar follows the image when its attributes change', () => {
    selectImage()
    withWrapperBottom(500, () => {
      const node = editor.state.selection.node
      editor.view.dispatch(editor.state.tr.setNodeMarkup(0, null, { ...node.attrs, width: 120 }))
    })
    assert.equal(tb().style.top, '506px')
  })

  test('the toolbar follows the image when a new size finishes loading', () => {
    selectImage()
    withWrapperBottom(300, () => {
      win.document.querySelector('#editor .image-wrapper img').dispatchEvent(new win.Event('load'))
    })
    assert.equal(tb().style.top, '306px')
  })

  function setNaturalSize(img, width, height) {
    Object.defineProperty(img, 'naturalWidth', { value: width, configurable: true })
    Object.defineProperty(img, 'naturalHeight', { value: height, configurable: true })
  }
  const dims = () => [win.document.getElementById('img-tb-w').value, win.document.getElementById('img-tb-h').value]

  test('W and H keep showing the natural size after a size change on an image with no stored width', () => {
    selectImage()
    setNaturalSize(win.document.querySelector('#editor .image-wrapper img'), 300, 200)
    const node = editor.state.selection.node
    editor.view.dispatch(editor.state.tr.setNodeMarkup(0, null, { ...node.attrs, src: 'http://x/p-300x200.jpg' }))
    assert.deepEqual(dims(), ['300', '200'])
  })

  test('W and H update when the new size finishes loading', () => {
    editor.commands.setContent('<figure class="wp-block-image"><img src="http://x/p.jpg" alt=""></figure><p>after</p>', { emitUpdate: false })
    const img = win.document.querySelector('#editor .image-wrapper img')
    setNaturalSize(img, 300, 200)
    editor.commands.setNodeSelection(0)
    const node = editor.state.selection.node
    editor.view.dispatch(editor.state.tr.setNodeMarkup(0, null, { ...node.attrs, src: 'http://x/p-1024x683.jpg' }))
    setNaturalSize(img, 1024, 683)
    img.dispatchEvent(new win.Event('load'))
    assert.deepEqual(dims(), ['1024', '683'])
  })

  test('an alignment button keeps the image selected and the toolbar open', async () => {
    selectImage()
    win.document.querySelector('[data-cmd="alignCenter"]')
      .dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true }))
    await wait(100)
    assert.equal(editor.state.selection.node?.attrs.alignment, 'center')
    assert.equal(tb().style.display, 'flex')
  })
})

describe('window.insertImage cursor placement', () => {
  before(() => { editor.commands.setContent('<p></p>', { emitUpdate: false }) })

  function selParent() { return editor.state.selection.$from.parent.type.name }

  test('inserting into an empty document leaves the cursor in a paragraph below', () => {
    editor.commands.setContent('<p></p>', { emitUpdate: false })
    editor.commands.focus()
    win.insertImage('http://x/p.jpg', 42, 'alt text')
    assert.equal(doc(), 'image[] | paragraph()')
    assert.equal(selParent(), 'paragraph')
  })

  test('inserting after existing text appends the paragraph after the image', () => {
    editor.commands.setContent('<p>hello</p>', { emitUpdate: false })
    editor.commands.setTextSelection(6)
    editor.commands.focus()
    win.insertImage('http://x/p.jpg')
    assert.equal(doc(), 'paragraph("hello") | image[] | paragraph()')
    assert.equal(selParent(), 'paragraph')
  })

  test('the caption is left empty and still holds the image attrs', () => {
    editor.commands.setContent('<p></p>', { emitUpdate: false })
    editor.commands.focus()
    win.insertImage('http://x/p.jpg', 42, 'alt text')
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
    editor.commands.setContent('<p></p>', { emitUpdate: false })
    editor.commands.focus()
    win.insertImage('http://x/a.jpg', 1)
    win.insertImage('http://x/b.jpg', 2)
    win.insertImage('http://x/c.jpg', 3)
    assert.equal(doc(), 'image[] | image[] | image[] | paragraph()')
    const srcs = []
    editor.state.doc.descendants(n => { if (n.type.name === 'image') srcs.push(n.attrs.src) })
    assert.deepEqual(srcs, ['http://x/a.jpg', 'http://x/b.jpg', 'http://x/c.jpg'])
    assert.equal(selParent(), 'paragraph')
  })

  test('a multi-image drop saves one wp:image pair per image, in drop order', () => {
    editor.commands.setContent('<p></p>', { emitUpdate: false })
    editor.commands.focus()
    win.insertImage('http://x/a.jpg', 1)
    win.insertImage('http://x/b.jpg', 2)
    const out = win.toWordPressHTML(editor.getHTML())
    const ids = [...out.matchAll(/<!-- wp:image \{"id":(\d+)[^}]*\} -->/g)].map(m => m[1])
    assert.deepEqual(ids, ['1', '2'])
    assert.equal((out.match(/<!-- \/wp:image -->/g) || []).length, 2)
    // No blank paragraph wedged between the two figures by the cursor move.
    assert.doesNotMatch(out, /<!-- \/wp:image -->\s*<p><\/p>\s*<!-- wp:image/)
    assert.equal(out, win.toWordPressHTML(out), 'save transform is idempotent')
  })

  test('the saved figure carries no caption and no empty paragraph', () => {
    editor.commands.setContent('<p>before</p>', { emitUpdate: false })
    editor.commands.focus('end')
    win.insertImage('http://x/r.jpg', 42, 'alt text')
    const out = win.toWordPressHTML(editor.getHTML())
    const figure = out.match(/<figure class="wp-block-image[^"]*">[\s\S]*?<\/figure>/)[0]
    assert.doesNotMatch(figure, /<figcaption/)
    assert.doesNotMatch(figure, /<p>/)
    assert.match(figure, /<img src="http:\/\/x\/r\.jpg"/)
    // The new paragraph is a sibling after the block, and empty it never saves.
    assert.equal(doc(), 'paragraph("before") | image[] | paragraph()')
    assert.match(out, /<!-- \/wp:image -->$/)
  })

  test('the paragraph below the image accepts typing', () => {
    editor.commands.setContent('<p>before</p>', { emitUpdate: false })
    editor.commands.focus('end')
    win.insertImage('http://x/r.jpg')
    editor.commands.insertContent('typed')
    assert.equal(doc(), 'paragraph("before") | image[] | paragraph("typed")')
  })

  test('inserting with the cursor in an existing caption appends below, leaving the caption intact', () => {
    editor.commands.setContent('<figure class="wp-block-image"><img src="http://x/o.jpg"><figcaption>cap</figcaption></figure>', { emitUpdate: false })
    editor.commands.focus('end')
    win.insertImage('http://x/n.jpg')
    assert.equal(doc(), 'image["cap"] | image[] | paragraph()')
    assert.equal(selParent(), 'paragraph')
  })

  test('inserting while an image node is selected replaces it and still lands below', () => {
    editor.commands.setContent('<p>a</p><figure class="wp-block-image"><img src="http://x/old.jpg"></figure><p>b</p>', { emitUpdate: false })
    editor.commands.setNodeSelection(posOfFirst('image'))
    win.insertImage('http://x/new.jpg')
    assert.equal(doc(), 'paragraph("a") | image[] | paragraph() | paragraph("b")')
    const srcs = []
    editor.state.doc.descendants(n => { if (n.type.name === 'image') srcs.push(n.attrs.src) })
    assert.deepEqual(srcs, ['http://x/new.jpg'])
    assert.equal(selParent(), 'paragraph')
  })

  // core/list-item holds only its text and a nested list, so the block editor's inserter adds the image after the list.
  test('from a list item the image and its paragraph go after the list', () => {
    editor.commands.setContent('<ul><li><p>one</p></li></ul>', { emitUpdate: false })
    editor.commands.focus('end')
    win.insertImage('http://x/l.jpg')
    assert.equal(doc(), 'bulletList(listItem(paragraph("one"))) | image[] | paragraph()')
    assert.equal(selParent(), 'paragraph')
    const out = win.toWordPressHTML(editor.getHTML())
    assert.match(out, /<\/ul>\s*<!-- \/wp:list -->\s*<!-- wp:image -->/)
  })

  test('inside a blockquote the image and its paragraph stay in the quote', () => {
    editor.commands.setContent('<blockquote><p>quoted</p></blockquote>', { emitUpdate: false })
    editor.commands.focus('end')
    win.insertImage('http://x/q.jpg')
    assert.equal(doc(), 'blockquote(paragraph("quoted"),image[],paragraph())')
    const out = win.toWordPressHTML(editor.getHTML())
    assert.match(out, /<blockquote class="wp-block-quote">[\s\S]*<figure class="wp-block-image">[\s\S]*<\/blockquote>/)
  })

  test('inside a table cell the image goes inline in that cell, as core cells hold text', () => {
    editor.commands.setContent('<table><tbody><tr><td><p>cell</p></td><td><p>b</p></td></tr></tbody></table>', { emitUpdate: false })
    // Not focus('end') — a trailing table now carries a paragraph after it.
    editor.commands.setTextSelection(paragraphStarts()[1] + 1)
    win.insertImage('http://x/t.jpg')
    assert.equal(doc(), 'table(tableRow(tableCell(paragraph("cell")),tableCell(paragraph("b",inlineImage())))) | paragraph()')
    assert.equal(selParent(), 'paragraph')
  })

  test('from a code block the image lands after the block, leaving the code untouched', () => {
    editor.commands.setContent('<pre><code>let x = 1</code></pre>', { emitUpdate: false })
    editor.commands.focus('end')
    win.insertImage('http://x/c2.jpg')
    assert.equal(doc(), 'codeBlock("let x = 1") | image[] | paragraph()')
    assert.equal(selParent(), 'paragraph')
    const out = win.toWordPressHTML(editor.getHTML())
    assert.match(out, /<pre class="wp-block-code"><code>let x = 1<\/code><\/pre>/)
  })

  test('inside a footnote the insert is refused and the document is unchanged', () => {
    editor.commands.setContent('<p>text</p>', { emitUpdate: false })
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

describe('trailing paragraph after a block that holds no text', () => {
  test('a document ending in a table gains one', () => {
    editor.commands.setContent('<table><tbody><tr><td><p>a</p></td></tr></tbody></table>', { emitUpdate: false })
    assert.equal(doc(), 'table(tableRow(tableCell(paragraph("a")))) | paragraph()')
  })

  test('typing in it reaches the document, not the table', () => {
    editor.commands.setContent('<table><tbody><tr><td><p>a</p></td></tr></tbody></table>', { emitUpdate: false })
    editor.commands.focus('end')
    editor.commands.insertContent('after')
    assert.equal(doc(), 'table(tableRow(tableCell(paragraph("a")))) | paragraph("after")')
  })

  test('an image figure gains none — its caption is a text position already', () => {
    editor.commands.setContent('<figure class="wp-block-image"><img src="http://x/a.jpg"></figure>', { emitUpdate: false })
    assert.equal(doc(), 'image[]')
  })

  test('a document already ending in a paragraph gains nothing', () => {
    editor.commands.setContent('<table><tbody><tr><td><p>a</p></td></tr></tbody></table><p>tail</p>', { emitUpdate: false })
    assert.equal(doc(), 'table(tableRow(tableCell(paragraph("a")))) | paragraph("tail")')
  })

  test('the added paragraph is stripped again on save', () => {
    editor.commands.setContent('<table><tbody><tr><td><p>a</p></td></tr></tbody></table>', { emitUpdate: false })
    const out = win.toWordPressHTML(editor.getHTML())
    assert.ok(!out.includes('<p></p>'), out)
    assert.ok(!out.includes('wp:paragraph'), out)
  })

  const tableThenFootnotes = () => {
    editor.commands.setContent('<p>body</p><table><tbody><tr><td><p>a</p></td></tr></tbody></table>', { emitUpdate: false })
    editor.commands.setTextSelection(5)
    win.insertFootnote()
  }

  test('a loaded table followed only by the footnotes list gains one before the list', () => {
    tableThenFootnotes()
    editor.commands.setContent(editor.getHTML().replace('<p></p>', ''), { emitUpdate: false })
    const names = []
    editor.state.doc.forEach(n => names.push(n.type.name + (n.type.name === 'paragraph' ? `(${n.textContent})` : '')))
    assert.deepEqual(names, ['paragraph(body)', 'table', 'paragraph()', 'footnotesList'])
  })

  test('the paragraph added before the footnotes list is stripped again on save', () => {
    tableThenFootnotes()
    const out = win.toWordPressHTML(editor.getHTML())
    assert.equal(out.match(/<!-- wp:paragraph -->/g).length, 1, out)
    assert.ok(!out.includes('<p></p>'), out)
  })

  test('an empty paragraph the author wrote before the footnotes list is kept on save', () => {
    editor.commands.setContent('<p>body</p>', { emitUpdate: false })
    editor.commands.setTextSelection(5)
    win.insertFootnote()
    const list = editor.state.doc.lastChild
    const at = editor.state.doc.content.size - list.nodeSize
    editor.view.dispatch(editor.state.tr.insert(at, editor.schema.nodes.paragraph.create()))
    const out = win.toWordPressHTML(editor.getHTML())
    assert.equal(out.match(/<!-- wp:paragraph -->/g).length, 2, out)
    assert.equal(out.match(/<p><\/p>/g).length, 1, out)
  })

  test('a footnotes list stays last', () => {
    editor.commands.setContent('<p>body</p>', { emitUpdate: false })
    editor.commands.focus('end')
    win.insertFootnote()
    assert.equal(editor.state.doc.lastChild.type.name, 'footnotesList')
  })
})

describe('inline images', () => {
  const IMG = '<img class="wp-image-42" style="width: 150px;" src="http://x/a.png" alt="alt x">'
  const tableWith = cell => '<!-- wp:table -->\n<figure class="wp-block-table"><table class="has-fixed-layout"><tbody><tr><td>' + cell + '</td><td>b</td></tr></tbody></table></figure>\n<!-- /wp:table -->'
  const para = text => '<!-- wp:paragraph -->\n<p>' + text + '</p>\n<!-- /wp:paragraph -->'
  const editAtEnd = () => {
    editor.commands.insertContentAt(editor.state.doc.content.size - 1, 'z')
    win.syncContentToSwift()
    return win.getContent()
  }

  test('one in a table cell is kept byte for byte when another block is edited', () => {
    win.setContent(tableWith('a' + IMG) + '\n\n' + para('end'), '[]')
    assert.equal(editAtEnd(), tableWith('a' + IMG) + '\n\n' + para('endz'))
  })

  test('one in a paragraph of text stays in the paragraph', () => {
    win.setContent(para('Text ' + IMG + ' more'), '[]')
    assert.equal(editAtEnd(), para('Text ' + IMG + ' morez'))
  })

  test('an image alone in a paragraph still becomes an image block', () => {
    win.setContent('<p><img src="http://x/a.png" alt=""></p>', '[]')
    assert.ok(editor.getJSON().content.some(n => n.type === 'image'))
  })

  test('a script handler on one is not carried into the editor or the save', () => {
    win.setContent(para('Text <img src="http://x/a.png" alt="" onerror="alert(1)"> more'), '[]')
    assert.equal(editor.view.dom.querySelector('[onerror]'), null)
    assert.doesNotMatch(editAtEnd(), /onerror/)
  })

  test('insertImage in a table cell inserts one as the block editor does, no wider than 150px', () => {
    win.setContent(tableWith('a'), '[]')
    editor.commands.setTextSelection(paragraphStarts()[0] + 1)
    win.insertImage('http://x/a.png', 42, 'alt x', 800)
    win.syncContentToSwift()
    assert.equal(win.getContent(), tableWith('a' + IMG))
  })

  test('insertImage in a table cell keeps a narrower image at its own width', () => {
    win.setContent(tableWith('a'), '[]')
    editor.commands.setTextSelection(paragraphStarts()[0] + 1)
    win.insertImage('http://x/a.png', 42, 'alt x', 100)
    win.syncContentToSwift()
    assert.match(win.getContent(), /style="width: 100px;"/)
  })

  test('one copied on its own, with no line around it, pastes into a cell as one', () => {
    win.setContent(tableWith('a'), '[]')
    editor.commands.setTextSelection(paragraphStarts()[0] + 1)
    editor.commands.insertContent('<img class="wp-image-42" data-quill-style="width: 150px;" src="http://x/a.png" alt="alt x" data-quill-inline-image="">')
    win.syncContentToSwift()
    assert.equal(win.getContent(), tableWith('a' + IMG))
  })

  test('insertImage in a table cell without a media id or width writes a 150px image and no wp-image class', () => {
    win.setContent(tableWith('a'), '[]')
    editor.commands.setTextSelection(paragraphStarts()[0] + 1)
    win.insertImage('http://x/a.png')
    win.syncContentToSwift()
    assert.equal(win.getContent(), tableWith('a<img style="width: 150px;" src="http://x/a.png" alt="">'))
  })

  test('insertImage in a header cell inserts one there too', () => {
    win.setContent('<table><tbody><tr><th><p>h</p></th><td><p>b</p></td></tr></tbody></table>', '[]')
    editor.commands.setTextSelection(paragraphStarts()[0] + 1)
    win.insertImage('http://x/a.png', 42, 'alt x', 800)
    assert.equal(doc(), 'table(tableRow(tableHeader(paragraph("h",inlineImage())),tableCell(paragraph("b")))) | paragraph()')
  })

  test('a linked one in a paragraph of text keeps its link', () => {
    const linked = '<a href="http://x/big.png">' + IMG + '</a>'
    win.setContent(para('Text ' + linked + ' more'), '[]')
    assert.equal(doc(), 'paragraph("Text ",inlineImage()," more")')
    assert.equal(editAtEnd(), para('Text ' + linked + ' morez'))
  })

  test('a linked image alone in a paragraph still becomes an image block', () => {
    win.setContent('<p><a href="http://x/big.png"><img src="http://x/a.png" alt=""></a></p>', '[]')
    const types = editor.getJSON().content.map(n => n.type)
    assert.ok(types.includes('image'))
    assert.equal(editor.view.dom.querySelector('p img, p [data-quill-inline-image]'), null)
  })

  test('one in a list item of text and one in a heading stay inline', () => {
    win.setContent('<ul><li>Item <img src="http://x/a.png" alt=""></li></ul><h3>Head <img src="http://x/b.png" alt=""></h3>', '[]')
    const found = []
    editor.state.doc.descendants((n, pos) => { if (n.type.name === 'inlineImage') found.push(editor.state.doc.resolve(pos).parent.type.name) })
    assert.deepEqual(found, ['paragraph', 'heading'])
  })

  test('a javascript: source is dropped with the script handlers', () => {
    win.setContent(para('Text <img src="javascript:alert(1)" alt="" onerror="alert(1)"> more'), '[]')
    assert.doesNotMatch(editAtEnd(), /javascript:|onerror/)
  })

  test('insertImage outside a table cell still inserts an image block', () => {
    win.setContent('<p>a</p>', '[]')
    editor.commands.setTextSelection(2)
    win.insertImage('http://x/a.png', 42, 'alt x', 800)
    assert.ok(editor.getJSON().content.some(n => n.type === 'image'))
  })
})

describe('the inline image popover', () => {
  const { applyInlineImage } = require('./core-formats')
  const IMG = '<img class="wp-image-42" style="width: 150px;" src="http://x/a.png" alt="alt x">'
  const para = text => '<!-- wp:paragraph -->\n<p>' + text + '</p>\n<!-- /wp:paragraph -->'
  const $ = id => win.document.getElementById(id)
  const settle = () => new Promise(resolve => setTimeout(resolve, 120))

  function select(html) {
    win.setContent(para(html), '[]')
    let at = null
    editor.state.doc.descendants((n, pos) => { if (n.type.name === 'inlineImage') at = pos })
    editor.commands.setNodeSelection(at)
  }

  function type(id, value) {
    $(id).value = value
    $(id).dispatchEvent(new win.Event('input', { bubbles: true }))
  }

  function apply() {
    $('inline-image-popover').dispatchEvent(new win.Event('submit', { bubbles: true, cancelable: true }))
    win.syncContentToSwift()
    return win.getContent().match(/<p>([\s\S]*)<\/p>/)[1]
  }

  test('selecting one opens it with the width and alt text the image has', () => {
    select('Text ' + IMG + ' more')
    assert.ok($('inline-image-popover').classList.contains('visible'))
    assert.equal($('iip-width').value, '150')
    assert.equal($('iip-alt').value, 'alt x')
  })

  test('a style with more than a width shows only the width and keeps the rest on Apply', () => {
    select('Text <img style="width:150px;height:100px" src="http://x/a.png" alt="a"> more')
    assert.equal($('iip-width').value, '150')
    type('iip-alt', 'b')
    assert.match(apply(), /style="width: 150px; height:100px;"/)
  })

  test('Apply stays off until a value changes', () => {
    select('Text ' + IMG + ' more')
    assert.equal($('iip-apply').disabled, true)
    type('iip-width', '300')
    assert.equal($('iip-apply').disabled, false)
    type('iip-width', '150')
    assert.equal($('iip-apply').disabled, true)
  })

  for (const [name, img, width, alt] of [
    ['a new width and alt text', IMG, '300', 'new alt'],
    ['a width on an image that had none', '<img src="http://x/a.png" alt="alt x">', '120', 'alt x'],
    ['a cleared width', IMG, '', 'alt x'],
    ['cleared alt text', IMG, '150', ''],
  ]) {
    test(`Apply writes what the block editor writes for ${name}`, () => {
      const html = 'Text ' + img + ' more'
      select(html)
      type('iip-width', width)
      type('iip-alt', alt)
      assert.equal(apply(), applyInlineImage(html, width, alt))
    })
  }

  test('the image stays selected after Apply', () => {
    select('Text ' + IMG + ' more')
    type('iip-width', '200')
    apply()
    assert.equal(editor.state.selection.node?.type.name, 'inlineImage')
    assert.ok($('inline-image-popover').classList.contains('visible'))
  })

  test('Escape in the editor closes it and leaves the table the image is in', () => {
    win.setContent('<!-- wp:table -->\n<figure class="wp-block-table"><table class="has-fixed-layout"><tbody><tr><td>a' + IMG + '</td><td>b</td></tr></tbody></table></figure>\n<!-- /wp:table -->', '[]')
    let at = null
    editor.state.doc.descendants((n, pos) => { if (n.type.name === 'inlineImage') at = pos })
    editor.commands.setNodeSelection(at)
    assert.ok($('inline-image-popover').classList.contains('visible'))
    key(editor.view, 'Escape')
    $('inline-image-popover').dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }))
    assert.equal($('inline-image-popover').classList.contains('visible'), false)
    assert.equal(editor.state.selection.node?.type.name, 'inlineImage')
    assert.ok(editor.state.selection.$from.depth > 1, 'the caret left the table')
  })

  test('deleting the image closes it', () => {
    select('Text ' + IMG + ' more')
    editor.commands.deleteSelection()
    assert.equal($('inline-image-popover').classList.contains('visible'), false)
  })

  test('opening code view closes it', () => {
    select('Text ' + IMG + ' more')
    $('btn-code-view').click()
    assert.equal($('inline-image-popover').classList.contains('visible'), false)
    $('btn-code-view').click()
  })

  test('the help link opens through Swift and does not navigate', () => {
    const opened = []
    win.webkit = { messageHandlers: { openLink: { postMessage: href => opened.push(href) } } }
    const ev = new win.MouseEvent('click', { bubbles: true, cancelable: true })
    $('iip-help-link').dispatchEvent(ev)
    delete win.webkit
    assert.deepEqual(opened, ['https://www.w3.org/WAI/tutorials/images/decision-tree/'])
    assert.equal(ev.defaultPrevented, true)
  })

  test('alt text with quotes and an ampersand is written as core writes it', () => {
    const html = 'Text ' + IMG + ' more'
    const alt = 'The "big" one & more'
    select(html)
    type('iip-alt', alt)
    assert.equal(apply(), applyInlineImage(html, '150', alt))
  })

  test('after Apply the popover shows the applied values and Apply is off again', () => {
    select('Text ' + IMG + ' more')
    type('iip-width', '200')
    type('iip-alt', 'changed')
    apply()
    assert.equal($('iip-width').value, '200')
    assert.equal($('iip-alt').value, 'changed')
    assert.equal($('iip-apply').disabled, true)
  })

  test('Escape closes it', () => {
    select('Text ' + IMG + ' more')
    $('iip-alt').dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }))
    assert.equal($('inline-image-popover').classList.contains('visible'), false)
  })

  test('moving the caret off the image closes it', async () => {
    select('Text ' + IMG + ' more')
    editor.commands.setTextSelection(2)
    await settle()
    assert.equal($('inline-image-popover').classList.contains('visible'), false)
  })
})

describe('find shortcut', () => {
  const press = mods => win.document.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'f', bubbles: true, cancelable: true, ...mods }))
  const bar = () => win.document.getElementById('find-bar').classList.contains('visible')

  test('⌘F opens the find bar', () => {
    press({ metaKey: true })
    assert.equal(bar(), true)
    win.document.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }))
    assert.equal(bar(), false)
  })

  test('⌃⌘F is left to the system and does not open it', () => {
    press({ metaKey: true, ctrlKey: true })
    assert.equal(bar(), false)
  })
})

describe('a press in the page gutter', () => {
  const wrap = () => win.document.getElementById('editor-wrap')
  const press = (target, init = {}) => {
    const ev = new win.MouseEvent('mousedown', { button: 0, clientX: 5, clientY: 5, bubbles: true, cancelable: true, ...init })
    target.dispatchEvent(ev)
    return ev
  }

  test('seats the caret at the nearest line instead of dropping focus', () => {
    editor.commands.setContent('<p>one</p><p>two</p>')
    const view = editor.view
    const original = view.posAtCoords
    view.posAtCoords = () => ({ pos: 6, inside: -1 })
    Object.defineProperty(wrap(), 'clientWidth', { configurable: true, value: 800 })
    try {
      const ev = press(wrap())
      assert.equal(ev.defaultPrevented, true)
      assert.equal(view.state.selection.from, 6)
    } finally { view.posAtCoords = original; delete wrap().clientWidth }
  })

  test('a press on the editor container beside the column seats too', () => {
    const view = editor.view
    const original = view.posAtCoords
    view.posAtCoords = () => ({ pos: 1, inside: -1 })
    Object.defineProperty(wrap(), 'clientWidth', { configurable: true, value: 800 })
    try {
      const ev = press(win.document.getElementById('editor'))
      assert.equal(ev.defaultPrevented, true)
      assert.equal(view.state.selection.from, 1)
    } finally { view.posAtCoords = original; delete wrap().clientWidth }
  })

  test('aims at the text block on the clicked line, not the column edge', () => {
    editor.commands.setContent('<ul><li><p>one</p></li></ul><p>two</p>')
    const view = editor.view
    const original = view.posAtCoords
    const asked = []
    const stub = (el, r) => { el.getBoundingClientRect = () => r }
    stub(view.dom, { left: 100, right: 300, top: 0, bottom: 100 })
    view.dom.querySelectorAll('p').forEach((el, i) => stub(el, i === 0 ? { left: 140, right: 300, top: 0, bottom: 40 } : { left: 100, right: 300, top: 50, bottom: 70 }))
    view.posAtCoords = point => { asked.push(point.left); return { pos: 3, inside: -1 } }
    Object.defineProperty(wrap(), 'clientWidth', { configurable: true, value: 800 })
    try {
      press(win.document.getElementById('editor'), { clientX: 20, clientY: 20 })
      assert.equal(asked[0], 141)
    } finally { view.posAtCoords = original; delete wrap().clientWidth }
  })

  test('Shift extends the selection from its anchor', () => {
    editor.commands.setContent('<p>one</p><p>two</p>')
    editor.commands.setTextSelection({ from: 2, to: 3 })
    const view = editor.view
    const original = view.posAtCoords
    view.posAtCoords = () => ({ pos: 7, inside: -1 })
    Object.defineProperty(wrap(), 'clientWidth', { configurable: true, value: 800 })
    try {
      press(wrap(), { shiftKey: true })
      assert.equal(view.state.selection.anchor, 2)
      assert.equal(view.state.selection.head, 7)
    } finally { view.posAtCoords = original; delete wrap().clientWidth }
  })

  test('a block whose anchor is "editor" is not mistaken for the container', () => {
    editor.commands.setContent('<p id="editor">anchored</p>')
    const block = editor.view.dom.querySelector('p')
    block.id = 'editor'
    assert.equal(press(block).defaultPrevented, false)
  })

  test('a press on the editor itself is left alone', () => {
    const ev = press(editor.view.dom)
    assert.equal(ev.defaultPrevented, false)
  })

  test('a secondary button is left alone', () => {
    const ev = press(wrap(), { button: 2 })
    assert.equal(ev.defaultPrevented, false)
  })
})

describe('the heading menu button', () => {
  const button = () => win.document.getElementById('heading-button')
  const menu = () => win.document.getElementById('heading-menu')
  const open = () => menu().classList.contains('visible')
  const mousedown = () => button().dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true, button: 0 }))
  const click = detail => button().dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true, detail }))

  test('a press opens the menu and a second press closes it', () => {
    mousedown()
    assert.equal(open(), true)
    assert.equal(button().getAttribute('aria-expanded'), 'true')
    mousedown()
    assert.equal(open(), false)
    assert.equal(button().getAttribute('aria-expanded'), 'false')
  })

  test('the click that ends a mouse press does not toggle it back', () => {
    mousedown()
    click(1)
    assert.equal(open(), true)
    mousedown()
    click(1)
    assert.equal(open(), false)
  })

  test('a click with no mouse detail, as a keyboard activation sends, toggles it', () => {
    click(0)
    assert.equal(open(), true)
    click(0)
    assert.equal(open(), false)
  })

  test('the press is cancelled so the editor keeps focus', () => {
    const ev = new win.MouseEvent('mousedown', { bubbles: true, cancelable: true, button: 0 })
    button().dispatchEvent(ev)
    assert.equal(ev.defaultPrevented, true)
    mousedown()
  })
})

// Pins v2 behaviour for the keys, clicks and link rules Tiptap 3 touches
// (docs/superpowers/plans/2026-11-11-tiptap-v3-migration.md, Task 2). The doc() values were
// read off v2; when v3 differs, v3 is changed, never these.
describe('Tiptap 3 migration: keys and clicks', () => {
  const textPos = str => {
    let at = null
    editor.state.doc.descendants((n, pos) => { if (at === null && n.isText && n.text === str) at = pos })
    return at
  }
  const nested = '<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>'

  test('Delete at the end of a list item that has a nested list', () => {
    editor.commands.setContent(nested, { emitUpdate: false })
    editor.commands.setTextSelection(textPos('a') + 1)
    key(editor.view, 'Delete')
    assert.equal(doc(), 'bulletList(listItem(paragraph("a"),paragraph("b")),listItem(paragraph("c")))')
  })

  test('Backspace at the start of a list item that follows a nested list', () => {
    editor.commands.setContent(nested, { emitUpdate: false })
    editor.commands.setTextSelection(textPos('c'))
    key(editor.view, 'Backspace')
    assert.equal(doc(), 'bulletList(listItem(paragraph("a"),bulletList(listItem(paragraph("b"))),paragraph("c")))')
  })

  test('Delete at the end of a footnote entry leaves the list intact', () => {
    editor.commands.setContent('<p>body</p>', { emitUpdate: false })
    editor.commands.setTextSelection(5)
    win.insertFootnote()
    editor.commands.insertContent('x')
    key(editor.view, 'Delete')
    assert.equal(doc(), 'paragraph("body",MARKER) | footnotesList(footnoteItem("x"))')
  })

  test('⌘-click on a link posts openLink once and a plain click posts nothing', () => {
    editor.commands.setContent('<p><a href="https://example.com/">l</a></p>', { emitUpdate: false })
    editor.commands.setTextSelection(1)
    const calls = []
    const opened = []
    const savedWebkit = win.webkit
    const savedOpen = win.open
    win.webkit = { messageHandlers: { ...(savedWebkit?.messageHandlers || {}), openLink: { postMessage: href => calls.push(href) } } }
    win.open = (...args) => { opened.push(args) }
    try {
      const anchor = editor.view.dom.querySelector('a')
      const click = metaKey => editor.view.someProp('handleClick', f => f(editor.view, 2, { button: 0, metaKey, target: anchor, preventDefault() {} }))
      click(true)
      const before = editor.state.selection.toJSON()
      click(false)
      assert.deepEqual(calls, ['https://example.com/'])
      assert.deepEqual(opened, [])
      assert.deepEqual(editor.state.selection.toJSON(), before)
    } finally {
      win.webkit = savedWebkit
      win.open = savedOpen
    }
  })

  test('a typed URL followed by a space becomes a link', () => {
    editor.commands.setContent('<p></p>', { emitUpdate: false })
    editor.commands.setTextSelection(1)
    for (const ch of 'see https://example.com ') editor.view.dispatch(editor.state.tr.insertText(ch))
    assert.equal(win.getContent(), '<!-- wp:paragraph -->\n<p>see <a href="https://example.com">https://example.com</a> </p>\n<!-- /wp:paragraph -->')
  })

  test('a URL pasted over selected text links that text', () => {
    editor.commands.setContent('<p>a word here</p>', { emitUpdate: false })
    editor.commands.setTextSelection({ from: 3, to: 7 })
    const ev = new win.Event('paste', { bubbles: true, cancelable: true })
    Object.defineProperty(ev, 'clipboardData', { value: { getData: t => (t === 'text/plain' ? 'https://example.com/' : ''), types: ['text/plain'], files: [] } })
    editor.view.dom.dispatchEvent(ev)
    assert.equal(win.getContent(), '<!-- wp:paragraph -->\n<p>a <a href="https://example.com/">word</a> here</p>\n<!-- /wp:paragraph -->')
  })
  test('Enter then Backspace in a footnote entry', () => {
    editor.commands.setContent('<p>body</p>', { emitUpdate: false })
    editor.commands.setTextSelection(5)
    win.insertFootnote()
    editor.commands.insertContent('xy')
    editor.commands.setTextSelection(editor.state.selection.from - 1)
    key(editor.view, 'Enter')
    const afterEnter = doc()
    key(editor.view, 'Backspace')
    assert.deepEqual([afterEnter, doc()], [
      'paragraph("body",MARKER) | footnotesList(footnoteItem("x",BR,"y"))',
      'paragraph("body",MARKER) | footnotesList(footnoteItem("xy"))',
    ])
  })

  // Input rules run from handleTextInput, which tr.insertText never reaches; type the way
  // ProseMirror's input handler does. Tiptap 3 gives each extension its own input-rule plugin.
  test('markdown input rules give the same document in every context', () => {
    const type = text => {
      for (const ch of text) {
        const { from, to } = editor.state.selection
        if (!editor.view.someProp('handleTextInput', f => f(editor.view, from, to, ch))) editor.view.dispatch(editor.state.tr.insertText(ch, from, to))
      }
    }
    const contexts = {
      paragraph: () => { editor.commands.setContent('<p></p>', { emitUpdate: false }); editor.commands.setTextSelection(1) },
      listItem: () => { editor.commands.setContent('<ul><li><p></p></li></ul>', { emitUpdate: false }); editor.commands.setTextSelection(posOfFirst('paragraph') + 1) },
      footnote: () => { editor.commands.setContent('<p>body</p>', { emitUpdate: false }); editor.commands.setTextSelection(5); win.insertFootnote() },
      tableCell: () => { editor.commands.setContent('<table><tbody><tr><td><p></p></td></tr></tbody></table>', { emitUpdate: false }); editor.commands.setTextSelection(posOfFirst('paragraph') + 1) },
    }
    const rules = ['# h', '> q', '- b', '1. n', '``` c', '---', '**b** ', '`c` ']
    const actual = {}
    for (const [where, setup] of Object.entries(contexts)) {
      for (const rule of rules) { setup(); type(rule); actual[`${where} ${rule}`] = rule.includes('*') || rule.includes('`c') ? `${(editor.getHTML().match(/<(strong|code)>[^<]*<\/\1>/) || ['no mark'])[0]} in ${doc()}` : doc() }
      setup(); type('- '); key(editor.view, 'Backspace'); actual[`${where} - then Backspace`] = doc()
    }
    assert.deepEqual(actual, {
      "paragraph # h": "heading(\"h\")",
      "paragraph > q": "blockquote(paragraph(\"q\"))",
      "paragraph - b": "bulletList(listItem(paragraph(\"b\")))",
      "paragraph 1. n": "orderedList(listItem(paragraph(\"n\")))",
      "paragraph ``` c": "codeBlock(\"c\")",
      "paragraph ---": "horizontalRule() | paragraph()",
      "paragraph **b** ": "<strong>b</strong> in paragraph(\"b\",\" \")",
      "paragraph `c` ": "<code>c</code> in paragraph(\"c\",\" \")",
      "paragraph - then Backspace": "paragraph(\"- \")",
      "listItem # h": "bulletList(listItem(paragraph(\"# h\")))",
      "listItem > q": "bulletList(listItem(paragraph(\"> q\")))",
      "listItem - b": "bulletList(listItem(paragraph(\"- b\")))",
      "listItem 1. n": "bulletList(listItem(paragraph(\"1. n\")))",
      "listItem ``` c": "bulletList(listItem(paragraph(\"``` c\")))",
      "listItem ---": "bulletList(listItem(paragraph(),horizontalRule(),paragraph()))",
      "listItem **b** ": "<strong>b</strong> in bulletList(listItem(paragraph(\"b\",\" \")))",
      "listItem `c` ": "<code>c</code> in bulletList(listItem(paragraph(\"c\",\" \")))",
      "listItem - then Backspace": "bulletList(listItem(paragraph(\"- \")))",
      "footnote # h": "paragraph(\"body\",MARKER) | footnotesList(footnoteItem(\"# h\"))",
      "footnote > q": "paragraph(\"body\",MARKER) | footnotesList(footnoteItem(\"> q\"))",
      "footnote - b": "paragraph(\"body\",MARKER) | footnotesList(footnoteItem(\"- b\"))",
      "footnote 1. n": "paragraph(\"body\",MARKER) | footnotesList(footnoteItem(\"1. n\"))",
      "footnote ``` c": "paragraph(\"body\",MARKER) | footnotesList(footnoteItem(\"``` c\"))",
      // cpoteet/Quill#24 bug 11: the rule split the footnotes list around a rule; v2 did the same.
      "footnote ---": "paragraph(\"body\",MARKER) | footnotesList(footnoteItem(\"---\"))",
      "footnote **b** ": "<strong>b</strong> in paragraph(\"body\",MARKER) | footnotesList(footnoteItem(\"b\",\" \"))",
      "footnote `c` ": "<code>c</code> in paragraph(\"body\",MARKER) | footnotesList(footnoteItem(\"c\",\" \"))",
      "footnote - then Backspace": "paragraph(\"body\",MARKER) | footnotesList(footnoteItem(\"- \"))",
      // Block rules stay text in a cell: 'block Markdown rules never fire in a table cell'.
      "tableCell # h": "table(tableRow(tableCell(paragraph(\"# h\")))) | paragraph()",
      "tableCell > q": "table(tableRow(tableCell(paragraph(\"> q\")))) | paragraph()",
      "tableCell - b": "table(tableRow(tableCell(paragraph(\"- b\")))) | paragraph()",
      "tableCell 1. n": "table(tableRow(tableCell(paragraph(\"1. n\")))) | paragraph()",
      "tableCell ``` c": "table(tableRow(tableCell(paragraph(\"``` c\")))) | paragraph()",
      "tableCell ---": "table(tableRow(tableCell(paragraph(\"---\")))) | paragraph()",
      "tableCell **b** ": "<strong>b</strong> in table(tableRow(tableCell(paragraph(\"b\",\" \")))) | paragraph()",
      "tableCell `c` ": "<code>c</code> in table(tableRow(tableCell(paragraph(\"c\",\" \")))) | paragraph()",
      "tableCell - then Backspace": "table(tableRow(tableCell(paragraph(\"- \")))) | paragraph()",
    })
  })
  // cpoteet/Quill#24 (bug 11 and its siblings): a block-level Markdown rule typed in a one-line
  // block turned it into that block or split its container: "# " in a caption replaced the image
  // with a heading, "---" split a Tabs block around a rule. In these the typed text stays text.
  test('block Markdown rules never fire in a title, button, caption or citation', () => {
    const type = text => {
      for (const ch of text) {
        const { from, to } = editor.state.selection
        if (!editor.view.someProp('handleTextInput', f => f(editor.view, from, to, ch))) editor.view.dispatch(editor.state.tr.insertText(ch, from, to))
      }
    }
    const contexts = {
      tabButton: '<div class="wp-block-tabs"><div role="tablist" class="wp-block-tab-list"><button type="button" role="tab"></button></div><div class="wp-block-tab-panels"><section role="tabpanel" tabindex="0" class="wp-block-tab-panel"><p>b</p></section></div></div>',
      buttonBlock: '<div class="wp-block-buttons"><div class="wp-block-button"><a class="wp-block-button__link wp-element-button"></a></div></div>',
      image: '<figure class="wp-block-image"><img src="a.jpg"><figcaption></figcaption></figure>',
      cite: '<blockquote><p>q</p><cite></cite></blockquote>',
      accordionHeading: '<div role="group" class="wp-block-accordion"><div class="wp-block-accordion-item"><h3 class="wp-block-accordion-heading"><button type="button" class="wp-block-accordion-heading__toggle"><span class="wp-block-accordion-heading__toggle-title"></span></button></h3><div role="region" class="wp-block-accordion-panel"><p>x</p></div></div></div>',
      detailsSummary: '<details class="wp-block-details"><summary></summary><p>b</p></details>',
    }
    const actual = {}, expected = {}
    for (const [name, html] of Object.entries(contexts)) {
      for (const rule of ['---', '# h', '> q', '- b', '1. n', '``` c', '![a](b.png)']) {
        const setup = () => { editor.commands.setContent(html, { emitUpdate: false }); editor.commands.setTextSelection(posOfFirst(name) + 1) }
        setup(); type(rule); actual[`${name} ${rule}`] = doc()
        setup(); editor.view.dispatch(editor.state.tr.insertText(rule)); expected[`${name} ${rule}`] = doc()
      }
    }
    assert.deepEqual(actual, expected)
  })

  // Core's table cells are rich text, so "- " or "> " typed in one made a list or quote inside the
  // cell, a shape WordPress has no block for. Inline rules still apply there.
  test('block Markdown rules never fire in a table cell, and inline ones still do', () => {
    const type = text => {
      for (const ch of text) {
        const { from, to } = editor.state.selection
        if (!editor.view.someProp('handleTextInput', f => f(editor.view, from, to, ch))) editor.view.dispatch(editor.state.tr.insertText(ch, from, to))
      }
    }
    const html = '<table><tr><th><p></p></th></tr><tr><td><p></p></td></tr></table><p>after</p>'
    const actual = {}, expected = {}
    for (const cell of ['tableHeader', 'tableCell']) {
      for (const rule of ['---', '# h', '> q', '- b', '1. n', '``` c', '![a](b.png)']) {
        const setup = () => { editor.commands.setContent(html, { emitUpdate: false }); editor.commands.setTextSelection(posOfFirst(cell) + 2) }
        setup(); type(rule); actual[`${cell} ${rule}`] = doc()
        setup(); editor.view.dispatch(editor.state.tr.insertText(rule)); expected[`${cell} ${rule}`] = doc()
      }
    }
    assert.deepEqual(actual, expected)
    editor.commands.setContent(html, { emitUpdate: false })
    editor.commands.setTextSelection(posOfFirst('tableCell') + 2)
    type('**bold** ')
    assert.match(JSON.stringify(editor.getJSON()), /"marks":\[\{"type":"bold"/)
  })

  // cpoteet/Quill#24 bug 1: the heading and paragraph keys ran setNode on the footnote and emptied it.
  test('⌘⌥0 to ⌘⌥6 in a footnote leave the note alone', () => {
    const notes = []
    for (const digit of '0123456') {
      editor.commands.setContent('<p>body</p>', { emitUpdate: false })
      editor.commands.setTextSelection(5)
      win.insertFootnote()
      editor.commands.insertContent('FootText words')
      editor.commands.setTextSelection(editor.state.selection.from - 4)
      editor.view.dom.dispatchEvent(new win.KeyboardEvent('keydown', {
        // ProseMirror's Mod is ⌘ only on a Mac platform, which jsdom is not.
        key: digit, code: 'Digit' + digit, keyCode: 48 + +digit, bubbles: true, cancelable: true, altKey: true,
        metaKey: /Mac/.test(win.navigator.platform), ctrlKey: !/Mac/.test(win.navigator.platform),
      }))
      notes.push(doc())
    }
    assert.deepEqual(notes, Array(7).fill('paragraph("body",MARKER) | footnotesList(footnoteItem("FootText words"))'))
  })

  // Found by review after the swap: Tiptap 3's Blockquote binds Backspace and ListItem brings
  // listItemBranchingDeleteKeymap, neither of which v2 had. Values read off v2.
  const typeX = () => editor.view.dispatch(editor.state.tr.insertText('X'))
  const caretBefore = str => editor.commands.setTextSelection(textPos(str))

  test('Backspace at the start of a paragraph after a quote, then typing', () => {
    editor.commands.setContent('<blockquote><p>Quote</p></blockquote><p>Following</p>', { emitUpdate: false })
    caretBefore('Following')
    key(editor.view, 'Backspace')
    typeX()
    assert.equal(doc(), 'blockquote(paragraph("Quote"),paragraph("XFollowing"))')
  })

  test('Backspace at the start of the second paragraph in a quote, then typing', () => {
    editor.commands.setContent('<blockquote><p>One</p><p>Two</p></blockquote>', { emitUpdate: false })
    caretBefore('Two')
    key(editor.view, 'Backspace')
    typeX()
    assert.equal(doc(), 'blockquote(paragraph("OneXTwo"))')
  })

  // v2's ordered-list input rule joins whenever the typed number follows the list; Tiptap 3's
  // also requires the list to have no type, so "3. " under a lettered list started a new list.
  test('typing the next number below a lettered list continues that list', () => {
    const type = text => {
      for (const ch of text) {
        const { from, to } = editor.state.selection
        if (!editor.view.someProp('handleTextInput', f => f(editor.view, from, to, ch))) editor.view.dispatch(editor.state.tr.insertText(ch, from, to))
      }
    }
    const below = (ol, typed) => {
      editor.commands.setContent(ol + '<p></p>', { emitUpdate: false })
      let at = null
      editor.state.doc.descendants((n, pos) => { if (n.type.name === 'paragraph' && n.content.size === 0) at = pos })
      editor.commands.setTextSelection(at + 1)
      type(typed)
      return doc() + ' type=' + editor.state.doc.firstChild.attrs.type
    }
    const two = 'orderedList(listItem(paragraph("one")),listItem(paragraph("two"))'
    assert.deepEqual({
      lettered: below('<ol type="a"><li><p>one</p></li><li><p>two</p></li></ol>', '3. x'),
      letteredSkip: below('<ol type="a"><li><p>one</p></li><li><p>two</p></li></ol>', '4. x'),
      plain: below('<ol><li><p>one</p></li><li><p>two</p></li></ol>', '3. x'),
    }, {
      lettered: two + ',listItem(paragraph("x"))) type=a',
      letteredSkip: two + ') | orderedList(listItem(paragraph("x"))) type=a',
      plain: two + ',listItem(paragraph("x"))) type=null',
    })
  })

  test('Backspace at the start of a paragraph after a quote with a citation, then typing', () => {
    win.setContent('<!-- wp:quote -->\n<blockquote class="wp-block-quote"><!-- wp:paragraph -->\n<p>Q</p>\n<!-- /wp:paragraph --><cite>Who</cite></blockquote>\n<!-- /wp:quote -->\n\n<!-- wp:paragraph -->\n<p>F</p>\n<!-- /wp:paragraph -->')
    caretBefore('F')
    key(editor.view, 'Backspace')
    typeX()
    // cpoteet/Quill#24 bug 10: v2 joined the line into the citation; it now joins the quote as a
    // line before the citation, as it does when the quote has none.
    assert.equal(doc(), 'blockquote(paragraph("Q"),paragraph("XF"),cite("Who"))')
  })

  // The same join into a pullquote, whose node holds paragraphs and a final citation only.
  test('Backspace at the start of a paragraph after a pullquote with a citation, then typing', () => {
    win.setContent('<!-- wp:pullquote -->\n<figure class="wp-block-pullquote"><blockquote><p>Q</p><cite>Who</cite></blockquote></figure>\n<!-- /wp:pullquote -->\n\n<!-- wp:paragraph -->\n<p>F</p>\n<!-- /wp:paragraph -->')
    caretBefore('F')
    key(editor.view, 'Backspace')
    typeX()
    assert.equal(doc(), 'pullquote(paragraph("Q"),paragraph("XF"),cite("Who"))')
    assert.match(win.getContent(), /<blockquote><p>Q<\/p><p>XF<\/p><cite>Who<\/cite><\/blockquote>/)
  })

  // A pullquote holds only paragraphs, so a heading, preformatted block or code block joins it as a
  // paragraph, as it does with no citation; inserting the line whole split the pullquote in two.
  test('Backspace at the start of a heading, preformatted or code block after a pullquote with a citation', () => {
    const pullquote = '<!-- wp:pullquote -->\n<figure class="wp-block-pullquote"><blockquote><p>Q</p><cite>Who</cite></blockquote></figure>\n<!-- /wp:pullquote -->\n\n'
    const join = (block, first) => {
      win.setContent(pullquote + block)
      caretBefore(first)
      key(editor.view, 'Backspace')
      typeX()
      return doc() + ' | ' + win.getContent().match(/<figure class="wp-block-pullquote">.*?<\/figure>/s)?.[0]
    }
    assert.deepEqual({
      heading: join('<!-- wp:heading -->\n<h2 class="wp-block-heading">F</h2>\n<!-- /wp:heading -->', 'F'),
      preformatted: join('<!-- wp:preformatted -->\n<pre class="wp-block-preformatted">P</pre>\n<!-- /wp:preformatted -->', 'P'),
      code: join('<!-- wp:code -->\n<pre class="wp-block-code"><code>C</code></pre>\n<!-- /wp:code -->', 'C'),
      codeLines: join('<!-- wp:code -->\n<pre class="wp-block-code"><code>C\nD</code></pre>\n<!-- /wp:code -->', 'C\nD'),
    }, {
      codeLines: 'pullquote(paragraph("Q"),paragraph("XC",BR,"D"),cite("Who")) | <figure class="wp-block-pullquote"><blockquote><p>Q</p><p>XC<br>D</p><cite>Who</cite></blockquote></figure>',
      heading: 'pullquote(paragraph("Q"),paragraph("XF"),cite("Who")) | <figure class="wp-block-pullquote"><blockquote><p>Q</p><p>XF</p><cite>Who</cite></blockquote></figure>',
      preformatted: 'pullquote(paragraph("Q"),paragraph("XP"),cite("Who")) | <figure class="wp-block-pullquote"><blockquote><p>Q</p><p>XP</p><cite>Who</cite></blockquote></figure>',
      code: 'pullquote(paragraph("Q"),paragraph("XC"),cite("Who")) | <figure class="wp-block-pullquote"><blockquote><p>Q</p><p>XC</p><cite>Who</cite></blockquote></figure>',
    })
  })

  test('Delete at the end of a list item whose nested item holds two paragraphs', () => {
    editor.commands.setContent('<ul><li><p>a</p><ul><li><p>b</p><p>c</p></li></ul></li><li><p>d</p></li></ul>', { emitUpdate: false })
    editor.commands.setTextSelection(textPos('a') + 1)
    key(editor.view, 'Delete')
    assert.equal(doc(), 'bulletList(listItem(paragraph("a"),paragraph("b"),bulletList(listItem(paragraph("c")))),listItem(paragraph("d")))')
  })

  test('Delete at the end of a list item whose nested item holds its own list', () => {
    editor.commands.setContent('<ul><li><p>a</p><ul><li><p>b</p><ul><li><p>c</p></li></ul></li></ul></li><li><p>d</p></li></ul>', { emitUpdate: false })
    editor.commands.setTextSelection(textPos('a') + 1)
    key(editor.view, 'Delete')
    assert.equal(doc() + ' sel=' + editor.state.selection.toJSON().type, 'bulletList(listItem(paragraph("a"),bulletList(listItem(paragraph("b"),bulletList(listItem(paragraph("c")))))),listItem(paragraph("d"))) sel=node')
  })
})

// Backspace at the start of a line after a block with no text of its own, or Delete at the end of
// a line before one, deleted the whole block in one keystroke: a separator, an image, or a block
// only code view can bring back. It is selected instead, and a second key deletes it.
describe('Backspace and Delete beside a block with no text select it first', () => {
  const preserved = '<!-- wp:paragraph -->\n<p>Before</p>\n<!-- /wp:paragraph -->\n\n' +
    '<!-- wp:acme/widget -->\n<div class="acme">Widget</div>\n<!-- /wp:acme/widget -->\n\n' +
    '<!-- wp:paragraph -->\n<p>After</p>\n<!-- /wp:paragraph -->'
  const count = name => { let n = 0; editor.state.doc.descendants(node => { if (node.type.name === name) n++ }); return n }

  test('Backspace after a separator selects it, and a second Backspace deletes it', () => {
    editor.commands.setContent('<p>hello</p><hr><p>after</p>')
    editor.commands.setTextSelection(paragraphStarts()[1])
    key(editor.view, 'Backspace')
    assert.equal(editor.state.selection.node?.type.name, 'horizontalRule')
    assert.equal(count('horizontalRule'), 1)
    key(editor.view, 'Backspace')
    assert.equal(count('horizontalRule'), 0)
  })

  test('a first list item or quote line after a separator still lifts out on Backspace', () => {
    for (const html of ['<hr><ul><li><p>x</p></li></ul>', '<hr><blockquote><p>x</p></blockquote>']) {
      editor.commands.setContent(html)
      editor.commands.setTextSelection(paragraphStarts()[0])
      key(editor.view, 'Backspace')
      assert.equal(doc(), 'horizontalRule() | paragraph("x")', html)
    }
  })

  test('Delete before a separator selects it, and a second Delete deletes it without joining the lines', () => {
    editor.commands.setContent('<p>hello</p><hr><p>after</p>')
    editor.commands.setTextSelection(6)
    key(editor.view, 'Delete')
    assert.equal(editor.state.selection.node?.type.name, 'horizontalRule')
    assert.equal(doc(), 'paragraph("hello") | horizontalRule() | paragraph("after")')
    key(editor.view, 'Delete')
    assert.equal(doc(), 'paragraph("hello") | paragraph("after")')
  })

  // From an empty line ProseMirror removes the line and selects the block itself; selecting the
  // block first would leave the empty line behind.
  test('Backspace or Delete on an empty line beside a separator removes the line and selects the separator', () => {
    editor.commands.setContent('<p>hello</p><hr><p></p><p>after</p>')
    editor.commands.setTextSelection(paragraphStarts()[1])
    key(editor.view, 'Backspace')
    assert.equal(doc(), 'paragraph("hello") | horizontalRule() | paragraph("after")')
    assert.equal(editor.state.selection.node?.type.name, 'horizontalRule')
    editor.commands.setContent('<p>hello</p><p></p><hr><p>after</p>')
    editor.commands.setTextSelection(paragraphStarts()[1])
    key(editor.view, 'Delete')
    assert.equal(doc(), 'paragraph("hello") | horizontalRule() | paragraph("after")')
    assert.equal(editor.state.selection.node?.type.name, 'horizontalRule')
  })

  test('Backspace after a preserved block selects it', () => {
    win.setContent(preserved, '')
    editor.commands.setTextSelection(paragraphStarts()[1])
    key(editor.view, 'Backspace')
    assert.equal(editor.state.selection.node?.type.name, 'gutenbergPassthrough')
    assert.match(win.getContent(), /acme\/widget/)
  })

  test('Delete before a preserved block selects it', () => {
    win.setContent(preserved, '')
    editor.commands.setTextSelection(paragraphStarts()[0] + 'Before'.length)
    key(editor.view, 'Delete')
    assert.equal(editor.state.selection.node?.type.name, 'gutenbergPassthrough')
    assert.match(win.getContent(), /acme\/widget/)
  })

  test('typing over a selected preserved block starts a paragraph after it instead of replacing it', () => {
    win.setContent(preserved, '')
    let at = null
    editor.state.doc.descendants((node, pos) => { if (at === null && node.type.name === 'gutenbergPassthrough') at = pos })
    editor.commands.setNodeSelection(at)
    const { from, to } = editor.state.selection
    const handled = editor.view.someProp('handleTextInput', f => f(editor.view, from, to, 'x'))
    assert.equal(handled, true)
    assert.equal(count('gutenbergPassthrough'), 1)
    assert.match(doc(), /gutenbergPassthrough\(\) \| paragraph\("x"\) \| paragraph\("After"\)/)
    // The caret is after the typed character, so the next one goes on the same new line.
    assert.equal(editor.state.selection.empty, true)
    assert.equal(editor.state.selection.$from.parent.textContent, 'x')
    assert.equal(editor.state.selection.$from.parentOffset, 1)
    const { from: f2, to: t2 } = editor.state.selection
    if (!editor.view.someProp('handleTextInput', f => f(editor.view, f2, t2, 'y'))) editor.view.dispatch(editor.state.tr.insertText('y', f2, t2))
    assert.equal(doc(), 'paragraph("Before") | gutenbergPassthrough() | paragraph("xy") | paragraph("After")')
  })

  test('typing over a selected separator still replaces it, as before', () => {
    editor.commands.setContent('<p>hello</p><hr><p>after</p>')
    editor.commands.setNodeSelection(editor.state.doc.child(0).nodeSize)
    const { from, to } = editor.state.selection
    if (!editor.view.someProp('handleTextInput', f => f(editor.view, from, to, 'x'))) editor.view.dispatch(editor.state.tr.insertText('x', from, to))
    assert.equal(doc(), 'paragraph("hello") | paragraph("x") | paragraph("after")')
  })
})
