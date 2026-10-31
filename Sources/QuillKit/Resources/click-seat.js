// Clicks outside every line of a block: docs/editor-gotchas.md, "A click outside every line".

const CLICK_SEAT_REACH_LINES = 2

// lines: { first, last } rects of each candidate's first and last line, in document order.
function clickSeatTarget(lines, y) {
  let best = null
  for (let i = 0; i < lines.length; i++) {
    const { first, last } = lines[i]
    if (y >= first.top && y <= last.bottom) return null
    const above = y < first.top
    const line = above ? first : last
    const dist = above ? first.top - y : y - last.bottom
    if (dist > (line.bottom - line.top) * CLICK_SEAT_REACH_LINES) continue
    if (best && dist > best.dist) continue
    best = { index: i, dist, y: (line.top + line.bottom) / 2 }
  }
  return best && { index: best.index, y: best.y }
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { clickSeatTarget }
}
