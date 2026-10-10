const DURATION = 68

// Seconds of stage before the timeline's zero, so the window opens on the music's first hit.
const LEAD = 1

const $ = sel => document.querySelector(sel)
const $$ = sel => [...document.querySelectorAll(sel)]

const COPY = {
  title: 'Above the Tree Line',
  p1: 'We left the trailhead well before sunrise, when the meadow was still grey and quiet and the lake was still holding on to the last few stars of the night.',
  p1Short: 'We left the trailhead before sunrise, while the lake still held the last stars.',
  heading: 'The last mile',
  accHeading: 'What I packed',
  accPanel: 'Layers, a headlamp and more water than seemed sensible.',
}

const BEATS = {
  write: [5.6, 15.9],
  media: [16.1, 24.9],
  claude: [25.1, 35.9],
  offline: [36.1, 42.9],
  settings: [43.1, 53.8],
}

// Window-space anchor of the camera inside #viewport, and the resting framing.
const ANCHOR = [670, 540]
const BASE = [520, 340, 1.15]

const CAMERA = [
  [5.0, [520, 340, 0.2]],
  [6.5, BASE, Ease.outQuint],
  [7.4, [630, 290, 1.6]],
  [10.6, [635, 300, 1.6]],
  [11.6, [640, 320, 1.6]],
  [12.3, [680, 320, 1.5]],
  [15.2, [660, 350, 1.5]],
  [16.4, BASE],
  [17.8, BASE],
  [18.8, [640, 420, 1.35]],
  [21.9, [640, 420, 1.35]],
  [22.6, BASE],
  [25.4, BASE],
  [26.0, [640, 230, 1.6]],
  [29.3, [640, 230, 1.6]],
  [29.9, [640, 390, 1.3]],
  [30.9, [640, 390, 1.3]],
  [32.4, [720, 300, 1.3]],
  [33.4, [880, 290, 1.55]],
  [35.9, [880, 290, 1.55]],
  [36.8, [680, 200, 1.45]],
  [38.75, [680, 200, 1.45]],
  [39.6, BASE],
  [42.8, BASE],
  [43.8, [880, 230, 1.6]],
  [45.4, [880, 280, 1.6]],
  [47.6, [880, 470, 1.6]],
  [48.9, [880, 470, 1.6]],
  [49.5, [800, 200, 1.6]],
  [50.6, [800, 200, 1.6]],
  [51.8, BASE],
  [54.0, BASE],
  [55.0, [520, 340, 0.2], Ease.in],
]

const SITE_TAGS = ['alpine', 'backpacking', 'camping', 'lakes', 'maps', 'snow', 'summit', 'wildflowers']

// How far Post Settings scrolls to bring the featured image into view.
const SETTINGS_SCROLL = 211

const TOASTS = [
  [19.3, 20.9, 'Image inserted'],
  [39.0, 42.6, 'Saved to WordPress'],
  [51.0, 53.6, 'Published'],
]

const CLICKS = [11.35, 11.85, 13.1, 13.65, 17.9, 22.6, 23.6, 23.98, 24.12, 25.3, 26.0, 27.2, 28.0, 30.7, 31.7, 36.2, 38.6, 43.3, 44.5, 45.2, 45.9, 48.2, 49.5, 50.2, 50.95]

// Document nodes

const P = text => ({ type: 'paragraph', ...(text ? { content: [{ type: 'text', text }] } : {}) })
const H2 = text => ({ type: 'heading', attrs: { level: 2 }, ...(text ? { content: [{ type: 'text', text }] } : {}) })
const ACCORDION = (heading, panel) => ({
  type: 'accordionBlock',
  content: [{
    type: 'accordionItem',
    content: [
      { type: 'accordionHeading', attrs: { level: 3, showIcon: true, iconPosition: 'right' }, ...(heading ? { content: [{ type: 'text', text: heading }] } : {}) },
      { type: 'accordionPanel', content: [P(panel)] },
    ],
  }],
})
const IMAGE = src => ({ type: 'image', attrs: { src, alt: '', mediaId: 101, linkTo: 'none' } })

