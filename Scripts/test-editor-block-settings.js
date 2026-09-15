'use strict'

// Per-setting tests for the block-settings preservation work. Loads the REAL
// editor.html in jsdom -- a node's renderHTML and its parse rule cannot be
// exercised through the pure editor-transforms.js helpers.

const { test, describe, before, after } = require('node:test')
const assert = require('node:assert/strict')
const { JSDOM, VirtualConsole } = require('jsdom')
const fs = require('fs')
const path = require('path')
const nodeCrypto = require('crypto')

const htmlPath = path.resolve(__dirname, '../Sources/QuillKit/Resources/editor.html')

let editor
let win

before(async () => {
  const html = fs.readFileSync(htmlPath, 'utf8')
  const vc = new VirtualConsole()
  const logs = []
  vc.on('jsdomError', e => logs.push('JSDOM_ERROR: ' + (e.detail?.stack || e.message || e)))

  const dom = new JSDOM(html, {
    runScripts: 'dangerously',
    resources: 'usable',
    pretendToBeVisual: true,
    url: 'file://' + htmlPath,
    virtualConsole: vc,
  })
  win = dom.window

  if (!win.crypto) win.crypto = {}
  if (!win.crypto.randomUUID) win.crypto.randomUUID = () => nodeCrypto.randomUUID()
  if (!win.matchMedia) win.matchMedia = () => ({ matches: false, addEventListener() {}, removeEventListener() {}, addListener() {}, removeListener() {} })
  if (!win.requestAnimationFrame) win.requestAnimationFrame = cb => setTimeout(cb, 0)
  if (!win.ResizeObserver) win.ResizeObserver = class { observe() {} unobserve() {} disconnect() {} }
  // undo dispatches a scrollIntoView, which measures the selection; jsdom gives
  // a Text node no geometry at all.
  const rect = { top: 0, left: 0, bottom: 0, right: 0, width: 0, height: 0 }
  for (const proto of [win.Text.prototype, win.Range.prototype]) {
    if (proto.getClientRects) continue
    proto.getClientRects = () => Object.assign([rect], { item: () => rect })
    proto.getBoundingClientRect = () => rect
  }

  editor = await new Promise((resolve, reject) => {
    let tries = 0
    const t = setInterval(() => {
      if (win._tiptapEditor) { clearInterval(t); resolve(win._tiptapEditor) }
      else if (++tries > 400) { clearInterval(t); reject(new Error('editor never became ready.\n' + logs.join('\n'))) }
    }, 25)
  })
})

after(() => { if (win) win.close() })

// The post-visual-edit save path: getContent() returns _rawHTML verbatim until
// an edit clears it, so calling the transform directly is what a real save does.
function save(src) {
  win.setContent(src)
  return win.toWordPressHTML(editor.getHTML())
}

const fixture = name => fs.readFileSync(path.resolve(__dirname, 'fixtures', name), 'utf8')

describe('className survives on container blocks', () => {
  test('an outline button keeps its class and its comment attr', () => {
    const out = save(`<!-- wp:buttons -->
<div class="wp-block-buttons"><!-- wp:button {"className":"is-style-outline"} -->
<div class="wp-block-button is-style-outline"><a class="wp-block-button__link wp-element-button" href="https://x.test">Go</a></div>
<!-- /wp:button --></div>
<!-- /wp:buttons -->`)
    assert.match(out, /class="wp-block-button is-style-outline"/)
    assert.match(out, /wp:button \{"className":"is-style-outline"\}/)
  })

  test('the class is not doubled when it is already rendered', () => {
    const out = save(`<!-- wp:details {"className":"is-style-x"} -->
<details class="wp-block-details is-style-x"><summary>S</summary><!-- wp:paragraph --><p>D</p><!-- /wp:paragraph --></details>
<!-- /wp:details -->`)
    assert.equal((out.match(/is-style-x/g) || []).length, 2, 'once in the class, once in the comment')
  })

  test('a block with no className is unchanged', () => {
    const out = save(`<!-- wp:buttons -->
<div class="wp-block-buttons"><!-- wp:button -->
<div class="wp-block-button"><a class="wp-block-button__link wp-element-button" href="https://x.test">Go</a></div>
<!-- /wp:button --></div>
<!-- /wp:buttons -->`)
    assert.match(out, /class="wp-block-button"/)
    assert.doesNotMatch(out, /class="wp-block-button "/)
  })
})

describe('delimiter attributes survive on core blocks', () => {
  test('a paragraph keeps dropCap', () => {
    const out = save('<!-- wp:paragraph {"dropCap":true} -->\n<p class="has-drop-cap">Hello</p>\n<!-- /wp:paragraph -->')
    assert.match(out, /wp:paragraph \{"dropCap":true\}/)
  })

  test('an ordered list keeps start, reversed and type', () => {
    const out = save('<!-- wp:list {"ordered":true,"start":5,"reversed":true,"type":"upper-roman"} -->\n<ol reversed start="5" style="list-style-type:upper-roman" class="wp-block-list"><!-- wp:list-item --><li>one</li><!-- /wp:list-item --></ol>\n<!-- /wp:list -->')
    assert.match(out, /"start":5/)
    assert.match(out, /"reversed":true/)
    assert.match(out, /"type":"upper-roman"/)
  })

  test('a separator keeps its className', () => {
    const out = save('<!-- wp:separator {"className":"is-style-dots"} -->\n<hr class="wp-block-separator has-alpha-channel-opacity is-style-dots"/>\n<!-- /wp:separator -->')
    assert.match(out, /"className":"is-style-dots"/)
  })

  test('an unmodeled attribute rides along untouched', () => {
    const out = save('<!-- wp:paragraph {"metadata":{"name":"Intro"}} -->\n<p>Hello</p>\n<!-- /wp:paragraph -->')
    assert.match(out, /"metadata":\{"name":"Intro"\}/)
  })
})

describe('image, gallery and embed keep unmodeled attributes', () => {
  test('an image keeps lightbox and className', () => {
    const out = save('<!-- wp:image {"id":9,"sizeSlug":"large","lightbox":{"enabled":true},"className":"is-style-rounded"} -->\n<figure class="wp-block-image size-large is-style-rounded"><img src="https://x.test/a.jpg" alt="" class="wp-image-9"/></figure>\n<!-- /wp:image -->')
    assert.match(out, /"lightbox":\{"enabled":true\}/)
    assert.match(out, /"className":"is-style-rounded"/)
  })

  test('a derived attribute still wins over a stale carried one', () => {
    const out = save('<!-- wp:image {"id":9,"sizeSlug":"thumbnail"} -->\n<figure class="wp-block-image size-large"><img src="https://x.test/a.jpg" alt="" class="wp-image-9"/></figure>\n<!-- /wp:image -->')
    assert.match(out, /"sizeSlug":"large"/)
    assert.doesNotMatch(out, /"sizeSlug":"thumbnail"/)
  })

  test('an embed keeps an attribute Quill does not model', () => {
    const out = save('<!-- wp:embed {"url":"https://www.youtube.com/watch?v=abc","type":"video","providerNameSlug":"youtube","responsive":true,"align":"wide","className":"wp-embed-aspect-16-9 wp-has-aspect-ratio"} -->\n<figure class="wp-block-embed alignwide is-type-video is-provider-youtube wp-block-embed-youtube wp-embed-aspect-16-9 wp-has-aspect-ratio"><div class="wp-block-embed__wrapper">\nhttps://www.youtube.com/watch?v=abc\n</div></figure>\n<!-- /wp:embed -->')
    assert.match(out, /"align":"wide"/)
  })

  test('a gallery keeps an attribute Quill does not model', () => {
    const out = save('<!-- wp:gallery {"columns":2,"linkTo":"none","randomOrder":true} -->\n<figure class="wp-block-gallery has-nested-images columns-2 is-cropped"><!-- wp:image {"id":1,"sizeSlug":"large"} -->\n<figure class="wp-block-image size-large"><img src="https://x.test/1.jpg" alt="" class="wp-image-1"/></figure>\n<!-- /wp:image --></figure>\n<!-- /wp:gallery -->')
    assert.match(out, /"randomOrder":true/)
  })
})

