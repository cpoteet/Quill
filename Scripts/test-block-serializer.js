'use strict'

const { test, describe, after } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('fs')
const path = require('path')

function loadParser() {
  return require('../Sources/QuillKit/Resources/block-parser.js')
}

describe('block parser', () => {
  test('parses a delimited paragraph', () => {
    const blocks = loadParser().parseBlocks('<!-- wp:paragraph --><p>Hi</p><!-- /wp:paragraph -->')
    const real = blocks.filter(b => b.blockName)
    assert.equal(real.length, 1)
    assert.equal(real[0].blockName, 'core/paragraph')
    assert.equal(real[0].innerHTML.trim(), '<p>Hi</p>')
  })

  test('parses undelimited HTML as a freeform block', () => {
    const blocks = loadParser().parseBlocks('<p>Classic</p>')
    assert.equal(blocks.length, 1)
    assert.equal(blocks[0].blockName, null)
  })
})

describe('serializeAttributes matches WordPress', () => {
  const { serializeAttributes } = require('../Sources/QuillKit/Resources/editor-transforms.js')
  const validator = require('./wp-validator.js')
  const { serializeRawBlock } = require('@wordpress/blocks')
  const reference = attrs => {
    const out = serializeRawBlock({ blockName: 'core/a', attrs, innerBlocks: [], innerContent: [] })
    return out.slice('<!-- wp:a '.length, -' /-->'.length)
  }
  after(() => validator.close())

  const cases = [
    ['an ampersand', { url: 'https://y.test/?v=a&t=10s' }],
    ['angle brackets', { a: '<b>' }],
    ['a double hyphen', { b: 'x--y' }],
    ['an odd run of hyphens', { b: '---' }],
    ['an even run of hyphens', { b: '----' }],
    ['a comment opener and closer', { b: '<!-- x -->' }],
    ['a backslash', { a: 'c:\\path' }],
    ['an embedded quote', { b: 'say "hi"' }],
    ['a backslash before a quote', { b: '\\"' }],
    ['a trailing backslash', { b: 'end\\' }],
    ['a newline and a tab', { b: 'a\n\tb' }],
    ['a line separator and an emoji', { b: '\u2028😀é' }],
    ['a special character in a key', { 'k<-->&"': 1 }],
    ['nested objects and arrays', { a: [1, -1, 'x--', { c: null, d: true }], e: 0.1, f: 1e21 }],
  ]
  for (const [name, attrs] of cases) {
    test(name, () => assert.equal(serializeAttributes(attrs), reference(attrs)))
  }

  test('2,000 generated attribute objects', () => {
    let seed = 20260926
    const rand = () => {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff
      return seed / 0x80000000
    }
    const pieces = ['-', '--', '<', '>', '&', '\\', '"', "'", '/', 'a', ' ', '\n', '\u2028', '😀', '{', '}', '\u00a0']
    const text = () => Array.from({ length: Math.floor(rand() * 8) }, () => pieces[Math.floor(rand() * pieces.length)]).join('')
    const value = depth => {
      const kind = Math.floor(rand() * (depth > 1 ? 4 : 6))
      if (kind === 0) return text()
      if (kind === 1) return Math.floor(rand() * 200) - 100
      if (kind === 2) return rand() < 0.5
      if (kind === 3) return null
      if (kind === 4) return Array.from({ length: Math.floor(rand() * 3) }, () => value(depth + 1))
      return Object.fromEntries(Array.from({ length: Math.floor(rand() * 3) }, () => [text(), value(depth + 1)]))
    }
    for (let i = 0; i < 2000; i++) {
      const attrs = Object.fromEntries(Array.from({ length: 1 + Math.floor(rand() * 3) }, () => [text(), value(0)]))
      assert.equal(serializeAttributes(attrs), reference(attrs), JSON.stringify(attrs))
    }
  })
})

function loadDescriptors() {
  const src = fs.readFileSync(
    path.resolve(__dirname, '../Sources/QuillKit/Resources/block-descriptors.js'), 'utf8')
  const sandbox = {}
  new Function('module', 'exports', src + '\nmodule.exports = { BLOCK_DESCRIPTORS, descriptorFor }')(
    sandbox, sandbox)
  return sandbox.exports
}

