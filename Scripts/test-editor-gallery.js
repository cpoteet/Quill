'use strict'

// Live Tiptap tests for the galleryBlock node — loads the REAL editor.html in
// jsdom, same approach as test-editor-keyboard.js, because parseHTML/renderHTML
// for a custom Tiptap node can't be tested via the pure editor-transforms.js
// helpers (those only cover post-serialization DOM transforms).

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

describe('galleryBlock — insert and render', () => {
  test('inserting a galleryBlock renders wp-block-gallery figure with nested image figures', () => {
    editor.commands.setContent('<p></p>')
    editor.commands.insertContent({
      type: 'galleryBlock',
      attrs: {
        images: [
          { id: 1, url: 'http://x.test/a.png', alt: '' },
          { id: 2, url: 'http://x.test/b.png', alt: '' },
        ],
        columns: 3,
        cropped: true,
        linkTo: 'none',
      },
    })
    const html = editor.getHTML()
    assert.match(html, /<figure class="wp-block-gallery has-nested-images columns-3 is-cropped">/)
    assert.match(html, /class="wp-block-image size-large"/)
    assert.match(html, /class="wp-image-1"/)
    assert.match(html, /class="wp-image-2"/)
  })

  test('non-default sizeSlug is honored by the reconstruction render path', () => {
    editor.commands.setContent('<p></p>')
    editor.commands.insertContent({
      type: 'galleryBlock',
      attrs: {
        images: [{ id: 1, url: 'http://x.test/a.png', alt: '' }],
        columns: 3,
        cropped: true,
        linkTo: 'none',
        sizeSlug: 'medium',
      },
    })
    const html = editor.getHTML()
    assert.match(html, /class="wp-block-image size-medium"/)
  })

  test('linkTo media wraps each image in an anchor to its own url', () => {
    editor.commands.setContent('<p></p>')
    editor.commands.insertContent({
      type: 'galleryBlock',
      attrs: {
        images: [{ id: 5, url: 'http://x.test/full.png', alt: '' }],
        columns: 3,
        cropped: true,
        linkTo: 'media',
      },
    })
    const html = editor.getHTML()
    assert.match(html, /<a href="http:\/\/x\.test\/full\.png"><img[^>]*class="wp-image-5"[^>]*><\/a>/)
  })

  test('linkTo media links to fullUrl (true original), not the display-size url', () => {
    // Regression: when a non-full display Size is chosen, the anchor must still
    // point at the full-resolution original, not the smaller displayed image.
    editor.commands.setContent('<p></p>')
    editor.commands.insertContent({
      type: 'galleryBlock',
      attrs: {
        images: [{ id: 5, url: 'http://x.test/thumb.png', fullUrl: 'http://x.test/original-full.png', alt: '' }],
        columns: 3,
        cropped: true,
        linkTo: 'media',
        sizeSlug: 'thumbnail',
      },
    })
    const html = editor.getHTML()
    assert.match(html, /<a href="http:\/\/x\.test\/original-full\.png">/)
    assert.match(html, /<img[^>]*src="http:\/\/x\.test\/thumb\.png"/)
  })

  test('linkTo media falls back to url when fullUrl is absent', () => {
    editor.commands.setContent('<p></p>')
    editor.commands.insertContent({
      type: 'galleryBlock',
      attrs: {
        images: [{ id: 5, url: 'http://x.test/only.png', alt: '' }],
        columns: 3,
        cropped: true,
        linkTo: 'media',
      },
    })
    const html = editor.getHTML()
    assert.match(html, /<a href="http:\/\/x\.test\/only\.png">/)
  })

  test('cropped false omits is-cropped class', () => {
    editor.commands.setContent('<p></p>')
    editor.commands.insertContent({
      type: 'galleryBlock',
      attrs: { images: [{ id: 1, url: 'http://x.test/a.png', alt: '' }], columns: 2, cropped: false, linkTo: 'none' },
    })
    const html = editor.getHTML()
    assert.match(html, /<figure class="wp-block-gallery has-nested-images columns-2">/)
  })
})

