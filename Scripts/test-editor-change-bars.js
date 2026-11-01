'use strict'

// Loads the real editor.html in jsdom and checks the change bars: docs/superpowers/specs/2026-10-31-change-bars-design.md.

const { test, describe, before, after } = require('node:test')
const assert = require('node:assert/strict')
const { JSDOM, VirtualConsole } = require('jsdom')
const fs = require('fs')
const path = require('path')
const nodeCrypto = require('crypto')

const htmlPath = path.resolve(__dirname, '../Sources/QuillKit/Resources/editor.html')
const fixturesDir = path.resolve(__dirname, 'fixtures')

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
  // A dispatch scrolls the selection into view, and jsdom gives text no geometry.
  const rect = { top: 0, left: 0, bottom: 0, right: 0, width: 0, height: 0 }
  for (const proto of [win.Text.prototype, win.Range.prototype]) {
    if (proto.getClientRects) continue
    proto.getClientRects = () => Object.assign([rect], { item: () => rect })
    proto.getBoundingClientRect = () => rect
  }
  win.webkit = { messageHandlers: { contentChanged: { postMessage() {} } } }

  editor = await new Promise((resolve, reject) => {
    let tries = 0
    const t = setInterval(() => {
      if (win._tiptapEditor) { clearInterval(t); resolve(win._tiptapEditor) }
      else if (++tries > 400) { clearInterval(t); reject(new Error('editor never became ready.\n' + logs.join('\n'))) }
    }, 25)
  })
})

after(() => { if (win) win.close() })

const TRAILING = () => new Set(['table', 'galleryBlock', 'embedBlock', 'gutenbergPassthrough', 'horizontalRule'])
const doc = () => editor.state.doc
const marksAgainst = baseline => {
  const result = win.changedBlocks(baseline, doc(), TRAILING(), win._changeKeyOf(baseline))
  return { changed: [...result.changed], removedGaps: [...result.removedGaps] }
}
const NONE = { changed: [], removedGaps: [] }

const para = text => `<!-- wp:paragraph -->\n<p>${text}</p>\n<!-- /wp:paragraph -->`
const post = (...texts) => texts.map(para).join('\n\n')

// What Swift holds as cleanContent and cleanFootnotes after a save.
const save = () => win.flushContent()

function loadWithBaseline(html, footnotes = '[]') {
  win.setContent(html, footnotes)
  return win._buildChangeBaseline(html, footnotes)
}

const startOf = index => win.topLevelPos(doc(), index)
const typeInto = (index, text) => editor.view.dispatch(editor.state.tr.insertText(text, startOf(index) + 1))
const deleteBlocks = (from, to) => editor.view.dispatch(editor.state.tr.delete(startOf(from), startOf(to)))

function lastBodyIndex() {
  return doc().lastChild.type.name === 'footnotesList' ? doc().childCount - 2 : doc().childCount - 1
}

function appendParagraph(text) {
  const d = doc()
  const at = d.lastChild.type.name === 'footnotesList' ? d.content.size - d.lastChild.nodeSize : d.content.size
  const p = editor.schema.nodes.paragraph.create(null, editor.schema.text(text))
  editor.view.dispatch(editor.state.tr.insert(at, p))
  return win.topLevelIndexAt(doc(), at + 1)
}

const postFixtures = fs.readdirSync(fixturesDir).filter(f => f.endsWith('.html')).sort()
  .concat(fs.readdirSync(path.join(fixturesDir, 'script-sinks')).filter(f => f.endsWith('.html')).sort().map(f => 'script-sinks/' + f))
const readFixture = name => fs.readFileSync(path.join(fixturesDir, name), 'utf8')

const FN1 = 'fn-11111111-2222-4333-8444-555555555555'
const FN2 = 'fn-99999999-8888-4777-8666-555555555555'
const marker = id => `<sup data-fn="${id}" class="fn" id="${id}-link"><a href="#${id}">1</a></sup>`
const footnotedPost = `${para('One' + marker(FN1) + ' two' + marker(FN2))}\n\n<!-- wp:footnotes /-->`

function assertSaveLeavesOnlyTheEdit(name, source) {
  win.setContent(source, '[]')
  appendParagraph('Z')
  const saved = save()
  const baseline = win._buildChangeBaseline(saved.html, saved.footnotes)
  assert.deepEqual(marksAgainst(baseline), NONE, `${name}: marks straight after the save`)
  const edited = appendParagraph('Y')
  assert.deepEqual(marksAgainst(baseline), { changed: [edited], removedGaps: [] }, `${name}: marks after editing once more`)
}