// The bug class CLAUDE.md records: a top-level const is reachable by bare
// identifier but never as a property of globalThis, so it reads undefined in
// the app while every pure-Node test passes. Only this harness catches it.
describe('the settings registry is live in the editor', () => {
  test('settingsFor is callable as a global', () => {
    assert.equal(typeof win.settingsFor, 'function')
  })

  test('it returns a real entry, not an empty object', () => {
    const entry = win.settingsFor('accordionItem')
    assert.equal(entry.openByDefault.kind, 'flagClass')
    assert.equal(entry.openByDefault.class, 'is-open')
  })

  test('settingKinds reaches the browser too', () => {
    assert.ok(win.settingKinds().includes('flagClass'))
  })
})

describe('registry-generated attributes: accordionItem.openByDefault', () => {
  const open = `<!-- wp:accordion -->
<div role="group" class="wp-block-accordion"><!-- wp:accordion-item {"openByDefault":true} -->
<div class="wp-block-accordion-item is-open"><!-- wp:accordion-heading -->
<h3 class="wp-block-accordion-heading has-icon has-icon-right"><button type="button" class="wp-block-accordion-heading__toggle"><span class="wp-block-accordion-heading__toggle-title">T</span><span class="wp-block-accordion-heading__toggle-icon" aria-hidden="true">+</span></button></h3>
<!-- /wp:accordion-heading -->

<!-- wp:accordion-panel -->
<div role="region" class="wp-block-accordion-panel"><!-- wp:paragraph -->
<p>Body</p>
<!-- /wp:paragraph --></div>
<!-- /wp:accordion-panel --></div>
<!-- /wp:accordion-item --></div>
<!-- /wp:accordion -->`

  const shut = open
    .replace(' {"openByDefault":true}', '')
    .replace('wp-block-accordion-item is-open', 'wp-block-accordion-item')

  test('an open item keeps its is-open class through a save', () => {
    assert.match(save(open), /class="wp-block-accordion-item is-open"/)
  })

  test('an open item keeps its delimiter key', () => {
    assert.match(save(open), /wp:accordion-item \{"openByDefault":true\}/)
  })

  test('a closed item gains neither the class nor the key', () => {
    const out = save(shut)
    assert.doesNotMatch(out, /is-open/)
    assert.doesNotMatch(out, /wp:accordion-item \{/)
  })

  test('the class is not doubled across two save cycles', () => {
    const once = save(open)
    win.setContent(once)
    const twice = win.toWordPressHTML(editor.getHTML())
    assert.equal((twice.match(/is-open/g) || []).length, 1)
  })

  // Settles the wrapper nesting: withBlockSettings must run inside
  // withBlockAttrs, so the carried className merges onto a class list the
  // setting has already contributed to rather than replacing it.
  test('a carried className and the setting class land together', () => {
    const out = save(open.replace('{"openByDefault":true}', '{"openByDefault":true,"className":"mine"}'))
    const m = out.match(/<div class="([^"]*wp-block-accordion-item[^"]*)"/)
    assert.ok(m, 'the item div should still be there')
    const classes = m[1].split(/\s+/)
    assert.ok(classes.includes('is-open'), `is-open missing from "${m[1]}"`)
    assert.ok(classes.includes('mine'), `mine missing from "${m[1]}"`)
  })
})

// Toggling the attribute, rather than editing the HTML, is the only way to
// reach the state the delimiter half exists for: the carrier still holds the
// old value while the markup holds the new one.
function setNodeAttr(typeName, attr, value) {
  const { state, view } = editor
  let done = false
  state.doc.descendants((node, pos) => {
    if (done || node.type.name !== typeName) return
    view.dispatch(state.tr.setNodeMarkup(pos, undefined, { ...node.attrs, [attr]: value }))
    done = true
  })
  return done
}

describe('the delimiter half comes from the registry too', () => {
  const item = `<!-- wp:accordion -->
<div role="group" class="wp-block-accordion"><!-- wp:accordion-item {"openByDefault":true} -->
<div class="wp-block-accordion-item is-open"><!-- wp:accordion-heading -->
<h3 class="wp-block-accordion-heading has-icon has-icon-right"><button type="button" class="wp-block-accordion-heading__toggle"><span class="wp-block-accordion-heading__toggle-title">T</span><span class="wp-block-accordion-heading__toggle-icon" aria-hidden="true">+</span></button></h3>
<!-- /wp:accordion-heading -->

<!-- wp:accordion-panel -->
<div role="region" class="wp-block-accordion-panel"><!-- wp:paragraph -->
<p>Body</p>
<!-- /wp:paragraph --></div>
<!-- /wp:accordion-panel --></div>
<!-- /wp:accordion-item --></div>
<!-- /wp:accordion -->`

  test('the registry contributes the owned key', () => {
    assert.ok(win.ownedAttrsFor('accordionItem').includes('openByDefault'))
  })

  test('a hand-written ownedAttrs entry is kept alongside it', () => {
    assert.deepEqual(Array.from(win.ownedAttrsFor('accordionBlock')), ['autoclose'])
  })

  test('turning the setting off clears the class and the stale carried key', () => {
    win.setContent(item)
    assert.ok(setNodeAttr('accordionItem', 'openByDefault', false))
    const out = win.toWordPressHTML(editor.getHTML())
    assert.doesNotMatch(out, /is-open/)
    assert.doesNotMatch(out, /wp:accordion-item \{/)
  })

  test('turning it on writes both the class and the key', () => {
    win.setContent(item.replace(' {"openByDefault":true}', '').replace('wp-block-accordion-item is-open', 'wp-block-accordion-item'))
    assert.ok(setNodeAttr('accordionItem', 'openByDefault', true))
    const out = win.toWordPressHTML(editor.getHTML())
    assert.match(out, /class="wp-block-accordion-item is-open"/)
    assert.match(out, /wp:accordion-item \{"openByDefault":true\}/)
  })

  test('an unmodeled carried attribute is not swept away with it', () => {
    win.setContent(item.replace('{"openByDefault":true}', '{"openByDefault":true,"metadata":{"name":"One"}}'))
    assert.ok(setNodeAttr('accordionItem', 'openByDefault', false))
    const out = win.toWordPressHTML(editor.getHTML())
    assert.match(out, /"metadata":\{"name":"One"\}/)
    assert.doesNotMatch(out, /openByDefault/)
  })
})

describe('the toolbar control comes from the registry', () => {
  const item = `<!-- wp:accordion -->
<div role="group" class="wp-block-accordion"><!-- wp:accordion-item -->
<div class="wp-block-accordion-item"><!-- wp:accordion-heading -->
<h3 class="wp-block-accordion-heading has-icon has-icon-right"><button type="button" class="wp-block-accordion-heading__toggle"><span class="wp-block-accordion-heading__toggle-title">T</span><span class="wp-block-accordion-heading__toggle-icon" aria-hidden="true">+</span></button></h3>
<!-- /wp:accordion-heading -->

<!-- wp:accordion-panel -->
<div role="region" class="wp-block-accordion-panel"><!-- wp:paragraph -->
<p>Body</p>
<!-- /wp:paragraph --></div>
<!-- /wp:accordion-panel --></div>
<!-- /wp:accordion-item --></div>
<!-- /wp:accordion -->

<p>Outside</p>`

  const group = () => win.document.getElementById('settings-accordionItem-controls')
  const button = () => group().querySelector('[data-setting="openByDefault"]')

  function caretAt(text) {
    let found = null
    editor.state.doc.descendants((node, pos) => {
      if (found || !node.isTextblock || node.textContent !== text) return
      found = pos + 1
    })
    assert.ok(found !== null, `no textblock reading "${text}"`)
    editor.commands.setTextSelection(found)
  }

  function press(el) {
    el.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true }))
  }

  test('the group is generated for a node that declares a control', () => {
    assert.ok(group(), 'no generated group for accordionItem')
    assert.equal(group().parentElement.id, 'toolbar-row2')
  })

  test('the control carries the label the registry gave it', () => {
    assert.equal(button().textContent, 'Open')
  })

  test('it is hidden when the cursor is outside the block', () => {
    win.setContent(item)
    caretAt('Outside')
    assert.equal(group().style.display, 'none')
  })

  test('it appears when the cursor is inside the block', () => {
    win.setContent(item)
    caretAt('Body')
    assert.equal(group().style.display, 'inline-flex')
  })

  test('it reflects the current value', () => {
    win.setContent(item)
    caretAt('Body')
    assert.equal(button().classList.contains('active'), false)
    setNodeAttr('accordionItem', 'openByDefault', true)
    caretAt('Body')
    assert.equal(button().classList.contains('active'), true)
  })

  test('pressing it flips the attribute and the saved markup', () => {
    win.setContent(item)
    caretAt('Body')
    press(button())
    const out = win.toWordPressHTML(editor.getHTML())
    assert.match(out, /class="wp-block-accordion-item is-open"/)
    assert.match(out, /wp:accordion-item \{"openByDefault":true\}/)
    press(button())
    const back = win.toWordPressHTML(editor.getHTML())
    assert.doesNotMatch(back, /is-open/)
  })
})

