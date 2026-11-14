'use strict'

// Live Tiptap tests for core/footnotes. WordPress stores footnote bodies in post
// meta and renders the <ol> server-side, so the split crosses setContent,
// getContent, getFootnotes and the footnoteSync plugin — none of which the pure
// editor-transforms.js helpers reach.

const { test, describe, before, after } = require('node:test')
const assert = require('node:assert/strict')
const { JSDOM, VirtualConsole } = require('jsdom')
const fs = require('fs')
const path = require('path')
const nodeCrypto = require('crypto')

const htmlPath = path.resolve(__dirname, '../Sources/QuillKit/Resources/editor.html')
const source = fs.readFileSync(htmlPath, 'utf8')

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

const ID = 'fn-11111111-2222-4333-8444-555555555555'
const ID2 = 'fn-99999999-8888-4777-8666-555555555555'
const marker = id => `<sup data-fn="${id}" class="fn" id="${id}-link"><a href="#${id}">1</a></sup>`
const META = id => JSON.stringify([{ id, content: 'A <em>note</em>.' }])

describe('the transform helpers reach the editor as globals', () => {
  test('extractFootnotes and inlineFootnotes are callable in the page', () => {
    assert.equal(typeof win.extractFootnotes, 'function')
    assert.equal(typeof win.inlineFootnotes, 'function')
  })
})

describe('loading a post with native footnotes', () => {
  test('the delimiter plus meta becomes an editable list', () => {
    win.setContent(`<!-- wp:paragraph -->\n<p>Body${marker(ID)}</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`, META(ID))
    const html = editor.getHTML()
    assert.match(html, /wp-block-footnotes/)
    assert.match(html, /A <em>note<\/em>\./)
  })

  test('the footnotes block is not frozen into an unsupported card', () => {
    win.setContent(`<!-- wp:paragraph -->\n<p>Body${marker(ID)}</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`, META(ID))
    assert.doesNotMatch(editor.getHTML(), /wp-block-quill-unsupported/)
    assert.doesNotMatch(editor.getHTML(), /Not editable/)
  })

  test('a delimiter with no meta is preserved as a passthrough card instead', () => {
    win.setContent('<!-- wp:paragraph -->\n<p>Body</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->', '[]')
    assert.match(editor.getHTML(), /wp-block-quill-unsupported/)
  })

  test('markers with no meta load as an editable list with an empty note each, and no card', () => {
    win.setContent(`<!-- wp:paragraph -->\n<p>Body${marker(ID)}</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`, '[]')
    const types = []
    editor.state.doc.forEach(n => types.push(n.type.name))
    assert.deepEqual(types, ['paragraph', 'footnotesList'])
    assert.equal(editor.state.doc.lastChild.childCount, 1)
  })

  test('a note written for such a marker saves with one delimiter and no stray paragraph', () => {
    win.setContent(`<!-- wp:paragraph -->\n<p>Body${marker(ID)}</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`, '[]')
    editor.commands.insertContentAt(editor.state.doc.content.size - 2, 'Written.')
    win.syncContentToSwift()
    assert.equal(win.getContent(), `<!-- wp:paragraph -->\n<p>Body${marker(ID)}</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`)
    assert.deepEqual(JSON.parse(win.getFootnotes()), [{ id: ID, content: 'Written.' }])
  })
})

