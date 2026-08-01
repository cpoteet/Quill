'use strict'

// Live Tiptap tests for the gutenbergPassthrough node — loads the REAL
// editor.html in jsdom, same approach as test-editor-gallery.js, because a
// custom node's parseHTML/renderHTML can't be exercised through the pure
// editor-transforms.js helpers alone.

const { test, describe, before, beforeEach, after } = require('node:test')
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

function nodesOfType(typeName) {
  const out = []
  editor.state.doc.descendants(n => { if (n.type.name === typeName) out.push(n) })
  return out
}

const ACCORDION_CLASS_ONLY =
  '<div class="wp-block-accordion" data-wp-interactive="core/accordion">' +
  '<div class="wp-block-accordion-item">' +
  '<h3 class="wp-block-accordion-heading"><button type="button" class="wp-block-accordion-heading__toggle">Features</button></h3>' +
  '<div class="wp-block-accordion-panel"><ul class="wp-block-list"><li>One</li></ul></div>' +
  '</div></div>'

describe('gutenbergPassthrough — class-only markup (no wp: comments)', () => {
  test('parses into a single gutenbergPassthrough node', () => {
    win.setContent(ACCORDION_CLASS_ONLY)
    const nodes = nodesOfType('gutenbergPassthrough')
    assert.equal(nodes.length, 1)
    assert.equal(nodes[0].attrs.blockLabel, 'Accordion')
    assert.equal(nodes[0].attrs.blockName, null)
  })

  test('round-trips the essential markup through getContent()', () => {
    win.setContent(ACCORDION_CLASS_ONLY)
    const out = win.getContent()
    assert.match(out, /data-wp-interactive="core\/accordion"/)
    assert.match(out, /wp-block-accordion-heading__toggle/)
    assert.match(out, /<li>One<\/li>/)
    assert.ok(!out.includes('<!--'))
  })

  test('an unrelated edit elsewhere in the document does not disturb the passthrough node', () => {
    win.setContent('<p>hello</p>' + ACCORDION_CLASS_ONLY)
    editor.commands.setTextSelection(1)
    editor.commands.insertContent('X')
    const out = win.getContent()
    assert.match(out, /Xhello|helloX/)
    assert.match(out, /wp-block-accordion-heading__toggle/)
  })

  test('renders a static card, not the raw accordion markup, in the editor DOM', () => {
    win.setContent(ACCORDION_CLASS_ONLY)
    const card = win.document.querySelector('.passthrough-card')
    assert.ok(card, 'expected a .passthrough-card element in the editor DOM')
    assert.match(card.textContent, /Accordion/)
    assert.equal(win.document.querySelector('#editor button.wp-block-accordion-heading__toggle'), null)
  })
})

describe('gutenbergPassthrough — comment-wrapped markup', () => {
  const ACCORDION_WITH_COMMENTS =
    '<!-- wp:accordion {"autoclose":false} -->\n' +
    ACCORDION_CLASS_ONLY +
    '\n<!-- /wp:accordion -->'

  test('recovers blockName and attrsJSON from adjacent comments', () => {
    win.setContent(ACCORDION_WITH_COMMENTS)
    const nodes = nodesOfType('gutenbergPassthrough')
    assert.equal(nodes.length, 1)
    assert.equal(nodes[0].attrs.blockName, 'accordion')
    assert.equal(nodes[0].attrs.attrsJSON, '{"autoclose":false}')
    assert.equal(nodes[0].attrs.blockLabel, 'Accordion')
  })

  test('regenerates matching wp:accordion comments on save', () => {
    win.setContent(ACCORDION_WITH_COMMENTS)
    const out = win.getContent()
    assert.match(out, /<!-- wp:accordion \{"autoclose":false\} -->/)
    assert.match(out, /<!-- \/wp:accordion -->/)
  })
})