describe('block styles', () => {
  function caretIn(text) {
    let found = null
    editor.state.doc.descendants((node, pos) => {
      if (found !== null || !node.isTextblock || !node.textContent.includes(text)) return
      found = pos + 1
    })
    assert.ok(found !== null, `no textblock containing "${text}"`)
    editor.commands.setTextSelection(found)
  }

  function selectNode(typeName) {
    let found = null
    editor.state.doc.descendants((node, pos) => {
      if (found !== null || node.type.name !== typeName) return
      found = pos
    })
    assert.ok(found !== null, `no ${typeName} in the document`)
    editor.commands.setNodeSelection(found)
  }

  const picker = node => win.document.querySelector(`#settings-${node}-controls [data-setting="className"]`)

  // A block with two styles draws a toggle button, one with more draws a select.
  const styleOf = node => {
    const el = picker(node)
    assert.ok(el, `no style control for ${node}`)
    if (el.tagName === 'SELECT') return el.value
    return el.classList.contains('active') ? el.dataset.style : ''
  }

  function choose(node, value) {
    const el = picker(node)
    assert.ok(el, `no style control for ${node}`)
    if (el.tagName === 'SELECT') {
      el.value = value
      el.dispatchEvent(new win.Event('change', { bubbles: true }))
      return
    }
    assert.ok(value === '' || value === el.dataset.style, `${node} has no ${value} toggle`)
    if (styleOf(node) !== value) el.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true }))
  }

  const cases = [
    {
      name: 'button', node: 'buttonBlock', place: () => caretIn('Go'), from: 'is-style-outline', to: '',
      src: `<!-- wp:buttons -->
<div class="wp-block-buttons"><!-- wp:button {"className":"mine is-style-outline"} -->
<div class="wp-block-button mine is-style-outline"><a class="wp-block-button__link wp-element-button" href="https://x.test">Go</a></div>
<!-- /wp:button --></div>
<!-- /wp:buttons -->`,
    },
    {
      name: 'quote', node: 'blockquote', place: () => caretIn('Quoted'), from: 'is-style-plain', to: '',
      src: `<!-- wp:quote {"className":"mine is-style-plain"} -->
<blockquote class="wp-block-quote mine is-style-plain"><!-- wp:paragraph -->
<p>Quoted</p>
<!-- /wp:paragraph --></blockquote>
<!-- /wp:quote -->`,
    },
    {
      name: 'separator', node: 'horizontalRule', place: () => selectNode('horizontalRule'), from: 'is-style-dots', to: 'is-style-wide',
      src: `<!-- wp:separator {"className":"mine is-style-dots"} -->
<hr class="wp-block-separator has-alpha-channel-opacity mine is-style-dots"/>
<!-- /wp:separator -->`,
    },
    {
      name: 'image', node: 'image', place: () => selectNode('image'), from: 'is-style-rounded', to: '',
      src: `<!-- wp:image {"id":9,"sizeSlug":"large","className":"mine is-style-rounded"} -->
<figure class="wp-block-image size-large mine is-style-rounded"><img src="https://x.test/a.jpg" alt="" class="wp-image-9"/></figure>
<!-- /wp:image -->`,
    },
  ]

  for (const c of cases) {
    describe(c.name, () => {
      test('the loaded style survives a save in both the class and the comment', () => {
        const out = save(c.src)
        assert.match(out, new RegExp(`class="[^"]*${c.from}`))
        assert.match(out, new RegExp(`"className":"[^"]*${c.from}`))
      })

      test('the picker appears in the block and reports the current style', () => {
        win.setContent(c.src)
        c.place()
        assert.equal(win.document.getElementById(`settings-${c.node}-controls`).style.display, 'inline-flex')
        assert.equal(styleOf(c.node), c.from)
      })

      test('switching replaces the old token rather than stacking it', () => {
        win.setContent(c.src)
        c.place()
        choose(c.node, c.to)
        const out = win.toWordPressHTML(editor.getHTML())
        assert.doesNotMatch(out, new RegExp(c.from))
        if (c.to) assert.match(out, new RegExp(`class="[^"]*${c.to}`))
        assert.equal((out.match(/is-style-/g) || []).length, c.to ? 2 : 0)
      })

      test("the user's own unrelated class is left alone", () => {
        win.setContent(c.src)
        c.place()
        choose(c.node, c.to)
        const out = win.toWordPressHTML(editor.getHTML())
        assert.match(out, /class="[^"]*\bmine\b/)
        assert.match(out, /"className":"[^"]*\bmine\b/)
      })
    })
  }

  // The image node view replaces renderHTML, so its style token reaches the
  // canvas only if the view copies it onto the wrapper.
  describe('the image node view carries the style token onto the canvas', () => {
    const wrapper = () => win.document.querySelector('.ProseMirror .image-wrapper')

    test('a loaded rounded image renders the class on the wrapper', () => {
      win.setContent(cases[3].src)
      assert.equal(wrapper().classList.contains('is-style-rounded'), true)
    })

    test('choosing Default takes it off again', () => {
      win.setContent(cases[3].src)
      selectNode('image')
      choose('image', '')
      assert.equal(wrapper().classList.contains('is-style-rounded'), false)
    })

    test('an image with no style carries no token', () => {
      win.setContent('<!-- wp:image -->\n<figure class="wp-block-image"><img src="https://x.test/b.jpg" alt=""/></figure>\n<!-- /wp:image -->')
      assert.equal([...wrapper().classList].some(c => c.startsWith('is-style-')), false)
    })
  })

  test('the image keeps its size class through a style change', () => {
    win.setContent(cases[3].src)
    selectNode('image')
    choose('image', '')
    assert.match(win.toWordPressHTML(editor.getHTML()), /class="[^"]*size-large/)
  })

  test('a block with no style at all starts on Default', () => {
    win.setContent(`<!-- wp:quote -->
<blockquote class="wp-block-quote"><!-- wp:paragraph -->
<p>Plainest</p>
<!-- /wp:paragraph --></blockquote>
<!-- /wp:quote -->`)
    caretIn('Plainest')
    assert.equal(styleOf('blockquote'), '')
  })

  test('choosing a style on a block that had none writes both halves', () => {
    win.setContent(`<!-- wp:quote -->
<blockquote class="wp-block-quote"><!-- wp:paragraph -->
<p>Plainest</p>
<!-- /wp:paragraph --></blockquote>
<!-- /wp:quote -->`)
    caretIn('Plainest')
    choose('blockquote', 'is-style-plain')
    const out = win.toWordPressHTML(editor.getHTML())
    assert.match(out, /class="wp-block-quote is-style-plain"/)
    assert.match(out, /"className":"is-style-plain"/)
  })
})

