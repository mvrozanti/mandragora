(function () {
  "use strict";

  var C = window.StatusCore;
  var STEP = 300;
  var POLL_MS = 60000;
  var TIMEOUT_MS = 8000;
  var RANGES = { "1h": 12, "6h": 72, "24h": 288 };
  var MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  var GLYPH = { o: "✓", w: "!", d: "✗", b: "?", ".": "·" };
  var WORD = { o: "up", w: "slow", d: "down", b: "unread", ".": "no data" };
  var DOT = { o: "ok", w: "warn", d: "down", b: "unknown", ".": "unknown" };

  var main = document.getElementById("main");
  var data = { status: null, pull: null, probes: null, vps: null, offset: 0, err: {}, at: {} };
  var ui = { range: "24h", hostsOpen: false, cur: null, held: false, collapsed: {}, narrow: null };
  var M = null;
  var timer = null;

  function esc(v) {
    return String(v).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function pad(n) { return (n < 10 ? "0" : "") + n; }
  function clock(t) { var d = new Date(t * 1000); return pad(d.getHours()) + ":" + pad(d.getMinutes()); }
  function stamp(t) { var d = new Date(t * 1000); return d.getDate() + " " + MON[d.getMonth()] + " " + clock(t); }
  function nowSec() { return Date.now() / 1000 + data.offset; }

  function getJSON(url) {
    var ctl = typeof AbortController === "function" ? new AbortController() : null;
    var t = ctl ? setTimeout(function () { ctl.abort(); }, TIMEOUT_MS) : null;
    return fetch(url, { cache: "no-store", credentials: "same-origin", signal: ctl ? ctl.signal : undefined })
      .then(function (r) {
        if (!r.ok) throw new Error("HTTP " + r.status);
        var date = r.headers.get("Date");
        return r.json().then(function (json) { return { json: json, date: date ? Date.parse(date) / 1000 : null }; });
      })
      .then(function (v) { if (t) clearTimeout(t); return { ok: true, v: v }; },
            function (e) { if (t) clearTimeout(t); return { ok: false, e: e && e.name === "AbortError" ? "timed out" : (e && e.message) || "failed" }; });
  }

  function validStatus(s) {
    return s && s.v === 1 && typeof s.generated === "number" && s.hosts && typeof s.hosts === "object";
  }

  function refresh() {
    return Promise.all([
      getJSON("/data/status.json"),
      getJSON("/data/pull.json"),
      getJSON("/api/status-probes"),
      getJSON("/api/vps")
    ]).then(function (r) {
      var stamped = r.filter(function (x) { return x.ok && x.v.date; })[0];
      if (r[0].ok && r[0].v.date) data.offset = r[0].v.date - Date.now() / 1000;
      else if (stamped) data.offset = stamped.v.date - Date.now() / 1000;
      if (r[0].ok && validStatus(r[0].v.json)) { data.status = r[0].v.json; data.err.status = null; }
      else data.err.status = r[0].ok ? "unreadable" : r[0].e;
      data.pull = r[1].ok ? r[1].v.json : null;
      data.err.pull = r[1].ok ? null : r[1].e;
      data.probes = r[2].ok && r[2].v.json && r[2].v.json.hosts ? r[2].v.json : null;
      data.err.probes = data.probes ? null : (r[2].ok ? "unreadable" : r[2].e);
      data.vps = r[3].ok && r[3].v.json ? r[3].v.json : null;
      data.err.vps = data.vps && (data.vps.cpu || data.vps.disk) ? null : (r[3].ok ? "no readings" : r[3].e);
      if (data.err.vps) data.vps = null;
      build();
      render();
    }).catch(function (e) {
      main.innerHTML = '<p class="mv-empty">status could not be drawn: ' + esc(e.message || e) + "</p>";
    });
  }

  function hostSource(src) {
    if (!src || !src.hosts) return null;
    return { start: src.start, step: src.step || STEP, hosts: C.applyBlind(src.hosts) };
  }

  function liveSource(p) {
    if (!p || !p.hosts) return null;
    var hosts = {};
    Object.keys(p.hosts).forEach(function (h) { hosts[h] = String(p.hosts[h].states || ""); });
    return { start: p.start, step: p.step || STEP, hosts: C.applyBlind(hosts) };
  }

  function factOf(host, key) {
    var f = (host && host.facts || []).filter(function (x) { return x.key === key; })[0];
    return f ? f.value : null;
  }

  function build() {
    var s = data.status;
    var now = nowSec();
    var desk = s ? hostSource(s.probes) : null;
    var live = liveSource(data.probes);
    var merged = C.merge(desk, live, STEP);
    var nowMap = C.nowStates(data.probes && data.probes.hosts, desk);
    var census = C.census(nowMap);
    var fresh = C.freshness(s ? now : null, s ? s.generated : null, s ? s.period : 60);
    var pull = C.pullState(data.pull);
    var deskHost = s && s.hosts.desk;
    var deskUptime = factOf(deskHost, "uptime");
    if (deskUptime != null && fresh.age != null) deskUptime += fresh.age;
    var verdict = C.verdict({
      census: census, fresh: fresh, pull: pull, now: now,
      deskUptime: fresh.state === "fresh" || fresh.state === "stale" ? deskUptime : null,
      probesLive: !!data.probes, vpsLive: !!data.vps,
      hot: deskHost ? C.hottest(C.cardSeries(deskHost)) : null
    });
    var ends = [];
    if (s && s.end) ends.push(s.end);
    if (merged.end != null) ends.push(merged.end);
    var wEnd = C.align(ends.length ? Math.max.apply(null, ends) : now, STEP);
    var meta = {};
    if (data.probes) Object.keys(data.probes.hosts).forEach(function (h) { meta[h] = data.probes.hosts[h]; });
    var names = {};
    Object.keys(merged.hosts).forEach(function (h) { names[h] = true; });
    Object.keys(nowMap).forEach(function (h) { names[h] = true; });
    var order = { desk: 0, vps: 1, edge: 2 };
    var hostList = Object.keys(names).sort(function (a, b) {
      var wa = meta[a] ? order[meta[a].where] : 3;
      var wb = meta[b] ? order[meta[b].where] : 3;
      if (wa == null) wa = 3;
      if (wb == null) wb = 3;
      return wa - wb || (a < b ? -1 : 1);
    });
    var machines = s ? Object.keys(s.hosts) : [];
    if (machines.indexOf("vps") < 0 && data.vps) machines.push("vps");
    M = { s: s, now: now, merged: merged, nowMap: nowMap, census: census, fresh: fresh, pull: pull, verdict: verdict, wEnd: wEnd, meta: meta, hosts: hostList, machines: machines };
    if (ui.cur != null && ui.cur > wEnd) { ui.cur = null; ui.held = false; }
  }

  function windowN() { return RANGES[ui.range]; }
  function tOf(k) { return M.wEnd - (windowN() - 1 - k) * STEP; }
  function kOf(t) { return Math.round((t - M.wEnd) / STEP) + windowN() - 1; }

  function valueAt(series, t) {
    var s = M.s;
    if (!s || !series || !series.values) return null;
    var i = Math.round((t - s.start) / (s.step || STEP));
    if (i < 0 || i >= series.values.length) return null;
    return series.values[i];
  }

  function cellAt(h, t) {
    var m = M.merged;
    if (m.start == null || !m.hosts[h]) return ".";
    var i = Math.round((t - m.start) / m.step);
    if (i < 0 || i >= m.hosts[h].length) return ".";
    return m.hosts[h].charAt(i) || ".";
  }

  function columnAt(t) {
    var r = { o: 0, w: 0, d: 0, b: 0, ".": 0 };
    M.hosts.forEach(function (h) { r[cellAt(h, t)]++; });
    return r;
  }

  function isNowT(t) { return t >= M.wEnd; }

  function hostCountAt(t) {
    if (isNowT(t)) {
      var c = M.census;
      return { blind: c.blind, down: c.down, answering: c.ok + c.warn, total: c.total };
    }
    var col = columnAt(t);
    return { blind: col.b, down: col.d, answering: col.o + col.w, total: M.hosts.length, known: col.o + col.w + col.d };
  }

  function meterScale(series) {
    if (series.unit === "%") return Math.max(100, series.crit || 0);
    return series.crit ? series.crit * 1.15 : null;
  }

  function meterHTML(series, v, live) {
    var hi = meterScale(series);
    var p = hi && v != null ? Math.max(0, Math.min(100, v * 100 / hi)) : 0;
    var lv = C.level(series, v);
    var cls = lv === "crit" ? " is-critical" : lv === "warn" ? " is-warn" : "";
    return '<div class="mv-meter st-meter' + cls + '" title="' + esc(series.label) + (live ? " · live" : "") + '"><span class="mv-meter__label">' + esc(series.label) + '</span><span class="mv-meter__track"><i class="mv-meter__fill" style="width:' + p.toFixed(1) + '%"></i></span><span class="mv-meter__value">' + C.fmtValue(series.unit, v) + "</span></div>";
  }

  function pillHTML(machine) {
    var f = M.fresh.state;
    if (machine === "vps") {
      if (data.vps) return '<span class="mv-pill is-ok">live</span>';
      if (M.s && M.s.hosts.vps) return '<span class="mv-pill' + (f === "fresh" ? " is-ok" : " is-warn") + '">from snapshot</span>';
      return '<span class="mv-pill is-down">no data</span>';
    }
    if (f === "silent" || f === "missing") return '<span class="mv-pill is-down">silent</span>';
    if (f === "stale") return '<span class="mv-pill is-warn">stale</span>';
    var up = factOf(M.s.hosts[machine], "uptime");
    if (machine === "desk" && up != null && up + (M.fresh.age || 0) < 900) return '<span class="mv-pill is-warn">restarted</span>';
    return '<span class="mv-pill is-ok">up</span>';
  }

  function factsHTML(host) {
    var facts = (host && host.facts) || [];
    var parts = facts.map(function (f) {
      var v = f.value;
      if (f.key === "uptime" && v != null && M.fresh.age != null && M.fresh.state !== "silent") v += M.fresh.age;
      return esc(f.label) + " <b>" + C.fmtValue(f.unit, v) + "</b>";
    });
    return parts.join(" · ");
  }

  function freshHTML() {
    var f = M.fresh;
    var p = M.pull;
    var since = p.unreachable ? (p.since != null ? " The VPS has failed to reach the desktop since " + stamp(p.since) + "." : " The VPS has not reached the desktop yet.") : "";
    if (f.state === "fresh") return '<p class="st-fresh is-fresh"><i class="mv-dot is-ok"></i><span>updated ' + C.duration(f.age) + " ago · pulled every " + ((M.s.period || 60) === 60 ? "minute" : C.duration(M.s.period)) + " · data to " + clock(M.s.end) + "</span></p>";
    if (f.state === "stale") return '<p class="st-fresh is-stale"><i class="mv-dot is-warn"></i><span><b>Stale.</b> Last snapshot ' + C.duration(f.age) + " ago, " + f.missed + " pulls missed. Desktop figures stop at " + clock(M.s.end) + "." + since + "</span></p>";
    if (f.state === "silent") return '<p class="st-fresh is-silent"><i class="mv-dot is-down"></i><span><b>The desktop has gone silent.</b> No snapshot for ' + C.duration(f.age) + ". Desktop figures stop at " + clock(M.s.end) + "; the VPS card and host probes are live from the VPS." + since + "</span></p>";
    return '<p class="st-fresh is-silent"><i class="mv-dot is-down"></i><span><b>No desktop snapshot.</b> ' + esc(data.err.status || "not published yet") + ". The VPS card and host probes are live from the VPS." + since + "</span></p>";
  }

  function sourcesHTML() {
    var items = [
      ["desktop snapshot", !data.err.status, data.err.status],
      ["vps probes", !data.err.probes, data.err.probes ? "now-state falls back to the desktop's last round" : null],
      ["vps stats", !data.err.vps, data.err.vps ? "vps card shows the snapshot" : null],
      ["puller", !data.err.pull, data.err.pull]
    ];
    return '<p class="st-sources">' + items.map(function (x) {
      return '<span title="' + esc(x[2] || "answering") + '"><i class="mv-dot is-' + (x[1] ? "ok" : "down") + '"></i>' + x[0] + (x[1] ? "" : " · " + esc(x[2] || "unavailable")) + "</span>";
    }).join("") + "</p>";
  }

  function heldTag(t, withButton) {
    if (isNowT(t)) return "";
    return '<span class="st-when">at ' + clock(t) + "</span>" + (withButton ? '<button class="st-now" data-now>back to now</button>' : "");
  }

  function toggleHTML(g) {
    var closed = !!ui.collapsed[g];
    return '<button class="st-toggle" data-toggle="' + g + '" aria-expanded="' + !closed + '">' + (closed ? "rows ▾" : "hide ▴") + "</button>";
  }

  function statusCardHTML(t) {
    var v = isNowT(t) ? M.verdict : pastVerdict(t);
    var hc = hostCountAt(t);
    var hostsPill = hc.blind ? '<span class="mv-pill">blind</span>' : '<span class="mv-pill ' + (hc.down ? "is-down" : "is-ok") + '">' + hc.answering + "/" + hc.total + "</span>";
    var pills = M.machines.map(function (m) {
      var label = M.s && M.s.hosts[m] ? M.s.hosts[m].label : m === "vps" ? "mandragora-vps" : m;
      return '<span class="mv-label">' + esc(label) + "</span>" + pillHTML(m);
    }).join("");
    return '<div class="st-card st-verdict' + (isNowT(t) ? "" : " is-past") + '"><div class="st-card__top"><i class="mv-dot is-' + v.level + '"></i><h1 class="st-head">' + esc(v.head) + "</h1>" + heldTag(t, true) + toggleHTML("svc") + "</div>" +
      '<p class="st-detail">' + esc(v.detail) + "</p>" + freshHTML() +
      '<div class="st-pills">' + pills + '<span class="mv-label">hosts</span>' + hostsPill + "</div>" + sourcesHTML() + "</div>";
  }

  function pastVerdict(t) {
    var col = {};
    M.hosts.forEach(function (h) { col[h] = cellAt(h, t); });
    var c = C.census(col);
    var v = C.verdict({ census: c, fresh: { state: "fresh", age: 0, missed: 0 }, vpsLive: true });
    if (!c.total || c.none === c.total) return { level: "unknown", head: "No probe data at " + clock(t), detail: "Neither prober has a reading for this round." };
    return v;
  }

  function machineCardHTML(m, t) {
    var host = M.s && M.s.hosts[m];
    var label = host ? host.label : m === "vps" ? "mandragora-vps" : m;
    var nowT = isNowT(t);
    var meters = "";
    var cards = host ? C.cardSeries(host) : [];
    if (m === "vps" && data.vps && nowT) {
      var cpuSeries = (host && host.series || []).filter(function (s) { return s.key === "cpu"; })[0] || { key: "cpu", label: "cpu", unit: "%", warn: 50, crit: 85 };
      if (data.vps.cpu) meters += meterHTML(cpuSeries, data.vps.cpu.util_pct, true);
      if (data.vps.disk) meters += meterHTML({ key: "root", label: "root disk", unit: "%", warn: 70, crit: 90 }, data.vps.disk.used_pct, true);
      cards = cards.filter(function (s) { return s.key !== "cpu" || !data.vps.cpu; });
    }
    var snapOnly = M.fresh.state === "silent" || M.fresh.state === "missing";
    meters += cards.map(function (s) { return meterHTML(s, valueAt(s, nowT ? M.s && M.s.end : t)); }).join("");
    if (!meters) meters = '<p class="st-note">no readings</p>';
    var disk = m === "vps" && data.vps && data.vps.disk ? " · root <b>" + data.vps.disk.used_gb.toFixed(0) + " of " + data.vps.disk.total_gb.toFixed(0) + " GB</b>" : "";
    var dimmed = snapOnly && !(m === "vps" && data.vps) ? " is-dim" : "";
    return '<div class="st-card' + (nowT ? "" : " is-past") + dimmed + '" data-card="' + esc(m) + '"><div class="st-card__top"><span class="st-name c-' + esc(m) + '">' + esc(label) + "</span>" + pillHTML(m) + heldTag(t) + toggleHTML(m) + "</div>" +
      '<div class="st-meters">' + meters + "</div>" + '<p class="st-note">' + factsHTML(host) + disk + "</p></div>";
  }

  function sparkSVG(series, o) {
    var W = 600, H = 38, n = series[0].length;
    var lo = 0, hi = o.max;
    if (hi == null) {
      hi = 1e-9;
      series.forEach(function (s) { s.forEach(function (v) { if (v != null && v > hi) hi = v; }); });
      hi *= 1.08;
    }
    function X(j) { return n <= 1 ? W : j * W / (n - 1); }
    function Y(v) { return H - 1 - (Math.max(lo, Math.min(hi, v)) - lo) / (hi - lo) * (H - 2); }
    var paths = "";
    series.forEach(function (arr, si) {
      var line = "", area = "", seg = [];
      function flush() {
        if (seg.length > 1) {
          var pts = seg.map(function (p) { return p[0].toFixed(1) + " " + p[1].toFixed(1); }).join("L");
          line += "M" + pts;
          area += "M" + seg[0][0].toFixed(1) + " " + H + "L" + pts + "L" + seg[seg.length - 1][0].toFixed(1) + " " + H + "Z";
        } else if (seg.length === 1) {
          line += "M" + (seg[0][0] - 1).toFixed(1) + " " + seg[0][1].toFixed(1) + "L" + (seg[0][0] + 1).toFixed(1) + " " + seg[0][1].toFixed(1);
        }
        seg = [];
      }
      arr.forEach(function (v, j) { if (v == null) flush(); else seg.push([X(j), Y(v)]); });
      flush();
      if (si === 0) paths += '<path class="a" d="' + area + '"/>';
      paths += '<path class="' + (si === 0 ? "l" : "l2") + '" d="' + line + '"/>';
    });
    var bands = (o.bands || []).map(function (b) {
      return '<rect class="bd-' + b.kind + '" x="' + (b.a * W).toFixed(1) + '" y="0" width="' + Math.max(1.5, (b.b - b.a) * W).toFixed(1) + '" height="' + H + '"/>';
    }).join("");
    if (o.warn != null && hi > o.warn) paths += '<path class="th" d="M0 ' + Y(o.warn).toFixed(1) + "L" + W + " " + Y(o.warn).toFixed(1) + '"/>';
    return '<svg class="mv-spark" viewBox="0 0 ' + W + " " + H + '" preserveAspectRatio="none" aria-hidden="true">' + bands + paths + "</svg>";
  }

  function events() {
    var n = windowN();
    var out = [];
    var run = null;
    for (var k = 0; k < n; k++) {
      var col = columnAt(tOf(k));
      var kind = col.b ? "blind" : col.d ? "down" : null;
      var cnt = col.b || col.d;
      if (run && kind === run.kind && cnt === run.n && k === run.k2 + 1) { run.k2 = k; continue; }
      run = kind ? { k: k, k2: k, kind: kind, n: cnt } : null;
      if (run) out.push(run);
    }
    if (M.s) {
      Object.keys(M.s.hosts).forEach(function (m) {
        var up = factOf(M.s.hosts[m], "uptime");
        if (up == null) return;
        var k = kOf(C.align(M.s.generated - up, STEP));
        if (k >= 0 && k < n) out.push({ k: k, k2: k, kind: "restart", m: m, label: M.s.hosts[m].label });
      });
    }
    return out;
  }

  function bandsFor(evs, kinds) {
    var den = Math.max(1, windowN() - 1);
    return evs.filter(function (e) { return kinds[e.kind]; }).map(function (e) {
      return { a: Math.max(0, (e.k - 0.5) / den), b: Math.min(1, (e.k2 + 0.5) / den), kind: e.kind };
    });
  }

  function annotationsHTML(evs) {
    var den = Math.max(1, windowN() - 1);
    var plotW = Math.max(200, main.clientWidth - (ui.narrow ? 0 : 20 * 16 + 24));
    var marks = evs.map(function (e) {
      var span = e.k2 > e.k ? " · " + C.duration((e.k2 - e.k + 1) * STEP) : "";
      var lab = (e.kind === "blind" ? "prober blind" : e.kind === "down" ? e.n + " down" : esc(e.label) + " restart") + span;
      return { f: e.k / den, lab: lab, cls: e.kind === "down" ? "st-down" : "st-ghost" };
    }).sort(function (a, b) { return a.f - b.f; });
    var lanes = [], html = "";
    marks.forEach(function (m) {
      var lane = 0;
      var w = m.lab.length * 6.6 + 8;
      while (lanes[lane] != null && (m.f - lanes[lane].f) * plotW < (lanes[lane].w + w) / 2) lane++;
      lanes[lane] = { f: m.f, w: w };
      html += '<span class="sc-ann ' + m.cls + '" style="left:' + (m.f * 100).toFixed(2) + "%;top:" + lane * 14 + 'px">' + m.lab + "</span>";
    });
    return { html: html, h: Math.max(14, lanes.length * 14 + 2) };
  }

  function ticksHTML() {
    var n = windowN(), den = Math.max(1, n - 1);
    var every = n >= 288 ? 10800 : n >= 72 ? 3600 : 600;
    var html = "";
    for (var k = 0; k < n; k++) {
      var t = tOf(k), d = new Date(t * 1000);
      var secs = d.getHours() * 3600 + d.getMinutes() * 60;
      if (secs % every !== 0) continue;
      var f = k / den;
      var lab = d.getHours() === 0 && every >= 3600 ? d.getDate() + " " + MON[d.getMonth()] : clock(t);
      html += '<span class="sc-tick" style="left:' + (f * 100).toFixed(2) + "%;transform:translateX(" + (f < 0.04 ? "0" : f > 0.96 ? "-100%" : "-50%") + ')">' + lab + "</span>";
    }
    return html;
  }

  function barsSVG(h) {
    var n = windowN(), r = "", k = 0, cells = [];
    for (var j = 0; j < n; j++) cells.push(cellAt(h, tOf(j)));
    var Y = { o: 0, w: 0, d: 0, b: 3, ".": 4.5 }, HH = { o: 10, w: 10, d: 10, b: 4, ".": 1 };
    var CLS = { o: "ok", w: "warn", d: "down", b: "blind", ".": "none" };
    while (k < n) {
      var e = k;
      while (e + 1 < n && cells[e + 1] === cells[k]) e++;
      r += '<rect class="bar-' + CLS[cells[k]] + '" x="' + k + '" y="' + Y[cells[k]] + '" width="' + (e - k + 1) + '" height="' + HH[cells[k]] + '"/>';
      k = e + 1;
    }
    return '<svg class="mv-bars" viewBox="0 0 ' + n + ' 10" preserveAspectRatio="none" aria-hidden="true">' + r + "</svg>";
  }

  function hostValHTML(t) {
    var c = hostCountAt(t);
    if (!c.total) return '<span class="st-ghost">no probes</span>';
    if (c.blind) return '<span class="st-ghost">? blind · ' + c.blind + " unread</span>";
    if (!isNowT(t) && !c.known) return '<span class="st-ghost">no data</span>';
    if (c.down) return '<span class="st-down">✗ <b>' + c.answering + "</b>/" + c.total + "</span>";
    return '<span class="st-ok">✓</span> <b>' + c.answering + "</b>/" + c.total;
  }

  function oneHostVal(h, t) {
    var c = isNowT(t) ? M.nowMap[h] || "." : cellAt(h, t);
    var live = isNowT(t) && data.probes && data.probes.hosts[h] && data.probes.hosts[h].now;
    return '<span class="st-' + DOT[c] + '">' + GLYPH[c] + "</span> " + (c === "o" && live && live.ms != null ? live.ms + "ms" : WORD[c]);
  }

  function seriesValHTML(s, t) {
    return "<b>" + C.fmtValue(s.unit, valueAt(s, isNowT(t) ? M.s.end : t)) + "</b>";
  }

  function render() {
    if (!M) return;
    var n = windowN();
    var t = ui.cur == null ? M.wEnd : ui.cur;
    var evs = events();
    var ann = annotationsHTML(evs);
    var rowsHTML = "";
    rowsHTML += '<div class="sc-row"><div class="sc-lab is-empty"></div><div class="sc-plot is-axis">' + ticksHTML() + '</div><div class="sc-val is-empty"></div></div>';
    rowsHTML += '<div class="sc-row"><div class="sc-lab is-empty"></div><div class="sc-plot is-ann" style="height:' + ann.h + 'px">' + ann.html + '</div><div class="sc-val is-empty"></div></div>';
    rowsHTML += '<div class="sc-group" data-gh="svc">' + statusCardHTML(t) + "</div>";
    if (!ui.collapsed.svc) {
      var counts = [];
      for (var k = 0; k < n; k++) {
        var c = hostCountAt(tOf(k));
        counts.push(c.blind || (!c.known && !isNowT(tOf(k))) ? null : c.answering);
      }
      rowsHTML += '<div class="sc-row"><div class="sc-lab"><button class="st-linkbtn" data-hosts aria-expanded="' + ui.hostsOpen + '">hosts answering <span>' + (ui.hostsOpen ? "hide " + M.hosts.length + " ▴" : "show " + M.hosts.length + " ▾") + "</span></button><small>" + (data.probes ? "vps and desktop probers" : "desktop prober only") + "</small></div>" +
        '<div class="sc-plot c-svc" data-plot>' + sparkSVG([counts], { max: Math.max(1, M.hosts.length), bands: bandsFor(evs, { blind: true, down: true }) }) + '<i class="sc-cur"></i></div><div class="sc-val" data-v="hosts">' + hostValHTML(t) + "</div></div>";
      if (ui.hostsOpen) {
        M.hosts.forEach(function (h) {
          var meta = M.meta[h];
          rowsHTML += '<div class="sc-row"><div class="sc-hostlab">' + esc(h) + (meta && meta.where ? " <span>" + esc(meta.where) + "</span>" : "") + '</div><div class="sc-plot is-host" data-plot>' + barsSVG(h) + '<i class="sc-cur"></i></div><div class="sc-val" data-v="host:' + esc(h) + '">' + oneHostVal(h, t) + "</div></div>";
        });
      }
    }
    M.machines.forEach(function (m) {
      var host = M.s && M.s.hosts[m];
      rowsHTML += '<div class="sc-group" data-gh="' + esc(m) + '">' + machineCardHTML(m, t) + "</div>";
      if (ui.collapsed[m]) return;
      if (!host) {
        rowsHTML += '<div class="sc-row"><div class="sc-lab is-empty"></div><div class="sc-plot is-note"><span class="st-note">history comes from the desktop snapshot, which is unavailable</span></div><div class="sc-val is-empty"></div></div>';
        return;
      }
      host.series.forEach(function (s) {
        var vals = [];
        for (var k = 0; k < n; k++) vals.push(valueAt(s, tOf(k)));
        var bands = bandsFor(evs, { blind: true }).concat(bandsFor(evs.filter(function (e) { return e.kind !== "restart" || e.m === m; }), { restart: true }));
        rowsHTML += '<div class="sc-row"><div class="sc-lab">' + esc(s.label) + "<small>" + esc(s.unit || "") + (s.warn != null ? " · warn " + C.fmtValue(s.unit, s.warn) : "") + '</small></div><div class="sc-plot c-' + esc(m) + '" data-plot>' +
          sparkSVG([vals], { max: s.unit === "%" ? Math.max(100, Math.max.apply(null, vals.filter(function (v) { return v != null; }).concat([0]))) : null, warn: s.warn, bands: bands }) +
          '<i class="sc-cur"></i></div><div class="sc-val" data-v="s:' + esc(m) + ":" + esc(s.key) + '">' + seriesValHTML(s, t) + "</div></div>";
      });
    });
    var chips = ["1h", "6h", "24h"].map(function (r) { return '<button class="mv-chip" data-range="' + r + '" aria-pressed="' + (r === ui.range) + '">' + r + "</button>"; }).join("");
    main.innerHTML = '<div class="sc-bar"><div class="mv-chips" role="group" aria-label="range">' + chips + '</div><span class="sc-read" data-read></span></div>' +
      '<div class="sc-grid" tabindex="0" aria-label="Status on a shared time axis. Arrow keys move the crosshair, Escape returns to now.">' + rowsHTML + "</div>" +
      '<p class="sc-hint">hover to preview a moment · click or use ← → to hold it · esc or "back to now" returns</p>';
    cursor(ui.cur);
  }

  function cursor(t) {
    if (!M) return;
    var n = windowN();
    var first = tOf(0);
    if (t == null || t >= M.wEnd) t = M.wEnd;
    if (t < first) t = first;
    ui.cur = t >= M.wEnd ? null : t;
    if (ui.cur == null) ui.held = false;
    var grid = main.querySelector(".sc-grid");
    if (!grid) return;
    grid.style.setProperty("--x", (kOf(t) / Math.max(1, n - 1) * 100).toFixed(3) + "%");
    var vals = main.querySelectorAll("[data-v]");
    for (var i = 0; i < vals.length; i++) {
      var key = vals[i].getAttribute("data-v");
      if (key === "hosts") vals[i].innerHTML = hostValHTML(t);
      else if (key.indexOf("host:") === 0) vals[i].innerHTML = oneHostVal(key.slice(5), t);
      else if (key.indexOf("s:") === 0) {
        var parts = key.split(":");
        var host = M.s && M.s.hosts[parts[1]];
        var s = host && host.series.filter(function (x) { return x.key === parts[2]; })[0];
        if (s) vals[i].innerHTML = seriesValHTML(s, t);
      }
    }
    var heads = main.querySelectorAll("[data-gh]");
    for (i = 0; i < heads.length; i++) {
      var g = heads[i].getAttribute("data-gh");
      heads[i].innerHTML = g === "svc" ? statusCardHTML(t) : machineCardHTML(g, t);
    }
    var read = main.querySelector("[data-read]");
    if (read) read.innerHTML = (ui.cur == null ? "<b>now</b>" : "<b>" + stamp(t) + "</b>") + " · " + esc(hostReadText(t));
  }

  function hostReadText(t) {
    var c = hostCountAt(t);
    if (!c.total) return "no probes";
    if (c.blind) return "prober blind";
    if (!isNowT(t) && !c.known) return "no probe data";
    return c.down ? c.down + " of " + c.total + " down" : c.answering + " of " + c.total + " answering";
  }

  function fracFrom(e) {
    var p = e.target.closest && e.target.closest("[data-plot]");
    if (!p) return null;
    var r = p.getBoundingClientRect();
    if (!r.width) return null;
    return Math.max(0, Math.min(1, (e.clientX - r.left) / r.width));
  }
  function tFrom(f) { return tOf(Math.round(f * (windowN() - 1))); }

  main.addEventListener("pointermove", function (e) {
    if (ui.held || !M) return;
    var f = fracFrom(e);
    if (f != null) cursor(tFrom(f));
  });
  main.addEventListener("pointerdown", function (e) {
    if (!M) return;
    var f = fracFrom(e);
    if (f == null) return;
    ui.held = true;
    cursor(tFrom(f));
  });
  main.addEventListener("pointerleave", function (e) {
    if (e.pointerType === "mouse" && !ui.held) cursor(null);
  });
  main.addEventListener("click", function (e) {
    if (!M) return;
    if (e.target.closest("[data-now]")) { ui.held = false; cursor(null); return; }
    var r = e.target.closest("[data-range]");
    if (r) { ui.range = r.getAttribute("data-range"); ui.cur = null; ui.held = false; render(); return; }
    if (e.target.closest("[data-hosts]")) { ui.hostsOpen = !ui.hostsOpen; render(); return; }
    var tg = e.target.closest("[data-toggle]");
    if (tg) { var g = tg.getAttribute("data-toggle"); ui.collapsed[g] = !ui.collapsed[g]; render(); }
  });
  main.addEventListener("keydown", function (e) {
    if (!M || !e.target.closest || !e.target.closest(".sc-grid")) return;
    var t = ui.cur == null ? M.wEnd : ui.cur;
    var step = (e.shiftKey ? 12 : 1) * STEP;
    if (e.key === "ArrowLeft") { ui.held = true; cursor(t - step); e.preventDefault(); }
    else if (e.key === "ArrowRight") { ui.held = true; cursor(t + step); e.preventDefault(); }
    else if (e.key === "Escape" || e.key === "End") { ui.held = false; cursor(null); e.preventDefault(); }
    else if (e.key === "Home") { ui.held = true; cursor(tOf(0)); e.preventDefault(); }
  });

  var mq = window.matchMedia ? window.matchMedia("(max-width: 620px)") : null;
  function applyNarrow() {
    var narrow = !!(mq && mq.matches);
    if (narrow === ui.narrow) return;
    ui.narrow = narrow;
    ui.collapsed = { desk: narrow, vps: narrow };
    if (M) render();
  }
  if (mq) {
    if (mq.addEventListener) mq.addEventListener("change", applyNarrow);
    else if (mq.addListener) mq.addListener(applyNarrow);
  }
  applyNarrow();

  function start() {
    if (timer) return;
    timer = setInterval(refresh, POLL_MS);
  }
  function stop() {
    if (!timer) return;
    clearInterval(timer);
    timer = null;
  }
  document.addEventListener("visibilitychange", function () {
    if (document.visibilityState === "hidden") stop();
    else { refresh(); start(); }
  });

  refresh();
  if (document.visibilityState !== "hidden") start();
})();
