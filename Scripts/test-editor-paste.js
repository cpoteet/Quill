'use strict'

// Live paste-handling tests for the Tiptap editor.
//
// Loads the REAL Sources/QuillKit/Resources/editor.html inside jsdom, dispatches
// actual `paste` events at the ProseMirror view, and asserts on the resulting
// document. Same approach as test-editor-keyboard.js / -gallery.js / -passthrough.js.
//
// Covers the two clipboard branches ProseMirror takes, which behave differently
// and have separate hooks in editorProps:
//   - text/html present  → parseFromClipboard → transformPastedHTML
//   - text/plain only    → parseFromClipboard → transformPastedText
// The footnote flatten guard originally existed only on the HTML branch, so
// multi-line plain text pasted into a footnote escaped the footnote and landed
// as sibling paragraphs after the footnotes list.
//
// jsdom caveat: jsdom does not implement DataTransfer, so `event.clipboardData`
// is hand-built below. That means these tests assert against a clipboard this
// file constructs, NOT the flavors WKWebView actually delivers (RTF, webarchive,
// Word's conditional-comment HTML, syntax-highlighted HTML from code editors).
// Treat green here as weaker evidence than the keyboard suite, where jsdom's
// keydown is faithful to the browser.

const { test, describe, before, after } = require('node:test')
const assert = require('node:assert/strict')
const { JSDOM, VirtualConsole } = require('jsdom')
const fs = require('fs')
const path = require('path')
const nodeCrypto = require('crypto')

const htmlPath = path.resolve(__dirname, '../Sources/QuillKit/Resources/editor.html')

const { problems, resaved, close: closeValidator } = require('./wp-validator.js')

let editor
let win
const sentToSwift = []

// Compact, readable structural summary of a ProseMirror JSON doc.
function summarize(json) {
  function walk(n) {
    if (n.type === 'text') return JSON.stringify(n.text)
    if (n.type === 'hardBreak') return 'BR'
    if (n.type === 'footnoteMarker') return 'MARKER'
    return n.type + '(' + (n.content || []).map(walk).join(',') + ')'
  }
  return (json.content || []).map(walk).join(' | ')
}

function doc() { return summarize(editor.getJSON()) }

// Dispatch a paste event carrying the given clipboard flavors, e.g.
// paste({ 'text/plain': 'a\n\nb' }) or paste({ 'text/html': '<p>a</p>' }).
function paste(data) {
  const ev = new win.Event('paste', { bubbles: true, cancelable: true })
  Object.defineProperty(ev, 'clipboardData', {
    value: {
      getData: t => data[t] || '',
      types: Object.keys(data),
      files: [],
    },
  })
  editor.view.dom.dispatchEvent(ev)
}

// Copy the current selection through ProseMirror's own copy handler and return the clipboard.
function copy() {
  const data = {}
  const ev = new win.Event('copy', { bubbles: true, cancelable: true })
  Object.defineProperty(ev, 'clipboardData', {
    value: { setData: (t, v) => { data[t] = v }, getData: t => data[t] || '', clearData: () => {}, types: [] },
  })
  editor.view.dom.dispatchEvent(ev)
  return data
}

// Place the cursor inside a footnote entry containing the text "note".
function focusFootnote() {
  editor.commands.setContent('<p>body</p>')
  editor.commands.focus('end')
  win.insertFootnote()
  editor.commands.insertContent('note')
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

  if (!win.crypto) win.crypto = {}
  if (!win.crypto.randomUUID) win.crypto.randomUUID = () => nodeCrypto.randomUUID()
  if (!win.matchMedia) win.matchMedia = () => ({ matches: false, addEventListener() {}, removeEventListener() {}, addListener() {}, removeListener() {} })
  if (!win.requestAnimationFrame) win.requestAnimationFrame = cb => setTimeout(cb, 0)
  if (!win.ResizeObserver) win.ResizeObserver = class { observe() {} unobserve() {} disconnect() {} }
  // jsdom has no layout. ProseMirror's drop focuses the editor, and a focused editor scrolls the
  // selection into view on every dispatch, which measures text and ranges.
  const rect = { top: 0, left: 0, bottom: 0, right: 0, width: 0, height: 0 }
  for (const proto of [win.Text.prototype, win.Range.prototype]) {
    if (proto.getClientRects) continue
    proto.getClientRects = () => Object.assign([rect], { item: () => rect })
    proto.getBoundingClientRect = () => rect
  }
  win.webkit = { messageHandlers: { contentChanged: { postMessage: html => sentToSwift.push(html) } } }

  editor = await new Promise((resolve, reject) => {
    let tries = 0
    const t = setInterval(() => {
      if (win._tiptapEditor) { clearInterval(t); resolve(win._tiptapEditor) }
      else if (++tries > 400) { clearInterval(t); reject(new Error('editor never became ready.\n' + logs.join('\n'))) }
    }, 25)
  })
})

after(() => { if (win) win.close(); closeValidator() })

describe('paste into footnotes', () => {
  test('multi-line plain text stays inside the footnote', () => {
    focusFootnote()
    paste({ 'text/plain': 'line one\n\nline two\n\nline three' })
    assert.equal(doc(), 'paragraph("body",MARKER) | footnotesList(footnoteItem("noteline one line two line three"))')
  })

  test('single-line plain text is inserted unchanged', () => {
    focusFootnote()
    paste({ 'text/plain': ' just one line ' })
    assert.equal(doc(), 'paragraph("body",MARKER) | footnotesList(footnoteItem("note just one line "))')
  })

  test('one line of HTML keeps the spaces at its edges (cpoteet/Quill#27)', () => {
    focusFootnote()
    paste({ 'text/html': '<span> by&nbsp;</span>', 'text/plain': ' by\u00a0' })
    assert.equal(doc(), 'paragraph("body",MARKER) | footnotesList(footnoteItem("note by\u00a0"))')
  })

  test('escaped markup in pasted HTML stays text in the footnote', () => {
    focusFootnote()
    paste({ 'text/html': '<p>&lt;b&gt;literal&lt;/b&gt;</p>', 'text/plain': '<b>literal</b>' })
    assert.equal(doc(), 'paragraph("body",MARKER) | footnotesList(footnoteItem("note<b>literal</b>"))')
  })

  test('block HTML is flattened into the footnote (pre-existing transformPastedHTML guard)', () => {
    focusFootnote()
    paste({ 'text/html': '<h2>Head</h2><ul><li>one</li><li>two</li></ul>', 'text/plain': 'Head one two' })
    assert.equal(doc(), 'paragraph("body",MARKER) | footnotesList(footnoteItem("noteHead one two"))')
  })

  test('CRLF and lone-CR line endings collapse the same way', () => {
    focusFootnote()
    paste({ 'text/plain': 'a\r\nb\rc' })
    assert.equal(doc(), 'paragraph("body",MARKER) | footnotesList(footnoteItem("notea b c"))')
  })
})

