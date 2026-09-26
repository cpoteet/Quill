'use strict'

// Holds Quill's parseBlocks to WordPress's JavaScript and PHP parsers over a site export; see docs/wordpress-release-audit.md.

const fs = require('fs')
const path = require('path')
const { execFileSync } = require('child_process')
const { isDeepStrictEqual } = require('util')
const { JSDOM } = require('jsdom')
const { parseBlocks } = require('../Sources/QuillKit/Resources/block-parser.js')
const { blockSourceSlices } = require('../Sources/QuillKit/Resources/editor-transforms.js')
const wordpressJS = require('@wordpress/block-serialization-default-parser').parse

// XML 1.0 forbids most control characters, but WordPress exports them raw inside post content.
const CONTROL = /[\x00-\x08\x0b\x0c\x0e-\x1f]/g
const PARKED = /[-]/g

function readItems(file) {
  const xml = fs.readFileSync(file, 'utf8')
  if (PARKED.test(xml)) throw new Error('export already contains U+E000–U+E01F; cannot park control characters')
  const parked = xml.replace(CONTROL, ch => String.fromCharCode(0xe000 + ch.charCodeAt(0)))
  const doc = new JSDOM(parked, { contentType: 'text/xml' }).window.document
  const text = (item, tag) => (item.getElementsByTagName(tag)[0] || {}).textContent || ''
  return Array.from(doc.getElementsByTagName('item'), item => ({
    id: text(item, 'wp:post_id'),
    type: text(item, 'wp:post_type'),
    title: text(item, 'title'),
    content: text(item, 'content:encoded').replace(PARKED, ch => String.fromCharCode(ch.charCodeAt(0) - 0xe000)),
  })).filter(item => item.content.trim())
}

function strip(blocks) {
  return blocks.map(({ start, end, closed, innerBlocks, ...rest }) => ({ ...rest, innerBlocks: strip(innerBlocks) }))
}

function countUnclosed(blocks) {
  return blocks.reduce((n, b) => n + (b.closed === false ? 1 : 0) + countUnclosed(b.innerBlocks), 0)
}

function countNamed(blocks) {
  return blocks.reduce((n, b) => n + (b.blockName ? 1 : 0) + countNamed(b.innerBlocks), 0)
}

// PHP has one array type: an empty object comes back as [], an object keyed 0..n-1 as a list.
function equalToPHP(ours, php) {
  if (ours === php) return true
  if (ours === null || php === null || typeof ours !== 'object' || typeof php !== 'object') return false
  if (Array.isArray(php) && !Array.isArray(ours)) {
    const keys = Object.keys(ours)
    return keys.length === php.length && keys.every((k, i) => k === String(i) && equalToPHP(ours[k], php[i]))
  }
  if (Array.isArray(ours) !== Array.isArray(php)) return false
  const keys = Object.keys(ours)
  return keys.length === Object.keys(php).length &&
    keys.every(k => Object.prototype.hasOwnProperty.call(php, k) && equalToPHP(ours[k], php[k]))
}

function parseWithPHP(inputs) {
  const runner = path.join(__dirname, 'php-block-parser.php')
  if (!fs.existsSync(path.join(wordpressPath, 'wp-includes', 'class-wp-block-parser.php'))) {
    return { skipped: `no WordPress install at ${wordpressPath}` }
  }
  try {
    const out = execFileSync('php', ['-d', 'memory_limit=2G', runner, wordpressPath], {
      input: JSON.stringify(inputs), maxBuffer: 1 << 30,
    })
    const version = (fs.readFileSync(path.join(wordpressPath, 'wp-includes', 'version.php'), 'utf8')
      .match(/\$wp_version = '([^']+)'/) || [])[1]
    return { results: JSON.parse(out), version }
  } catch (error) {
    return { skipped: `PHP failed: ${error.message.split('\n')[0]}` }
  }
}

if (require.main !== module) {
  module.exports = { readItems }
  return
}

const exportPath = process.argv[2]
const wordpressPath = process.argv[3] || process.env.QUILL_WP_PATH || '/Users/Chris/Dev/Studio'
if (!exportPath) {
  console.error('usage: node Scripts/compare-export.js <wordpress-export.xml> [path-to-wordpress-install]')
  process.exit(2)
}

const items = readItems(exportPath)
const php = parseWithPHP(items.map(item => item.content))
const problems = []
const notCompared = []
let blocks = 0

items.forEach((item, i) => {
  const label = `${item.type} ${item.id} "${item.title}"`
  const ours = parseBlocks(item.content)
  blocks += countNamed(ours)
  const joined = blockSourceSlices(item.content, parseBlocks).map(s => s.source).join('')
  const added = joined.slice(item.content.length)
  if (!joined.startsWith(item.content) || !/^(<!-- \/wp:\S+ -->)*$/.test(added)) {
    problems.push(`${label}: preserved-block slices do not rejoin into the original`)
  }
  if (countUnclosed(ours) >= 2) {
    notCompared.push(label)
    return
  }
  const tree = strip(ours)
  const js = wordpressJS(item.content)
  if (!isDeepStrictEqual(tree, js)) problems.push(`${label}: differs from WordPress's JavaScript parser`)
  if (php.results && !equalToPHP(tree, php.results[i])) {
    const shared = equalToPHP(js, php.results[i]) ? '' : ' (WordPress\'s JavaScript parser differs from PHP the same way)'
    problems.push(`${label}: differs from WordPress's PHP parser${shared}`)
  }
})

const jsVersion = require('@wordpress/block-serialization-default-parser/package.json').version
console.log(`${items.length} items with content, ${blocks} blocks`)
console.log(`WordPress JavaScript parser ${jsVersion}: compared`)
console.log(php.results ? `WordPress PHP parser ${php.version || '(unknown version)'}: compared` : `WordPress PHP parser: SKIPPED — ${php.skipped}`)
if (notCompared.length) console.log(`Not compared (two or more unclosed blocks, the one deliberate difference): ${notCompared.join('; ')}`)
if (problems.length) {
  console.log(`\n✗ ${problems.length} problem(s):`)
  for (const p of problems) console.log(`  ${p}`)
  process.exit(1)
}
if (!php.results) {
  console.log('\n! Incomplete: Quill matches WordPress\'s JavaScript parser, but the PHP comparison did not run')
  process.exit(3)
}
console.log('\n✓ Quill reads every item exactly as WordPress does')