describe('galleryBlock — load (parseHTML)', () => {
  test('loading real gallery HTML recovers images, columns, cropped, linkTo', () => {
    const realGallery =
      '<figure class="wp-block-gallery has-nested-images columns-3 is-cropped">' +
      '<figure class="wp-block-image size-large"><img src="http://localhost:8881/wp-content/uploads/2026/06/ai-writing-9.06.39-PM.png" alt="" class="wp-image-145"/></figure>' +
      '<figure class="wp-block-image size-large"><img src="http://localhost:8881/wp-content/uploads/2026/06/ai-writing-9.06.39-PM-1.png" alt="" class="wp-image-146"/></figure>' +
      '</figure>'
    editor.commands.setContent(realGallery)
    let found = null
    editor.state.doc.descendants(n => { if (n.type.name === 'galleryBlock') found = n })
    assert.ok(found, 'expected a galleryBlock node in the parsed document')
    assert.equal(found.attrs.images.length, 2)
    assert.equal(found.attrs.images[0].id, 145)
    assert.equal(found.attrs.images[0].url, 'http://localhost:8881/wp-content/uploads/2026/06/ai-writing-9.06.39-PM.png')
    assert.equal(found.attrs.columns, 3)
    assert.equal(found.attrs.cropped, true)
    assert.equal(found.attrs.linkTo, 'none')
    assert.equal(found.attrs.sizeSlug, 'large')
  })

  test('loading a gallery with a non-large size class recovers that sizeSlug', () => {
    const medium =
      '<figure class="wp-block-gallery has-nested-images columns-3 is-cropped">' +
      '<figure class="wp-block-image size-medium"><img src="http://x.test/a.png" alt="" class="wp-image-1"/></figure>' +
      '</figure>'
    editor.commands.setContent(medium)
    let found = null
    editor.state.doc.descendants(n => { if (n.type.name === 'galleryBlock') found = n })
    assert.ok(found)
    assert.equal(found.attrs.sizeSlug, 'medium')
  })

  test('loading a gallery with images linked to media recovers linkTo=media', () => {
    const linked =
      '<figure class="wp-block-gallery has-nested-images columns-3 is-cropped">' +
      '<figure class="wp-block-image size-large"><a href="http://x.test/a.png"><img src="http://x.test/a.png" alt="" class="wp-image-1"/></a></figure>' +
      '</figure>'
    editor.commands.setContent(linked)
    let found = null
    editor.state.doc.descendants(n => { if (n.type.name === 'galleryBlock') found = n })
    assert.ok(found)
    assert.equal(found.attrs.linkTo, 'media')
  })

  test('captures sourceHTML verbatim, including content the structured attrs do not model', () => {
    const captioned =
      '<figure class="wp-block-gallery has-nested-images columns-3 is-cropped">' +
      '<figure class="wp-block-image size-medium"><img src="http://x.test/a.png" alt="" class="wp-image-1"/><figcaption class="wp-element-caption">A caption</figcaption></figure>' +
      '</figure>'
    editor.commands.setContent(captioned)
    let found = null
    editor.state.doc.descendants(n => { if (n.type.name === 'galleryBlock') found = n })
    assert.ok(found)
    assert.ok(found.attrs.sourceHTML.includes('A caption'))
    assert.ok(found.attrs.sourceHTML.includes('size-medium'))
  })
})

describe('galleryBlock — verbatim re-render (sourceHTML)', () => {
  test('a loaded gallery with a caption re-renders with the caption intact', () => {
    const captioned =
      '<figure class="wp-block-gallery has-nested-images columns-3 is-cropped">' +
      '<figure class="wp-block-image size-medium"><img src="http://x.test/a.png" alt="" class="wp-image-1"/><figcaption class="wp-element-caption">A caption</figcaption></figure>' +
      '</figure>'
    editor.commands.setContent(captioned)
    const html = editor.getHTML()
    assert.ok(html.includes('A caption'))
    assert.ok(html.includes('size-medium'))
  })

  test('sheet-inserted galleries (sourceHTML null) still use the reconstruction path', () => {
    editor.commands.setContent('<p></p>')
    editor.commands.insertContent({
      type: 'galleryBlock',
      attrs: { images: [{ id: 1, url: 'http://x.test/a.png', alt: '' }], columns: 3, cropped: true, linkTo: 'none' },
    })
    let found = null
    editor.state.doc.descendants(n => { if (n.type.name === 'galleryBlock') found = n })
    assert.equal(found.attrs.sourceHTML, null)
    assert.ok(editor.getHTML().includes('size-large'))
  })
})

