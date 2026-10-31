// The type-marker grip beside each top-level block: docs/superpowers/specs/2026-10-31-drag-to-reorder-blocks-design.md.

function blockGlyphSVG(id) {
  const shapes = {
    image: '<rect x="1" y="2.5" width="12" height="9" rx="1.5"/><path d="M1.5 10.5l3.5-3.5 2.5 2.5 2-2 3 3"/>',
    gallery: '<rect x="4" y="1" width="9" height="8" rx="1.3"/><path d="M4 4H2.3A1.3 1.3 0 0 0 1 5.3v6.4A1.3 1.3 0 0 0 2.3 13h6.4a1.3 1.3 0 0 0 1.3-1.3V9"/>',
    embed: '<rect x="1" y="2.5" width="12" height="9" rx="1.5"/><path d="M5.8 5.2v3.6L8.8 7z" fill="currentColor"/>',
    table: '<rect x="1" y="1.5" width="12" height="11" rx="1.3"/><path d="M5 1.5v11M9 1.5v11M1 5.2h12M1 8.8h12"/>',
    columns: '<rect x="1" y="1.5" width="5.2" height="11" rx="1.2"/><rect x="7.8" y="1.5" width="5.2" height="11" rx="1.2"/>',
    group: '<path d="M3.5 1.5h-2v11h2M10.5 1.5h2v11h-2"/><rect x="4.5" y="4.5" width="5" height="5" rx="0.8"/>',
    buttons: '<rect x="1" y="4" width="12" height="6" rx="2"/><path d="M4.5 7h5"/>',
    chevron: '<path d="M5 3.5L8.5 7 5 10.5"/>',
    accordion: '<path d="M1.5 2.5l1.5 1.5-1.5 1.5M5.5 4h7M1.5 8.5l1.5 1.5-1.5 1.5M5.5 10h7"/>',
    tabs: '<rect x="1" y="4.5" width="12" height="8" rx="1.2"/><path d="M1.6 4.5V2.8a1 1 0 0 1 1-1h3a1 1 0 0 1 1 1v1.7"/>',
    synced: '<path d="M2.6 6a4.5 4.5 0 0 1 8-2.4M11.4 8a4.5 4.5 0 0 1-8 2.4"/><path d="M10.9 1.3v2.6H8.3M3.1 12.7v-2.6h2.6"/>',
    html: '<path d="M5 3.5L1.8 7 5 10.5M9 3.5L12.2 7 9 10.5"/>',
    quote: '<path d="M2 2v10M5.5 4.5h6.5M5.5 7h6.5M5.5 9.5h4"/>',
  }
  return '<svg width="13" height="13" viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.3" ' +
    'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (shapes[id] || shapes.html) + '</svg>'
}

function _gripLineHeight(el) {
  const style = getComputedStyle(el)
  const lh = parseFloat(style.lineHeight)
  if (Number.isFinite(lh)) return lh
  const size = parseFloat(style.fontSize)
  return Number.isFinite(size) ? size * 1.2 : 22
}

function nearestGap(ys, y) {
  let best = 0
  for (let i = 1; i < ys.length; i++) if (Math.abs(ys[i] - y) < Math.abs(ys[best] - y)) best = i
  return best
}

function gapYs(view) {
  const doc = view.state.doc
  const count = movableCount(doc)
  const rects = []
  for (let i = 0; i < count; i++) {
    const dom = view.nodeDOM(topLevelPos(doc, i))
    rects.push(dom && dom.nodeType === 1 ? dom.getBoundingClientRect() : null)
  }
  const ys = []
  for (let i = 0; i <= count; i++) {
    const above = rects[i - 1]
    const below = rects[i]
    if (above && below) ys.push((above.bottom + below.top) / 2)
    else if (below) ys.push(below.top - 4)
    else if (above) ys.push(above.bottom + 4)
    else ys.push(ys.length ? ys[ys.length - 1] : 0)
  }
  return ys
}

