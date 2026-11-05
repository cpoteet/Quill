(function () {
  const ACTIVE_LINE = 140;
  const SCROLL_IDLE_MS = 150;
  const list = document.querySelector('.toc__list');
  const links = Array.from(document.querySelectorAll('.toc__link'));
  const targets = links.map(function (link) {
    return document.getElementById(decodeURIComponent(link.hash.slice(1)));
  });
  let current = -1;
  let following = true;
  let idleTimer;

  function placeMarker(link, animate) {
    if (!animate) list.classList.add('is-placing');
    list.style.setProperty('--marker-y', link.offsetTop + 'px');
    list.style.setProperty('--marker-h', link.offsetHeight + 'px');
    if (!animate) {
      void list.offsetHeight;
      list.classList.remove('is-placing');
    }
  }

  function setActive(index) {
    if (index === current) return;
    links.forEach(function (link, i) {
      link.classList.toggle('toc__link--active', i === index);
    });
    placeMarker(links[index], current !== -1);
    current = index;
  }

  function update() {
    let active = 0;
    targets.forEach(function (target, i) {
      if (target && target.getBoundingClientRect().top < ACTIVE_LINE) active = i;
    });
    setActive(active);
  }

  function followWhenIdle() {
    clearTimeout(idleTimer);
    idleTimer = setTimeout(function () {
      following = true;
      update();
    }, SCROLL_IDLE_MS);
  }

  function replace() {
    if (current !== -1) placeMarker(links[current], false);
  }

  links.forEach(function (link, i) {
    link.addEventListener('click', function () {
      following = false;
      setActive(i);
      followWhenIdle();
    });
  });

  window.addEventListener('scroll', function () {
    if (following) update();
    else followWhenIdle();
  }, { passive: true });
  window.addEventListener('load', update);
  window.addEventListener('resize', replace);
  document.querySelector('.toc__disclosure').addEventListener('toggle', replace);
  update();
})();