describe('paste into the body is unaffected', () => {
  test('multi-line plain text still becomes one paragraph per line', () => {
    editor.commands.setContent('<p></p>')
    editor.commands.focus('end')
    paste({ 'text/plain': 'line one\n\nline two' })
    assert.equal(doc(), 'paragraph("line one") | paragraph("line two")')
  })

  test('a line holding only spaces between two lines leaves no empty paragraph', () => {
    editor.commands.setContent('<p></p>')
    editor.commands.focus('end')
    paste({ 'text/plain': 'line one\n \t \nline two' })
    assert.equal(doc(), 'paragraph("line one") | paragraph("line two")')
  })

  test('single-line plain text is inserted as-is', () => {
    editor.commands.setContent('<p></p>')
    editor.commands.focus('end')
    paste({ 'text/plain': 'hello' })
    assert.equal(doc(), 'paragraph("hello")')
  })

  test('block HTML keeps its structure', () => {
    editor.commands.setContent('<p></p>')
    editor.commands.focus('end')
    paste({ 'text/html': '<h2>Head</h2><ul><li>one</li></ul>', 'text/plain': 'Head one' })
    assert.equal(doc(), 'heading("Head") | bulletList(listItem(paragraph("one")))')
  })
})

describe('window.insertMarkdown', () => {
  function md(text) {
    editor.commands.setContent('<p></p>')
    editor.commands.focus('end')
    return win.insertMarkdown(text)
  }

  test('converts headings, lists and inline marks', () => {
    const status = md('# Title\n\nSome **bold** text.\n\n- one\n- two')
    assert.equal(status, 'ok')
    assert.equal(doc(),
      'heading("Title") | paragraph("Some ","bold"," text.") | bulletList(listItem(paragraph("one")),listItem(paragraph("two")))')
  })

  test('converts blockquotes, fenced code and horizontal rules', () => {
    const status = md('> quoted\n\n```\ncode line\n```\n\n---')
    assert.equal(status, 'ok')
    assert.equal(doc(), 'blockquote(paragraph("quoted")) | codeBlock("code line") | horizontalRule() | paragraph()')
  })

  test('emits no blank paragraphs between blocks', () => {
    md('para one\n\npara two\n\npara three')
    assert.equal(doc(), 'paragraph("para one") | paragraph("para two") | paragraph("para three")')
  })

  test('converts tables', () => {
    md('| A | B |\n|---|---|\n| 1 | 2 |')
    assert.equal(doc(),
      'table(tableRow(tableHeader(paragraph("A")),tableHeader(paragraph("B"))),tableRow(tableCell(paragraph("1")),tableCell(paragraph("2")))) | paragraph()')
  })

  test('keeps images, matching what an HTML paste does', () => {
    md('![alt text](https://example.com/a.jpg)')
    assert.match(doc(), /image\(/)
  })

  test('an image on an empty line replaces that line instead of leaving an empty paragraph', () => {
    editor.commands.setContent('<p>Intro</p><p></p>')
    editor.commands.focus('end')
    win.insertMarkdown('![alt](https://example.com/a.jpg)')
    assert.equal(doc(), 'paragraph("Intro") | image()')
  })

  test('blocks on an empty line after text replace that line instead of leaving it empty above them', () => {
    editor.commands.setContent('<p>Intro</p><p></p>')
    editor.commands.focus('end')
    win.insertMarkdown('# H1 **bold**\n\npara')
    assert.equal(doc(), 'paragraph("Intro") | heading("H1 ","bold") | paragraph("para")')
  })

  // Raw HTML that leaves a tag open, then a line of text after it: the empty line stayed above
  // the paste, and every block after the raw HTML came out bold.
  test('raw HTML with an unclosed tag replaces the empty line and bolds nothing after it', () => {
    editor.commands.setContent('<p>Intro</p><p></p>')
    editor.commands.focus('end')
    win.insertMarkdown('# H1\n\n<div>raw <b>html</div> after\n\nnext para\n\n- item')
    const blocks = doc().split(' | ')
    assert.equal(blocks[0], 'paragraph("Intro")')
    assert.equal(blocks[1], 'heading("H1")')
    assert.ok(blocks.includes('paragraph("next para")'), doc())
    assert.ok(blocks.includes('bulletList(listItem(paragraph("item")))'), doc())
  })

  test('an empty line in the middle is replaced too', () => {
    editor.commands.setContent('<p>Intro</p><p></p><p>Outro</p>')
    editor.commands.setTextSelection(editor.state.doc.child(0).nodeSize + 1)
    win.insertMarkdown('- one\n- two')
    assert.equal(doc(), 'paragraph("Intro") | bulletList(listItem(paragraph("one")),listItem(paragraph("two"))) | paragraph("Outro")')
  })

  // A blank line splits raw HTML into two tokens; closing the first one off ended the table early.
  test('a raw table split by a blank line keeps both rows', () => {
    editor.commands.setContent('<p></p>')
    editor.commands.focus('end')
    win.insertMarkdown('<table>\n<tr><td><b>A</b></td></tr>\n\n<tr><td>B</td></tr>\n</table>')
    assert.equal((doc().match(/tableRow\(/g) || []).length, 2, doc())
  })

  test('an image inside a line of text splits it around the image', () => {
    editor.commands.setContent('<p>Intro</p><p></p>')
    editor.commands.focus('end')
    win.insertMarkdown('before ![alt](https://example.com/a.jpg) after')
    assert.equal(doc(), 'paragraph("Intro") | paragraph("before") | image() | paragraph("after")')
  })

  test('a linked image on its own line keeps its link', () => {
    md('[![alt](https://example.com/a.jpg)](https://example.com/page)')
    assert.equal(doc(), 'image()')
    assert.equal(editor.getJSON().content[0].attrs.linkHref, 'https://example.com/page')
  })

  test('aligned table columns save as valid Gutenberg table markup', () => {
    md('| L | C | R |\n|:--|:-:|--:|\n| a | b | c |')
    win.syncContentToSwift()
    const saved = sentToSwift.at(-1)
    assert.match(saved, /<td class="has-text-align-center" data-align="center">b<\/td>/)
    assert.doesNotMatch(saved, / align="/)
    assert.deepEqual(problems(saved), [], saved)
    assert.equal(resaved(saved), saved)
  })

  test('task list checkboxes degrade to plain list items', () => {
    md('- [ ] todo\n- [x] done')
    assert.equal(doc(), 'bulletList(listItem(paragraph("todo")),listItem(paragraph("done")))')
  })

  test('strips raw script tags in the source', () => {
    const status = md('text before\n\n<script>window.__pwned = 1</script>\n\ntext after')
    assert.equal(status, 'ok')
    assert.equal(win.__pwned, undefined)
    assert.doesNotMatch(doc(), /pwned/)
  })

  test('refuses inside a footnote and leaves the document untouched', () => {
    focusFootnote()
    const before = doc()
    const status = win.insertMarkdown('# Heading')
    assert.equal(status, 'footnote')
    assert.equal(doc(), before)
  })

  test('refuses inside a code block and leaves the document untouched', () => {
    editor.commands.setContent('<pre><code>existing</code></pre>')
    editor.commands.focus('end')
    const before = doc()
    const status = win.insertMarkdown('# Heading')
    assert.equal(status, 'code-block')
    assert.equal(doc(), before)
  })

  test('reports empty input without touching the document', () => {
    editor.commands.setContent('<p>keep me</p>')
    editor.commands.focus('end')
    assert.equal(win.insertMarkdown('   \n  '), 'empty')
    assert.equal(win.insertMarkdown(''), 'empty')
    assert.equal(win.insertMarkdown(null), 'empty')
    assert.equal(doc(), 'paragraph("keep me")')
  })

  test('inserts at the cursor rather than replacing the document', () => {
    editor.commands.setContent('<p>existing</p>')
    editor.commands.focus('end')
    win.insertMarkdown('## Added')
    assert.equal(doc(), 'paragraph("existing") | heading("Added")')
  })
})

// A title, label or caption holds inline content only, so pasted lines or blocks used to close its
// container to make room: a tabs, buttons or accordion block split in two around a stray paragraph.
describe('paste into a title, label or caption stays on one line', () => {
  const fixture = f => fs.readFileSync(path.resolve(__dirname, 'fixtures', f), 'utf8')
  const QUOTE = '<!-- wp:quote -->\n<blockquote class="wp-block-quote"><!-- wp:paragraph -->\n<p>Q</p>\n<!-- /wp:paragraph --><cite>Who</cite></blockquote>\n<!-- /wp:quote -->'
  const targets = {
    tabButton: () => fixture('tabs-block.html'),
    buttonBlock: () => fixture('settings-buttons.html'),
    detailsSummary: () => fixture('settings-details.html'),
    accordionHeading: () => fixture('accordion-block.html'),
    cite: () => QUOTE,
    image: () => fixture('settings-image.html'),
  }
  // Loads the markup, puts the caret two characters into the first `type` node, pastes, and
  // returns what changed: the block count, that node's text, and the rest of the document.
  const pasteInto = (type, data) => {
    win.setContent(targets[type]())
    const first = () => { let found = null; editor.state.doc.descendants((n, pos) => { if (found === null && n.type.name === type) found = { n, pos } }); return found }
    const { n, pos } = first()
    const offset = Math.min(2, n.content.size)
    const before = { blocks: editor.state.doc.childCount, text: n.textContent }
    editor.commands.setTextSelection(pos + 1 + offset)
    paste(data)
    const after = first()
    return {
      blocks: editor.state.doc.childCount,
      expectedBlocks: before.blocks,
      text: after.n.textContent,
      expectedText: before.text.slice(0, offset) + 'line one line two' + before.text.slice(offset),
      // Spread into this realm's array: the node's content array comes from the jsdom window.
      bold: [...after.n.content.content.filter(c => c.marks.some(m => m.type.name === 'bold')).map(c => c.text)],
      saved: win.getContent(),
    }
  }

  for (const type of Object.keys(targets)) {
    test(`multi-line plain text pasted into ${type} joins with spaces and leaves its block whole`, () => {
      const r = pasteInto(type, { 'text/plain': 'line one\n\nline two' })
      assert.deepEqual([r.blocks, r.text], [r.expectedBlocks, r.expectedText])
      assert.deepEqual(problems(r.saved), [], r.saved)
    })

    test(`paragraphs of HTML pasted into ${type} become one line that keeps its inline formatting`, () => {
      const r = pasteInto(type, { 'text/html': '<p>line <b>one</b></p><p>line two</p>', 'text/plain': 'line one\n\nline two' })
      assert.deepEqual([r.blocks, r.text, r.bold], [r.expectedBlocks, r.expectedText, ['one']])
      assert.deepEqual(problems(r.saved), [], r.saved)
    })
  }

  test('escaped markup in the pasted HTML stays text, never becomes a tag', () => {
    const r = pasteInto('tabButton', { 'text/html': '<p>&lt;b&gt;literal&lt;/b&gt; &lt;img src=x&gt;</p>', 'text/plain': '<b>literal</b> <img src=x>' })
    assert.deepEqual([r.blocks, r.text, r.bold], [r.expectedBlocks, r.expectedText.replace('line one line two', '<b>literal</b> <img src=x>'), []])
  })

  test('one line of plain text keeps its own spaces, non-breaking ones too', () => {
    const r = pasteInto('cite', { 'text/plain': ' by\u00a0 ' })
    assert.equal(r.text, r.expectedText.replace('line one line two', ' by\u00a0 '))
  })

  // cpoteet/Quill#27: the HTML path trimmed the flattened line, &nbsp; included, and ProseMirror's
  // parser drops a space at either end of inline content, so " by " went in as "by".
  for (const type of Object.keys(targets)) {
    test(`one line of HTML pasted into ${type} keeps the spaces at its edges`, () => {
      const r = pasteInto(type, { 'text/html': '<span> by </span>', 'text/plain': ' by ' })
      assert.equal(r.text, r.expectedText.replace('line one line two', ' by '))
      assert.deepEqual(problems(r.saved), [], r.saved)
    })
  }

  test('an edge space counts only when it is in the copied text, not at a block edge or between blocks', () => {
    const into = html => pasteInto('cite', { 'text/html': html, 'text/plain': 'x' }).text
    assert.deepEqual({
      bare: into(' by '),
      bold: into('<b> by </b>'),
      nbsp: into('<span>&nbsp;by&nbsp;</span>'),
      webkit: into('<span><span class="Apple-converted-space">\u00a0</span>by<span class="Apple-converted-space">\u00a0</span></span>'),
      chrome: into('<meta charset="utf-8"><span> by </span>\n'),
      openSlice: into('<p data-pm-slice="1 1 []"> by </p>'),
      closedBlock: into('<p> by </p>'),
      betweenBlocks: into('\n<p>a </p>\n<p> b</p>\n'),
    }, {
      bare: 'Wh by o',
      bold: 'Wh by o',
      nbsp: 'Wh\u00a0by\u00a0o',
      webkit: 'Wh by o',
      chrome: 'Wh by o',
      openSlice: 'Wh by o',
      closedBlock: 'Whbyo',
      betweenBlocks: 'Wha bo',
    })
  })

  // What real WebKit delivers for <span> by </span>: its sanitizer drops the leading space.
  test('a leading space WebKit dropped from the HTML comes back from the plain text', () => {
    const r = pasteInto('cite', { 'text/html': '<span>by<span class="Apple-converted-space">\u00a0</span></span>', 'text/plain': ' by ' })
    assert.equal(r.text, 'Wh by o')
  })

  test('the plain text adds no space when it is not the same line as the HTML', () => {
    assert.deepEqual({
      other: pasteInto('cite', { 'text/html': '<span>by</span>', 'text/plain': ' other ' }).text,
      lines: pasteInto('cite', { 'text/html': '<span>by</span>', 'text/plain': ' by\n' }).text,
    }, { other: 'Whbyo', lines: 'Whbyo' })
  })

  test("Quill's own copy of a phrase pastes into a citation with its spaces", () => {
    editor.commands.setContent('<p>Painted by Van Gogh</p>', { emitUpdate: false })
    editor.commands.setTextSelection({ from: 8, to: 12 })
    const clipboard = copy()
    assert.equal(clipboard['text/plain'], ' by ')
    assert.equal(pasteInto('cite', clipboard).text, 'Wh by o')
  })

  test('a heading still splits into blocks, as in the block editor', () => {
    editor.commands.setContent('<h2>Head</h2>', { emitUpdate: false })
    editor.commands.setTextSelection(5)
    paste({ 'text/plain': 'line one\nline two' })
    assert.equal(doc(), 'heading("Headline one") | paragraph("line two")')
  })
})

// ProseMirror's parser drops a space at either end of inline content in the body too, so a phrase
// copied from a page and pasted mid-sentence ran into its neighbours (cpoteet/Quill#27).
// ProseMirror runs the paste hooks for a drop from another app too, with the drop point as the parse
// context; the hooks read where it lands, not the caret, which a drop leaves where it was.
describe('a drop is shaped by where it lands, not by the caret', () => {
  const fixture = f => fs.readFileSync(path.resolve(__dirname, 'fixtures', f), 'utf8')
  const BODY = '<!-- wp:paragraph -->\n<p>Body text</p>\n<!-- /wp:paragraph -->'
  const LIST = '<!-- wp:list -->\n<ul class="wp-block-list"><!-- wp:list-item -->\n<li>Item</li>\n<!-- /wp:list-item --></ul>\n<!-- /wp:list -->'
  const TWO_PARAGRAPHS = { 'text/html': '<p>line one</p><p>line two</p>', 'text/plain': 'line one\n\nline two' }
  // jsdom has no layout, so the drop point comes from a stubbed posAtCoords; the rest is
  // ProseMirror's own drop handler.
  function drop(data, at) {
    const original = editor.view.posAtCoords
    editor.view.posAtCoords = () => ({ pos: at, inside: -1 })
    try {
      const ev = new win.Event('drop', { bubbles: true, cancelable: true })
      Object.defineProperty(ev, 'dataTransfer', { value: { getData: t => data[t] || '', types: Object.keys(data), files: [] } })
      editor.view.dom.dispatchEvent(ev)
    } finally {
      editor.view.posAtCoords = original
    }
  }
  const find = test => { let found = null; editor.state.doc.descendants((n, pos) => { if (found === null && test(n)) found = { n, pos } }); return found }
  const tabTitle = () => find(n => n.type.name === 'tabButton')
  const body = () => find(n => n.type.name === 'paragraph' && n.textContent.startsWith('Body'))
  const names = () => [...editor.state.doc.content.content].map(n => n.type.name)

  test('dropped into a tab title with the caret in the body, paragraphs join into one line', () => {
    win.setContent(fixture('tabs-block.html') + '\n\n' + BODY)
    const before = { blocks: names(), title: tabTitle().n.textContent }
    editor.commands.setTextSelection(body().pos + 3)
    drop(TWO_PARAGRAPHS, tabTitle().pos + 1)
    assert.deepEqual([names(), tabTitle().n.textContent], [before.blocks, 'line one line two' + before.title])
    assert.deepEqual(problems(win.getContent()), [])
  })

  test('dropped into the body with the caret in a tab title, paragraphs stay paragraphs', () => {
    win.setContent(fixture('tabs-block.html') + '\n\n' + BODY)
    const title = tabTitle()
    editor.commands.setTextSelection(title.pos + 2)
    drop(TWO_PARAGRAPHS, body().pos + 1 + 'Body'.length)
    const texts = [...editor.state.doc.content.content].filter(n => n.type.name === 'paragraph').map(n => n.textContent)
    assert.deepEqual([tabTitle().n.textContent, texts], [title.n.textContent, ['Bodyline one', 'line two text']])
  })

  test('dropped into the body with the caret in a list item, paragraphs do not become list items', () => {
    win.setContent(LIST + '\n\n' + BODY)
    editor.commands.setTextSelection(find(n => n.type.name === 'listItem').pos + 3)
    drop(TWO_PARAGRAPHS, body().pos + 1 + 'Body'.length)
    assert.deepEqual([names(), find(n => n.type.name === 'listItem').n.textContent], [['bulletList', 'paragraph', 'paragraph'], 'Item'])
  })

  test('plain text dropped into a citation with the caret in the body joins into one line', () => {
    win.setContent('<!-- wp:quote -->\n<blockquote class="wp-block-quote"><!-- wp:paragraph -->\n<p>Q</p>\n<!-- /wp:paragraph --><cite>Who</cite></blockquote>\n<!-- /wp:quote -->\n\n' + BODY)
    editor.commands.setTextSelection(body().pos + 3)
    drop({ 'text/plain': 'line one\n\nline two' }, find(n => n.type.name === 'cite').pos + 1)
    assert.deepEqual([names(), find(n => n.type.name === 'cite').n.textContent], [['blockquote', 'paragraph'], 'line one line twoWho'])
  })
})

describe('one line of HTML pasted mid-paragraph keeps its edge spaces', () => {
  const into = data => {
    editor.commands.setContent('<p>PaintedVan Gogh</p>', { emitUpdate: false })
    editor.commands.setTextSelection(8)
    paste(data)
    return doc()
  }

  test('as the HTML marks them, or as only the plain text does', () => {
    assert.deepEqual({
      span: into({ 'text/html': '<span> by </span>', 'text/plain': ' by ' }),
      webkit: into({ 'text/html': '<span><span class="Apple-converted-space">\u00a0</span>by<span class="Apple-converted-space">\u00a0</span></span>', 'text/plain': ' by ' }),
      dropped: into({ 'text/html': '<span>by<span class="Apple-converted-space">\u00a0</span></span>', 'text/plain': ' by ' }),
      bold: into({ 'text/html': '<b> by </b>', 'text/plain': ' by ' }),
    }, {
      span: 'paragraph("Painted by Van Gogh")',
      webkit: 'paragraph("Painted by Van Gogh")',
      dropped: 'paragraph("Painted by Van Gogh")',
      bold: 'paragraph("Painted ","by"," Van Gogh")',
    })
  })

  test('block HTML still trims its edges', () => {
    assert.equal(into({ 'text/html': '<p> by </p>', 'text/plain': ' by ' }), 'paragraph("PaintedbyVan Gogh")')
  })

  test('the save stays valid', () => {
    into({ 'text/html': '<span> by </span>', 'text/plain': ' by ' })
    assert.deepEqual(problems(win.getContent()), [])
  })
})

describe('paste into a code block preserves line breaks', () => {
  test('multi-line plain text keeps its newlines inside a code block', () => {
    editor.commands.setContent('<pre><code></code></pre>')
    editor.commands.focus('end')
    paste({ 'text/plain': 'const a = 1\nconst b = 2' })
    assert.equal(doc(), 'codeBlock("const a = 1\\nconst b = 2")')
  })
})

// Tiptap 3's OrderedList brought this (cpoteet/Quill#26); Quill keeps v3's parser but not its
// plugin, which pasted the list into code blocks and footnotes and merged it into the text beside it.
describe('plain text that is a numbered list', () => {
  const into = (html, text) => {
    editor.commands.setContent(html, { emitUpdate: false })
    let at = null
    editor.state.doc.descendants((n, pos) => { if (at === null && n.type.name === 'paragraph' && n.content.size === 0) at = pos })
    editor.commands.setTextSelection(at + 1)
    paste({ 'text/plain': text })
    return doc()
  }
  const LIST = '1. one\n2. two'

  test('pastes into an empty paragraph as one list that saves as a valid core/list', () => {
    let changes = 0
    const count = ({ transaction }) => { if (transaction.docChanged) changes++ }
    editor.commands.setContent('<p>before</p><p></p><p>after</p>', { emitUpdate: false })
    editor.on('transaction', count)
    try {
      assert.equal(into('<p>before</p><p></p><p>after</p>', LIST), 'paragraph("before") | orderedList(listItem(paragraph("one")),listItem(paragraph("two"))) | paragraph("after")')
    } finally {
      editor.off('transaction', count)
    }
    assert.equal(changes, 2, 'the setContent, then one paste transaction')
    const saved = win.getContent()
    assert.match(saved, /<!-- wp:list \{"ordered":true\} -->\n<ol class="wp-block-list">/)
    assert.deepEqual(problems(saved), [], saved)
  })

  test('keeps the first number as the start, and takes 1) markers, CRLF and blank lines', () => {
    assert.deepEqual({
      start: into('<p></p>', '3. x\n4. y'),
      paren: into('<p></p>', '1) one\n2) two'),
      crlf: into('<p></p>', '1. one\r\n2. two\r\n'),
      blank: into('<p></p>', '1. one\n\n2. two'),
    }, {
      start: 'orderedList(listItem(paragraph("x")),listItem(paragraph("y")))',
      paren: 'orderedList(listItem(paragraph("one")),listItem(paragraph("two")))',
      crlf: 'orderedList(listItem(paragraph("one")),listItem(paragraph("two")))',
      blank: 'orderedList(listItem(paragraph("one")),listItem(paragraph("two")))',
    })
    into('<p></p>', '3. x\n4. y')
    const saved = win.getContent()
    assert.match(saved, /<!-- wp:list \{"ordered":true,"start":3\} -->\n<ol start="3" class="wp-block-list">/)
    assert.deepEqual(problems(saved), [], saved)
  })

  test('item text is text, never markup', () => {
    assert.equal(into('<p></p>', '1. <b>x</b> & y\n2. two'), 'orderedList(listItem(paragraph("<b>x</b> & y")),listItem(paragraph("two")))')
  })

  test('joins the list, quote or column the empty paragraph is in', () => {
    assert.deepEqual({
      item: into('<ol><li><p>a</p></li><li><p></p></li></ol>', LIST),
      nested: into('<ul><li><p>a</p><ul><li><p></p></li></ul></li></ul>', LIST),
      quote: into('<blockquote><p>q</p><p></p></blockquote>', LIST),
      onlyItem: into('<ol><li><p></p></li></ol>', LIST),
      firstItem: into('<ul><li><p></p></li><li><p>b</p></li></ul>', LIST),
      onlyQuoteParagraph: into('<blockquote><p></p></blockquote>', LIST),
      column: into('<div class="wp-block-columns"><div class="wp-block-column"><p></p></div><div class="wp-block-column"><p>r</p></div></div>', LIST),
    }, {
      item: 'orderedList(listItem(paragraph("a")),listItem(paragraph("one")),listItem(paragraph("two")))',
      nested: 'bulletList(listItem(paragraph("a"),bulletList(listItem(paragraph("one")),listItem(paragraph("two")))))',
      quote: 'blockquote(paragraph("q"),orderedList(listItem(paragraph("one")),listItem(paragraph("two"))))',
      onlyItem: 'orderedList(listItem(paragraph("one")),listItem(paragraph("two")))',
      firstItem: 'bulletList(listItem(paragraph("one")),listItem(paragraph("two")),listItem(paragraph("b")))',
      onlyQuoteParagraph: 'blockquote(orderedList(listItem(paragraph("one")),listItem(paragraph("two"))))',
      column: 'columnsBlock(columnBlock(orderedList(listItem(paragraph("one")),listItem(paragraph("two")))),columnBlock(paragraph("r")))',
    })
  })

  test('at the start of a quote with a citation, the quote and citation stay', () => {
    win.setContent('<!-- wp:quote -->\n<blockquote class="wp-block-quote"><!-- wp:paragraph -->\n<p></p>\n<!-- /wp:paragraph --><cite>Who</cite></blockquote>\n<!-- /wp:quote -->')
    editor.commands.setTextSelection(2)
    paste({ 'text/plain': LIST })
    assert.equal(doc(), 'blockquote(orderedList(listItem(paragraph("one")),listItem(paragraph("two"))),cite("Who"))')
  })

  // Each value is what Quill pasted before the change.
  test('stays one paragraph per line anywhere else', () => {
    const at = (html, from, to = from) => { editor.commands.setContent(html, { emitUpdate: false }); editor.commands.setTextSelection({ from, to }); paste({ 'text/plain': LIST }); return doc() }
    assert.deepEqual({
      oneLine: into('<p></p>', '1. Introduction'),
      romanLooking: into('<p></p>', 'C. Smith'),
      skipsANumber: into('<p></p>', '1. one\n3. two'),
      notEveryLine: into('<p></p>', '1. one\nplain'),
      midParagraph: at('<p>abcd</p>', 3),
      overText: at('<p>abcd</p>', 2, 4),
      heading: at('<h2>Head</h2>', 5),
      code: at('<pre><code>code</code></pre>', 5),
      cell: into('<table><tbody><tr><td><p></p></td></tr></tbody></table>', LIST),
    }, {
      oneLine: 'paragraph("1. Introduction")',
      romanLooking: 'paragraph("C. Smith")',
      skipsANumber: 'paragraph("1. one") | paragraph("3. two")',
      notEveryLine: 'paragraph("1. one") | paragraph("plain")',
      midParagraph: 'paragraph("ab1. one") | paragraph("2. twocd")',
      overText: 'paragraph("a1. one") | paragraph("2. twod")',
      heading: 'heading("Head1. one") | paragraph("2. two")',
      code: 'codeBlock("code1. one\\n2. two")',
      cell: 'table(tableRow(tableCell(paragraph("1. one"),paragraph("2. two")))) | paragraph()',
    })
  })

  // Core writes a lettered or roman list as list-style-type plus the delimiter's type (cpoteet/Quill#27).
  test('a lettered or roman list pastes as core writes one, and passes WordPress\'s validator', () => {
    const saved = text => { into('<p></p>', text); return win.getContent() }
    for (const [text, type] of [['a. one\nb. two', 'lower-alpha'], ['A. one\nB. two', 'upper-alpha'], ['i. one\nii. two', 'lower-roman'], ['I) one\nII) two', 'upper-roman']]) {
      const html = saved(text)
      assert.equal(doc(), 'orderedList(listItem(paragraph("one")),listItem(paragraph("two")))', text)
      assert.match(html, new RegExp(`<!-- wp:list \\{"ordered":true,"type":"${type}"\\} -->\\n<ol style="list-style-type:${type}" class="wp-block-list">`), html)
      assert.deepEqual(problems(html), [], html)
    }
    // The style rides as data-quill-style, which is never drawn, so the editor's CSS draws the type.
    into('<p></p>', 'a. one\nb. two')
    assert.equal(win.getComputedStyle(editor.view.dom.querySelector('ol')).listStyleType, 'lower-alpha')
    const fromFour = saved('iv. x\nv. y')
    assert.match(fromFour, /"type":"lower-roman","start":4/)
    assert.deepEqual(problems(fromFour), [], fromFour)
  })

  test('a list starting at a letter other than a stays paragraphs', () => {
    assert.equal(into('<p></p>', 'c. x\nd. y'), 'paragraph("c. x") | paragraph("d. y")')
  })

  test('a Group holding only an empty paragraph gets the list inside it', () => {
    win.setContent('<!-- wp:group {"layout":{"type":"constrained"}} -->\n<div class="wp-block-group"><!-- wp:paragraph -->\n<p></p>\n<!-- /wp:paragraph --></div>\n<!-- /wp:group -->')
    editor.commands.setTextSelection(2)
    paste({ 'text/plain': LIST })
    assert.equal(doc(), 'groupBlock(orderedList(listItem(paragraph("one")),listItem(paragraph("two"))))')
  })

  // These open with a title, so the paste cannot widen over them. A pullquote holds paragraphs only.
  test('a details body, a tab panel and an accordion panel take the list; a pullquote keeps paragraphs', () => {
    const TABS = '<div class="wp-block-tabs"><div role="tablist" class="wp-block-tab-list"><button type="button" role="tab">T</button></div>' +
      '<div class="wp-block-tab-panels"><section role="tabpanel" tabindex="0" class="wp-block-tab-panel"><p></p></section></div></div>'
    const ACC = '<div role="group" class="wp-block-accordion"><div class="wp-block-accordion-item"><h3 class="wp-block-accordion-heading">' +
      '<button type="button" class="wp-block-accordion-heading__toggle"><span class="wp-block-accordion-heading__toggle-title">H</span></button></h3>' +
      '<div role="region" class="wp-block-accordion-panel"><p></p></div></div></div>'
    const ol = 'orderedList(listItem(paragraph("one")),listItem(paragraph("two")))'
    assert.deepEqual({
      details: into('<details class="wp-block-details"><summary>S</summary><p></p></details>', LIST),
      tab: into(TABS, LIST),
      accordion: into(ACC, LIST),
      pullquote: into('<figure class="wp-block-pullquote"><blockquote><p></p></blockquote></figure>', LIST),
    }, {
      details: `detailsBlock(detailsSummary("S"),${ol})`,
      tab: `tabsBlock(tabList(tabButton("T")),tabPanels(tabPanel(${ol})))`,
      accordion: `accordionBlock(accordionItem(accordionHeading("H"),accordionPanel(${ol})))`,
      pullquote: 'pullquote(paragraph("1. one"),paragraph("2. two"))',
    })
  })

  test('in a footnote it stays inline text', () => {
    focusFootnote()
    paste({ 'text/plain': LIST })
    assert.equal(doc(), 'paragraph("body",MARKER) | footnotesList(footnoteItem("note1. one 2. two"))')
  })

  test('a clipboard that also carries HTML pastes that HTML', () => {
    editor.commands.setContent('<p></p>', { emitUpdate: false })
    editor.commands.setTextSelection(1)
    paste({ 'text/plain': LIST, 'text/html': '<p>1. one</p><p>2. two</p>' })
    assert.equal(doc(), 'paragraph("1. one") | paragraph("2. two")')
  })
})

describe('copy and paste inside Quill', () => {
  const fixturesDir = path.resolve(__dirname, 'fixtures')

  function saved() {
    win.syncContentToSwift()
    return sentToSwift.at(-1)
  }

  // ProseMirror's own copy handler writes the clipboard; the paste reads it back.
  function copyAll() {
    editor.commands.focus()
    editor.commands.selectAll()
    const data = {}
    const ev = new win.Event('copy', { bubbles: true, cancelable: true })
    Object.defineProperty(ev, 'clipboardData', {
      value: { setData: (t, v) => { data[t] = v }, getData: t => data[t] || '', clearData: () => {}, types: [] },
    })
    editor.view.dom.dispatchEvent(ev)
    return data
  }

  function roundTrip(name) {
    win.setContent(fs.readFileSync(path.join(fixturesDir, name), 'utf8'))
    const original = saved()
    const clipboard = copyAll()
    assert.match(clipboard['text/html'] || '', /data-pm-slice/, 'the copy went through ProseMirror')
    win.setContent('<!-- wp:paragraph -->\n<p></p>\n<!-- /wp:paragraph -->')
    editor.commands.focus('end')
    paste(clipboard)
    return { original, pasted: saved() }
  }

  for (const name of fs.readdirSync(fixturesDir).filter(f => f.endsWith('.html')).sort()) {
    test(`${name} pastes back exactly as it saved`, () => {
      const { original, pasted } = roundTrip(name)
      assert.doesNotMatch(pasted, /data-pm-slice/)
      assert.equal(pasted, original)
      assert.deepEqual(problems(pasted), problems(original), pasted)
    })
  }

  test('a copy holding a line break is still recognised as Quill\'s own', () => {
    const original = '<!-- wp:paragraph {"metadata":{"name":"Intro"},"backgroundColor":"accent"} -->\n<p class="has-accent-background-color has-background">one<br>two</p>\n<!-- /wp:paragraph -->'
    win.setContent(original)
    const before = saved()
    const clipboard = copyAll()
    win.setContent('<!-- wp:paragraph -->\n<p></p>\n<!-- /wp:paragraph -->')
    editor.commands.focus('end')
    paste(clipboard)
    assert.equal(saved(), before)
  })

  const foreign = '<p data-pm-slice="1 1 []" style="text-align:center">Centered</p>' +
    '<h2 class="heading-anchor" style="color:red">Head</h2><p><span style="font-weight:bold">Bold</span></p>'

  test("another ProseMirror editor's copy is cleaned like any outside paste", () => {
    win.setContent('<!-- wp:paragraph -->\n<p></p>\n<!-- /wp:paragraph -->')
    editor.commands.focus('end')
    paste({ 'text/html': foreign, 'text/plain': 'Centered\n\nHead\n\nBold' })
    const pasted = saved()
    assert.doesNotMatch(pasted, /style="|<span|data-pm-slice|heading-anchor/)
    assert.match(pasted, /<strong>Bold<\/strong>/)
    assert.deepEqual(problems(pasted), [], pasted)
  })

  test('the same markup pasted right after a Quill copy of other text is still cleaned', () => {
    win.setContent('<!-- wp:paragraph -->\n<p>Something else</p>\n<!-- /wp:paragraph -->')
    copyAll()
    win.setContent('<!-- wp:paragraph -->\n<p></p>\n<!-- /wp:paragraph -->')
    editor.commands.focus('end')
    paste({ 'text/html': foreign, 'text/plain': 'Centered\n\nHead\n\nBold' })
    assert.doesNotMatch(saved(), /style="|<span|heading-anchor/)
  })

  test('Paste as Markdown cleans raw HTML that carries the marker', () => {
    editor.commands.setContent('<p></p>')
    editor.commands.focus('end')
    win.insertMarkdown('<p data-pm-slice="1 1 []"><span style="color:red">Red</span> text</p>')
    const pasted = saved()
    assert.doesNotMatch(pasted, /style="|<span|data-pm-slice/)
    assert.match(pasted, /Red text/)
  })
})

// A selection dragged or ⇧↓-extended to the start of the next line ends inside the next block.
// Pasted over, that block was joined into the last pasted block: a code block became list text,
// and Tiptap's paste rules then turned its literal **stars** into bold. The block after the
// selection is left where it was.
describe('a paste over a selection that ends at the start of the next block', () => {
  test('leaves the next block and its text alone', () => {
    editor.commands.setContent('<p>BBB</p><p>CCC</p><pre><code>**not bold** code</code></pre>')
    const codeStart = editor.state.doc.child(0).nodeSize + editor.state.doc.child(1).nodeSize + 1
    editor.commands.setTextSelection({ from: 2, to: codeStart })
    paste({ 'text/html': '<h2>Pasted</h2><ul><li>item</li></ul>', 'text/plain': 'Pasted\nitem' })
    assert.match(doc(), /codeBlock\("\*\*not bold\*\* code"\)$/)
    assert.doesNotMatch(doc(), /listItem\(paragraph\("item\*\*not bold/)
  })

  test('a plain-text paste leaves it alone too', () => {
    editor.commands.setContent('<p>BBB</p><p>CCC</p><p>DDD</p>')
    const dddStart = editor.state.doc.child(0).nodeSize + editor.state.doc.child(1).nodeSize + 1
    editor.commands.setTextSelection({ from: 2, to: dddStart })
    paste({ 'text/plain': 'one\n\ntwo' })
    assert.match(doc(), /paragraph\("DDD"\)$/)
  })

  test('a separator inside the selection survives, being outside what the paste replaces', () => {
    editor.commands.setContent('<p>BBB</p><hr><p>CCC</p>')
    const cccStart = editor.state.doc.child(0).nodeSize + editor.state.doc.child(1).nodeSize + 1
    editor.commands.setTextSelection({ from: 2, to: cccStart })
    paste({ 'text/plain': 'x' })
    assert.equal(doc(), 'paragraph("Bx") | horizontalRule() | paragraph("CCC")')
  })

  test('Paste as Markdown over it leaves the next block alone too', () => {
    editor.commands.setContent('<p>BBB</p><p>CCC</p><pre><code>**not bold** code</code></pre>')
    const codeStart = editor.state.doc.child(0).nodeSize + editor.state.doc.child(1).nodeSize + 1
    editor.commands.setTextSelection({ from: 2, to: codeStart })
    win.insertMarkdown('## Pasted\n\n- item')
    assert.match(doc(), /codeBlock\("\*\*not bold\*\* code"\)$/)
  })

  test('a selection that ends inside the next block still joins it', () => {
    editor.commands.setContent('<p>BBB</p><p>CCC</p>')
    editor.commands.setTextSelection({ from: 2, to: editor.state.doc.child(0).nodeSize + 3 })
    paste({ 'text/plain': 'x' })
    assert.equal(doc(), 'paragraph("BxC")')
  })
})

// Core's table cells are rich text. Blocks pasted into one went in as blocks, so the saved cell
// held a heading, paragraphs and a list, and a table pasted into a cell nested a table in it.
// They become lines, as the blocks inside a pasted table's own cells already do.
describe('blocks pasted into a table cell become lines', () => {
  const inCell = () => {
    editor.commands.setContent('<table><tr><td><p>a1</p></td><td><p>b1</p></td></tr></table><p>after</p>')
    editor.commands.setTextSelection(6)
  }

  test('a heading, paragraphs and a list become lines with breaks', () => {
    inCell()
    paste({ 'text/html': '<h2>Cell heading</h2><p>First</p><ul><li>bullet</li></ul>', 'text/plain': 'Cell heading\nFirst\nbullet' })
    assert.match(doc(), /tableCell\(paragraph\("a1Cell heading",BR,"First",BR,"bullet"\)\)/)
    assert.doesNotMatch(doc(), /heading\(|bulletList\(/)
  })

  // A table on its own is cells: ProseMirror fills the grid from the caret's cell, as before.
  test('a pasted table still fills the grid from the cell', () => {
    inCell()
    paste({ 'text/html': '<table><tr><td>x</td><td>y</td></tr></table>', 'text/plain': 'x\ty' })
    assert.match(doc(), /^table\(tableRow\(tableCell\(paragraph\("x"\)\),tableCell\(paragraph\("y"\)\)\)\)/)
  })

  test('a cell range copied in the editor still fills the grid', () => {
    editor.commands.setContent('<table><tr><td><p>a</p></td><td><p>b</p></td></tr></table><p>gap</p><table><tr><td><p>1</p></td><td><p>2</p></td></tr></table>')
    const cells = []
    editor.state.doc.descendants((n, p) => { if (n.type.name === 'tableCell') cells.push(p) })
    editor.commands.setCellSelection({ anchorCell: cells[0], headCell: cells[1] })
    const clip = copy()
    editor.commands.setTextSelection(cells[2] + 2)
    paste(clip)
    assert.match(doc(), /paragraph\("gap"\) \| table\(tableRow\(tableCell\(paragraph\("a"\)\),tableCell\(paragraph\("b"\)\)\)\)/)
  })

  test('Paste as Markdown into a cell writes lines too', () => {
    inCell()
    win.insertMarkdown('## Head\n\npara\n\n- item')
    assert.doesNotMatch(doc(), /heading\(|bulletList\(/)
    assert.match(doc(), /tableCell\(paragraph\("a1Head",BR,"para",BR,"item"\)\)/)
  })

  test('one line of inline HTML in a cell is unchanged', () => {
    inCell()
    paste({ 'text/html': '<b>bold</b> text', 'text/plain': 'bold text' })
    assert.match(doc(), /tableCell\(paragraph\("a1","bold"," text"\)\)/)
  })
})
