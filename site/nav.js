(function () {
  const nav = document.querySelector('.nav');
  const toggle = nav.querySelector('.nav__toggle');

  function setOpen(open) {
    nav.classList.toggle('nav--open', open);
    toggle.setAttribute('aria-expanded', String(open));
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
