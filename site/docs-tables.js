(function () {
  document.querySelectorAll('.docs-table').forEach(function (table) {
    const labels = Array.from(table.querySelectorAll('thead th')).map(function (th) {
      return th.textContent;
    });

    table.setAttribute('role', 'table');
    table.querySelectorAll('thead, tbody').forEach(function (group) {
      group.setAttribute('role', 'rowgroup');
    });
    table.querySelectorAll('tr').forEach(function (row) {
      row.setAttribute('role', 'row');
    });
    table.querySelectorAll('th').forEach(function (th) {
      th.setAttribute('role', 'columnheader');
    });
    table.querySelectorAll('tbody tr').forEach(function (row) {
      Array.from(row.cells).forEach(function (cell, i) {
        cell.setAttribute('role', 'cell');
        cell.dataset.label = labels[i];
      });
    });
  });
})();
