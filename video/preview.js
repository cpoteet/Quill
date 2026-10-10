const frame = document.getElementById('stage-frame')
const box = document.getElementById('frame-box')
const scrub = document.getElementById('scrub')
const time = document.getElementById('time')
const play = document.getElementById('play')

const hashTime = () => Number((location.hash.match(/t=([\d.]+)/) || [])[1] || 0)

let t = hashTime()
let playing = false
let last = 0
let busy = false
let duration = 60

function fit() {
  const k = Math.min(box.clientWidth / 1920, box.clientHeight / 1080)
  frame.style.transform = `translate(${(box.clientWidth - 1920 * k) / 2}px, ${(box.clientHeight - 1080 * k) / 2}px) scale(${k})`
}

async function show() {
  if (busy || !frame.contentWindow.seek) return
  busy = true
  await frame.contentWindow.seek(t)
  busy = false
  scrub.value = t
  time.textContent = t.toFixed(2)
}

function tick(now) {
  if (!playing) return
  t += (now - last) / 1000
  last = now
  if (t >= duration) { t = duration; playing = false; play.textContent = 'Play' }
  show()
  requestAnimationFrame(tick)
}

play.addEventListener('click', () => {
  playing = !playing
  play.textContent = playing ? 'Pause' : 'Play'
  if (t >= duration) t = 0
  last = performance.now()
  requestAnimationFrame(tick)
})
scrub.addEventListener('input', () => { t = Number(scrub.value); show() })
window.addEventListener('resize', fit)
window.addEventListener('hashchange', () => { t = hashTime(); show() })
frame.addEventListener('load', () => {
  fit()
  const wait = () => {
    if (!frame.contentWindow.seek) return setTimeout(wait, 50)
    duration = frame.contentWindow.DURATION
    scrub.max = duration
    show()
  }
  wait()
})
fit()