function editorState(t) {
  const p1 = t < 29.6 ? COPY.p1 : COPY.p1Short
  const content = []
  let caret = null
  let selection = null

  if (t < 8.1) {
    content.push(P(''))
  } else if (t < 10.8) {
    content.push(P(typed(t, 8.1, 10.7, COPY.p1)))
    caret = [0, 'end']
  } else if (t < 11.9) {
    content.push(P(COPY.p1), P(''))
    caret = [1, 'end']
  } else if (t < 13.7) {
    content.push(P(COPY.p1), H2(typed(t, 12.0, 12.6, COPY.heading)))
    caret = [1, 'end']
  } else {
    content.push(P(p1), H2(COPY.heading), ACCORDION(typed(t, 13.85, 14.4, COPY.accHeading), typed(t, 14.55, 15.35, COPY.accPanel)))
    caret = t < 14.5 ? [2, 'end'] : [3, 'end']
    if (t >= 19.1) content.push(IMAGE(Photos.hero))
    content.push(P(''))
  }

  if (t >= 15.6) caret = null
  if (t >= 26.0 && t < 30.7) {
    const end = t < 29.6 ? Math.round(lerp(0, COPY.p1.length, Ease.inOut(span(t, 26.0, 26.9)))) : COPY.p1Short.length
    selection = [[0, 0], [0, end]]
  }
  if (t >= 30.7 && t < 36.0) caret = [0, 'end']

  return { content, caret, selection }
}

const TYPING = [[6.9, 7.9], [8.1, 10.7], [12.0, 12.6], [13.85, 14.4], [14.55, 15.35], [46.0, 46.5], [46.8, 47.3]]

function typingSince(t) {
  let since = 0
  for (const [a, b] of TYPING) if (t >= a) since = Math.min(t, b)
  return since
}

// Pointer path: each key is [time, point or target name, ease].

const TARGETS = {
  headingButton: () => EditorDriver.pointOfSelector('#heading-button'),
  heading2: () => EditorDriver.pointOfSelector('#heading-menu [data-heading-level="2"]', 0.35),
  insert: () => EditorDriver.pointOfSelector('#insert-button'),
  accordionItem: () => EditorDriver.pointOfSelector('#insert-menu [data-insert="accordion"]', 0.3),
  mediaTab: () => pointOf('.tab[data-tab="media"]'),
  draftsTab: () => pointOf('.tab[data-tab="drafts"]'),
  firstTile: () => pointOf('#media-grid img', 0.4, 0.45),
  p1Start: () => EditorDriver.pointOfPos(EditorDriver.posIn(0, 0)),
  p1End: () => EditorDriver.pointOfPos(EditorDriver.posIn(0, 'end')),
  p1Mid: () => EditorDriver.pointOfPos(EditorDriver.posIn(0, 34)),
  shorter: () => pointOf('#menu-shorter', 0.35),
  accept: () => pointOf('#ai-accept'),
  evaluate: () => EditorDriver.pointOfSelector('#btn-evaluate'),
  inspector: () => pointOf('#btn-inspector'),
  saveWP: () => pointOf('#btn-save-wp'),
  hiking: () => pointOf('.check[data-cat="hiking"] i'),
  trailNotes: () => pointOf('.check[data-cat="trail-notes"] i'),
  tagField: () => pointOf('#tag-field', 0.3),
  choose: () => pointOf('#btn-choose'),
  statusPopup: () => pointOf('#status-popup', 0.4),
  published: () => pointOf('#status-menu [data-status="publish"]', 0.8),
  publish: () => pointOf('#btn-publish'),
}

