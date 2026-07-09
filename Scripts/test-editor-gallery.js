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