describe('baseline equals the loaded document', () => {
  test('every post fixture', () => {
    for (const name of postFixtures) {
      const source = readFixture(name)
      assert.deepEqual(marksAgainst(loadWithBaseline(source)), NONE, name)
    }
  })

  test('after a save, only the edited block is marked', () => {
    for (const name of postFixtures) assertSaveLeavesOnlyTheEdit(name, readFixture(name))
  })

  test('accordion, gallery and post-17780 pass the save test', () => {
    for (const name of ['accordion-block.html', 'gallery-block.html', 'post-17780.html']) {
      assert.ok(postFixtures.includes(name), name)
      assertSaveLeavesOnlyTheEdit(name, readFixture(name))
    }
  })

  test('a paragraph saved with trailing spaces is not marked when another block is edited', () => {
    win.setContent(post('Hello', 'B'), '[]')
    editor.view.dispatch(editor.state.tr.insertText('  ', startOf(0) + 1 + 'Hello'.length))
    const saved = save()
    const baseline = win._buildChangeBaseline(saved.html, saved.footnotes)
    assert.deepEqual(marksAgainst(baseline), NONE, 'straight after the save')
    typeInto(1, 'x')
    assert.deepEqual(marksAgainst(baseline), { changed: [1], removedGaps: [] })
  })

  test('footnotes stored out of marker order', () => {
    const footnotes = JSON.stringify([{ id: FN2, content: 'Second.' }, { id: FN1, content: 'First.' }])
    const baseline = loadWithBaseline(footnotedPost, footnotes)
    const list = doc().lastChild
    assert.equal(list.type.name, 'footnotesList')
    assert.deepEqual(Array.from(list.content.content, item => item.attrs.fnId), [FN1, FN2], 'FootnoteSync reordered the list on load')
    assert.deepEqual(marksAgainst(baseline), NONE)
    assertSaveLeavesOnlyTheEdit('footnotes out of order', footnotedPost)
  })

  test('a synced pattern', () => {
    const source = `${para('Before')}\n\n<!-- wp:block {"ref":1234} /-->\n\n${para('After')}`
    const baseline = loadWithBaseline(source)
    assert.deepEqual(marksAgainst(baseline), NONE)
    assertSaveLeavesOnlyTheEdit('synced pattern', source)
  })
})

describe('changedBlocks', () => {
  test('editing a paragraph: one bar, no dot', () => {
    const baseline = loadWithBaseline(post('A', 'B', 'C'))
    typeInto(1, 'x')
    assert.deepEqual(marksAgainst(baseline), { changed: [1], removedGaps: [] })
  })

  test('inserting at the top marks only the new block', () => {
    const baseline = loadWithBaseline(post('A', 'B', 'C'))
    editor.view.dispatch(editor.state.tr.insert(0, editor.schema.nodes.paragraph.create(null, editor.schema.text('New'))))
    assert.deepEqual(marksAgainst(baseline), { changed: [0], removedGaps: [] })
  })

  test('deleting a block leaves a dot and no bars', () => {
    const baseline = loadWithBaseline(post('A', 'B', 'C'))
    deleteBlocks(1, 2)
    assert.deepEqual(marksAgainst(baseline), { changed: [], removedGaps: [1] })
  })

  test('deleting two adjacent blocks leaves one dot', () => {
    const baseline = loadWithBaseline(post('A', 'B', 'C', 'D'))
    deleteBlocks(1, 3)
    assert.deepEqual(marksAgainst(baseline), { changed: [], removedGaps: [1] })
  })

  test('a moved block: a bar at the new place, a dot at the old', () => {
    const baseline = loadWithBaseline(post('A', 'B', 'C', 'D'))
    const result = win.moveTopLevelBlocks(editor.state, 0, 1, 4, TRAILING())
    editor.view.dispatch(result.tr)
    assert.equal(doc().child(3).textContent, 'A')
    assert.deepEqual(marksAgainst(baseline), { changed: [3], removedGaps: [0] })
  })

  test('undo back to the original: no marks', () => {
    const baseline = loadWithBaseline(post('A', 'B', 'C'))
    typeInto(1, 'x')
    assert.notDeepEqual(marksAgainst(baseline), NONE)
    editor.commands.undo()
    assert.equal(doc().child(1).textContent, 'B')
    assert.deepEqual(marksAgainst(baseline), NONE)
  })

  test('a change inside a Group marks the Group', () => {
    const baseline = loadWithBaseline(`${para('Before')}\n\n${readFixture('settings-group.html')}\n\n${para('After')}`)
    const group = doc().child(1)
    assert.notEqual(group.type.name, 'paragraph')
    let inner = null
    group.descendants((node, pos) => { if (inner === null && node.type.name === 'paragraph') inner = pos })
    editor.view.dispatch(editor.state.tr.insertText('x', startOf(1) + 1 + inner + 1))
    assert.deepEqual(marksAgainst(baseline), { changed: [1], removedGaps: [] })
  })

  test('editing a footnote marks the footnotes list', () => {
    const footnotes = JSON.stringify([{ id: FN1, content: 'First.' }, { id: FN2, content: 'Second.' }])
    const baseline = loadWithBaseline(footnotedPost, footnotes)
    const listIndex = doc().childCount - 1
    assert.equal(doc().child(listIndex).type.name, 'footnotesList')
    let textPos = null
    doc().child(listIndex).descendants((node, pos) => { if (textPos === null && node.isText) textPos = pos })
    editor.view.dispatch(editor.state.tr.insertText('x', startOf(listIndex) + 1 + textPos))
    assert.deepEqual(marksAgainst(baseline), { changed: [listIndex], removedGaps: [] })
  })

  test('the generated trailing paragraph is never marked', () => {
    const baseline = loadWithBaseline(`${para('A')}\n\n<!-- wp:separator -->\n<hr class="wp-block-separator has-alpha-channel-opacity"/>\n<!-- /wp:separator -->`)
    const trailing = win.generatedTrailingIndex(doc(), TRAILING())
    assert.equal(trailing, lastBodyIndex(), 'the editor added a trailing paragraph')
    typeInto(0, 'x')
    assert.deepEqual(marksAgainst(baseline), { changed: [0], removedGaps: [] })
  })
})

