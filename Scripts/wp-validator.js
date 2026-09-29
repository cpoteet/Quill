'use strict'

// WordPress's own block parser and validator, for tests; see Scripts/fixtures/ai/README.md.

const { JSDOM, VirtualConsole } = require('jsdom')

// @wordpress/blocks reads the DOM from globals, so it gets a document of its own.
const wpDom = new JSDOM('<!doctype html><html><body></body></html>', { url: 'http://localhost/', pretendToBeVisual: true, virtualConsole: new VirtualConsole() })
for (const key of ['window', 'document', 'navigator', 'HTMLElement', 'Node', 'DOMParser', 'MutationObserver', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'Element', 'CustomEvent', 'Event', 'KeyboardEvent']) {
  Object.defineProperty(globalThis, key, { value: wpDom.window[key], configurable: true, writable: true })
}
wpDom.window.matchMedia = globalThis.matchMedia = () => ({ matches: false, addListener() {}, removeListener() {}, addEventListener() {}, removeEventListener() {} })

// The packages log store-registration and CSS chatter on load; none of it bears on validation.
function quiet(fn) {
  const saved = { ...console }
  Object.assign(console, { log() {}, info() {}, warn() {}, error() {} })
  try { return fn() } finally { Object.assign(console, saved) }
}

quiet(() => require('@wordpress/block-library').registerCoreBlocks())
const { parse, serialize, getBlockType } = require('@wordpress/blocks')

function blockNames(blocks, into = []) {
  for (const b of blocks) { into.push(b.name); blockNames(b.innerBlocks, into) }
  return into
}

// Without the classic editor loaded, core parses undelimited HTML as core/missing rather than core/freeform.
function problems(html) {
  const found = []
  const walk = blocks => blocks.forEach(b => {
    const classic = b.name === 'core/freeform' ? b.originalContent : b.attributes.originalUndelimitedContent
    if (classic !== undefined) found.push('classic (non-block) HTML: ' + classic.trim().slice(0, 80))
    else if (b.name === 'core/missing') found.push('unregistered block: ' + b.attributes.originalName)
    else if (!b.isValid) found.push(b.name + ' is invalid: ' + (b.validationIssues || []).map(i => i.args.join(' ')).join('; ').slice(0, 300))
    walk(b.innerBlocks)
  })
  quiet(() => walk(parse(html)))
  return found
}

function resaved(html) {
  return quiet(() => serialize(parse(html)))
}

// The attributes core parses out of each top-level block: what an editor's save() rebuilds from.
function attributesOf(html) {
  return quiet(() => parse(html)).map(b => b.attributes)
}

// The comment attributes of every block core accepts as valid, keyed by its path of block names.
function commentAttributes(html) {
  const out = {}
  const walk = (blocks, prefix) => {
    const seen = {}
    for (const b of blocks) {
      if (!b.name || b.name === 'core/missing' || b.name === 'core/freeform') continue
      seen[b.name] = (seen[b.name] ?? -1) + 1
      const key = `${prefix}${b.name}#${seen[b.name]}`
      if (!b.isValid) continue
      const defs = getBlockType(b.name).attributes
      out[key] = Object.fromEntries(Object.entries(b.attributes).filter(([k]) => !defs[k] || !defs[k].source))
      walk(b.innerBlocks, key + ' > ')
    }
  }
  quiet(() => walk(parse(html), ''))
  return out
}

function namesIn(html) {
  return new Set(blockNames(quiet(() => parse(html))))
}

function close() {
  wpDom.window.close()
}

module.exports = { problems, resaved, namesIn, attributesOf, commentAttributes, close }
