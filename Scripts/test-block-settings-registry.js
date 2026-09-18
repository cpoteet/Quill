'use strict'

// Shape guard for the block settings registry. Pure Node, no DOM and no Tiptap:
// this asserts the data is well formed before any consumer reads it, so a bad
// entry fails here rather than as silently missing markup in the editor.

const { test, describe } = require('node:test')
const assert = require('node:assert/strict')
const path = require('path')

const registry = require(path.resolve(__dirname, '../Sources/QuillKit/Resources/block-settings.js'))
const descriptors = require(path.resolve(__dirname, '../Sources/QuillKit/Resources/block-descriptors.js'))

const { BLOCK_SETTINGS, settingsFor, settingKinds } = registry

const entries = []
for (const [node, settings] of Object.entries(BLOCK_SETTINGS)) {
  for (const [name, def] of Object.entries(settings)) entries.push([node, name, def])
}

describe('registry shape', () => {
  test('every entry declares a known kind', () => {
    const kinds = new Set(settingKinds())
    for (const [node, name, def] of entries) {
      assert.ok(kinds.has(def.kind), `${node}.${name} has unknown kind ${def.kind}`)
    }
  })

  test('every flagClass names its class, its trigger value and its default', () => {
    for (const [node, name, def] of entries) {
      if (def.kind !== 'flagClass') continue
      assert.equal(typeof def.class, 'string', `${node}.${name} class`)
      assert.ok('when' in def, `${node}.${name} must say which value renders the class`)
      assert.ok('default' in def, `${node}.${name} must declare core's default`)
      assert.notEqual(def.when, def.default, `${node}.${name} renders its class at the default, which would always emit it`)
    }
  })

  test('every valueClass pattern has a placeholder', () => {
    for (const [node, name, def] of entries) {
      if (def.kind !== 'valueClass') continue
      assert.match(def.pattern, /\{\}/, `${node}.${name} pattern needs {}`)
    }
  })

  test('every style entry names one CSS property', () => {
    for (const [node, name, def] of entries) {
      if (def.kind !== 'style') continue
      assert.match(def.property, /^[a-z-]+$/, `${node}.${name} property`)
    }
  })

  test('every attr entry names an HTML attribute', () => {
    for (const [node, name, def] of entries) {
      if (def.kind !== 'attr') continue
      assert.match(def.attr, /^[a-zA-Z-]+$/, `${node}.${name} attr`)
    }
  })

  // A carried setting draws nothing, so it exists only to hang a control on.
  test('a carried setting earns its entry with a control', () => {
    for (const [node, name, def] of entries) {
      if (def.kind !== 'carried') continue
      assert.ok(def.control, `${node}.${name} is carried with no control, so it does nothing`)
    }
  })

  test('a sourced setting never claims a comment key', () => {
    for (const [node, name, def] of entries) {
      if (!def.sourced) continue
      assert.notEqual(def.kind, 'carried', `${node}.${name} is sourced, so it must draw something`)
    }
  })
})

describe('registry agrees with the block descriptors', () => {
  // Only a setting that writes a delimiter key needs one: the block descriptor
  // is what emits that key. A carried setting rides on the carrier, which every
  // node has, so image -- delimited by toWordPressHTML's own image pass rather
  // than by a descriptor -- may still declare one.
  test('every node that writes a delimiter key has a block descriptor', () => {
    for (const [node, settings] of Object.entries(BLOCK_SETTINGS)) {
      const writes = Object.values(settings).some(registry.settingWritesDelimiter)
      if (!writes) continue
      assert.ok(descriptors.descriptorFor(node), `${node} writes a delimiter key but has no block descriptor`)
    }
  })

  test('ownedAttrsFor never claims a carried setting', () => {
    for (const [node, settings] of Object.entries(BLOCK_SETTINGS)) {
      const owned = descriptors.ownedAttrsFor(node)
      for (const [name, def] of Object.entries(settings)) {
        if (def.kind !== 'carried') continue
        assert.ok(!owned.includes(name), `${node}.${name} is carried, so owning it would delete it`)
      }
    }
  })
})

// A repeated key in an object literal is not an error in JS -- the last one
// silently wins and every setting under the earlier one disappears. That is
// invisible at runtime, so it has to be caught in the source.
describe('the registry source has no repeated block', () => {
  const source = require('fs').readFileSync(
    path.resolve(__dirname, '../Sources/QuillKit/Resources/block-settings.js'), 'utf8')
  const body = source.slice(source.indexOf('const BLOCK_SETTINGS = {'))

  test('each block is named once', () => {
    const seen = new Set()
    for (const line of body.split('\n')) {
      const m = /^  ([A-Za-z][A-Za-z0-9]*):/.exec(line)
      if (!m) continue
      assert.ok(!seen.has(m[1]), `${m[1]} is declared twice; the second one silently wins`)
      seen.add(m[1])
    }
    assert.deepEqual([...seen].sort(), Object.keys(BLOCK_SETTINGS).sort())
  })
})

describe('lookup', () => {
  test('settingsFor returns an entry map for a known node', () => {
    const [node] = Object.keys(BLOCK_SETTINGS)
    assert.deepEqual(settingsFor(node), BLOCK_SETTINGS[node])
  })

  test('settingsFor returns an empty map for a node with no settings', () => {
    assert.deepEqual(settingsFor('paragraph'), {})
  })

  test('settingsFor is safe on a node that does not exist', () => {
    assert.deepEqual(settingsFor('nopeBlock'), {})
  })
})