describe('gutenbergPassthrough — nested media blocks survive save (regression)', () => {
  const GROUP_WITH_NESTED_IMAGE =
    '<!-- wp:group -->\n' +
    '<div class="wp-block-group">\n' +
    '<!-- wp:image {"id":42} -->\n' +
    '<figure class="wp-block-image"><img src="x.jpg"/></figure>\n' +
    '<!-- /wp:image -->\n' +
    '</div>\n' +
    '<!-- /wp:group -->'

  test('a wp:image comment nested inside a passthrough wp:group survives getContent()', () => {
    win.setContent(GROUP_WITH_NESTED_IMAGE)
    const out = win.getContent()
    assert.match(out, /<!-- wp:image \{"id":42\} -->/)
    assert.match(out, /<!-- \/wp:image -->/)
    assert.match(out, /<img src="x.jpg"/)
    assert.ok(!out.includes('data-quill-passthrough'), 'marker attributes should not leak into saved HTML')
  })

  test('surviving through getContent() is stable across repeated saves (idempotent)', () => {
    win.setContent(GROUP_WITH_NESTED_IMAGE)
    const first = win.getContent()
    win.setContent(first)
    const second = win.getContent()
    assert.equal(first, second)
  })
})

describe('gutenbergPassthrough — unmodeled blocks on tags core nodes also match', () => {
  // Regression: gutenbergPassthrough used to sit at priority 1, below every
  // core node, so it only ever won on tags no other rule matched (<div>,
  // <section>, …). Any unmodeled block on a <ul>/<ol>/<pre>/<blockquote>/<hr>
  // was claimed by the core rule first — a wp-block-social-links <ul> parsed
  // as a bullet list, and its <a>/<svg> children were dropped on the next save.
  const SOCIAL_LINKS =
    '<!-- wp:social-links -->\n' +
    '<ul class="wp-block-social-links"><!-- wp:social-link {"url":"https://x.com/me","service":"x"} /-->\n' +
    '<li class="wp-block-social-link wp-social-link wp-social-link-x"><a class="wp-block-social-link-anchor" href="https://x.com/me"><svg width="24" height="24" viewBox="0 0 24 24"><path d="M1 1h5"></path></svg><span class="wp-block-social-link-label screen-reader-text">X</span></a></li></ul>\n' +
    '<!-- /wp:social-links -->'

  beforeEach(() => { win.setContent('<p></p>') })

  test('a wp-block-social-links <ul> parses as gutenbergPassthrough, not a bulletList', () => {
    win.setContent(SOCIAL_LINKS)
    const nodes = nodesOfType('gutenbergPassthrough')
    assert.equal(nodes.length, 1)
    assert.equal(nodes[0].attrs.blockLabel, 'Social Links')
    assert.equal(nodes[0].attrs.blockName, 'social-links')
    assert.equal(nodesOfType('bulletList').length, 0)
  })

  test('its anchors and icons survive a save that round-trips through Tiptap', () => {
    win.setContent(SOCIAL_LINKS)
    // Clear _rawHTML so getContent() goes through toWordPressHTML(editor.getHTML())
    editor.commands.insertContentAt(editor.state.doc.content.size, '<p>edit</p>')
    const out = win.getContent()
    assert.match(out, /href="https:\/\/x\.com\/me"/)
    assert.match(out, /<svg/)
    assert.match(out, /<!-- wp:social-links -->/)
    assert.match(out, /<!-- \/wp:social-links -->/)
    assert.ok(!out.includes('wp-block-list'), 'must not be rewritten as a Gutenberg list')
  })

  test('an unmodeled <pre> block (wp-block-verse) is preserved, not turned into a code block', () => {
    win.setContent('<pre class="wp-block-verse">one\ntwo</pre>')
    assert.equal(nodesOfType('gutenbergPassthrough').length, 1)
    assert.equal(nodesOfType('codeBlock').length, 0)
  })
})