const POINTER = [
  [10.5, [720, 430]],
  [11.25, 'headingButton'],
  [11.4, 'headingButton'],
  [11.75, 'heading2'],
  [11.9, [377, 244]],
  [12.6, [384, 250]],
  [13.0, 'insert'],
  [13.15, 'insert'],
  [13.5, 'accordionItem'],
  [13.75, [854, 210]],
  [14.6, [860, 216]],
  [15.4, [1180, 470], Ease.in],
  [16.2, [1180, 470]],
  [17.5, [640, 460], Ease.outQuint],
  [17.95, [640, 470]],
  [18.8, [1000, 640]],
  [21.9, [1000, 640]],
  [22.5, 'mediaTab'],
  [22.7, 'mediaTab'],
  [23.5, 'firstTile'],
  [24.7, 'firstTile'],
  [25.25, 'draftsTab'],
  [25.4, 'draftsTab'],
  [25.95, 'p1Start'],
  [26.0, 'p1Start'],
  [26.9, 'p1End', 'drag'],
  [27.15, 'p1Mid'],
  [27.9, 'shorter'],
  [28.1, 'shorter'],
  [29.4, [700, 330]],
  [30.6, 'accept'],
  [30.8, 'accept'],
  [31.6, 'evaluate'],
  [31.8, 'evaluate'],
  [33.2, [880, 470]],
  [36.1, 'inspector'],
  [36.3, 'inspector'],
  [37.0, [980, 50]],
  [37.7, 'saveWP'],
  [38.7, 'saveWP'],
  [39.4, [984, 54]],
  [42.6, [990, 56]],
  [43.2, 'inspector'],
  [43.4, 'inspector'],
  [44.4, 'hiking'],
  [44.6, 'hiking'],
  [45.1, 'trailNotes'],
  [45.3, 'trailNotes'],
  [45.85, 'tagField'],
  [46.0, 'tagField'],
  [47.55, 'tagField'],
  [48.1, 'choose'],
  [48.3, [900, 498]],
  [49.4, 'statusPopup'],
  [49.6, 'statusPopup'],
  [50.1, 'published'],
  [50.3, 'published'],
  [50.8, 'publish'],
  [51.0, 'publish'],
  [51.6, [900, 300]],
]

function pointOf(selector, ax = 0.5, ay = 0.5) {
  const win = $('#window').getBoundingClientRect()
  const r = document.querySelector(selector).getBoundingClientRect()
  const k = 1040 / win.width
  return [(r.left - win.left + r.width * ax) * k, (r.top - win.top + r.height * ay) * k]
}

function resolveTarget(target, t) {
  return typeof target === 'string' ? TARGETS[target](t) : target
}

function pointerAt(t) {
  if (t <= POINTER[0][0]) return resolveTarget(POINTER[0][1], t)
  for (let i = 1; i < POINTER.length; i++) {
    const [t1, target, ease] = POINTER[i]
    if (t <= t1) {
      const [t0, from] = POINTER[i - 1]
      const a = resolveTarget(from, t)
      const b = resolveTarget(target, t)
      const drag = ease === 'drag'
      const p = (drag ? Ease.inOut : ease || Ease.inOut)(span(t, t0, t1))
      const arc = drag ? 0 : Math.sin(Math.PI * p) * Math.min(40, Math.hypot(b[0] - a[0], b[1] - a[1]) * 0.08)
      return [lerp(a[0], b[0], p), lerp(a[1], b[1], p) - arc]
    }
  }
  return resolveTarget(POINTER[POINTER.length - 1][1], t)
}

// Setup

let openIconHome = null
let closeIconHome = null

function stagePoint(el) {
  let x = 0, y = 0, n = el
  while (n && n.id !== 'stage') {
    x += n.offsetLeft
    y += n.offsetTop
    n = n.offsetParent
  }
  return [x + el.offsetWidth / 2, y + el.offsetHeight / 2]
}

function setupCaptions() {
  $$('.caption h2').forEach(h2 => {
    h2.innerHTML = h2.innerHTML.split(/<br\s*\/?>/).map(line => `<span class="line">${line}</span>`).join('')
  })
}

function setupMedia() {
  const grid = $('#media-grid')
  Photos.library.forEach(src => {
    const img = document.createElement('img')
    img.src = src
    img.alt = ''
    grid.appendChild(img)
  })
  $('#drag-img').src = Photos.hero
  $('#media-preview img').src = Photos.hero
  $('#featured-img').src = Photos.hero
}

const ready = (async () => {
  setupCaptions()
  setupMedia()
  await document.fonts.ready
  openIconHome = stagePoint($('#open-icon'))
  closeIconHome = stagePoint($('#close-icon'))
  await EditorDriver.init($('#editor-frame'))
})()

// Render

