(function () {
  "use strict";

  var render = { all: function () { }, toasts: function () { }, sheet: function () { } };

  var RPC = "/transmission/rpc";
  var LIST_FIELDS = ["id", "name", "status", "percentDone", "metadataPercentComplete", "totalSize",
    "rateDownload", "rateUpload", "uploadRatio", "eta", "labels", "errorString", "error",
    "peersGettingFromUs", "peersSendingToUs", "peersConnected", "addedDate", "activityDate",
    "doneDate", "downloadDir", "queuePosition", "isFinished"];
  var DETAIL_FIELDS = LIST_FIELDS.concat(["hashString", "magnetLink", "pieceCount", "pieceSize",
    "downloadedEver", "uploadedEver", "corruptEver", "seedRatioLimit", "seedRatioMode",
    "bandwidthPriority", "sequentialDownload", "isPrivate", "files", "fileStats", "trackerStats",
    "peers", "honorsSessionLimits", "uploadLimit", "uploadLimited", "downloadLimit", "downloadLimited",
    "secondsSeeding", "secondsDownloading"]);

  var S = {
    torrents: {}, order: [], cur: null, q: "", filter: "all",
    session: null, stats: null, free: {}, sheet: null, sheetArg: null,
    online: false, error: null, toasts: [], detail: null, seen: {},
    notify: { on: true, done: true, ratio: true, native: (window.Notification && Notification.permission) || "denied" },
    mobileDetail: false
  };
  try {
    var saved = JSON.parse(localStorage.getItem("mv-torrent-notify") || "null");
    if (saved) { S.notify.on = !!saved.on; S.notify.done = !!saved.done; S.notify.ratio = !!saved.ratio; }
  } catch (e) { }
  function saveNotify() {
    try { localStorage.setItem("mv-torrent-notify", JSON.stringify({ on: S.notify.on, done: S.notify.done, ratio: S.notify.ratio })); } catch (e) { }
  }

  var sessionId = null, inflight = 0;
  function rpc(method, args, retry) {
    inflight++;
    return fetch(RPC, {
      method: "POST", credentials: "same-origin",
      headers: Object.assign({ "Content-Type": "application/json" },
        sessionId ? { "X-Transmission-Session-Id": sessionId } : {}),
      body: JSON.stringify({ method: method, arguments: args || {} })
    }).then(function (r) {
      if (r.status === 409) {
        sessionId = r.headers.get("X-Transmission-Session-Id");
        if (retry) throw new Error("session handshake failed");
        return rpc(method, args, true);
      }
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.json().then(function (j) {
        if (j.result !== "success") throw new Error(j.result);
        return j.arguments || {};
      });
    }).finally(function () { inflight--; });
  }

  var B = 1000;
  function bytes(n) {
    if (n === null || n === undefined || isNaN(n)) return "–";
    if (n < 0) return "–";
    var u = ["B", "kB", "MB", "GB", "TB"], i = 0;
    while (n >= B && i < u.length - 1) { n /= B; i++; }
    return (i === 0 ? n.toFixed(0) : n < 10 ? n.toFixed(2) : n < 100 ? n.toFixed(1) : n.toFixed(0)) + " " + u[i];
  }
  function rate(n) { return !n || n < 1 ? "—" : bytes(n) + "/s"; }
  function pct(f) { return (f * 100).toFixed(f >= 1 ? 0 : 1) + "%"; }
  function ratio(r) { return r === null || r === undefined || r < 0 ? "∞" : r >= 100 ? r.toFixed(0) : r.toFixed(2); }
  function dur(s) {
    if (s === null || s === undefined || s < 0) return "—";
    var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
    if (d) return d + "d " + h + "h";
    if (h) return h + "h " + m + "m";
    return m ? m + "m" : Math.floor(s) + "s";
  }
  function ago(ts) {
    if (!ts || ts <= 0) return "never";
    var s = Date.now() / 1000 - ts;
    if (s < 90) return "just now";
    if (s < 3600) return Math.floor(s / 60) + "m ago";
    if (s < 86400) return Math.floor(s / 3600) + "h ago";
    var d = Math.floor(s / 86400);
    return d < 60 ? d + "d ago" : Math.floor(d / 30) + "mo ago";
  }
  function dstr(ts) { return ts > 0 ? new Date(ts * 1000).toISOString().slice(0, 10) : "—"; }
  function tidy(p) { return String(p || "").replace(/^\/home\/[^/]+/, "~"); }
  function esc(s) {
    return String(s === null || s === undefined ? "" : s)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
  }
  function base(p) { var a = String(p || "").split("/"); return a[a.length - 1] || p; }

  function isMeta(t) { return (t.metadataPercentComplete !== undefined && t.metadataPercentComplete < 1) || t.totalSize === 0; }
  function isDone(t) { return !isMeta(t) && t.percentDone >= 1; }
  function stateWord(t) {
    if (t.error) return "error";
    if (t.status === 0) return "stopped";
    if (t.status === 2) return "checking";
    if (t.status === 1 || t.status === 3 || t.status === 5) return "queued";
    if (t.status === 4) return "downloading";
    return t.peersGettingFromUs > 0 ? "seeding" : "idle";
  }
  function dotClass(t) {
    var w = stateWord(t);
    return w === "error" ? "err" : w === "stopped" ? "stop" : w === "downloading" ? "down"
      : w === "seeding" ? "seed" : "idle";
  }

  function visible() {
    var q = S.q.trim().toLowerCase();
    var list = S.order.map(function (id) { return S.torrents[id]; }).filter(Boolean);
    if (q) list = list.filter(function (t) {
      return t.name.toLowerCase().indexOf(q) >= 0 ||
        tidy(t.downloadDir).toLowerCase().indexOf(q) >= 0 ||
        (t.labels || []).join(" ").toLowerCase().indexOf(q) >= 0;
    });
    if (S.filter !== "all") list = list.filter(function (t) { return stateWord(t) === S.filter; });
    list.sort(function (a, b) {
      var ai = isDone(a) ? 1 : 0, bi = isDone(b) ? 1 : 0;
      if (ai !== bi) return ai - bi;
      return (a.queuePosition || 0) - (b.queuePosition || 0);
    });
    return list;
  }
  function totals() {
    var up = 0, dn = 0, n = 0, seeding = 0, stopped = 0, downloading = 0, size = 0;
    S.order.forEach(function (id) {
      var t = S.torrents[id]; if (!t) return;
      n++; up += t.rateUpload || 0; dn += t.rateDownload || 0;
      size += (t.totalSize || 0) * (t.percentDone || 0);
      var w = stateWord(t);
      if (w === "stopped") stopped++; else if (w === "downloading") downloading++; else seeding++;
    });
    return { up: up, dn: dn, n: n, seeding: seeding, stopped: stopped, downloading: downloading, size: size };
  }

  function toast(kind, title, msg) {
    if (!S.notify.on) return;
    var id = Math.random();
    S.toasts.push({ id: id, kind: kind, title: title, msg: msg });
    if (S.toasts.length > 3) S.toasts.shift();
    render.toasts();
    setTimeout(function () {
      S.toasts = S.toasts.filter(function (x) { return x.id !== id; });
      render.toasts();
    }, 5200);
    if (S.notify.native === "granted" && window.Notification) {
      try { new Notification("torrent.mvr.ac — " + title, { body: msg, tag: "mv-torrent-" + kind }); } catch (e) { }
    }
  }
  function askNative() {
    if (!window.Notification) { toast("warn", "Not available", "This browser exposes no notification API."); return; }
    Notification.requestPermission().then(function (p) {
      S.notify.native = p;
      if (p === "granted") toast("ok", "Notifications on", "Finished downloads will reach your desktop.");
      else toast("warn", "Notifications blocked", "Allow them in the browser's site settings.");
      if (S.sheet === "rules") render.sheet();
    });
  }

  function watch(list) {
    list.forEach(function (t) {
      var prev = S.seen[t.id];
      if (prev) {
        if (S.notify.done && !prev.done && isDone(t) && !isMeta(t)) {
          toast("ok", "Download finished", t.name + " → " + tidy(t.downloadDir));
        }
        var lim = t.seedRatioMode === 1 ? t.seedRatioLimit
          : t.seedRatioMode === 0 && S.session && S.session.seedRatioLimited ? S.session.seedRatioLimit : null;
        if (S.notify.ratio && lim !== null && prev.ratio < lim && t.uploadRatio >= lim) {
          toast("ok", "Seed target reached", t.name + " · ratio " + ratio(t.uploadRatio));
        }
        if (!prev.error && t.error) toast("warn", "Tracker problem", t.name + " · " + (t.errorString || "error " + t.error));
      }
      S.seen[t.id] = { done: isDone(t), ratio: t.uploadRatio, error: t.error };
    });
  }

  function refresh() {
    return rpc("torrent-get", { fields: LIST_FIELDS }).then(function (a) {
      var map = {}, order = [];
      (a.torrents || []).forEach(function (t) { map[t.id] = t; order.push(t.id); });
      watch(a.torrents || []);
      S.torrents = map; S.order = order; S.online = true; S.error = null;
      if (S.cur !== null && !map[S.cur]) S.cur = null;
      if (S.cur === null) { var v = visible(); if (v.length) S.cur = v[0].id; }
      return S.cur === null ? null : rpc("torrent-get", { ids: [S.cur], fields: DETAIL_FIELDS })
        .then(function (d) { S.detail = (d.torrents || [])[0] || null; });
    }).catch(function (e) {
      S.online = false; S.error = e.message || String(e);
    }).then(render.all);
  }
  function refreshSession() {
    return Promise.all([
      rpc("session-get").then(function (a) { S.session = a; }),
      rpc("session-stats").then(function (a) { S.stats = a; })
    ]).catch(function () { }).then(render.all);
  }
  function freeSpace(path) {
    if (!path) return Promise.resolve();
    return rpc("free-space", { path: path }).then(function (a) {
      S.free[path] = a["size-bytes"] >= 0 ? a["size-bytes"] : -1;
    }).catch(function () { S.free[path] = -1; });
  }

  window.TorrentApp = {
    S: S, render: render, rpc: rpc, refresh: refresh, refreshSession: refreshSession, freeSpace: freeSpace,
    fmt: { bytes: bytes, rate: rate, pct: pct, ratio: ratio, dur: dur, ago: ago, dstr: dstr, tidy: tidy, esc: esc, base: base },
    isMeta: isMeta, isDone: isDone, stateWord: stateWord, dotClass: dotClass,
    visible: visible, totals: totals, toast: toast, askNative: askNative, saveNotify: saveNotify
  };
})();

