'use strict'

const { test, describe } = require('node:test')
const assert = require('node:assert/strict')
const { JSDOM } = require('jsdom')
const { extractAlignment, toWordPressHTML, formatHTML, countStats, findMatches, detectEmbedProvider, embedClassFor } = require('../Sources/QuillKit/Resources/editor-transforms.js')

const { document } = new JSDOM('<!DOCTYPE html>').window

// Convenience wrapper — always passes our jsdom document
function wp(html) {
  return toWordPressHTML(html, document)
}

// ---------------------------------------------------------------------------
// extractAlignment
// ---------------------------------------------------------------------------

describe('extractAlignment', () => {
  test('alignleft returns left', () => {
    assert.equal(extractAlignment('alignleft'), 'left')
  })

  test('alignright returns right', () => {
    assert.equal(extractAlignment('alignright'), 'right')
  })

  test('aligncenter returns center', () => {
    assert.equal(extractAlignment('aligncenter'), 'center')
  })

  test('empty string returns null', () => {
    assert.equal(extractAlignment(''), null)
  })

  test('unrelated class returns null', () => {
    assert.equal(extractAlignment('wp-block-image'), null)
  })

  test('alignment class mixed with others is still detected', () => {
    assert.equal(extractAlignment('wp-block-image alignright size-large'), 'right')
  })
})

// ---------------------------------------------------------------------------
// toWordPressHTML — headings
// ---------------------------------------------------------------------------

describe('toWordPressHTML — headings', () => {
  test('h1 gains wp-block-heading class', () => {
    const out = wp('<h1>Title</h1>')
    assert.match(out, /class="wp-block-heading"/)
  })

  test('h2 through h6 each gain wp-block-heading', () => {
    for (const level of [2, 3, 4, 5, 6]) {
      const out = wp(`<h${level}>Text</h${level}>`)
      assert.match(out, /wp-block-heading/, `h${level} missing class`)
    }
  })

  test('existing classes on heading are preserved', () => {
    const out = wp('<h2 class="custom">Text</h2>')
    assert.match(out, /custom/)
    assert.match(out, /wp-block-heading/)
  })

  test('headings are idempotent — running twice does not duplicate class', () => {
    const once = wp('<h2>Text</h2>')
    const twice = wp(once)
    const count = (twice.match(/wp-block-heading/g) || []).length
    assert.equal(count, 1)
  })
})

// ---------------------------------------------------------------------------
// toWordPressHTML — lists
// ---------------------------------------------------------------------------

describe('toWordPressHTML — lists', () => {
  test('ul gains wp-block-list', () => {
    const out = wp('<ul><li>item</li></ul>')
    assert.match(out, /wp-block-list/)
  })

  test('ol gains wp-block-list', () => {
    const out = wp('<ol><li>item</li></ol>')
    assert.match(out, /wp-block-list/)
  })

  test('task list (data-type=taskList) does NOT gain wp-block-list', () => {
    const out = wp('<ul data-type="taskList"><li data-type="taskItem"><div><p>task</p></div></li></ul>')
    assert.doesNotMatch(out, /wp-block-list/)
  })
})

// ---------------------------------------------------------------------------
// toWordPressHTML — list-item <p> unwrapping
// ---------------------------------------------------------------------------

describe('toWordPressHTML — list item p unwrap', () => {
  test('single-child <p> inside <li> is unwrapped', () => {
    const out = wp('<ul><li><p>text</p></li></ul>')
    assert.doesNotMatch(out, /<p>text<\/p>/)
    assert.match(out, /<li>text<\/li>/)
  })

  test('multi-child <li> is left untouched', () => {
    const out = wp('<ul><li><p>a</p><p>b</p></li></ul>')
    assert.match(out, /<p>a<\/p>/)
    assert.match(out, /<p>b<\/p>/)
  })

  test('task item div>p is unwrapped', () => {
    const out = wp('<ul data-type="taskList"><li data-type="taskItem"><div><p>task text</p></div></li></ul>')
    assert.doesNotMatch(out, /<p>task text<\/p>/)
    assert.match(out, /<div>task text<\/div>/)
  })
})

// ---------------------------------------------------------------------------
// toWordPressHTML — blockquotes and cite
// ---------------------------------------------------------------------------