function renderOpening(t) {
  const word = typed(t, 0.6, 1.4, 'Quill')
  $('#open-word').textContent = word
  const caretOn = t < 0.6 ? blink(t, -LEAD - 0.5) : t < 1.4 ? 1 : blink(t, 1.4)
  css($('#open-caret'), { opacity: String(t < 4.3 ? caretOn : 0) })

  const iconIn = Ease.back(span(t, 1.6, 2.25))
  const leave = span(t, 4.3, 5.0)
  const target = [600 + ANCHOR[0], ANCHOR[1]]
  const dx = (target[0] - openIconHome[0]) * Ease.inOut(leave)
  const dy = (target[1] - openIconHome[1]) * Ease.inOut(leave)
  const grow = lerp(1, 208 / 172, Ease.inOut(leave)) * lerp(1, 5.75, Ease.outQuint(span(t, 5.0, 6.5)))
  css($('#open-icon'), {
    opacity: String(Math.min(span(t, 1.6, 1.8), 1 - span(t, 5.0, 5.3))),
    transform: `translate(${dx}px, ${dy}px) scale(${(0.6 + 0.4 * iconIn) * grow})`,
  })

  const textOut = 1 - Ease.out(span(t, 4.3, 4.8))
  css($('#opening .wordmark'), { opacity: String(textOut) })
  const sub = Ease.out(span(t, 2.3, 2.9))
  css($('#open-sub'), { opacity: String(Math.min(sub, textOut)), transform: `translateY(${(1 - sub) * 14}px)` })
  css($('#opening'), { visibility: t < 5.4 ? 'visible' : 'hidden' })
}

function renderClosing(t) {
  const arrive = span(t, 55.0, 55.9)
  const target = [600 + ANCHOR[0], ANCHOR[1]]
  const p = Ease.inOut(arrive)
  const dx = (target[0] - closeIconHome[0]) * (1 - p)
  const dy = (target[1] - closeIconHome[1]) * (1 - p)
  const fromWindow = lerp(5.75, 1, Ease.in(span(t, 54.0, 55.0)))
  const settle = t < 55.0 ? 208 / 172 : lerp(208 / 172, 1, Ease.back(arrive))
  css($('#close-icon'), {
    opacity: String(span(t, 54.75, 55.0)),
    transform: `translate(${dx}px, ${dy}px) scale(${fromWindow * settle})`,
  })
  const text = Ease.out(span(t, 55.7, 56.4))
  css($('#closing .wordmark'), { opacity: String(text), transform: `translateY(${(1 - text) * 12}px)` })
  const sub = Ease.out(span(t, 56.0, 56.7))
  css($('#closing .subline'), { opacity: String(sub), transform: `translateY(${(1 - sub) * 12}px)` })
  css($('#close-caret'), { opacity: String(t < 56.4 ? 0 : blink(t, 56.4)) })
  css($('#closing'), { visibility: t >= 54.7 ? 'visible' : 'hidden' })
}

function renderCaptions(t) {
  $$('.caption').forEach(cap => {
    const [a, b] = BEATS[cap.dataset.beat]
    const out = 1 - Ease.out(span(t, b - 0.35, b))
    cap.querySelectorAll('.line').forEach((line, i) => {
      const p = Ease.outQuint(span(t, a + i * 0.12, a + i * 0.12 + 0.7))
      css(line, { opacity: String(Math.min(p, out)), transform: `translateY(${(1 - p) * 16}px)` })
    })
    const lines = cap.querySelectorAll('.line').length
    const s = Ease.outQuint(span(t, a + lines * 0.12 + 0.2, a + lines * 0.12 + 0.9))
    css(cap.querySelector('.subline'), { opacity: String(Math.min(s, out)), transform: `translateY(${(1 - s) * 12}px)` })
    css(cap, { visibility: t > a - 0.1 && t < b + 0.1 ? 'visible' : 'hidden', transform: 'translateY(-50%)' })
  })
}

function renderCamera(t) {
  const [fx, fy, s] = kf(t, CAMERA)
  const tx = ANCHOR[0] - fx * s
  const ty = ANCHOR[1] - fy * s
  css($('#camera'), { transform: `translate(${tx.toFixed(2)}px, ${ty.toFixed(2)}px) scale(${s.toFixed(4)})` })
  const visible = t >= 5.0 && t < 55.0
  css($('#window'), {
    opacity: String(Math.min(span(t, 5.0, 5.3), 1 - span(t, 54.75, 55.0))),
    visibility: visible ? 'visible' : 'hidden',
  })
}