describe('the tabs default tab', () => {
  const tabs = `<!-- wp:tabs -->
<div class="wp-block-tabs"><!-- wp:tab-list -->
<div role="tablist" class="wp-block-tab-list"><button type="button" role="tab">One</button><button type="button" role="tab">Two</button></div>
<!-- /wp:tab-list -->

<!-- wp:tab-panels -->
<div class="wp-block-tab-panels"><!-- wp:tab-panel {"label":"One"} -->
<section role="tabpanel" tabindex="0" class="wp-block-tab-panel"><!-- wp:paragraph -->
<p>First body</p>
<!-- /wp:paragraph --></section>
<!-- /wp:tab-panel -->

<!-- wp:tab-panel {"label":"Two"} -->
<section role="tabpanel" tabindex="0" class="wp-block-tab-panel"><!-- wp:paragraph -->
<p>Second body</p>
<!-- /wp:paragraph --></section>
<!-- /wp:tab-panel --></div>
<!-- /wp:tab-panels --></div>
<!-- /wp:tabs -->`

  const toggle = () => win.document.querySelector('#settings-tabPanel-controls [data-setting="isDefaultTab"]')

  function caretIn(text) {
    let found = null
    editor.state.doc.descendants((node, pos) => {
      if (found !== null || !node.isTextblock || node.textContent !== text) return
      found = pos + 1
    })
    assert.ok(found !== null, `no textblock reading "${text}"`)
    editor.commands.setTextSelection(found)
  }

  const press = el => el.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true }))

  test('a loaded activeTabIndex survives an edit', () => {
    const out = save(tabs.replace('<!-- wp:tabs -->', '<!-- wp:tabs {"activeTabIndex":1} -->'))
    assert.match(out, /wp:tabs \{"activeTabIndex":1\}/)
  })

  // Core checks the box on tab 0 as well -- its checkbox is `checked:
  // isDefaultTab`, and with no attribute written the default index is 0.
  test('the control appears in a panel and is on for the first tab by default', () => {
    win.setContent(tabs)
    caretIn('First body')
    assert.equal(win.document.getElementById('settings-tabPanel-controls').style.display, 'inline-flex')
    assert.equal(toggle().classList.contains('active'), true)
  })

  test('it is on for whichever panel the index names', () => {
    win.setContent(tabs.replace('<!-- wp:tabs -->', '<!-- wp:tabs {"activeTabIndex":1} -->'))
    caretIn('Second body')
    assert.equal(toggle().classList.contains('active'), true)
    caretIn('First body')
    assert.equal(toggle().classList.contains('active'), false)
  })

  test('pressing it on the second panel writes that index to the tabs block', () => {
    win.setContent(tabs)
    caretIn('Second body')
    press(toggle())
    assert.match(win.toWordPressHTML(editor.getHTML()), /wp:tabs \{"activeTabIndex":1\}/)
  })

  test('pressing it again falls back to the first tab and writes no attribute', () => {
    win.setContent(tabs.replace('<!-- wp:tabs -->', '<!-- wp:tabs {"activeTabIndex":1} -->'))
    caretIn('Second body')
    press(toggle())
    const out = win.toWordPressHTML(editor.getHTML())
    assert.doesNotMatch(out, /activeTabIndex/)
    assert.match(out, /<!-- wp:tabs -->/)
  })

  test('an unmodeled attribute on the tabs block is not lost when the index changes', () => {
    win.setContent(tabs.replace('<!-- wp:tabs -->', '<!-- wp:tabs {"metadata":{"name":"T"}} -->'))
    caretIn('Second body')
    press(toggle())
    const out = win.toWordPressHTML(editor.getHTML())
    assert.match(out, /"metadata":\{"name":"T"\}/)
    assert.match(out, /"activeTabIndex":1/)
  })

  test('the control is absent outside a tab panel', () => {
    win.setContent('<p>plain</p>')
    editor.commands.setTextSelection(2)
    assert.equal(win.document.getElementById('settings-tabPanel-controls').style.display, 'none')
  })

  // The visibly active tab follows the caret, so the default needs its own mark.
  describe('the default tab is marked on the canvas', () => {
    const tabButtons = () => [...win.document.querySelectorAll('.ProseMirror .wp-block-tab-list button[role="tab"]')]
    const marked = () => tabButtons().map(b => b.classList.contains('is-default-tab'))

    test('with no attribute written the first tab is marked', () => {
      win.setContent(tabs)
      caretIn('Second body')
      assert.deepEqual(marked(), [true, false])
    })

    test('the index moves the mark, and the caret does not', () => {
      win.setContent(tabs.replace('<!-- wp:tabs -->', '<!-- wp:tabs {"activeTabIndex":1} -->'))
      caretIn('First body')
      assert.deepEqual(marked(), [false, true])
    })

    test('pressing the control moves the mark', () => {
      win.setContent(tabs)
      caretIn('Second body')
      press(toggle())
      assert.deepEqual(marked(), [false, true])
    })

    test('the mark never reaches the saved markup', () => {
      win.setContent(tabs.replace('<!-- wp:tabs -->', '<!-- wp:tabs {"activeTabIndex":1} -->'))
      caretIn('First body')
      assert.doesNotMatch(win.toWordPressHTML(editor.getHTML()), /is-default-tab/)
    })
  })
})

// core gives core/accordion-heading its own openByDefault, but its save() never
// reads it, so it draws nothing and Gutenberg does not write it. The carrier
// preserves whatever a post already had; nothing propagates.
describe('the accordion heading keeps its own openByDefault out of the way', () => {
  const withHeadingFlag = `<!-- wp:accordion -->
<div role="group" class="wp-block-accordion"><!-- wp:accordion-item {"openByDefault":true} -->
<div class="wp-block-accordion-item is-open"><!-- wp:accordion-heading {"openByDefault":true} -->
<h3 class="wp-block-accordion-heading has-icon has-icon-right"><button type="button" class="wp-block-accordion-heading__toggle"><span class="wp-block-accordion-heading__toggle-title">T</span><span class="wp-block-accordion-heading__toggle-icon" aria-hidden="true">+</span></button></h3>
<!-- /wp:accordion-heading -->

<!-- wp:accordion-panel -->
<div role="region" class="wp-block-accordion-panel"><!-- wp:paragraph -->
<p>Body</p>
<!-- /wp:paragraph --></div>
<!-- /wp:accordion-panel --></div>
<!-- /wp:accordion-item --></div>
<!-- /wp:accordion -->`

  test('a heading that carries the flag keeps it verbatim', () => {
    assert.match(save(withHeadingFlag), /wp:accordion-heading \{"openByDefault":true\}/)
  })

  test('it draws nothing on the heading either way', () => {
    const out = save(withHeadingFlag)
    const heading = out.match(/<h3 class="([^"]*)"/)[1]
    assert.equal(heading, 'wp-block-accordion-heading has-icon has-icon-right')
  })

  test('turning the item off leaves the heading alone', () => {
    win.setContent(withHeadingFlag)
    assert.ok(setNodeAttr('accordionItem', 'openByDefault', false))
    const out = win.toWordPressHTML(editor.getHTML())
    assert.doesNotMatch(out, /wp:accordion-item \{/)
    assert.match(out, /wp:accordion-heading \{"openByDefault":true\}/)
  })
})

