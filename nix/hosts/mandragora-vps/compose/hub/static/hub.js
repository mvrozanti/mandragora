(function () {
  var $ = function (id) { return document.getElementById(id); };
  var esc = function (v) {
    return String(v).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  };

  var data = null;
  var health = {};
  var clicks = {};

  var groupLabel = function (id) {
    var g = data.groups.filter(function (x) { return x.id === id; })[0];
    return g ? g.label : id;
  };
  var machine = function (id) {
    var m = data.machines.filter(function (x) { return x.id === id; })[0];
    return m || { id: id, label: id, meta: "" };
  };
  var linkOf = function (s) { return s.url || "https://" + s.host; };

  var fmtSecs = function (s) {
    if (s == null) return "";
    if (s < 60) return s.toFixed(0) + "s";
    if (s < 3600) return (s / 60).toFixed(1) + "m";
    return (s / 3600).toFixed(1) + "h";
  };
  var fmtGB = function (g) {
    if (g == null) return "–";
    return g < 1000 ? g.toFixed(g < 10 ? 1 : 0) + "G" : (g / 1000).toFixed(1) + "T";
  };
  var pct = function (v) { return v == null ? "–" : v.toFixed(0) + "%"; };

  var stateOf = function (s) {
    var h = health[s.host];
    return h && h.state ? h.state : "unknown";
  };

  var LOCK_OPEN = '<rect x="4" y="11" width="14" height="9" rx="2"></rect><path d="M8 11V7a4 4 0 0 1 7.7-1.5"></path>';
  var LOCK_SHUT = '<rect x="5" y="11" width="14" height="9" rx="2"></rect><path d="M8.5 11V7.5a3.5 3.5 0 0 1 7 0V11"></path>';
  var lockSvg = function (open) {
    return '<svg class="mv-lock" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' +
      'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
      (open ? LOCK_OPEN : LOCK_SHUT) + "</svg>";
  };

  var STATE_WORD = { ok: "up", warn: "degraded", down: "down", unknown: "not probed yet" };

  var recordClick = function (host) {
    clicks[host] = (clicks[host] || 0) + 1;
    fetch("/api/clicks", {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ host: host }),
      keepalive: true
    }).catch(function () {});
  };

  var rowHTML = function (s) {
    var open = s.access === "open";
    var state = stateOf(s);
    var label = s.host + " — " + s.desc + " — on " + machine(s.where).label +
      (open ? " — reachable without signing in" : " — behind authelia") + " — " + STATE_WORD[state];
    return '<a class="mv-row' + (state === "down" ? " is-down" : "") + '" href="' + esc(linkOf(s)) +
      '" target="_blank" rel="noopener" data-host="' + esc(s.host) + '" aria-label="' + esc(label) + '">' +
      '<span class="mv-dot mv-row__state is-' + state + '" aria-hidden="true"></span>' +
      '<span class="mv-badge ' + (open ? "is-open" : "is-gated") + '" aria-hidden="true">' + lockSvg(open) + "</span>" +
      '<span class="mv-row__host">' + esc(s.host) + "</span></a>";
  };

  var renderList = function () {
    $("list").innerHTML = '<div class="mv-list">' + data.services.map(rowHTML).join("") + "</div>";
    $("count").textContent = data.services.length + " services";
  };

  var meterHTML = function (label, value, percent, warnAt, criticalAt) {
    var p = Math.max(0, Math.min(100, percent || 0));
    var cls = p >= criticalAt ? " is-critical" : p >= warnAt ? " is-warn" : "";
    return '<div class="mv-meter' + cls + '"><span class="mv-meter__label">' + label + "</span>" +
      '<span class="mv-meter__track"><i class="mv-meter__fill" style="width:' + p + '%"></i></span>' +
      '<span class="mv-meter__value">' + value + "</span></div>";
  };

  var alerts = [];
  var pushAlert = function (level, title, detail) {
    alerts.push('<div class="mv-alert"><span class="mv-dot mv-alert__dot is-' + level + '"></span>' +
      "<div><b>" + title + "</b><em>" + detail + "</em></div></div>");
  };

  var serviceAlerts = function () {
    if (!data) return;
    var bad = data.services.filter(function (s) {
      var st = stateOf(s);
      return st === "down" || st === "warn";
    });
    bad.sort(function (a, b) { return stateOf(a) === "down" ? -1 : stateOf(b) === "down" ? 1 : 0; });
    bad.slice(0, 6).forEach(function (s) {
      var h = health[s.host] || {};
      pushAlert(stateOf(s) === "down" ? "down" : "warn", esc(s.host),
        (h.code ? h.code : "no answer") + (h.ms != null ? " · " + h.ms + "ms" : ""));
    });
    if (bad.length > 6) pushAlert("warn", (bad.length - 6) + " more not healthy", "see the list below");
  };

  var deskCard = function (d) {
    if (!d) {
      pushAlert("down", "mandragora unreachable", "gpu-status is not answering — desktop asleep?");
      return '<div class="mv-card"><div class="mv-card__name">' + esc(machine("desk").label) +
        '<span class="mv-pill is-down">offline</span></div>' +
        '<div class="mv-card__meta">' + esc(machine("desk").meta) + "</div>" +
        '<div class="mv-card__note">gpu-status unreachable</div></div>';
    }
    var g = d.gpu || {};
    var lock = d.locked && d.holder;
    var note = lock
      ? "<b>" + esc(d.holder.name || "?") + "</b> · " + fmtSecs(d.holder.held_for) + " held" +
        (d.holder.expected_remaining != null ? " · ~" + fmtSecs(d.holder.expected_remaining) + " left" : "")
      : "no holder";
    if (lock) pushAlert("warn", "gpu-lock held", esc(d.holder.name || "?") + " · " + fmtSecs(d.holder.held_for));
    if (d.disk && d.disk.used_pct >= 85) pushAlert("warn", "desktop disk at " + pct(d.disk.used_pct), fmtGB(d.disk.used_gb) + " of " + fmtGB(d.disk.total_gb));
    var gpuName = g.name ? g.name.replace(/^NVIDIA\s+(GeForce\s+)?/i, "") : "gpu";
    return '<div class="mv-card"><div class="mv-card__name">' + esc(machine("desk").label) +
      '<span class="mv-pill ' + (lock ? "is-warn" : "is-ok") + '">' + (lock ? "lock held" : "lock free") + "</span></div>" +
      '<div class="mv-card__meta">' + esc(gpuName) + "</div>" +
      meterHTML("gpu", pct(g.util_pct), g.util_pct, 50, 85) +
      meterHTML("vram", g.mem_used_mb != null ? (g.mem_used_mb / 1024).toFixed(1) + "/" + (g.mem_total_mb / 1024).toFixed(0) + "G" : "–", g.mem_pct, 60, 90) +
      meterHTML("temp", g.temp_c != null ? g.temp_c.toFixed(0) + "°C" : "–", g.temp_c != null ? (g.temp_c - 30) * 100 / 60 : 0, 50, 80) +
      meterHTML("cpu", pct(d.cpu && d.cpu.util_pct), d.cpu && d.cpu.util_pct, 50, 85) +
      meterHTML("disk", d.disk ? fmtGB(d.disk.used_gb) + "/" + fmtGB(d.disk.total_gb) : "–", d.disk && d.disk.used_pct, 70, 90) +
      '<div class="mv-card__note">' + note + "</div></div>";
  };

  var vpsCard = function (v) {
    if (!v) {
      pushAlert("down", "mandragora-vps unreachable", "host-stats is not answering");
      return '<div class="mv-card"><div class="mv-card__name">' + esc(machine("vps").label) +
        '<span class="mv-pill is-down">offline</span></div>' +
        '<div class="mv-card__meta">' + esc(machine("vps").meta) + "</div>" +
        '<div class="mv-card__note">host-stats unreachable</div></div>';
    }
    if (v.disk && v.disk.used_pct >= 70) pushAlert("warn", "vps disk at " + pct(v.disk.used_pct), fmtGB(v.disk.used_gb) + " of " + fmtGB(v.disk.total_gb) + " — seafile is the driver");
    return '<div class="mv-card"><div class="mv-card__name">' + esc(machine("vps").label) +
      '<span class="mv-pill is-ok">online</span></div>' +
      '<div class="mv-card__meta">' + esc(machine("vps").meta) + "</div>" +
      meterHTML("cpu", pct(v.cpu && v.cpu.util_pct), v.cpu && v.cpu.util_pct, 50, 85) +
      meterHTML("disk", v.disk ? fmtGB(v.disk.used_gb) + "/" + fmtGB(v.disk.total_gb) : "–", v.disk && v.disk.used_pct, 70, 90) +
      '<div class="mv-card__note">' + data.services.filter(function (s) { return s.where === "vps"; }).length + " services here</div></div>";
  };

  var glance = function (d, v) {
    var parts = [];
    parts.push('<span><i class="mv-dot ' + (d ? (d.locked ? "is-warn" : "is-ok") : "is-down") + '"></i><b>' +
      esc(machine("desk").label) + "</b> " + (d ? (d.gpu ? "gpu " + pct(d.gpu.util_pct) : "up") + (d.locked ? " · lock held" : "") : "offline") + "</span>");
    parts.push('<span><i class="mv-dot ' + (v ? (v.disk && v.disk.used_pct >= 70 ? "is-warn" : "is-ok") : "is-down") + '"></i><b>vps</b> ' +
      (v ? "disk " + pct(v.disk && v.disk.used_pct) : "offline") + "</span>");
    var bad = data ? data.services.filter(function (s) { return stateOf(s) === "down" || stateOf(s) === "warn"; }).length : 0;
    parts.push('<span><i class="mv-dot ' + (bad ? "is-warn" : "is-ok") + '"></i>' +
      (bad ? bad + " service" + (bad > 1 ? "s" : "") + " need attention" : "all services up") + "</span>");
    $("glance").innerHTML = parts.join("");
  };

  var renderStatus = function (d, v) {
    alerts = [];
    var cards = deskCard(d) + vpsCard(v);
    serviceAlerts();
    var alertCard = '<div class="mv-card"><div class="mv-card__meta">needs attention</div>' +
      (alerts.length ? alerts.join("") : '<div class="mv-alert"><span class="mv-dot mv-alert__dot is-ok"></span><div><b>all clear</b><em>no thresholds crossed</em></div></div>') +
      "</div>";
    $("statusBody").innerHTML = '<div class="hub__status-grid">' + cards + alertCard + "</div>";
    glance(d, v);
  };

  var timer = null;
  var lastHealth = "";
  var grab = function (path) {
    return fetch(path, { credentials: "same-origin", cache: "no-store" })
      .then(function (r) { return r.ok ? r.text() : null; })
      .catch(function () { return null; });
  };
  var poll = function () {
    Promise.all([grab("/api/gpu"), grab("/api/vps"), grab("/api/health")]).then(function (res) {
      if (res[2] && res[2] !== lastHealth) {
        lastHealth = res[2];
        try { health = (JSON.parse(res[2]) || {}).services || {}; } catch (e) { health = {}; }
        if (data) renderList();
      }
      var parse = function (t) { try { return t ? JSON.parse(t) : null; } catch (e) { return null; } };
      renderStatus(parse(res[0]), parse(res[1]));
    });
  };
  var start = function () { if (timer) return; poll(); timer = setInterval(poll, 4000); };
  var stop = function () { if (!timer) return; clearInterval(timer); timer = null; };

  var sortByUse = function () {
    var order = {};
    data.services.forEach(function (s, i) { order[s.host] = i; });
    data.services.sort(function (a, b) {
      return (clicks[b.host] || 0) - (clicks[a.host] || 0) || order[a.host] - order[b.host];
    });
  };

  Promise.all([
    fetch("services.json", { cache: "no-cache" }).then(function (r) { return r.json(); }),
    fetch("/api/clicks", { credentials: "same-origin", cache: "no-store" })
      .then(function (r) { return r.ok ? r.json() : null; })
      .catch(function () { return null; })
  ])
    .then(function (res) {
      data = res[0];
      clicks = (res[1] && res[1].clicks) || {};
      sortByUse();
      renderList();
      poll();
      $("list").addEventListener("click", function (e) {
        var row = e.target.closest(".mv-row");
        if (row && row.dataset.host) recordClick(row.dataset.host);
      });
    })
    .catch(function () {
      $("list").innerHTML = '<p class="mv-empty">services.json failed to load</p>';
    });

  fetch("/whoami", { credentials: "same-origin" })
    .then(function (r) { return r.ok ? r.text() : null; })
    .then(function (n) { if (n) $("who").textContent = n.trim(); })
    .catch(function () {});

  $("status").open = window.matchMedia("(min-width: 760px)").matches;
  document.addEventListener("visibilitychange", function () {
    if (document.visibilityState === "visible") start(); else stop();
  });
  start();
})();