describe('saving', () => {
  test('post_content carries the delimiter, never the list', () => {
    win.setContent(`<!-- wp:paragraph -->\n<p>Body${marker(ID)}</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`, META(ID))
    editor.commands.insertContentAt(1, 'x')
    const content = win.getContent()
    assert.match(content, /<!-- wp:footnotes \/-->/)
    assert.doesNotMatch(content, /wp-block-footnotes/)
  })

  test('getFootnotes returns the bodies as core stores them', () => {
    win.setContent(`<!-- wp:paragraph -->\n<p>Body${marker(ID)}</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`, META(ID))
    editor.commands.insertContentAt(1, 'x')
    win.syncContentToSwift()
    assert.deepEqual(JSON.parse(win.getFootnotes()), [{ id: ID, content: 'A <em>note</em>.' }])
  })

  test('an edited footnote body reaches the meta', () => {
    win.setContent(`<!-- wp:paragraph -->\n<p>Body${marker(ID)}</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`, META(ID))
    const pos = editor.state.doc.content.size - 2
    editor.commands.insertContentAt(pos, ' Appended.')
    win.syncContentToSwift()
    assert.match(JSON.parse(win.getFootnotes())[0].content, /Appended\./)
  })

  test('the marker keeps core\'s <id>-link anchor so the rendered backref resolves', () => {
    win.setContent(`<!-- wp:paragraph -->\n<p>Body${marker(ID)}</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`, META(ID))
    editor.commands.insertContentAt(1, 'x')
    assert.match(win.getContent(), new RegExp(`id="${ID}-link"`))
  })

  test('no backref is written into post_content — WordPress renders it', () => {
    win.setContent(`<!-- wp:paragraph -->\n<p>Body${marker(ID)}</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`, META(ID))
    editor.commands.insertContentAt(1, 'x')
    assert.doesNotMatch(win.getContent(), /footnote-backref/)
  })

  test('an unedited post saves back byte-identically', () => {
    const src = `<!-- wp:paragraph -->\n<p>Body${marker(ID)}</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`
    win.setContent(src, META(ID))
    assert.equal(win.getContent(), src)
  })

  // inlineFootnotes rebuilt the whole post through innerHTML, re-quoting the source it was meant to keep.
  test('an unsupported block beside footnotes is saved byte for byte after an edit', () => {
    const custom = "<!-- wp:html -->\n<div class='promo' data-x='1'>Hi<br/><img src='a.png'/></div>\n<!-- /wp:html -->"
    const src = `<!-- wp:paragraph -->\n<p>Body${marker(ID)}</p>\n<!-- /wp:paragraph -->\n\n${custom}\n\n<!-- wp:footnotes /-->`
    win.setContent(src, META(ID))
    editor.commands.insertContentAt(1, 'x')
    assert.equal(win.getContent(), src.replace('<p>Body', '<p>xBody'))
  })

  test('load → edit → save is idempotent through a second cycle', () => {
    const src = `<!-- wp:paragraph -->\n<p>Body${marker(ID)}</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`
    win.setContent(src, META(ID))
    editor.commands.insertContentAt(1, 'x')
    const once = win.getContent()
    const meta = win.getFootnotes()
    win.setContent(once, meta)
    assert.equal(win.getContent(), once)
    assert.deepEqual(JSON.parse(win.getFootnotes()), JSON.parse(meta))
  })

  test('deleting the last marker clears the meta rather than stranding it', () => {
    win.setContent(`<!-- wp:paragraph -->\n<p>B${marker(ID)}</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`, META(ID))
    let markerPos = null
    editor.state.doc.descendants((node, pos) => {
      if (node.type.name === 'footnoteMarker') markerPos = pos
    })
    editor.commands.deleteRange({ from: markerPos, to: markerPos + 1 })
    win.syncContentToSwift()
    assert.deepEqual(JSON.parse(win.getFootnotes()), [])
    assert.doesNotMatch(win.getContent(), /wp-block-footnotes/)
  })
})

describe('migrating a legacy inline list', () => {
  const legacy = `<!-- wp:paragraph -->\n<p>Body${marker(ID)}</p>\n<!-- /wp:paragraph -->\n` +
    `<ol class="wp-block-footnotes"><li id="${ID}">Old note<a href="#ref-${ID}" class="footnote-backref">↩︎</a></li></ol>`

  test('an untouched legacy post is left exactly as it was', () => {
    win.setContent(legacy, '')
    assert.equal(win.getContent(), legacy)
    assert.deepEqual(JSON.parse(win.getFootnotes()), [])
  })

  test('the first edit moves the bodies into meta and the list out of the content', () => {
    win.setContent(legacy, '')
    editor.commands.insertContentAt(1, 'x')
    win.syncContentToSwift()
    assert.deepEqual(JSON.parse(win.getFootnotes()), [{ id: ID, content: 'Old note' }])
    assert.match(win.getContent(), /<!-- wp:footnotes \/-->/)
    assert.doesNotMatch(win.getContent(), /wp-block-footnotes/)
  })

  test('the legacy backref anchor does not survive into the meta', () => {
    win.setContent(legacy, '')
    editor.commands.insertContentAt(1, 'x')
    win.syncContentToSwift()
    assert.doesNotMatch(win.getFootnotes(), /footnote-backref/)
  })
})