// linkTarget and rel are source: "attribute" on core/button, so they live in
// the markup and never in the delimiter. Core's own algorithm, from
// button/constants.mjs and get-updated-link-attributes.mjs: NEW_TAB_REL is
// "noopener" alone, appended to whatever rel already says and then trimmed.
describe('a button opening in a new tab', () => {
  const plain = `<!-- wp:buttons -->
<div class="wp-block-buttons"><!-- wp:button -->
<div class="wp-block-button"><a class="wp-block-button__link wp-element-button" href="https://x.test">Go</a></div>
<!-- /wp:button --></div>
<!-- /wp:buttons -->`

  const newTab = plain.replace('href="https://x.test"', 'href="https://x.test" target="_blank" rel="noopener"')

  const toggle = () => win.document.querySelector('#settings-buttonBlock-controls [data-setting="linkTarget"]')

  function caretInButton() {
    let found = null
    editor.state.doc.descendants((node, pos) => {
      if (found !== null || node.type.name !== 'buttonBlock') return
      found = pos + 1
    })
    assert.ok(found !== null, 'no buttonBlock')
    editor.commands.setTextSelection(found)
  }

  const press = el => el.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true }))

  test('a loaded target and rel survive an edit', () => {
    const out = save(newTab)
    assert.match(out, /target="_blank"/)
    assert.match(out, /rel="noopener"/)
  })

  test('neither reaches the delimiter, because core reads them from the markup', () => {
    const out = save(newTab)
    assert.doesNotMatch(out, /wp:button \{/)
  })

  test('a button without them gains neither', () => {
    const out = save(plain)
    assert.doesNotMatch(out, /target=/)
    assert.doesNotMatch(out, /rel=/)
  })

  test('the toggle reflects whether the link opens in a new tab', () => {
    win.setContent(plain)
    caretInButton()
    assert.equal(toggle().classList.contains('active'), false)
    win.setContent(newTab)
    caretInButton()
    assert.equal(toggle().classList.contains('active'), true)
  })

  test('pressing it writes core\'s exact target and rel', () => {
    win.setContent(plain)
    caretInButton()
    press(toggle())
    const out = win.toWordPressHTML(editor.getHTML())
    assert.match(out, /target="_blank"/)
    assert.match(out, /rel="noopener"/)
    assert.doesNotMatch(out, /rel=" noopener"/)
  })

  test('pressing it again removes both', () => {
    win.setContent(newTab)
    caretInButton()
    press(toggle())
    const out = win.toWordPressHTML(editor.getHTML())
    assert.doesNotMatch(out, /target=/)
    assert.doesNotMatch(out, /rel=/)
  })

  test('an existing rel token is kept on both sides of the toggle', () => {
    win.setContent(plain.replace('href="https://x.test"', 'href="https://x.test" rel="nofollow"'))
    caretInButton()
    press(toggle())
    assert.match(win.toWordPressHTML(editor.getHTML()), /rel="nofollow noopener"/)
    press(toggle())
    const off = win.toWordPressHTML(editor.getHTML())
    assert.match(off, /rel="nofollow"/)
    assert.doesNotMatch(off, /noopener/)
  })

  test('turning it on twice does not double the rel token', () => {
    win.setContent(newTab)
    caretInButton()
    const before = win.toWordPressHTML(editor.getHTML())
    assert.equal((before.match(/noopener/g) || []).length, 1)
  })
})

// A prose link is the Tiptap Link mark, not a block, so this control is
// hand-written rather than a registry entry. The site's own format-library.js
// composes the same single "noopener" token core/button does.
describe('a prose link opening in a new tab', () => {
  const plain = '<!-- wp:paragraph -->\n<p>See <a href="https://x.test">this</a>.</p>\n<!-- /wp:paragraph -->'
  const newTab = '<!-- wp:paragraph -->\n<p>See <a href="https://x.test" target="_blank" rel="noopener">this</a>.</p>\n<!-- /wp:paragraph -->'

  const controls = () => win.document.getElementById('link-controls')
  const toggle = () => win.document.getElementById('btn-link-new-tab')
  const press = el => el.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true }))

  // extendMarkRange over an existing mark poisons exactly the next setContent
  // (see the CLAUDE.md gotcha), so every test absorbs it before loading.
  function load(src) {
    editor.commands.setContent('<p></p>', false)
    win.setContent(src)
    let found = null
    editor.state.doc.descendants((node, pos) => {
      if (found !== null || !node.isText || !node.marks.some(m => m.type.name === 'link')) return
      found = pos + 1
    })
    assert.ok(found !== null, 'no linked text')
    editor.commands.setTextSelection(found)
  }

  test('the control appears only inside a link', () => {
    load(plain)
    assert.equal(controls().style.display, 'inline-flex')
    editor.commands.setContent('<p>bare</p>', false)
    editor.commands.setTextSelection(2)
    assert.equal(controls().style.display, 'none')
  })

  test('it reflects the current target', () => {
    load(plain)
    assert.equal(toggle().classList.contains('active'), false)
    load(newTab)
    assert.equal(toggle().classList.contains('active'), true)
  })

  // Tiptap emits target and rel ahead of href, because Link.configure seeds
  // them into HTMLAttributes first. Gutenberg's validator is order-insensitive
  // and only a link the user actually toggled is rewritten, so this is left as
  // it is rather than fought.
  test('pressing it writes target and rel', () => {
    load(plain)
    press(toggle())
    const out = win.toWordPressHTML(editor.getHTML())
    const anchor = out.match(/<a [^>]*>/)[0]
    assert.match(anchor, /href="https:\/\/x\.test"/)
    assert.match(anchor, /target="_blank"/)
    assert.match(anchor, /rel="noopener"/)
  })

  test('pressing it again removes both', () => {
    load(newTab)
    press(toggle())
    const out = win.toWordPressHTML(editor.getHTML())
    assert.match(out, /<a href="https:\/\/x\.test">/)
    assert.doesNotMatch(out, /target=/)
    assert.doesNotMatch(out, /noopener/)
  })

  test('an existing rel token survives both directions', () => {
    load('<!-- wp:paragraph -->\n<p>See <a href="https://x.test" rel="nofollow">this</a>.</p>\n<!-- /wp:paragraph -->')
    press(toggle())
    assert.match(win.toWordPressHTML(editor.getHTML()), /rel="nofollow noopener"/)
    press(toggle())
    const off = win.toWordPressHTML(editor.getHTML())
    assert.match(off, /rel="nofollow"/)
    assert.doesNotMatch(off, /noopener/)
  })

  test('the link text is untouched', () => {
    load(plain)
    press(toggle())
    assert.match(win.toWordPressHTML(editor.getHTML()), />this<\/a>/)
  })
})

