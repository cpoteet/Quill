'use strict'

// Reads WordPress block comments into a tree with source offsets; held to WordPress's parser by Scripts/test-block-parser.js (docs/block-model.md).

function parseBlocks(html) {
  const WHITESPACE = /\s/
  const ATTRS_END = /\}\s+\/?-->/g
  let attrsSearchFrom = -1
  let attrsFound = -1

  function isNameStart(ch) {
    return ch >= 'a' && ch <= 'z'
  }

  function isNameChar(ch) {
    return isNameStart(ch) || (ch >= '0' && ch <= '9') || ch === '_' || ch === '-'
  }

  function skipWhitespace(p) {
    while (p < html.length && WHITESPACE.test(html[p])) p++
    return p
  }

  function readName(p) {
    if (!isNameStart(html[p])) return -1
    p++
    while (p < html.length && isNameChar(html[p])) p++
    return p
  }

  function findAttrsEnd(from) {
    if (attrsSearchFrom !== -1 && from >= attrsSearchFrom && (attrsFound === -1 || from <= attrsFound)) {
      return attrsFound
    }
    ATTRS_END.lastIndex = from
    const match = ATTRS_END.exec(html)
    attrsSearchFrom = from
    attrsFound = match ? match.index : -1
    return attrsFound
  }

  function readDelimiter(start) {
    let p = start + 4
    const afterOpen = skipWhitespace(p)
    if (afterOpen === p) return null
    p = afterOpen

    let closer = false
    if (html[p] === '/') {
      closer = true
      p++
    }
    if (!html.startsWith('wp:', p)) return null
    p += 3

    const firstStart = p
    const firstEnd = readName(p)
    if (firstEnd === -1) return null
    let blockName = 'core/' + html.slice(firstStart, firstEnd)
    p = firstEnd
    if (html[p] === '/') {
      const secondEnd = readName(p + 1)
      if (secondEnd === -1) return null
      blockName = html.slice(firstStart, secondEnd)
      p = secondEnd
    }

    const afterName = skipWhitespace(p)
    if (afterName === p) return null
    p = afterName

    let attrs = {}
    if (html[p] === '{') {
      const brace = findAttrsEnd(p)
      if (brace === -1) return null
      const attrsEnd = skipWhitespace(brace + 1)
      try {
        attrs = JSON.parse(html.slice(p, attrsEnd))
      } catch {
        attrs = null
      }
      p = attrsEnd
    }

    let selfClosing = false
    if (html[p] === '/') {
      selfClosing = true
      p++
    }
    if (!html.startsWith('-->', p)) return null

    const kind = selfClosing ? 'void' : closer ? 'close' : 'open'
    return { kind, blockName, attrs, start, end: p + 3 }
  }

  function nextToken(from) {
    let i = html.indexOf('<!--', from)
    while (i !== -1) {
      const token = readDelimiter(i)
      if (token) return token
      i = html.indexOf('<!--', i + 1)
    }
    return null
  }

  function freeform(start, end) {
    const text = html.slice(start, end)
    return { blockName: null, attrs: {}, innerBlocks: [], innerHTML: text, innerContent: [text], start, end }
  }

  const output = []
  const stack = []

  function addText(start, end, keepEmpty) {
    if (start === end && !keepEmpty) return
    if (stack.length === 0) {
      output.push(freeform(start, end))
      return
    }
    const text = html.slice(start, end)
    const block = stack[stack.length - 1]
    block.innerHTML += text
    block.innerContent.push(text)
  }

  function addBlock(block) {
    if (stack.length === 0) {
      output.push(block)
      return
    }
    const parent = stack[stack.length - 1]
    parent.innerBlocks.push(block)
    parent.innerContent.push(null)
  }

  let cursor = 0
  for (;;) {
    const token = nextToken(cursor)
    if (!token) break

    if (token.kind === 'close' && stack.length === 0) {
      output.push(freeform(cursor, html.length))
      return output
    }

    addText(cursor, token.start, token.kind === 'close' && stack.length > 1)
    cursor = token.end

    if (token.kind === 'open') {
      stack.push({
        blockName: token.blockName,
        attrs: token.attrs,
        innerBlocks: [],
        innerHTML: '',
        innerContent: [],
        start: token.start,
        end: token.end,
      })
    } else if (token.kind === 'void') {
      addBlock({
        blockName: token.blockName,
        attrs: token.attrs,
        innerBlocks: [],
        innerHTML: '',
        innerContent: [],
        start: token.start,
        end: token.end,
      })
    } else {
      const block = stack.pop()
      block.end = token.end
      addBlock(block)
    }
  }

  addText(cursor, html.length)
  while (stack.length) {
    const block = stack.pop()
    block.end = html.length
    block.closed = false
    addBlock(block)
  }
  return output
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { parseBlocks }
}