describe('bridge', () => {
  const marks = () => {
    const result = win._changeMarks()
    return { changed: [...result.changed], removedGaps: [...result.removedGaps] }
  }
  const restored = () => {
    win.setContent(post('A', 'B2'), '[]')
    win.setChangeBaseline(post('A', 'B'), '[]')
    win.setBodyDirty(true)
  }

  test('no marks before any baseline arrives', () => {
    win.setContent(post('A', 'B2'), '[]')
    win.setBodyDirty(true)
    assert.deepEqual(marks(), NONE)
  })

  test('restored unsaved changes are marked', () => {
    restored()
    assert.deepEqual(marks(), { changed: [1], removedGaps: [] })
  })

  test('no marks while the body is clean', () => {
    restored()
    win.setBodyDirty(false)
    assert.deepEqual(marks(), NONE)
  })

  test('a second baseline replaces the first', () => {
    restored()
    win.setChangeBaseline(post('A', 'B2'), '[]')
    assert.deepEqual(marks(), NONE)
    win.setChangeBaseline(post('A2', 'B2'), '[]')
    assert.deepEqual(marks(), { changed: [0], removedGaps: [] })
  })

  test('marks follow edits after the baseline arrives', () => {
    restored()
    typeInto(0, 'x')
    assert.deepEqual(marks(), { changed: [0, 1], removedGaps: [] })
  })

  test('no marks in code view', () => {
    restored()
    win.document.getElementById('btn-code-view').click()
    try {
      assert.deepEqual(marks(), NONE)
    } finally {
      win.document.getElementById('btn-code-view').click()
    }
    assert.deepEqual(marks(), { changed: [1], removedGaps: [] })
  })

  test('no marks with an overlay open', () => {
    restored()
    win.openFindBar()
    assert.deepEqual(marks(), NONE)
    win.setContent(post('A', 'B2'), '[]')
    win.setChangeBaseline(post('A', 'B'), '[]')
    assert.deepEqual(marks(), { changed: [1], removedGaps: [] }, 'setContent closes the find bar')
  })

  test('loading another post drops the old baseline until its own arrives', () => {
    restored()
    win.setContent(post('X', 'Y'), '[]')
    assert.deepEqual(marks(), NONE)
    win.setChangeBaseline(post('X', 'Y0'), '[]')
    assert.deepEqual(marks(), { changed: [1], removedGaps: [] })
  })

  test('the first paragraph typed in a new empty draft is marked', () => {
    win.setContent('', '[]')
    win.setChangeBaseline('', '[]')
    win.setBodyDirty(true)
    assert.deepEqual(marks(), NONE)
    typeInto(0, 'Hello')
    assert.deepEqual(marks(), { changed: [0], removedGaps: [] })
  })

  test('marks never appear in getContent()', () => {
    restored()
    typeInto(0, 'x')
    const saved = win.getContent()
    assert.doesNotMatch(saved, /change-bar/)
    assert.equal(saved, win.extractFootnotes(win.toWordPressHTML(editor.getHTML())).content)
  })
})