describe('toWordPressHTML — blockquote', () => {
  test('blockquote gains wp-block-quote class', () => {
    const out = wp('<blockquote><p>quote</p></blockquote>')
    assert.match(out, /wp-block-quote/)
  })

  test('empty cite is stripped', () => {
    const out = wp('<blockquote><p>quote</p><cite></cite></blockquote>')
    assert.doesNotMatch(out, /<cite/)
  })

  test('whitespace-only cite is stripped', () => {
    const out = wp('<blockquote><p>quote</p><cite>   </cite></blockquote>')
    assert.doesNotMatch(out, /<cite/)
  })

  test('non-empty cite is preserved', () => {
    const out = wp('<blockquote><p>quote</p><cite>— Author</cite></blockquote>')
    assert.match(out, /<cite>— Author<\/cite>/)
  })

  test('cite stripping only applies inside blockquote', () => {
    // A <cite> outside a blockquote should not be stripped
    const out = wp('<p>text</p><cite>standalone</cite>')
    assert.match(out, /<cite>standalone<\/cite>/)
  })
})

// ---------------------------------------------------------------------------
// toWordPressHTML — code blocks
// ---------------------------------------------------------------------------

describe('toWordPressHTML — code blocks', () => {
  test('pre gains wp-block-code class', () => {
    const out = wp('<pre><code>const x = 1</code></pre>')
    assert.match(out, /wp-block-code/)
  })
})

// ---------------------------------------------------------------------------
// toWordPressHTML — images
// ---------------------------------------------------------------------------

describe('toWordPressHTML — images', () => {
  // renderHTML now always produces <figure><img ...><figcaption></figcaption></figure>

  test('figure with plain img gets wp-block-image class', () => {
    const out = wp('<figure><img src="a.jpg"><figcaption></figcaption></figure>')
    assert.match(out, /class="wp-block-image"/)
  })

  test('data-media-id produces wp-image-{id} class on img inside figure', () => {
    const out = wp('<figure><img src="a.jpg" data-media-id="42"><figcaption></figcaption></figure>')
    assert.match(out, /wp-image-42/)
  })

  test('alignleft on img is moved to figure class', () => {
    const out = wp('<figure><img src="a.jpg" class="alignleft"><figcaption></figcaption></figure>')
    const dom = new JSDOM(out).window.document
    const fig = dom.querySelector('figure')
    const img = dom.querySelector('img')
    assert.ok(fig.classList.contains('wp-block-image'), 'figure missing wp-block-image')
    assert.ok(fig.classList.contains('alignleft'), 'figure missing alignleft')
    assert.ok(!img.classList.contains('alignleft'), 'img should not have alignleft')
  })

  test('alignright on img is moved to figure class', () => {
    const out = wp('<figure><img src="a.jpg" class="alignright"><figcaption></figcaption></figure>')
    assert.match(out, /class="wp-block-image alignright"/)
  })

  test('aligncenter on img is moved to figure class', () => {
    const out = wp('<figure><img src="a.jpg" class="aligncenter"><figcaption></figcaption></figure>')
    assert.match(out, /class="wp-block-image aligncenter"/)
  })

  test('both alignment and media-id: figure gets align class, img gets wp-image class', () => {
    const out = wp('<figure><img src="a.jpg" class="alignleft" data-media-id="7"><figcaption></figcaption></figure>')
    assert.match(out, /wp-block-image alignleft/)
    assert.match(out, /wp-image-7/)
  })

  test('empty figcaption is removed from output', () => {
    const out = wp('<figure><img src="a.jpg"><figcaption></figcaption></figure>')
    assert.doesNotMatch(out, /<figcaption/)
  })

  test('non-empty figcaption gets wp-element-caption class', () => {
    const out = wp('<figure><img src="a.jpg"><figcaption>A caption</figcaption></figure>')
    assert.match(out, /class="wp-element-caption"/)
    assert.match(out, /A caption/)
  })

  test('whitespace-only figcaption is removed', () => {
    const out = wp('<figure><img src="a.jpg"><figcaption>   </figcaption></figure>')
    assert.doesNotMatch(out, /<figcaption/)
  })

  test('table figure is not treated as image figure', () => {
    const out = wp('<figure class="wp-block-table"><table><tbody><tr><td>x</td></tr></tbody></table></figure>')
    assert.doesNotMatch(out, /wp-block-image/)
  })
})

