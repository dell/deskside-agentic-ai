/* Turn article sections into tabs.
   Usage: <article data-tabs="Title A|Title B|..."> — each h2 whose text matches
   a title, plus its siblings up to the next h2, becomes a tab panel. */
(function () {
  var art = document.querySelector('article[data-tabs]');
  if (!art) return;
  var titles = art.getAttribute('data-tabs').split('|');
  var bar = document.createElement('div');
  bar.className = 'tabbar';
  var panels = [];
  titles.forEach(function (title) {
    var hs = [].slice.call(art.querySelectorAll('h2')).filter(function (h) {
      return h.textContent.trim() === title;
    });
    if (!hs.length) return;
    var h = hs[0];
    var panel = document.createElement('div');
    panel.className = 'tabpanel';
    art.insertBefore(panel, h);
    var cur = h;
    while (cur && !(cur.tagName === 'H2' && cur !== h)) {
      var next = cur.nextElementSibling;
      panel.appendChild(cur);
      cur = next;
    }
    panels.push({ title: title, panel: panel });
  });
  if (panels.length < 2) return;
  var buttons = panels.map(function (p, i) {
    var b = document.createElement('button');
    b.textContent = p.title;
    b.setAttribute('role', 'tab');
    b.addEventListener('click', function () { select(i); });
    bar.appendChild(b);
    return b;
  });
  function select(i) {
    panels.forEach(function (p, j) { p.panel.hidden = j !== i; });
    buttons.forEach(function (b, j) { b.setAttribute('aria-selected', j === i ? 'true' : 'false'); });
  }
  art.insertBefore(bar, panels[0].panel);
  var initial = 0;
  if (location.hash) {
    var m = panels.findIndex(function (p) {
      var h = p.panel.querySelector('h2');
      return h && h.id === location.hash.slice(1);
    });
    if (m > -1) initial = m;
  }
  select(initial);
})();