describe('overlay', () => {
  const layer = () => win.document.getElementById('change-bar-layer')
  const wrap = () => win.document.getElementById('editor-wrap')
  const key = k => win.document.dispatchEvent(new win.KeyboardEvent('keydown', { key: k, bubbles: true }))
  const move = buttons => wrap().dispatchEvent(new win.MouseEvent('mousemove', { bubbles: true, buttons, clientX: 5, clientY: 5 }))
  // A edited, C deleted, E deleted: one bar and two dots.
  function drawn() {
    win.setContent(post('A2', 'B', 'D'), '[]')
    win.setChangeBaseline(post('A', 'B', 'C', 'D', 'E'), '[]')
    win.setBodyDirty(true)
    move(0)
    win._changeBars.redraw()
  }

  test('one .change-bar per changed block and one .change-bar-removed per gap', () => {
    drawn()
    assert.equal(layer().querySelectorAll('.change-bar').length, 1)
    assert.equal(layer().querySelectorAll('.change-bar-removed').length, 2)
    win.setBodyDirty(false)
    assert.equal(layer().children.length, 0)
  })

  test('the layer is outside the contenteditable and aria-hidden', () => {
    drawn()
    assert.ok(wrap().contains(layer()))
    assert.ok(!editor.view.dom.contains(layer()))
    assert.equal(layer().getAttribute('aria-hidden'), 'true')
    assert.equal(win.document.getElementById('change-bar-tooltip').parentNode, win.document.body)
  })

  test('marks have pointer-events: none', () => {
    drawn()
    assert.equal(win.getComputedStyle(layer()).pointerEvents, 'none')
    assert.equal(win.getComputedStyle(layer().querySelector('.change-bar')).pointerEvents, 'none')
    assert.equal(win.getComputedStyle(layer().querySelector('.change-bar-removed')).pointerEvents, 'none')
  })

  test('a keypress fades the layer; a mousemove with no buttons shows it', () => {
    drawn()
    assert.ok(!layer().classList.contains('faded'))
    key('a')
    assert.ok(layer().classList.contains('faded'))
    move(1)
    assert.ok(layer().classList.contains('faded'), 'a drag with a button held does not count')
    move(0)
    assert.ok(!layer().classList.contains('faded'))
  })

  test('a modifier key alone does not fade it', () => {
    drawn()
    for (const k of ['Shift', 'Meta', 'Alt', 'Control', 'CapsLock']) key(k)
    assert.ok(!layer().classList.contains('faded'))
  })

  test('isGripHidingKey matches the grip: the grip also hides on "a" and not on "Meta"', () => {
    assert.equal(win.isGripHidingKey({ key: 'a' }), true)
    assert.equal(win.isGripHidingKey({ key: 'Meta' }), false)
    win.setContent(post('A', 'B'), '[]')
    const grip = win.document.getElementById('block-grip')
    win._blockGrip.showFor(0)
    assert.ok(grip.classList.contains('visible'))
    key('Meta')
    assert.ok(grip.classList.contains('visible'))
    key('a')
    assert.ok(!grip.classList.contains('visible'))
  })

  test('opening an overlay clears the drawn marks', async () => {
    drawn()
    assert.equal(layer().children.length, 3)
    win.openFindBar()
    await new Promise(resolve => setTimeout(resolve, 0))
    assert.equal(layer().children.length, 0)
    win.setContent(post('A'), '[]')
  })

  test('a grip drag clears the drawn marks until it ends', () => {
    drawn()
    win.gripDragStart(editor.view, { dataTransfer: { clearData() {}, setDragImage() {} } }, { from: 0, to: 1 })
    win._changeBars.redraw()
    try {
      assert.equal(layer().children.length, 0)
    } finally {
      win.endGripDrag(editor.view)
    }
    win._changeBars.redraw()
    assert.equal(layer().children.length, 3)
  })

  test('a table wider than the column scrolls inside it, so nothing reaches the bars', () => {
    win.setContent(readFixture('settings-table.html'), '[]')
    const table = editor.view.dom.querySelector('table')
    assert.equal(win.getComputedStyle(table).display, 'block')
    assert.equal(win.getComputedStyle(table).overflowX, 'auto')
    assert.equal(win.getComputedStyle(table.querySelector('tbody')).display, 'table', 'the rows still fill the column')
  })

  test('a table that scrolls fades the edges it hides', () => {
    win.setContent(readFixture('settings-table.html'), '[]')
    const style = win.getComputedStyle(editor.view.dom.querySelector('table'))
    assert.match(style.getPropertyValue('mask-image'), /--table-fade-start.*--table-fade-end/)
    assert.equal(style.getPropertyValue('animation-timeline'), 'scroll(x self)')
  })

  test('no marks drawn in code view', () => {
    drawn()
    win.document.getElementById('btn-code-view').click()
    try {
      assert.equal(layer().children.length, 0)
    } finally {
      win.document.getElementById('btn-code-view').click()
    }
  })
})

describe('the WebKit fixture corpus', () => {
  test('reports whether the baseline matched, both as loaded and after a save', () => {
    const source = readFixture('settings-image.html')
    const rows = JSON.parse(JSON.stringify(win.__runFixtureCorpus(JSON.stringify([{ name: 'x', source }]))))
    assert.equal(rows[0].baseline, true)
  })
})
