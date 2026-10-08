'use strict'

// AI output → editor → saved bytes, judged by WordPress's own block validator; see Scripts/fixtures/ai/README.md.

const { test, describe, before, after } = require('node:test')
const assert = require('node:assert/strict')
const { JSDOM, VirtualConsole } = require('jsdom')
const fs = require('fs')
const path = require('path')
const nodeCrypto = require('crypto')

const htmlPath = path.resolve(__dirname, '../Sources/QuillKit/Resources/editor.html')
const fixturesDir = path.resolve(__dirname, 'fixtures', 'ai')
const fixture = name => fs.readFileSync(path.join(fixturesDir, name + '.html'), 'utf8')

const { problems, resaved, namesIn, close: closeValidator } = require('./wp-validator.js')

function assertGutenbergValid(html, expectedBlocks) {
  assert.deepEqual(problems(html), [], 'saved markup:\n' + html)
  // A block that parses only through a deprecation would re-save differently.
  assert.equal(resaved(html), html, 'WordPress would rewrite this markup on its next save')
  const names = namesIn(html)
  for (const name of expectedBlocks) assert.ok(names.has(name), `expected a ${name} block in:\n${html}`)
}

let editor
let win
const sentToSwift = []

before(async () => {
  const vc = new VirtualConsole()
  const logs = []
  vc.on('jsdomError', e => logs.push('JSDOM_ERROR: ' + (e.detail?.stack || e.message || e)))
  const dom = new JSDOM(fs.readFileSync(htmlPath, 'utf8'), {
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

// The same two calls EditorView makes when GeneratePostSheet hands back a post.
function saveGeneratedPost(html) {
  win.setContent(html)
  win.syncContentToSwift()
  return sentToSwift.at(-1)
}

// beginAIOperation / showAIResult as PostEditorView drives them, then the save it triggers.
function saveOperationResult(startHTML, caretText, resultHTML) {
  if (startHTML !== null) {
    win.setContent(startHTML)
    win.syncContentToSwift()
  }
  let caret = null
  editor.state.doc.descendants((node, pos) => {
    if (caret === null && node.isText && node.text.includes(caretText)) caret = pos + node.text.indexOf(caretText)
  })
  editor.commands.setTextSelection({ from: caret, to: caret + caretText.length })
  const op = win.beginAIOperation()
  assert.ok(op, 'beginAIOperation refused the selection')
  win.showAIResult(resultHTML, op.containerFrom, op.containerTo)
  win.acceptAIResult()
  win.syncContentToSwift()
  return sentToSwift.at(-1)
}

function topLevelTexts() {
  return Array.from(editor.state.doc.toJSON().content, n => Array.from(n.content || [], c => c.text).join(''))
}

describe('the validator itself', () => {
  test('passes markup the block editor wrote', () => {
    assert.deepEqual(problems('<!-- wp:heading {"level":3} -->\n<h3 class="wp-block-heading">A</h3>\n<!-- /wp:heading -->'), [])
  })

  test('flags a heading whose level disagrees with its comment', () => {
    assert.equal(problems('<!-- wp:heading -->\n<h3 class="wp-block-heading">A</h3>\n<!-- /wp:heading -->').length, 1)
  })

  test('flags a table with inline styles', () => {
    const html = '<!-- wp:table -->\n<figure class="wp-block-table"><table class="has-fixed-layout"><tbody><tr><td style="padding:10px">a</td></tr></tbody></table></figure>\n<!-- /wp:table -->'
    assert.equal(problems(html).length, 1)
  })

  test('flags HTML that is not in a block', () => {
    assert.equal(problems('<h2>A</h2>').length, 1)
  })
})

describe('a generated post saves as valid blocks', () => {
  let saved
  before(() => { saved = saveGeneratedPost(fixture('generate-post')) })

  test('every block passes WordPress validation and re-saves unchanged', () => {
    assertGutenbergValid(saved, [
      'core/heading', 'core/paragraph', 'core/list', 'core/list-item',
      'core/table', 'core/quote', 'core/code', 'core/separator',
    ])
  })

  test('each heading level survives', () => {
    for (const level of [2, 3, 4]) assert.match(saved, new RegExp(`<h${level} class="wp-block-heading">`))
  })

  test('no inline style reaches the saved post', () => {
    assert.doesNotMatch(saved, /style=/)
  })

  test('the table saves like a toolbar table', () => {
    assert.match(saved, /<!-- wp:table -->\n<figure class="wp-block-table"><table class="has-fixed-layout">/)
  })

  test('saving it again changes nothing', () => {
    assert.equal(saveGeneratedPost(saved), saved)
  })
})

describe('markup Claude sometimes writes saves as valid blocks', () => {
  let saved
  before(() => { saved = saveGeneratedPost(fixture('generate-edge-cases')) })

  test('every block passes WordPress validation and re-saves unchanged', () => {
    assertGutenbergValid(saved, ['core/heading', 'core/paragraph', 'core/list', 'core/code', 'core/table', 'core/image'])
  })

  test('a heading id is recorded as the anchor', () => {
    assert.match(saved, /<!-- wp:heading \{"anchor":"intro"\} -->\n<h2 id="intro" class="wp-block-heading">/)
  })

  test('a custom paragraph class is recorded as className', () => {
    assert.match(saved, /<!-- wp:paragraph \{"className":"lead"\} -->\n<p class="lead">/)
  })

  test('a list that does not start at one keeps its start', () => {
    assert.match(saved, /<!-- wp:list \{"ordered":true,"start":3\} -->\n<ol start="3" class="wp-block-list">/)
  })

  test('a code language moves from the code element to the block', () => {
    assert.match(saved, /<!-- wp:code \{"className":"language-python"\} -->\n<pre class="wp-block-code language-python"><code>print/)
  })

  test('a table caption becomes the block caption, not a row', () => {
    assert.match(saved, /<figcaption class="wp-element-caption">Plans compared<\/figcaption><\/figure>/)
    assert.doesNotMatch(saved, /<td>Plans compared<\/td>/)
  })

  test('an image caption stays with its image', () => {
    assert.match(saved, /<img src="https:\/\/example.com\/dog.jpg" alt="A dog"\/><figcaption class="wp-element-caption">A happy dog<\/figcaption><\/figure>/)
    assert.doesNotMatch(saved, /<p>A happy dog<\/p>/)
  })

  test('saving it again changes nothing', () => {
    assert.equal(saveGeneratedPost(saved), saved)
  })
})

describe('everything else Claude might write saves as valid blocks', () => {
  let saved
  before(() => { saved = saveGeneratedPost(fixture('generate-broad')) })

  test('every block passes WordPress validation and re-saves unchanged', () => {
    assertGutenbergValid(saved, [
      'core/heading', 'core/paragraph', 'core/list', 'core/list-item', 'core/quote',
      'core/table', 'core/code', 'core/separator', 'core/image', 'core/details',
    ])
  })

  test('no text is lost', () => {
    const text = html => html.replace(/<[^>]*>/g, ' ').replace(/&[a-z]+;/g, ' ').replace(/\s+/g, ' ')
    for (const phrase of ['A Top-Level Title', 'Level six', 'highlighted', 'café 😀', 'Bare text with no tags.',
      'Numbered child', 'A bare quote.', 'Someone', 'Merged cell', 'Paragraph cell', 'Listed', 'Total',
      'Plain preformatted text', 'Definition', 'Hidden detail', 'Section text', 'The end.']) {
      assert.ok(text(saved).includes(phrase), `lost "${phrase}"`)
    }
  })

  test('saving it again changes nothing', () => {
    assert.equal(saveGeneratedPost(saved), saved)
  })
})

describe('a right-click AI result saves as valid blocks', () => {
  test('a rewritten table', () => {
    const start = '<!-- wp:table -->\n<figure class="wp-block-table"><table class="has-fixed-layout"><tbody><tr><td>Plan</td><td>Price</td></tr></tbody></table></figure>\n<!-- /wp:table -->'
    const saved = saveOperationResult(start, 'Plan', fixture('operation-table'))
    assertGutenbergValid(saved, ['core/table'])
    assert.match(saved, /<td>Pro<\/td>/)
  })

  test('a rewritten list', () => {
    const start = '<!-- wp:list -->\n<ul class="wp-block-list"><!-- wp:list-item -->\n<li>feed pets</li>\n<!-- /wp:list-item --></ul>\n<!-- /wp:list -->'
    const saved = saveOperationResult(start, 'feed pets', fixture('operation-list'))
    assertGutenbergValid(saved, ['core/list', 'core/list-item'])
    assert.match(saved, /Book an annual checkup/)
  })

  test('rewritten paragraphs', () => {
    const start = '<!-- wp:paragraph -->\n<p>Pets are a big commitment for anyone.</p>\n<!-- /wp:paragraph -->'
    const saved = saveOperationResult(start, 'Pets are a big commitment', fixture('operation-paragraphs'))
    assertGutenbergValid(saved, ['core/paragraph'])
    // Claude never sees a URL, so a link it writes is invented and goes in as plain text.
    assert.match(saved, /read our guide first/)
    assert.doesNotMatch(saved, /<a /)
  })
})

describe('a right-click AI result replaces only the selection', () => {
  const start = '<!-- wp:paragraph -->\n<p>First sentence stays. Middle sentence is rather long and wordy. Last sentence stays.</p>\n<!-- /wp:paragraph -->'

  for (const [where, selected, expected] of [
    ['start', 'First sentence stays.', 'Short. Middle sentence is rather long and wordy. Last sentence stays.'],
    ['middle', 'Middle sentence is rather long and wordy.', 'First sentence stays. Short. Last sentence stays.'],
    ['end', 'Last sentence stays.', 'First sentence stays. Middle sentence is rather long and wordy. Short.'],
  ]) {
    test(`a sentence at the ${where} of a paragraph`, () => {
      const saved = saveOperationResult(start, selected, '<p>Short.</p>')
      assertGutenbergValid(saved, ['core/paragraph'])
      assert.deepEqual(topLevelTexts(), [expected])
      assert.equal(namesIn(saved).size, 1)
      assert.equal((saved.match(/<p>/g) || []).length, 1, 'the paragraph was split:\n' + saved)
    })
  }

  test('the highlighted result is exactly the inserted text, and accepting puts the caret after it', () => {
    win.setContent(start)
    let from = null
    editor.state.doc.descendants((node, pos) => {
      if (from === null && node.isText) from = pos + node.text.indexOf('Middle')
    })
    editor.commands.setTextSelection({ from, to: from + 'Middle sentence is rather long and wordy.'.length })
    win.beginAIOperation()
    win.showAIResult('<p>Short.</p>')
    const shown = editor.state.selection
    assert.equal(editor.state.doc.textBetween(shown.from, shown.to), 'Short.')
    win.acceptAIResult()
    const caret = editor.state.selection
    assert.ok(caret.empty)
    assert.equal(editor.state.doc.textBetween(0, caret.from), 'First sentence stays. Short.')
  })

  test('a selection that crosses bold text', () => {
    const bold = '<!-- wp:paragraph -->\n<p>Keep this. Shorten <strong>this bold</strong> part please. Keep that.</p>\n<!-- /wp:paragraph -->'
    win.setContent(bold)
    let from = null
    let to = null
    editor.state.doc.descendants((node, pos) => {
      if (!node.isText) return
      if (node.text.includes('Shorten')) from = pos + node.text.indexOf('Shorten')
      if (node.text.includes('part please.')) to = pos + node.text.indexOf('part please.') + 'part please.'.length
    })
    editor.commands.setTextSelection({ from, to })
    win.beginAIOperation()
    win.showAIResult('<p>Short.</p>')
    win.acceptAIResult()
    win.syncContentToSwift()
    const saved = sentToSwift.at(-1)
    assertGutenbergValid(saved, ['core/paragraph'])
    assert.ok(saved.includes('Keep this. Short. Keep that.'), saved)
  })

  for (const [what, result, inserted] of [
    ['an entity', '<p>R&amp;D costs are high.</p>', 'R&D costs are high.'],
    ['a non-breaking space', '<p>Ten&nbsp;km.</p>', 'Ten km.'],
    ['a line break and indent', '<p>Costs are\n  high.</p>', 'Costs are high.'],
  ]) {
    test(`a plain-text result holding ${what} goes in as text, not markup`, () => {
      const saved = saveOperationResult(start, 'Middle sentence is rather long and wordy.', result)
      assertGutenbergValid(saved, ['core/paragraph'])
      assert.deepEqual(topLevelTexts(), [`First sentence stays. ${inserted} Last sentence stays.`])
      assert.ok(!saved.includes('&amp;amp;'), saved)
    })
  }

  for (const [edge, selected] of [
    ['trailing', 'Middle sentence is rather long and wordy. '],
    ['leading', ' Middle sentence is rather long and wordy.'],
  ]) {
    test(`a selection with a ${edge} space keeps the space`, () => {
      saveOperationResult(start, selected, '<p>Short.</p>')
      assert.deepEqual(topLevelTexts(), ['First sentence stays. Short. Last sentence stays.'])
    })
  }

  test('showAIResult reports whether it inserted anything', () => {
    win.setContent(start)
    editor.commands.setTextSelection({ from: 1, to: 22 })
    win.beginAIOperation()
    assert.equal(win.showAIResult('<p>   </p>'), null)
    win.discardAIResult()
    assert.equal(editor.state.doc.textContent, 'First sentence stays. Middle sentence is rather long and wordy. Last sentence stays.')
    editor.commands.setTextSelection({ from: 1, to: 22 })
    win.beginAIOperation()
    assert.equal(win.showAIResult('<p>Short.</p>'), true)
    win.acceptAIResult()
  })

  test('a result that arrives after the post changed leaves the new post alone', () => {
    win.setContent(start)
    editor.commands.setTextSelection({ from: 1, to: 22 })
    win.beginAIOperation()
    const other = '<!-- wp:paragraph -->\n<p>A different post entirely.</p>\n<!-- /wp:paragraph -->'
    win.setContent(other)
    const before = editor.state.doc.toJSON()
    assert.equal(win.showAIResult('<p>Short.</p>'), null)
    assert.deepEqual(editor.state.doc.toJSON(), before)
  })

  test('a selection across two paragraphs keeps the text outside it', () => {
    const two = '<!-- wp:paragraph -->\n<p>Before one. Selected one.</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:paragraph -->\n<p>Selected two. After two.</p>\n<!-- /wp:paragraph -->'
    win.setContent(two)
    let from = null
    let to = null
    editor.state.doc.descendants((node, pos) => {
      if (!node.isText) return
      if (node.text.includes('Selected one.')) from = pos + node.text.indexOf('Selected one.')
      if (node.text.includes('Selected two.')) to = pos + node.text.indexOf('Selected two.') + 'Selected two.'.length
    })
    editor.commands.setTextSelection({ from, to })
    win.beginAIOperation()
    win.showAIResult('<p>Merged.</p>')
    win.acceptAIResult()
    win.syncContentToSwift()
    const saved = sentToSwift.at(-1)
    assertGutenbergValid(saved, ['core/paragraph'])
    assert.deepEqual(topLevelTexts(), ['Before one.', 'Merged.', 'After two.'])
  })

  for (const [where, selected, expected] of [
    ['the whole paragraph', 'First sentence stays. Middle sentence is rather long and wordy. Last sentence stays.',
      ['One.', 'Two.']],
    ['the start of a paragraph', 'First sentence stays.',
      ['One.', 'Two.', 'Middle sentence is rather long and wordy. Last sentence stays.']],
    ['the end of a paragraph', 'Last sentence stays.',
      ['First sentence stays. Middle sentence is rather long and wordy.', 'One.', 'Two.']],
    ['the middle of a paragraph', 'Middle sentence is rather long and wordy.',
      ['First sentence stays.', 'One.', 'Two.', 'Last sentence stays.']],
  ]) {
    test(`a two-paragraph result for ${where} leaves no empty paragraph`, () => {
      const saved = saveOperationResult(start, selected, '<p>One.</p><p>Two.</p>')
      assertGutenbergValid(saved, ['core/paragraph'])
      assert.ok(!/<p>\s*<\/p>/.test(saved), 'empty paragraph in:\n' + saved)
      assert.deepEqual(topLevelTexts(), expected)
    })
  }

  test('a block result in mid-paragraph leaves no stray space at the split', () => {
    const saved = saveOperationResult(start, 'Middle sentence is rather long and wordy.', '<p>One.</p><p>Two.</p>')
    assert.ok(saved.includes('<p>First sentence stays.</p>'), saved)
    assert.ok(saved.includes('<p>Last sentence stays.</p>'), saved)
  })

  // Restoring through getHTML/setContent trimmed edge spaces and shifted every later position.
  test('a second operation after a result that split a paragraph replaces the right text', () => {
    const two = start + '\n\n<!-- wp:paragraph -->\n<p>Basic costs five dollars. Pro costs fifteen.</p>\n<!-- /wp:paragraph -->'
    saveOperationResult(two, 'Middle sentence is rather long and wordy.', '<p>One.</p><p>Two.</p>')
    saveOperationResult(null, 'Basic costs five dollars. Pro costs fifteen.', '<p>Short.</p>')
    assert.deepEqual(topLevelTexts(), ['First sentence stays.', 'One.', 'Two.', 'Last sentence stays.', 'Short.'])
  })

  test('discarding restores the original paragraph', () => {
    win.setContent(start)
    let caret = null
    editor.state.doc.descendants((node, pos) => {
      if (caret === null && node.isText) caret = pos + node.text.indexOf('Middle')
    })
    editor.commands.setTextSelection({ from: caret, to: caret + 'Middle sentence is rather long and wordy.'.length })
    win.beginAIOperation()
    win.showAIResult('<p>Short.</p>')
    win.discardAIResult()
    assert.equal(editor.state.doc.textContent, 'First sentence stays. Middle sentence is rather long and wordy. Last sentence stays.')
  })

  test('discarding keeps a space the author just typed at the end of a paragraph, and tells Swift', async () => {
    win.setContent('<!-- wp:paragraph -->\n<p>Plain start, <strong>then bold</strong> and then plain.</p>\n<!-- /wp:paragraph -->')
    editor.view.dispatch(editor.state.tr.insertText(' ', editor.state.doc.firstChild.nodeSize - 1))
    win.syncContentToSwift()
    const typed = sentToSwift.at(-1)
    const original = editor.state.doc.toJSON()
    editor.commands.setTextSelection({ from: 1, to: 20 })
    win.beginAIOperation()
    win.showAIResult('<p>Short.</p>')
    const posted = sentToSwift.length
    win.discardAIResult()
    assert.deepEqual(editor.state.doc.toJSON(), original)
    await new Promise(resolve => setTimeout(resolve, 600))
    assert.equal(sentToSwift.length, posted + 1)
    assert.equal(sentToSwift.at(-1), typed)
  })
})

describe('editing while Claude responds', () => {
  const two = '<!-- wp:paragraph -->\n<p>First sentence stays. Middle sentence is rather long and wordy. Last sentence stays.</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:paragraph -->\n<p>Second paragraph.</p>\n<!-- /wp:paragraph -->'

  function beginOnMiddle() {
    win.setContent(two)
    let from = null
    editor.state.doc.descendants((node, pos) => {
      if (from === null && node.isText) from = pos + node.text.indexOf('Middle')
    })
    editor.commands.setTextSelection({ from, to: from + 'Middle sentence is rather long and wordy.'.length })
    assert.ok(win.beginAIOperation())
  }

  function typeAtEndOf(index, text) {
    let end = 0
    editor.state.doc.forEach((node, offset, i) => { if (i === index) end = offset + node.nodeSize - 1 })
    editor.view.dispatch(editor.state.tr.insertText(text, end))
  }

  test('the placeholder is never saved as content', () => {
    win.setContent(two)
    win.syncContentToSwift()
    const before = sentToSwift.at(-1)
    beginOnMiddle()
    win.syncContentToSwift()
    assert.equal(sentToSwift.at(-1), before)
    assert.ok(!editor.getHTML().includes('Rewriting'))
    win.discardAIResult()
  })

  test('an edit in another paragraph survives accepting the result', () => {
    beginOnMiddle()
    typeAtEndOf(1, ' Typed later.')
    assert.equal(win.showAIResult('<p>Short.</p>'), true)
    win.acceptAIResult()
    assert.deepEqual(topLevelTexts(), ['First sentence stays. Short. Last sentence stays.', 'Second paragraph. Typed later.'])
  })

  test('an edit before the selection moves the result with it', () => {
    beginOnMiddle()
    editor.view.dispatch(editor.state.tr.insertText('Added. ', 1))
    win.showAIResult('<p>Short.</p>')
    win.acceptAIResult()
    assert.deepEqual(topLevelTexts(), ['Added. First sentence stays. Short. Last sentence stays.', 'Second paragraph.'])
  })

  test('an edit made while Claude responds survives discarding the result', () => {
    beginOnMiddle()
    typeAtEndOf(1, ' Typed later.')
    win.showAIResult('<p>Short.</p>')
    win.discardAIResult()
    assert.deepEqual(topLevelTexts(), ['First sentence stays. Middle sentence is rather long and wordy. Last sentence stays.', 'Second paragraph. Typed later.'])
  })

  test('an edit made while the result is shown survives discarding it', () => {
    beginOnMiddle()
    win.showAIResult('<p>One.</p><p>Two.</p>')
    typeAtEndOf(4, ' Typed later.')
    win.discardAIResult()
    assert.deepEqual(topLevelTexts(), ['First sentence stays. Middle sentence is rather long and wordy. Last sentence stays.', 'Second paragraph. Typed later.'])
  })

  test('a second operation is refused while one is pending, and the first still lands', () => {
    beginOnMiddle()
    editor.commands.setTextSelection({ from: 1, to: 22 })
    assert.deepEqual({ ...win.beginAIOperation() }, { busy: true })
    win.showAIResult('<p>Short.</p>')
    win.acceptAIResult()
    assert.deepEqual(topLevelTexts(), ['First sentence stays. Short. Last sentence stays.', 'Second paragraph.'])
  })

  test('a second operation is refused while a result waits for Accept or Discard', () => {
    beginOnMiddle()
    win.showAIResult('<p>Short.</p>')
    editor.commands.setTextSelection({ from: 1, to: 22 })
    assert.deepEqual({ ...win.beginAIOperation() }, { busy: true })
    win.discardAIResult()
    assert.deepEqual(topLevelTexts(), ['First sentence stays. Middle sentence is rather long and wordy. Last sentence stays.', 'Second paragraph.'])
    editor.commands.setTextSelection({ from: 1, to: 22 })
    assert.ok(win.beginAIOperation().text)
    win.discardAIResult()
  })

  test('discarding before a result arrives leaves the document alone', () => {
    beginOnMiddle()
    typeAtEndOf(1, ' Typed later.')
    win.discardAIResult()
    assert.deepEqual(topLevelTexts(), ['First sentence stays. Middle sentence is rather long and wordy. Last sentence stays.', 'Second paragraph. Typed later.'])
    assert.equal(win.showAIResult('<p>Short.</p>'), null)
  })

  test('the pending text is dimmed and labelled in the view, and both go once the result is accepted', () => {
    beginOnMiddle()
    const view = win.document.querySelector('.ProseMirror')
    const label = view.querySelector('.ai-loading')
    const pending = view.querySelectorAll('.ai-pending')
    assert.ok(label, 'no Rewriting label')
    assert.equal(Array.from(pending, el => el.textContent).join(''), 'Middle sentence is rather long and wordy.')
    assert.equal(label.nextSibling, pending[0], 'the label does not sit right before the pending text')
    win.showAIResult('<p>Short.</p>')
    win.acceptAIResult()
    assert.equal(view.querySelector('.ai-loading, .ai-pending'), null)
  })

  test('typing at the caret while Claude responds lands after the result, not inside the replaced text', () => {
    beginOnMiddle()
    const caret = editor.state.selection
    assert.ok(caret.empty, 'the selection should collapse so typing cannot overwrite it')
    editor.view.dispatch(editor.state.tr.insertText(' Typed', caret.from))
    win.showAIResult('<p>Short.</p>')
    win.acceptAIResult()
    assert.deepEqual(topLevelTexts(), ['First sentence stays. Short. Typed Last sentence stays.', 'Second paragraph.'])
  })

  test('a result for text deleted while Claude responds is not inserted', () => {
    beginOnMiddle()
    let from = null
    editor.state.doc.descendants((node, pos) => {
      if (from === null && node.isText) from = pos + node.text.indexOf('Middle')
    })
    editor.view.dispatch(editor.state.tr.delete(from, from + 'Middle sentence is rather long and wordy. '.length))
    const before = editor.state.doc.toJSON()
    assert.equal(win.showAIResult('<p>Short.</p>'), null)
    assert.deepEqual(editor.state.doc.toJSON(), before)
    win.discardAIResult()
    assert.deepEqual(topLevelTexts(), ['First sentence stays. Last sentence stays.', 'Second paragraph.'])
    editor.commands.setTextSelection({ from: 1, to: 22 })
    assert.ok(win.beginAIOperation().text, 'the discarded operation still blocks a new one')
    win.discardAIResult()
  })

  function selectText(text) {
    let from = null
    editor.state.doc.descendants((node, pos) => {
      if (from === null && node.isText && node.text.includes(text)) from = pos + node.text.indexOf(text)
    })
    editor.commands.setTextSelection({ from, to: from + text.length })
  }

  test('discarding a table result that ends the post leaves no empty paragraph behind', () => {
    win.setContent('<!-- wp:paragraph -->\n<p>Intro text here.</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:paragraph -->\n<p>Alpha beta gamma delta epsilon.</p>\n<!-- /wp:paragraph -->')
    const original = editor.state.doc.toJSON()
    selectText('Alpha beta gamma delta epsilon.')
    assert.ok(win.beginAIOperation())
    assert.equal(win.showAIResult('<table><tbody><tr><td>a</td><td>b</td></tr></tbody></table>'), true)
    assert.deepEqual(Array.from({ length: editor.state.doc.childCount }, (_, i) => editor.state.doc.child(i).type.name), ['paragraph', 'table', 'paragraph'])
    win.discardAIResult()
    assert.deepEqual(editor.state.doc.toJSON(), original)
  })

  test('discarding after the paragraph holding the result was deleted brings none of it back', () => {
    win.setContent('<p>Keep this.</p><p>Alpha beta gamma delta epsilon.</p><p>Tail para.</p>')
    selectText('beta gamma delta')
    assert.ok(win.beginAIOperation())
    assert.equal(win.showAIResult('<p>Short.</p>'), true)
    const start = editor.state.doc.child(0).nodeSize
    editor.view.dispatch(editor.state.tr.delete(start, start + editor.state.doc.child(1).nodeSize))
    win.discardAIResult()
    assert.deepEqual(topLevelTexts(), ['Keep this.', 'Tail para.'])
    selectText('Tail para.')
    assert.ok(win.beginAIOperation().text, 'the discard did not clear the operation')
    win.discardAIResult()
  })

  test('discarding after the whole document was deleted leaves it empty', () => {
    win.setContent('<p>Keep this.</p><p>Alpha beta gamma delta epsilon.</p><p>Tail para.</p>')
    selectText('beta gamma delta')
    assert.ok(win.beginAIOperation())
    win.showAIResult('<p>Short.</p>')
    editor.commands.selectAll()
    editor.commands.deleteSelection()
    win.discardAIResult()
    assert.equal(editor.state.doc.textContent, '')
  })

  test('a list rewrite replaces its own list after text is typed above it', () => {
    const start = '<!-- wp:paragraph -->\n<p>Intro.</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:list -->\n<ul class="wp-block-list"><!-- wp:list-item -->\n<li>feed pets</li>\n<!-- /wp:list-item --></ul>\n<!-- /wp:list -->\n\n<!-- wp:paragraph -->\n<p>Outro.</p>\n<!-- /wp:paragraph -->'
    win.setContent(start)
    let from = null
    editor.state.doc.descendants((node, pos) => {
      if (from === null && node.isText && node.text === 'feed pets') from = pos
    })
    editor.commands.setTextSelection({ from, to: from + 'feed pets'.length })
    const op = win.beginAIOperation()
    assert.equal(op.context, 'bulletList')
    typeAtEndOf(0, ' More intro.')
    assert.equal(win.showAIResult(fixture('operation-list'), op.containerFrom, op.containerTo), true)
    win.acceptAIResult()
    const doc = editor.state.doc
    assert.deepEqual(Array.from({ length: doc.childCount }, (_, i) => doc.child(i).type.name), ['paragraph', 'bulletList', 'paragraph'])
    assert.equal(doc.child(0).textContent, 'Intro. More intro.')
    assert.deepEqual(Array.from({ length: doc.child(1).childCount }, (_, i) => doc.child(1).child(i).textContent),
      ['Feed twice a day', 'Walk every morning', 'Book an annual checkup'])
    assert.equal(doc.child(2).textContent, 'Outro.')
  })
})


describe('a selection goes to Claude as reduced HTML with stubs', () => {
  const FN = 'fn-11111111-2222-4333-8444-555555555555'
  const footnoted = `<!-- wp:paragraph -->\n<p>Intro para.</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:paragraph -->\n<p>See the <a href="https://example.com" target="_blank" rel="noopener">docs</a> today.<sup data-fn="${FN}" class="fn" id="${FN}-link"><a href="#${FN}">1</a></sup> More <em>words</em> here.</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:footnotes /-->`
  const META = JSON.stringify([{ id: FN, content: 'The note body.' }])

  function select(text) {
    const search = win._editorSearchText()
    const at = search.text.indexOf(text)
    assert.ok(at >= 0, `"${text}" is not in the document`)
    editor.commands.setTextSelection({ from: search.positions[at], to: search.positions[at + text.length - 1] + 1 })
  }

  function rewrite(text, resultHTML) {
    select(text)
    const op = win.beginAIOperation()
    assert.ok(op && !op.busy, 'beginAIOperation refused the selection')
    const inserted = win.showAIResult(resultHTML, op.containerFrom, op.containerTo)
    win.acceptAIResult()
    win.syncContentToSwift()
    return { op, inserted, saved: sentToSwift.at(-1) }
  }

  test('selection html reduces links and footnotes to stubs', () => {
    win.setContent(footnoted, META)
    select('See the docs today. More words here.')
    const op = win.beginAIOperation()
    win.discardAIResult()
    assert.equal(op.html, 'See the <a id="L1">docs</a> today.<sup id="F1"></sup> More <em>words</em> here.')
    assert.doesNotMatch(op.html, /href|target|data-fn|class=/)
  })

  test('before and after carry the rest of the paragraph for a mid-paragraph selection', () => {
    win.setContent('<p>Intro para.</p><p>First sentence here. Second sentence is selected. Third one.</p><p>Outro para.</p>')
    select('Second sentence is selected.')
    const op = win.beginAIOperation()
    win.discardAIResult()
    assert.equal(op.html, 'Second sentence is selected.')
    assert.equal(op.before, 'Intro para.\n\nFirst sentence here. ')
    assert.equal(op.after, ' Third one.\n\nOutro para.')
  })

  test('a list sends its whole container, reduced', () => {
    win.setContent('<p>Before.</p><ul><li><p>One <a href="https://example.com">link</a></p></li><li><p>Two items here</p></li></ul><p>After.</p>')
    select('Two items here')
    const op = win.beginAIOperation()
    win.discardAIResult()
    assert.equal(op.html, '<ul><li><p>One <a id="L1">link</a></p></li><li><p>Two items here</p></li></ul>')
    assert.equal(op.before, 'Before.')
    assert.equal(op.after, 'After.')
  })

  test('showAIResult restores link attributes and the footnote marker by id', () => {
    win.setContent(footnoted, META)
    const { saved } = rewrite('See the docs today. More words here.', 'Read the <a id="L1">docs</a> now.<sup id="F1"></sup> More <em>words</em>.')
    assert.match(saved, /<a (?=[^>]*href="https:\/\/example.com")(?=[^>]*target="_blank")(?=[^>]*rel="noopener")[^>]*>docs<\/a>/)
    assert.match(saved, /<p>Read the <a [^>]*>docs<\/a> now\.<sup data-fn="fn-11111111-2222-4333-8444-555555555555" class="fn" id="fn-11111111-2222-4333-8444-555555555555-link"><a href="#fn-11111111-2222-4333-8444-555555555555">1<\/a><\/sup> More <em>words<\/em>\.<\/p>/)
    assert.match(editor.getHTML(), /The note body\./)
  })

  test('a table sends its whole container, every attribute stripped', () => {
    win.setContent('<p>Before.</p><table class="has-fixed-layout"><tbody><tr><td>Name <strong>bold</strong></td><td>Two cells here</td></tr></tbody></table><p>After.</p>')
    select('Two cells here')
    const op = win.beginAIOperation()
    win.discardAIResult()
    assert.equal(op.context, 'table')
    assert.equal(op.html, '<table><colgroup><col><col></colgroup><tbody><tr><td><p>Name <strong>bold</strong></p></td><td><p>Two cells here</p></td></tr></tbody></table>')
    assert.equal(op.before, 'Before.')
    assert.equal(op.after, 'After.')
  })

  test('a stub id on the wrong tag is unwrapped, not restored', () => {
    win.setContent(footnoted, META)
    const link = rewrite('See the docs today.', 'Read the <sup id="L1">docs</sup> now.').saved
    assert.match(link, /<p>Read the docs now\.<sup data-fn=/)
    assert.doesNotMatch(link, /example\.com/)
    win.setContent(footnoted, META)
    const note = rewrite('See the docs today. More words here.', 'See the <a id="L1">docs</a> today.<a id="F1">1</a> More words here.').saved
    assert.match(note, /today\.1 More words here\.<\/p>/)
    assert.doesNotMatch(note, /data-fn/)
  })

  test('a plain superscript survives the rewrite', () => {
    win.setContent('<p>Einstein wrote E=mc<sup>2</sup> in a famous paper.</p>')
    const op = (() => { select('Einstein wrote E=mc2 in a famous paper.'); const o = win.beginAIOperation(); win.discardAIResult(); return o })()
    assert.equal(op.html, 'Einstein wrote E=mc<sup>2</sup> in a famous paper.')
    const { saved } = rewrite('Einstein wrote E=mc2 in a famous paper.', 'Einstein wrote E=mc<sup>2</sup> in a celebrated paper.')
    assert.match(saved, /<p>Einstein wrote E=mc<sup>2<\/sup> in a celebrated paper\.<\/p>/)
  })

  test('an invented footnote marker without a stub id is unwrapped', () => {
    win.setContent(footnoted, META)
    const { saved } = rewrite('See the docs today.', 'Read the docs now.<sup class="fn" data-fn="invented">1</sup>')
    assert.match(saved, /<p>Read the docs now\.1<sup data-fn="fn-11111111/)
    assert.doesNotMatch(saved, /invented/)
  })

  test('unknown stub id is unwrapped to its text', () => {
    win.setContent(footnoted, META)
    const { saved } = rewrite('See the docs today.', 'Read <a id="L9">this</a> now.')
    assert.match(saved, /<p>Read this now\.<sup/)
  })

  test('duplicated stub keeps the first and unwraps the rest', () => {
    win.setContent(footnoted, META)
    const { saved } = rewrite('See the docs today.', 'The <a id="L1">docs</a> and <a id="L1">guides</a> today.')
    assert.match(saved, /<p>The <a [^>]*href="https:\/\/example.com"[^>]*>docs<\/a> and guides today\.<sup/)
  })

  test('dropped footnote stub leaves no marker and no text loss', () => {
    win.setContent(footnoted, META)
    const { saved } = rewrite('See the docs today. More words here.', 'See the <a id="L1">docs</a> today. More <em>words</em> here.')
    assert.match(saved, /<p>Intro para\.<\/p>/)
    assert.match(saved, /<p>See the <a [^>]*>docs<\/a> today\. More <em>words<\/em> here\.<\/p>/)
    assert.doesNotMatch(saved, /data-fn/)
  })

  test('a plain-text result inside a paragraph goes in as text, its whitespace collapsed', () => {
    win.setContent('<p>Intro para.</p><p>First sentence here. Second sentence is selected. Third one.</p><p>Outro para.</p>')
    const { inserted } = rewrite('Second sentence is selected.', ' The second\n sentence &amp; more. ')
    assert.equal(inserted, true)
    assert.deepEqual(topLevelTexts(), ['Intro para.', 'First sentence here. The second sentence & more. Third one.', 'Outro para.'])
  })

  test('inline result inside a paragraph does not split it', () => {
    win.setContent('<p>Intro para.</p><p>First sentence here. Second sentence is selected. Third one.</p><p>Outro para.</p>')
    const before = topLevelTexts().length
    const { inserted } = rewrite('Second sentence is selected.', 'The <em>second</em> sentence, rewritten.')
    assert.equal(inserted, true)
    assert.equal(topLevelTexts().length, before)
    assert.deepEqual(topLevelTexts(), ['Intro para.', 'First sentence here. The second sentence, rewritten. Third one.', 'Outro para.'])
  })
})
