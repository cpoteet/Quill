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
    assert.match(source, /:root\s*\{\s*--link:\s*#[0-9a-f]{6};\s*\}/i)
    assert.match(source, /body\.dark\s*\{\s*--link:\s*#[0-9a-f]{6};\s*\}/i)
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
