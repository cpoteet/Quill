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
