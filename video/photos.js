const Photos = (() => {
  function rng(seed) {
    let s = seed >>> 0
    return () => {
      s = (s * 1664525 + 1013904223) >>> 0
      return s / 4294967296
    }
  }

  function ridge(rand, w, h, base, amp, rough, steps = 48) {
    const pts = []
    const phase = rand() * 10
    for (let i = 0; i <= steps; i++) {
      const x = (i / steps) * w
      const n = Math.sin(i * 0.21 + phase) * 0.55 + Math.sin(i * 0.53 + phase * 2) * 0.3 + (rand() - 0.5) * rough
      pts.push(`${x.toFixed(1)},${(base - n * amp).toFixed(1)}`)
    }
    return `M0,${h} L${pts.join(' L')} L${w},${h} Z`
  }

  function trees(rand, w, base, color, count) {
    let out = ''
    for (let i = 0; i < count; i++) {
      const x = rand() * w
      const th = 18 + rand() * 26
      const y = base + rand() * 30
      out += `<path d="M${x},${y - th} L${x - th * 0.28},${y} L${x + th * 0.28},${y} Z" fill="${color}"/>`
    }
    return out
  }

  function landscape({ seed, sky, layers, sun, snow, lake, forest, w = 1200, h = 800 }) {
    const rand = rng(seed)
    let body = ''
    if (sun) body += `<circle cx="${sun[0] * w}" cy="${sun[1] * h}" r="${sun[2]}" fill="${sun[3]}" opacity="0.9"/>`
    const horizon = lake ? h * 0.62 : h
    layers.forEach((color, i) => {
      const base = h * (0.42 + i * 0.12)
      const amp = h * (0.16 - i * 0.025)
      const fill = snow && i === 0 ? 'url(#snow)' : color
      body += `<path d="${ridge(rand, w, horizon, base, amp, 0.35 + i * 0.1)}" fill="${fill}"/>`
    })
    if (forest) body += trees(rand, w, h * 0.78, forest, 70)
    if (lake) {
      body += `<rect x="0" y="${horizon}" width="${w}" height="${h - horizon}" fill="url(#water)"/>`
      body += `<g transform="translate(0 ${horizon * 2}) scale(1 -1)" opacity="0.28">${layers.map((c, i) => `<path d="${ridge(rng(seed), w, horizon, h * (0.42 + i * 0.12), h * (0.16 - i * 0.025), 0.35 + i * 0.1)}" fill="${c}"/>`).join('')}</g>`
    }
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" preserveAspectRatio="xMidYMid slice">
<defs>
<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${sky[0]}"/><stop offset="1" stop-color="${sky[1]}"/></linearGradient>
<linearGradient id="water" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${sky[1]}"/><stop offset="1" stop-color="${sky[0]}"/></linearGradient>
<linearGradient id="snow" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f4f6fa"/><stop offset="0.3" stop-color="${layers[0]}"/></linearGradient>
<linearGradient id="haze" x1="0" y1="0" x2="0" y2="1"><stop offset="0.3" stop-color="#ffffff" stop-opacity="0"/><stop offset="1" stop-color="#ffffff" stop-opacity="0.12"/></linearGradient>
<filter id="grain"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="${seed}"/><feColorMatrix values="0 0 0 0 0.5  0 0 0 0 0.5  0 0 0 0 0.5  0 0 0 0.09 0"/></filter>
</defs>
<rect width="${w}" height="${h}" fill="url(#sky)"/>${body}
<rect width="${w}" height="${h}" fill="url(#haze)"/>
<rect width="${w}" height="${h}" filter="url(#grain)"/>
</svg>`
    return 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg)
  }

  const hero = landscape({
    seed: 11, sky: ['#9fb8d6', '#f1d2b8'], sun: [0.7, 0.36, 46, '#fff3df'],
    layers: ['#8a93ab', '#5f6b86', '#3d4a63', '#24303f'], snow: true,
  })

  const library = [
    hero,
    landscape({ seed: 3, sky: ['#5d8fc4', '#c9ddee'], layers: ['#6c8a76', '#4b6b56', '#33503d'], forest: '#243a2b' }),
    landscape({ seed: 21, sky: ['#3b3f6b', '#d98f7a'], sun: [0.3, 0.55, 30, '#ffd9b0'], layers: ['#5a4b6e', '#3c3352', '#251f36'], lake: true }),
    landscape({ seed: 8, sky: ['#b9c4c9', '#e4e7e6'], layers: ['#8fa09a', '#6c7f78', '#4f6059'], forest: '#3b4a44' }),
    landscape({ seed: 34, sky: ['#7fb2d9', '#e5eef4'], layers: ['#b9c6d3', '#8aa0b6', '#5d7690'], snow: true, lake: true }),
    landscape({ seed: 5, sky: ['#e7b98f', '#f5dfc4'], layers: ['#b8714c', '#93543a', '#6a3b2a'] }),
    landscape({ seed: 15, sky: ['#0f1a33', '#3a4d73'], sun: [0.78, 0.22, 16, '#f4f1e6'], layers: ['#24314d', '#18223a', '#0e1528'] }),
    landscape({ seed: 27, sky: ['#9cc3e4', '#f0f4f2'], layers: ['#9fb27e', '#7a9160', '#58704a'], forest: '#3e5636' }),
    landscape({ seed: 41, sky: ['#d7a07d', '#f2d1a8'], sun: [0.5, 0.5, 52, '#fff1d6'], layers: ['#8d6a63', '#6a4c4b', '#463335'], lake: true }),
    landscape({ seed: 19, sky: ['#6f8fb3', '#dfe6ec'], layers: ['#a7b3bf', '#7b8a99', '#556373', '#36424f'], snow: true }),
    landscape({ seed: 52, sky: ['#88a9c7', '#d8e2e6'], layers: ['#7d8f6e', '#5d714f', '#405238'], forest: '#2b3a26', lake: true }),
    landscape({ seed: 63, sky: ['#c4cfd8', '#eef0ee'], layers: ['#9aa6a6', '#768585', '#556464'] }),
  ]

  return { hero, library }
})()
