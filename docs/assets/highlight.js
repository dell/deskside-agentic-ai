/* Syntax highlighting for code blocks (bash, json, yaml, toml, python) — no dependencies, works offline.
   Also converts the Recipe Configuration markers (\uE000<kind> ... \uE001) into <mark class="ds-var ds-v-<kind>">.
   window.dsHighlight(text, lang) -> HTML. Auto-runs on every <pre><code class="language-*"> on the page. */
(function () {
  var OPEN = '\uE000', CLOSE = '\uE001';
  function esc(s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
  var MARK = ['[\\uE000][\\s\\S]|\\uE001', null];
  var CMDS = /^(?:curl|docker|nvidia-smi|git|sudo|apt|apt-get|export|ssh|rsync|python3?|pip3?|npm|npx|cd|ls|cat|echo|grep|awk|sed|tar|mkdir|rm|cp|mv|chmod|systemctl|journalctl|ss|df|du|free|until|sleep|source|tee|head|tail|watch|opencode|claude|codex|copilot|aiperf|ollama|hf|huggingface-cli|ansible-playbook|landscape-config|openshell|nemoclaw|nemohermes|hermes|bash|sh|time|env|kill|ps)$/;
  var KW = /^(?:import|from|def|class|return|if|elif|else|for|while|in|not|and|or|is|None|True|False|with|as|try|except|finally|raise|lambda|pass|break|continue|yield|print|assert|global|async|await)$/;
  var LANGS = {
    bash: [
      [MARK[0], 'm'],
      ['(?<![^\\s])#[^\\n]*', 'c'],
      ['"(?:\\\\[\\s\\S]|[^"\\\\])*"', 's'],
      ["'[^']*'", 's'],
      ['\\$\\{[^}\\n]*\\}|\\$\\([^)\\n]*\\)?|\\$[A-Za-z_]\\w*|\\$[0-9?#@*]', 'v'],
      ['(?<![^\\s])--?[A-Za-z][\\w-]*(?=[=\\s]|$)', 'f'],
      ['(?<![^\\s])[A-Za-z_][A-Za-z0-9_]*(?==)', 'v'],
      ['(?<=(?:^|\\n|\\|\\||\\||&&|;)[ \\t]*)[^\\s|&;()<>"\'$=#\\uE000\\uE001]+', function (t) { return CMDS.test(t) || t.indexOf('/') > -1 ? 'fn' : null; }],
      ['(?<![\\w.:/-])\\d+(?:\\.\\d+)?(?![\\w.:/-])', 'n'],
      ['\\|\\||&&|[|;]', 'o']
    ],
    json: [
      [MARK[0], 'm'],
      ['"(?:\\\\.|[^"\\\\])*"(?=\\s*:)', 'k'],
      ['"(?:\\\\.|[^"\\\\])*"', 's'],
      ['-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?', 'n'],
      ['\\b(?:true|false|null)\\b', 'b'],
      ['[{}\\[\\],:]', 'o']
    ],
    yaml: [
      [MARK[0], 'm'],
      ['(?<![^\\s])#[^\\n]*', 'c'],
      ['(?<=(?:^|\\n)[ \\t-]*)[\\w.\\-/]+(?=:(?:\\s|$))', 'k'],
      ['"(?:\\\\.|[^"\\\\])*"', 's'],
      ["'[^']*'", 's'],
      ['(?<=(?:^|\\n)[ \\t]*)-(?=\\s)', 'o'],
      ['(?<![\\w.:/-])-?\\d+(?:\\.\\d+)?(?![\\w.:/-])', 'n'],
      ['\\b(?:true|false|null|yes|no)\\b', 'b']
    ],
    toml: [
      [MARK[0], 'm'],
      ['(?<![^\\s])#[^\\n]*', 'c'],
      ['(?<=(?:^|\\n)[ \\t]*)\\[[^\\]\\n]+\\]', 'f'],
      ['(?<=(?:^|\\n)[ \\t]*)[\\w.\\-]+(?=\\s*=)', 'k'],
      ['"(?:\\\\.|[^"\\\\])*"', 's'],
      ["'[^']*'", 's'],
      ['(?<![\\w.:/-])-?\\d+(?:\\.\\d+)?(?![\\w.:/-])', 'n'],
      ['\\b(?:true|false)\\b', 'b']
    ],
    python: [
      [MARK[0], 'm'],
      ['(?<![^\\s])#[^\\n]*', 'c'],
      ['"""[\\s\\S]*?"""|\'\'\'[\\s\\S]*?\'\'\'', 's'],
      ['"(?:\\\\.|[^"\\\\\\n])*"', 's'],
      ["'(?:\\\\.|[^'\\\\\\n])*'", 's'],
      ['(?<=\\b(?:def|class)\\s+)\\w+', 'fn'],
      ['\\b[A-Za-z_]\\w*\\b', function (t) { return KW.test(t) ? 'kw' : null; }],
      ['(?<![\\w.])\\d+(?:\\.\\d+)?(?![\\w.])', 'n']
    ]
  };
  var ALIAS = { sh: 'bash', shell: 'bash', console: 'bash', zsh: 'bash', yml: 'yaml', py: 'python' };
  var COMPILED = {};
  function rules(lang) {
    if (COMPILED[lang]) return COMPILED[lang];
    return (COMPILED[lang] = LANGS[lang].map(function (r) { return [new RegExp(r[0], 'y'), r[1]]; }));
  }
  function wrap(cls, t) { return cls && cls !== 'm' ? '<span class="tok-' + cls + '">' + esc(t) + '</span>' : esc(t); }
  function tokenize(text, lang) {
    lang = ALIAS[lang] || lang;
    if (!LANGS[lang]) return esc(text);
    var rs = rules(lang), out = '', plain = '', i = 0, n = text.length;
    while (i < n) {
      var hit = false;
      for (var k = 0; k < rs.length; k++) {
        var re = rs[k][0]; re.lastIndex = i;
        var m = re.exec(text);
        if (m && m[0].length) {
          var cls = typeof rs[k][1] === 'function' ? rs[k][1](m[0]) : rs[k][1];
          if (plain) { out += esc(plain); plain = ''; }
          out += cls === 'm' ? m[0] : wrap(cls, m[0]);
          i += m[0].length; hit = true; break;
        }
      }
      if (!hit) { plain += text[i]; i++; }
    }
    return out + esc(plain);
  }
  // markers -> <mark>, closing/reopening around token spans so the HTML stays well-nested
  function marks(html) {
    var cur = null, out = '';
    var re = /\uE000([a-z])|\uE001|<span[^>]*>|<\/span>/g, last = 0, m;
    function open(c) { return '<mark class="ds-var ds-v-' + c + '">'; }
    while ((m = re.exec(html))) {
      out += html.slice(last, m.index); last = re.lastIndex;
      if (m[0][0] === OPEN) { cur = m[1]; out += open(cur); }
      else if (m[0] === CLOSE) { if (cur) out += '</mark>'; cur = null; }
      else if (cur) { out += '</mark>' + m[0] + open(cur); }
      else out += m[0];
    }
    out += html.slice(last);
    return cur ? out + '</mark>' : out;
  }
  function highlight(text, lang) { return marks(tokenize(text, (lang || '').toLowerCase())); }
  window.dsHighlight = highlight;
  window.dsHighlightLang = function (el) {
    var m = /language-([\w+-]+)/.exec((el.getAttribute('class') || '')); return m ? m[1] : '';
  };
  function run() {
    document.querySelectorAll('pre > code').forEach(function (c) {
      var lang = window.dsHighlightLang(c);
      if (!lang || c.dataset.dsHl) return;
      c.dataset.dsHl = '1';
      c.innerHTML = highlight(c.textContent, lang);
    });
  }
  if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run); else run();
  }
  if (typeof module !== 'undefined') module.exports = { highlight: highlight };
})();