describe('two footnotes', () => {
  const two = `<!-- wp:paragraph -->\n<p>A${marker(ID)} B${marker(ID2)}</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`
  const meta = JSON.stringify([{ id: ID, content: 'First' }, { id: ID2, content: 'Second' }])

  test('both bodies load in meta order', () => {
    win.setContent(two, meta)
    const html = editor.getHTML()
    assert.ok(html.indexOf('First') < html.indexOf('Second'))
  })

  test('both survive a save round trip in order', () => {
    win.setContent(two, meta)
    editor.commands.insertContentAt(1, 'x')
    win.syncContentToSwift()
    assert.deepEqual(JSON.parse(win.getFootnotes()).map(f => f.content), ['First', 'Second'])
  })

  test('markers are renumbered 1, 2 in the saved content', () => {
    win.setContent(two, meta)
    editor.commands.insertContentAt(1, 'x')
    const content = win.getContent()
    assert.ok(content.indexOf('>1</a>') < content.indexOf('>2</a>'))
  })
})

// cpoteet/Quill#25. Every copy, cut and paste below goes through the editor's real handlers.
describe('copying and pasting a footnote marker', () => {
  const SRC = `<!-- wp:paragraph -->\n<p>One sentence${marker(ID)}.</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:paragraph -->\n<p>Other</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`
  const NOTE = 'A <em>note</em>.'
  const clipboardEvent = (type, data) => {
    const ev = new win.Event(type, { bubbles: true, cancelable: true })
    Object.defineProperty(ev, 'clipboardData', {
      value: { setData: (t, v) => { data[t] = v }, getData: t => data[t] || '', clearData: () => {}, types: Object.keys(data), files: [] },
    })
    editor.view.dom.dispatchEvent(ev)
    return data
  }
  const copy = type => clipboardEvent(type || 'copy', {})
  const paste = data => clipboardEvent('paste', data)
  const firstSentence = () => editor.commands.setTextSelection({ from: 1, to: editor.state.doc.child(0).nodeSize - 1 })
  const endOfOther = () => {
    let at = null
    editor.state.doc.descendants((n, pos) => { if (n.type.name === 'paragraph' && n.textContent.startsWith('Other')) at = pos + 1 + n.content.size })
    editor.commands.setTextSelection(at)
  }
  // The save, read as the front end will: each marker's id, its anchor id and its link, and the meta.
  const saved = () => {
    win.syncContentToSwift()
    const content = win.getContent()
    return {
      ids: [...content.matchAll(/data-fn="([^"]+)"/g)].map(m => m[1]),
      anchors: [...content.matchAll(/ id="([^"]+)-link"/g)].map(m => m[1]),
      links: [...content.matchAll(/href="#([^"]+)"/g)].map(m => m[1]),
      meta: JSON.parse(win.getFootnotes()),
    }
  }
  const assertSeparateNotes = (s, count) => {
    assert.equal(new Set(s.ids).size, count, s.ids.join(' '))
    assert.deepEqual(s.anchors, s.ids)
    assert.deepEqual(s.links, s.ids)
    assert.deepEqual(s.meta.map(f => f.id), s.ids)
  }

  test('a pasted copy gets an id of its own and a copy of the note', () => {
    win.setContent(SRC, META(ID))
    firstSentence()
    const clipboard = copy()
    endOfOther()
    paste(clipboard)
    const s = saved()
    assertSeparateNotes(s, 2)
    assert.equal(s.ids[0], ID)
    assert.deepEqual(s.meta.map(f => f.content), [NOTE, NOTE])
    assert.match(s.ids[1], /^fn-[0-9a-f-]{36}$/)
  })

  test('one undo removes the paste and its new note', () => {
    win.setContent(SRC, META(ID))
    const before = editor.getJSON()
    firstSentence()
    const clipboard = copy()
    endOfOther()
    paste(clipboard)
    editor.commands.undo()
    assert.deepEqual(editor.getJSON(), before)
    assert.deepEqual(saved().meta.map(f => f.id), [ID])
  })

  test('the marker already in the post keeps its id when the copy goes in before it', () => {
    win.setContent(SRC, META(ID))
    firstSentence()
    const clipboard = copy()
    editor.commands.setTextSelection(1)
    paste(clipboard)
    const s = saved()
    assertSeparateNotes(s, 2)
    assert.equal(s.ids[1], ID)
  })

  test('pasting twice gives three separate notes', () => {
    win.setContent(SRC, META(ID))
    firstSentence()
    const clipboard = copy()
    endOfOther()
    paste(clipboard)
    paste(clipboard)
    const s = saved()
    assertSeparateNotes(s, 3)
    assert.deepEqual(s.meta.map(f => f.content), [NOTE, NOTE, NOTE])
  })

  test('the whole post copied and pasted into itself keeps one footnotes list', () => {
    win.setContent(SRC, META(ID))
    editor.commands.selectAll()
    const clipboard = copy()
    endOfOther()
    paste(clipboard)
    assert.equal(editor.getJSON().content.filter(n => n.type === 'footnotesList').length, 1)
    assert.equal(editor.state.doc.lastChild.type.name, 'footnotesList')
    const s = saved()
    assertSeparateNotes(s, 2)
    assert.deepEqual(s.meta.map(f => f.content), [NOTE, NOTE])
  })

  test('a pasted copy of the whole post never replaces the post\'s own list, or a note edited since the copy', () => {
    const src = `<!-- wp:paragraph -->\n<p>One sentence${marker(ID)}.</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->\n\n<!-- wp:paragraph -->\n<p>After</p>\n<!-- /wp:paragraph -->`
    win.setContent(src, META(ID))
    editor.commands.selectAll()
    const clipboard = copy()
    let item = null
    editor.state.doc.descendants((n, pos) => { if (n.type.name === 'footnoteItem') item = pos + n.nodeSize - 1 })
    editor.commands.setTextSelection(item)
    editor.commands.insertContent(' Edited')
    let after = null
    editor.state.doc.descendants((n, pos) => { if (n.type.name === 'paragraph' && n.textContent === 'After') after = pos + 1 + n.content.size })
    editor.commands.setTextSelection(after)
    paste(clipboard)
    assert.equal(editor.getJSON().content.filter(n => n.type === 'footnotesList').length, 1)
    const content = win.getContent()
    assert.ok(content.indexOf('<!-- wp:footnotes /-->') < content.indexOf('After'), content)
    const s = saved()
    assertSeparateNotes(s, 2)
    assert.equal(s.meta[0].id, ID)
    assert.match(s.meta[0].content, /Edited$/)
  })

  test('a sentence cut and pasted elsewhere keeps its id and its note', () => {
    win.setContent(SRC, META(ID))
    firstSentence()
    const clipboard = copy('cut')
    endOfOther()
    paste(clipboard)
    const s = saved()
    assert.deepEqual(s.ids, [ID])
    assert.deepEqual(s.meta, [{ id: ID, content: NOTE }])
  })

  test('a note cut in one post never comes back in another post', () => {
    win.setContent(SRC, META(ID))
    firstSentence()
    const clipboard = copy('cut')
    win.setContent('<!-- wp:paragraph -->\n<p>Another post</p>\n<!-- /wp:paragraph -->', '[]')
    editor.commands.setTextSelection(editor.state.doc.child(0).nodeSize - 1)
    paste(clipboard)
    assert.deepEqual(saved().meta, [{ id: ID, content: '' }])
  })

  test('a marker pasted into a footnote entry is dropped, and the text goes in', () => {
    win.setContent(SRC, META(ID))
    firstSentence()
    const clipboard = copy()
    let item = null
    editor.state.doc.descendants((n, pos) => { if (n.type.name === 'footnoteItem') item = pos })
    editor.commands.setTextSelection(item + 2)
    paste(clipboard)
    const s = saved()
    assert.deepEqual(s.ids, [ID])
    assert.deepEqual(s.meta, [{ id: ID, content: 'AOne sentence. <em>note</em>.' }])
  })

  // jsdom has no layout, so the drop point comes from a stubbed posAtCoords; the rest is
  // ProseMirror's own drop handler.
  test('a dropped copy gets an id of its own too', () => {
    win.setContent(SRC, META(ID))
    firstSentence()
    const clipboard = copy()
    let at = null
    editor.state.doc.descendants((n, pos) => { if (n.type.name === 'paragraph' && n.textContent === 'Other') at = pos + 6 })
    const original = editor.view.posAtCoords
    editor.view.posAtCoords = () => ({ pos: at, inside: -1 })
    try {
      const ev = new win.Event('drop', { bubbles: true, cancelable: true })
      Object.defineProperty(ev, 'dataTransfer', { value: { getData: t => clipboard[t] || '', types: Object.keys(clipboard), files: [] } })
      editor.view.dom.dispatchEvent(ev)
    } finally {
      editor.view.posAtCoords = original
    }
    const s = saved()
    assertSeparateNotes(s, 2)
    assert.equal(s.ids[0], ID)
    assert.deepEqual(s.meta.map(f => f.content), [NOTE, NOTE])
  })

  test('a post that loads with a repeated id saves as it was, and typing leaves the ids alone', () => {
    const dup = `<!-- wp:paragraph -->\n<p>A${marker(ID)} B${marker(ID)}</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`
    win.setContent(dup, META(ID))
    assert.equal(win.getContent(), dup)
    editor.commands.insertContentAt(1, 'x')
    assert.deepEqual(saved().ids, [ID, ID])
  })
})

