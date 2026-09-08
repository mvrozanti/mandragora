(function () {
  var $ = function (id) { return document.getElementById(id); };
  var esc = function (v) {
    return String(v).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  };

  var data = null;
  var health = {};
  var query = "";
  var group = "all";

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

  var highlight = function (name) {
    if (!query) return esc(name);
    var i = name.toLowerCase().indexOf(query);
    if (i < 0) return esc(name);
    return esc(name.slice(0, i)) + "<mark>" + esc(name.slice(i, i + query.length)) + "</mark>" + esc(name.slice(i + query.length));
  };

  var stateOf = function (s) {
    var h = health[s.host];
    if (!h) return "unknown";
    if (h.up === false) return "down";
    if (h.ms != null && h.ms > 600) return "slow";
    return "ok";
  };

  var UNLOCKED = '<svg class="mv-lock" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
    'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<rect x="4" y="11" width="14" height="9" rx="2"></rect>' +
    '<path d="M8 11V7a4 4 0 0 1 7.7-1.5"></path></svg>';

  var rowHTML = function (s) {
    var state = stateOf(s);
    var dotClass = state === "ok" ? "is-ok" : state === "slow" ? "is-warn" : state === "down" ? "is-down" : "";
    var label = s.name + " — " + s.desc + " — on " + machine(s.where).label +
      (s.access === "open" ? " — reachable without signing in" : "");
    return '<a class="mv-row mv-row--' + s.where + (state === "down" ? " is-down" : "") + '"' +
      ' href="' + esc(linkOf(s)) + '" target="_blank" rel="noopener" aria-label="' + esc(label) + '">' +
      '<span class="mv-dot mv-row__state ' + dotClass + '" aria-hidden="true"></span>' +
      '<span><span class="mv-row__name">' + highlight(s.name) +
      (s.access === "open" ? UNLOCKED : "") + "</span>" +
      '<span class="mv-row__desc">' + esc(s.desc) + "</span></span>" +
      '<span class="mv-row__host">' + esc(s.host) + "</span></a>";
  };

  var matches = function (s) {
    if (group !== "all" && s.group !== group) return false;
    if (!query) return true;
    return s.haystack.indexOf(query) >= 0;
  };

  var renderList = function () {
    var items = data.services.filter(matches);
    $("list").innerHTML = items.length
      ? '<div class="mv-list">' + items.map(rowHTML).join("") + "</div>"
      : '<p class="mv-empty">nothing matches &ldquo;' + esc(query) + '&rdquo;</p>';
    $("count").textContent = items.length === data.services.length
      ? data.services.length + " services"
      : items.length + " of " + data.services.length;
  };

  var renderChips = function () {
    $("chips").innerHTML = [{ id: "all", label: "everything" }].concat(data.groups).map(function (g) {
      return '<button class="mv-chip" type="button" data-group="' + g.id + '" aria-pressed="' + (g.id === group) + '">' + esc(g.label) + "</button>";
    }).join("");
  };

  var renderLegend = function () {
    $("legend").innerHTML = data.machines.map(function (m) {
      var n = data.services.filter(function (s) { return s.where === m.id; }).length;
      return '<span><i style="background:var(--mv-machine-' + m.id + ')"></i><b>' + esc(m.label) + "</b> " + n + "</span>";
    }).join("");
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
    parts.push("<span>" + (alerts.length ? alerts.length + " need attention" : "all clear") + "</span>");
    $("glance").innerHTML = parts.join("");
  };

  var renderStatus = function (d, v) {
    alerts = [];
    var cards = deskCard(d) + vpsCard(v);
    var alertCard = '<div class="mv-card"><div class="mv-card__meta">needs attention</div>' +
      (alerts.length ? alerts.join("") : '<div class="mv-alert"><span class="mv-dot mv-alert__dot is-ok"></span><div><b>all clear</b><em>no thresholds crossed</em></div></div>') +
      "</div>";
    $("statusBody").innerHTML = '<div class="hub__status-grid">' + cards + alertCard + "</div>";
    glance(d, v);
  };

  var timer = null;
  var poll = function () {
    Promise.all([
      fetch("/api/gpu", { credentials: "same-origin", cache: "no-store" }).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; }),
      fetch("/api/vps", { credentials: "same-origin", cache: "no-store" }).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; })
    ]).then(function (res) { renderStatus(res[0], res[1]); });
  };
  var start = function () { if (timer) return; poll(); timer = setInterval(poll, 4000); };
  var stop = function () { if (!timer) return; clearInterval(timer); timer = null; };

  var loadHealth = function () {
    fetch("/api/health", { credentials: "same-origin", cache: "no-store" })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (h) { health = h || {}; renderList(); })
      .catch(function () {});
  };

  fetch("services.json", { cache: "no-cache" })
    .then(function (r) { return r.json(); })
    .then(function (json) {
      data = json;
      data.services.forEach(function (s) {
        s.haystack = [s.name, s.host, s.desc, groupLabel(s.group), machine(s.where).label, s.access].join(" ").toLowerCase();
      });
      renderChips();
      renderLegend();
      renderList();
      loadHealth();

      $("chips").addEventListener("click", function (e) {
        var b = e.target.closest(".mv-chip");
        if (!b) return;
        group = b.dataset.group;
        Array.prototype.forEach.call($("chips").querySelectorAll(".mv-chip"), function (x) {
          x.setAttribute("aria-pressed", String(x === b));
        });
        renderList();
      });

      var input = $("q");
      input.addEventListener("input", function () { query = input.value.trim().toLowerCase(); renderList(); });
      input.addEventListener("keydown", function (e) {
        if (e.key === "Escape") { input.value = ""; query = ""; renderList(); }
        if (e.key === "Enter") {
          var first = $("list").querySelector(".mv-row");
          if (first) first.click();
        }
      });
      document.addEventListener("keydown", function (e) {
        if (e.key === "/" && document.activeElement !== input) { e.preventDefault(); input.focus(); }
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