function _gripMarkClass(value) {
  const named = { '”': 'pullquote', '¶': 'pilcrow', '•': 'bullet' }[value]
  return 'block-grip-mark-' + (named || (/^h\d$|^pre$/.test(value) ? 'caps' : 'plain'))
}

function _gripMarkerElement(marker) {
  const el = document.createElement('span')
  el.className = 'block-drag-card-marker'
  if (marker.kind === 'glyph') {
    el.innerHTML = blockGlyphSVG(marker.value)
    return el
  }
  const text = document.createElement('span')
  text.className = _gripMarkClass(marker.value)
  text.textContent = marker.value
  el.append(text)
  return el
}

function _gripDragCard(doc, range) {
  let card = document.getElementById('block-drag-card')
  if (!card) {
    card = document.createElement('div')
    card.id = 'block-drag-card'
    card.setAttribute('aria-hidden', 'true')
    document.body.appendChild(card)
  }
  const node = doc.child(range.from)
  const marker = blockMarker(node)
  const text = document.createElement('span')
  text.className = 'block-drag-card-text'
  text.textContent = node.textContent.trim().slice(0, 140) || marker.label
  const parts = [_gripMarkerElement(marker), text]
  if (range.to - range.from > 1) {
    const more = document.createElement('span')
    more.className = 'block-drag-card-more'
    more.textContent = `+ ${range.to - range.from - 1} more`
    parts.push(more)
  }
  card.replaceChildren(...parts)
  return card
}

// Leaves the pasteboard empty: docs/editor-gotchas.md, "A grip drag must leave the pasteboard empty".
function gripDragStart(view, event, range) {
  const doc = view.state.doc
  const transfer = event.dataTransfer
  transfer.clearData()
  transfer.effectAllowed = 'move'
  view.dragging = { slice: doc.slice(topLevelPos(doc, range.from), topLevelPos(doc, range.to)), move: true }
  transfer.setDragImage(_gripDragCard(doc, range), 12, 12)
  gripDragStart.active = { from: range.from, to: range.to }
}

function activeGripDrag() {
  return gripDragStart.active || null
}

function endGripDrag(view) {
  gripDragStart.active = null
  if (view) view.dragging = null
}