describe('inserting a brand-new footnote', () => {
  test('a post with none gains the delimiter and a meta entry', () => {
    win.setContent('<!-- wp:paragraph -->\n<p>Body</p>\n<!-- /wp:paragraph -->', '')
    editor.commands.focus('end')
    win.insertFootnote()
    win.syncContentToSwift()
    const meta = JSON.parse(win.getFootnotes())
    assert.equal(meta.length, 1)
    assert.match(win.getContent(), /<!-- wp:footnotes \/-->/)
    assert.doesNotMatch(win.getContent(), /wp-block-footnotes/)
  })

  test('its marker anchors to the id core will render the backref for', () => {
    win.setContent('<!-- wp:paragraph -->\n<p>Body</p>\n<!-- /wp:paragraph -->', '')
    editor.commands.focus('end')
    win.insertFootnote()
    win.syncContentToSwift()
    const id = JSON.parse(win.getFootnotes())[0].id
    assert.match(win.getContent(), new RegExp(`<sup data-fn="${id}" class="fn" id="${id}-link">`))
  })

  test('typing into it reaches the meta body', () => {
    win.setContent('<!-- wp:paragraph -->\n<p>Body</p>\n<!-- /wp:paragraph -->', '')
    editor.commands.focus('end')
    win.insertFootnote()
    editor.commands.insertContent('Fresh note.')
    win.syncContentToSwift()
    assert.equal(JSON.parse(win.getFootnotes())[0].content, 'Fresh note.')
  })
})