describe('block descriptors', () => {
  const { descriptorFor } = loadDescriptors()

  test('maps heading to core/heading with its level attribute', () => {
    const d = descriptorFor('heading')
    assert.equal(d.blockName, 'core/heading')
    assert.equal(d.shape, 'text')
    const el = { tagName: 'H3', className: 'wp-block-heading', getAttribute: () => null }
    assert.deepEqual(d.attrsFrom(el), { level: 3 })
  })

  test('maps paragraph to core/paragraph with no attributes', () => {
    const d = descriptorFor('paragraph')
    assert.equal(d.blockName, 'core/paragraph')
    const el = { tagName: 'P', className: '', getAttribute: () => null }
    assert.deepEqual(d.attrsFrom(el), {})
  })

  test('returns null for an unknown node', () => {
    assert.equal(descriptorFor('nonesuch'), null)
  })

  // core/heading's level defaults to 2 and core omits a default, so emitting it
  // put a key in every h2's comment that WordPress itself never writes.
  test('level 2 headings emit no level, the way core writes them', () => {
    const el = { tagName: 'H2', className: '', getAttribute: () => null }
    assert.deepEqual(descriptorFor('heading').attrsFrom(el), {})
  })

  test('every other level is emitted', () => {
    for (const tag of ['H1', 'H3', 'H4', 'H5', 'H6']) {
      const el = { tagName: tag, className: '', getAttribute: () => null }
      assert.deepEqual(descriptorFor('heading').attrsFrom(el), { level: parseInt(tag.slice(1), 10) })
    }
  })
})

function loadTransforms() {
  return require('../Sources/QuillKit/Resources/editor-transforms.js')
}

describe('blockSourceSlices', () => {
  const { blockSourceSlices } = loadTransforms()
  const parse = loadParser().parseBlocks
  const slices = src => blockSourceSlices(src, parse)

  test('a canonical block yields an exact slice of the original', () => {
    const src = '<!-- wp:heading {"level":2} --><h2>T</h2><!-- /wp:heading -->'
    const out = slices(src)
    assert.equal(out.length, 1)
    assert.equal(out[0].source, src)
    assert.equal(out[0].blockName, 'core/heading')
    assert.equal(out[0].attrsJSON, '{"level":2}')
  })

  test('slices concatenate back to the original', () => {
    const src = '<p>Classic</p><!-- wp:separator /--><p>More</p>'
    assert.equal(slices(src).map(s => s.source).join(''), src)
  })

  test('inter-block whitespace is preserved as a freeform slice', () => {
    const src = '<!-- wp:paragraph --><p>A</p><!-- /wp:paragraph -->\n\n<!-- wp:calendar /-->'
    const out = slices(src)
    assert.equal(out.map(s => s.source).join(''), src)
    assert.ok(out.some(s => s.blockName === null && s.source === '\n\n'))
  })

  test('a non-canonical self-closing block does not derail the blocks after it', () => {
    const src = '<!-- wp:calendar  /-->\n\n<!-- wp:paragraph -->\n<p>A</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:paragraph -->\n<p>B</p>\n<!-- /wp:paragraph -->'
    const out = slices(src)
    assert.equal(out.map(s => s.source).join(''), src)
    const named = out.filter(s => s.blockName)
    assert.deepEqual(named.map(s => s.blockName), ['core/calendar', 'core/paragraph', 'core/paragraph'])
    assert.equal(named[0].source, '<!-- wp:calendar  /-->')
  })

  test('a non-canonical opening comment keeps its own bytes', () => {
    const src = '<!-- wp:paragraph  {"dropCap":true} -->\n<p>A</p>\n<!-- /wp:paragraph -->'
    const out = slices(src)
    assert.equal(out.length, 1)
    assert.equal(out[0].source, src)
  })

  test('a nested block does not end its parent early', () => {
    const src = '<!-- wp:group -->\n<div class="wp-block-group"><!-- wp:paragraph -->\n<p>A</p>\n<!-- /wp:paragraph --></div>\n<!-- /wp:group -->\n\n<!-- wp:paragraph -->\n<p>B</p>\n<!-- /wp:paragraph -->'
    const out = slices(src).filter(s => s.blockName)
    assert.deepEqual(out.map(s => s.blockName), ['core/group', 'core/paragraph'])
    assert.equal(out[0].source, '<!-- wp:group -->\n<div class="wp-block-group"><!-- wp:paragraph -->\n<p>A</p>\n<!-- /wp:paragraph --></div>\n<!-- /wp:group -->')
  })

  test('a self-closing block yields an exact slice', () => {
    const src = '<!-- wp:calendar /-->'
    const out = slices(src)
    assert.equal(out[0].source, src)
  })

  test('freeform content is reported with a null blockName', () => {
    const out = slices('<p>Classic</p>')
    assert.equal(out.length, 1)
    assert.equal(out[0].blockName, null)
  })

  test('non-canonical attribute formatting keeps its own bytes', () => {
    const src = '<!-- wp:column {"width":33.0} --><div class="wp-block-column"></div><!-- /wp:column -->'
    const out = slices(src)
    assert.equal(out[0].source, src)
  })

  test('a non-canonical block does not desynchronise the blocks after it', () => {
    const src = '<!-- wp:column {"width":33.0} --><div class="wp-block-column"></div><!-- /wp:column -->' +
                '<!-- wp:heading {"level":3} --><h3>After</h3><!-- /wp:heading -->'
    const out = slices(src)
    assert.equal(out.length, 2)
    assert.equal(out[1].source, '<!-- wp:heading {"level":3} --><h3>After</h3><!-- /wp:heading -->')
  })

  test('a nested block with non-canonical attrs keeps its own bytes', () => {
    const src = '<!-- wp:query {"x":1.0} --><div class="wp-block-query"><!-- wp:post-title --><h2>T</h2><!-- /wp:post-title --></div><!-- /wp:query -->' +
                '<!-- wp:heading {"level":3} --><h3>After</h3><!-- /wp:heading -->'
    const out = slices(src)
    assert.equal(out.length, 2)
    assert.equal(out[0].source, '<!-- wp:query {"x":1.0} --><div class="wp-block-query"><!-- wp:post-title --><h2>T</h2><!-- /wp:post-title --></div><!-- /wp:query -->')
    assert.equal(out[1].source, '<!-- wp:heading {"level":3} --><h3>After</h3><!-- /wp:heading -->')
  })

  test('a self-closing block with non-canonical attrs keeps its own bytes', () => {
    const src = '<!-- wp:calendar {"x":1e3} /--><!-- wp:heading {"level":3} --><h3>After</h3><!-- /wp:heading -->'
    const out = slices(src)
    assert.equal(out.length, 2)
    assert.equal(out[0].source, '<!-- wp:calendar {"x":1e3} /-->')
    assert.equal(out[1].source, '<!-- wp:heading {"level":3} --><h3>After</h3><!-- /wp:heading -->')
  })

  test('an unclosed block keeps its text and gains its closing comment', () => {
    const src = '<!-- wp:group -->\n<div class="wp-block-group">unclosed'
    const out = slices(src)
    assert.equal(out.length, 1)
    assert.ok(out[0].source.startsWith(src), 'the original bytes survive')
    assert.equal(out[0].source, src + '<!-- /wp:group -->')
  })

  test('nested unclosed blocks gain closers innermost first', () => {
    const src = '<!-- wp:group --><!-- wp:acme/x -->t'
    const out = slices(src)
    assert.equal(out.length, 1)
    assert.equal(out[0].source, src + '<!-- /wp:acme/x --><!-- /wp:group -->')
  })

  test('a stray close comment is left as freeform, the way the parser reads it', () => {
    const src = '<!-- /wp:paragraph --><p>After</p>'
    const out = slices(src)
    assert.equal(out.map(s => s.source).join(''), src)
    assert.deepEqual(out.map(s => s.blockName), [null])
  })
})

