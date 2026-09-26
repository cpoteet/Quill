'use strict'

const { test, describe } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('fs')
const path = require('path')

const { parseBlocks } = require('../Sources/QuillKit/Resources/block-parser.js')
const reference = require('@wordpress/block-serialization-default-parser').parse

function strip(blocks) {
  return blocks.map(({ start, end, closed, innerBlocks, ...rest }) => ({
    ...rest,
    innerBlocks: strip(innerBlocks),
  }))
}

function slices(html, blocks) {
  return blocks.map(b => html.slice(b.start, b.end))
}

function countUnclosed(blocks) {
  return blocks.reduce((n, b) => n + (b.closed === false ? 1 : 0) + countUnclosed(b.innerBlocks), 0)
}

function mulberry32(seed) {
  return () => {
    seed |= 0
    seed = (seed + 0x6d2b79f5) | 0
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

const fixtureDir = path.resolve(__dirname, 'fixtures')
const fixtures = [fixtureDir, path.join(fixtureDir, 'ai')].flatMap(dir =>
  fs.readdirSync(dir)
    .filter(f => f.endsWith('.html'))
    .map(f => ({ name: path.relative(fixtureDir, path.join(dir, f)), src: fs.readFileSync(path.join(dir, f), 'utf8') }))
)

const edgeCases = [
  ['whitespace between blocks', '<!-- wp:a /-->\n\n<!-- wp:b /-->'],
  ['leading and trailing text', '  <!-- wp:a /-->  '],
  ['invalid attribute JSON', '<!-- wp:a {"x":} /-->'],
  ['one unclosed block', '<!-- wp:a --><p>x'],
  ['stray closer before a valid block', '<p>A</p><!-- /wp:a --><p>B</p><!-- wp:c /-->'],
  ['closer with the wrong name', '<!-- wp:a -->x<!-- /wp:b -->y'],
  ['text around a nested block', '<!-- wp:a -->1<!-- wp:b -->2<!-- /wp:b -->3<!-- /wp:a -->'],
  ['no space after <!--', '<!--wp:a /-->'],
  ['uppercase name', '<!-- wp:A /-->'],
  ['namespaced name', '<!-- wp:acme/w-x_1 /-->'],
  ['}  --> inside an attribute string', '<!-- wp:a {"s":"}  -->"} /-->'],
  ['attributes spanning lines', '<!-- wp:a {\n"x":1\n} /-->'],
  ['attributes on a closer', '<!-- wp:a -->x<!-- /wp:a {"y":1} -->'],
  ['closer after a self-closing block', '<!-- wp:a /-->x<!-- /wp:a -->'],
  ['empty input', ''],
  ['empty block', '<!-- wp:a --><!-- /wp:a -->'],
  ['array in place of attributes', '<!-- wp:a [1] /-->'],
  ['tab and CRLF as delimiter whitespace', '<!--\twp:a\r\n/-->'],
  ['runs of spaces around attributes', '<!-- wp:a  {"x":1}   /-->'],
  ['delimiter inside a script', '<!-- wp:html --><script>"<!-- wp:a /-->"</script><!-- /wp:html -->'],
  ['delimiter inside an attribute value', '<p title="<!-- wp:a /-->">x</p>'],
  ['empty nested block', '<!-- wp:c --><!-- wp:b --><!-- /wp:b -->x<!-- /wp:c -->'],
  ['nested block ending in an inner block', '<!-- wp:c --><!-- wp:b -->z<!-- wp:d /--><!-- /wp:b --><!-- /wp:c -->'],
  ['closer with a self-closing slash', '<!-- wp:a -->x<!-- /wp:a /-->y'],
  ['no-break space after attributes', '<!-- wp:a {"x":1} /-->'],
  ['form feed after attributes', '<!-- wp:a {"x":1}\f-->x<!-- /wp:a -->'],
  ['no-break space before attributes', '<!-- wp:a {"x":1} /-->'],
]

const NAMES = ['a', 'b', 'core/c', 'acme/w-x_1', 'A']
const ATTRS = ['', '{"x":1}', '{"x":}', '{"s":"}  -->"}', '{\n"y":2\n}', '[1]']
const NEAR_MISSES = ['<!--wp:a -->', '<!-- wp:a-->', '<!-- -->', '<!-- wp: -->']
const TEXT = ['<p>t</p>', 'x', '  ', '\n\n', '}', ' -->', 'é😀']

function generate(count) {
  const rand = mulberry32(20260925)
  const pick = list => list[Math.floor(rand() * list.length)]
  const inputs = []
  for (let i = 0; i < count; i++) {
    const pieces = []
    const length = Math.floor(rand() * 13)
    for (let j = 0; j < length; j++) {
      const kind = rand()
      if (kind < 0.55) {
        const name = pick(NAMES)
        const attrs = pick(ATTRS)
        const attrsPart = attrs ? attrs + ' ' : ''
        const form = pick(['open', 'close', 'void'])
        if (form === 'open') pieces.push(`<!-- wp:${name} ${attrsPart}-->`)
        else if (form === 'close') pieces.push(`<!-- /wp:${name} ${attrsPart}-->`)
        else pieces.push(`<!-- wp:${name} ${attrsPart}/-->`)
      } else if (kind < 0.65) {
        pieces.push(pick(NEAR_MISSES))
      } else {
        pieces.push(pick(TEXT))
      }
    }
    inputs.push(pieces.join(''))
  }
  return inputs
}

const generated = generate(2000)
const nestedUnclosed = '<!-- wp:a --><!-- wp:b --><p>x'
const nonASCII = 'é<!-- wp:a -->😀字<!-- /wp:a -->😀'

const allInputs = [
  ...fixtures.map(f => f.src),
  ...edgeCases.map(([, src]) => src),
  ...generated,
  nestedUnclosed,
  nonASCII,
]

describe('matches WordPress', () => {
  for (const { name, src } of fixtures) {
    test(`fixture ${name}`, () => {
      assert.deepEqual(strip(parseBlocks(src)), reference(src))
    })
  }

  for (const [name, src] of edgeCases) {
    test(name, () => {
      assert.deepEqual(strip(parseBlocks(src)), reference(src))
    })
  }

  test('matches WordPress on 2,000 generated inputs', () => {
    let skipped = 0
    for (const src of generated) {
      const ours = parseBlocks(src)
      if (countUnclosed(ours) >= 2) {
        skipped++
        continue
      }
      assert.deepEqual(strip(ours), reference(src), `input: ${JSON.stringify(src)}`)
    }
    assert.ok(skipped < 500, `skipped ${skipped} of ${generated.length}`)
  })
})

test('two unclosed blocks nest instead of repeating text', () => {
  const result = parseBlocks(nestedUnclosed)
  assert.equal(result.length, 1)
  assert.equal(result[0].blockName, 'core/a')
  assert.equal(result[0].closed, false)
  assert.deepEqual(result[0].innerContent, [null])
  assert.equal(result[0].innerHTML, '')
  const inner = result[0].innerBlocks[0]
  assert.equal(inner.blockName, 'core/b')
  assert.equal(inner.closed, false)
  assert.equal(inner.innerHTML, '<p>x')
  const allHTML = blocks => blocks.flatMap(b => [b.innerHTML, ...allHTML(b.innerBlocks)])
  assert.equal(allHTML(result).join('').split('<p>x').length - 1, 1)
})

test('top-level slices join back into the input', () => {
  for (const src of allInputs) {
    assert.equal(slices(src, parseBlocks(src)).join(''), src, `input: ${JSON.stringify(src)}`)
  }
})

test('positions frame each block', () => {
  function check(src, block, parent) {
    const slice = src.slice(block.start, block.end)
    const where = `input: ${JSON.stringify(src)}, block: ${JSON.stringify(slice)}`
    if (block.blockName) {
      assert.ok(slice.startsWith('<!--'), where)
      if (block.closed !== false) assert.ok(slice.endsWith('-->'), where)
    } else if (!parent) {
      assert.equal(slice, block.innerHTML, where)
    }
    if (parent) assert.ok(block.start >= parent.start && block.end <= parent.end, where)
    for (const child of block.innerBlocks) check(src, child, block)
  }
  for (const src of allInputs) {
    for (const block of parseBlocks(src)) check(src, block, null)
  }
})

test('non-ASCII text keeps exact offsets', () => {
  assert.deepEqual(slices(nonASCII, parseBlocks(nonASCII)), ['é', '<!-- wp:a -->😀字<!-- /wp:a -->', '😀'])
})

test('a long run of unterminated attributes parses in under a second', () => {
  const src = '<!-- wp:a {'.repeat(5000)
  const started = performance.now()
  parseBlocks(src)
  assert.ok(performance.now() - started < 1000)
})