// core/accordion stores showIcon and iconPosition, and core/accordion-heading
// stores them again -- it is the heading's copy that draws has-icon and the
// icon span. A control that wrote only the parent would leave the two
// disagreeing, which is what makes Gutenberg call a block invalid.
describe('accordion icons propagate to every heading', () => {
  const two = `<!-- wp:accordion -->
<div role="group" class="wp-block-accordion"><!-- wp:accordion-item -->
<div class="wp-block-accordion-item"><!-- wp:accordion-heading -->
<h3 class="wp-block-accordion-heading has-icon has-icon-right"><button type="button" class="wp-block-accordion-heading__toggle"><span class="wp-block-accordion-heading__toggle-title">One</span><span class="wp-block-accordion-heading__toggle-icon" aria-hidden="true">+</span></button></h3>
<!-- /wp:accordion-heading -->

<!-- wp:accordion-panel -->
<div role="region" class="wp-block-accordion-panel"><!-- wp:paragraph -->
<p>First body</p>
<!-- /wp:paragraph --></div>
<!-- /wp:accordion-panel --></div>
<!-- /wp:accordion-item -->

<!-- wp:accordion-item -->
<div class="wp-block-accordion-item"><!-- wp:accordion-heading -->
<h3 class="wp-block-accordion-heading has-icon has-icon-right"><button type="button" class="wp-block-accordion-heading__toggle"><span class="wp-block-accordion-heading__toggle-title">Two</span><span class="wp-block-accordion-heading__toggle-icon" aria-hidden="true">+</span></button></h3>
<!-- /wp:accordion-heading -->

<!-- wp:accordion-panel -->
<div role="region" class="wp-block-accordion-panel"><!-- wp:paragraph -->
<p>Second body</p>
<!-- /wp:paragraph --></div>
<!-- /wp:accordion-panel --></div>
<!-- /wp:accordion-item --></div>
<!-- /wp:accordion -->

<p>Outside</p>`

  const group = () => win.document.getElementById('settings-accordionBlock-controls')
  const showIcon = () => group().querySelector('[data-setting="showIcon"]')
  const position = () => group().querySelector('[data-setting="iconPosition"]')

  function caretIn(text) {
    let found = null
    editor.state.doc.descendants((node, pos) => {
      if (found !== null || !node.isTextblock || node.textContent !== text) return
      found = pos + 1
    })
    assert.ok(found !== null, `no textblock reading "${text}"`)
    editor.commands.setTextSelection(found)
  }

  const press = el => el.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true }))

  function choose(el, value) {
    el.value = value
    el.dispatchEvent(new win.Event('change', { bubbles: true }))
  }

  const positionValue = () => (position().textContent === 'Icon left' ? 'left' : 'right')

  function setPosition(value) {
    if (positionValue() !== value) press(position())
  }

  const headingClasses = out => (out.match(/<h3 class="([^"]*)"/g) || []).map(m => m.match(/"([^"]*)"/)[1])

  test('both controls are generated for the accordion block', () => {
    assert.ok(group(), 'no generated group for accordionBlock')
    assert.ok(showIcon(), 'no showIcon control')
    assert.equal(position().tagName, 'BUTTON', 'two options is a switch, not a list')
    assert.equal(position().classList.contains('active'), false, 'the side shows its value, never a checked state')
  })

  test('they appear inside an accordion and nowhere else', () => {
    win.setContent(two)
    caretIn('First body')
    assert.equal(group().style.display, 'inline-flex')
    caretIn('Outside')
    assert.equal(group().style.display, 'none')
  })

  test('they reflect the loaded values', () => {
    win.setContent(two)
    caretIn('First body')
    assert.equal(showIcon().classList.contains('active'), true)
    assert.equal(positionValue(), 'right')
    win.setContent(two.replace('<!-- wp:accordion -->', '<!-- wp:accordion {"iconPosition":"left"} -->'))
    caretIn('First body')
    assert.equal(positionValue(), 'left')
  })

  test('the side control is joined to the toggle that gates it', () => {
    const pair = position().parentElement
    assert.equal(pair.className, 'setting-pair')
    assert.equal(pair.firstElementChild, showIcon())
    assert.equal(pair.lastElementChild, position())
  })

  test('the side control is hidden while the icon is off', () => {
    win.setContent(two)
    caretIn('First body')
    assert.equal(position().style.display, '')
    assert.equal(position().parentElement.classList.contains('is-solo'), false)
    press(showIcon())
    caretIn('First body')
    assert.equal(position().style.display, 'none')
    assert.equal(position().parentElement.classList.contains('is-solo'), true)
    press(showIcon())
    caretIn('First body')
    assert.equal(position().style.display, '')
    assert.equal(position().parentElement.classList.contains('is-solo'), false)
  })

  test('turning the icon off writes the parent, both headings and their markup', () => {
    win.setContent(two)
    caretIn('First body')
    press(showIcon())
    const out = win.toWordPressHTML(editor.getHTML())
    assert.match(out, /wp:accordion \{"showIcon":false\}/)
    assert.equal((out.match(/wp:accordion-heading \{"showIcon":false\}/g) || []).length, 2)
    assert.deepEqual(headingClasses(out), ['wp-block-accordion-heading', 'wp-block-accordion-heading'])
    assert.doesNotMatch(out, /toggle-icon/)
  })

  // The pause is load-bearing: prosemirror-history groups steps within 500ms,
  // so without it the load and the click undo as one event.
  test('one undo restores the parent and both headings together', async () => {
    win.setContent(two)
    caretIn('First body')
    await new Promise(r => setTimeout(r, 600))
    press(showIcon())
    editor.commands.undo()
    const out = win.toWordPressHTML(editor.getHTML())
    assert.doesNotMatch(out, /showIcon/)
    assert.equal((out.match(/has-icon has-icon-right/g) || []).length, 2)
  })

  test('moving the icon left rewrites both headings and their icon spans', () => {
    win.setContent(two)
    caretIn('First body')
    setPosition('left')
    const out = win.toWordPressHTML(editor.getHTML())
    assert.match(out, /wp:accordion \{"iconPosition":"left"\}/)
    assert.equal((out.match(/wp:accordion-heading \{"iconPosition":"left"\}/g) || []).length, 2)
    assert.deepEqual(headingClasses(out),
      ['wp-block-accordion-heading has-icon has-icon-left', 'wp-block-accordion-heading has-icon has-icon-left'])
    assert.match(out, /toggle"><span class="wp-block-accordion-heading__toggle-icon"/)
  })

  test('returning to the default writes no key on the parent or the headings', () => {
    win.setContent(two.replace('<!-- wp:accordion -->', '<!-- wp:accordion {"iconPosition":"left"} -->')
      .replace(/<!-- wp:accordion-heading -->/g, '<!-- wp:accordion-heading {"iconPosition":"left"} -->')
      .replace(/has-icon has-icon-right/g, 'has-icon has-icon-left'))
    caretIn('First body')
    setPosition('right')
    const out = win.toWordPressHTML(editor.getHTML())
    assert.doesNotMatch(out, /iconPosition/)
    assert.match(out, /<!-- wp:accordion -->/)
    assert.equal((out.match(/<!-- wp:accordion-heading -->/g) || []).length, 2)
  })

  test('an unmodeled attribute on the accordion survives the change', () => {
    win.setContent(two.replace('<!-- wp:accordion -->', '<!-- wp:accordion {"metadata":{"name":"A"}} -->'))
    caretIn('First body')
    press(showIcon())
    const out = win.toWordPressHTML(editor.getHTML())
    assert.match(out, /"metadata":\{"name":"A"\}/)
    assert.match(out, /"showIcon":false/)
  })

  // Core hands the heading its icon settings through block context, so an item
  // added to a left-icon accordion is left-icon too. Quill has no context, so
  // the command copies them.
  test('an item added afterwards inherits the icon settings', () => {
    win.setContent(two)
    caretIn('First body')
    setPosition('left')
    win.document.querySelector('[data-cmd="addAccordionItem"]')
      .dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true }))
    const out = win.toWordPressHTML(editor.getHTML())
    assert.equal((out.match(/wp:accordion-heading \{"iconPosition":"left"\}/g) || []).length, 3)
    assert.equal((out.match(/has-icon has-icon-left/g) || []).length, 3)
  })

  test('a heading keeps its own level while the icon changes around it', () => {
    win.setContent(two.replace('<!-- wp:accordion-heading -->', '<!-- wp:accordion-heading {"level":3} -->'))
    caretIn('First body')
    setPosition('left')
    const out = win.toWordPressHTML(editor.getHTML())
    assert.match(out, /wp:accordion-heading \{"level":3,"iconPosition":"left"\}/)
  })
})