describe('galleryBlock — code-view round-trip', () => {
  test('serialize via toWordPressHTML then re-parse preserves a sheet-inserted gallery', () => {
    editor.commands.setContent('<p></p>')
    editor.commands.insertContent({
      type: 'galleryBlock',
      attrs: {
        images: [
          { id: 1, url: 'http://x.test/a.png', alt: '' },
          { id: 2, url: 'http://x.test/b.png', alt: '' },
        ],
        columns: 4,
        cropped: false,
        linkTo: 'media',
      },
    })
    const serialized = win.toWordPressHTML(editor.getHTML())
    assert.match(serialized, /<!-- wp:gallery /)
    editor.commands.setContent(serialized)
    let found = null
    editor.state.doc.descendants(n => { if (n.type.name === 'galleryBlock') found = n })
    assert.ok(found, 'gallery survived the code-view round trip')
    assert.equal(found.attrs.images.length, 2)
    assert.equal(found.attrs.columns, 4)
    assert.equal(found.attrs.cropped, false)
    assert.equal(found.attrs.linkTo, 'media')
  })

  test('serialize then re-parse preserves a loaded, captioned gallery verbatim', () => {
    const captioned =
      '<figure class="wp-block-gallery has-nested-images columns-3 is-cropped">' +
      '<figure class="wp-block-image size-medium"><img src="http://x.test/a.png" alt="" class="wp-image-1"/><figcaption class="wp-element-caption">A caption</figcaption></figure>' +
      '</figure>'
    editor.commands.setContent(captioned)
    const serialized = win.toWordPressHTML(editor.getHTML())
    assert.match(serialized, /"sizeSlug":"medium"/)
    editor.commands.setContent(serialized)
    let found = null
    editor.state.doc.descendants(n => { if (n.type.name === 'galleryBlock') found = n })
    assert.ok(found)
    assert.ok(found.attrs.sourceHTML.includes('A caption'))
  })
})

describe('window.insertGallery bridge function', () => {
  test('inserts a galleryBlock from a JSON payload', () => {
    editor.commands.setContent('<p></p>')
    win.insertGallery(JSON.stringify({
      images: [{ id: 9, url: 'http://x.test/z.png', alt: '' }],
      columns: 4,
      cropped: false,
      linkTo: 'none',
    }))
    let found = null
    editor.state.doc.descendants(n => { if (n.type.name === 'galleryBlock') found = n })
    assert.ok(found)
    assert.equal(found.attrs.columns, 4)
    assert.equal(found.attrs.cropped, false)
    assert.equal(found.attrs.images[0].id, 9)
  })

  test('sizeSlug from the JSON payload propagates to node attrs, defaulting to large', () => {
    editor.commands.setContent('<p></p>')
    win.insertGallery(JSON.stringify({
      images: [{ id: 9, url: 'http://x.test/z.png', alt: '' }],
      columns: 3,
      cropped: true,
      linkTo: 'none',
      sizeSlug: 'thumbnail',
    }))
    let found = null
    editor.state.doc.descendants(n => { if (n.type.name === 'galleryBlock') found = n })
    assert.equal(found.attrs.sizeSlug, 'thumbnail')

    editor.commands.setContent('<p></p>')
    win.insertGallery(JSON.stringify({
      images: [{ id: 9, url: 'http://x.test/z.png', alt: '' }],
      columns: 3,
      cropped: true,
      linkTo: 'none',
    }))
    found = null
    editor.state.doc.descendants(n => { if (n.type.name === 'galleryBlock') found = n })
    assert.equal(found.attrs.sizeSlug, 'large')
  })

  test('ignores an empty images array', () => {
    editor.commands.setContent('<p>unchanged</p>')
    win.insertGallery(JSON.stringify({ images: [], columns: 3, cropped: true, linkTo: 'none' }))
    let found = null
    editor.state.doc.descendants(n => { if (n.type.name === 'galleryBlock') found = n })
    assert.equal(found, null)
  })

  test('inserting at the end of the doc leaves a paragraph to type in', () => {
    // A gallery last in the document used to leave only a gap cursor to click,
    // which is a 0x0 widget and reads as a dot. The trailing paragraph is a real
    // caret position; the save transform drops it while it is still empty, so
    // no phantom <p></p> reaches saved HTML either way.
    editor.commands.setContent('<p>Hello world</p>')
    win.insertGallery(JSON.stringify({
      images: [{ id: 1, url: 'http://x.test/a.png', alt: '' }],
      columns: 3,
      cropped: true,
      linkTo: 'none',
    }))
    const doc = editor.state.doc
    assert.equal(doc.lastChild.type.name, 'paragraph')
    assert.equal(doc.child(doc.childCount - 2).type.name, 'galleryBlock')
    const saved = win.toWordPressHTML(editor.getHTML())
    assert.ok(!saved.includes('<p></p>'))
  })
})

