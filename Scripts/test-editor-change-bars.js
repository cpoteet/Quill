'use strict'

// Loads the real editor.html in jsdom and checks the change bars: docs/superpowers/specs/2026-10-31-change-bars-design.md.

const { test, describe, before, after, afterEach } = require('node:test')
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
// With the moved list. moves names the blocks the author moved, as [index, index of the saved
// block it came from]; every other block's origin is left for the saved HTML to find.
const movesAgainst = (baseline, moves) => {
  const keyOf = win._changeKeyOf(baseline)
  const known = moves && new Map(moves.map(([index, origin]) => [index, { origin, moved: true }]))
  const result = win.changedBlocks(baseline, doc(), TRAILING(), keyOf, known)
  return { changed: [...result.changed], moved: [...result.moved], removedGaps: [...result.removedGaps] }
}
const texts = () => Array.from(doc().content.content, n => n.textContent)
const move = (from, to, gap) => editor.view.dispatch(win.moveTopLevelBlocks(editor.state, from, to, gap, TRAILING()).tr)

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

  test('a moved block: a moved bar at the new place and no dot at the old', () => {
    const baseline = loadWithBaseline(post('A', 'B', 'C', 'D'))
    move(0, 1, 4)
    assert.equal(doc().child(3).textContent, 'A')
    assert.deepEqual(movesAgainst(baseline), { changed: [3], moved: [3], removedGaps: [] })
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

describe('changedBlocks, where the marks fall', () => {
  test('deleting the first block puts the dot above everything', () => {
    const baseline = loadWithBaseline(post('A', 'B', 'C'))
    deleteBlocks(0, 1)
    assert.deepEqual(marksAgainst(baseline), { changed: [], removedGaps: [0] })
  })

  test('deleting the last block puts the dot below everything', () => {
    const baseline = loadWithBaseline(post('A', 'B', 'C'))
    deleteBlocks(2, 3)
    assert.deepEqual(marksAgainst(baseline), { changed: [], removedGaps: [2] })
  })

  test('two removals apart from each other leave two dots', () => {
    const baseline = loadWithBaseline(post('A', 'B', 'C', 'D', 'E'))
    deleteBlocks(3, 4)
    deleteBlocks(1, 2)
    assert.deepEqual(marksAgainst(baseline), { changed: [], removedGaps: [1, 2] })
  })

  test('replacing a block marks the new one and leaves no dot', () => {
    const baseline = loadWithBaseline(post('A', 'B', 'C'))
    editor.view.dispatch(editor.state.tr.insertText('Z', startOf(1) + 1, startOf(1) + 2))
    assert.equal(doc().child(1).textContent, 'Z')
    assert.deepEqual(marksAgainst(baseline), { changed: [1], removedGaps: [] })
  })

  test('deleting one of two identical paragraphs leaves a dot, not a bar', () => {
    const baseline = loadWithBaseline(post('Same', 'Same', 'Other'))
    deleteBlocks(0, 1)
    const marks = marksAgainst(baseline)
    assert.deepEqual(marks.changed, [])
    assert.equal(marks.removedGaps.length, 1)
  })

  test('adding a copy of a paragraph marks one of the two', () => {
    const baseline = loadWithBaseline(post('Same', 'Other'))
    editor.view.dispatch(editor.state.tr.insert(startOf(1), editor.schema.nodes.paragraph.create(null, editor.schema.text('Same'))))
    const marks = marksAgainst(baseline)
    assert.equal(marks.changed.length, 1)
    assert.deepEqual(marks.removedGaps, [])
    assert.equal(doc().child(marks.changed[0]).textContent, 'Same')
  })

  test('swapping two neighbours with no hint marks one block as moved and leaves no dot', () => {
    const baseline = loadWithBaseline(post('A', 'B', 'C'))
    move(0, 1, 2)
    assert.deepEqual(texts(), ['B', 'A', 'C'])
    assert.deepEqual(movesAgainst(baseline), { changed: [0], moved: [0], removedGaps: [] })
  })

  test('a swap marks the block the author moved', () => {
    const baseline = loadWithBaseline(post('A', 'B', 'C'))
    move(0, 1, 2)
    assert.deepEqual(movesAgainst(baseline, [[1, 0]]), { changed: [1], moved: [1], removedGaps: [] }, 'A moved')
    assert.deepEqual(movesAgainst(baseline, [[0, 1]]), { changed: [0], moved: [0], removedGaps: [] }, 'B moved')
    assert.deepEqual(movesAgainst(baseline, [[0, 1], [1, 0]]), { changed: [0], moved: [0], removedGaps: [] }, 'both moved: no preference')
  })

  test('blocks the author never moved are matched first', () => {
    const baseline = loadWithBaseline(post('A', 'B', 'C'))
    move(0, 1, 2)
    move(2, 3, 0)
    assert.deepEqual(texts(), ['C', 'B', 'A'])
    assert.deepEqual(movesAgainst(baseline, [[0, 2], [2, 0]]), { changed: [0, 2], moved: [0, 2], removedGaps: [] }, 'B was never moved')
  })

  test('a two-block run moved past two blocks marks the run the author moved', () => {
    const baseline = loadWithBaseline(post('A', 'B', 'C', 'D', 'E'))
    move(0, 2, 4)
    assert.deepEqual(texts(), ['C', 'D', 'A', 'B', 'E'])
    assert.deepEqual(movesAgainst(baseline, [[2, 0], [3, 1]]), { changed: [2, 3], moved: [2, 3], removedGaps: [] })
  })

  test('a moved block that is then edited is changed, not moved, and leaves no dot', () => {
    const baseline = loadWithBaseline(post('A', 'B', 'C', 'D'))
    move(0, 1, 4)
    typeInto(3, 'x')
    assert.deepEqual(movesAgainst(baseline), { changed: [3], moved: [], removedGaps: [0] }, 'not known to be moved: a dot')
    assert.deepEqual(movesAgainst(baseline, [[3, 0]]), { changed: [3], moved: [], removedGaps: [] }, 'moved from A: no dot')
  })

  test('a move and a deletion from the same gap keep the dot', () => {
    const baseline = loadWithBaseline(post('A', 'B', 'C', 'D'))
    move(0, 1, 4)
    deleteBlocks(0, 1)
    assert.deepEqual(texts(), ['C', 'D', 'A'])
    assert.deepEqual(movesAgainst(baseline), { changed: [2], moved: [2], removedGaps: [0] })
  })

  test('a moved copy of an identical paragraph is still one move', () => {
    const baseline = loadWithBaseline(post('Same', 'A', 'B', 'Same'))
    move(0, 1, 4)
    const marks = movesAgainst(baseline)
    assert.equal(marks.changed.length, 1)
    assert.deepEqual(marks.moved, marks.changed)
    assert.deepEqual(marks.removedGaps, [])
  })

  test('an edit is never a move', () => {
    const baseline = loadWithBaseline(post('A', 'B', 'C'))
    typeInto(1, 'x')
    assert.deepEqual(movesAgainst(baseline), { changed: [1], moved: [], removedGaps: [] })
  })

  test('a block rewritten and another deleted beside it: one bar, no dot at the rewrite', () => {
    const baseline = loadWithBaseline(post('A', 'B', 'C', 'D'))
    typeInto(0, 'x')
    deleteBlocks(3, 4)
    assert.deepEqual(marksAgainst(baseline), { changed: [0], removedGaps: [3] })
  })

  test('the footnotes list is a block of its own, and unchanged it is not marked', () => {
    const footnotes = JSON.stringify([{ id: FN1, content: 'First.' }, { id: FN2, content: 'Second.' }])
    const baseline = loadWithBaseline(footnotedPost, footnotes)
    typeInto(0, 'x')
    assert.deepEqual(marksAgainst(baseline), { changed: [0], removedGaps: [] })
  })
})

describe('moves through the editor', () => {
  const marks = () => {
    const result = win._changeMarks()
    return { changed: [...result.changed], moved: [...result.moved], removedGaps: [...result.removedGaps] }
  }
  const open = html => {
    win.setContent(html, '[]')
    win.setChangeBaseline(html, '[]')
    win.setBodyDirty(true)
  }
  const caretIn = index => editor.commands.setTextSelection(startOf(index) + 1)
  const gripDrop = (from, to) => {
    const transfer = { clearData() {}, setData() {}, setDragImage() {} }
    win.gripDragStart(editor.view, { dataTransfer: transfer }, { from, to })
    const drop = new win.Event('drop', { bubbles: true, cancelable: true })
    Object.defineProperty(drop, 'clientY', { value: 100 })
    win.document.getElementById('editor-wrap').dispatchEvent(drop)
  }
  afterEach(() => win.setBodyDirty(false))

  const columns = `<!-- wp:columns -->\n<div class="wp-block-columns"><!-- wp:column -->\n<div class="wp-block-column">${para('Left')}</div>\n<!-- /wp:column --></div>\n<!-- /wp:columns -->`
  const hero = `<!-- wp:group {"layout":{"type":"constrained"}} -->\n<div class="wp-block-group">${para('Hero')}</div>\n<!-- /wp:group -->`
  const names = () => Array.from(doc().content.content, n => n.type.name)

  test('a grip drag of Columns below a Group marks the Columns, not the Group', () => {
    open([columns, hero].join('\n\n'))
    const [c, g] = names()
    gripDrop(0, 1)
    assert.deepEqual(names(), [g, c])
    assert.deepEqual(marks(), { changed: [1], moved: [1], removedGaps: [] })
  })

  test('Move Block Down past one block marks the moved block, not the one it passed', () => {
    open([columns, hero, para('End')].join('\n\n'))
    const [c, g] = names()
    caretIn(0)
    assert.equal(win.moveBlock('down'), true)
    assert.deepEqual(names().slice(0, 2), [g, c])
    assert.deepEqual(marks(), { changed: [1], moved: [1], removedGaps: [] })
  })

  test('Move Block Up marks the moved block', () => {
    open(post('A', 'B', 'C'))
    caretIn(1)
    assert.equal(win.moveBlock('up'), true)
    assert.deepEqual(texts(), ['B', 'A', 'C'])
    assert.deepEqual(marks(), { changed: [0], moved: [0], removedGaps: [] })
  })

  test('two Move Block Down presses mark only the moved block', () => {
    open(post('A', 'B', 'C', 'D'))
    caretIn(0)
    win.moveBlock('down')
    win.moveBlock('down')
    assert.deepEqual(texts(), ['B', 'C', 'A', 'D'])
    assert.deepEqual(marks(), { changed: [2], moved: [2], removedGaps: [] })
  })

  test('a grip drop past one block marks the dragged block', () => {
    open(post('Columns', 'Hero'))
    gripDrop(0, 1)
    assert.deepEqual(texts(), ['Hero', 'Columns'])
    assert.deepEqual(marks(), { changed: [1], moved: [1], removedGaps: [] })
  })

  test('a section moved past two blocks marks each of its blocks', () => {
    const heading = text => `<!-- wp:heading -->\n<h2 class="wp-block-heading">${text}</h2>\n<!-- /wp:heading -->`
    open([heading('H'), para('A'), heading('I'), para('B')].join('\n\n'))
    gripDrop(0, 2)
    assert.deepEqual(texts(), ['I', 'B', 'H', 'A'])
    assert.deepEqual(marks(), { changed: [2, 3], moved: [2, 3], removedGaps: [] })
  })

  test('editing another block after a move keeps the move mark', () => {
    open(post('A', 'B', 'C'))
    caretIn(0)
    win.moveBlock('down')
    typeInto(2, 'x')
    assert.deepEqual(marks(), { changed: [1, 2], moved: [1], removedGaps: [] })
  })

  test('a block moved back home does not steer a later move', () => {
    open(post('A', 'B', 'C'))
    caretIn(1)
    win.moveBlock('up')
    win.moveBlock('down')
    assert.deepEqual(texts(), ['A', 'B', 'C'])
    caretIn(0)
    win.moveBlock('down')
    assert.deepEqual(texts(), ['B', 'A', 'C'])
    assert.deepEqual(marks(), { changed: [1], moved: [1], removedGaps: [] }, 'A moved')
  })

  test('a move then an undo does not steer a later move', () => {
    open(post('A', 'B', 'C'))
    caretIn(1)
    win.moveBlock('up')
    editor.commands.undo()
    caretIn(0)
    win.moveBlock('down')
    assert.deepEqual(marks(), { changed: [1], moved: [1], removedGaps: [] })
  })

  test('a footnoted paragraph moved past another is moved', () => {
    const html = `${para('One' + marker(FN1))}\n\n${para('Two' + marker(FN2))}\n\n<!-- wp:footnotes /-->`
    const footnotes = JSON.stringify([{ id: FN1, content: 'First.' }, { id: FN2, content: 'Second.' }])
    win.setContent(html, footnotes)
    win.setChangeBaseline(html, footnotes)
    win.setBodyDirty(true)
    caretIn(0)
    win.moveBlock('down')
    assert.ok(texts()[1].startsWith('One'))
    const result = marks()
    assert.deepEqual(result.moved, [1])
    assert.ok(!result.changed.includes(0), 'the paragraph it passed is not marked')
    assert.deepEqual(result.removedGaps, [])
  })

  const editEnd = (index, text) => {
    const node = doc().child(index)
    editor.view.dispatch(editor.state.tr.insertText(text, startOf(index) + 1 + node.content.size))
  }

  test('a Group dragged down, a paragraph edited, then moved below the Group: no dot', () => {
    open([columns, hero, para('Alpha'), para('Beta')].join('\n\n'))
    const names0 = names()
    gripDrop(1, 2)
    assert.deepEqual(names(), [names0[0], 'paragraph', 'paragraph', names0[1]])
    assert.deepEqual(marks(), { changed: [3], moved: [3], removedGaps: [] }, 'the Group moved')
    editEnd(1, 'x')
    assert.deepEqual(marks(), { changed: [1, 3], moved: [3], removedGaps: [] }, 'Alpha edited')
    caretIn(1)
    win.moveBlock('down')
    win.moveBlock('down')
    assert.deepEqual(texts().slice(1), ['Beta', 'Hero', 'Alphax'])
    assert.deepEqual(marks(), { changed: [2, 3], moved: [2], removedGaps: [] }, 'Alpha changed and moved; nothing removed')
  })

  test('an edited block moved: a changed bar and no dot', () => {
    open(post('A', 'B', 'C'))
    editEnd(0, 'x')
    caretIn(0)
    win.moveBlock('down')
    assert.deepEqual(texts(), ['B', 'Ax', 'C'])
    assert.deepEqual(marks(), { changed: [1], moved: [], removedGaps: [] })
  })

  test('a moved block edited afterwards: a changed bar and no dot', () => {
    open(post('A', 'B', 'C'))
    caretIn(0)
    win.moveBlock('down')
    editEnd(1, 'x')
    assert.deepEqual(texts(), ['B', 'Ax', 'C'])
    assert.deepEqual(marks(), { changed: [1], moved: [], removedGaps: [] })
  })

  test('a block the author never moved is never marked as moved', () => {
    open(post('A', 'G', 'B'))
    gripDrop(1, 2)
    assert.deepEqual(texts(), ['A', 'B', 'G'])
    caretIn(0)
    win.moveBlock('down')
    assert.deepEqual(texts(), ['B', 'A', 'G'])
    assert.deepEqual(marks(), { changed: [1, 2], moved: [1, 2], removedGaps: [] }, 'A and G moved, B untouched')
  })

  test('undo and redo of a move and an edit give the same marks back', () => {
    open(post('A', 'B', 'C', 'D'))
    caretIn(0)
    win.moveBlock('down')
    win.moveBlock('down')
    editEnd(2, 'x')
    const before = marks()
    assert.deepEqual(before, { changed: [2], moved: [], removedGaps: [] })
    editor.commands.undo()
    editor.commands.undo()
    editor.commands.undo()
    assert.deepEqual(marks(), { changed: [], moved: [], removedGaps: [] })
    editor.commands.redo()
    editor.commands.redo()
    assert.deepEqual(texts(), ['B', 'C', 'A', 'D'])
    assert.deepEqual(marks(), { changed: [2], moved: [2], removedGaps: [] }, 'redone moves')
    editor.commands.redo()
    assert.deepEqual(marks(), before, 'redone edit')
  })

  test('one undo that puts a block back and reverses an edit to it keeps its origin', () => {
    open(post('A', 'B', 'C', 'D'))
    caretIn(1)
    win.moveBlock('down')
    editEnd(2, 'x')
    editor.view.dispatch(editor.state.tr.setMeta('closeHistory$', true))
    editEnd(2, 'y')
    deleteBlocks(2, 3)
    assert.deepEqual(texts(), ['A', 'C', 'D'])
    editor.commands.undo()
    assert.deepEqual(texts(), ['A', 'C', 'Bx', 'D'], 'the edit and the deletion were one undo step')
    assert.deepEqual(marks(), { changed: [2], moved: [], removedGaps: [] })
  })

  test('a moved paragraph turned into a heading: a changed bar and no dot', () => {
    open(post('A', 'B', 'C'))
    caretIn(0)
    win.moveBlock('down')
    caretIn(1)
    editor.commands.setNode('heading', { level: 2 })
    assert.equal(doc().child(1).type.name, 'heading')
    assert.deepEqual(marks(), { changed: [1], moved: [], removedGaps: [] })
  })

  test('a moved paragraph wrapped in a list: a changed bar and no dot', () => {
    open(post('A', 'B', 'C'))
    caretIn(0)
    win.moveBlock('down')
    caretIn(1)
    editor.commands.toggleBulletList()
    assert.equal(doc().child(1).type.name, 'bulletList')
    assert.deepEqual(marks(), { changed: [1], moved: [], removedGaps: [] })
  })

  test('Enter at the start of a block marks only the new empty paragraph', () => {
    open(post('A', 'B', 'C'))
    caretIn(1)
    editor.commands.splitBlock()
    assert.deepEqual(texts(), ['A', '', 'B', 'C'])
    assert.deepEqual(marks(), { changed: [1], moved: [], removedGaps: [] })
  })

  test('a block edited to read like another saved block does not take its place', () => {
    open(post('A', 'B', 'C'))
    editor.view.dispatch(editor.state.tr.insertText('C', startOf(0) + 1, startOf(0) + 2))
    editor.view.dispatch(editor.state.tr.insertText('D', startOf(2) + 1, startOf(2) + 2))
    assert.deepEqual(texts(), ['C', 'B', 'D'])
    assert.deepEqual(marks(), { changed: [0, 2], moved: [], removedGaps: [] })
  })

  test('undoing Enter at the start of a moved block keeps it the moved one', () => {
    open(post('A', 'B', 'C'))
    caretIn(0)
    win.moveBlock('down')
    assert.deepEqual(marks(), { changed: [1], moved: [1], removedGaps: [] })
    editor.commands.setTextSelection(startOf(1) + 1)
    editor.commands.splitBlock()
    editor.view.dispatch(editor.state.tr.setMeta('closeHistory$', true))
    assert.deepEqual(texts(), ['B', '', 'A', 'C'])
    editor.commands.undo()
    assert.deepEqual(texts(), ['B', 'A', 'C'])
    assert.deepEqual(marks(), { changed: [1], moved: [1], removedGaps: [] }, 'after undo')
    editor.commands.redo()
    editor.commands.undo()
    assert.deepEqual(marks(), { changed: [1], moved: [1], removedGaps: [] }, 'after redo and undo')
  })

  test('a moved and edited block that is then deleted leaves its dot', () => {
    open(post('A', 'B', 'C'))
    caretIn(0)
    win.moveBlock('down')
    editEnd(1, 'x')
    deleteBlocks(1, 2)
    assert.deepEqual(texts(), ['B', 'C'])
    assert.deepEqual(marks(), { changed: [], moved: [], removedGaps: [0] })
  })

  test('random moves, edits, deletions, undo and redo keep the marks honest', () => {
    const letters = ['A', 'B', 'C', 'D', 'E', 'F']
    const SEEDS = Number(process.env.CHANGE_BAR_SEEDS || 60)
    const STEPS = Number(process.env.CHANGE_BAR_STEPS || 20)
    const ops = ['up', 'down', 'grip', 'edit', 'delete', 'undo', 'redo', 'heading', 'list', 'split-start', 'split-mid', 'join', 'insert']
    // A block reads as saved when it is a plain paragraph holding one letter and nothing else.
    const asSaved = i => doc().child(i).type.name === 'paragraph' && /^[A-F]$/.test(doc().child(i).textContent)
    const idOf = i => (doc().child(i).textContent.match(/[A-F]/) || [''])[0]
    for (let seed = 1; seed <= SEEDS; seed++) {
      let state = seed * 2654435761 >>> 0
      const random = n => { state = (state * 1664525 + 1013904223) >>> 0; return state % n }
      open(post(...letters))
      const touched = new Set()
      const moved = new Set()
      const log = []
      for (let step = 0; step < STEPS; step++) {
        const count = doc().childCount
        const index = random(count)
        const id = idOf(index)
        const op = ops[random(ops.length)]
        log.push(`${op} ${id || index}`)
        const start = startOf(index)
        const isPara = doc().child(index).type.name === 'paragraph'
        if (op === 'up' || op === 'down') { caretIn(index); if (win.moveBlock(op)) { touched.add(id); moved.add(id) } }
        else if (op === 'grip') { gripDrop(index, index + 1); touched.add(id); moved.add(id) }
        else if (op === 'edit' && isPara) { editEnd(index, 'x'); touched.add(id) }
        else if (op === 'delete' && count > 2) deleteBlocks(index, index + 1)
        else if (op === 'undo' || op === 'redo') {
          editor.commands[op]()
          // Undo and redo can move or edit any block.
          letters.forEach(l => { touched.add(l); moved.add(l) })
        } else if (op === 'heading' && isPara) { caretIn(index); editor.commands.setNode('heading', { level: 2 }); touched.add(id) }
        else if (op === 'list' && isPara) { caretIn(index); editor.commands.toggleBulletList(); touched.add(id) }
        else if (op === 'split-start' && isPara) { editor.commands.setTextSelection(start + 1); editor.commands.splitBlock() }
        else if (op === 'split-mid' && isPara && doc().child(index).content.size > 1) {
          editor.commands.setTextSelection(start + 2); editor.commands.splitBlock(); touched.add(id)
        } else if (op === 'join' && index > 0 && isPara && doc().child(index - 1).type.name === 'paragraph') {
          editor.commands.setTextSelection(start + 1); editor.commands.joinBackward()
          touched.add(id); touched.add(idOf(index - 1))
        } else if (op === 'insert') {
          editor.view.dispatch(editor.state.tr.insert(start, editor.schema.nodes.paragraph.create(null, editor.schema.text('new'))))
        }
        // One undo step per action, as a person's pauses make them (instant dispatches would merge).
        editor.view.dispatch(editor.state.tr.setMeta('closeHistory$', true))
        const where = `seed ${seed}: ${log.join(', ')} → ${texts().map(t => t || '∅').join(' ')}`
        const m = marks()
        // Gone: no block starts with the letter any more (deleted, or merged into another block).
        const blockTexts = texts()
        const gone = letters.filter(l => !blockTexts.some(t => t.startsWith(l))).length
        if (!gone) assert.deepEqual(m.removedGaps, [], `a dot with no saved block gone, ${where} marks ${JSON.stringify(m)}`)
        for (let i = 0; i < doc().childCount; i++) {
          const t = doc().child(i).textContent
          if (!asSaved(i) && /^[A-F]x*$/.test(t) && doc().child(i).type.name === 'paragraph') {
            assert.ok(m.changed.includes(i) && !m.moved.includes(i), `edited ${t} must be changed, not moved, ${where}`)
          }
          if (asSaved(i) && m.changed.includes(i)) assert.ok(m.moved.includes(i), `unedited ${t} marked but not as moved, ${where}`)
          if (asSaved(i) && !moved.has(t)) assert.ok(!m.changed.includes(i), `never-moved ${t} reading as saved is marked, ${where} marks ${JSON.stringify(m)}`)
          if (!touched.has(t) && /^[A-F]$/.test(t)) assert.ok(!m.changed.includes(i), `untouched ${t} marked, ${where}`)
          if (t === 'new' || t === '') assert.ok(m.changed.includes(i), `new block ${i} not marked, ${where}`)
        }
      }
      while (editor.can().undo()) editor.commands.undo()
      assert.deepEqual(marks(), { changed: [], moved: [], removedGaps: [] }, `undo all, seed ${seed}`)
    }
  })

  test('undoing a move leaves no marks', () => {
    open(post('A', 'B', 'C'))
    caretIn(0)
    win.moveBlock('down')
    editor.commands.undo()
    assert.deepEqual(texts(), ['A', 'B', 'C'])
    assert.deepEqual(marks(), { changed: [], moved: [], removedGaps: [] })
  })

  test('a new baseline forgets earlier moves', () => {
    open(post('A', 'B', 'C'))
    caretIn(0)
    win.moveBlock('down')
    win.setChangeBaseline(post('B', 'A', 'C'), '[]')
    assert.deepEqual(marks(), { changed: [], moved: [], removedGaps: [] })
    caretIn(0)
    win.moveBlock('down')
    assert.deepEqual(texts(), ['A', 'B', 'C'])
    assert.deepEqual(marks(), { changed: [1], moved: [1], removedGaps: [] }, 'B moved, not A from the earlier hint')
  })

  test('loading another post forgets earlier moves', () => {
    open(post('A', 'B'))
    caretIn(0)
    win.moveBlock('down')
    open(post('B', 'A'))
    gripDrop(0, 1)
    assert.deepEqual(texts(), ['A', 'B'])
    assert.deepEqual(marks(), { changed: [1], moved: [1], removedGaps: [] })
  })
})

describe('overlay behaviour', () => {
  const layer = () => win.document.getElementById('change-bar-layer')
  const tip = () => win.document.getElementById('change-bar-tooltip')
  const wrap = () => win.document.getElementById('editor-wrap')
  const wait = ms => new Promise(resolve => setTimeout(resolve, ms))
  const move = (x, y) => wrap().dispatchEvent(new win.MouseEvent('mousemove', { bubbles: true, buttons: 0, clientX: x, clientY: y }))
  const stubbed = []

  afterEach(() => {
    stubbed.splice(0).forEach(el => { delete el.getBoundingClientRect })
    win.setBodyDirty(false)
    win._changeBars.redraw()
  })

  function stub(el, rect) {
    el.getBoundingClientRect = () => ({ ...rect, width: rect.right - rect.left, height: rect.bottom - rect.top })
    stubbed.push(el)
  }

  function arrange() {
    win.setContent(post('A2', 'B', 'D'), '[]')
    win.setChangeBaseline(post('A', 'B', 'C', 'D'), '[]')
    win.setBodyDirty(true)
    stub(layer(), { top: 0, bottom: 0, left: 0, right: 0 })
    stub(editor.view.dom, { top: 0, bottom: 300, left: 100, right: 500 })
    ;[[10, 30], [50, 70], [90, 110]].forEach(([top, bottom], i) => stub(editor.view.nodeDOM(startOf(i)), { top, bottom, left: 100, right: 500 }))
    win._changeBars.redraw()
  }

  test('an edit redraws the marks on its own', async () => {
    win.setContent(post('A', 'B'), '[]')
    win.setChangeBaseline(post('A', 'B'), '[]')
    win.setBodyDirty(true)
    win._changeBars.redraw()
    assert.equal(layer().children.length, 0)
    typeInto(1, 'x')
    await wait(60)
    assert.equal(layer().querySelectorAll('.change-bar').length, 1)
  })

  test('a bar spans its block and a dash lies across the bar column in the gap where a block was removed', () => {
    arrange()
    const bar = layer().querySelector('.change-bar')
    assert.equal(bar.style.top, '10px')
    assert.equal(bar.style.height, '20px')
    const dot = layer().querySelector('.change-bar-removed')
    assert.equal(parseFloat(dot.style.top) + 1, 80, 'centred on the gap')
    assert.equal(parseFloat(dot.style.left) + 5, parseFloat(bar.style.left) + 1, 'centred on the bar column')
  })

  test('a bar stops short of a deletion dash at its end', () => {
    // A moved to the end and D removed: the moved bar ends just above the dash below it.
    win.setContent(post('B', 'C', 'A'), '[]')
    win.setChangeBaseline(post('A', 'B', 'C', 'D'), '[]')
    win.setBodyDirty(true)
    stub(layer(), { top: 0, bottom: 0, left: 0, right: 0 })
    stub(editor.view.dom, { top: 0, bottom: 300, left: 100, right: 500 })
    ;[[10, 30], [50, 70], [90, 110]].forEach(([top, bottom], i) => stub(editor.view.nodeDOM(startOf(i)), { top, bottom, left: 100, right: 500 }))
    win._changeBars.redraw()
    const bar = layer().querySelector('.change-bar')
    const dash = layer().querySelector('.change-bar-removed')
    assert.ok(bar && dash, 'a bar on A and a dash below it')
    const barBottom = parseFloat(bar.style.top) + parseFloat(bar.style.height)
    assert.ok(parseFloat(dash.style.top) + 1 - barBottom >= 6, `clear space between bar (${barBottom}) and dash (${dash.style.top})`)
  })

  test('the bars sit to the right of the text column', () => {
    arrange()
    assert.ok(parseFloat(layer().querySelector('.change-bar').style.left) >= 500)
  })

  test('hovering a bar names it after a delay, and moving off hides the name', async () => {
    arrange()
    const bar = layer().querySelector('.change-bar')
    stub(bar, { top: 10, bottom: 30, left: 508, right: 511 })
    move(509, 20)
    await wait(300)
    assert.ok(!tip().classList.contains('visible'), 'too early')
    await wait(450)
    assert.equal(tip().textContent, 'Changed since the last save')
    assert.ok(tip().classList.contains('visible'))
    move(200, 200)
    assert.ok(!tip().classList.contains('visible'))
  })

  test('hovering a moved bar says it moved', async () => {
    win.setContent(post('A', 'B'), '[]')
    win.setChangeBaseline(post('A', 'B'), '[]')
    win.setBodyDirty(true)
    editor.commands.setTextSelection(startOf(0) + 1)
    win.moveBlock('down')
    stub(layer(), { top: 0, bottom: 0, left: 0, right: 0 })
    stub(editor.view.dom, { top: 0, bottom: 300, left: 100, right: 500 })
    win._changeBars.redraw()
    assert.equal(layer().querySelectorAll('.change-bar-removed').length, 0)
    const bar = layer().querySelector('.change-bar')
    assert.ok(bar.classList.contains('moved'))
    stub(bar, { top: 10, bottom: 30, left: 508, right: 511 })
    move(509, 20)
    await wait(750)
    assert.equal(tip().textContent, 'Moved since the last save')
  })

  test('hovering a deletion mark says what it marks', async () => {
    arrange()
    const dot = layer().querySelector('.change-bar-removed')
    stub(dot, { top: 79, bottom: 81, left: 504, right: 514 })
    move(509, 80)
    await wait(750)
    assert.equal(tip().textContent, 'Removed since the last save')
    wrap().dispatchEvent(new win.MouseEvent('mouseleave'))
    assert.ok(!tip().classList.contains('visible'))
  })

  test('a press-and-drag over a bar names nothing', async () => {
    arrange()
    stub(layer().querySelector('.change-bar'), { top: 10, bottom: 30, left: 508, right: 511 })
    wrap().dispatchEvent(new win.MouseEvent('mousemove', { bubbles: true, buttons: 1, clientX: 509, clientY: 20 }))
    await wait(750)
    assert.ok(!tip().classList.contains('visible'))
  })

  test('scrolling hides the name', async () => {
    arrange()
    stub(layer().querySelector('.change-bar'), { top: 10, bottom: 30, left: 508, right: 511 })
    move(509, 20)
    await wait(750)
    assert.ok(tip().classList.contains('visible'))
    wrap().dispatchEvent(new win.Event('scroll'))
    assert.ok(!tip().classList.contains('visible'))
  })

  test('a fade during typing is drawn fresh when the pointer comes back', () => {
    arrange()
    win.document.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'a', bubbles: true }))
    assert.ok(layer().classList.contains('faded'))
    win.setChangeBaseline(post('A2', 'B', 'D'), '[]')
    win._changeBars.redraw()
    assert.equal(layer().querySelectorAll('.change-bar').length, 1, 'redraw is held while faded')
    move(0, 0)
    assert.ok(!layer().classList.contains('faded'))
    assert.equal(layer().children.length, 0)
  })
})

describe('every overlay hides the marks and blocks moves', () => {
  const layer = () => win.document.getElementById('change-bar-layer')
  const wait = ms => new Promise(resolve => setTimeout(resolve, ms))

  for (const id of ['insert-menu', 'embed-menu', 'find-bar', 'table-size-menu', 'inline-image-popover']) {
    test(id, async () => {
      win.setContent(post('A', 'B2'), '[]')
      win.setChangeBaseline(post('A', 'B'), '[]')
      win.setBodyDirty(true)
      win._changeBars.redraw()
      assert.equal(layer().querySelectorAll('.change-bar').length, 1)
      const el = win.document.getElementById(id)
      el.classList.add('visible')
      try {
        await wait(20)
        assert.equal(layer().children.length, 0, 'marks drawn under the overlay')
        assert.deepEqual([...win._changeMarks().changed], [])
        editor.commands.setTextSelection(startOf(1) + 1)
        assert.equal(win.moveBlock('up'), false, 'a block moved under the overlay')
      } finally {
        el.classList.remove('visible')
      }
      await wait(20)
      assert.equal(layer().querySelectorAll('.change-bar').length, 1, 'marks back once it closes')
      win.setBodyDirty(false)
    })
  }
})
