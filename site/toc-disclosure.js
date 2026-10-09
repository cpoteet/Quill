(function () {
  const disclosure = document.querySelector('.toc__disclosure');
  if (!disclosure) return;
  const summary = disclosure.querySelector('summary');
  const count = disclosure.querySelector('.toc__count');
  const narrow = window.matchMedia('(max-width: ' + disclosure.dataset.collapseWidth + 'px)');

  if (count) count.textContent = '(' + disclosure.querySelectorAll('.toc__link').length + ')';

  function sync() {
    disclosure.classList.toggle('toc__disclosure--narrow', narrow.matches);
    disclosure.open = !narrow.matches;
    summary.tabIndex = narrow.matches ? 0 : -1;
  }

  summary.addEventListener('click', function (event) {
    if (!narrow.matches) event.preventDefault();
  });

  disclosure.addEventListener('click', function (event) {
    if (narrow.matches && event.target.closest('.toc__link')) disclosure.open = false;
  });

  narrow.addEventListener('change', sync);
  sync();
})();
