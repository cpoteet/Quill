'use strict'

const { test, describe } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('fs')
const path = require('path')

const bundlePath = path.resolve(__dirname, '../Sources/QuillKit/Resources/block-parser-bundle.js')

function loadParser() {
  const src = fs.readFileSync(bundlePath, 'utf8')
  const sandbox = {}
  new Function('window', src + '\nwindow.BlockParser = BlockParser')(sandbox)
  return sandbox.BlockParser
}

describe('block parser bundle', () => {
  test('parses a delimited paragraph', () => {
    const blocks = loadParser().parse('<!-- wp:paragraph --><p>Hi</p><!-- /wp:paragraph -->')
    const real = blocks.filter(b => b.blockName)
    assert.equal(real.length, 1)
    assert.equal(real[0].blockName, 'core/paragraph')
    assert.equal(real[0].innerHTML.trim(), '<p>Hi</p>')
  })

  test('parses undelimited HTML as a freeform block', () => {
    const blocks = loadParser().parse('<p>Classic</p>')
    assert.equal(blocks.length, 1)
    assert.equal(blocks[0].blockName, null)
  })
})

function loadSerializer() {
  const src = fs.readFileSync(
    path.resolve(__dirname, '../Sources/QuillKit/Resources/block-serializer.js'), 'utf8')
  const sandbox = {}
  new Function('module', 'exports', src + '\nmodule.exports = { serializeBlocks, serializeBlock }')(
    sandbox, sandbox)
  return sandbox.exports
}