describe('blockSourceSlices over the real fixtures', () => {
  const { blockSourceSlices } = loadTransforms()
  const parse = loadParser().parseBlocks
  const dir = path.resolve(__dirname, 'fixtures')

  for (const name of fs.readdirSync(dir).filter(f => f.endsWith('.html'))) {
    test(`${name} slices concatenate back to the file`, () => {
      const src = fs.readFileSync(path.join(dir, name), 'utf8')
      const out = blockSourceSlices(src, parse)
      assert.equal(out.map(s => s.source).join(''), src)
    })
  }
})

describe('blockNeedsWrapping', () => {
  const { blockSourceSlices, blockNeedsWrapping } = loadTransforms()
  const parse = loadParser().parseBlocks
  const { JSDOM } = require('jsdom')
  const doc = new JSDOM('<body></body>').window.document
  const decide = src => blockSourceSlices(src, parse).map(s => blockNeedsWrapping(s, doc))

  // Every unmodeled block goes through the exact-slice wrapper, whatever its
  // markup looks like: one preservation path, and the only byte-exact one.
  test('a block with a wp-block class root is still wrapped, because Quill does not model it', () => {
    assert.deepEqual(decide('<!-- wp:spacer --><div class="wp-block-spacer"></div><!-- /wp:spacer -->'), [true])
  })

  test('a wp:html holding a wp-block classed element is wrapped, not dismantled', () => {
    assert.deepEqual(decide('<!-- wp:html --><div class="wp-block-foo">x</div><p>y</p><!-- /wp:html -->'), [true])
  })

  test('a paragraph is left alone even though its markup carries no class', () => {
    assert.deepEqual(decide('<!-- wp:paragraph --><p>Hi</p><!-- /wp:paragraph -->'), [false])
  })

  test('every block Quill models is left alone', () => {
    const modeled = [
      '<!-- wp:paragraph --><p>A</p><!-- /wp:paragraph -->',
      '<!-- wp:heading --><h2 class="wp-block-heading">H</h2><!-- /wp:heading -->',
      '<!-- wp:list --><ul class="wp-block-list"><!-- wp:list-item --><li>x</li><!-- /wp:list-item --></ul><!-- /wp:list -->',
      '<!-- wp:quote --><blockquote class="wp-block-quote"><!-- wp:paragraph --><p>q</p><!-- /wp:paragraph --></blockquote><!-- /wp:quote -->',
      '<!-- wp:code --><pre class="wp-block-code"><code>c</code></pre><!-- /wp:code -->',
      '<!-- wp:separator --><hr class="wp-block-separator has-alpha-channel-opacity"/><!-- /wp:separator -->',
    ]
    assert.deepEqual(decide(modeled.join('')), modeled.map(() => false))
  })

  // A block that saves no markup has no node to live in, whether or not Quill
  // models its name, so the modeled exemption must not reach it.
  test('a modeled block that saves no markup is wrapped', () => {
    assert.deepEqual(decide('<!-- wp:separator /-->'), [true])
  })

  test('a modeled block that does save markup is still left alone', () => {
    assert.deepEqual(decide('<!-- wp:separator --><hr class="wp-block-separator"/><!-- /wp:separator -->'), [false])
  })

  test('core/html is wrapped, because its markup has no wp-block class', () => {
    assert.deepEqual(decide('<!-- wp:html --><div class="promo">Hi</div><!-- /wp:html -->'), [true])
  })

  test('core/shortcode is wrapped, because it has no element at all', () => {
    assert.deepEqual(decide('<!-- wp:shortcode -->[gallery ids="1,2"]<!-- /wp:shortcode -->'), [true])
  })

  test('a self-closing dynamic block is wrapped', () => {
    assert.deepEqual(decide('<!-- wp:calendar /-->'), [true])
  })

  test('a page break is wrapped', () => {
    assert.deepEqual(decide('<!-- wp:nextpage --><!--nextpage--><!-- /wp:nextpage -->'), [true])
  })

  test('freeform prose is never wrapped', () => {
    assert.deepEqual(decide('<p>Classic</p>'), [false])
  })

  test('a container Quill does not model is wrapped whole, nested blocks and all', () => {
    const src = '<!-- wp:query --><div class="wp-block-query"><!-- wp:post-title /--></div><!-- /wp:query -->'
    assert.deepEqual(decide(src), [true])
  })
})

