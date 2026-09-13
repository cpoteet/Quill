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
  test('every node named here is a node Quill models', () => {
    for (const node of Object.keys(BLOCK_SETTINGS)) {
      assert.ok(descriptors.descriptorFor(node), `${node} has settings but no block descriptor`)
    }
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
