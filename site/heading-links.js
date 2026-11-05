(function () {
  if (!navigator.clipboard) return;

  const RESET_MS = 1500;
  const ICONS =
    '<span class="t-icon" data-icon="a"><svg viewBox="0 0 16 16" aria-hidden="true">' +
    '<path d="M6.5 9.5l3-3"/><path d="M7.25 4.75l1-1a2.5 2.5 0 0 1 3.5 3.5l-1 1"/><path d="M8.75 11.25l-1 1a2.5 2.5 0 0 1-3.5-3.5l1-1"/>' +
    '</svg></span>' +
    '<span class="t-icon" data-icon="b"><svg viewBox="0 0 16 16" aria-hidden="true"><path d="M3.5 8.5l3 3 6-7"/></svg></span>';

  const status = document.createElement('p');
  status.className = 'visually-hidden';
  status.setAttribute('role', 'status');
  document.body.appendChild(status);

  function anchorFor(heading) {
    if (heading.id) return heading.id;
    if (heading.matches('h2')) {
      const owner = heading.closest('[id]');
      if (owner && owner.querySelector('h2') === heading) return owner.id;
    }
    return '';
  }

  document.querySelectorAll('.docs-h2, .docs-h3, .docs-h4, .release__version').forEach(function (heading) {
    const id = anchorFor(heading);
    if (!id) return;

    const label = 'Copy link to ' + heading.textContent.trim();
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'heading-link t-icon-swap';
    button.dataset.state = 'a';
    button.setAttribute('aria-label', label);
    button.innerHTML = ICONS;
    heading.appendChild(button);

    let resetTimer;
    button.addEventListener('click', function () {
      const url = location.origin + location.pathname + '#' + encodeURIComponent(id);
      navigator.clipboard.writeText(url).then(function () {
        clearTimeout(resetTimer);
        button.dataset.state = 'b';
        status.textContent = 'Link copied';
        resetTimer = setTimeout(function () {
          button.dataset.state = 'a';
          status.textContent = '';
        }, RESET_MS);
      }).catch(function () {});
    });
  });
})();
