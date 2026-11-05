(function () {
  const dialog = document.getElementById('tour');
  const video = dialog.querySelector('video');
  const closeMs = parseFloat(
    getComputedStyle(document.documentElement).getPropertyValue('--modal-close-dur')
  ) || 150;
  let closeTimer;

  function open() {
    if (dialog.open && !dialog.classList.contains('is-closing')) return;
    clearTimeout(closeTimer);
    dialog.classList.remove('is-closing');
    if (!dialog.open) dialog.showModal();
    void dialog.offsetWidth;
    dialog.classList.add('is-open');
    video.play().catch(function () {});
  }

  function close() {
    if (!dialog.open || dialog.classList.contains('is-closing')) return;
    dialog.classList.remove('is-open');
    dialog.classList.add('is-closing');
    closeTimer = setTimeout(function () {
      dialog.classList.remove('is-closing');
      dialog.close();
    }, closeMs);
  }

  document.querySelectorAll('[data-tour-open]').forEach(function (link) {
    link.addEventListener('click', function (event) {
      event.preventDefault();
      open();
    });
  });

  dialog.querySelector('[data-tour-close]').addEventListener('click', close);

  dialog.addEventListener('click', function (event) {
    if (event.target === dialog) close();
  });

  dialog.addEventListener('cancel', function (event) {
    event.preventDefault();
    close();
  });

  dialog.addEventListener('close', function () {
    video.pause();
    if (location.hash === '#tour') history.replaceState(null, '', location.pathname + location.search);
  });

  window.addEventListener('hashchange', function () {
    if (location.hash === '#tour') open();
  });

  if (location.hash === '#tour') open();
})();
