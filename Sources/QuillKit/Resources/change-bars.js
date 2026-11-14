// Change bars beside blocks that differ from the saved version: docs/superpowers/specs/2026-10-31-change-bars-design.md.

function _changeBarEntries(doc, trailingAfter, keyOf) {
  const skip = generatedTrailingIndex(doc, trailingAfter)
  const entries = []
  doc.forEach((node, _offset, index) => { if (index !== skip) entries.push({ index, key: keyOf(node) }) })
  return entries
}

// Which saved block each current block came from, worked out from the saved HTML alone: a
// longest common subsequence of the keys, then same-HTML pairs as moves, then each edit paired
// with a removal between the same two matches. Used when nothing better is known (no history).
function _originsByKey(before, after) {
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
  const origin = after.map(() => -1)
  const inOrder = after.map(() => false)
  const runs = [[]]
  let i = 0
  let j = 0
  while (i < before.length || j < after.length) {
    if (i < before.length && j < after.length && before[i].key === after[j].key) {
      origin[j] = i
      inOrder[j] = true
      runs.push([])
      i++
      j++
    } else if (j < after.length && (i === before.length || lengths[i * cols + j + 1] >= lengths[(i + 1) * cols + j])) {
      runs[runs.length - 1].push({ added: j })
      j++
    } else {
      runs[runs.length - 1].push({ removed: i })
      i++
    }
  }
  const removedByKey = new Map()
  for (const op of runs.flat()) {
    if (op.removed === undefined) continue
    const key = before[op.removed].key
    if (!removedByKey.has(key)) removedByKey.set(key, [])
    removedByKey.get(key).push(op)
  }
  for (const op of runs.flat()) {
    if (op.added === undefined) continue
    const removal = removedByKey.get(after[op.added].key)?.shift()
    if (removal) { origin[op.added] = removal.removed; op.paired = removal.paired = true }
  }
  for (const run of runs) {
    const removals = run.filter(op => op.removed !== undefined && !op.paired)
    run.filter(op => op.added !== undefined && !op.paired).forEach((op, k) => {
      if (k < removals.length) origin[op.added] = removals[k].removed
    })
  }
  return { origin, inOrder }
}

// The largest set of blocks still in their saved order, counting a block the author moved as
// worth less than all the others together, so the blocks the author moved are the ones left out.
function _keptInOrder(origin, flagged) {
  const weightOf = j => (flagged[j] ? 1 : origin.length + 1)
  const best = origin.map(() => 0)
  const prev = origin.map(() => -1)
  let end = -1
  for (let j = 0; j < origin.length; j++) {
    if (origin[j] < 0) continue
    best[j] = weightOf(j)
    // On a tie the later predecessor wins, so of two swapped blocks the first is the one marked.
    for (let k = 0; k < j; k++) {
      if (origin[k] >= 0 && origin[k] < origin[j] && best[k] + weightOf(j) >= best[j]) {
        best[j] = best[k] + weightOf(j)
        prev[j] = k
      }
    }
    if (end < 0 || best[j] >= best[end]) end = j
  }
  const inOrder = origin.map(() => false)
  for (let j = end; j >= 0; j = prev[j]) inOrder[j] = true
  return inOrder
}