// Quill rebuilds the visible HTML on every save, so anything the node's own
// renderHTML does not write was dropped. The carrier snapshots the parsed
// element's attributes and replays them, which is what lets a block Quill has
// no registry entry for keep its markup.
describe('the generic attribute carrier', () => {
  function caretIn(text) {
    let found = null
    editor.state.doc.descendants((node, pos) => {
      if (found !== null || !node.isTextblock || !node.textContent.includes(text)) return
      found = pos + 1
    })
    assert.ok(found !== null, `no textblock containing "${text}"`)
    editor.commands.setTextSelection(found)
  }

  test('an unmodeled attribute on a container survives an edit', () => {
    assert.match(save(fixture('settings-details.html')), /<details class="wp-block-details" name="faq">/)
  })

  test('an unmodeled class on a container survives an edit', () => {
    const out = save(fixture('settings-columns.html'))
    assert.match(out, /class="wp-block-columns is-not-stacked-on-mobile"/)
    assert.match(out, /class="wp-block-column is-vertically-aligned-center" style="flex-basis:66\.66%"/)
  })

  // Not asserted as one string: WebKit moves an inline style to the end of the
  // attribute list and jsdom does not, so only the values are the same in both.
  test('a sourced attribute no registry entry declares survives', () => {
    const ol = /<ol ([^>]*)>/.exec(save(fixture('settings-list.html')))[1]
    assert.match(ol, /(^| )reversed( |$)/)
    assert.match(ol, /start="5"/)
    assert.match(ol, /style="list-style-type:upper-roman"/)
    assert.match(ol, /class="wp-block-list"/)
  })

  test('the attribute order of the original markup is kept', () => {
    const src = '<!-- wp:details -->\n<details class="wp-block-details" name="faq" open><summary>S</summary><!-- wp:paragraph -->\n<p>B</p>\n<!-- /wp:paragraph --></details>\n<!-- /wp:details -->'
    assert.match(save(src), /<details class="wp-block-details" name="faq" open>/)
  })

  // The snapshot is taken at parse time, so an attribute the node itself draws
  // would come back from the dead the moment the user turns it off.
  test('an attribute the node models is not resurrected once turned off', () => {
    win.setContent('<!-- wp:details -->\n<details class="wp-block-details" name="faq" open><summary>S</summary><!-- wp:paragraph -->\n<p>Body</p>\n<!-- /wp:paragraph --></details>\n<!-- /wp:details -->')
    caretIn('Body')
    editor.commands.toggleDetailsOpen()
    const out = win.toWordPressHTML(editor.getHTML())
    assert.doesNotMatch(out, /open/)
    assert.match(out, /name="faq"/)
  })

  // A setting that draws a class puts that class into the snapshot as well, so
  // a node whose class any setting writes has to own its class list outright.
  test('a class a registry setting drew is not resurrected once turned off', () => {
    win.setContent(`<!-- wp:accordion -->
<div role="group" class="wp-block-accordion"><!-- wp:accordion-item {"openByDefault":true} -->
<div class="wp-block-accordion-item is-open"><!-- wp:accordion-heading -->
<h3 class="wp-block-accordion-heading has-icon has-icon-right"><button type="button" class="wp-block-accordion-heading__toggle"><span class="wp-block-accordion-heading__toggle-title">T</span><span class="wp-block-accordion-heading__toggle-icon" aria-hidden="true">+</span></button></h3>
<!-- /wp:accordion-heading -->

<!-- wp:accordion-panel -->
<div role="region" class="wp-block-accordion-panel"><!-- wp:paragraph -->
<p>Body</p>
<!-- /wp:paragraph --></div>
<!-- /wp:accordion-panel --></div>
<!-- /wp:accordion-item --></div>
<!-- /wp:accordion -->`)
    caretIn('Body')
    const toggle = win.document.querySelector('#settings-accordionItem-controls [data-setting="openByDefault"]')
    toggle.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true }))
    assert.doesNotMatch(win.toWordPressHTML(editor.getHTML()), /is-open/)
  })

  // colspan changes as the user edits columns, so a snapshot of it goes stale
  // the moment they do.
  describe('a colspanned table', () => {
    const src = '<!-- wp:table -->\n<figure class="wp-block-table"><table class="wp-block-table"><tbody><tr><td colspan="2">A</td></tr><tr><td>B</td><td>C</td></tr></tbody></table></figure>\n<!-- /wp:table -->'

    const liveColspan = () => {
      let span = null
      editor.state.doc.descendants(node => {
        if (span === null && node.type.name === 'tableCell' && node.textContent === 'A') span = node.attrs.colspan
      })
      return span
    }

    const savedColspan = () => {
      const m = /<td( colspan="(\d+)")?>A<\/td>/.exec(win.toWordPressHTML(editor.getHTML()))
      return m ? Number(m[2] || 1) : null
    }

    test('survives a column being added', () => {
      win.setContent(src)
      caretIn('B')
      editor.commands.addColumnAfter()
      assert.equal(savedColspan(), liveColspan())
    })

    test('survives a column being deleted', () => {
      win.setContent(src)
      caretIn('B')
      editor.commands.deleteColumn()
      assert.equal(savedColspan(), liveColspan())
    })
  })
})

describe('inline styles and delimiter attributes are written the way core writes them', () => {
  test('a hex text colour is not re-serialized as rgb()', () => {
    const out = save(fixture('settings-paragraph-color.html'))
    assert.match(out, /style="color:#cf2e2e"/)
  })

  test('a style value core wrote with a space keeps it', () => {
    const out = save('<!-- wp:columns -->\n<div class="wp-block-columns" style="margin: 0 auto"><!-- wp:column -->\n<div class="wp-block-column"><!-- wp:paragraph -->\n<p>C</p>\n<!-- /wp:paragraph --></div>\n<!-- /wp:column --></div>\n<!-- /wp:columns -->')
    assert.match(out, /style="margin: 0 auto"/)
  })

  test('a style Quill itself authored is still compacted', () => {
    const out = save('<!-- wp:image {"id":1,"width":"300px"} -->\n<figure class="wp-block-image is-resized"><img src="https://x.test/a.jpg" alt="" class="wp-image-1" style="width:300px;height:auto"/></figure>\n<!-- /wp:image -->')
    assert.match(out, /style="width:300px;height:auto"/)
  })

  test('a delimiter attribute escapes -- the way core does', () => {
    const out = save(fixture('settings-tabs.html').replace(/tab 1/g, 'Pros -- Cons'))
    assert.match(out, /\\u002d\\u002d/)
    assert.doesNotMatch(out, /"label":"Pros -- Cons"/)
  })

  test('a delimiter attribute escapes & the way core does', () => {
    const out = save(fixture('settings-embed.html'))
    assert.match(out, /\\u0026t=10s/)
  })

  test('carried comment attributes keep the order WordPress wrote them', () => {
    const out = save(fixture('settings-embed.html'))
    const attrs = out.slice(out.indexOf('{'), out.indexOf('} -->') + 1)
    assert.deepEqual(Object.keys(JSON.parse(attrs.replaceAll('\\u0026', '&'))),
      ['url', 'type', 'providerNameSlug', 'responsive', 'className'])
  })

  test('an owned key that is no longer present is dropped, not moved', () => {
    const out = save('<!-- wp:heading {"level":3,"className":"x"} -->\n<h3 class="wp-block-heading x">H</h3>\n<!-- /wp:heading -->')
    const attrs = JSON.parse(out.slice(out.indexOf('{'), out.indexOf('} -->') + 1))
    assert.deepEqual(Object.keys(attrs), ['level', 'className'])
  })
})

describe('a quote holds inner blocks, not bare markup', () => {
  test('a heading inside a quote keeps its delimiters', () => {
    const out = save(fixture('settings-quote-inner.html'))
    assert.match(out, /<!-- wp:heading \{"level":4\} -->\n<h4 class="wp-block-heading">A heading inside a quote<\/h4>\n<!-- \/wp:heading -->/)
  })

  test('a list inside a quote is delimited down to its items', () => {
    const out = save(fixture('settings-quote-inner.html'))
    assert.match(out, /<!-- wp:list -->/)
    assert.equal((out.match(/<!-- wp:list-item -->/g) || []).length, 2)
  })

  test('the cite is left undelimited', () => {
    const out = save(fixture('settings-quote-inner.html'))
    assert.match(out, /<cite>Someone<\/cite>/)
    assert.doesNotMatch(out, /wp:cite/)
  })

  test('a Quill-made quote holding a list emits list delimiters', () => {
    const out = win.toWordPressHTML('<blockquote class="wp-block-quote"><ul><li>a</li></ul></blockquote>')
    assert.match(out, /<!-- wp:list -->/)
    assert.match(out, /<!-- wp:list-item -->/)
  })
})

describe('a table carries its own fixed-layout setting', () => {
  test('the has-fixed-layout class survives an edit', () => {
    const out = save(fixture('settings-table-fixed.html'))
    assert.match(out, /<table class="has-fixed-layout">/)
  })

  test('a default table writes no hasFixedLayout key', () => {
    const out = save(fixture('settings-table-fixed.html'))
    assert.doesNotMatch(out, /hasFixedLayout/)
  })

  test('a table core turned fixed layout off for keeps the key and no class', () => {
    const out = save(fixture('settings-table.html'))
    assert.match(out, /"hasFixedLayout":false/)
    assert.doesNotMatch(out, /has-fixed-layout/)
  })

  test('the class is not moved onto the figure', () => {
    const out = save(fixture('settings-table-fixed.html'))
    assert.match(out, /<figure class="wp-block-table">/)
  })

  test('a table Quill inserts is fixed layout, the way core creates one', () => {
    win.setContent('<!-- wp:paragraph -->\n<p>x</p>\n<!-- /wp:paragraph -->')
    editor.commands.focus('end')
    editor.commands.insertTable({ rows: 2, cols: 2, withHeaderRow: true })
    assert.match(win.toWordPressHTML(editor.getHTML()), /<table class="has-fixed-layout">/)
  })
})