describe('wrapUnsupportedBlocks', () => {
  const { wrapUnsupportedBlocks } = loadTransforms()
  const parse = loadParser().parseBlocks
  const { JSDOM } = require('jsdom')
  const doc = new JSDOM('<body></body>').window.document
  const wrap = src => wrapUnsupportedBlocks(src, parse, doc)

  test('leaves a fully supported post untouched', () => {
    const src = '<!-- wp:paragraph --><p>Hi</p><!-- /wp:paragraph -->'
    assert.equal(wrap(src), src)
  })

  // The fixtures that deliberately hold blocks Quill does not model; every
  // other one is supported end to end and must come through the wrap untouched.
  const HOLDS_UNMODELED = new Set([
    'unsupported-blocks.html', 'settings-group.html', 'settings-media-text.html', 'settings-spacer.html',
  ])

  test('leaves every fully supported fixture untouched', () => {
    const dir = path.resolve(__dirname, 'fixtures')
    const capture = f => f.endsWith('.html') && !HOLDS_UNMODELED.has(f)
    for (const name of fs.readdirSync(dir).filter(capture)) {
      const src = fs.readFileSync(path.join(dir, name), 'utf8')
      assert.equal(wrap(src), src, name)
    }
  })

  test('each unmodeled block in a mixed fixture is wrapped exactly once', () => {
    const dir = path.resolve(__dirname, 'fixtures')
    for (const name of ['settings-group.html', 'settings-media-text.html']) {
      const out = wrap(fs.readFileSync(path.join(dir, name), 'utf8'))
      assert.equal((out.match(/wp-block-quill-unsupported/g) || []).length, 1, name)
    }
    const spacer = wrap(fs.readFileSync(path.join(dir, 'settings-spacer.html'), 'utf8'))
    assert.equal((spacer.match(/wp-block-quill-unsupported/g) || []).length, 2, 'spacer and calendar')
  })

  test('wraps exactly the eight unsupported blocks in the corpus fixture', () => {
    const src = fs.readFileSync(path.resolve(__dirname, 'fixtures/unsupported-blocks.html'), 'utf8')
    const out = wrap(src)
    assert.equal((out.match(/wp-block-quill-unsupported/g) || []).length, 8)
    assert.match(out, /<p>Opening prose\.<\/p>/)
    assert.match(out, /<p>Closing prose\.<\/p>/)
  })

  test('replaces a shortcode block with a wrapper carrying its source', () => {
    const src = '<!-- wp:shortcode -->[gallery ids="1,2"]<!-- /wp:shortcode -->'
    const out = wrap(src)
    assert.match(out, /class="wp-block-quill-unsupported"/)
    const el = new JSDOM('<body>' + out + '</body>').window.document.querySelector('[data-quill-unsupported-source]')
    assert.equal(el.getAttribute('data-quill-unsupported-source'), src)
    assert.equal(el.getAttribute('data-quill-unsupported-label'), 'Shortcode')
  })

  test('stores quotes and ampersands in the source without corruption', () => {
    const src = '<!-- wp:html --><div data-x="a&amp;b" class="p">&lt;hi&gt;</div><!-- /wp:html -->'
    const out = wrap(src)
    const el = new JSDOM('<body>' + out + '</body>').window.document.querySelector('[data-quill-unsupported-source]')
    assert.equal(el.getAttribute('data-quill-unsupported-source'), src)
  })

  test('keeps supported blocks in place around a wrapped one', () => {
    const src = '<!-- wp:paragraph --><p>A</p><!-- /wp:paragraph -->' +
                '<!-- wp:calendar /-->' +
                '<!-- wp:paragraph --><p>B</p><!-- /wp:paragraph -->'
    const out = wrap(src)
    assert.ok(out.indexOf('<p>A</p>') < out.indexOf('wp-block-quill-unsupported'))
    assert.ok(out.indexOf('wp-block-quill-unsupported') < out.indexOf('<p>B</p>'))
  })
})