// known, when given, maps a current block's index to { origin, moved }: the index of the saved
// block it came from (null for a new block) and whether the author moved it with the grip or
// Move Block. Quill follows every block through its edits, moves, undo and redo, so an edited
// block is never mistaken for a deletion. A block with no known origin (pasted, or rebuilt from
// code view) takes the saved block with the same HTML, if no other block has it.
function changedBlocks(baseline, current, trailingAfter, keyOf, known) {
  const before = _changeBarEntries(baseline, trailingAfter, keyOf)
  const after = _changeBarEntries(current, trailingAfter, keyOf)
  let origin
  let inOrder
  let flagged = after.map(() => false)
  if (known) {
    // Known origins first, a block still reading as its own before an edited one; then a block
    // with no known origin (pasted, or rebuilt from code view) takes a saved block nobody has
    // and that reads the same.
    const positionOf = new Map(before.map((entry, i) => [entry.index, i]))
    const knownAt = after.map(entry => {
      const saved = known.get(entry.index)?.origin
      return saved == null ? undefined : positionOf.get(saved)
    })
    const claimed = new Set()
    const claim = i => (i === undefined || claimed.has(i) ? -1 : (claimed.add(i), i))
    origin = after.map((entry, j) => (knownAt[j] !== undefined && before[knownAt[j]].key === entry.key ? claim(knownAt[j]) : -1))
    origin = origin.map((i, j) => (i >= 0 ? i : claim(knownAt[j])))
    const unclaimed = new Map()
    before.forEach((entry, i) => {
      if (claimed.has(i)) return
      if (!unclaimed.has(entry.key)) unclaimed.set(entry.key, [])
      unclaimed.get(entry.key).push(i)
    })
    origin = origin.map((i, j) => {
      if (i >= 0 || knownAt[j] !== undefined) return i
      const same = unclaimed.get(after[j].key)
      while (same?.length) { const k = same.shift(); if (!claimed.has(k)) return claim(k) }
      return -1
    })
    // A move flags the saved block, so the flag stays with whichever block reads as it now.
    const movedOrigins = new Set(knownAt.filter((i, j) => i !== undefined && known.get(after[j].index).moved))
    flagged = after.map((entry, j) => !!known.get(entry.index)?.moved || movedOrigins.has(origin[j]))
    inOrder = _keptInOrder(origin, flagged)
  } else {
    ({ origin, inOrder } = _originsByKey(before, after))
  }

  const edited = j => origin[j] < 0 || before[origin[j]].key !== after[j].key
  const changed = []
  const moved = []
  const anchors = []
  after.forEach((entry, j) => {
    if (edited(j) || !inOrder[j]) changed.push(entry.index)
    if (!edited(j) && !inOrder[j]) moved.push(entry.index)
    if (!edited(j) && inOrder[j]) anchors.push(j)
  })

  // A saved block that no current block came from was removed. Removals between the same two
  // unchanged blocks share a gap, which gets one dash unless an edit between those two stands in
  // for them, as before. A block the author moved there stands in for nothing.
  const claimedBy = new Set(origin.filter(i => i >= 0))
  const removedGaps = []
  let a = 0
  let gapHasRemoval = false
  const closeGap = () => {
    if (!gapHasRemoval) return
    gapHasRemoval = false
    const from = a > 0 ? anchors[a - 1] + 1 : 0
    const to = a < anchors.length ? anchors[a] : after.length
    for (let j = from; j < to; j++) if (edited(j) && !flagged[j]) return
    removedGaps.push(to > 0 ? after[to - 1].index + 1 : 0)
  }
  for (let i = 0; i < before.length; i++) {
    while (a < anchors.length && origin[anchors[a]] < i) { closeGap(); a++ }
    if (!claimedBy.has(i)) gapHasRemoval = true
  }
  closeGap()

  const origins = []
  const placed = []
  after.forEach((entry, j) => {
    origins[entry.index] = origin[j] >= 0 ? before[origin[j]].index : null
    placed[entry.index] = inOrder[j]
  })
  // A body emptied of every saved block is one empty paragraph, which ProseMirror puts there because
  // a doc can't hold none. The author wrote none of it, so it stands in for nothing: one dash. A
  // saved empty paragraph, unchanged or with only its settings changed, is not that paragraph.
  const isEmptyParagraph = node => node.type.name === 'paragraph' && node.content.size === 0
  const emptied = after.length === 1 && isEmptyParagraph(current.child(after[0].index)) && edited(0)
    && (origin[0] < 0 || !isEmptyParagraph(baseline.child(before[origin[0]].index)))
  if (emptied) return { changed: [], moved: [], removedGaps: [0], origins, placed }
  return { changed, moved, removedGaps, origins, placed }
}

// Follows every top-level block through one transaction. state.entries holds { pos, origin, moved }
// per block: its start, the index of the saved block it came from (or null) and whether the author
// moved it. state.seen remembers each node version's entry, so a block that an undo or redo puts
// back, which is the same node object, gets its entry back. Step by step, because one undo can put
// a block back and then reverse edits made to it, leaving a version only an in-between doc held.
function mapMovedBlocks(state, tr) {
  if (!state.ready || !tr.docChanged) return state
  let entries = state.entries
  tr.steps.forEach((_step, k) => {
    const doc = k + 1 < tr.docs.length ? tr.docs[k + 1] : tr.doc
    entries = _followStep(entries, tr.mapping.maps[k], doc, state.seen)
  })
  return { ...state, entries }
}

