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
