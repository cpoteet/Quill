'use strict'

// One entry per Gutenberg block setting Quill redraws or offers a control for.
// Adding a setting is an entry here; removing one is deleting it. The machinery
// in editor.html derives the Tiptap attribute, and block-descriptors.js derives
// the delimiter key, so neither needs editing per setting.
//
// kind:
//   carried    draws nothing -- the delimiter carrier already preserves it, so
//              the entry exists only to hang a control on
//   flagClass  a class that is either present or absent
//   valueClass a class with the value interpolated at {}
//   style      one inline CSS property
//   attr       an HTML attribute, optionally on a descendant named by `on`
//
// sourced: true marks an attribute WordPress reads back out of the saved markup
// (block.json `source`). Core never writes those to the delimiter and neither
// may Quill, or the fixtures stop round-tripping byte-identically.
//
// flagClass declares `when` as well as `default` because presence does not mean
// truth: isStackedOnMobile defaults to true and renders its class when false.

const BLOCK_SETTINGS = {
  accordionItem: {
    openByDefault: {
      kind: 'flagClass',
      class: 'is-open',
      when: true,
      default: false,
      control: { type: 'toggle', label: 'Open', title: 'Open this section by default' },
    },
  },

  // Block styles. className is already carried and spliced into the rendered
  // class list, so these draw nothing and exist only to hang a picker on.
  // classAttr names the node's own class attribute, which has to be edited
  // alongside the carrier or the two disagree; a node without one renders a
  // fixed class and needs no such edit. Slugs verified against the site's own
  // block-library.js on 2026-09-13.
  buttonBlock:    { className: blockStyle('Fill',    [['is-style-outline', 'Outline']]) },
  blockquote:     { className: blockStyle('Default', [['is-style-plain',   'Plain']], 'class') },
  horizontalRule: { className: blockStyle('Default', [['is-style-wide',    'Wide Line'],
                                                      ['is-style-dots',    'Dots']], 'class') },
  image:          { className: blockStyle('Default', [['is-style-rounded', 'Rounded']], 'figureClass') },
}

// The default style writes no class at all, which is why its value is empty.
function blockStyle(defaultLabel, rest, classAttr) {
  const options = [{ value: '', label: defaultLabel }].concat(rest.map(([value, label]) => ({ value, label })))
  return { kind: 'carried', default: '', control: { type: 'blockStyle', label: 'Style', classAttr, options } }
}

const SETTING_KINDS = ['carried', 'flagClass', 'valueClass', 'style', 'attr']

// The one definition of how a setting reads back out of rendered markup, used
// by the editor's parse fallback and by the delimiter derivation.
function readSettingFromElement(el, def) {
  const target = def.on ? el.querySelector(def.on) : el
  if (!target) return def.default
  if (def.kind === 'carried') return def.default
  if (def.kind === 'attr') {
    const value = target.getAttribute(def.attr)
    return value === null ? def.default : value
  }
  if (def.kind === 'style') return target.style.getPropertyValue(def.property) || def.default
  if (def.kind === 'flagClass') return target.classList.contains(def.class) ? def.when : def.default
  const pattern = def.pattern.replace('{}', '([^\\s]+)')
  const m = new RegExp('(?:^|\\s)' + pattern + '(?:\\s|$)').exec(target.getAttribute('class') || '')
  return m ? m[1] : def.default
}

// A setting that draws nothing is already preserved by the carrier, and a
// sourced one is read back out of the markup by WordPress itself. Neither may
// reach the delimiter.
function settingWritesDelimiter(def) {
  return !def.sourced && def.kind !== 'carried'
}

// Function declarations, not consts: only these reach globalThis from a classic
// script, which is how editor.html resolves this registry.
function settingsFor(nodeName) {
  return BLOCK_SETTINGS[nodeName] || {}
}

function settingKinds() {
  return SETTING_KINDS.slice()
}

function settingsNodeNames() {
  return Object.keys(BLOCK_SETTINGS)
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { BLOCK_SETTINGS, settingsFor, settingKinds, settingsNodeNames, readSettingFromElement, settingWritesDelimiter }
}