// A block keeps its entry while its start survives. One replaced in place (made a heading,
// wrapped in a list) keeps it too, when no surviving block starts where it began.
function _followStep(entries, map, doc, seen) {
  const starts = new Map()
  doc.forEach((node, offset) => starts.set(offset, node))
  const claims = new Map()
  const replaced = []
  for (const entry of entries) {
    const result = map.mapResult(entry.pos, 1)
    if (!result.deletedAfter && starts.has(result.pos) && !claims.has(result.pos)) claims.set(result.pos, entry)
    else replaced.push(entry)
  }
  for (const entry of replaced) {
    const pos = map.map(entry.pos, -1)
    if (starts.has(pos) && !claims.has(pos)) claims.set(pos, entry)
  }
  // Enter at the start of a block leaves its start on a new empty block in front; the entry
  // belongs to the text, which is the brand-new block right after it. Undoing that joins the
  // text back into the new block, and the text's entry takes the merged block back.
  for (const entry of entries) {
    if ([...claims.values()].includes(entry)) continue
    const at = map.map(entry.pos, -1) - 1
    if (starts.get(at)?.isTextblock && (!claims.has(at) || claims.get(at).origin === null)) claims.set(at, entry)
  }
  const offsets = [...starts.keys()]
  offsets.forEach((offset, k) => {
    const node = starts.get(offset)
    const nextOffset = offsets[k + 1]
    if (!claims.has(offset) || !node.isTextblock || node.content.size || nextOffset === undefined) return
    if (claims.has(nextOffset) || seen.has(starts.get(nextOffset))) return
    claims.set(nextOffset, claims.get(offset))
    claims.delete(offset)
  })
  const next = []
  const used = new Set()
  for (const [offset, node] of starts) {
    let entry = claims.get(offset)
    if (entry && entry.origin !== null && used.has(entry.origin)) entry = null
    if (!entry) {
      const known = seen.get(node)
      entry = known && (known.origin === null || !used.has(known.origin)) ? known : { origin: null, moved: false }
    }
    if (entry.origin !== null) used.add(entry.origin)
    const kept = { pos: offset, origin: entry.origin, moved: entry.moved }
    seen.set(node, kept)
    next.push(kept)
  }
  return next
}

// The entries as changedBlocks takes them, or undefined before the first baseline.
function knownBlockOrigins(doc, state) {
  if (!state.ready) return undefined
  const indexAt = new Map()
  doc.forEach((_node, offset, index) => indexAt.set(offset, index))
  const known = new Map()
  for (const entry of state.entries) {
    if (indexAt.has(entry.pos)) known.set(indexAt.get(entry.pos), entry)
  }
  return known
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
  const TICK_WIDTH = 10
  const TICK_HEIGHT = 2
  const TICK_CLEAR = 6
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
    const { changed, moved, removedGaps } = hooks.marks()
    if (!changed.length && !removedGaps.length) return layer.replaceChildren()
    const doc = view.state.doc
    const layerRect = layer.getBoundingClientRect()
    const colRect = view.dom.getBoundingClientRect()
    const x = colRect.right - (parseFloat(getComputedStyle(view.dom).paddingRight) || 0) - layerRect.left + BAR_GAP
    const marks = []
    const ys = removedGaps.length ? gapYs(view) : []
    const dashYs = removedGaps.map(gap => ys[Math.min(gap, ys.length - 1)] - layerRect.top)
    for (const index of changed) {
      const dom = view.nodeDOM(topLevelPos(doc, index))
      if (!dom || dom.nodeType !== 1) continue
      const rect = dom.getBoundingClientRect()
      // A bar stops short of a deletion dash beside its end, so the two never read as one shape.
      let top = rect.top - layerRect.top
      let bottom = rect.bottom - layerRect.top
      for (const y of dashYs) {
        if (y >= bottom - TICK_CLEAR && y < bottom + TICK_CLEAR) bottom = Math.min(bottom, y - TICK_CLEAR)
        if (y <= top + TICK_CLEAR && y > top - TICK_CLEAR) top = Math.max(top, y + TICK_CLEAR)
      }
      // Too short to trim (or no layout yet): keep the block's full height.
      if (bottom - top < 4) { top = rect.top - layerRect.top; bottom = rect.bottom - layerRect.top }
      const bar = document.createElement('div')
      bar.className = moved.includes(index) ? 'change-bar moved' : 'change-bar'
      Object.assign(bar.style, { left: x + 'px', top: top + 'px', height: (bottom - top) + 'px' })
      marks.push(bar)
    }
    for (const y of dashYs) {
      const dash = document.createElement('div')
      dash.className = 'change-bar-removed'
      Object.assign(dash.style, { left: (x + 1 - TICK_WIDTH / 2) + 'px', top: (y - TICK_HEIGHT / 2) + 'px' })
      marks.push(dash)
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
    tip.textContent = mark.classList.contains('change-bar-removed') ? 'Removed since the last save'
      : mark.classList.contains('moved') ? 'Moved since the last save'
      : 'Changed since the last save'
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
