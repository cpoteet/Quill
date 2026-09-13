'use strict'

// Per-setting tests for the block-settings preservation work. Loads the REAL
// editor.html in jsdom -- a node's renderHTML and its parse rule cannot be
// exercised through the pure editor-transforms.js helpers.

const { test, describe, before, after } = require('node:test')
const assert = require('node:assert/strict')
const { JSDOM, VirtualConsole } = require('jsdom')
const fs = require('fs')
const path = require('path')
const nodeCrypto = require('crypto')

const htmlPath = path.resolve(__dirname, '../Sources/QuillKit/Resources/editor.html')

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

// The post-visual-edit save path: getContent() returns _rawHTML verbatim until
// an edit clears it, so calling the transform directly is what a real save does.
function save(src) {
  win.setContent(src)
  return win.toWordPressHTML(editor.getHTML())
}

const fixture = name => fs.readFileSync(path.resolve(__dirname, 'fixtures', name), 'utf8')

describe('className survives on container blocks', () => {
  test('an outline button keeps its class and its comment attr', () => {
    const out = save(`<!-- wp:buttons -->
<div class="wp-block-buttons"><!-- wp:button {"className":"is-style-outline"} -->
<div class="wp-block-button is-style-outline"><a class="wp-block-button__link wp-element-button" href="https://x.test">Go</a></div>
<!-- /wp:button --></div>
<!-- /wp:buttons -->`)
    assert.match(out, /class="wp-block-button is-style-outline"/)
    assert.match(out, /wp:button \{"className":"is-style-outline"\}/)
  })

  test('the class is not doubled when it is already rendered', () => {
    const out = save(`<!-- wp:details {"className":"is-style-x"} -->
<details class="wp-block-details is-style-x"><summary>S</summary><!-- wp:paragraph --><p>D</p><!-- /wp:paragraph --></details>
<!-- /wp:details -->`)
    assert.equal((out.match(/is-style-x/g) || []).length, 2, 'once in the class, once in the comment')
  })

  test('a block with no className is unchanged', () => {
    const out = save(`<!-- wp:buttons -->
<div class="wp-block-buttons"><!-- wp:button -->
<div class="wp-block-button"><a class="wp-block-button__link wp-element-button" href="https://x.test">Go</a></div>
<!-- /wp:button --></div>
<!-- /wp:buttons -->`)
    assert.match(out, /class="wp-block-button"/)
    assert.doesNotMatch(out, /class="wp-block-button "/)
  })
})

describe('delimiter attributes survive on core blocks', () => {
  test('a paragraph keeps dropCap', () => {
    const out = save('<!-- wp:paragraph {"dropCap":true} -->\n<p class="has-drop-cap">Hello</p>\n<!-- /wp:paragraph -->')
    assert.match(out, /wp:paragraph \{"dropCap":true\}/)
  })

  test('an ordered list keeps start, reversed and type', () => {
    const out = save('<!-- wp:list {"ordered":true,"start":5,"reversed":true,"type":"upper-roman"} -->\n<ol reversed start="5" style="list-style-type:upper-roman" class="wp-block-list"><!-- wp:list-item --><li>one</li><!-- /wp:list-item --></ol>\n<!-- /wp:list -->')
    assert.match(out, /"start":5/)
    assert.match(out, /"reversed":true/)
    assert.match(out, /"type":"upper-roman"/)
  })

  test('a separator keeps its className', () => {
    const out = save('<!-- wp:separator {"className":"is-style-dots"} -->\n<hr class="wp-block-separator has-alpha-channel-opacity is-style-dots"/>\n<!-- /wp:separator -->')
    assert.match(out, /"className":"is-style-dots"/)
  })

  test('an unmodeled attribute rides along untouched', () => {
    const out = save('<!-- wp:paragraph {"metadata":{"name":"Intro"}} -->\n<p>Hello</p>\n<!-- /wp:paragraph -->')
    assert.match(out, /"metadata":\{"name":"Intro"\}/)
  })
})

