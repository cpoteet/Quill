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
    assert.equal(doc(), 'paragraph("body",MARKER) | footnotesList(footnoteItem("notejust one line"))')
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

  test('a heading still splits into blocks, as in the block editor', () => {
    editor.commands.setContent('<h2>Head</h2>', { emitUpdate: false })
    editor.commands.setTextSelection(5)
    paste({ 'text/plain': 'line one\nline two' })
    assert.equal(doc(), 'heading("Headline one") | paragraph("line two")')
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
      letters: into('<p></p>', 'a. one\nb. two'),
      roman: into('<p></p>', 'i. one\nii. two'),
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
      letters: 'paragraph("a. one") | paragraph("b. two")',
      roman: 'paragraph("i. one") | paragraph("ii. two")',
      skipsANumber: 'paragraph("1. one") | paragraph("3. two")',
      notEveryLine: 'paragraph("1. one") | paragraph("plain")',
      midParagraph: 'paragraph("ab1. one") | paragraph("2. twocd")',
      overText: 'paragraph("a1. one") | paragraph("2. twod")',
      heading: 'heading("Head1. one") | paragraph("2. two")',
      code: 'codeBlock("code1. one\\n2. two")',
      cell: 'table(tableRow(tableCell(paragraph("1. one"),paragraph("2. two")))) | paragraph()',
    })
  })

  test('a Group holding only an empty paragraph keeps the Group', () => {
    win.setContent('<!-- wp:group {"layout":{"type":"constrained"}} -->\n<div class="wp-block-group"><!-- wp:paragraph -->\n<p></p>\n<!-- /wp:paragraph --></div>\n<!-- /wp:group -->')
    editor.commands.setTextSelection(2)
    paste({ 'text/plain': LIST })
    assert.equal(doc(), 'groupBlock(paragraph("1. one"),paragraph("2. two"))')
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
