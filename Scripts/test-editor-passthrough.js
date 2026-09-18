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

// core/media-text stands in for any block Quill does not model. Accordion filled
// this role until it gained real nodes.
const MEDIA_TEXT_CLASS_ONLY =
  '<div class="wp-block-media-text" data-wp-interactive="core/media-text">' +
  '<div class="wp-block-media-text__content">' +
  '<h3 class="wp-block-media-text__title"><button type="button" class="wp-block-media-text__toggle">Features</button></h3>' +
  '<div class="wp-block-media-text__body"><ul class="wp-block-list"><li>One</li></ul></div>' +
  '</div></div>'

describe('gutenbergPassthrough — class-only markup (no wp: comments)', () => {
  test('parses into a single gutenbergPassthrough node', () => {
    win.setContent(MEDIA_TEXT_CLASS_ONLY)
    const nodes = nodesOfType('gutenbergPassthrough')
    assert.equal(nodes.length, 1)
    assert.equal(nodes[0].attrs.blockLabel, 'Media Text')
    assert.equal(nodes[0].attrs.blockName, null)
  })

  test('round-trips the essential markup through getContent()', () => {
    win.setContent(MEDIA_TEXT_CLASS_ONLY)
    const out = win.getContent()
    assert.match(out, /data-wp-interactive="core\/media-text"/)
    assert.match(out, /wp-block-media-text__toggle/)
    assert.match(out, /<li>One<\/li>/)
    assert.ok(!out.includes('<!--'))
  })

  test('an unrelated edit elsewhere in the document does not disturb the passthrough node', () => {
    win.setContent('<p>hello</p>' + MEDIA_TEXT_CLASS_ONLY)
    editor.commands.setTextSelection(1)
    editor.commands.insertContent('X')
    const out = win.getContent()
    assert.match(out, /Xhello|helloX/)
    assert.match(out, /wp-block-media-text__toggle/)
  })

  test('renders a static card, not the raw media-text markup, in the editor DOM', () => {
    win.setContent(MEDIA_TEXT_CLASS_ONLY)
    const card = win.document.querySelector('.passthrough-card')
    assert.ok(card, 'expected a .passthrough-card element in the editor DOM')
    assert.match(card.textContent, /Media Text/)
    assert.equal(win.document.querySelector('#editor button.wp-block-media-text__toggle'), null)
  })
})

