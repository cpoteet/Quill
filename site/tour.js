(function () {
  const dialog = document.getElementById('tour');
  const video = dialog.querySelector('video');

  function open() {
    if (dialog.open) return;
    dialog.showModal();
    video.play().catch(function () {});
  }

  document.querySelectorAll('[data-tour-open]').forEach(function (link) {
    link.addEventListener('click', function (event) {
      event.preventDefault();
      open();
    });
  });

  dialog.querySelector('[data-tour-close]').addEventListener('click', function () {
    dialog.close();
  });

  dialog.addEventListener('click', function (event) {
    if (event.target === dialog) dialog.close();
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