describe('block serializer', () => {
  const { serializeBlocks } = loadSerializer()
  const parse = loadParser().parse

  test('round-trips a paragraph byte-identically', () => {
    const src = '<!-- wp:paragraph --><p>Hi</p><!-- /wp:paragraph -->'
    assert.equal(serializeBlocks(parse(src)), src)
  })

  test('round-trips attributes without reordering or re-spacing', () => {
    const src = '<!-- wp:heading {"level":3} --><h3>T</h3><!-- /wp:heading -->'
    assert.equal(serializeBlocks(parse(src)), src)
  })

  test('round-trips nested blocks at their innerContent slots', () => {
    const src = '<!-- wp:group --><div class="wp-block-group">' +
      '<!-- wp:paragraph --><p>In</p><!-- /wp:paragraph -->' +
      '</div><!-- /wp:group -->'
    assert.equal(serializeBlocks(parse(src)), src)
  })

  test('passes freeform content through untouched', () => {
    const src = '<p>Classic</p>'
    assert.equal(serializeBlocks(parse(src)), src)
  })

  test('strips the core/ prefix in delimiters', () => {
    const out = serializeBlocks(parse('<!-- wp:separator /-->'))
    assert.match(out, /wp:separator/)
    assert.doesNotMatch(out, /core\//)
  })
})

describe('fixture round-trips', () => {
  const { serializeBlocks } = loadSerializer()
  const parse = loadParser().parse
  const fixturesDir = path.resolve(__dirname, 'fixtures')

  for (const name of fs.readdirSync(fixturesDir).filter(f => f.endsWith('.html'))) {
    test(`${name} survives parse → serialize byte-identically`, () => {
      const src = fs.readFileSync(path.join(fixturesDir, name), 'utf8')
      assert.equal(serializeBlocks(parse(src)), src)
    })
  }
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

  test('level 2 headings emit level 2, not a default', () => {
    const el = { tagName: 'H2', className: '', getAttribute: () => null }
    assert.deepEqual(descriptorFor('heading').attrsFrom(el), { level: 2 })
  })
})

function loadTransforms() {
  return require('../Sources/QuillKit/Resources/editor-transforms.js')
}

describe('blockSourceSlices', () => {
  const { blockSourceSlices } = loadTransforms()
  const parse = loadParser().parse
  const { serializeBlock } = loadSerializer()
  const slices = src => blockSourceSlices(src, parse, serializeBlock)

  test('a canonical block yields an exact slice of the original', () => {
    const src = '<!-- wp:heading {"level":2} --><h2>T</h2><!-- /wp:heading -->'
    const out = slices(src)
    assert.equal(out.length, 1)
    assert.equal(out[0].source, src)
    assert.equal(out[0].exact, true)
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

  test('a self-closing block yields an exact slice', () => {
    const src = '<!-- wp:calendar /-->'
    const out = slices(src)
    assert.equal(out[0].source, src)
    assert.equal(out[0].exact, true)
  })

  test('freeform content is reported with a null blockName', () => {
    const out = slices('<p>Classic</p>')
    assert.equal(out.length, 1)
    assert.equal(out[0].blockName, null)
    assert.equal(out[0].exact, true)
  })

  test('non-canonical attribute formatting falls back, marked inexact', () => {
    const src = '<!-- wp:column {"width":33.0} --><div class="wp-block-column"></div><!-- /wp:column -->'
    const out = slices(src)
    assert.equal(out[0].exact, false)
    assert.equal(out[0].source, '<!-- wp:column {"width":33} --><div class="wp-block-column"></div><!-- /wp:column -->')
  })

  test('an inexact block does not desynchronise the blocks after it', () => {
    const src = '<!-- wp:column {"width":33.0} --><div class="wp-block-column"></div><!-- /wp:column -->' +
                '<!-- wp:heading {"level":3} --><h3>After</h3><!-- /wp:heading -->'
    const out = slices(src)
    assert.equal(out.length, 2)
    assert.equal(out[1].exact, true)
    assert.equal(out[1].source, '<!-- wp:heading {"level":3} --><h3>After</h3><!-- /wp:heading -->')
  })

  // An inexact block's own source is always a faithful serialisation, so the
  // worst a mis-landed cursor can do is mark later blocks inexact too.
  test('an inexact nested block still yields faithful sources for what follows', () => {
    const src = '<!-- wp:query {"x":1.0} --><div class="wp-block-query"><!-- wp:post-title --><h2>T</h2><!-- /wp:post-title --></div><!-- /wp:query -->' +
                '<!-- wp:heading {"level":3} --><h3>After</h3><!-- /wp:heading -->'
    const out = slices(src)
    assert.equal(out.length, 2)
    assert.equal(out[0].source, '<!-- wp:query {"x":1} --><div class="wp-block-query"><!-- wp:post-title --><h2>T</h2><!-- /wp:post-title --></div><!-- /wp:query -->')
    assert.equal(out[1].source, '<!-- wp:heading {"level":3} --><h3>After</h3><!-- /wp:heading -->')
  })

  test('an inexact self-closing block still yields a faithful source for what follows', () => {
    const src = '<!-- wp:calendar {"x":1e3} /--><!-- wp:heading {"level":3} --><h3>After</h3><!-- /wp:heading -->'
    const out = slices(src)
    assert.equal(out.length, 2)
    assert.equal(out[0].source, '<!-- wp:calendar {"x":1000} /-->')
    assert.equal(out[1].source, '<!-- wp:heading {"level":3} --><h3>After</h3><!-- /wp:heading -->')
  })
})

describe('blockSourceSlices over the real fixtures', () => {
  const { blockSourceSlices } = loadTransforms()
  const parse = loadParser().parse
  const { serializeBlock } = loadSerializer()
  const dir = path.resolve(__dirname, 'fixtures')

  for (const name of fs.readdirSync(dir).filter(f => f.endsWith('.html'))) {
    test(`${name} yields exact slices for every block`, () => {
      const src = fs.readFileSync(path.join(dir, name), 'utf8')
      const out = blockSourceSlices(src, parse, serializeBlock)
      assert.ok(out.every(s => s.exact), 'every block exact')
      assert.equal(out.map(s => s.source).join(''), src)
    })
  }
})

describe('blockNeedsWrapping', () => {
  const { blockSourceSlices, blockNeedsWrapping } = loadTransforms()
  const parse = loadParser().parse
  const { serializeBlock } = loadSerializer()
  const { JSDOM } = require('jsdom')
  const doc = new JSDOM('<body></body>').window.document
  const decide = src => blockSourceSlices(src, parse, serializeBlock).map(s => blockNeedsWrapping(s, doc))

  test('a block with a wp-block class root is left alone', () => {
    assert.deepEqual(decide('<!-- wp:spacer --><div class="wp-block-spacer"></div><!-- /wp:spacer -->'), [false])
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

  test('a nested block inside a claimed block does not make the parent wrap', () => {
    const src = '<!-- wp:query --><div class="wp-block-query"><!-- wp:post-title /--></div><!-- /wp:query -->'
    assert.deepEqual(decide(src), [false])
  })
})

describe('wrapUnsupportedBlocks', () => {
  const { wrapUnsupportedBlocks } = loadTransforms()
  const parse = loadParser().parse
  const { serializeBlock } = loadSerializer()
  const { JSDOM } = require('jsdom')
  const doc = new JSDOM('<body></body>').window.document
  const wrap = src => wrapUnsupportedBlocks(src, parse, serializeBlock, doc)

  test('leaves a fully supported post untouched', () => {
    const src = '<!-- wp:paragraph --><p>Hi</p><!-- /wp:paragraph -->'
    assert.equal(wrap(src), src)
  })

  // unsupported-blocks.html is the deliberate counter-example, asserted below.
  test('leaves every real-site fixture untouched', () => {
    const dir = path.resolve(__dirname, 'fixtures')
    const capture = f => f.endsWith('.html') && f !== 'unsupported-blocks.html'
    for (const name of fs.readdirSync(dir).filter(capture)) {
      const src = fs.readFileSync(path.join(dir, name), 'utf8')
      assert.equal(wrap(src), src, name)
    }
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

describe('unrepresentedBlockNames', () => {
  const { unrepresentedBlockNames } = loadTransforms()
  const slice = (blockName) => ({ blockName, attrsJSON: null, source: '', exact: true })

  test('reports nothing when every block is accounted for', () => {
    const out = unrepresentedBlockNames([slice('core/heading'), slice('core/calendar')], new Set(['heading', 'calendar']))
    assert.deepEqual(out, [])
  })

  test('reports a block the document does not hold', () => {
    const out = unrepresentedBlockNames([slice('core/heading'), slice('core/calendar')], new Set(['heading']))
    assert.deepEqual(out, ['calendar'])
  })

  test('ignores freeform blocks, which are prose not blocks', () => {
    assert.deepEqual(unrepresentedBlockNames([slice(null)], new Set()), [])
  })

  test('strips the core prefix and de-duplicates', () => {
    const out = unrepresentedBlockNames([slice('core/calendar'), slice('core/calendar')], new Set())
    assert.deepEqual(out, ['calendar'])
  })

  test('keeps a third-party namespace intact', () => {
    assert.deepEqual(unrepresentedBlockNames([slice('acme/widget')], new Set()), ['acme/widget'])
  })
})