describe('gutenbergPassthrough — comment-wrapped markup', () => {
  const MEDIA_TEXT_WITH_COMMENTS =
    '<!-- wp:media-text {"align":"right"} -->\n' +
    MEDIA_TEXT_CLASS_ONLY +
    '\n<!-- /wp:media-text -->'

  // A delimited top-level block now goes through the exact-slice wrapper, which
  // keeps the source verbatim rather than recovering a name from the comments.
  test('is held as one exact source slice, labelled from its block name', () => {
    win.setContent(MEDIA_TEXT_WITH_COMMENTS)
    const nodes = nodesOfType('gutenbergPassthrough')
    assert.equal(nodes.length, 1)
    assert.equal(nodes[0].attrs.blockLabel, 'Media Text')
    assert.equal(nodes[0].attrs.unsupportedSource, MEDIA_TEXT_WITH_COMMENTS)
  })

  test('comes back byte-for-byte, newlines and all', () => {
    win.setContent(MEDIA_TEXT_WITH_COMMENTS)
    assert.equal(win.getContent(), MEDIA_TEXT_WITH_COMMENTS)
  })

  test('regenerates matching wp:media-text comments on save', () => {
    win.setContent(MEDIA_TEXT_WITH_COMMENTS)
    const out = win.getContent()
    assert.match(out, /<!-- wp:media-text \{"align":"right"\} -->/)
    assert.match(out, /<!-- \/wp:media-text -->/)
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
    assert.equal(nodes[0].attrs.unsupportedSource, SOCIAL_LINKS)
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

// Real WP 7.1 markup, taken from core's shipped block-library.js save() output
// (verified 2026-08-19 against a live WordPress 7.1 install). Playlist saves as
// a <figure>, which the passthrough rule's original `:not(figure)` selector
// excluded — the whole block was shredded on save.
const PLAYLIST_71 =
  '<!-- wp:playlist {"showNumbers":true} -->\n' +
  '<figure class="wp-block-playlist">' +
  '<ol class="wp-block-playlist__tracklist wp-block-playlist__tracklist-show-numbers">' +
  '<!-- wp:playlist-track {"id":42,"url":"http://x/a.mp3","title":"Track A"} -->\n' +
  '<li class="wp-block-playlist-track"><button type="button">Track A</button></li>\n' +
  '<!-- /wp:playlist-track -->' +
  '</ol><figcaption class="wp-element-caption">My playlist</figcaption></figure>\n' +
  '<!-- /wp:playlist -->'

const AUDIO_FIGURE =
  '<figure class="wp-block-audio"><audio controls src="http://x/a.mp3"></audio>' +
  '<figcaption class="wp-element-caption">Cap</figcaption></figure>'

const VIDEO_FIGURE =
  '<figure class="wp-block-video"><video controls src="http://x/v.mp4"></video></figure>'

const PULLQUOTE_FIGURE =
  '<figure class="wp-block-pullquote"><blockquote><p>Big idea</p><cite>Someone</cite></blockquote></figure>'

describe('gutenbergPassthrough — figure-rooted blocks Quill does not model', () => {
  before(() => {
    // Absorb the pre-existing jsdom/Tiptap one-shot quirk: the first setContent
    // after a doc that is a single atom node silently yields an empty <p>.
    // Reproduces on unmodified editor.html, so it is not caused by these rules.
    editor.commands.setContent('<p></p>', false)
  })

  test('a wp:playlist figure parses to gutenbergPassthrough, not shredded into loose nodes', () => {
    win.setContent(PLAYLIST_71)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 1)
    assert.equal(nodesOfType('bulletList').length, 0)
    assert.equal(nodesOfType('orderedList').length, 0)
    // Only the empty paragraph the editor keeps after a trailing atom.
    assert.ok(nodesOfType('paragraph').every(n => n.content.size === 0))
  })

  test('a wp:playlist figure survives a save byte-for-byte, comments and all', () => {
    win.setContent(PLAYLIST_71)
    const out = win.toWordPressHTML(editor.getHTML())
    const doc = new JSDOM('<body>' + out + '</body>').window.document
    const fig = doc.querySelector('figure.wp-block-playlist')
    assert.ok(fig, 'the playlist figure survived')
    assert.ok(fig.querySelector('ol.wp-block-playlist__tracklist'), 'tracklist survived')
    assert.equal(fig.querySelectorAll('li.wp-block-playlist-track').length, 1)
    assert.equal(
      fig.querySelector('figcaption.wp-element-caption').textContent,
      'My playlist',
      'the figcaption stayed a figcaption inside the figure, not hoisted to a <p>'
    )
    assert.match(out, /<!-- wp:playlist \{"showNumbers":true\} -->/)
    assert.match(out, /<!-- \/wp:playlist -->/)
  })

  test('an audio figure is preserved rather than reduced to its caption text', () => {
    win.setContent(AUDIO_FIGURE)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 1)
    const out = win.toWordPressHTML(editor.getHTML())
    const doc = new JSDOM('<body>' + out + '</body>').window.document
    const fig = doc.querySelector('figure.wp-block-audio')
    assert.ok(fig, 'the audio figure survived')
    assert.ok(fig.querySelector(':scope > audio[src="http://x/a.mp3"]'), 'the <audio> is still a direct child')
    const cap = fig.querySelector(':scope > figcaption.wp-element-caption')
    assert.ok(cap, 'the caption stayed a figcaption inside the figure')
    assert.equal(cap.textContent, 'Cap')
    assert.equal(doc.body.children.length, 1, 'nothing was hoisted out of the figure')
    // The generic figure pass adds wp-block-image to any figure containing an
    // <img>; an audio figure has none, but the class must not appear regardless.
    assert.ok(!fig.classList.contains('wp-block-image'))
  })

  test('a video figure is preserved rather than emptied', () => {
    win.setContent(VIDEO_FIGURE)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 1)
    const out = win.toWordPressHTML(editor.getHTML())
    const doc = new JSDOM('<body>' + out + '</body>').window.document
    assert.ok(doc.querySelector('figure.wp-block-video > video[src="http://x/v.mp4"]'))
  })

})

describe('gutenbergPassthrough — modeled figures still go to their own nodes', () => {
  before(() => {
    // Same one-shot jsdom quirk as above: the preceding describe leaves the doc
    // as a single atom node, which makes the next setContent no-op.
    editor.commands.setContent('<p></p>', false)
  })

  test('a wp-block-image figure still parses as an image', () => {
    win.setContent('<figure class="wp-block-image"><img src="http://x/a.jpg"></figure>')
    assert.equal(nodesOfType('image').length, 1)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
  })

  test('a wp-block-gallery figure still parses as a galleryBlock, nested image figures included', () => {
    win.setContent('<figure class="wp-block-gallery has-nested-images columns-2 is-cropped">' +
      '<figure class="wp-block-image size-large"><img src="http://x/1.jpg" class="wp-image-1"></figure>' +
      '<figure class="wp-block-image size-large"><img src="http://x/2.jpg" class="wp-image-2"></figure>' +
      '</figure>')
    assert.equal(nodesOfType('galleryBlock').length, 1)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
  })

  test('a wp-block-embed figure still parses as an embedBlock', () => {
    win.setContent('<figure class="wp-block-embed is-type-video is-provider-youtube wp-block-embed-youtube">' +
      '<div class="wp-block-embed__wrapper">\nhttps://www.youtube.com/watch?v=abc\n</div></figure>')
    assert.equal(nodesOfType('embedBlock').length, 1)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
  })

  test('a wp-block-table figure still parses as a table', () => {
    win.setContent('<figure class="wp-block-table"><table><tbody><tr><td>x</td></tr></tbody></table></figure>')
    assert.equal(nodesOfType('table').length, 1)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
  })

  test('a pullquote figure parses as a pullquote, not shredded into a plain quote', () => {
    win.setContent(PULLQUOTE_FIGURE)
    assert.equal(nodesOfType('pullquote').length, 1)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
    assert.equal(nodesOfType('blockquote').length, 0)
    const out = win.toWordPressHTML(editor.getHTML())
    const doc = new JSDOM('<body>' + out + '</body>').window.document
    const fig = doc.querySelector('figure.wp-block-pullquote')
    assert.ok(fig, 'the pullquote figure survived')
    assert.equal(doc.body.children.length, 1, 'nothing was hoisted out of the figure')
    const bq = fig.querySelector(':scope > blockquote')
    assert.ok(bq, 'the blockquote is still nested inside the figure')
    assert.equal(bq.querySelector(':scope > p').textContent, 'Big idea')
    assert.equal(bq.querySelector(':scope > cite').textContent, 'Someone')
    // A shredded pullquote would come back stamped wp-block-quote by the
    // blockquote pass; core/pullquote owns this blockquote, so it must not be.
    assert.ok(!bq.classList.contains('wp-block-quote'))
  })
})

describe('gutenbergPassthrough - figure blocks and the rest of the document', () => {
  // Every test here leaves the doc ending on a passthrough atom, which triggers
  // the documented one-shot setContent no-op. Absorb it before each test.
  beforeEach(() => { win.setContent('<p></p>') })

  test('a playlist figure is stable across repeated load/save cycles', () => {
    // The wp:name comment regeneration pass wraps passthrough elements on every
    // save; a second pass must not stack a second comment pair or drop the
    // nested wp:playlist-track comments.
    win.setContent(PLAYLIST_71)
    // Clear _rawHTML so getContent() actually re-runs toWordPressHTML.
    editor.commands.insertContentAt(editor.state.doc.content.size, '<p>edit</p>')
    const first = win.getContent()
    win.setContent(first)
    editor.commands.insertContentAt(editor.state.doc.content.size, '<p>edit</p>')
    const second = win.getContent()

    const count = (hay, needle) => hay.split(needle).length - 1
    assert.equal(count(first, '<!-- wp:playlist '), 1, 'exactly one opening comment on the first save')
    assert.equal(count(first, '<!-- /wp:playlist -->'), 1)
    assert.equal(count(first, '<!-- wp:playlist-track '), 1, 'the nested track comment survived')
    assert.equal(count(second, '<!-- wp:playlist '), 1, 'the second save did not stack a second comment pair')
    assert.equal(count(second, '<!-- /wp:playlist -->'), 1)
    assert.equal(count(second, '<!-- wp:playlist-track '), 1)
    assert.equal(
      count(second, '<figure class="wp-block-playlist">'),
      1,
      'the figure was not duplicated'
    )
  })

  test('passthrough figures keep their position among modeled blocks', () => {
    win.setContent(
      '<p>before</p>\n' +
      AUDIO_FIGURE + '\n' +
      '<h2>middle</h2>\n' +
      '<figure class="wp-block-image"><img src="http://x/b.jpg"></figure>\n' +
      '<p>after</p>'
    )
    const types = []
    editor.state.doc.forEach(n => types.push(n.type.name))
    assert.deepEqual(types, ['paragraph', 'gutenbergPassthrough', 'heading', 'image', 'paragraph'])

    const out = win.toWordPressHTML(editor.getHTML())
    const doc = new JSDOM('<body>' + out + '</body>').window.document
    const shape = Array.from(doc.body.children).map(
      el => el.tagName.toLowerCase() + (el.className ? '.' + el.className.trim().split(/\s+/)[0] : '')
    )
    assert.deepEqual(shape, ['p', 'figure.wp-block-audio', 'h2.wp-block-heading', 'figure.wp-block-image', 'p'])
    assert.equal(doc.querySelector('figure.wp-block-image img').getAttribute('src'), 'http://x/b.jpg')
  })

  test('an unmodeled figure containing an img is not rewritten into an image block', () => {
    // toWordPressHTML stamps wp-block-image on any figure holding an <img>.
    // A third-party figure block must be shielded from that pass, or a plugin's
    // markup silently turns into a core image block on the next save.
    const THIRD_PARTY =
      '<figure class="wp-block-acme-lightbox" data-zoom="true">' +
      '<img src="http://x/c.jpg" class="acme-thumb"><figcaption></figcaption></figure>'
    win.setContent(THIRD_PARTY)
    assert.equal(nodesOfType('gutenbergPassthrough').length, 1)
    assert.equal(nodesOfType('image').length, 0)

    const out = win.toWordPressHTML(editor.getHTML())
    const doc = new JSDOM('<body>' + out + '</body>').window.document
    const fig = doc.querySelector('figure.wp-block-acme-lightbox')
    assert.ok(fig, 'the third-party figure survived')
    assert.ok(!fig.classList.contains('wp-block-image'), 'not restamped as a core image block')
    assert.equal(fig.getAttribute('data-zoom'), 'true', 'arbitrary attributes preserved')
    assert.ok(fig.querySelector(':scope > figcaption'), 'the empty figcaption was not pruned')
    assert.ok(!out.includes('data-quill-passthrough'), 'marker attributes do not leak into saved HTML')
  })

  test('a classic figure with no wp-block class still parses as an image', () => {
    // The new figure rule selector is [class*="wp-block-"]; classic-editor
    // markup has no such class and must keep reaching the bare img[src] rule.
    win.setContent('<figure><img src="http://x/d.jpg" alt="Classic"></figure>')
    assert.equal(nodesOfType('gutenbergPassthrough').length, 0)
    assert.equal(nodesOfType('image').length, 1)
    const out = win.toWordPressHTML(editor.getHTML())
    const doc = new JSDOM('<body>' + out + '</body>').window.document
    const img = doc.querySelector('figure.wp-block-image > img')
    assert.ok(img, 'promoted to a Gutenberg image figure on save')
    assert.equal(img.getAttribute('alt'), 'Classic')
  })
})