(function () {
  "use strict";
  var A = window.TorrentApp, S = A.S, F = A.fmt, rpc = A.rpc;
  var esc = F.esc, bytes = F.bytes, rate = F.rate, pct = F.pct, ratio = F.ratio,
    dur = F.dur, ago = F.ago, dstr = F.dstr, tidy = F.tidy, base = F.base;

  var $ = function (id) { return document.getElementById(id); };
  var app = $("app"), railEl = $("items"), filtersEl = $("filters"), paneEl = $("pane"),
    footEl = $("foot"), toastEl = $("toasts"), sheetEl = $("sheet"), offEl = $("offline"),
    offText = $("offlineText"), findEl = $("find"), turtleEl = $("turtle");

  function act(p, okMsg) {
    return p.then(function (r) {
      if (okMsg) A.toast("ok", okMsg.t, okMsg.m);
      return A.refresh().then(function () { return r; });
    }).catch(function (e) {
      A.toast("warn", "Did not work", e.message || String(e));
    });
  }
  function ids() { return S.cur === null ? [] : [S.cur]; }

  var ACT = {
    start: function (i, now) { return act(rpc(now ? "torrent-start-now" : "torrent-start", { ids: i })); },
    stop: function (i) { return act(rpc("torrent-stop", { ids: i })); },
    startAll: function () { return act(rpc("torrent-start", {}), { t: "Started", m: "Every torrent resumed" }); },
    stopAll: function () { return act(rpc("torrent-stop", {}), { t: "Paused", m: "Every torrent stopped" }); },
    verify: function (i) { return act(rpc("torrent-verify", { ids: i }), { t: "Verifying", m: "Rechecking local data" }); },
    reannounce: function (i) { return act(rpc("torrent-reannounce", { ids: i }), { t: "Reannounced", m: "Asked the trackers for peers" }); },
    remove: function (i, del) { return act(rpc("torrent-remove", { ids: i, "delete-local-data": !!del }), { t: del ? "Removed with data" : "Removed", m: del ? "Files deleted from disk" : "Files left on disk" }); },
    move: function (i, loc, mv) { return act(rpc("torrent-set-location", { ids: i, location: loc, move: !!mv }), { t: mv ? "Moving data" : "Location updated", m: tidy(loc) }); },
    set: function (i, args) { return act(rpc("torrent-set", Object.assign({ ids: i }, args))); },
    queue: function (i, where) { return act(rpc("queue-move-" + where, { ids: i })); },
    session: function (args) { return act(rpc("session-set", args).then(A.refreshSession)); },
    add: function (args) { return rpc("torrent-add", args); }
  };

  function copy(text, what) {
    var done = function () { A.toast("ok", "Copied", what); };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done, function () { fallbackCopy(text); done(); });
    } else { fallbackCopy(text); done(); }
  }
  function fallbackCopy(text) {
    var ta = document.createElement("textarea");
    ta.value = text; ta.setAttribute("readonly", "");
    ta.style.cssText = "position:fixed;top:-1000px";
    document.body.appendChild(ta); ta.select();
    try { document.execCommand("copy"); } catch (e) { }
    document.body.removeChild(ta);
  }

  function paintFilters() {
    var counts = { all: 0 };
    S.order.forEach(function (id) {
      var t = S.torrents[id]; if (!t) return;
      counts.all++;
      var w = A.stateWord(t); counts[w] = (counts[w] || 0) + 1;
    });
    var keys = ["all", "downloading", "seeding", "idle", "stopped", "error"];
    filtersEl.innerHTML = keys.filter(function (k) { return k === "all" || counts[k]; }).map(function (k) {
      return '<button class="chip' + (S.filter === k ? " on" : "") + '" data-filter="' + k + '">' +
        esc(k) + ' <span style="opacity:.6">' + (counts[k] || 0) + "</span></button>";
    }).join("");
  }

  function railRow(t) {
    var meta = A.isMeta(t), done = A.isDone(t);
    var gone = S.free[t.downloadDir] === -1;
    var line = gone ? "destination missing"
      : meta ? "fetching metadata"
      : done ? bytes(t.totalSize) + " · ×" + ratio(t.uploadRatio) + (t.rateUpload ? " · ▲" + rate(t.rateUpload) : "")
        : pct(t.percentDone) + " of " + bytes(t.totalSize) +
        (t.rateDownload ? " · ▼" + rate(t.rateDownload) : t.status === 0 ? " · stopped" : "");
    var bar = done ? "" :
      '<div class="bar ' + (meta ? "meta" : t.status === 0 ? "stalled" : "") + '">' +
      '<i' + (meta ? "" : ' style="width:' + (t.percentDone * 100).toFixed(1) + '%"') + "></i></div>";
    return '<div class="item' + (S.cur === t.id ? " on" : "") + '" data-id="' + t.id + '" role="button" tabindex="0">' +
      '<i class="dot ' + (gone ? "err" : A.dotClass(t)) + '"></i>' +
      '<div style="min-width:0"><div class="n" title="' + esc(t.name) + '">' + esc(t.name) + "</div>" +
      '<div class="m">' + esc(line) + "</div>" + bar + "</div></div>";
  }
  function paintRail() {
    var list = A.visible();
    list.forEach(function (t) { if (S.free[t.downloadDir] === undefined) A.freeSpace(t.downloadDir); });
    railEl.innerHTML = list.length ? list.map(railRow).join("")
      : '<div class="mv-empty">' + (S.q ? "nothing matches" : "no torrents") + "</div>";
  }

  function trackerChips(t) {
    var seen = {}, out = [];
    (t.trackerStats || []).forEach(function (ts) {
      var n = ts.sitename || ts.host || "";
      if (!n || seen[n]) return;
      seen[n] = 1;
      var alive = ts.lastAnnounceSucceeded || ts.lastScrapeSucceeded;
      out.push('<span class="chip flat' + (alive ? "" : " dead") + '" title="' + esc(ts.announce || "") + '">' + esc(n) + "</span>");
    });
    return out.join("");
  }

  function paintPane() {
    var t = S.detail;
    if (!t) {
      paneEl.innerHTML = '<div class="empty"><b>Nothing selected</b>' +
        "<span>Pick a torrent on the left, or add one.</span></div>";
      return;
    }
    var meta = A.isMeta(t), done = A.isDone(t);
    var lim = t.seedRatioMode === 1 ? t.seedRatioLimit
      : t.seedRatioMode === 0 && S.session && S.session.seedRatioLimited ? S.session.seedRatioLimit : null;
    var alive = (t.trackerStats || []).filter(function (x) { return x.lastAnnounceSucceeded || x.lastScrapeSucceeded; }).length;
    var wanted = (t.fileStats || []).filter(function (f) { return f.wanted; }).length;
    var under = meta ? "size unknown until metadata arrives"
      : pct(t.percentDone) + " of " + bytes(t.totalSize);
    var right = t.rateUpload ? '<span style="color:var(--mv-accent)">▲ ' + rate(t.rateUpload) + " to " + t.peersGettingFromUs + " peers</span>"
      : t.rateDownload ? '<span style="color:var(--mv-tone-3)">▼ ' + rate(t.rateDownload) + " · " + dur(t.eta) + " left</span>"
        : esc(A.stateWord(t)) + " · " + ago(t.activityDate);

    paneEl.innerHTML =
      '<div><div class="pane-head">' +
      '<button class="btn sm hide" id="back" data-back="1">‹ list</button>' +
      '<i class="dot ' + A.dotClass(t) + '"></i>' +
      '<span class="mv-label">' + esc(A.stateWord(t)) + "</span>" +
      (t.labels || []).map(function (l) { return '<span class="chip flat">' + esc(l) + "</span>"; }).join("") +
      '<button class="chip" data-sheet="label">+ label</button>' +
      '<span class="grow"></span>' +
      '<span class="mv-mono" style="font-size:var(--mv-text-xs);color:var(--mv-text-ghost)">#' + t.id + "</span>" +
      "</div>" +
      '<h1 class="title">' + esc(t.name) + "</h1>" +
      (t.errorString ? '<div class="line" style="border-color:var(--mv-down);margin-top:10px"><code style="color:var(--mv-down)">' + esc(t.errorString) + "</code></div>" : "") +
      '<div class="prog ' + (meta ? "meta" : "") + '" style="margin-top:14px"><i class="' + (done ? "" : "part") +
      '"' + (meta ? "" : ' style="width:' + (t.percentDone * 100).toFixed(1) + '%"') + "></i></div>" +
      '<div class="under"><span>' + esc(under) + "</span><span>" + right + "</span></div></div>" +

      '<div class="acts">' +
      '<button class="btn pri" data-do="' + (t.status === 0 ? "start" : "stop") + '">' + (t.status === 0 ? "▶ resume" : "❙❙ pause") + "</button>" +
      (t.status === 0 ? '<button class="btn" data-do="startnow">start now</button>' : "") +
      '<button class="btn" data-do="verify">verify</button>' +
      '<button class="btn" data-do="reannounce">reannounce</button>' +
      '<button class="btn" data-sheet="files">files' + (t.files ? " (" + wanted + "/" + t.files.length + ")" : "") + "</button>" +
      '<button class="btn danger" data-sheet="remove">remove…</button>' +
      "</div>" +

      '<div class="sec"><p class="mv-label">where it lives</p>' +
      '<div class="line"><code title="' + esc(t.downloadDir) + '">' + esc(tidy(t.downloadDir)) + "</code>" +
      '<button class="btn sm" data-sheet="loc">change</button></div>' +
      '<div class="under"><span>' + esc(base(t.downloadDir)) + "</span>" +
      (S.free[t.downloadDir] === -1
        ? '<span style="color:var(--mv-warn)">destination missing on disk</span>'
        : "<span>" + (S.free[t.downloadDir] !== undefined ? bytes(S.free[t.downloadDir]) + " free" : "") + "</span>") +
      "</div></div>" +

      '<div class="sec"><p class="mv-label">give it to someone</p>' +
      '<div class="line"><code>' + esc(t.magnetLink || "") + "</code>" +
      '<button class="btn sm" data-copy="magnet">copy</button></div>' +
      '<div class="under"><span>a magnet is the whole torrent — anyone with it can fetch from the swarm</span></div></div>' +

      '<div class="grid">' +
      '<div class="sec"><p class="mv-label">numbers</p><dl class="kv">' +
      "<dt>given</dt><dd>" + bytes(t.uploadedEver) + "</dd>" +
      "<dt>taken</dt><dd>" + bytes(t.downloadedEver) + "</dd>" +
      "<dt>ratio</dt><dd>" + ratio(t.uploadRatio) + "</dd>" +
      "<dt>pieces</dt><dd>" + (t.pieceCount || 0) + " × " + bytes(t.pieceSize) + "</dd>" +
      "<dt>seeding</dt><dd>" + dur(t.secondsSeeding) + "</dd>" +
      "</dl></div>" +
      '<div class="sec"><p class="mv-label">swarm</p><dl class="kv">' +
      "<dt>leeching</dt><dd>" + (t.peersGettingFromUs || 0) + "</dd>" +
      "<dt>seeds</dt><dd>" + (t.peersSendingToUs || 0) + "</dd>" +
      "<dt>peers</dt><dd>" + (t.peersConnected || 0) + "</dd>" +
      "<dt>trackers</dt><dd>" + alive + " / " + (t.trackerStats || []).length + " up</dd>" +
      "<dt>added</dt><dd>" + dstr(t.addedDate) + "</dd>" +
      "</dl></div>" +
      '<div class="sec"><p class="mv-label">seed until</p>' +
      '<div class="row"><input type="range" min="0" max="10" step="0.5" value="' + (lim === null ? 0 : lim) +
      '" id="ratioRange" style="flex:1"><span class="mv-mono" id="ratioOut" style="font-size:var(--mv-text-xs);min-width:62px;text-align:right">' +
      (lim === null ? "forever" : "×" + Number(lim).toFixed(1)) + "</span></div>" +
      '<div class="row"><span class="mv-label">priority</span><span>' +
      [["-1", "low"], ["0", "normal"], ["1", "high"]].map(function (p) {
        return '<button class="chip' + (String(t.bandwidthPriority) === p[0] ? " on" : "") + '" data-prio="' + p[0] + '">' + p[1] + "</button>";
      }).join(" ") + "</span></div>" +
      '<div class="row"><span class="mv-label">queue</span><span>' +
      '<button class="chip" data-queue="top">top</button> <button class="chip" data-queue="up">↑</button> ' +
      '<button class="chip" data-queue="down">↓</button> <button class="chip" data-queue="bottom">bottom</button>' +
      "</span></div></div></div>" +

      '<div class="sec"><p class="mv-label">trackers</p><div style="display:flex;flex-wrap:wrap;gap:5px">' +
      (trackerChips(t) || '<span class="mv-mono" style="font-size:var(--mv-text-xs);color:var(--mv-text-ghost)">none</span>') +
      '</div><div class="acts"><button class="btn sm" data-sheet="tracker">add a tracker</button></div></div>';

    var back = $("back");
    if (back) back.classList.toggle("hide", window.innerWidth > 720 ? true : false);
    if (S.free[t.downloadDir] === undefined) A.freeSpace(t.downloadDir).then(render.all);
  }

  function paintFoot() {
    var tt = A.totals(), ses = S.session || {};
    var cap = ses["alt-speed-enabled"] ? ses["alt-speed-up"] + " kB/s 🐢"
      : ses["speed-limit-up-enabled"] ? ses["speed-limit-up"] + " kB/s cap" : "no cap";
    var dd = ses["download-dir"];
    footEl.innerHTML =
      '<span><span class="up">▲ ' + rate(tt.up) + "</span> / <b>" + esc(cap) + "</b></span>" +
      '<span class="dn">▼ ' + rate(tt.dn) + "</span>" +
      "<span>" + tt.n + " torrents · " + tt.seeding + " seeding · " + tt.stopped + " stopped</span>" +
      '<span class="grow"></span>' +
      (dd && S.free[dd] !== undefined && S.free[dd] >= 0 ? "<span>" + bytes(S.free[dd]) + " free on " + esc(tidy(dd)) + "</span>" : "") +
      (ses["peer-port"] ? "<span>port " + ses["peer-port"] + "</span>" : "") +
      (ses.version ? "<span>transmission " + esc(ses.version) + "</span>" : "");
    if (dd && S.free[dd] === undefined) A.freeSpace(dd);
    turtleEl.setAttribute("aria-pressed", ses["alt-speed-enabled"] ? "true" : "false");
  }

  function paintToasts() {
    toastEl.innerHTML = S.toasts.map(function (x) {
      return '<div class="toast' + (x.kind === "warn" ? " warn" : "") + '">' +
        '<div class="t"><span>◈</span><span>' + esc(x.title) + "</span></div>" +
        '<div class="m" title="' + esc(x.msg) + '">' + esc(x.msg) + "</div></div>";
    }).join("");
  }

  function paintOffline() {
    var bad = !S.online;
    offEl.classList.toggle("hide", !bad);
    if (bad) offText.textContent = "transmission is not answering — " + (S.error || "no response") +
      ". The desktop may be asleep.";
  }

  var render = A.render;
  render.all = function () {
    paintOffline(); paintFilters(); paintRail(); paintPane(); paintFoot();
    app.classList.toggle("detail", S.mobileDetail);
  };
  render.toasts = paintToasts;
  render.sheet = paintSheet;

  function openSheet(name, arg) { S.sheet = name; S.sheetArg = arg || null; paintSheet(); }
  function closeSheet() { S.sheet = null; S.sheetArg = null; paintSheet(); }

  function knownDirs() {
    var seen = {}, out = [];
    if (S.session && S.session["download-dir"]) { seen[S.session["download-dir"]] = 1; out.push(S.session["download-dir"]); }
    S.order.forEach(function (id) {
      var d = S.torrents[id] && S.torrents[id].downloadDir;
      if (d && !seen[d]) { seen[d] = 1; out.push(d); }
    });
    return out.sort();
  }
  function dirOptions(onPick) {
    return knownDirs().map(function (d) {
      if (S.free[d] === undefined) A.freeSpace(d).then(function () { if (S.sheet) paintSheet(); });
      var f = S.free[d];
      return '<button class="opt" data-dir="' + esc(d) + '"><span class="p" title="' + esc(d) + '">' + esc(tidy(d)) + "</span>" +
        '<span class="f"' + (f === -1 ? ' style="color:var(--mv-warn)"' : "") + ">" +
        (f === -1 ? "missing" : f !== undefined ? bytes(f) + " free" : "…") + "</span></button>";
    }).join("");
  }
  function toggleRow(label, on, key) {
    return '<div class="row"><span>' + esc(label) + '</span><button class="btn sm' + (on ? " on" : "") +
      '" data-toggle="' + key + '">' + (on ? "on" : "off") + "</button></div>";
  }
  function rangeRow(label, key, min, max, step, val, suffix, on) {
    return '<div class="row"><span>' + esc(label) + '</span><span style="display:flex;gap:9px;align-items:center">' +
      '<input type="range" min="' + min + '" max="' + max + '" step="' + step + '" value="' + val + '" data-range="' + key + '">' +
      '<span class="mv-mono" style="font-size:var(--mv-text-xs);min-width:72px;text-align:right" data-out="' + key + '">' +
      val + suffix + "</span>" +
      (on === undefined ? "" : '<button class="btn sm' + (on ? " on" : "") + '" data-toggle="' + key + "-enabled" + '">' + (on ? "on" : "off") + "</button>") +
      "</span></div>";
  }

  function sheetAdd() {
    var dirs = knownDirs();
    return shell("Add torrents", "paste magnets or URLs, one per line — or pick .torrent files",
      '<textarea id="addText" rows="5" placeholder="magnet:?xt=urn:btih:…"></textarea>' +
      '<div class="row"><span>from a file</span><input type="file" id="addFile" accept=".torrent,application/x-bittorrent" multiple style="max-width:60%"></div>' +
      '<div class="row"><span>lands in</span><select id="addDir" style="max-width:60%;background:var(--mv-bg);border:1px solid var(--mv-line);border-radius:var(--mv-radius-1);color:var(--mv-text);font-family:var(--mv-font-mono);font-size:var(--mv-text-xs);padding:6px">' +
      dirs.map(function (d) { return '<option value="' + esc(d) + '">' + esc(tidy(d)) + "</option>"; }).join("") + "</select></div>" +
      '<div class="row"><span>start immediately</span><button class="btn sm on" id="addStart">yes</button></div>',
      '<button class="btn" data-close="1">cancel</button><button class="btn pri" id="addGo">add</button>');
  }
  function sheetLoc() {
    var t = S.detail;
    return shell("Save location", t ? esc(t.name) : "",
      '<div style="display:flex;gap:8px"><button class="opt on" style="flex:1" data-mode="move"><span class="p">move the data</span></button>' +
      '<button class="opt" style="flex:1" data-mode="set"><span class="p">just re-point</span></button></div>' +
      '<p class="mv-label">known destinations</p>' + dirOptions() +
      '<input type="text" id="locCustom" placeholder="/mnt/toshiba/hdd/new-folder">',
      '<button class="btn" data-close="1">cancel</button><button class="btn pri" id="locGo">move here</button>');
  }
  function sheetFiles() {
    var t = S.detail;
    if (!t || !t.files) return shell("Files", "", '<p class="mv-empty">no file list yet</p>', '<button class="btn" data-close="1">close</button>');
    var st = t.fileStats || [];
    var rows = t.files.map(function (f, i) {
      var s = st[i] || {};
      var p = s.priority === 1 ? "high" : s.priority === -1 ? "low" : "normal";
      return '<div class="file' + (s.wanted ? "" : " off") + '">' +
        '<input type="checkbox" data-file="' + i + '"' + (s.wanted ? " checked" : "") + ' aria-label="download this file">' +
        '<span class="fn" title="' + esc(f.name) + '">' + esc(base(f.name)) + "</span>" +
        '<span class="fs">' + bytes(f.length) + "</span>" +
        '<select data-fprio="' + i + '" style="background:var(--mv-bg);border:1px solid var(--mv-line);border-radius:3px;color:var(--mv-text);font-family:var(--mv-font-mono);font-size:10px;padding:2px">' +
        ["high", "normal", "low"].map(function (o) { return '<option value="' + o + '"' + (o === p ? " selected" : "") + ">" + o + "</option>"; }).join("") +
        "</select></div>";
    }).join("");
    return shell("Files", t.files.length + " in this torrent · uncheck to skip",
      '<div class="files">' + rows + "</div>",
      '<button class="btn pri" data-close="1">done</button>');
  }
  function sheetRules() {
    var s = S.session || {};
    return shell("Rules", "transmission " + esc(s.version || "") + " · rpc " + (s["rpc-version"] || ""),
      '<p class="mv-label">throttle seeding</p>' +
      rangeRow("upload cap", "speed-limit-up", 10, 2000, 10, s["speed-limit-up"] || 100, " kB/s", !!s["speed-limit-up-enabled"]) +
      rangeRow("download cap", "speed-limit-down", 10, 20000, 10, s["speed-limit-down"] || 100, " kB/s", !!s["speed-limit-down-enabled"]) +
      rangeRow("turtle up", "alt-speed-up", 5, 1000, 5, s["alt-speed-up"] || 200, " kB/s") +
      rangeRow("turtle down", "alt-speed-down", 5, 5000, 5, s["alt-speed-down"] || 50, " kB/s") +
      toggleRow("turtle now", !!s["alt-speed-enabled"], "alt-speed-enabled") +
      toggleRow("turtle on a schedule", !!s["alt-speed-time-enabled"], "alt-speed-time-enabled") +
      '<p class="mv-label">stop seeding when</p>' +
      rangeRow("ratio reaches", "seedRatioLimit", 0.5, 10, 0.5, s.seedRatioLimit || 2, "", !!s.seedRatioLimited) +
      rangeRow("idle for", "idle-seeding-limit", 5, 240, 5, s["idle-seeding-limit"] || 30, " min", !!s["idle-seeding-limit-enabled"]) +
      rangeRow("seed queue", "seed-queue-size", 1, 50, 1, s["seed-queue-size"] || 10, " slots", !!s["seed-queue-enabled"]) +
      rangeRow("download queue", "download-queue-size", 1, 20, 1, s["download-queue-size"] || 5, " slots", !!s["download-queue-enabled"]) +
      rangeRow("peer limit", "peer-limit-global", 20, 1000, 10, s["peer-limit-global"] || 200, " peers") +
      '<p class="mv-label">network</p>' +
      toggleRow("port forwarding", !!s["port-forwarding-enabled"], "port-forwarding-enabled") +
      toggleRow("distributed hash table", !!s["dht-enabled"], "dht-enabled") +
      toggleRow("peer exchange", !!s["pex-enabled"], "pex-enabled") +
      toggleRow("local peer discovery", !!s["lpd-enabled"], "lpd-enabled") +
      toggleRow("µTP", !!s["utp-enabled"], "utp-enabled") +
      toggleRow("blocklist (" + (s["blocklist-size"] || 0) + " rules)", !!s["blocklist-enabled"], "blocklist-enabled") +
      '<div class="row"><span>encryption</span><span>' +
      ["tolerated", "preferred", "required"].map(function (e) {
        return '<button class="chip' + (s.encryption === e ? " on" : "") + '" data-enc="' + e + '">' + e + "</button>";
      }).join(" ") + "</span></div>" +
      '<p class="mv-label">notifications</p>' +
      '<div class="row"><span>send to this desktop</span><span style="display:flex;gap:8px;align-items:center">' +
      '<span class="mv-mono" style="font-size:var(--mv-text-xs);color:var(--mv-text-ghost)">' +
      (S.notify.native === "granted" ? "granted" : S.notify.native === "denied" ? "blocked" : "not asked") + "</span>" +
      '<button class="btn sm' + (S.notify.native === "granted" ? " on" : "") + '" id="askNative">' +
      (S.notify.native === "granted" ? "live" : "allow") + "</button></span></div>" +
      toggleRow("show anything at all", S.notify.on, "n-on") +
      toggleRow("when a download finishes", S.notify.done, "n-done") +
      toggleRow("when a seed target is met", S.notify.ratio, "n-ratio"),
      '<button class="btn" id="portTest">test port</button><button class="btn pri" data-close="1">done</button>');
  }
  function sheetStats() {
    var st = S.stats, s = S.session || {};
    if (!st) return shell("Statistics", "", '<p class="mv-empty">no stats yet</p>', '<button class="btn" data-close="1">close</button>');
    var c = st["cumulative-stats"] || {}, cur = st["current-stats"] || {};
    var big = function (v, l) {
      return '<div><div class="mv-mono" style="font-size:1.5rem;color:var(--mv-accent);line-height:1">' + esc(v) +
        '</div><div class="mv-label" style="margin-top:4px">' + esc(l) + "</div></div>";
    };
    return shell("Statistics", (c.sessionCount || 0).toLocaleString() + " sessions · " + dur(c.secondsActive) + " active",
      '<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:var(--mv-space-4)">' +
      big(bytes(c.uploadedBytes), "given") + big(bytes(c.downloadedBytes), "taken") +
      big(c.downloadedBytes ? (c.uploadedBytes / c.downloadedBytes).toFixed(2) : "∞", "lifetime ratio") + "</div>" +
      '<div style="height:1px;background:var(--mv-line)"></div>' +
      '<dl class="kv">' +
      "<dt>this session up</dt><dd>" + bytes(cur.uploadedBytes) + "</dd>" +
      "<dt>this session down</dt><dd>" + bytes(cur.downloadedBytes) + "</dd>" +
      "<dt>uptime</dt><dd>" + dur(cur.secondsActive) + "</dd>" +
      "<dt>files added</dt><dd>" + (c.filesAdded || 0).toLocaleString() + "</dd>" +
      "<dt>active now</dt><dd>" + (st.activeTorrentCount || 0) + " of " + (st.torrentCount || 0) + "</dd>" +
      "<dt>on disk</dt><dd>" + bytes(A.totals().size) + " across " + knownDirs().length + " locations</dd>" +
      "</dl>" +
      '<div style="height:1px;background:var(--mv-line)"></div>' +
      '<p class="mv-label">free space</p>' + dirOptions(),
      '<button class="btn pri" data-close="1">close</button>');
  }
  function sheetTransfer() {
    var payload = JSON.stringify({
      exportedFrom: "torrent.mvr.ac",
      exportedAt: new Date().toISOString(),
      daemon: "transmission " + ((S.session && S.session.version) || "?"),
      session: S.session ? {
        "speed-limit-up": S.session["speed-limit-up"], "speed-limit-up-enabled": S.session["speed-limit-up-enabled"],
        "alt-speed-up": S.session["alt-speed-up"], "alt-speed-down": S.session["alt-speed-down"],
        seedRatioLimit: S.session.seedRatioLimit, seedRatioLimited: S.session.seedRatioLimited,
        "idle-seeding-limit": S.session["idle-seeding-limit"], "download-dir": S.session["download-dir"]
      } : null,
      torrents: S.order.map(function (id) {
        var t = S.torrents[id];
        return { name: t.name, downloadDir: t.downloadDir, labels: t.labels || [], paused: t.status === 0, uploadRatio: t.uploadRatio };
      })
    }, null, 1);
    return shell("Import and export", payload.length.toLocaleString() + " bytes · " + S.order.length + " torrents",
      '<p class="mv-label">export</p><textarea rows="8" readonly id="exportText">' + esc(payload) + "</textarea>" +
      '<p class="mv-label">import</p><textarea rows="4" id="importText" placeholder="paste a previous export, or magnets one per line"></textarea>',
      '<button class="btn" data-close="1">close</button><button class="btn" id="exportCopy">copy export</button><button class="btn pri" id="importGo">import</button>');
  }
  function sheetRemove() {
    var t = S.detail;
    return shell("Remove", t ? esc(t.name) : "",
      '<button class="opt" data-remove="keep"><span class="p">remove from the list — keep the files</span></button>' +
      '<button class="opt" style="border-color:var(--mv-down)" data-remove="delete"><span class="p">remove and delete the files on disk</span></button>',
      '<button class="btn" data-close="1">cancel</button>');
  }
  function sheetLabel() {
    var t = S.detail, cur = (t && t.labels) || [];
    var all = {};
    S.order.forEach(function (id) { ((S.torrents[id] || {}).labels || []).forEach(function (l) { all[l] = 1; }); });
    return shell("Labels", "transmission stores these on the torrent itself",
      '<div style="display:flex;flex-wrap:wrap;gap:6px">' +
      Object.keys(all).sort().map(function (l) {
        return '<button class="chip' + (cur.indexOf(l) >= 0 ? " on" : "") + '" data-label="' + esc(l) + '">' + esc(l) + "</button>";
      }).join("") + "</div>" +
      '<input type="text" id="labelNew" placeholder="a new label, then Enter">',
      '<button class="btn pri" data-close="1">done</button>');
  }
  function sheetTracker() {
    return shell("Add a tracker", S.detail ? esc(S.detail.name) : "",
      '<input type="text" id="trackerUrl" placeholder="udp://tracker.opentrackr.org:1337/announce">',
      '<button class="btn" data-close="1">cancel</button><button class="btn pri" id="trackerGo">add</button>');
  }

  function shell(title, sub, body, foot) {
    return '<div class="scrim" data-scrim="1"><div class="sheet" role="dialog" aria-modal="true" aria-label="' + esc(title) + '">' +
      "<h2>" + esc(title) + '</h2><div class="sub">' + sub + "</div>" +
      '<div class="in">' + body + "</div><footer>" + foot + "</footer></div></div>";
  }
  function paintSheet() {
    var map = {
      add: sheetAdd, loc: sheetLoc, files: sheetFiles, rules: sheetRules,
      stats: sheetStats, transfer: sheetTransfer, remove: sheetRemove, label: sheetLabel, tracker: sheetTracker
    };
    sheetEl.innerHTML = S.sheet && map[S.sheet] ? map[S.sheet]() : "";
    var first = sheetEl.querySelector("textarea, input, button");
    if (first) first.focus();
  }

  var locMode = "move";

  document.addEventListener("click", function (e) {
    var el = e.target.closest("[data-id],[data-filter],[data-do],[data-sheet],[data-close],[data-scrim],[data-copy]," +
      "[data-dir],[data-mode],[data-remove],[data-label],[data-prio],[data-queue],[data-toggle],[data-enc],[data-back]");
    if (!el) return;
    var d = el.dataset;

    if (d.scrim !== undefined && e.target === el) return closeSheet();
    if (d.close !== undefined) return closeSheet();
    if (d.back !== undefined) { S.mobileDetail = false; return render.all(); }
    if (d.id !== undefined) {
      S.cur = Number(d.id); S.detail = null; S.mobileDetail = true;
      render.all();
      return rpc("torrent-get", { ids: [S.cur], fields: ["id", "name", "status", "percentDone", "metadataPercentComplete",
        "totalSize", "rateDownload", "rateUpload", "uploadRatio", "eta", "labels", "errorString", "error",
        "peersGettingFromUs", "peersSendingToUs", "peersConnected", "addedDate", "activityDate", "doneDate",
        "downloadDir", "queuePosition", "isFinished", "hashString", "magnetLink", "pieceCount", "pieceSize",
        "downloadedEver", "uploadedEver", "seedRatioLimit", "seedRatioMode", "bandwidthPriority", "files",
        "fileStats", "trackerStats", "secondsSeeding", "isPrivate"] })
        .then(function (r) { S.detail = (r.torrents || [])[0] || null; render.all(); });
    }
    if (d.filter !== undefined) { S.filter = d.filter; return render.all(); }
    if (d.sheet !== undefined) return openSheet(d.sheet);
    if (d.copy === "magnet" && S.detail) return copy(S.detail.magnetLink || "", "magnet link");
    if (d.do !== undefined) {
      var i = ids();
      if (d.do === "start") return ACT.start(i);
      if (d.do === "startnow") return ACT.start(i, true);
      if (d.do === "stop") return ACT.stop(i);
      if (d.do === "verify") return ACT.verify(i);
      if (d.do === "reannounce") return ACT.reannounce(i);
    }
    if (d.mode !== undefined) {
      locMode = d.mode;
      sheetEl.querySelectorAll("[data-mode]").forEach(function (b) { b.classList.toggle("on", b.dataset.mode === locMode); });
      var go = $("locGo"); if (go) go.textContent = locMode === "move" ? "move here" : "re-point here";
      return;
    }
    if (d.dir !== undefined) {
      if (S.sheet === "loc") { closeSheet(); return ACT.move(ids(), d.dir, locMode === "move"); }
      return;
    }
    if (d.remove !== undefined) { closeSheet(); return ACT.remove(ids(), d.remove === "delete"); }
    if (d.label !== undefined && S.detail) {
      var cur = (S.detail.labels || []).slice(), at = cur.indexOf(d.label);
      if (at >= 0) cur.splice(at, 1); else cur.push(d.label);
      return ACT.set(ids(), { labels: cur }).then(function () { if (S.sheet === "label") paintSheet(); });
    }
    if (d.prio !== undefined) return ACT.set(ids(), { bandwidthPriority: Number(d.prio) });
    if (d.queue !== undefined) return ACT.queue(ids(), d.queue);
    if (d.enc !== undefined) return ACT.session({ encryption: d.enc }).then(function () { if (S.sheet === "rules") paintSheet(); });
    if (d.toggle !== undefined) {
      var k = d.toggle;
      if (k === "n-on") { S.notify.on = !S.notify.on; A.saveNotify(); return paintSheet(); }
      if (k === "n-done") { S.notify.done = !S.notify.done; A.saveNotify(); return paintSheet(); }
      if (k === "n-ratio") { S.notify.ratio = !S.notify.ratio; A.saveNotify(); return paintSheet(); }
      var s = S.session || {}, args = {};
      args[k] = !s[k];
      return ACT.session(args).then(function () { if (S.sheet) paintSheet(); });
    }
  });

  document.addEventListener("input", function (e) {
    var el = e.target;
    if (el.id === "find") { S.q = el.value; return render.all(); }
    if (el.id === "ratioRange") {
      var v = Number(el.value), out = $("ratioOut");
      if (out) out.textContent = v === 0 ? "forever" : "×" + v.toFixed(1);
      return;
    }
    if (el.dataset && el.dataset.range !== undefined) {
      var out2 = sheetEl.querySelector('[data-out="' + el.dataset.range + '"]');
      if (out2) out2.textContent = el.value + (out2.textContent.replace(/^[\d.]+/, "") || "");
    }
  });
  document.addEventListener("change", function (e) {
    var el = e.target;
    if (el.id === "ratioRange") {
      var v = Number(el.value);
      return ACT.set(ids(), v === 0 ? { seedRatioMode: 2 } : { seedRatioMode: 1, seedRatioLimit: v });
    }
    if (el.dataset && el.dataset.range !== undefined) {
      var k = el.dataset.range, args = {};
      args[k] = k === "seedRatioLimit" ? Number(el.value) : Math.round(Number(el.value));
      return ACT.session(args);
    }
    if (el.dataset && el.dataset.file !== undefined) {
      var idx = Number(el.dataset.file);
      var a = el.checked ? { "files-wanted": [idx] } : { "files-unwanted": [idx] };
      return ACT.set(ids(), a).then(function () { if (S.sheet === "files") paintSheet(); });
    }
    if (el.dataset && el.dataset.fprio !== undefined) {
      var i2 = Number(el.dataset.fprio), key = "priority-" + el.value, a2 = {};
      a2[key] = [i2];
      return ACT.set(ids(), a2);
    }
  });
  document.addEventListener("keydown", function (e) {
    var tag = (e.target.tagName || "").toLowerCase();
    var typing = tag === "input" || tag === "textarea" || tag === "select";
    if (e.key === "Escape") { if (S.sheet) closeSheet(); else if (typing) e.target.blur(); return; }
    if (typing) {
      if (e.key === "Enter" && e.target.id === "labelNew" && e.target.value.trim() && S.detail) {
        var cur = (S.detail.labels || []).concat([e.target.value.trim()]);
        e.target.value = "";
        ACT.set(ids(), { labels: cur }).then(function () { if (S.sheet === "label") paintSheet(); });
      }
      if (e.key === "Enter" && e.target.id === "locCustom" && e.target.value.trim()) {
        var p = e.target.value.trim(); closeSheet(); ACT.move(ids(), p, locMode === "move");
      }
      return;
    }
    if (e.key === "/") { e.preventDefault(); findEl.focus(); findEl.select(); return; }
    var list = A.visible(), at = list.findIndex(function (t) { return t.id === S.cur; });
    if (e.key === "j" || e.key === "ArrowDown") { e.preventDefault(); at = Math.min(list.length - 1, at + 1); }
    else if (e.key === "k" || e.key === "ArrowUp") { e.preventDefault(); at = Math.max(0, at - 1); }
    else if (e.key === " ") { e.preventDefault(); if (S.detail) return S.detail.status === 0 ? ACT.start(ids()) : ACT.stop(ids()); return; }
    else return;
    if (list[at] && list[at].id !== S.cur) {
      S.cur = list[at].id;
      rpc("torrent-get", { ids: [S.cur], fields: ["id", "name", "status", "percentDone", "metadataPercentComplete",
        "totalSize", "rateDownload", "rateUpload", "uploadRatio", "eta", "labels", "errorString", "error",
        "peersGettingFromUs", "peersSendingToUs", "peersConnected", "addedDate", "activityDate", "downloadDir",
        "queuePosition", "hashString", "magnetLink", "pieceCount", "pieceSize", "downloadedEver", "uploadedEver",
        "seedRatioLimit", "seedRatioMode", "bandwidthPriority", "files", "fileStats", "trackerStats", "secondsSeeding"] })
        .then(function (r) { S.detail = (r.torrents || [])[0] || null; render.all(); });
      render.all();
      var node = railEl.querySelector('[data-id="' + S.cur + '"]');
      if (node) node.scrollIntoView({ block: "nearest" });
    }
  });

  sheetEl.addEventListener("click", function (e) {
    var id = e.target.id;
    if (id === "askNative") return A.askNative();
    if (id === "portTest") {
      return rpc("port-test").then(function (r) {
        A.toast(r["port-is-open"] ? "ok" : "warn", r["port-is-open"] ? "Port is open" : "Port is closed",
          "peer port " + ((S.session && S.session["peer-port"]) || "?"));
      }).catch(function (e2) { A.toast("warn", "Port test failed", e2.message); });
    }
    if (id === "exportCopy") { var ta = $("exportText"); return copy(ta ? ta.value : "", "session export"); }
    if (id === "importGo") return doImport();
    if (id === "addGo") return doAdd();
    if (id === "addStart") {
      e.target.classList.toggle("on");
      e.target.textContent = e.target.classList.contains("on") ? "yes" : "no";
      return;
    }
    if (id === "locGo") {
      var v = ($("locCustom") || {}).value;
      if (v && v.trim()) { closeSheet(); return ACT.move(ids(), v.trim(), locMode === "move"); }
      return A.toast("warn", "Pick a destination", "Choose one above or type a path.");
    }
    if (id === "trackerGo") {
      var u = ($("trackerUrl") || {}).value;
      if (!u || !u.trim()) return;
      closeSheet();
      return ACT.set(ids(), { trackerAdd: [u.trim()] }).then(function () { A.toast("ok", "Tracker added", u.trim()); });
    }
  });

  function magnetsIn(text) {
    return (text.match(/magnet:\?[^\s"']+/g) || []).concat(
      (text.match(/https?:\/\/\S+\.torrent\b/g) || []));
  }
  function doAdd() {
    var text = ($("addText") || {}).value || "";
    var dir = ($("addDir") || {}).value || undefined;
    var paused = !($("addStart") && $("addStart").classList.contains("on"));
    var files = ($("addFile") || {}).files || [];
    var jobs = magnetsIn(text).map(function (m) {
      return ACT.add({ filename: m, "download-dir": dir, paused: paused });
    });
    Array.prototype.forEach.call(files, function (f) {
      jobs.push(new Promise(function (res, rej) {
        var r = new FileReader();
        r.onload = function () {
          var b64 = String(r.result).split(",")[1];
          ACT.add({ metainfo: b64, "download-dir": dir, paused: paused }).then(res, rej);
        };
        r.onerror = rej;
        r.readAsDataURL(f);
      }));
    });
    if (!jobs.length) return A.toast("warn", "Nothing to add", "Paste a magnet or choose a .torrent file.");
    closeSheet();
    Promise.allSettled(jobs).then(function (rs) {
      var ok = rs.filter(function (r) { return r.status === "fulfilled"; }).length;
      var dup = rs.filter(function (r) { return r.status === "rejected" && /duplicate/i.test(r.reason && r.reason.message || ""); }).length;
      if (ok) A.toast("ok", "Added " + ok, "into " + tidy(dir || ""));
      if (dup) A.toast("warn", dup + " already here", "duplicate torrents were skipped");
      if (!ok && !dup) A.toast("warn", "Nothing added", (rs[0] && rs[0].reason && rs[0].reason.message) || "rejected");
      A.refresh();
    });
  }
  function doImport() {
    var text = ($("importText") || {}).value || "";
    var found = magnetsIn(text);
    if (!found.length) {
      try {
        var doc = JSON.parse(text);
        (doc.torrents || []).forEach(function (t) { if (t.magnet) found.push(t.magnet); });
      } catch (e) { }
    }
    if (!found.length) return A.toast("warn", "Nothing to import", "No magnets found in that text.");
    closeSheet();
    Promise.allSettled(found.map(function (m) { return ACT.add({ filename: m }); })).then(function (rs) {
      var ok = rs.filter(function (r) { return r.status === "fulfilled"; }).length;
      A.toast(ok ? "ok" : "warn", ok ? "Imported " + ok : "Imported nothing", found.length + " candidates");
      A.refresh();
    });
  }

  $("add").onclick = function () { openSheet("add"); };
  $("stats").onclick = function () { openSheet("stats"); };
  $("transfer").onclick = function () { openSheet("transfer"); };
  $("rules").onclick = function () { openSheet("rules"); };
  $("retry").onclick = function () { A.refresh(); A.refreshSession(); };
  turtleEl.onclick = function () {
    var on = !(S.session && S.session["alt-speed-enabled"]);
    ACT.session({ "alt-speed-enabled": on }).then(function () {
      A.toast("ok", on ? "Turtle on" : "Turtle off",
        on ? ((S.session && S.session["alt-speed-up"]) || "?") + " kB/s up" : "back to the normal cap");
    });
  };

  window.addEventListener("resize", function () { if (window.innerWidth > 720) S.mobileDetail = false; render.all(); });

  A.refreshSession().then(A.refresh);
  setInterval(function () { if (!document.hidden) A.refresh(); }, 2000);
  setInterval(function () { if (!document.hidden) A.refreshSession(); }, 15000);
  document.addEventListener("visibilitychange", function () { if (!document.hidden) { A.refresh(); A.refreshSession(); } });
})();