// ---------------------------------------------------------------------------
// toWordPressHTML — tables
// ---------------------------------------------------------------------------

describe('toWordPressHTML — tables', () => {
  test('table is wrapped in figure.wp-block-table', () => {
    const out = wp('<table><tbody><tr><td>cell</td></tr></tbody></table>')
    assert.match(out, /class="wp-block-table"/)
    assert.match(out, /<figure/)
  })

  test('all-th first row is promoted from tbody to thead', () => {
    const out = wp('<table><tbody><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></tbody></table>')
    const dom = new JSDOM(out).window.document
    const thead = dom.querySelector('thead')
    assert.ok(thead, 'thead not created')
    assert.ok(thead.querySelector('th'), 'th not in thead')
  })

  test('mixed th/td first row is NOT promoted to thead', () => {
    const out = wp('<table><tbody><tr><th>A</th><td>B</td></tr><tr><td>1</td><td>2</td></tr></tbody></table>')
    const dom = new JSDOM(out).window.document
    assert.equal(dom.querySelector('thead'), null, 'thead should not be created for mixed row')
  })

  test('table already having thead is not modified', () => {
    const input = '<table><thead><tr><th>A</th></tr></thead><tbody><tr><td>1</td></tr></tbody></table>'
    const out = wp(input)
    const dom = new JSDOM(out).window.document
    // Should still have exactly one thead
    assert.equal(dom.querySelectorAll('thead').length, 1)
  })

  test('table already inside wp-block-table is not double-wrapped', () => {
    const once = wp('<table><tbody><tr><td>cell</td></tr></tbody></table>')
    const twice = wp(once)
    const count = (twice.match(/wp-block-table/g) || []).length
    assert.equal(count, 1)
  })
})

// ---------------------------------------------------------------------------
// toWordPressHTML — idempotency and edge cases
// ---------------------------------------------------------------------------

describe('toWordPressHTML — idempotency and edge cases', () => {
  test('full document is idempotent across all transform types', () => {
    const input = [
      '<h2>Heading</h2>',
      '<ul><li><p>item</p></li></ul>',
      '<blockquote><p>quote</p><cite>author</cite></blockquote>',
      '<pre><code>code</code></pre>',
      '<figure><img src="a.jpg" class="alignleft" data-media-id="3"><figcaption></figcaption></figure>',
      '<table><tbody><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></tbody></table>',
    ].join('\n')
    const once = wp(input)
    const twice = wp(once)
    assert.equal(once, twice)
  })

  test('empty paragraph is stable', () => {
    const out = wp('<p></p>')
    assert.equal(out, '<p></p>')
  })

  test('unicode and emoji in text are preserved', () => {
    const out = wp('<p>café 🎉 "curly" ’quotes’</p>')
    assert.match(out, /café/)
    assert.match(out, /🎉/)
    assert.match(out, /curly/)
  })
})

// ---------------------------------------------------------------------------
// formatHTML — pretty-printer
// ---------------------------------------------------------------------------

function fmt(html) {
  return formatHTML(html, document)
}

describe('formatHTML — block elements', () => {
  test('single paragraph renders on one line with no surrounding blank lines', () => {
    const out = fmt('<p class="wp-block-heading">Hello world</p>')
    assert.equal(out, '<p class="wp-block-heading">Hello world</p>')
  })

  test('two top-level blocks are separated by a blank line', () => {
    const out = fmt('<p>First</p><h2>Second</h2>')
    assert.match(out, /First[\s\S]*\n\n[\s\S]*Second/)
  })

  test('inline elements stay on the same line as their parent block', () => {
    const out = fmt('<p>Hello <strong>bold</strong> and <em>italic</em></p>')
    assert.equal(out.trim(), '<p>Hello <strong>bold</strong> and <em>italic</em></p>')
  })

  test('links stay inline', () => {
    const out = fmt('<p>See <a href="https://example.com">this</a> link</p>')
    assert.match(out, /<p>See <a/)
    assert.equal(out.split('\n').length, 1)
  })
})

