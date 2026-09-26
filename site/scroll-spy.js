(function () {
  const ACTIVE_LINE = 140;
  const links = Array.from(document.querySelectorAll('.toc__link'));
  const targets = links.map(function (link) {
    return document.getElementById(decodeURIComponent(link.hash.slice(1)));
  });

  function update() {
    let active = 0;
    targets.forEach(function (target, i) {
      if (target && target.getBoundingClientRect().top < ACTIVE_LINE) active = i;
    });
    links.forEach(function (link, i) {
      link.classList.toggle('toc__link--active', i === active);
    });
  }

  window.addEventListener('scroll', update, { passive: true });
  update();
})();
