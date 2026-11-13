'use strict'

// Prints the live editor's schema, extensions, plugins and commands, one fact per line,
// so two runs (before and after a Tiptap update) can be diffed. Facts no test asserts —
// a new attribute, an extra parse rule, a plugin that moved — show up here.
//
//   node Scripts/dump-editor-schema.js [path/to/editor.html] > out.txt
//
// Nodes, marks and extensions are sorted by name so a reorder does not hide a real change.
// Plugins keep registration order, because the order decides which handler wins.

const { JSDOM, VirtualConsole } = require('jsdom')
const fs = require('fs')
const path = require('path')
const nodeCrypto = require('crypto')

const htmlPath = path.resolve(process.argv[2] || path.join(__dirname, '../Sources/QuillKit/Resources/editor.html'))

const show = v => {
  if (v === undefined) return 'undefined'
  if (typeof v === 'function') return 'fn'
  try { return JSON.stringify(v) } catch { return String(v) }
}

function bootEditor() {
  const vc = new VirtualConsole()
  const logs = []
  vc.on('jsdomError', e => logs.push('JSDOM_ERROR: ' + (e.detail?.stack || e.message || e)))
  const dom = new JSDOM(fs.readFileSync(htmlPath, 'utf8'), {
    runScripts: 'dangerously',
    resources: 'usable',
    pretendToBeVisual: true,
    url: 'file://' + htmlPath,
    virtualConsole: vc,
  })
  const win = dom.window
  if (!win.crypto) win.crypto = {}
  if (!win.crypto.randomUUID) win.crypto.randomUUID = () => nodeCrypto.randomUUID()
  if (!win.matchMedia) win.matchMedia = () => ({ matches: false, addEventListener() {}, removeEventListener() {}, addListener() {}, removeListener() {} })
  if (!win.requestAnimationFrame) win.requestAnimationFrame = cb => setTimeout(cb, 0)
  if (!win.ResizeObserver) win.ResizeObserver = class { observe() {} unobserve() {} disconnect() {} }
  return new Promise((resolve, reject) => {
    let tries = 0
    const t = setInterval(() => {
      if (win._tiptapEditor) { clearInterval(t); resolve(win._tiptapEditor) }
      else if (++tries > 400) { clearInterval(t); reject(new Error('editor never became ready.\n' + logs.join('\n'))) }
    }, 25)
  })
}

function specLines(kind, name, spec, fields) {
  const out = [`${kind} ${name} ` + fields.map(f => `${f}=${show(spec[f])}`).join(' ')]
  for (const attr of Object.keys(spec.attrs || {}).sort()) {
    out.push(`  attr ${name}.${attr} default=${show(spec.attrs[attr].default)}`)
  }
  for (const rule of spec.parseDOM || []) {
    out.push(`  parse ${name} tag=${show(rule.tag)} style=${show(rule.style)} prio=${show(rule.priority)}` +
      ` ctx=${show(rule.context)} consuming=${show(rule.consuming)} pw=${show(rule.preserveWhitespace)}` +
      ` getAttrs=${typeof rule.getAttrs === 'function'} contentEl=${typeof rule.contentElement}`)
  }
  return out
}

function sortedEntries(orderedMap) {
  const entries = []
  orderedMap.forEach((name, spec) => entries.push([name, spec]))
  return entries.sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
}

async function main() {
  const editor = await bootEditor()
  const lines = []
  const nodeFields = ['content', 'group', 'marks', 'inline', 'atom', 'defining', 'isolating', 'code', 'draggable', 'selectable', 'whitespace']
  for (const [name, spec] of sortedEntries(editor.schema.spec.nodes)) lines.push(...specLines('node', name, spec, nodeFields))
  for (const [name, spec] of sortedEntries(editor.schema.spec.marks)) lines.push(...specLines('mark', name, spec, ['excludes', 'inclusive', 'spanning']))

  const exts = editor.extensionManager.extensions.map(e => `ext ${e.type} ${e.name}`).sort()
  lines.push(...exts)

  editor.state.plugins.forEach((p, i) => {
    const key = String(p.key).replace(/\d+$/, 'N')
    lines.push(`plugin ${i} ${key} props=${Object.keys(p.props || {}).sort().join(',')}`)
  })

  lines.push(`commands ${Object.keys(editor.commands).sort().join(' ')}`)
  process.stdout.write(lines.join('\n') + '\n')
  process.exit(0)
}

main().catch(err => { console.error(err.stack || err); process.exit(1) })