function renderTitle(t) {
  const text = typed(t, 6.9, 7.9, COPY.title)
  $('#post-title-text').textContent = text
  css($('#title-placeholder'), { display: text ? 'none' : 'inline' })
  const active = t >= 6.6 && t < 8.1
  css($('#title-caret'), { opacity: String(active ? blink(t, typingSince(t) || 6.6) : 0) })
  $('#draft-row-title').textContent = t >= 8.0 ? COPY.title : 'Untitled'

  const saved = t >= 39.0
  const published = t >= 51.0
  css($('#status-icon .st-local'), { opacity: String(1 - span(t, 39.0, 39.25)) })
  css($('#status-icon .st-draft'), { opacity: String(Math.min(span(t, 39.0, 39.25), 1 - span(t, 51.0, 51.25))) })
  css($('#status-icon .st-publish'), { opacity: String(span(t, 51.0, 51.25)) })
  const pop = saved ? 1 + 0.18 * Math.sin(Math.PI * span(t, published ? 51.0 : 39.0, published ? 51.4 : 39.4)) : 1
  css($('#status-icon'), { transform: `scale(${pop})` })
}

function renderSidebar(t) {
  const tab = t >= 22.6 && t < 25.3 ? 'media' : t >= 39.0 ? 'posts' : 'drafts'
  $$('.tab').forEach(el => el.classList.toggle('selected', el.dataset.tab === tab))
  $('#search-label').textContent = { media: 'Search Media', posts: 'Search Posts', drafts: 'Search Drafts' }[tab]
  $('#sidebar').classList.toggle('has-filter', tab === 'posts')
  $$('.side-list').forEach(list => css(list, { display: list.dataset.list === tab ? 'block' : 'none' }))
  const mv = Math.min(span(t, 22.6, 22.85), 1 - span(t, 25.3, 25.5))
  css($('#media-view'), { opacity: String(mv), visibility: mv > 0 ? 'visible' : 'hidden' })
  $('#media-grid img').classList.toggle('selected', t >= 23.6)
  const preview = Ease.out(span(t, 24.12, 24.37))
  css($('#media-preview'), { opacity: String(preview) })
  css($('#btn-back'), { opacity: String(preview) })

  const arrive = Ease.outQuint(span(t, 39.15, 39.7))
  css($('#post-row'), { maxHeight: `${arrive * 60}px`, opacity: String(arrive), paddingTop: `${arrive * 8}px`, paddingBottom: `${arrive * 8}px` })
  const published = t >= 51.0
  $('#post-row-meta').textContent = published ? 'Oct 9, 2026 · Published' : 'Oct 9, 2026 · Draft'
  css($('#post-row-dot'), { background: published ? '#3e9e63' : '#d99a2b' })
}

function renderToolbar(t) {
  const remote = span(t, 39.0, 39.3)
  const local = (1 - remote) * (1 - Math.min(span(t, 22.6, 22.85), 1 - span(t, 25.3, 25.5)))
  css($('#actions-local'), { opacity: String(local), visibility: local > 0 ? 'visible' : 'hidden' })
  css($('#actions-remote'), { opacity: String(remote), visibility: remote > 0 ? 'visible' : 'hidden' })
  $('#window').classList.toggle('is-publish', t >= 50.2)
  $('#window').classList.toggle('is-published', t >= 51.0)
  css($('#btn-revert'), { display: t >= 44.5 && t < 51.0 ? 'flex' : 'none' })
  css($('#btn-share'), { display: t >= 51.0 ? 'flex' : 'none' })
  css($('#tooltip'), { opacity: String(window01(t, 38.05, 38.65, 0.15)) })
  $('#btn-save-wp').classList.toggle('pressed', t >= 38.55 && t < 38.75)
  $('#btn-publish').classList.toggle('pressed', t >= 50.9 && t < 51.05)
  $('#btn-inspector').classList.toggle('pressed', (t >= 36.15 && t < 36.35) || (t >= 43.25 && t < 43.45))
}

