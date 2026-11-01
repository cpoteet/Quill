// Change bars beside blocks that differ from the saved version: docs/superpowers/specs/2026-10-31-change-bars-design.md.

function _changeBarEntries(doc, trailingAfter, keyOf) {
  const skip = generatedTrailingIndex(doc, trailingAfter)
  const entries = []
  doc.forEach((node, _offset, index) => { if (index !== skip) entries.push({ index, key: keyOf(node) }) })
  return entries
}

function changedBlocks(baseline, current, trailingAfter, keyOf) {
  const before = _changeBarEntries(baseline, trailingAfter, keyOf)
  const after = _changeBarEntries(current, trailingAfter, keyOf)
  const rows = before.length + 1
  const cols = after.length + 1
  const lengths = new Uint32Array(rows * cols)
  for (let i = before.length - 1; i >= 0; i--) {
    for (let j = after.length - 1; j >= 0; j--) {
      lengths[i * cols + j] = before[i].key === after[j].key
        ? lengths[(i + 1) * cols + j + 1] + 1
        : Math.max(lengths[(i + 1) * cols + j], lengths[i * cols + j + 1])
    }
  }

  const changed = []
  const removedGaps = []
  let i = 0
  let j = 0
  let removedHere = false
  let addedHere = false
  const closeRun = () => {
    if (removedHere && !addedHere) removedGaps.push(j > 0 ? after[j - 1].index + 1 : 0)
    removedHere = addedHere = false
  }
  while (i < before.length || j < after.length) {
    if (i < before.length && j < after.length && before[i].key === after[j].key) {
      closeRun()
      i++
      j++
    } else if (j < after.length && (i === before.length || lengths[i * cols + j + 1] >= lengths[(i + 1) * cols + j])) {
      changed.push(after[j].index)
      addedHere = true
      j++
    } else {
      removedHere = true
      i++
    }
  }
  closeRun()
  return { changed, removedGaps }
}

function installChangeBars(editor, hooks) {
  const view = editor.view
  const wrap = document.getElementById('editor-wrap')
  const layer = document.createElement('div')
  layer.id = 'change-bar-layer'
  layer.setAttribute('aria-hidden', 'true')
  wrap.insertBefore(layer, wrap.firstChild)
  const tip = document.createElement('div')
  tip.id = 'change-bar-tooltip'
  document.body.appendChild(tip)

  const BAR_GAP = 8
  const DOT = 6
  const HOVER_HALF = 6
  let stale = true
  let frame = null
  let tipMark = null
  let tipTimer = null

  function hideTip() {
    clearTimeout(tipTimer)
    tipMark = null
    tip.classList.remove('visible')
  }

  function redraw() {
    cancelAnimationFrame(frame)
    frame = null
    if (layer.classList.contains('faded')) {
      stale = true
      return
    }
    stale = false
    hideTip()
    const { changed, removedGaps } = hooks.marks()
    if (!changed.length && !removedGaps.length) return layer.replaceChildren()
    const doc = view.state.doc
    const layerRect = layer.getBoundingClientRect()
    const colRect = view.dom.getBoundingClientRect()
    const x = colRect.right - (parseFloat(getComputedStyle(view.dom).paddingRight) || 0) - layerRect.left + BAR_GAP
    const marks = []
    for (const index of changed) {
      const dom = view.nodeDOM(topLevelPos(doc, index))
      if (!dom || dom.nodeType !== 1) continue
      const rect = dom.getBoundingClientRect()
      const bar = document.createElement('div')
      bar.className = 'change-bar'
      Object.assign(bar.style, { left: x + 'px', top: (rect.top - layerRect.top) + 'px', height: rect.height + 'px' })
      marks.push(bar)
    }
    const ys = removedGaps.length ? gapYs(view) : []
    for (const gap of removedGaps) {
      const dot = document.createElement('div')
      dot.className = 'change-bar-removed'
      const y = ys[Math.min(gap, ys.length - 1)]
      Object.assign(dot.style, { left: (x + 1 - DOT / 2) + 'px', top: (y - layerRect.top - DOT / 2) + 'px' })
      marks.push(dot)
    }
    layer.replaceChildren(...marks)
  }

  function schedule() {
    if (frame === null) frame = requestAnimationFrame(redraw)
  }

  function hide() {
    hideTip()
    layer.classList.add('faded')
  }

  function show() {
    if (!layer.classList.contains('faded')) return
    layer.classList.remove('faded')
    if (stale) redraw()
  }

  function markAt(x, y) {
    for (const mark of layer.children) {
      const rect = mark.getBoundingClientRect()
      const cx = rect.left + rect.width / 2
      const cy = rect.top + rect.height / 2
      if (Math.abs(x - cx) > HOVER_HALF) continue
      if (y >= Math.min(rect.top, cy - HOVER_HALF) && y <= Math.max(rect.bottom, cy + HOVER_HALF)) return mark
    }
    return null
  }

  function showTip(mark, y) {
    tip.textContent = mark.classList.contains('change-bar-removed') ? 'Removed since the last save' : 'Changed since the last save'
    tip.style.left = '-9999px'
    tip.style.top = '-9999px'
    requestAnimationFrame(() => {
      if (tipMark !== mark) return
      const rect = mark.getBoundingClientRect()
      const half = tip.getBoundingClientRect().width / 2
      const margin = 8
      const idealLeft = rect.left + rect.width / 2
      const left = Math.min(Math.max(idealLeft, half + margin), window.innerWidth - half - margin)
      tip.style.setProperty('--arrow-offset', `${idealLeft - (left - half)}px`)
      tip.style.left = `${left}px`
      tip.style.top = `${(mark.classList.contains('change-bar-removed') ? rect.bottom : y) + margin}px`
      tip.classList.add('below', 'visible')
    })
  }

  // The marks never take the pointer, so the gutter press handler still sees #editor-wrap.
  wrap.addEventListener('mousemove', e => {
    if (e.buttons) return
    show()
    const mark = markAt(e.clientX, e.clientY)
    if (mark === tipMark) return
    hideTip()
    if (!mark) return
    tipMark = mark
    const y = e.clientY
    tipTimer = setTimeout(() => showTip(mark, y), 600)
  })
  wrap.addEventListener('mouseleave', hideTip)
  wrap.addEventListener('scroll', hideTip)
  document.addEventListener('keydown', e => { if (isGripHidingKey(e)) hide() }, true)
  editor.on('transaction', ({ transaction }) => { if (transaction.docChanged) schedule() })
  window.addEventListener('resize', schedule)
  new ResizeObserver(schedule).observe(view.dom)

  return { redraw, hide }
}
