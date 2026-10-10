const Ease = {
  linear: x => x,
  inOut: x => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2),
  out: x => 1 - Math.pow(1 - x, 3),
  in: x => x * x * x,
  outQuint: x => 1 - Math.pow(1 - x, 5),
  sine: x => -(Math.cos(Math.PI * x) - 1) / 2,
  back: x => 1 + 2.2 * Math.pow(x - 1, 3) + 1.2 * Math.pow(x - 1, 2),
}

const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x))
const lerp = (a, b, p) => a + (b - a) * p
const span = (t, a, b) => clamp((t - a) / (b - a))

function mix(a, b, p) {
  if (Array.isArray(a)) return a.map((v, i) => lerp(v, b[i], p))
  return lerp(a, b, p)
}

// keys: [[time, value, ease?], ...]; the ease on a key shapes the segment that ends there.
function kf(t, keys) {
  if (t <= keys[0][0]) return keys[0][1]
  for (let i = 1; i < keys.length; i++) {
    const [t1, v1, ease] = keys[i]
    if (t <= t1) {
      const [t0, v0] = keys[i - 1]
      const p = t1 === t0 ? 1 : (t - t0) / (t1 - t0)
      return mix(v0, v1, (ease || Ease.inOut)(p))
    }
  }
  return keys[keys.length - 1][1]
}

// 0 → 1 over [a, a+d], then 1 → 0 over [b-d, b].
function window01(t, a, b, d = 0.3, ease = Ease.out) {
  return Math.min(ease(span(t, a, a + d)), ease(1 - span(t, b - d, b)))
}

// When each character of text appears, with a deterministic rhythm so typing does not look mechanical.
function keyTimes(t0, t1, text) {
  const weights = [...text].map((c, i) => (c === ' ' ? 1.5 : /[,.]/.test(c) ? 2.4 : 1) * (0.75 + ((i * 7919) % 13) / 26))
  const total = weights.reduce((a, b) => a + b, 0)
  let acc = 0
  return weights.map(w => t0 + ((acc += w) / total) * (t1 - t0))
}

function typed(t, t0, t1, text) {
  if (t <= t0) return ''
  if (t >= t1) return text
  return text.slice(0, keyTimes(t0, t1, text).filter(k => k <= t).length)
}

const blink = (t, since) => (t - since < 0.5 ? 1 : Math.floor((t - since - 0.5) / 0.53) % 2 === 0 ? 0 : 1)

function css(el, props) {
  for (const k in props) {
    const v = props[k]
    if (el.style[k] !== v) el.style[k] = v
  }
}