function renderInspector(t) {
  const evalOpen = Ease.inOut(span(t, 31.8, 32.3)) * (1 - Ease.inOut(span(t, 36.25, 36.65)))
  const settingsOpen = Ease.inOut(span(t, 43.35, 43.85))
  css($('#inspector'), { width: `${Math.round(280 * Math.max(evalOpen, settingsOpen))}px` })
  css($('#eval-panel'), { opacity: String(evalOpen > 0 && t < 40 ? 1 : 0) })
  css($('#eval-loading'), { display: t < 33.0 ? 'flex' : 'none' })
  css($('#eval-body'), { opacity: String(Ease.out(span(t, 33.0, 33.4))) })
  css($('#eval-footer'), { opacity: t < 33.0 ? '0.45' : '1' })
  css($('#settings-panel'), { opacity: String(settingsOpen > 0 ? 1 : 0) })

  $('.check[data-cat="hiking"]').classList.toggle('on', t >= 44.5)
  $('.check[data-cat="trail-notes"]').classList.toggle('on', t >= 45.2)

  const tags = []
  if (t >= 46.6) tags.push('alpine')
  if (t >= 47.45) tags.push('sunrise')
  const tagBox = $('#tags')
  if (tagBox.dataset.value !== tags.join(',')) {
    tagBox.dataset.value = tags.join(',')
    tagBox.innerHTML = tags.map(tag => `<span class="token">${tag}</span>`).join('')
  }
  let tagText = ''
  if (t >= 46.0 && t < 46.6) tagText = typed(t, 46.0, 46.5, 'alpine')
  if (t >= 46.8 && t < 47.45) tagText = typed(t, 46.8, 47.3, 'sunrise')
  $('#tag-text').textContent = tagText
  const rows = SITE_TAGS.filter(tag => !tags.includes(tag) && tag.includes(tagText)).map(tag => `<div class="tag-row">${tag}</div>`)
  if (tagText && !SITE_TAGS.includes(tagText)) rows.push(`<div class="tag-row add"><svg viewBox="0 0 12 12"><path d="M6 1.5v9M1.5 6h9"/></svg>Add "${tagText}"</div>`)
  const tagList = $('#tag-list')
  if (tagList.dataset.value !== rows.join('')) {
    tagList.dataset.value = rows.join('')
    tagList.innerHTML = rows.join('')
  }
  const tagFocus = t >= 45.9 && t < 48.0
  css($('#tag-placeholder'), { display: tagText ? 'none' : 'inline' })
  css($('#tag-caret'), { display: tagFocus ? 'inline-block' : 'none', opacity: String(blink(t, typingSince(t) || 45.9)) })

  const featured = t >= 48.4
  css($('#featured-empty'), { display: featured ? 'none' : 'flex' })
  css($('#featured-set'), { display: featured ? 'block' : 'none', opacity: String(Ease.out(span(t, 48.4, 48.8))) })
  $('#btn-choose').classList.toggle('pressed', t >= 48.15 && t < 48.35)
  const scroll = Ease.inOut(span(t, 47.55, 48.0)) - Ease.inOut(span(t, 48.95, 49.35))
  css($('#settings-scroll'), { transform: `translateY(${-Math.round(scroll * SETTINGS_SCROLL)}px)` })

  $('#status-value').textContent = t >= 50.2 ? 'Published' : 'Draft'
}

function renderMenus(t) {
  const statusOpen = t >= 49.5 && t < 50.25
  const popup = pointOf('#status-popup', 0, 0)
  css($('#status-menu'), { opacity: statusOpen ? '1' : '0', transform: `translate(${popup[0] - 6}px, ${popup[1] - 6}px)` })
  $('#status-menu [data-status="publish"]').classList.toggle('hover', t >= 49.95 && t < 50.25)

  const ctxOpen = t >= 27.2 && t < 28.05
  const at = TARGETS.p1Mid()
  css($('#context-menu'), { opacity: ctxOpen ? '1' : '0', transform: `translate(${at[0] + 2}px, ${at[1] + 2}px)` })
  $('#menu-shorter').classList.toggle('hover', t >= 27.75 && t < 28.05)
}

function renderHUD(t) {
  const pill = window01(t, 18.0, 19.15, 0.25)
  css($('#upload-pill'), { opacity: String(pill), transform: `translate(-50%, ${(1 - pill) * 12}px)` })

  const toast = TOASTS.find(([a, b]) => t >= a && t < b)
  if (toast) $('#toast-text').textContent = toast[2]
  const tp = toast ? window01(t, toast[0], toast[1], 0.25) : 0
  css($('#toast'), { opacity: String(tp), transform: `translate(-50%, ${(1 - tp) * 12}px) scale(${0.96 + 0.04 * tp})` })

  const bar = window01(t, 29.7, 30.8, 0.2)
  css($('#ai-bar'), { opacity: String(bar), transform: `translate(-50%, ${(1 - bar) * 10}px)` })
  $('#ai-accept').classList.toggle('pressed', t >= 30.65 && t < 30.8)

  const tick = Math.floor(t * 12)
  $$('.spinner').forEach(sp => {
    sp.querySelectorAll('i').forEach((el, i) => {
      css(el, { transform: `rotate(${i * 45}deg)`, opacity: String(0.25 + 0.75 * (((i - tick) % 8 + 8) % 8 === 0 ? 1 : ((i - tick) % 8 + 8) % 8 > 5 ? 0.5 : 0)) })
    })
  })
}