describe('gutenbergPassthrough — does not steal elements other rules already claim', () => {
  // A setContent() call right after certain prior editor operations silently
  // no-ops exactly once — a pre-existing jsdom/Tiptap quirk (see
  // Sources/QuillKit/Resources/CLAUDE.md's setContent gotcha), reproduced
  // here by a gallery setContent immediately preceding an image setContent,
  // confirmed via git stash to occur on unmodified editor.html. Absorb it
  // with a throwaway setContent before each test in this block.
  beforeEach(() => { win.setContent('<p></p>') })

  test('a real gallery figure still parses as galleryBlock, not gutenbergPassthrough', () => {
    const html = '<figure class="wp-block-gallery has-nested-images columns-3 is-cropped">' +
      '<figure class="wp-block-image size-large"><img src="http://x.test/a.png" alt="" class="wp-image-1"></figure>' +
      '</figure>'
    win.setContent(html)
    assert.equal(nodesOfType('galleryBlock').length, 1)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
  })

  test('a real image figure still parses as image, not gutenbergPassthrough', () => {
    win.setContent('<figure class="wp-block-image"><img src="http://x.test/a.png" alt=""></figure>')
    assert.equal(nodesOfType('image').length, 1)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
  })

  test('a real embed figure still parses as embedBlock, not gutenbergPassthrough', () => {
    win.setContent('<figure class="wp-block-embed"><div class="wp-block-embed__wrapper">\nhttps://example.com/video\n</div></figure>')
    assert.equal(nodesOfType('embedBlock').length, 1)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
  })

  test('a table wrapped in figure.wp-block-table still parses as a table, not gutenbergPassthrough', () => {
    win.setContent('<figure class="wp-block-table"><table><tbody><tr><td>x</td></tr></tbody></table></figure>')
    assert.equal(nodesOfType('table').length, 1)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
  })

  test('a heading with a wp-block-heading class still parses as heading, not gutenbergPassthrough', () => {
    win.setContent('<h2 class="wp-block-heading">Title</h2>')
    assert.equal(nodesOfType('heading').length, 1)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
  })

  test('a wp-block-list <ul> still parses as a bulletList, not gutenbergPassthrough', () => {
    win.setContent('<ul class="wp-block-list"><li>One</li></ul>')
    assert.equal(nodesOfType('bulletList').length, 1)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
  })

  test('a wp-block-list <ol> still parses as an orderedList, not gutenbergPassthrough', () => {
    win.setContent('<ol class="wp-block-list"><li>One</li></ol>')
    assert.equal(nodesOfType('orderedList').length, 1)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
  })

  test('a wp-block-footnotes <ol> still parses as footnotesList, not gutenbergPassthrough', () => {
    // A marker is required: FootnoteSync's appendTransaction rebuilds the list
    // from the markers in the doc and drops a list with no matching marker.
    win.setContent('<p>Text<sup class="fn" data-fn="a"><a href="#a"></a></sup></p>' +
      '<ol class="wp-block-footnotes"><li id="a">Note</li></ol>')
    assert.equal(nodesOfType('footnotesList').length, 1)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
  })

  test('a wp-block-quote blockquote still parses as a blockquote, not gutenbergPassthrough', () => {
    win.setContent('<blockquote class="wp-block-quote"><p>Quoted</p></blockquote>')
    assert.equal(nodesOfType('blockquote').length, 1)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
  })

  test('a wp-block-code <pre> still parses as a codeBlock, not gutenbergPassthrough', () => {
    win.setContent('<pre class="wp-block-code"><code>let x = 1</code></pre>')
    assert.equal(nodesOfType('codeBlock').length, 1)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
  })

  test('a wp-block-separator <hr> still parses as a horizontalRule, not gutenbergPassthrough', () => {
    win.setContent('<hr class="wp-block-separator has-alpha-channel-opacity">')
    assert.equal(nodesOfType('horizontalRule').length, 1)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
  })
})
