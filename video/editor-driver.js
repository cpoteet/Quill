const EditorDriver = (() => {
  let frame, win, doc, ed, wrap, overlay, caretEl, pendingStyle, insertMenu, insertButton, dropOverlay
  let lastKey = null
  let selEls = []

  const OVERLAY_CSS = `
    *, *::before, *::after { transition: none !important; animation: none !important; }
    #heading-menu, #insert-menu { background: #fff; }
    .ProseMirror { caret-color: transparent; }
    .ProseMirror ::selection { background: transparent; }
    #editor-wrap { position: relative; }
    #video-overlay { position: absolute; left: 0; top: 0; width: 0; height: 0; pointer-events: none; z-index: 5; }
    .video-sel { position: absolute; background: rgba(199, 119, 0, 0.3); mix-blend-mode: multiply; border-radius: 2px; }
    .video-caret { position: absolute; width: 1.5px; background: #bf801e; }
  `

  function loaded(el) {
    return new Promise(resolve => {
      const ready = () => el.contentWindow?.document?.readyState === 'complete' && el.contentWindow.eval('typeof editor') === 'object'
      const poll = () => (ready() ? resolve() : setTimeout(poll, 30))
      poll()
    })
  }

  async function init(frameEl) {
    frame = frameEl
    await loaded(frame)
    win = frame.contentWindow
    doc = win.document
    ed = win.eval('editor')
    ed.view.dom.setAttribute('spellcheck', 'false')
    doc.getElementById('ai-toolbar-group').style.display = ''
    const style = doc.createElement('style')
    style.textContent = OVERLAY_CSS
    doc.head.appendChild(style)
    pendingStyle = doc.createElement('style')
    doc.head.appendChild(pendingStyle)
    wrap = doc.getElementById('editor-wrap')
    overlay = doc.createElement('div')
    overlay.id = 'video-overlay'
    wrap.appendChild(overlay)
    caretEl = doc.createElement('div')
    caretEl.className = 'video-caret'
    overlay.appendChild(caretEl)
    insertMenu = doc.getElementById('insert-menu')
    insertButton = doc.getElementById('insert-button')
    dropOverlay = doc.getElementById('drop-overlay')
  }

  function setDoc(json) {
    const key = JSON.stringify(json)
    if (key !== lastKey) {
      ed.commands.setContent(json, false)
      lastKey = key
    }
  }

  function select(pos) {
    if (pos != null && ed.state.selection.from !== pos) ed.commands.setTextSelection(pos)
  }

  function textblocks() {
    const out = []
    ed.state.doc.descendants((node, pos) => {
      if (node.isTextblock) out.push({ node, pos })
    })
    return out
  }

  // Positions inside the i-th textblock: start, end, or start + offset.
  function posIn(i, offset = 'end') {
    const tb = textblocks()[i]
    if (!tb) return null
    if (offset === 'end') return tb.pos + 1 + tb.node.content.size
    return tb.pos + 1 + Math.min(offset, tb.node.content.size)
  }

  function toWrap(rect) {
    const w = wrap.getBoundingClientRect()
    return { x: rect.left - w.left + wrap.scrollLeft, y: rect.top - w.top + wrap.scrollTop }
  }

  function showCaret(pos, visible) {
    if (pos == null || !visible) {
      caretEl.style.display = 'none'
      return
    }
    const c = ed.view.coordsAtPos(pos)
    const p = toWrap({ left: c.left, top: c.top })
    css(caretEl, { display: 'block', left: `${p.x}px`, top: `${p.y}px`, height: `${c.bottom - c.top}px` })
  }

  function lineRects(from, to) {
    const a = ed.view.domAtPos(from)
    const b = ed.view.domAtPos(to)
    const range = doc.createRange()
    range.setStart(a.node, a.offset)
    range.setEnd(b.node, b.offset)
    const lines = new Map()
    for (const r of range.getClientRects()) {
      if (r.width < 1) continue
      const key = Math.round(r.top)
      const line = lines.get(key)
      if (line) {
        line.left = Math.min(line.left, r.left)
        line.right = Math.max(line.right, r.right)
      } else {
        lines.set(key, { left: r.left, right: r.right, top: r.top, bottom: r.bottom })
      }
    }
    return [...lines.values()]
  }

  function showSelection(range) {
    const rects = range && range[1] > range[0] ? lineRects(range[0], range[1]) : []
    while (selEls.length < rects.length) {
      const el = doc.createElement('div')
      el.className = 'video-sel'
      overlay.appendChild(el)
      selEls.push(el)
    }
    selEls.forEach((el, i) => {
      const r = rects[i]
      if (!r) return css(el, { display: 'none' })
      const p = toWrap(r)
      css(el, { display: 'block', left: `${p.x}px`, top: `${p.y - 1}px`, width: `${r.right - r.left}px`, height: `${r.bottom - r.top + 2}px` })
    })
  }

  function setPending(childIndex, opacity) {
    const rule = childIndex == null ? '' : `.ProseMirror > :nth-child(${childIndex + 1}) { opacity: ${opacity.toFixed(3)}; }`
    if (pendingStyle.textContent !== rule) pendingStyle.textContent = rule
  }

  function setInsertMenu(open, hoverItem) {
    if (open) {
      const r = insertButton.getBoundingClientRect()
      css(insertMenu, { left: `${Math.max(r.left, 8)}px`, top: `${r.bottom + 8}px` })
    }
    insertMenu.classList.toggle('visible', open)
    insertButton.setAttribute('aria-expanded', String(open))
    insertMenu.querySelectorAll('.heading-menu-item').forEach(el => {
      el.classList.toggle('active', open && el.dataset.insert === hoverItem)
    })
  }

  function setHeadingMenu(open, level) {
    const menu = doc.getElementById('heading-menu')
    const button = doc.getElementById('heading-button')
    if (open) {
      const r = button.getBoundingClientRect()
      css(menu, { left: `${Math.max(r.left, 8)}px`, top: `${r.bottom + 8}px` })
    }
    menu.classList.toggle('visible', open)
    button.setAttribute('aria-expanded', String(open))
    menu.querySelectorAll('[data-heading-level]').forEach(el => {
      el.classList.toggle('active', Number(el.dataset.headingLevel) === level)
    })
  }

  function setDropOverlay(on) {
    dropOverlay.classList.toggle('active', on)
  }

  function setScroll(y) {
    const max = wrap.scrollHeight - wrap.clientHeight
    const v = Math.round(Math.min(Math.max(y, 0), max))
    if (wrap.scrollTop !== v) wrap.scrollTop = v
  }

  // Window-space point for something inside the editor frame.
  function frameOrigin() {
    let x = 0, y = 0, el = frame
    while (el && el.id !== 'window') {
      x += el.offsetLeft
      y += el.offsetTop
      el = el.offsetParent
    }
    return [x, y]
  }

  function pointOfSelector(selector, ax = 0.5, ay = 0.5) {
    const el = doc.querySelector(selector)
    const r = el.getBoundingClientRect()
    const [ox, oy] = frameOrigin()
    return [ox + r.left + r.width * ax, oy + r.top + r.height * ay]
  }

  function pointOfPos(pos) {
    const c = ed.view.coordsAtPos(pos)
    const [ox, oy] = frameOrigin()
    return [ox + c.left, oy + (c.top + c.bottom) / 2]
  }

  function blockTop(childIndex) {
    const el = ed.view.dom.children[childIndex]
    return el ? toWrap(el.getBoundingClientRect()).y : 0
  }

  function settled() {
    const imgs = [...doc.images].filter(img => !img.complete)
    const decode = imgs.map(img => new Promise(r => { img.onload = img.onerror = r }))
    return Promise.all([...decode, doc.fonts.ready]).then(
      () => new Promise(r => {
        win.requestAnimationFrame(() => win.requestAnimationFrame(r))
        setTimeout(r, 80)
      })
    )
  }

  return {
    init, setDoc, select, posIn, showCaret, showSelection, setPending, setHeadingMenu, setInsertMenu, setDropOverlay,
    setScroll, pointOfSelector, pointOfPos, blockTop, settled,
  }
})()
