(function (root) {
  "use strict";

  var KNOWN = { o: true, w: true, d: true };
  var NOW_CHAR = { ok: "o", warn: "w", down: "d" };

  function align(t, step) {
    return Math.round(t / step) * step;
  }

  function isBlindColumn(cells, mvrIndex) {
    var known = 0;
    var down = 0;
    for (var k = 0; k < cells.length; k++) {
      if (KNOWN[cells[k]]) known++;
      if (cells[k] === "d") down++;
    }
    if (!known || !down) return false;
    if (down * 2 >= known) return true;
    return mvrIndex >= 0 && cells[mvrIndex] === "d" && down >= 3;
  }

  function applyBlind(hosts) {
    var names = Object.keys(hosts || {});
    var grid = {};
    var len = 0;
    names.forEach(function (n) {
      grid[n] = String(hosts[n] || "").split("");
      if (grid[n].length > len) len = grid[n].length;
    });
    var mvr = names.indexOf("mvr.ac");
    for (var i = 0; i < len; i++) {
      var col = names.map(function (n) { return grid[n][i] || "."; });
      if (!isBlindColumn(col, mvr)) continue;
      names.forEach(function (n) { if (grid[n][i] === "d") grid[n][i] = "b"; });
    }
    var out = {};
    names.forEach(function (n) { out[n] = grid[n].join(""); });
    return out;
  }

  function sourceSpan(src) {
    var step = src.step || 300;
    var start = align(src.start, step);
    var len = 0;
    Object.keys(src.hosts || {}).forEach(function (h) {
      if (src.hosts[h].length > len) len = src.hosts[h].length;
    });
    return { start: start, step: step, len: len, end: len ? start + (len - 1) * step : null };
  }

  function cellAt(src, span, host, t) {
    if (!src || !span || !src.hosts || src.hosts[host] == null) return ".";
    var i = Math.round((t - span.start) / span.step);
    var s = src.hosts[host];
    if (i < 0 || i >= s.length) return ".";
    return s.charAt(i) || ".";
  }

  function merge(desk, vps, step) {
    step = step || 300;
    var srcs = [];
    if (desk && desk.hosts) srcs.push({ src: desk, span: sourceSpan(desk), role: "desk" });
    if (vps && vps.hosts) srcs.push({ src: vps, span: sourceSpan(vps), role: "vps" });
    srcs = srcs.filter(function (x) { return x.span.len > 0; });
    if (!srcs.length) return { start: null, end: null, step: step, hosts: {} };
    var start = Math.min.apply(null, srcs.map(function (x) { return x.span.start; }));
    var end = Math.max.apply(null, srcs.map(function (x) { return x.span.end; }));
    var n = Math.round((end - start) / step) + 1;
    var d = srcs.filter(function (x) { return x.role === "desk"; })[0];
    var v = srcs.filter(function (x) { return x.role === "vps"; })[0];
    var names = {};
    srcs.forEach(function (x) { Object.keys(x.src.hosts).forEach(function (h) { names[h] = true; }); });
    var hosts = {};
    Object.keys(names).sort().forEach(function (h) {
      var out = "";
      for (var i = 0; i < n; i++) {
        var t = start + i * step;
        var vc = v ? cellAt(v.src, v.span, h, t) : ".";
        out += vc !== "." ? vc : (d ? cellAt(d.src, d.span, h, t) : ".");
      }
      hosts[h] = out;
    });
    return { start: start, end: end, step: step, hosts: hosts };
  }

  function nowStates(liveHosts, desk) {
    var names = {};
    if (liveHosts) Object.keys(liveHosts).forEach(function (h) { names[h] = true; });
    if (desk && desk.hosts) Object.keys(desk.hosts).forEach(function (h) { names[h] = true; });
    var list = Object.keys(names).sort();
    var col = list.map(function (h) {
      var live = liveHosts && liveHosts[h] && liveHosts[h].now;
      if (live && NOW_CHAR[live.state]) return NOW_CHAR[live.state];
      var s = desk && desk.hosts && desk.hosts[h];
      return s ? s.charAt(s.length - 1) || "." : ".";
    });
    var blind = isBlindColumn(col, list.indexOf("mvr.ac"));
    var out = {};
    list.forEach(function (h, k) { out[h] = blind && col[k] === "d" ? "b" : col[k]; });
    return out;
  }

  function census(states) {
    var r = { ok: 0, warn: 0, down: 0, blind: 0, none: 0, total: 0, downHosts: [], warnHosts: [] };
    Object.keys(states || {}).sort().forEach(function (h) {
      var c = states[h];
      r.total++;
      if (c === "o") r.ok++;
      else if (c === "w") { r.warn++; r.warnHosts.push(h); }
      else if (c === "d") { r.down++; r.downHosts.push(h); }
      else if (c === "b") r.blind++;
      else r.none++;
    });
    return r;
  }

  function freshness(now, generated, period) {
    if (now == null || generated == null) return { state: "missing", age: null, missed: null };
    var p = period || 60;
    var age = Math.max(0, now - generated);
    var state = age >= 10 * p ? "silent" : age >= 3 * p ? "stale" : "fresh";
    return { state: state, age: age, missed: Math.floor(age / p) };
  }

  function pullState(pull) {
    if (!pull) return { unreachable: false, since: null };
    var ok = pull.ok_at == null ? null : pull.ok_at;
    var fail = pull.fail_at == null ? null : pull.fail_at;
    return { unreachable: fail != null && (ok == null || fail > ok), since: ok, error: pull.error || null };
  }

  function duration(s) {
    if (s == null || !isFinite(s)) return "–";
    s = Math.max(0, Math.round(s));
    var d = Math.floor(s / 86400);
    var h = Math.floor((s % 86400) / 3600);
    var m = Math.floor((s % 3600) / 60);
    if (d) return d + "d " + h + "h";
    if (h) return h + "h " + (m < 10 ? "0" : "") + m + "m";
    if (m) return m + "m";
    return s + "s";
  }

  function fmtValue(unit, v) {
    if (v == null || !isFinite(v)) return "–";
    if (unit === "%") return (v > 0 && v < 10 ? v.toFixed(1) : v.toFixed(0)) + "%";
    if (unit === "°C") return v.toFixed(0) + "°C";
    if (unit === "W") return v.toFixed(0) + " W";
    if (unit === "B/s") return v >= 1e6 ? (v / 1e6).toFixed(1) + " MB/s" : v >= 1e3 ? (v / 1e3).toFixed(0) + " kB/s" : v.toFixed(0) + " B/s";
    if (unit === "B") return v >= 1e9 ? (v / 1e9).toFixed(1) + " GB" : v >= 1e6 ? (v / 1e6).toFixed(0) + " MB" : (v / 1e3).toFixed(0) + " kB";
    if (unit === "s") return duration(v);
    if (unit === "GiB") return v.toFixed(1) + " GiB";
    return String(Math.round(v * 100) / 100) + (unit ? " " + unit : "");
  }

  function level(series, v) {
    if (v == null || series.warn == null) return "ok";
    if (series.crit != null && v >= series.crit) return "crit";
    return v >= series.warn ? "warn" : "ok";
  }

  function lastValue(series) {
    var vals = series.values || [];
    for (var i = vals.length - 1; i >= 0; i--) if (vals[i] != null) return vals[i];
    return null;
  }

  function cardSeries(host) {
    var list = (host && host.series) || [];
    var flagged = list.filter(function (s) { return s.card === true; });
    if (flagged.length) return flagged;
    return list.filter(function (s) { return s.warn != null; }).slice(0, 6);
  }

  function hottest(seriesList) {
    var best = null;
    (seriesList || []).forEach(function (s) {
      var v = lastValue(s);
      if (v == null || s.warn == null || v < s.warn) return;
      var score = v / (s.crit || s.warn);
      if (!best || score > best.score) best = { score: score, key: s.key, label: s.label, text: fmtValue(s.unit, v), level: level(s, v) };
    });
    return best;
  }

  function shortHost(h) {
    return h === "mvr.ac" ? h : String(h).replace(/\.mvr\.ac$/, "");
  }

  function joinList(a) {
    if (a.length <= 1) return a.join("");
    if (a.length === 2) return a[0] + " and " + a[1];
    return a.slice(0, -1).join(", ") + " and " + a[a.length - 1];
  }

  function verdict(x) {
    var c = x.census;
    var f = x.fresh;
    var answering = c.ok + c.warn;
    var r;
    if (f.state === "silent" || f.state === "missing") {
      var parts = [f.state === "missing" ? "No desktop snapshot is available." : "No snapshot for " + duration(f.age) + "."];
      if (x.pull && x.pull.unreachable) {
        parts.push(x.pull.since != null && x.now != null ? "The VPS has failed to reach it for " + duration(x.now - x.pull.since) + "." : "The VPS has not reached it yet.");
      }
      if (x.probesLive) parts.push("The VPS is probing on its own: " + answering + " of " + c.total + " answer" + (c.down ? ", " + c.down + " do not." : "."));
      else parts.push("Live host probes are unavailable too.");
      return { level: "down", head: "The desktop has gone silent", detail: parts.join(" ") };
    }
    if (c.down > 6) {
      r = { level: "down", head: c.down + " of " + c.total + " hosts down", detail: answering + " of " + c.total + " answer the latest probe." };
    } else if (c.down) {
      r = { level: "down", head: joinList(c.downHosts.map(shortHost)) + " not answering", detail: answering + " of " + c.total + " answer the latest probe." };
    } else if (c.blind) {
      r = { level: "unknown", head: "No outage · the prober went blind", detail: "Most probes failed in the same round, so the prober is at fault. " + c.blind + " hosts are unread, not down." };
    } else if (x.deskUptime != null && x.deskUptime < 900) {
      r = { level: "warn", head: "The desktop restarted " + duration(x.deskUptime) + " ago", detail: answering + " of " + c.total + " answer." };
    } else if (c.warn) {
      r = { level: "warn", head: joinList(c.warnHosts.map(shortHost)) + (c.warn > 1 ? " are" : " is") + " slow or erroring", detail: answering + " of " + c.total + " answer." };
    } else if (!c.total) {
      r = { level: "unknown", head: "No host probes yet", detail: "Neither prober has reported a round." };
    } else {
      r = {
        level: "ok",
        head: "All " + c.total + " answering" + (x.hot ? " · " + x.hot.label + " at " + x.hot.text : ""),
        detail: x.vpsLive ? "Both machines up." : "Both machines up. Live VPS figures are unavailable, so its card shows the snapshot."
      };
    }
    if (f.state === "stale") {
      if (r.level === "ok") r.level = "warn";
      r.head = "Stale · " + r.head;
      r.detail = "Last snapshot " + duration(f.age) + " ago, " + f.missed + " pulls missed. " + r.detail;
    }
    return r;
  }

  var api = {
    align: align,
    isBlindColumn: isBlindColumn,
    applyBlind: applyBlind,
    merge: merge,
    nowStates: nowStates,
    census: census,
    freshness: freshness,
    pullState: pullState,
    duration: duration,
    fmtValue: fmtValue,
    level: level,
    lastValue: lastValue,
    cardSeries: cardSeries,
    hottest: hottest,
    shortHost: shortHost,
    joinList: joinList,
    verdict: verdict
  };

  if (typeof module === "object" && module && module.exports) module.exports = api;
  else root.StatusCore = api;
})(typeof self !== "undefined" ? self : this);
