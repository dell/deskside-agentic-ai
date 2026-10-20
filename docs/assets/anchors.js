/* Linkable sections: hovering a heading shows a link icon; clicking the heading copies its URL (with #fragment)
   to the clipboard, updates the address bar and confirms with a short toast. */
(function () {
  var toast;
  function say(msg) {
    if (!toast) { toast = document.createElement('div'); toast.className = 'ds-toast'; document.body.appendChild(toast); }
    toast.textContent = msg; toast.classList.add('on');
    clearTimeout(toast._t); toast._t = setTimeout(function () { toast.classList.remove('on'); }, 1600);
  }
  function copy(text) {
    if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text);
    return new Promise(function (ok, no) {
      var ta = document.createElement('textarea'); ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
      document.body.appendChild(ta); ta.select();
      try { document.execCommand('copy') ? ok() : no(); } catch (e) { no(e); } document.body.removeChild(ta);
    });
  }
  function init() {
    document.querySelectorAll('.article h1[id], .article h2[id], .article h3[id], .article h4[id]').forEach(function (h) {
      if (h.dataset.dsAnchor) return; h.dataset.dsAnchor = '1'; h.classList.add('ds-anchor');
      h.setAttribute('title', 'Click to copy a link to this section');
      h.addEventListener('click', function (e) {
        if (e.target.closest('a')) return;
        var url = location.origin + location.pathname + '#' + h.id;
        history.replaceState(null, '', '#' + h.id);
        copy(url).then(function () { say('Link copied'); }, function () { say(url); });
      });
    });
    if (location.hash) { var t = document.getElementById(decodeURIComponent(location.hash.slice(1))); if (t) t.scrollIntoView(); }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