function installBlockGrip(editor, hooks) {
  const view = editor.view
  const wrap = document.getElementById('editor-wrap')
  const layer = document.createElement('div')
  layer.id = 'block-grip-layer'
  layer.setAttribute('aria-hidden', 'true')
  const grip = document.createElement('div')
  grip.id = 'block-grip'
  grip.setAttribute('aria-hidden', 'true')
  grip.draggable = true
  const tint = document.createElement('div')
  tint.id = 'block-grip-tint'
  const dropLine = document.createElement('div')
  dropLine.id = 'block-drop-line'
  layer.append(tint, dropLine, grip)
  wrap.insertBefore(layer, wrap.firstChild)
  const tip = document.createElement('div')
  tip.id = 'block-grip-tooltip'
  document.body.appendChild(tip)

  const GRIP_W = 26
  const GRIP_H = 22
  let index = -1
  let onGrip = false
  let sectionKey = false
  let pressRange = null
  let tipTimer = null
  let scrollSpeed = 0
  let scrollFrame = null
  let lastDragY = 0

  const doc = () => editor.state.doc
  const nodeDOMAt = i => {
    const dom = view.nodeDOM(topLevelPos(doc(), i))
    return dom && dom.nodeType === 1 ? dom : null
  }
  const isHeading = () => index >= 0 && doc().child(index).type.name === 'heading'
  const sectionShown = () => sectionKey && onGrip && isHeading()

  function hideTip() {
    clearTimeout(tipTimer)
    tip.classList.remove('visible')
  }

  function hide() {
    index = -1
    onGrip = false
    grip.classList.remove('visible', 'held', 'section')
    tint.style.display = 'none'
    hideTip()
  }

  function render() {
    const marker = blockMarker(doc().child(index))
    grip.dataset.label = marker.label
    grip.className = 'visible' + (onGrip ? ' held' : '') + (sectionShown() ? ' section' : '')
    if (marker.kind === 'glyph') {
      grip.innerHTML = blockGlyphSVG(marker.value)
      return
    }
    const text = document.createElement('span')
    text.className = 'block-grip-mark ' + _gripMarkClass(marker.value)
    text.textContent = marker.value
    grip.replaceChildren(text)
  }

  function place() {
    const dom = nodeDOMAt(index)
    if (!dom) return hide()
    const layerRect = layer.getBoundingClientRect()
    const colRect = view.dom.getBoundingClientRect()
    const colLeft = colRect.left + (parseFloat(getComputedStyle(view.dom).paddingLeft) || 0)
    const node = doc().child(index)
    const marker = blockMarker(node)
    const rect = dom.getBoundingClientRect()
    let top = rect.top
    if (node.type.name === 'horizontalRule') {
      top = rect.top + rect.height / 2 - GRIP_H / 2
    } else if (marker.kind === 'text') {
      const textPos = firstTextblockPos(doc(), topLevelPos(doc(), index))
      const line = (textPos !== null && view.nodeDOM(textPos - 1)) || dom
      const lineEl = line.nodeType === 1 ? line : dom
      const lineStyle = getComputedStyle(lineEl)
      const inset = (parseFloat(lineStyle.paddingTop) || 0) + (parseFloat(lineStyle.borderTopWidth) || 0)
      top = lineEl.getBoundingClientRect().top + inset + (_gripLineHeight(lineEl) - GRIP_H) / 2
    }
    grip.style.left = (colLeft - layerRect.left - GRIP_W - 6) + 'px'
    grip.style.top = (top - layerRect.top) + 'px'

    if (!sectionShown()) {
      tint.style.display = 'none'
      return
    }
    const last = nodeDOMAt(sectionEnd(doc(), index) - 1) || dom
    Object.assign(tint.style, {
      display: 'block',
      left: (colRect.left - layerRect.left - 8) + 'px',
      width: (colRect.width + 16) + 'px',
      top: (rect.top - layerRect.top - 6) + 'px',
      height: (last.getBoundingClientRect().bottom - rect.top + 12) + 'px',
    })
  }

  function showFor(i) {
    const d = doc()
    if (!hooks.allowed() || i < 0 || i >= movableCount(d) || i === generatedTrailingIndex(d, hooks.trailingAfter)) return hide()
    if (i !== index) onGrip = false
    index = i
    render()
    place()
  }

  // Halfway into the gap, or at the next block's top when a float makes the two overlap.
  function rowBoundary(above, below) {
    const a = above.getBoundingClientRect()
    const b = below.getBoundingClientRect()
    return Math.min((a.bottom + b.top) / 2, b.top)
  }

  // A block's row reaches into the gaps on each side, so the margin counts as the block.
  function rowOf(i) {
    const dom = nodeDOMAt(i)
    if (!dom) return null
    const rect = dom.getBoundingClientRect()
    const prev = i > 0 ? nodeDOMAt(i - 1) : null
    const next = i + 1 < movableCount(doc()) ? nodeDOMAt(i + 1) : null
    return {
      top: prev ? rowBoundary(prev, dom) : rect.top - 16,
      bottom: next ? rowBoundary(dom, next) : rect.bottom + 16,
    }
  }

  // The block under the pointer wins, so a floated image and the text wrapping beside it are both reachable.
  function indexAtPoint(x, y) {
    let el = document.elementFromPoint ? document.elementFromPoint(x, y) : null
    while (el && el.parentNode !== view.dom) el = el.parentNode
    if (el) {
      try {
        const i = topLevelIndexAt(doc(), view.posAtDOM(el, 0))
        if (i >= 0) return i
      } catch (e) {}
    }
    return indexAtY(y)
  }

  function indexAtY(y) {
    let lo = 0
    let hi = movableCount(doc()) - 1
    while (lo <= hi) {
      const mid = (lo + hi) >> 1
      const row = rowOf(mid)
      if (!row) return -1
      if (y < row.top) hi = mid - 1
      else if (y >= row.bottom) lo = mid + 1
      else return mid
    }
    return -1
  }

  // Read from the grip's box, not mouseenter/mouseleave, which WebKit skips when the grip moves under a still pointer.
  function overGrip(x, y) {
    if (!grip.classList.contains('visible')) return false
    const rect = grip.getBoundingClientRect()
    return x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom
  }

  function track(x, y) {
    if (overGrip(x, y)) {
      if (!onGrip) { onGrip = true; render(); place() }
      return
    }
    if (onGrip) {
      onGrip = false
      hideTip()
    }
    const i = indexAtPoint(x, y)
    if (i !== index) showFor(i)
  }

  function positionTip() {
    const rect = grip.getBoundingClientRect()
    const tipRect = tip.getBoundingClientRect()
    const margin = 8
    const half = tipRect.width / 2
    const idealLeft = rect.left + rect.width / 2
    const left = Math.min(Math.max(idealLeft, half + margin), window.innerWidth - half - margin)
    tip.style.setProperty('--arrow-offset', `${idealLeft - (left - half)}px`)
    tip.style.left = `${left}px`
    tip.style.top = `${rect.bottom + margin}px`
    tip.classList.add('below')
  }

  function showTip() {
    if (index < 0) return
    tip.textContent = grip.dataset.label + (isHeading() ? ' · Drag to move, ⌘ for the section' : ' · Drag to move')
    tip.style.left = '-9999px'
    tip.style.top = '-9999px'
    requestAnimationFrame(() => {
      if (!onGrip) return
      positionTip()
      tip.classList.add('visible')
    })
  }

  function click() {
    if (index < 0) return
    const start = topLevelPos(doc(), index)
    const textual = ['paragraph', 'heading', 'bulletList', 'orderedList'].includes(doc().child(index).type.name)
    const chain = editor.chain().focus()
    if (textual) chain.setTextSelection(firstTextblockPos(doc(), start) ?? start)
    else chain.setNodeSelection(start)
    chain.run()
  }

  function dragRange() {
    return sectionShown() ? { from: index, to: sectionEnd(doc(), index) } : { from: index, to: index + 1 }
  }

  // The range is fixed at the press; leaving the grip or letting go of ⌘ before dragstart does not shrink it.
  function rangeForDrag(metaKey) {
    const range = pressRange || dragRange()
    pressRange = null
    if (!metaKey || range.to - range.from > 1 || doc().child(range.from).type.name !== 'heading') return range
    return { from: range.from, to: sectionEnd(doc(), range.from) }
  }

  function drawDropLine(clientY) {
    const range = activeGripDrag()
    const ys = gapYs(view)
    const gap = nearestGap(ys, clientY)
    if (!range || isNoOpMove(range.from, range.to, gap)) {
      dropLine.style.display = 'none'
      return
    }
    const layerRect = layer.getBoundingClientRect()
    const colRect = view.dom.getBoundingClientRect()
    const padLeft = parseFloat(getComputedStyle(view.dom).paddingLeft) || 0
    Object.assign(dropLine.style, {
      display: 'block',
      left: (colRect.left + padLeft - layerRect.left) + 'px',
      width: (colRect.width - padLeft) + 'px',
      top: (ys[gap] - layerRect.top - 1) + 'px',
    })
  }

  // WebKit does not autoscroll #editor-wrap during a drag: docs/platform-workarounds.md.
  function autoscroll(clientY) {
    const rect = wrap.getBoundingClientRect()
    const band = 48
    const into = clientY < rect.top + band ? clientY - (rect.top + band)
      : clientY > rect.bottom - band ? clientY - (rect.bottom - band) : 0
    scrollSpeed = Math.max(-18, Math.min(18, Math.round(18 * into / band)))
    if (scrollSpeed && scrollFrame === null) scrollFrame = requestAnimationFrame(scrollStep)
  }

  function scrollStep() {
    scrollFrame = null
    if (!scrollSpeed || !activeGripDrag()) return
    wrap.scrollTop += scrollSpeed
    drawDropLine(lastDragY)
    scrollFrame = requestAnimationFrame(scrollStep)
  }

  function stopAutoscroll() {
    scrollSpeed = 0
    if (scrollFrame !== null) cancelAnimationFrame(scrollFrame)
    scrollFrame = null
  }

  function endDragVisuals() {
    stopAutoscroll()
    document.body.classList.remove('block-dragging')
    dropLine.style.display = 'none'
  }

  // ⌘, not ⇧: WebKit never starts a drag from a ⇧-press (EventHandler::handleMousePressEvent).
  function setSectionKey(down) {
    if (sectionKey === down) return
    sectionKey = down
    if (index >= 0) { render(); place() }
  }

  // Key events only reach the web view while it has focus; mouse events always carry ⌘.
  wrap.addEventListener('mousemove', e => {
    if (e.buttons) return
    setSectionKey(e.metaKey)
    track(e.clientX, e.clientY)
  })
  wrap.addEventListener('mouseleave', hide)
  wrap.addEventListener('scroll', () => { if (!activeGripDrag()) hide() })
  grip.addEventListener('mouseenter', () => {
    if (index < 0) return
    onGrip = true
    render()
    place()
    clearTimeout(tipTimer)
    tipTimer = setTimeout(showTip, 600)
  })
  grip.addEventListener('mouseleave', () => {
    onGrip = false
    hideTip()
    if (index >= 0) { render(); place() }
  })
  grip.addEventListener('mousedown', e => {
    e.stopPropagation()
    onGrip = true
    setSectionKey(e.metaKey)
    hideTip()
    pressRange = index >= 0 ? dragRange() : null
  })
  grip.addEventListener('click', e => { e.stopPropagation(); click() })
  grip.addEventListener('dragstart', e => {
    if (index < 0 || !hooks.allowed()) {
      e.preventDefault()
      return
    }
    hideTip()
    document.body.classList.add('block-dragging')
    hooks.onDragStart(e, rangeForDrag(!!e.metaKey))
  })
  grip.addEventListener('dragend', () => {
    endDragVisuals()
    hooks.onDragEnd()
  })
  wrap.addEventListener('dragover', e => {
    if (!activeGripDrag()) return
    e.preventDefault()
    if (e.dataTransfer) e.dataTransfer.dropEffect = 'move'
    lastDragY = e.clientY
    drawDropLine(e.clientY)
    autoscroll(e.clientY)
  })
  wrap.addEventListener('dragleave', e => {
    if (!activeGripDrag() || wrap.contains(e.relatedTarget)) return
    dropLine.style.display = 'none'
    stopAutoscroll()
  })
  wrap.addEventListener('drop', e => {
    if (!activeGripDrag()) return
    e.preventDefault()
    hooks.onDrop(e.clientY)
    endDragVisuals()
  })
  for (const type of ['mousedown', 'dragstart']) {
    document.addEventListener(type, e => {
      if (!activeGripDrag() || e.target === grip) return
      endDragVisuals()
      hooks.onDragEnd()
    }, true)
  }
  document.addEventListener('keydown', e => {
    if (e.key === 'Meta') return setSectionKey(true)
    if (['Shift', 'Alt', 'Control', 'CapsLock'].includes(e.key)) return
    hide()
  }, true)
  document.addEventListener('keyup', e => { if (e.key === 'Meta') setSectionKey(false) }, true)
  window.addEventListener('blur', () => setSectionKey(false))
  editor.on('transaction', ({ transaction }) => { if (transaction.docChanged) hide() })

  return { el: grip, hide, showFor, click, setSectionKey }
}