describe('countBlockNames and unrepresentedBlockNames', () => {
  const { unrepresentedBlockNames, countBlockNames } = loadTransforms()
  const parse = loadParser().parseBlocks
  const counts = src => countBlockNames(parse(src))

  test('counts every block in the tree, not just the top level', () => {
    const src = '<!-- wp:quote --><blockquote><!-- wp:heading --><h4>H</h4><!-- /wp:heading -->' +
                '<!-- wp:paragraph --><p>P</p><!-- /wp:paragraph --></blockquote><!-- /wp:quote -->'
    assert.deepEqual([...counts(src).entries()].sort(), [['heading', 1], ['paragraph', 1], ['quote', 1]])
  })

  test('counts two blocks with the same name separately', () => {
    const src = '<!-- wp:html --><p>a</p><!-- /wp:html --><!-- wp:html --><p>b</p><!-- /wp:html -->'
    assert.equal(counts(src).get('html'), 2)
  })

  test('freeform content is not a block', () => {
    assert.equal(counts('<p>Classic</p>').size, 0)
  })

  test('the core prefix is stripped and a third-party namespace is kept', () => {
    const src = '<!-- wp:calendar /--><!-- wp:acme/widget /-->'
    assert.deepEqual([...counts(src).keys()].sort(), ['acme/widget', 'calendar'])
  })

  test('reports nothing when every block is accounted for', () => {
    const expected = new Map([['heading', 1], ['calendar', 1]])
    assert.deepEqual(unrepresentedBlockNames(expected, new Map([['heading', 1], ['calendar', 1]])), [])
  })

  test('reports a block the document does not hold', () => {
    const expected = new Map([['heading', 1], ['calendar', 1]])
    assert.deepEqual(unrepresentedBlockNames(expected, new Map([['heading', 1]])), ['calendar'])
  })

  // The whole point of counting: one surviving copy used to cover for the other.
  test('reports a name the document holds fewer of than the source', () => {
    assert.deepEqual(unrepresentedBlockNames(new Map([['html', 2]]), new Map([['html', 1]])), ['html'])
  })

  test('a document holding more than the source is not a loss', () => {
    assert.deepEqual(unrepresentedBlockNames(new Map([['html', 1]]), new Map([['html', 2]])), [])
  })
})
