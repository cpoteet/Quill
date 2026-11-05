(function () {
  const collapseMs = parseFloat(
    getComputedStyle(document.documentElement).getPropertyValue('--acc-collapse')
  ) || 250;

  document.querySelectorAll('details').forEach(function (details) {
    const summary = details.querySelector(':scope > summary');
    const panel = document.createElement('div');
    const inner = document.createElement('div');
    let closeTimer = null;

    panel.className = 't-acc-panel';
    inner.className = 't-acc-panel-inner';
    while (summary.nextSibling) inner.appendChild(summary.nextSibling);
    panel.appendChild(inner);
    details.appendChild(panel);
    details.classList.add('t-acc');
    details.dataset.open = String(details.open);

    function expand() {
      clearTimeout(closeTimer);
      closeTimer = null;
      details.open = true;
      void panel.offsetHeight;
      details.dataset.open = 'true';
    }

    function collapse() {
      details.dataset.open = 'false';
      closeTimer = setTimeout(function () {
        closeTimer = null;
        details.open = false;
      }, collapseMs);
    }

    summary.addEventListener('click', function (event) {
      if (event.defaultPrevented) return;
      event.preventDefault();
      if (details.dataset.open === 'true') collapse();
      else expand();
    });

    details.addEventListener('toggle', function () {
      if (!details.open) details.dataset.open = 'false';
      else if (closeTimer === null && details.dataset.open === 'false') expand();
    });
  });
})();