describe('code view shows what will actually be saved', () => {
  const codeView = () => win.document.getElementById('code-editor')
  const toggle = () => win.document.getElementById('btn-code-view').dispatchEvent(
    new win.Event('click', { bubbles: true }))

  test('after a visual edit it shows the delimiter, not the list', () => {
    win.setContent(`<!-- wp:paragraph -->\n<p>Body${marker(ID)}</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`, META(ID))
    editor.commands.insertContentAt(1, 'x')
    toggle()
    const src = codeView().value
    toggle()
    assert.match(src, /<!-- wp:footnotes \/-->/)
    assert.doesNotMatch(src, /wp-block-footnotes/)
  })

  test('a freshly inserted footnote is not shown as a list either', () => {
    win.setContent('<!-- wp:paragraph -->\n<p>Body</p>\n<!-- /wp:paragraph -->', '')
    editor.commands.focus('end')
    win.insertFootnote()
    editor.commands.insertContent('Fresh note.')
    toggle()
    const src = codeView().value
    toggle()
    assert.doesNotMatch(src, /wp-block-footnotes/)
    assert.doesNotMatch(src, /Fresh note\./)
  })

  test('entering and leaving code view without editing keeps the meta', () => {
    win.setContent(`<!-- wp:paragraph -->\n<p>Body${marker(ID)}</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`, META(ID))
    editor.commands.insertContentAt(1, 'x')
    toggle()
    toggle()
    assert.deepEqual(JSON.parse(win.getFootnotes()), [{ id: ID, content: 'A <em>note</em>.' }])
  })

  const typeInCodeView = source => {
    const sent = { content: [], footnotes: [] }
    const saved = win.webkit
    win.webkit = { messageHandlers: {
      contentChanged: { postMessage: m => sent.content.push(m) },
      footnotesChanged: { postMessage: m => sent.footnotes.push(m) },
    } }
    try {
      toggle()
      codeView().value = source
      toggle()
    } finally {
      win.webkit = saved
    }
    return { content: sent.content.at(-1), footnotes: JSON.parse(sent.footnotes.at(-1)) }
  }

  test('a footnote list typed in code view reaches the meta', () => {
    win.setContent('<!-- wp:paragraph -->\n<p>Body</p>\n<!-- /wp:paragraph -->', '')
    const sent = typeInCodeView(`<p>Plain paragraph with a note.${marker(ID)}</p>\n<ol class="wp-block-footnotes"><li id="${ID}">Mostly on the support forums.</li></ol>`)
    assert.deepEqual(sent.footnotes, [{ id: ID, content: 'Mostly on the support forums.' }])
    assert.match(sent.content, /<!-- wp:footnotes \/-->/)
    assert.doesNotMatch(sent.content, /wp-block-footnotes/)
    assert.match(editor.getHTML(), /Mostly on the support forums\./)
  })

  test('a footnote id that is not fn-<uuid> keeps its body too', () => {
    win.setContent('<!-- wp:paragraph -->\n<p>Body</p>\n<!-- /wp:paragraph -->', '')
    const sent = typeInCodeView(`<p>Note.${marker('fn1')}</p>\n<ol class="wp-block-footnotes"><li id="fn1">A short note.</li></ol>`)
    assert.deepEqual(sent.footnotes, [{ id: 'fn1', content: 'A short note.' }])
  })

  test('a delimiter typed with the list leaves one delimiter and no card', () => {
    win.setContent('<!-- wp:paragraph -->\n<p>Body</p>\n<!-- /wp:paragraph -->', '')
    const sent = typeInCodeView(`<p>Note.${marker(ID)}</p>\n\n<!-- wp:footnotes /-->\n<ol class="wp-block-footnotes"><li id="${ID}">The body.</li></ol>`)
    assert.equal(sent.content.match(/wp:footnotes/g).length, 1)
    assert.deepEqual(sent.footnotes, [{ id: ID, content: 'The body.' }])
    assert.doesNotMatch(editor.getHTML(), /wp-block-quill-unsupported/)
  })

  test('code view shows the delimiter again after a list was typed there', () => {
    win.setContent('<!-- wp:paragraph -->\n<p>Body</p>\n<!-- /wp:paragraph -->', '')
    typeInCodeView(`<p>Note.${marker(ID)}</p>\n<ol class="wp-block-footnotes"><li id="${ID}">The body.</li></ol>`)
    toggle()
    const src = codeView().value
    toggle()
    assert.match(src, /<!-- wp:footnotes \/-->/)
    assert.doesNotMatch(src, /wp-block-footnotes/)
  })

  test('the list comes back in the visual editor after a code-view round trip', () => {
    win.setContent(`<!-- wp:paragraph -->\n<p>Body${marker(ID)}</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`, META(ID))
    editor.commands.insertContentAt(1, 'x')
    toggle()
    toggle()
    assert.match(editor.getHTML(), /A <em>note<\/em>\./)
  })
})