function renderPointer(t) {
  const [x, y] = pointerAt(t)
  const down = CLICKS.some(c => t >= c - 0.06 && t < c + 0.08)
  const visible = Math.min(span(t, 10.5, 10.7), 1 - span(t, 51.6, 51.9))
  css($('#pointer'), { opacity: String(visible), transform: `translate(${(x - 5).toFixed(1)}px, ${(y - 3).toFixed(1)}px) scale(${down ? 0.86 : 1})` })

  const dragging = t >= 16.2 && t < 17.95
  const ghost = dragging ? 0.95 : window01(t, 16.2, 18.15, 0.2) * (1 - span(t, 17.95, 18.15))
  css($('#drag-ghost'), { opacity: String(ghost), transform: `translate(${x - 60}px, ${y - 40}px) scale(${1 - 0.3 * span(t, 17.95, 18.15)})` })
}

function renderEditor(t) {
  const state = editorState(t)
  EditorDriver.setDoc({ type: 'doc', content: state.content })
  const caretPos = state.caret ? EditorDriver.posIn(...state.caret) : null
  EditorDriver.select(caretPos ?? EditorDriver.posIn(0, 0))

  const scroll = kf(t, [[19.1, 0], [19.8, 1], [22.6, 1], [22.7, 0, Ease.linear]])
  EditorDriver.setScroll(scroll * (EditorDriver.blockTop(3) - 40))

  EditorDriver.showCaret(caretPos, state.caret && blink(t, typingSince(t)))
  const selection = state.selection && [EditorDriver.posIn(...state.selection[0]), EditorDriver.posIn(...state.selection[1])]
  if (t >= 26.0 && t < 26.9) selection[1] = clamp(EditorDriver.posAtPoint(pointerAt(t)) ?? selection[0], selection[0], EditorDriver.posIn(0, 'end'))
  EditorDriver.showSelection(selection)

  const pending = t >= 28.05 && t < 29.6
  EditorDriver.setPending(pending ? 0 : null, 0.3 + 0.55 * (0.5 - 0.5 * Math.cos((t - 28.05) * Math.PI * 1.6)))
  EditorDriver.setHeadingMenu(t >= 11.4 && t < 11.9, t >= 11.6 ? 2 : 0)
  EditorDriver.setInsertMenu(t >= 13.15 && t < 13.7, t >= 13.4 ? 'accordion' : null)
  EditorDriver.setDropOverlay(t >= 16.95 && t < 17.95)
}

function render(t) {
  renderOpening(t)
  renderCamera(t)
  renderCaptions(t)
  renderTitle(t)
  renderSidebar(t)
  renderToolbar(t)
  renderInspector(t)
  renderEditor(t)
  renderMenus(t)
  renderHUD(t)
  renderPointer(t)
  renderClosing(t)
}

function audioCues() {
  const cues = []
  TOASTS.forEach(([t, , text]) => cues.push({ t, kind: text.endsWith('Published') ? 'chime' : 'toast' }))
  cues.push({ t: 1.6, kind: 'logo' }, { t: 5.0, kind: 'open' }, { t: 17.95, kind: 'drop' }, { t: 54.0, kind: 'close' }, { t: 55.0, kind: 'logo' })
  return cues.map(c => ({ ...c, t: c.t + LEAD })).sort((x, y) => x.t - y.t)
}

window.audioCues = audioCues
window.seek = async t => {
  await ready
  const g = Math.min(Math.max(t, 0), DURATION)
  render(g - LEAD)
  css($('#fade'), { opacity: String(Math.max(1 - span(g, 0, 0.6), span(g, DURATION - 2, DURATION))) })
  await EditorDriver.settled()
}
window.DURATION = DURATION
