'use strict'

// Every saved-post fixture, loaded, edited and saved by Quill, must not fail WordPress's validator in any new way.

const { test, describe, before, after } = require('node:test')
const assert = require('node:assert/strict')
const { JSDOM, VirtualConsole } = require('jsdom')
const fs = require('fs')
const path = require('path')
const nodeCrypto = require('crypto')

const htmlPath = path.resolve(__dirname, '../Sources/QuillKit/Resources/editor.html')
const fixturesDir = path.resolve(__dirname, 'fixtures')

const { problems, resaved, close: closeValidator } = require('./wp-validator.js')

let editor
let win

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

  editor = await new Promise((resolve, reject) => {
    let tries = 0
    const t = setInterval(() => {
      if (win._tiptapEditor) { clearInterval(t); resolve(win._tiptapEditor) }
      else if (++tries > 400) { clearInterval(t); reject(new Error('editor never became ready.\n' + logs.join('\n'))) }
    }, 25)
  })
})

after(() => { if (win) win.close(); closeValidator() })

const CLASSIC = 'classic (non-block) HTML: '

const tight = html => html.replace(/>\s+</g, '><')

// Classic HTML Quill carried over is not new, even when the source reported it inside a larger chunk.
function newProblems(saved, source) {
  const left = problems(saved)
  for (const r of problems(source)) { const i = left.indexOf(r); if (i !== -1) left.splice(i, 1) }
  return left.filter(p => !(p.startsWith(CLASSIC) && tight(source).includes(tight(p.slice(CLASSIC.length)))))
}

// Force an edit so the save runs through Tiptap rather than returning the loaded bytes.
function editAndSave(source) {
  win.setContent(source)
  return win.extractFootnotes(win.toWordPressHTML(editor.getHTML())).content
}

describe('WordPress accepts every fixture after a Quill edit', () => {
  for (const name of fs.readdirSync(fixturesDir).filter(f => f.endsWith('.html')).sort()) {
    test(name, () => {
      const source = fs.readFileSync(path.join(fixturesDir, name), 'utf8')
      const saved = editAndSave(source)
      assert.deepEqual(newProblems(saved, source), [], 'saved markup:\n' + saved)
      if (resaved(source) === source) assert.equal(resaved(saved), saved, 'WordPress would rewrite what Quill saved')
    })
  }
})

describe('the sweep can fail', () => {
  test('a heading whose level disagrees with its comment is reported as new', () => {
    const source = '<!-- wp:heading -->\n<h2 class="wp-block-heading">A</h2>\n<!-- /wp:heading -->'
    const broken = source.replace(/h2/g, 'h3')
    assert.equal(newProblems(broken, source).length, 1)
  })

  test('classic HTML that was not in the source is reported as new', () => {
    assert.equal(newProblems('<p>Invented.</p>', '<!-- wp:paragraph -->\n<p>A</p>\n<!-- /wp:paragraph -->').length, 1)
  })

  test('classic HTML Quill turns into blocks is not a new problem', () => {
    const source = '<p>Classic prose.</p>'
    assert.equal(problems(source).length, 1)
    assert.deepEqual(newProblems(editAndSave(source), source), [])
  })
})
