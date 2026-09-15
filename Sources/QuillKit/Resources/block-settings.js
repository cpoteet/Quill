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
  // Ordered ahead of accordionBlock so Open lands beside the accordion's own
  // Auto-close: the toolbar builds one group per entry, in this order.
  accordionItem: {
    openByDefault: {
      kind: 'flagClass',
      class: 'is-open',
      when: true,
      default: false,
      control: { type: 'toggle', label: 'Open', title: 'Open this section by default' },
    },
  },

  // core/accordion's save() draws nothing from either, so both are carried --
  // but core/accordion-heading stores its own copy and that copy draws the
  // classes and the icon span, so the control propagates to every heading.
  accordionBlock: {
    showIcon: {
      kind: 'carried',
      default: true,
      control: { type: 'toggle', label: 'Icon', title: 'Show the toggle icon',
                 propagate: 'accordionHeading' },
    },
    iconPosition: {
      kind: 'carried',
      default: 'right',
      control: { type: 'choice', label: 'Icon side', title: 'Put the toggle icon on the left',
                 propagate: 'accordionHeading', showWhen: 'showIcon',
                 options: [{ value: 'right', label: 'Icon right' }, { value: 'left', label: 'Icon left' }] },
    },
  },

  // isDefaultTab is core's own name for a derived value: the checkbox sits on
  // the panel while activeTabIndex lives on the tabs block, which carries it
  // already and whose save() draws nothing from it.
  tabPanel: {
    isDefaultTab: {
      kind: 'carried',
      default: false,
      control: { type: 'ancestorIndex', label: 'Default', ancestor: 'tabsBlock',
                 attr: 'activeTabIndex', title: 'Show this tab first' },
    },
  },

  // Block styles. className is already carried and spliced into the rendered
  // class list, so these draw nothing and exist only to hang a picker on.
  // classAttr names the node's own class attribute, which has to be edited
  // alongside the carrier or the two disagree; a node without one renders a
  // fixed class and needs no such edit. Slugs verified against the site's own
  // block-library.js on 2026-09-13.
  buttonBlock: {
    className: blockStyle('Fill', [['is-style-outline', 'Outline']], 'class').className,
    // source: "attribute" on core/button, so both live in the markup and
    // neither may reach the delimiter. NEW_TAB_REL is "noopener" alone --
    // core appends it to whatever rel already says and trims.
    linkTarget: {
      kind: 'attr', attr: 'target', on: 'a', sourced: true, default: null,
      control: { type: 'newTab', label: 'New tab', rel: 'noopener', relSetting: 'rel',
                 title: 'Open this link in a new tab', showWhen: 'href' },
    },
    rel: { kind: 'attr', attr: 'rel', on: 'a', sourced: true, default: null },
  },
  blockquote:     blockStyle('Default', [['is-style-plain',   'Plain']], 'class'),
  horizontalRule: blockStyle('Default', [['is-style-wide',    'Wide Line'],
                                         ['is-style-dots',    'Dots']], 'class'),
  image:          blockStyle('Default', [['is-style-rounded', 'Rounded']], 'figureClass'),
  // The table's class lives on its <figure>, which nothing in Quill saw until
  // the figure parse rule landed -- until then this style was lost on any edit.
  table:          blockStyle('Default', [['is-style-stripes', 'Stripes']], 'class'),
}

// The default style writes no class at all, which is why its value is empty.
function blockStyle(defaultLabel, rest, classAttr) {
  const options = [{ value: '', label: defaultLabel }].concat(rest.map(([value, label]) => ({ value, label })))
  return { className: { kind: 'carried', default: '', control: { type: 'blockStyle', label: 'Style', classAttr, options } } }
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
