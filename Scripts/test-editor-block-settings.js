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

  const picker = node => win.document.querySelector(`#settings-${node}-controls select[data-setting="className"]`)

  function choose(node, value) {
    const el = picker(node)
    assert.ok(el, `no style picker for ${node}`)
    el.value = value
    el.dispatchEvent(new win.Event('change', { bubbles: true }))
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
        assert.equal(picker(c.node).value, c.from)
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
    assert.equal(picker('blockquote').value, '')
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