// jsdom does no layout, so these assert the rules that produce the fix rather
// than the geometry. Verified visually in WebKit on 2026-09-13.
describe('backref chrome in the editor', () => {
  // Hiding the break itself made the item uneditable in WebKit: it is the only
  // caret target an empty inline container has. Regression guard, 2026-09-13.
  test('the trailing break stays in layout so an empty item keeps its caret', () => {
    assert.doesNotMatch(source, /br\.ProseMirror-trailingBreak(:only-child)?\s*\{/)
  })

  test('the backref is hidden while the item is empty rather than wrapping', () => {
    assert.match(source, /li\.fn-item-empty > \.fn-backref\s*\{[^}]*display:\s*none/)
  })

  // WebKit does not re-evaluate :has() when the trailing break is removed, so
  // the backref never reappeared once the user typed. Regression guard.
  test('the empty state is a node-view class, not a :has() on the break', () => {
    assert.doesNotMatch(source, /:has\([^)]*ProseMirror-trailingBreak/)
  })

  test('the class tracks the item emptying and filling', () => {
    win.setContent('<!-- wp:paragraph -->\n<p>Body</p>\n<!-- /wp:paragraph -->', '')
    editor.commands.focus('end')
    win.insertFootnote()
    const li = () => win.document.querySelector('ol.wp-block-footnotes > li')
    assert.ok(li().classList.contains('fn-item-empty'), 'a new footnote starts empty')
    editor.commands.insertContent('Some text')
    assert.ok(!li().classList.contains('fn-item-empty'), 'typing clears the empty class')
  })

  test('the backref and the marker opt out of the ⌘-held underline', () => {
    assert.match(source, /body\.cmd-held \.ProseMirror \.fn-backref[\s\S]{0,120}?text-decoration:\s*none/)
    assert.match(source, /body\.cmd-held \.ProseMirror sup\.fn a[\s\S]{0,120}?text-decoration:\s*none/)
  })

  test('the opt-out is specific enough to beat the ⌘-held rule it overrides', () => {
    const optOut = source.indexOf('body.cmd-held .ProseMirror .fn-backref')
    const affordance = source.indexOf('body.cmd-held .ProseMirror a {')
    assert.ok(affordance !== -1, 'the ⌘-held affordance rule is gone — the opt-out is now dead code')
    assert.ok(optOut > affordance, 'the opt-out must come after the rule it overrides')
  })

  test('a real link keeps the ⌘-held affordance', () => {
    assert.match(source, /body\.cmd-held \.ProseMirror a \{[^}]*text-decoration:\s*underline/)
  })

  // cpoteet/Quill#24 bug 7: the number is the item's list marker, drawn outside the item's box, so
  // a press on it reaches the li itself left of its content. Only the ↩ had a handler. jsdom gives
  // every box a zero rect, so a press left of 0 is on the number and one at 5 is on the note.
  test('a press on a footnote number puts the caret after its marker, a press on the note does not', () => {
    win.setContent('<!-- wp:paragraph -->\n<p>Body text</p>\n<!-- /wp:paragraph -->', '')
    editor.commands.setTextSelection(5)
    win.insertFootnote()
    editor.commands.insertContent('Note')
    let markerEnd = null
    editor.state.doc.descendants((n, pos) => { if (n.type.name === 'footnoteMarker') markerEnd = pos + n.nodeSize })
    const li = win.document.querySelector('ol.wp-block-footnotes > li')
    const press = clientX => {
      const inNote = editor.state.selection.from
      const ev = new win.MouseEvent('mousedown', { bubbles: true, cancelable: true, clientX, clientY: 0, button: 0 })
      li.dispatchEvent(ev)
      return { at: editor.state.selection.from === markerEnd ? 'marker' : editor.state.selection.from === inNote ? 'note' : 'elsewhere', prevented: ev.defaultPrevented }
    }
    const onNote = press(5)
    const onNumber = press(-10)
    win.document.dispatchEvent(new win.MouseEvent('mouseup', { bubbles: true }))
    assert.deepEqual({ onNote, onNumber }, { onNote: { at: 'note', prevented: false }, onNumber: { at: 'marker', prevented: true } })
  })

  test('the backref is still chrome, never serialized into post_content', () => {
    win.setContent(`<!-- wp:paragraph -->\n<p>B${marker(ID)}</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`, META(ID))
    editor.commands.insertContentAt(1, 'x')
    win.syncContentToSwift()
    assert.doesNotMatch(win.getContent(), /fn-backref/)
    assert.doesNotMatch(win.getFootnotes(), /fn-backref/)
  })
})

// One link colour per theme, used by prose links, footnote markers and
// backrefs alike. jsdom does no cascade, so these assert the rules.
describe('link colour is defined once per theme', () => {
  test('both themes are declared as variables on the root and body.dark', () => {
    assert.match(source, /:root\s*\{[^}]*--link:\s*#[0-9a-f]{6};/i)
    assert.match(source, /body\.dark\s*\{[^}]*--link:\s*#[0-9a-f]{6};/i)
  })

  test('prose links, footnote markers and backrefs all read the variable', () => {
    assert.match(source, /\.ProseMirror a \{ color: var\(--link\); \}/)
    assert.match(source, /sup\.fn a \{[^}]*color:\s*var\(--link\)/)
    assert.match(source, /\.fn-backref \{[^}]*color:\s*var\(--link\)/)
  })

  // Light prose links had no rule at all and fell through to WebKit's #0000EE,
  // while markers and backrefs used the amber accent. Regression guard.
  test('no link still carries a hard-coded colour', () => {
    assert.doesNotMatch(source, /\.ProseMirror a \{[^}]*color:\s*#/)
    assert.doesNotMatch(source, /\.fn-backref \{[^}]*color:\s*#/)
    assert.doesNotMatch(source, /body\.dark \.fn-backref\s*\{[^}]*color/)
    assert.doesNotMatch(source, /sup\.fn a \{[^}]*color:\s*#/)
  })
})

describe('code blocks in dark mode', () => {
  test('a code block\'s text has no inline-code shading', () => {
    win.setDarkMode(true)
    try {
      win.setContent('<!-- wp:code -->\n<pre class="wp-block-code"><code>let x = 1</code></pre>\n<!-- /wp:code -->', '[]')
      const code = editor.view.dom.querySelector('pre code')
      assert.equal(win.getComputedStyle(code).backgroundColor, 'rgba(0, 0, 0, 0)')
    } finally {
      win.setDarkMode(false)
    }
  })
})

// The selection ring, resize handles and caret all read these two. A theme that
// declares only one leaves the other resolving to nothing in that theme.
describe('accent and caret are defined once per theme', () => {
  test('both variables are declared on :root and on body.dark', () => {
    assert.match(source, /:root\s*\{[^}]*--accent:\s*#[0-9a-f]{6};/i)
    assert.match(source, /:root\s*\{[^}]*--caret:\s*#[0-9a-f]{6};/i)
    assert.match(source, /body\.dark\s*\{[^}]*--accent:\s*#[0-9a-f]{6};/i)
    assert.match(source, /body\.dark\s*\{[^}]*--caret:\s*#[0-9a-f]{6};/i)
  })

  test('the caret and the selection outline read the variables', () => {
    assert.match(source, /caret-color:\s*var\(--caret\)/)
    assert.match(source, /outline:\s*2px solid var\(--accent\)/)
  })

  test('the caret never carries a literal colour', () => {
    assert.doesNotMatch(source, /caret-color:\s*#/)
  })

  test('every selection and focus ring uses the accent variable', () => {
    assert.doesNotMatch(source, /outline:\s*2px solid #[0-9a-f]{6}/i)
  })
})