describe('formatHTML — nested block elements', () => {
  test('list items are indented inside ul', () => {
    const out = fmt('<ul class="wp-block-list"><li>Item 1</li><li>Item 2</li></ul>')
    const lines = out.split('\n')
    assert.match(lines[0], /^<ul/)
    assert.match(lines[1], /^  <li>Item 1<\/li>/)
    assert.match(lines[2], /^  <li>Item 2<\/li>/)
    assert.match(lines[3], /^<\/ul>/)
  })

  test('table cells are indented under their row and section', () => {
    const out = fmt('<figure class="wp-block-table"><table><thead><tr><th>Col</th></tr></thead></table></figure>')
    assert.match(out, /^<figure/m)
    assert.match(out, /^  <table/m)
    assert.match(out, /^    <thead/m)
    assert.match(out, /^      <tr/m)
    assert.match(out, /^        <th>Col<\/th>/m)
  })

  test('blockquote with p and cite each on their own indented lines', () => {
    const out = fmt('<blockquote class="wp-block-quote"><p>Quote</p><cite>Author</cite></blockquote>')
    assert.match(out, /^<blockquote/m)
    assert.match(out, /^  <p>Quote<\/p>/m)
    assert.match(out, /^  <cite>Author<\/cite>/m)
    assert.match(out, /^<\/blockquote>/m)
  })
})

describe('formatHTML — special elements', () => {
  test('img void element has no closing tag', () => {
    const out = fmt('<figure class="wp-block-image"><img src="x.jpg" width="100" height="100"></figure>')
    assert.doesNotMatch(out, /<\/img>/)
    assert.match(out, /<img/)
  })

  test('img is indented inside figure', () => {
    const out = fmt('<figure class="wp-block-image"><img src="x.jpg"></figure>')
    assert.match(out, /^  <img/m)
  })

  test('pre content is preserved verbatim without re-indenting', () => {
    const inner = '<code>line one\n  line two</code>'
    const out = fmt(`<pre class="wp-block-code">${inner}</pre>`)
    assert.match(out, new RegExp(inner.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))
  })

  test('empty input returns empty string', () => {
    assert.equal(fmt(''), '')
  })

  test('unicode and emoji are preserved', () => {
    const out = fmt('<p>café 🎉</p>')
    assert.match(out, /café/)
    assert.match(out, /🎉/)
  })
})

