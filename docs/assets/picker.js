/* Recipe Configuration — fills the samples on the page with the chosen platform, model, host, port and key.
   Every filled value is highlighted in the colour of the field that controls it. Nothing is sent anywhere.
   Activates on any page whose <article> carries data-picker (needs highlight.js loaded first). */
(function () {
  var art = document.querySelector('article[data-picker]');
  if (!art) return;
  var hl = window.dsHighlight, langOf = window.dsHighlightLang;
  var BASE_PORT = 8000;   // every recipe serves on 8000, counting up when taken (DESKSIDE_BASE_PORT / --port override)

  var NOTES = {
    'nvidia/nemotron-3.5-lightning': 'Reasoning model (--reasoning-parser nemotron_v3), tools via qwen3_coder; keep max_tokens \u2265 512.',
    'nvidia/nemotron-3.5-super-vl': 'Reasoning (nemotron_v3) + tools (qwen3_coder), text/image/video input; keep max_tokens \u2265 512.',
    'qwen3.8-27b': 'Tools via qwen3_coder, reasoning via qwen3, MTP speculative decoding; keep max_tokens \u2265 512.',
    'qwen3.8-flash-next': 'Tools via qwen3_xml, reasoning via qwen3, MTP \u00d73, needs \u2265 128 GB host RAM; keep max_tokens \u2265 512.',
    'glm-5.3-flash': 'Tools via glm47, reasoning via glm45, 262K context; keep max_tokens \u2265 512.'
  };
  var M = {
    lightning: { id: 'nvidia/nemotron-3.5-lightning', name: 'Nemotron 3.5 Lightning NVFP4' },
    supervl: { id: 'nvidia/nemotron-3.5-super-vl', name: 'Nemotron 3.5 Super VL NVFP4' },
    qwen27: { id: 'qwen3.8-27b', name: 'Qwen3.8-27B NVFP4' },
    flash: { id: 'qwen3.8-flash-next', name: 'Qwen3.8-Flash-Next NVFP4' },
    glm: { id: 'glm-5.3-flash', name: 'GLM-5.3-Flash NVFP4' }
  };
  var CLASS = { lightning: 'S/M/L', supervl: 'M/L', qwen27: 'S', flash: 'M', glm: 'L' };   // model tier: the tiers a model is designated for
  function mm(key, recipe, tag) { return { id: M[key].id, key: key, tier: CLASS[key], label: M[key].name + ' [' + CLASS[key] + ']' + (tag ? ' \u00b7 ' + tag : ''), recipe: recipe }; }
  var PLATFORMS = [
    { label: 'S \u2014 Dell Pro Precision with GB10 (DGX Spark class)', dir: 'gb10', key: 'gb10', tier: 'S', models: [
      mm('lightning', 'recipes/gb10/vllm/docker-nemotron-3.5-lightning-nvfp4.sh', 'default'),
      mm('qwen27', 'recipes/gb10/vllm/docker-qwen3.8-27b-nvfp4.sh', 'alternative')] },
    { label: 'S \u2014 Dell Pro Precision 9 T2 (1\u00d7 RTX PRO 6000)', dir: 'precision', key: 't2', tier: 'S', models: [
      mm('lightning', 'recipes/precision/vllm/docker-nemotron-3.5-lightning-nvfp4.sh', 'default'),
      mm('qwen27', 'recipes/gb10/vllm/docker-qwen3.8-27b-nvfp4.sh', 'alternative \u00b7 GPU-pinned')] },
    { label: 'M \u2014 Dell Pro Precision 9 T4 (2\u00d7 RTX PRO 6000)', dir: 'precision', key: 't4', tier: 'M', models: [
      mm('supervl', 'recipes/precision/vllm/docker-nemotron-3.5-super-vl-nvfp4.sh', 'default'),
      mm('lightning', 'recipes/precision/vllm/docker-nemotron-3.5-lightning-nvfp4.sh', 'alternative'),
      mm('flash', 'recipes/precision/vllm/docker-qwen3.8-flash-next-nvfp4.sh', 'alternative'),
      mm('qwen27', 'recipes/gb10/vllm/docker-qwen3.8-27b-nvfp4.sh', 'alternative \u00b7 GPU-pinned')] },
    { label: 'L \u2014 Dell Pro Precision 9 T6 (5\u00d7 RTX PRO 6000)', dir: 'precision', key: 't6', tier: 'L', models: [
      mm('supervl', 'recipes/precision/vllm/docker-nemotron-3.5-super-vl-nvfp4.sh', 'default'),
      mm('lightning', 'recipes/precision/vllm/docker-nemotron-3.5-lightning-nvfp4.sh', 'alternative \u00b7 replicas'),
      mm('flash', 'recipes/precision/vllm/docker-qwen3.8-flash-next-nvfp4.sh', 'alternative'),
      mm('qwen27', 'recipes/gb10/vllm/docker-qwen3.8-27b-nvfp4.sh', 'alternative \u00b7 GPU-pinned')] },
    { label: 'L \u2014 Dell Pro Precision with GB300 (DGX Station class)', dir: 'gb300', key: 'gb300', tier: 'L', models: [
      mm('supervl', 'recipes/gb300/vllm/docker-nemotron-3.5-super-vl-nvfp4.sh', 'default'),
      mm('lightning', 'recipes/gb300/vllm/docker-nemotron-3.5-lightning-nvfp4.sh', 'alternative'),
      mm('glm', 'recipes/gb300/vllm/docker-glm-5.3-flash-nvfp4.sh', 'alternative'),
      mm('flash', 'recipes/precision/vllm/docker-qwen3.8-flash-next-nvfp4.sh', 'alternative'),
      mm('qwen27', 'recipes/gb10/vllm/docker-qwen3.8-27b-nvfp4.sh', 'alternative')] }
  ];
  var IDS = ['qwen3.8-flash-next-nvfp4', 'nvidia/nemotron-3.5-super-vl', 'nemotron-3.5-super-vl', 'nvidia/nemotron-3.5-lightning',
             'glm-5.3-flash-nvfp4', 'nemotron-lightning', 'qwen3.8-flash-next', 'qwen3.8-27b', 'glm-5.3-flash'];
  var LS = 'ds-pick-v2';
  var root = (function () {
    var s = document.currentScript && document.currentScript.src;
    return s ? s.replace(/assets\/picker\.js.*$/, '') : '../../';
  })();
  var OPEN = '\uE000', CLOSE = '\uE001';
  function mk(kind, v) { return OPEN + kind + v + CLOSE; }

  var bar = document.createElement('section');
  bar.className = 'ds-picker';
  bar.innerHTML =
    '<h2>Recipe Configuration <span class="ds-note">(fills the samples below live; nothing is sent anywhere)</span></h2>' +
    '<div class="ds-fields">' +
    '<label class="ds-v-p">Platform / tier<select id="dsPlat"></select></label>' +
    '<label class="ds-v-m">Model<select id="dsModel"></select></label>' +
    '<label class="ds-v-h">Deskside host<input id="dsHost" placeholder="localhost" autocomplete="off" spellcheck="false"></label>' +
    '<label class="ds-v-o">Port<input id="dsPort" inputmode="numeric" autocomplete="off" spellcheck="false"></label>' +
    '<label class="ds-v-k">API key (optional)<input id="dsKey" placeholder="local" autocomplete="off" spellcheck="false"></label>' +
    '</div>' +
    '<p class="ds-legend">Highlighted below where filled: <mark class="ds-var ds-v-p">platform</mark> <mark class="ds-var ds-v-m">model</mark> ' +
    '<mark class="ds-var ds-v-h">host</mark> <mark class="ds-var ds-v-o">port</mark> <mark class="ds-var ds-v-k">key</mark></p>' +
    '<p class="ds-hint" id="dsHint"></p>';
  art.insertBefore(bar, art.firstChild);

  var $ = function (id) { return document.getElementById(id); };
  var plat = $('dsPlat'), model = $('dsModel'), host = $('dsHost'), port = $('dsPort'), key = $('dsKey');
  PLATFORMS.forEach(function (p, i) {
    var o = document.createElement('option'); o.value = i; o.textContent = p.label; plat.appendChild(o);
  });
  function modelOpts(pi) {
    model.innerHTML = '';
    PLATFORMS[pi].models.forEach(function (m, i) {
      var o = document.createElement('option'); o.value = i; o.textContent = m.label; model.appendChild(o);
    });
    model.value = 0;
  }
  var saved = {};
  try { saved = JSON.parse(localStorage.getItem(LS) || '{}'); } catch (e) {}
  plat.value = Math.min(Math.max(+saved.plat | 0, 0), PLATFORMS.length - 1);
  modelOpts(+plat.value);
  model.value = Math.min(Math.max(+saved.model | 0, 0), PLATFORMS[+plat.value].models.length - 1);
  host.value = saved.host || ''; port.value = saved.port || ''; key.value = saved.key || '';

  function activePlat() { return PLATFORMS[+plat.value]; }
  function active() { return activePlat().models[+model.value]; }
  function curPort() { var p = +port.value | 0; return p >= 1024 && p <= 65535 ? p : BASE_PORT; }
  var idRe = new RegExp('(?<![\\w./-])(' + IDS.map(function (s) { return s.replace(/[.*+?^${}()|[\]\\\/]/g, '\\$&'); }).join('|') + ')(?![\\w-]|\\.sh)', 'g');
  var hostRe = /(https?:\/\/)?(localhost|<(?:host|deskside-host)>)(?::(\d{2,5}))?/g;
  var keyRe = /((?:API_KEY|api_key|apiKey|AUTH_TOKEN)["']?\s*[:=]\s*["']?)local\b/g;
  var recipeRe = /(?<!\uE000p)recipes\/(?:gb10|precision|gb300)\/vllm\/docker-[\w.\-]+\.sh/g;

  function fillText(t) {
    var p = curPort(), a = active(), k = key.value.trim() || 'local', h = host.value.trim() || 'localhost';
    t = t.replace(hostRe, function (all, proto, tok, prt) {
      if (prt !== undefined && !/^80\d\d$/.test(prt)) return (proto || '') + mk('h', h) + ':' + prt;
      if (prt === undefined && !proto) return mk('h', h);
      return (proto || '') + mk('h', h) + ':' + mk('o', p);
    });
    t = t.replace(/(--port[= ]+)80\d\d/g, function (all, pre) { return pre + mk('o', p); });
    t = t.replace(idRe, function () { return mk('m', a.id); });
    t = t.replace(keyRe, function (all, pre) { return pre + mk('k', k); });
    t = t.replace(/recipes\/<platform>\/vllm\/docker-[\w.\-]+\.sh/g, function () { return mk('p', a.recipe); });
    t = t.replace(/<platform>/g, mk('p', activePlat().dir));
    t = t.replace(/(\btier:\s*')[SML](')/g, function (all, a, b) { return a + mk('p', activePlat().tier) + b; });
    t = t.replace(/(\bhost:\s*')deskside-[sml]\d(')/g, function (all, a, b) {
      return a + mk('h', host.value.trim() || ('deskside-' + activePlat().tier.toLowerCase() + '1')) + b; });
    t = t.replace(recipeRe, function (r) { return r === a.recipe ? mk('p', r) : r; });
    return t;
  }
  function fill(el, isPre) {
    if (el.dataset.dsText === undefined) el.dataset.dsText = el.textContent;
    var filled = fillText(el.dataset.dsText);
    el.innerHTML = hl(filled, isPre ? langOf(el) : '');
  }
  var MEASURED = null, mUrl = root + 'assets/measured.json';
  var SHAPE = { chat_200_200: 'Chat (200 in / 200 out)', agent_60k_1k: 'Agentic coding (60k in / 1k out)', rag_6400_100: 'RAG (6.4k in / 100 out)' };
  function atFloor(pts, floor) {            // concurrency where per-session tok/s falls to the floor (log-linear interpolation)
    if (!pts.length || pts[0].per < floor) return { none: true };
    for (var i = 0; i < pts.length - 1; i++) {
      if (pts[i].per >= floor && pts[i + 1].per < floor) {
        var f = (pts[i].per - floor) / (pts[i].per - pts[i + 1].per);
        return { c: Math.exp(Math.log(pts[i].c) + f * (Math.log(pts[i + 1].c) - Math.log(pts[i].c))) };
      }
    }
    return { c: pts[pts.length - 1].c, open: true };
  }
  function sess(r) { return r.none ? '\u2014' : (r.open ? '\u2265 ' : '\u2248 ') + Math.round(r.c); }
  function renderMeasured() {
    var boxes = art.querySelectorAll('.ds-measured');
    if (!boxes.length) return;
    if (MEASURED === null) {
      MEASURED = [];
      fetch(mUrl).then(function (r) { return r.json(); }).then(function (d) { MEASURED = d; renderMeasured(); }).catch(function () { MEASURED = []; });
      return;
    }
    var a = active(), pk = activePlat().key;
    var rows = MEASURED.filter(function (e) { return e.platform === pk && e.model === a.id; });
    var html = '<h4>Measured scaling \u2014 ' + activePlat().label.replace(/^[SML] \u2014 /, '') + ' \u00b7 ' + a.label.split(' [')[0] + '</h4>';
    if (!rows.length) {
      var have = MEASURED.filter(function (e) { return e.platform === pk; }).map(function (e) { return e.model; });
      html += '<p>No measured ladder for this exact platform and model yet.' +
        (have.length ? ' Measured on this platform: ' + have.filter(function (x, i) { return have.indexOf(x) === i; }).join(', ') + '.' : '') + '</p>';
    }
    rows.forEach(function (e) {
      html += '<p class="ds-m-cap"><b>' + (SHAPE[e.shape] || e.shape) + '</b> \u00b7 ' + e.topology + ' \u00b7 ' + e.run + (e.source === 'imported' ? ' (imported)' : '') + '</p>' +
        '<table class="ds-m"><thead><tr><th>Concurrent sessions</th><th>Per-session output tok/s</th><th>Aggregate output tok/s</th><th>TTFT (ms)</th></tr></thead><tbody>';
      e.points.forEach(function (p) {
        html += '<tr' + (p.per < 20 ? ' class="below"' : '') + '><td>' + p.c + '</td><td>' + p.per + '</td><td>' + p.agg + '</td><td>' + (p.ttft === null ? '\u2014' : p.ttft) + '</td></tr>';
      });
      var f20 = atFloor(e.points, 20), f10 = atFloor(e.points, 10);
      html += '</tbody></table><p class="ds-m-dev">Usable concurrent sessions \u2014 <b>\u226520</b> tok/s/session: ' + sess(f20) + ' \u00b7 <b>\u226510</b> tok/s/session: ' + sess(f10) + '.</p>';
    });
    boxes.forEach(function (b) { b.innerHTML = html; });
  }
  function apply() {
    art.querySelectorAll('pre > code').forEach(function (c) { fill(c, true); });
    art.querySelectorAll('code').forEach(function (c) {
      if (!c.closest('pre') && !c.closest('.ds-picker')) fill(c, false);
    });
    var a = active();
    port.placeholder = String(BASE_PORT);
    $('dsHint').innerHTML = 'Recipe: <a href="' + root + a.recipe + '">' + a.recipe + '</a> \u00b7 served id <code>' + a.id +
      '</code> \u00b7 platform tier <b>' + activePlat().tier + '</b> \u00b7 model tier <b>' + a.tier + '</b> \u00b7 http://' + (host.value.trim() || 'localhost') + ':' + curPort() + '/v1 \u2014 ' + NOTES[a.id];
    renderMeasured();
    try {
      localStorage.setItem(LS, JSON.stringify({ plat: +plat.value, model: +model.value, host: host.value, port: port.value, key: key.value }));
    } catch (e) {}
  }
  plat.addEventListener('change', function () { modelOpts(+plat.value); apply(); });
  model.addEventListener('change', apply);
  [host, port, key].forEach(function (i) { i.addEventListener('input', apply); });
  apply();
})();