describe('void elements are written the way core writes them', () => {
  test('a separator self-closes', () => {
    assert.match(save(fixture('settings-separator.html')), /<hr class="[^"]*"\/>/)
  })

  test('an image self-closes', () => {
    assert.match(save(fixture('settings-image.html')), /<img [^>]*\/>/)
  })

  test('a break is left bare, the way core writes it inside rich text', () => {
    const out = save('<!-- wp:paragraph -->\n<p>one<br>two</p>\n<!-- /wp:paragraph -->')
    assert.match(out, /one<br>two/)
  })

  test('a slash is not doubled on a second save', () => {
    const once = save(fixture('settings-separator.html'))
    assert.equal(save(once), once)
  })

  test('a preserved unsupported block keeps its own void syntax', () => {
    const src = '<!-- wp:html -->\n<div><img src="https://x.test/a.jpg" alt=""></div>\n<!-- /wp:html -->'
    assert.equal(save(src), src)
  })

  test('a < inside an attribute value does not end the tag early', () => {
    const out = save('<!-- wp:image {"id":1} -->\n<figure class="wp-block-image"><img src="https://x.test/a.jpg" alt="a <b> tag" class="wp-image-1"/></figure>\n<!-- /wp:image -->')
    assert.match(out, /alt="a <b> tag"/)
    assert.doesNotMatch(out, /<b\/>/)
  })
})

describe('attributes on a node\'s child elements survive', () => {
  test('a button anchor keeps its colour classes', () => {
    const out = save(fixture('settings-button-color.html'))
    assert.match(out, /has-white-color has-vivid-red-background-color has-text-color has-background/)
  })

  test('a button anchor keeps its inline style verbatim', () => {
    assert.match(save(fixture('settings-button-color.html')), /style="border-radius:8px"/)
  })

  test('a button anchor keeps the classes the node itself writes', () => {
    const out = save(fixture('settings-button-color.html'))
    assert.match(out, /wp-block-button__link/)
    assert.match(out, /wp-element-button/)
  })

  test('an image link keeps target and rel', () => {
    const out = save(fixture('settings-image.html'))
    assert.match(out, /target="_blank"/)
    assert.match(out, /rel=" noopener"/)
  })

  test('an image link keeps its own class', () => {
    assert.match(save(fixture('settings-image-custom-link.html')), /class="my-link"/)
  })

  test('a custom image link keeps its destination instead of becoming media', () => {
    const out = save(fixture('settings-image-custom-link.html'))
    assert.match(out, /"linkDestination":"custom"/)
    assert.doesNotMatch(out, /"linkDestination":"media"/)
  })

  test('an unlinked image writes no linkDestination', () => {
    const out = save('<!-- wp:image {"id":1,"linkDestination":"custom"} -->\n<figure class="wp-block-image"><img src="https://x.test/a.jpg" alt="" class="wp-image-1"/></figure>\n<!-- /wp:image -->')
    assert.doesNotMatch(out, /linkDestination/)
  })

  test('a non-dimension style on the img survives', () => {
    assert.match(save(fixture('settings-image-custom-link.html')), /style="border-radius:12px"/)
  })

  test('an accordion heading keeps colour classes the node does not write', () => {
    assert.match(save(fixture('settings-accordion-color.html')), /has-vivid-red-color has-text-color/)
  })

  test('turning the accordion icon off does not resurrect its classes', () => {
    win.setContent(fixture('settings-accordion-color.html'))
    assert.ok(setNodeAttr('accordionHeading', 'showIcon', false))
    const out = win.toWordPressHTML(editor.getHTML())
    assert.doesNotMatch(out, /has-icon/)
    assert.match(out, /has-vivid-red-color has-text-color/)
  })
})

describe('a heading omits the level core treats as the default', () => {
  test('an h2 writes no level', () => {
    const out = save('<!-- wp:heading -->\n<h2 class="wp-block-heading">H</h2>\n<!-- /wp:heading -->')
    assert.equal(out, '<!-- wp:heading -->\n<h2 class="wp-block-heading">H</h2>\n<!-- /wp:heading -->')
  })

  test('an h3 still writes its level', () => {
    assert.match(save('<!-- wp:heading {"level":3} -->\n<h3 class="wp-block-heading">H</h3>\n<!-- /wp:heading -->'), /"level":3/)
  })

  test('an h2 core wrote the level on explicitly keeps it', () => {
    const src = '<!-- wp:heading {"level":2} -->\n<h2 class="wp-block-heading">H</h2>\n<!-- /wp:heading -->'
    assert.equal(save(src), src)
  })
})

// The corpus, all at once. Each settings-*.html is real post_content from the
// site, so a match here is the closest thing to opening the post in Gutenberg
// and finding nothing changed.
describe('the whole settings fixture corpus', () => {
  const KNOWN_DIFFERENCES = {
    'settings-separator.html': 'Quill writes <hr> where core writes <hr/>',
  }

  const dir = path.resolve(__dirname, 'fixtures')
  const names = fs.readdirSync(dir).filter(n => n.startsWith('settings-') && n.endsWith('.html'))

  test('the corpus is the twenty-one fixtures the scan produced', () => {
    assert.equal(names.length, 21)
  })

  for (const name of names) {
    test(`${name} comes back untouched when nothing is edited`, () => {
      win.setContent(fixture(name))
      assert.equal(win.getContent(), fixture(name))
    })

    test(`${name} is idempotent once edited`, () => {
      const once = save(fixture(name))
      assert.equal(save(once), once)
    })

    // Byte-identity against the fixture is the real bar. Each fixture that
    // cannot meet it yet names why, so the difference is recorded rather than
    // invisible -- remove an entry from KNOWN_DIFFERENCES when it is fixed.
    test(`${name} saves byte-identically once edited`, { skip: KNOWN_DIFFERENCES[name] }, () => {
      assert.equal(save(fixture(name)), fixture(name))
    })
  }
})

// Gutenberg's serializer joins sibling blocks with a blank line, at every
// level. Quill wrote them adjacent, so every post with more than one block came
// back with its whitespace rewritten.
describe('sibling blocks are separated by a blank line', () => {
  const two = '<!-- wp:paragraph -->\n<p>One</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:paragraph -->\n<p>Two</p>\n<!-- /wp:paragraph -->'

  test('two top-level blocks keep the blank line between them', () => {
    assert.equal(save(two), two)
  })

  test('nothing is added before the first block or after the last', () => {
    const out = save(two)
    assert.ok(!/^\s/.test(out), 'leading whitespace')
    assert.ok(!/\s$/.test(out), 'trailing whitespace')
  })

  test('a second save does not stack another blank line', () => {
    assert.equal(save(save(two)), two)
  })

  test('inner blocks of a container get it too', () => {
    assert.equal(save(fixture('settings-buttons.html')), fixture('settings-buttons.html'))
  })

  test('so do nested containers', () => {
    assert.equal(save(fixture('settings-accordion.html')), fixture('settings-accordion.html'))
    assert.equal(save(fixture('settings-tabs.html')), fixture('settings-tabs.html'))
  })

  test('list items get it', () => {
    const list = '<!-- wp:list -->\n<ul class="wp-block-list"><!-- wp:list-item -->\n<li>A</li>\n<!-- /wp:list-item -->\n\n<!-- wp:list-item -->\n<li>B</li>\n<!-- /wp:list-item --></ul>\n<!-- /wp:list -->'
    assert.equal(save(list), list)
  })

  test('quote paragraphs get it', () => {
    const quote = '<!-- wp:quote -->\n<blockquote class="wp-block-quote"><!-- wp:paragraph -->\n<p>A</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:paragraph -->\n<p>B</p>\n<!-- /wp:paragraph --></blockquote>\n<!-- /wp:quote -->'
    assert.equal(save(quote), quote)
  })

  test('a block that already carries its own delimiters is left alone', () => {
    const out = save(fixture('unsupported-blocks.html'))
    assert.doesNotMatch(out, /-->\n\n\n/)
  })
})

// Adding a registry entry with no coverage is how the corpus silently falls
// behind the registry. Read from Node rather than the page: a describe body
// runs before the editor exists.
describe('every registry entry is covered', () => {
  const registry = require('../Sources/QuillKit/Resources/block-settings.js')
  const suiteSource = fs.readFileSync(__filename, 'utf8') +
    fs.readFileSync(path.resolve(__dirname, 'test-editor-containers.js'), 'utf8')

  for (const node of registry.settingsNodeNames()) {
    for (const name of Object.keys(registry.settingsFor(node))) {
      test(`${node}.${name} is named by a test`, () => {
        assert.ok(suiteSource.includes(name), `no test mentions ${name}`)
      })
    }
  }
})