describe('formatHTML — entity escaping', () => {
  test('text node with < is escaped so it round-trips safely', () => {
    const out = fmt('<p>5 &lt; 10</p>')
    assert.match(out, /5 &lt; 10/)
    assert.doesNotMatch(out, /5 < 10/)
  })

  test('text node with & is escaped', () => {
    const out = fmt('<p>cats &amp; dogs</p>')
    assert.match(out, /cats &amp; dogs/)
  })

  test('text node with > is escaped', () => {
    const out = fmt('<p>10 &gt; 5</p>')
    assert.match(out, /10 &gt; 5/)
  })

  test('attribute value with " is escaped', () => {
    const out = fmt('<p class="foo&quot;bar">text</p>')
    assert.match(out, /class="foo&quot;bar"/)
    assert.doesNotMatch(out, /class="foo"bar"/)
  })

  test('attribute value with & is escaped', () => {
    const out = fmt('<a href="?a=1&amp;b=2">link</a>')
    assert.match(out, /href="[^"]*&amp;[^"]*"/)
  })
})

// ---------------------------------------------------------------------------
// countStats
// ---------------------------------------------------------------------------

describe('countStats', () => {
  test('empty string is zero words, zero characters', () => {
    assert.deepEqual(countStats(''), { words: 0, characters: 0 })
  })

  test('null/undefined input is zero', () => {
    assert.deepEqual(countStats(null), { words: 0, characters: 0 })
    assert.deepEqual(countStats(undefined), { words: 0, characters: 0 })
  })

  test('simple sentence', () => {
    assert.deepEqual(countStats('hello world'), { words: 2, characters: 11 })
  })

  test('multiple spaces and newlines count as one separator', () => {
    assert.equal(countStats('one  two\n\nthree\tfour').words, 4)
  })

  test('leading/trailing whitespace does not add words', () => {
    assert.equal(countStats('  hello  ').words, 1)
  })

  test('whitespace-only string is zero words', () => {
    assert.equal(countStats('   \n\t ').words, 0)
  })

  test('characters counted as code points, not UTF-16 units', () => {
    // 👍 is one code point but two UTF-16 units
    assert.deepEqual(countStats('👍'), { words: 1, characters: 1 })
  })

  test('unicode words count normally', () => {
    assert.equal(countStats('café naïve résumé').words, 3)
  })
})

// ---------------------------------------------------------------------------
// findMatches
// ---------------------------------------------------------------------------

describe('findMatches', () => {
  test('case-insensitive by default', () => {
    assert.deepEqual(findMatches('Hello hello HELLO', 'hello', false), [
      { start: 0, end: 5 }, { start: 6, end: 11 }, { start: 12, end: 17 },
    ])
  })

  test('case-sensitive mode', () => {
    assert.deepEqual(findMatches('Hello hello', 'hello', true), [{ start: 6, end: 11 }])
  })

  test('empty query returns no matches', () => {
    assert.deepEqual(findMatches('anything', '', false), [])
  })

  test('no match returns empty array', () => {
    assert.deepEqual(findMatches('abc', 'xyz', false), [])
  })

  test('regex special characters are treated literally', () => {
    assert.deepEqual(findMatches('price is $5.00 (sale)', '$5.00 (sale)', false), [{ start: 9, end: 21 }])
  })

  test('matches are non-overlapping', () => {
    assert.deepEqual(findMatches('aaa', 'aa', false), [{ start: 0, end: 2 }])
  })

  test('offsets are JS string indices (UTF-16)', () => {
    // 👍 occupies indices 0–1
    assert.deepEqual(findMatches('👍 hi', 'hi', false), [{ start: 3, end: 5 }])
  })
})

// ---------------------------------------------------------------------------
// Embeds — provider detection
// ---------------------------------------------------------------------------

describe('detectEmbedProvider', () => {
  test('youtube.com and youtu.be map to youtube', () => {
    assert.equal(detectEmbedProvider('https://www.youtube.com/watch?v=abc').slug, 'youtube')
    assert.equal(detectEmbedProvider('https://youtu.be/abc').slug, 'youtube')
  })

  test('vimeo maps to vimeo with video type', () => {
    const p = detectEmbedProvider('https://vimeo.com/12345')
    assert.equal(p.slug, 'vimeo')
    assert.equal(p.type, 'video')
  })

  test('x.com and twitter.com map to twitter', () => {
    assert.equal(detectEmbedProvider('https://x.com/user/status/1').slug, 'twitter')
    assert.equal(detectEmbedProvider('https://twitter.com/user/status/1').slug, 'twitter')
  })

  test('unknown host returns null', () => {
    assert.equal(detectEmbedProvider('https://example.com/video'), null)
  })

  test('invalid URL returns null', () => {
    assert.equal(detectEmbedProvider('not a url'), null)
  })
})

describe('embedClassFor', () => {
  test('youtube gets full Gutenberg class list with aspect ratio', () => {
    assert.equal(
      embedClassFor('https://www.youtube.com/watch?v=abc'),
      'wp-block-embed is-type-video is-provider-youtube wp-block-embed-youtube wp-embed-aspect-16-9 wp-has-aspect-ratio'
    )
  })

  test('twitter gets rich type without aspect classes', () => {
    assert.equal(
      embedClassFor('https://x.com/user/status/1'),
      'wp-block-embed is-type-rich is-provider-twitter wp-block-embed-twitter'
    )
  })

  test('unknown provider gets bare wp-block-embed', () => {
    assert.equal(embedClassFor('https://example.com/thing'), 'wp-block-embed')
  })
})

describe('toWordPressHTML — embeds', () => {
  const EMBED = '<figure class="wp-block-embed is-type-video is-provider-youtube wp-block-embed-youtube wp-embed-aspect-16-9 wp-has-aspect-ratio"><div class="wp-block-embed__wrapper">\nhttps://youtu.be/abc\n</div></figure>'

  test('embed figure passes through unchanged', () => {
    assert.equal(wp(EMBED), EMBED)
  })

  test('embed figure does not gain wp-block-image', () => {
    assert.ok(!wp(EMBED).includes('wp-block-image'))
  })

  test('embed figure with caption passes through unchanged', () => {
    const withCaption = EMBED.replace('</figure>', '<figcaption class="wp-element-caption">My <a href="https://e.com">video</a></figcaption></figure>')
    assert.equal(wp(withCaption), withCaption)
  })
})