describe('image, gallery and embed keep unmodeled attributes', () => {
  test('an image keeps lightbox and className', () => {
    const out = save('<!-- wp:image {"id":9,"sizeSlug":"large","lightbox":{"enabled":true},"className":"is-style-rounded"} -->\n<figure class="wp-block-image size-large is-style-rounded"><img src="https://x.test/a.jpg" alt="" class="wp-image-9"/></figure>\n<!-- /wp:image -->')
    assert.match(out, /"lightbox":\{"enabled":true\}/)
    assert.match(out, /"className":"is-style-rounded"/)
  })

  test('a derived attribute still wins over a stale carried one', () => {
    const out = save('<!-- wp:image {"id":9,"sizeSlug":"thumbnail"} -->\n<figure class="wp-block-image size-large"><img src="https://x.test/a.jpg" alt="" class="wp-image-9"/></figure>\n<!-- /wp:image -->')
    assert.match(out, /"sizeSlug":"large"/)
    assert.doesNotMatch(out, /"sizeSlug":"thumbnail"/)
  })

  test('an embed keeps an attribute Quill does not model', () => {
    const out = save('<!-- wp:embed {"url":"https://www.youtube.com/watch?v=abc","type":"video","providerNameSlug":"youtube","responsive":true,"align":"wide","className":"wp-embed-aspect-16-9 wp-has-aspect-ratio"} -->\n<figure class="wp-block-embed alignwide is-type-video is-provider-youtube wp-block-embed-youtube wp-embed-aspect-16-9 wp-has-aspect-ratio"><div class="wp-block-embed__wrapper">\nhttps://www.youtube.com/watch?v=abc\n</div></figure>\n<!-- /wp:embed -->')
    assert.match(out, /"align":"wide"/)
  })

  test('a gallery keeps an attribute Quill does not model', () => {
    const out = save('<!-- wp:gallery {"columns":2,"linkTo":"none","randomOrder":true} -->\n<figure class="wp-block-gallery has-nested-images columns-2 is-cropped"><!-- wp:image {"id":1,"sizeSlug":"large"} -->\n<figure class="wp-block-image size-large"><img src="https://x.test/1.jpg" alt="" class="wp-image-1"/></figure>\n<!-- /wp:image --></figure>\n<!-- /wp:gallery -->')
    assert.match(out, /"randomOrder":true/)
  })
})

// The bug class CLAUDE.md records: a top-level const is reachable by bare
// identifier but never as a property of globalThis, so it reads undefined in
// the app while every pure-Node test passes. Only this harness catches it.
describe('the settings registry is live in the editor', () => {
  test('settingsFor is callable as a global', () => {
    assert.equal(typeof win.settingsFor, 'function')
  })

  test('it returns a real entry, not an empty object', () => {
    const entry = win.settingsFor('accordionItem')
    assert.equal(entry.openByDefault.kind, 'flagClass')
    assert.equal(entry.openByDefault.class, 'is-open')
  })

  test('settingKinds reaches the browser too', () => {
    assert.ok(win.settingKinds().includes('flagClass'))
  })
})

describe('registry-generated attributes: accordionItem.openByDefault', () => {
  const open = `<!-- wp:accordion -->
<div role="group" class="wp-block-accordion"><!-- wp:accordion-item {"openByDefault":true} -->
<div class="wp-block-accordion-item is-open"><!-- wp:accordion-heading -->
<h3 class="wp-block-accordion-heading has-icon has-icon-right"><button type="button" class="wp-block-accordion-heading__toggle"><span class="wp-block-accordion-heading__toggle-title">T</span><span class="wp-block-accordion-heading__toggle-icon" aria-hidden="true">+</span></button></h3>
<!-- /wp:accordion-heading -->

<!-- wp:accordion-panel -->
<div role="region" class="wp-block-accordion-panel"><!-- wp:paragraph -->
<p>Body</p>
<!-- /wp:paragraph --></div>
<!-- /wp:accordion-panel --></div>
<!-- /wp:accordion-item --></div>
<!-- /wp:accordion -->`

  const shut = open
    .replace(' {"openByDefault":true}', '')
    .replace('wp-block-accordion-item is-open', 'wp-block-accordion-item')

  test('an open item keeps its is-open class through a save', () => {
    assert.match(save(open), /class="wp-block-accordion-item is-open"/)
  })

  test('an open item keeps its delimiter key', () => {
    assert.match(save(open), /wp:accordion-item \{"openByDefault":true\}/)
  })

  test('a closed item gains neither the class nor the key', () => {
    const out = save(shut)
    assert.doesNotMatch(out, /is-open/)
    assert.doesNotMatch(out, /wp:accordion-item \{/)
  })

  test('the class is not doubled across two save cycles', () => {
    const once = save(open)
    win.setContent(once)
    const twice = win.toWordPressHTML(editor.getHTML())
    assert.equal((twice.match(/is-open/g) || []).length, 1)
  })

  // Settles the wrapper nesting: withBlockSettings must run inside
  // withBlockAttrs, so the carried className merges onto a class list the
  // setting has already contributed to rather than replacing it.
  test('a carried className and the setting class land together', () => {
    const out = save(open.replace('{"openByDefault":true}', '{"openByDefault":true,"className":"mine"}'))
    const m = out.match(/<div class="([^"]*wp-block-accordion-item[^"]*)"/)
    assert.ok(m, 'the item div should still be there')
    const classes = m[1].split(/\s+/)
    assert.ok(classes.includes('is-open'), `is-open missing from "${m[1]}"`)
    assert.ok(classes.includes('mine'), `mine missing from "${m[1]}"`)
  })
})
