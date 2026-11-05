(function () {
  const nav = document.querySelector('.nav');
  const toggle = nav.querySelector('.nav__toggle');
  const links = nav.querySelector('.nav__links');
  const label = toggle.querySelector('.t-text-swap');
  const rootStyle = getComputedStyle(document.documentElement);
  const closeMs = parseFloat(rootStyle.getPropertyValue('--dropdown-close-dur')) || 150;
  const swapMs = parseFloat(rootStyle.getPropertyValue('--text-swap-dur')) || 150;
  let closeTimer;
  let swapTimer;

  function swapLabel(next) {
    clearTimeout(swapTimer);
    label.classList.add('is-exit');
    swapTimer = setTimeout(function () {
      label.textContent = next;
      label.classList.remove('is-exit');
      label.classList.add('is-enter-start');
      void label.offsetHeight;
      label.classList.remove('is-enter-start');
    }, swapMs);
  }

  function setOpen(open) {
    if (open === nav.classList.contains('nav--open')) return;
    clearTimeout(closeTimer);
    nav.classList.toggle('nav--open', open);
    toggle.setAttribute('aria-expanded', String(open));
    swapLabel(open ? 'Close' : 'Menu');
    if (open) {
      links.classList.remove('is-closing');
      void links.offsetWidth;
      links.classList.add('is-open');
    } else {
      links.classList.remove('is-open');
      links.classList.add('is-closing');
      closeTimer = setTimeout(function () {
        links.classList.remove('is-closing');
      }, closeMs);
    }
  }

  toggle.addEventListener('click', function () {
    setOpen(!nav.classList.contains('nav--open'));
  });

  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape' && nav.classList.contains('nav--open')) {
      setOpen(false);
      toggle.focus();
    }
  });

  document.addEventListener('click', function (event) {
    if (!nav.contains(event.target)) setOpen(false);
  });
})();
