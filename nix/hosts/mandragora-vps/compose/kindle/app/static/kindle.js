(function () {
  var $ = function (id) { return document.getElementById(id); };
  var state = { device: null, scripts: [], busy: false, grabbed: 0, monitor: null };

  var esc = function (s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  };

  var toast = function (msg, bad) {
    var t = $("toast");
    t.textContent = msg;
    t.style.borderColor = bad ? "var(--mv-down)" : "var(--mv-line-strong)";
    t.hidden = false;
    clearTimeout(t._t);
    t._t = setTimeout(function () { t.hidden = true; }, 3200);
  };

  var api = function (method, url, body, raw) {
    var opts = { method: method, credentials: "same-origin" };
    if (body instanceof FormData) { opts.body = body; }
    else if (body) { opts.headers = { "Content-Type": "application/json" }; opts.body = JSON.stringify(body); }
    return fetch(url, opts).then(function (r) {
      if (!r.ok) return r.text().then(function (t) { throw new Error(t.slice(0, 160) || r.status); });
      return raw ? r : r.json();
    });
  };

  var ago = function (secs) {
    if (secs == null) return "never";
    if (secs < 60) return Math.round(secs) + "s ago";
    if (secs < 3600) return Math.round(secs / 60) + "m ago";
    return Math.round(secs / 3600) + "h ago";
  };

  var renderDevice = function () {
    var d = state.device;
    var dot = $("dot");
    if (!d || !d.online) {
      $("glance").textContent = d && d.error ? "offline" : "connecting";
      dot.className = "mv-dot is-down";
      $("detail").innerHTML = d && d.error
        ? "<span>" + esc(d.error) + "</span>"
        : "<span>no answer from the device</span>";
      $("batmeter").hidden = true;
      $("diskmeter").hidden = true;
      document.querySelectorAll("[data-act]").forEach(function (b) {
        if (b.dataset.act !== "refresh") b.disabled = true;
      });
      return;
    }
    dot.className = "mv-dot is-ok";
    $("glance").textContent = d.battery + "% · " + (d.tailnet || d.ip || "no ip");
    $("detail").innerHTML =
      "<span>fw <b>" + esc(d.firmware || "?") + "</b></span>" +
      "<span>up <b>" + esc(d.uptime || "?") + "</b></span>" +
      "<span>free <b>" + esc(d.free || "?") + "</b></span>" +
      "<span>art <b>" + esc(d.art) + "</b></span>" +
      (d.showing ? "<span>showing <b>" + esc(d.showing) + "</b></span>" : "") +
      "<span>koreader <b>" + esc(d.koreader) + "</b></span>" +
      "<span>tailscaled <b>" + esc(d.tailscaled) + "</b></span>" +
      "<span>dropbear <b>" + esc(d.dropbear) + "</b></span>" +
      (d.charging ? "<span><b>charging</b></span>" : "");

    $("batmeter").hidden = false;
    $("batfill").style.width = d.battery + "%";
    $("batval").textContent = d.battery + "%";
    $("batmeter").className = "mv-meter" + (d.battery < 15 ? " is-critical" : d.battery < 30 ? " is-warn" : "");
    $("diskmeter").hidden = false;
    $("diskfill").style.width = d.used_pct + "%";
    $("diskval").textContent = d.free || "";
    $("diskmeter").className = "mv-meter" + (d.used_pct > 95 ? " is-warn" : "");
    document.querySelectorAll("[data-act]").forEach(function (b) { b.disabled = false; });
  };

  var renderScripts = function () {
    var host = $("scriptlets");
    if (!state.scripts.length) { host.innerHTML = '<span class="mv-empty">none found</span>'; return; }
    host.innerHTML = state.scripts.map(function (s) {
      return '<button class="wa-btn" data-act="run" data-arg="' + esc(s.name) + '">' + esc(s.label) + "</button>";
    }).join("");
  };

  var loadScreen = function (force) {
    var img = $("screen");
    var url = "/api/screen.png?t=" + Date.now() + (force ? "&force=true" : "");
    return api("GET", url, null, true).then(function (r) {
      var at = Number(r.headers.get("X-Grabbed-At") || 0);
      return r.blob().then(function (b) {
        if (img.src.indexOf("blob:") === 0) URL.revokeObjectURL(img.src);
        img.src = URL.createObjectURL(b);
        img.hidden = false;
        $("screenempty").hidden = true;
        $("save").href = img.src;
        state.grabbed = at * 1000;
        $("grabbed").textContent = "grabbed " + ago((Date.now() - state.grabbed) / 1000);
        document.querySelector(".kx-panel").classList.remove("is-stale");
      });
    }).catch(function (e) {
      $("grabbed").textContent = "screen unavailable";
      document.querySelector(".kx-panel").classList.add("is-stale");
      throw e;
    });
  };

  var withBusy = function (p, ok) {
    state.busy = true;
    return p.then(function (r) { if (ok) toast(ok); return r; })
      .catch(function (e) { toast(String(e.message || e), true); })
      .then(function (r) { state.busy = false; return r; });
  };

  var sendFiles = function (files) {
    if (!files || !files.length) { toast("nothing selected", true); return; }
    var lane = document.querySelector('input[name="lane"]:checked').value;
    var fd = new FormData();
    for (var i = 0; i < files.length; i++) fd.append("files", files[i]);
    var url = lane === "direct" ? "/api/push" : "/api/send";
    withBusy(api("POST", url, fd).then(function (res) {
      var okCount = (res.results || []).filter(function (r) {
        return r.status === "pushed" || r.status === "sent";
      }).length;
      var bad = (res.results || []).filter(function (r) { return r.status === "error"; });
      if (bad.length) toast(bad[0].filename + ": " + bad[0].error, true);
      else toast(okCount + " " + (lane === "direct" ? "pushed" : "emailed"));
      if (lane === "direct") setTimeout(function () { loadScreen(true).catch(function () {}); }, 1500);
    }));
  };

  var renderMonitor = function () {
    var m = state.monitor;
    var pill = $("monpill");
    var btn = $("monbtn");
    if (!m) { btn.textContent = "…"; return; }
    pill.className = "mv-pill " + (m.enabled ? "is-ok" : "");
    pill.textContent = m.enabled ? "monitoring on" : "monitoring paused";
    btn.textContent = m.enabled ? "pause" : "resume";
    $("monnote").textContent = m.enabled
      ? "grafana polls every " + Math.round(m.poll_seconds / 60) + "m"
      : "no polling — saves battery";
  };

  var ACTS = {
    monitor: function () {
      var next = !(state.monitor && state.monitor.enabled);
      withBusy(api("POST", "/api/monitor", { enabled: next }).then(function (m) {
        state.monitor = { enabled: m.enabled, poll_seconds: (state.monitor || {}).poll_seconds || 240 };
        renderMonitor();
      }), next ? "monitoring on" : "monitoring paused");
    },
    refresh: function () { withBusy(loadScreen(true), "refreshed"); },
    browse: function () { $("files").click(); },
    send: function () { sendFiles($("files").files); },
    print: function () {
      var text = $("text").value.trim();
      if (!text) { toast("type something first", true); return; }
      withBusy(api("POST", "/api/print", { text: text }).then(function () {
        $("text").value = "";
        return new Promise(function (r) { setTimeout(r, 1200); }).then(function () {
          return loadScreen(true).catch(function () {});
        });
      }), "printed");
    },
    run: function (name) {
      var out = $("out");
      out.hidden = false;
      out.textContent = "running " + name + "…";
      withBusy(api("POST", "/api/scriptlets/" + encodeURIComponent(name) + "/run").then(function (res) {
        out.textContent = res.output || "(no output)";
        return new Promise(function (r) { setTimeout(r, 1200); }).then(function () {
          return loadScreen(true).catch(function () {});
        });
      }));
    }
  };

  document.addEventListener("click", function (ev) {
    var el = ev.target.closest("[data-act]");
    if (!el || el.disabled) return;
    var fn = ACTS[el.dataset.act];
    if (!fn) return;
    ev.preventDefault();
    fn(el.dataset.arg);
  });

  $("files").addEventListener("change", function () {
    if (this.files.length) toast(this.files.length + " file(s) ready");
  });

  var drop = $("drop");
  ["dragenter", "dragover"].forEach(function (e) {
    drop.addEventListener(e, function (ev) { ev.preventDefault(); drop.classList.add("is-over"); });
  });
  ["dragleave", "drop"].forEach(function (e) {
    drop.addEventListener(e, function (ev) { ev.preventDefault(); drop.classList.remove("is-over"); });
  });
  drop.addEventListener("drop", function (ev) { sendFiles(ev.dataTransfer.files); });

  var loadAll = function () {
    api("GET", "/api/device").then(function (d) { state.device = d; renderDevice(); }).catch(function () {});
    api("GET", "/api/scriptlets").then(function (s) { state.scripts = s; renderScripts(); }).catch(function () {});
    api("GET", "/api/monitor").then(function (m) { state.monitor = m; renderMonitor(); }).catch(function () {});
  };

  loadAll();
  loadScreen(false).catch(function () {});
  setInterval(function () {
    if (document.visibilityState !== "visible" || state.busy) return;
    loadAll();
    if (state.grabbed) $("grabbed").textContent = "grabbed " + ago((Date.now() - state.grabbed) / 1000);
  }, 30000);
})();