describe('gap-cursor styling', () => {
  test('editor.html overrides the default gap-cursor widget to match the app caret', () => {
    // Tiptap's built-in gapCursor extension (enabled via StarterKit, never
    // disabled) renders a black horizontal bar by default wherever the caret
    // sits next to an atomic node (e.g. right after a gallery/embed) with no
    // adjacent inline content. Guard against silently losing the override
    // that restyles it to the app's blue vertical caret.
    const source = fs.readFileSync(htmlPath, 'utf8')
    assert.match(source, /\.ProseMirror-gapcursor:after\s*\{[^}]*border-left:\s*1\.5px solid #007aff/)
  })
})

describe('galleryBlock — per-image captions', () => {
  const insert = (images, extra = {}) => {
    editor.commands.setContent('<p></p>')
    editor.commands.insertContent({
      type: 'galleryBlock',
      attrs: { images, columns: 3, cropped: true, linkTo: 'none', ...extra },
    })
    return editor.getHTML()
  }

  test('a non-empty caption renders as a wp-element-caption figcaption', () => {
    const html = insert([{ id: 1, url: 'http://x.test/a.png', alt: '', caption: 'Sunrise over the bay' }])
    assert.match(html, /<figcaption class="wp-element-caption">Sunrise over the bay<\/figcaption>/)
  })

  test('each caption lands inside its own image figure', () => {
    const html = insert([
      { id: 1, url: 'http://x.test/a.png', alt: '', caption: 'First' },
      { id: 2, url: 'http://x.test/b.png', alt: '', caption: '' },
    ])
    const doc = new win.DOMParser().parseFromString(html, 'text/html')
    const figures = doc.querySelectorAll('figure.wp-block-image')
    assert.equal(figures.length, 2)
    assert.equal(figures[0].querySelector('figcaption').textContent, 'First')
    assert.equal(figures[1].querySelector('figcaption'), null)
  })

  test('an omitted caption emits no figcaption at all', () => {
    const html = insert([{ id: 1, url: 'http://x.test/a.png', alt: '' }])
    assert.doesNotMatch(html, /figcaption/)
  })

  test('caption text containing markup is escaped, not injected', () => {
    const html = insert([
      { id: 1, url: 'http://x.test/a.png', alt: '', caption: '<script>x</script> & <b>bold</b>' },
    ])
    assert.doesNotMatch(html, /<script>/)
    assert.doesNotMatch(html, /<b>bold<\/b>/)
    assert.match(html, /&lt;script&gt;/)
    assert.match(html, /&amp;/)
  })

  test('the caption follows the anchor when linkTo is media', () => {
    const html = insert(
      [{ id: 1, url: 'http://x.test/a.png', fullUrl: 'http://x.test/a-full.png', alt: '', caption: 'Linked' }],
      { linkTo: 'media' }
    )
    const doc = new win.DOMParser().parseFromString(html, 'text/html')
    const fig = doc.querySelector('figure.wp-block-image')
    assert.equal(fig.children[0].tagName, 'A')
    assert.equal(fig.children[1].tagName, 'FIGCAPTION')
  })

  test('each per-image alt lands on its own img, in order', () => {
    const html = insert([
      { id: 1, url: 'http://x.test/a.png', alt: 'First alt' },
      { id: 2, url: 'http://x.test/b.png', alt: '' },
      { id: 3, url: 'http://x.test/c.png', alt: 'Third alt' },
    ])
    const doc = new win.DOMParser().parseFromString(html, 'text/html')
    const imgs = doc.querySelectorAll('figure.wp-block-gallery img')
    assert.deepEqual(
      Array.from(imgs, i => i.getAttribute('alt')),
      ['First alt', '', 'Third alt']
    )
  })

  test('an omitted alt still emits an empty alt attribute', () => {
    // WordPress markup always carries alt=""; a missing attribute would be an
    // accessibility regression, not just a cosmetic diff.
    const html = insert([{ id: 1, url: 'http://x.test/a.png' }])
    const doc = new win.DOMParser().parseFromString(html, 'text/html')
    const img = doc.querySelector('figure.wp-block-gallery img')
    assert.equal(img.getAttribute('alt'), '')
  })

  test('alt text containing quotes and markup is escaped, not injected', () => {
    // Alt comes straight from a TextField in GallerySheet, same as caption.
    // Attribute serialization must not let it break out of the quoted value.
    const raw = 'Bob & "Al" <b>bold</b>'
    const html = insert([{ id: 1, url: 'http://x.test/a.png', alt: raw }])
    const doc = new win.DOMParser().parseFromString(html, 'text/html')
    const fig = doc.querySelector('figure.wp-block-image')
    assert.equal(fig.querySelector('img').getAttribute('alt'), raw)
    assert.equal(fig.querySelector('b'), null, 'no element escaped out of the alt attribute')
    assert.equal(fig.children.length, 1, 'nothing extra was injected into the figure')
  })
})

describe('galleryBlock — alt and caption round-trip (insert → save → re-parse)', () => {
  const images = [
    { id: 1, url: 'http://x.test/a.png', fullUrl: 'http://x.test/a-full.png', alt: 'Alt one', caption: 'Cap one' },
    { id: 2, url: 'http://x.test/b.png', alt: '', caption: '' },
    { id: 3, url: 'http://x.test/c.png', alt: 'Bob & "Al" <b>', caption: 'Tom & <em>Jerry</em>' },
  ]

  const galleryAttrs = () => {
    let attrs = null
    editor.state.doc.descendants(node => {
      if (node.type.name === 'galleryBlock') attrs = node.attrs
    })
    return attrs
  }

  // The exact payload PostEditorView builds from GallerySelection — one dict per
  // image with id/url/fullUrl/alt/caption — handed to window.insertGallery.
  const insertViaBridge = () => {
    editor.commands.setContent('<p></p>')
    win.insertGallery(JSON.stringify({
      images, columns: 3, cropped: true, linkTo: 'none', sizeSlug: 'large',
    }))
  }

  // Attr arrays are created inside the jsdom realm, so their prototype is not
  // node's Array — re-materialize with node's Array.from before deep-comparing.
  const pluck = (images, key) => Array.from(images, i => i[key])

  test('alt and caption from the JSON bridge payload reach the node attrs', () => {
    insertViaBridge()
    const got = galleryAttrs().images
    assert.deepEqual(pluck(got, 'alt'), ['Alt one', '', 'Bob & "Al" <b>'])
    assert.deepEqual(pluck(got, 'caption'), ['Cap one', '', 'Tom & <em>Jerry</em>'])
  })

  test('alt and caption survive save and re-parse, per image and in order', () => {
    insertViaBridge()
    const saved = win.toWordPressHTML(editor.getHTML())
    editor.commands.setContent(saved, false)
    const got = galleryAttrs().images
    assert.deepEqual(pluck(got, 'id'), [1, 2, 3])
    assert.deepEqual(pluck(got, 'alt'), ['Alt one', '', 'Bob & "Al" <b>'])
    assert.deepEqual(pluck(got, 'caption'), ['Cap one', '', 'Tom & <em>Jerry</em>'])
  })

  test('each caption is saved inside its own wp:image comment pair', () => {
    insertViaBridge()
    const saved = win.toWordPressHTML(editor.getHTML())
    // Split on the opening comment: segment i+1 is image i's own block.
    const blocks = saved.split('<!-- wp:image ').slice(1)
    assert.equal(blocks.length, 3)
    assert.match(blocks[0], /<figcaption class="wp-element-caption">Cap one<\/figcaption>[\s\S]*<!-- \/wp:image -->/)
    assert.doesNotMatch(blocks[1].split('<!-- /wp:image -->')[0], /figcaption/)
    assert.match(blocks[2], /<figcaption class="wp-element-caption">Tom &amp; &lt;em&gt;Jerry&lt;\/em&gt;<\/figcaption>/)
  })

  test('saving a captioned gallery is idempotent', () => {
    insertViaBridge()
    const once = win.toWordPressHTML(editor.getHTML())
    assert.equal(win.toWordPressHTML(once), once)
  })
})

describe('galleryBlock — parsing captions from loaded galleries', () => {
  const LOADED =
    '<figure class="wp-block-gallery has-nested-images columns-2 is-cropped">' +
    '<figure class="wp-block-image size-large"><img src="http://x.test/a.png" alt="" class="wp-image-1">' +
    '<figcaption class="wp-element-caption">Loaded caption</figcaption></figure>' +
    '<figure class="wp-block-image size-large"><img src="http://x.test/b.png" alt="" class="wp-image-2"></figure>' +
    '</figure>'

  const galleryAttrs = () => {
    let attrs = null
    editor.state.doc.descendants(node => {
      if (node.type.name === 'galleryBlock') attrs = node.attrs
    })
    return attrs
  }

  test('a caption on a loaded image figure is extracted into node attrs', () => {
    editor.commands.setContent(LOADED, false)
    const attrs = galleryAttrs()
    assert.equal(attrs.images[0].caption, 'Loaded caption')
  })

  test('an image with no figcaption parses to an empty caption', () => {
    editor.commands.setContent(LOADED, false)
    const attrs = galleryAttrs()
    assert.equal(attrs.images[1].caption, '')
  })

  test('a loaded gallery still re-renders verbatim from sourceHTML', () => {
    editor.commands.setContent(LOADED, false)
    assert.match(editor.getHTML(), /<figcaption class="wp-element-caption">Loaded caption<\/figcaption>/)
  })
})

describe('galleryBlock — captions survive load → edit → save', () => {
  // Every debounced save runs toWordPressHTML(editor.getHTML()) over the whole
  // document, including a loaded gallery's verbatim sourceHTML. That is the path
  // where the greedy comment-strip regex once ate the image figures between two
  // wp:image comments; captions add another figcaption between them, so guard it
  // with a multi-image, fully-captioned gallery and a real intervening edit.
  const LOADED_TWO_CAPTIONS =
    '<figure class="wp-block-gallery has-nested-images columns-2 is-cropped">' +
    '<figure class="wp-block-image size-large"><img src="http://x.test/a.png" alt="A" class="wp-image-1">' +
    '<figcaption class="wp-element-caption">Cap A</figcaption></figure>' +
    '<figure class="wp-block-image size-large"><img src="http://x.test/b.png" alt="B" class="wp-image-2">' +
    '<figcaption class="wp-element-caption">Cap B</figcaption></figure>' +
    '</figure>'

  const saveAfterEdit = () => {
    editor.commands.setContent('<p>Intro</p>' + LOADED_TWO_CAPTIONS, false)
    editor.commands.focus('start')
    editor.commands.insertContent('X')   // an ordinary visual edit elsewhere in the doc
    return win.toWordPressHTML(editor.getHTML())
  }

  test('both images and both captions are still there after an edit and save', () => {
    const saved = saveAfterEdit()
    const doc = new win.DOMParser().parseFromString(saved, 'text/html')
    const figures = doc.querySelectorAll('figure.wp-block-gallery figure.wp-block-image')
    assert.equal(figures.length, 2, 'no image figure was consumed by the comment strip')
    assert.deepEqual(
      Array.from(figures, f => f.querySelector('figcaption').textContent),
      ['Cap A', 'Cap B']
    )
    assert.deepEqual(
      Array.from(figures, f => f.querySelector('img').getAttribute('alt')),
      ['A', 'B']
    )
    assert.match(saved, /<p>XIntro<\/p>/, 'the intervening edit really happened')
  })

  test('the edited save is idempotent — captions do not duplicate or drift', () => {
    const saved = saveAfterEdit()
    assert.equal(win.toWordPressHTML(saved), saved)
    assert.equal((saved.match(/<figcaption/g) || []).length, 2)
    assert.equal((saved.match(/<!-- wp:image /g) || []).length, 2)
  })
})
