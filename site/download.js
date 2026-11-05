(function () {
  const STARTED = 'Download started';
  const RESET_MS = 4000;
  const root = document.documentElement;
  const ms = function (name) {
    return parseFloat(getComputedStyle(root).getPropertyValue(name)) || 0;
  };

  function morphText(el, next) {
    const prev = el.dataset.text ?? el.textContent;
    if (prev === next) return;
    el.dataset.text = next;
    clearTimeout(el._morphTimer);

    let a = 0;
    while (a < prev.length && a < next.length && prev[a] === next[a]) a++;
    let b = 0;
    while (b < prev.length - a && b < next.length - a &&
           prev[prev.length - 1 - b] === next[next.length - 1 - b]) b++;

    const swap = document.createElement('span');
    swap.className = 't-morph-swap';
    const out = document.createElement('span');
    out.className = 't-morph-old';
    out.setAttribute('aria-hidden', 'true');
    out.textContent = prev.slice(a, prev.length - b);
    const inn = document.createElement('span');
    inn.className = 't-morph-new';
    inn.textContent = next.slice(a, next.length - b);
    swap.append(out, inn);

    el.textContent = '';
    el.append(next.slice(0, a), swap, next.slice(next.length - b));

    swap.style.width = out.getBoundingClientRect().width + 'px';
    void swap.offsetWidth;
    swap.classList.add('is-morphing');
    swap.style.width = inn.getBoundingClientRect().width + 'px';

    el._morphTimer = setTimeout(function () {
      el.textContent = next;
    }, Math.max(ms('--text-morph-dur'), ms('--text-morph-resize-dur')) + 40);
  }

  document.querySelectorAll('[data-download]').forEach(function (button) {
    const original = button.textContent;
    let resetTimer;

    button.addEventListener('click', function () {
      clearTimeout(resetTimer);
      morphText(button, STARTED);
      resetTimer = setTimeout(function () {
        morphText(button, original);
      }, RESET_MS);
    });
  });
})();
