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
  win.setContent(startHTML)
  win.syncContentToSwift()
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
    assert.match(saved, /our guide<\/a>/)
  })
})
