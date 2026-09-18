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

let editor
let win

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

  editor = await new Promise((resolve, reject) => {
    let tries = 0
    const t = setInterval(() => {
      if (win._tiptapEditor) { clearInterval(t); resolve(win._tiptapEditor) }
      else if (++tries > 400) { clearInterval(t); reject(new Error('editor never became ready.\n' + logs.join('\n'))) }
    }, 25)
  })
})

after(() => { if (win) win.close() })

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

describe('paste into a code block preserves line breaks', () => {
  test('multi-line plain text keeps its newlines inside a code block', () => {
    editor.commands.setContent('<pre><code></code></pre>')
    editor.commands.focus('end')
    paste({ 'text/plain': 'const a = 1\nconst b = 2' })
    assert.equal(doc(), 'codeBlock("const a = 1\\nconst b = 2")')
  })
})
