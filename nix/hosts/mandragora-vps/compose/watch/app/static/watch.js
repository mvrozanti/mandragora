(function () {
  var $ = function (id) { return document.getElementById(id); };
  var esc = function (v) {
    return String(v == null ? "" : v).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  };

  var state = {
    view: "inbox",
    filter: "all",
    watcherId: null,
    unackedOnly: false,
    showHidden: false,
    selected: null,
    health: null,
    watchers: [],
    events: [],
    releaseEvents: [],
    kinds: {},
    addOpen: false,
    busy: false
  };

  var api = function (method, path, body) {
    var opts = { method: method, credentials: "same-origin", cache: "no-store" };
    if (body !== undefined) {
      opts.headers = { "Content-Type": "application/json" };
      opts.body = JSON.stringify(body);
    }
    return fetch(path, opts).then(function (r) {
      if (!r.ok) return r.text().then(function (t) { throw new Error(t || r.status); });
      return r.status === 204 ? null : r.json();
    });
  };

  var toastTimer = null;
  var toast = function (msg, isError) {
    var el = $("toast");
    el.textContent = msg;
    el.className = "wa-toast" + (isError ? " err" : "");
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.hidden = true; }, isError ? 6000 : 2600);
  };

  var ago = function (iso) {
    if (!iso) return "never";
    var mins = (Date.now() - Date.parse(iso)) / 60000;
    if (!isFinite(mins)) return "?";
    if (mins < 1) return "just now";
    if (mins < 60) return Math.round(mins) + "m ago";
    if (mins < 1440) return Math.round(mins / 60) + "h ago";
    return Math.round(mins / 1440) + "d ago";
  };

  var verdictOf = function (e) {
    if (e.ai_verdict) return e.ai_verdict;
    return e.watcher_has_ai ? "pending" : "unfiltered";
  };
  var isRelease = function (e) { return e.watcher_kind === "github_release"; };

  var scoped = function () {
    return state.events.filter(function (e) {
      if (state.watcherId != null && e.watcher_id !== state.watcherId) return false;
      if (state.unackedOnly && e.acked_at) return false;
      return true;
    });
  };
  var inboxAll = function () { return scoped().filter(function (e) { return !isRelease(e); }); };
  var inboxLive = function () {
    return inboxAll().filter(function (e) {
      var v = verdictOf(e);
      if (state.filter === "all") return v !== "NO";
      return v === state.filter;
    });
  };
  var inboxHidden = function () {
    if (state.filter !== "all") return [];
    return inboxAll().filter(function (e) { return verdictOf(e) === "NO"; });
  };
  var releases = function () {
    return state.releaseEvents.filter(function (e) {
      if (state.watcherId != null && e.watcher_id !== state.watcherId) return false;
      if (state.unackedOnly && e.acked_at) return false;
      return true;
    });
  };

  var wState = function (w) {
    if (w.last_error) return "is-down";
    if (w.spec_lint && w.spec_lint.decidable === false) return "is-warn";
    if (!w.enabled) return "is-unknown";
    return "is-ok";
  };
  var wChips = function (w) {
    var out = [];
    if (w.last_error) out.push('<span class="mv-pill is-down">failing</span>');
    if (w.spec_lint && w.spec_lint.decidable === false) out.push('<span class="mv-pill is-warn">spec undecidable</span>');
    if (!w.enabled) out.push('<span class="mv-pill">paused</span>');
    if (!w.push) out.push('<span class="mv-pill">feed only</span>');
    if (w.requires_ack) out.push('<span class="mv-pill">needs ack</span>');
    if (!w.ai_spec) out.push('<span class="mv-pill">no filter</span>');
    return out.join("");
  };

  var renderFunnel = function () {
    var h = state.health;
    if (!h) { $("funnel").innerHTML = ""; return; }
    var f = h.funnel_24h || {};
    var seg = function (key, cls, label, value) {
      return '<button class="wa-seg ' + cls + '" data-act="seg" data-arg="' + key +
        '" aria-pressed="' + (state.filter === key) + '">' +
        '<span class="k">' + label + '</span><span class="v">' + value + "</span></button>";
    };
    $("funnel").innerHTML =
      seg("all", "", "arrived 24h", h.events_24h || 0) +
      seg("NO", "no", "rejected", f.NO || 0) +
      seg("UNCLEAR", "unclear", "unclear", f.UNCLEAR || 0) +
      seg("GO", "go", "passed", f.GO || 0);

    var tasks = h.tasks || {};
    var taskDot = function (name) {
      var alive = tasks[name] === "alive";
      return '<span><i class="mv-dot ' + (alive ? "is-ok" : "is-down") + '"></i>' + name + "</span>";
    };
    $("health").innerHTML =
      taskDot("poller") + taskDot("judge") +
      '<span><i class="mv-dot ' + (h.telegram_enabled ? "is-ok" : "is-warn") + '"></i>telegram</span>' +
      "<span>last poll <b>" + ago(h.last_poll_at) + "</b></span>" +
      "<span>last push <b>" + ago(h.last_push_at) + "</b></span>" +
      (h.pending_unjudged ? "<span><i class='mv-dot is-warn'></i>" + h.pending_unjudged + " unjudged</span>" : "");
  };

  var renderTabs = function () {
    var counts = { inbox: inboxLive().length, releases: releases().length, watchers: state.watchers.length };
    Array.prototype.forEach.call(document.querySelectorAll(".wa-tab"), function (t) {
      var v = t.dataset.v;
      t.setAttribute("aria-selected", String(state.view === v));
      t.innerHTML = v + '<span class="n">' + counts[v] + "</span>";
    });
  };

  var evHTML = function (e) {
    var v = verdictOf(e);
    var reason = e.ai_reason
      ? '<div class="wa-ev__reason">' + esc(e.ai_reason) + (e.ai_claim ? " — <em>" + esc(e.ai_claim) + "</em>" : "") + "</div>"
      : "";
    return '<article class="wa-ev' + (e.acked_at ? " is-acked" : "") + '">' +
      '<div class="wa-ev__head"><span class="wa-verdict ' + v + '">' + v + "</span>" +
      '<a class="wa-ev__title" href="' + esc(e.link || "#") + '" target="_blank" rel="noopener">' + esc(e.title) + "</a></div>" +
      '<div class="wa-ev__meta"><span>' + esc(e.watcher_name || e.watcher_target) + "</span>" +
      "<span>" + esc(state.kinds[e.watcher_kind] ? state.kinds[e.watcher_kind].label : e.watcher_kind) + "</span>" +
      "<span>" + ago(e.received_at) + "</span>" +
      (e.acked_at ? "<span>acked</span>" : "") + "</div>" + reason +
      '<div class="wa-ev__acts">' +
      (e.acked_at ? "" : '<button class="wa-btn" data-act="ack" data-arg="' + e.id + '">ack</button>') +
      (e.watcher_has_ai ? '<button class="wa-btn" data-act="rejudge" data-arg="' + e.id + '">re-judge</button>' : "") +
      '<button class="wa-btn" data-act="onlywatcher" data-arg="' + e.watcher_id + '">only this</button>' +
      "</div></article>";
  };

  var scopeBar = function () {
    var w = state.watcherId != null
      ? state.watchers.filter(function (x) { return x.id === state.watcherId; })[0]
      : null;
    return '<div class="wa-ev__acts" style="margin:var(--mv-space-3) 0">' +
      '<button class="wa-btn" data-act="unacked" aria-pressed="' + state.unackedOnly + '">' +
      (state.unackedOnly ? "showing unacked" : "unacked only") + "</button>" +
      (w ? '<button class="wa-btn" data-act="clearwatcher">' + esc(w.name || w.target) + " ×</button>" : "") +
      (state.filter !== "all" ? '<button class="wa-btn" data-act="seg" data-arg="all">' + state.filter + " ×</button>" : "") +
      "</div>";
  };

  var renderInbox = function () {
    var live = inboxLive();
    var hidden = inboxHidden();
    var body = live.length
      ? live.map(evHTML).join("")
      : '<p class="mv-empty">nothing here — the judge let nothing through in this window</p>';
    var tail = "";
    if (hidden.length) {
      tail = state.showHidden
        ? '<button class="wa-collapsed" data-act="hide">▾ <b>' + hidden.length + " rejected</b> — collapse</button>" +
          hidden.map(evHTML).join("")
        : '<button class="wa-collapsed" data-act="show">▸ <b>' + hidden.length +
          " rejected by the judge</b> — expand to audit</button>";
    }
    $("view").innerHTML = scopeBar() + body + tail;
  };

  var renderReleases = function () {
    var rows = releases();
    if (!rows.length) { $("view").innerHTML = scopeBar() + '<p class="mv-empty">no releases in this window</p>'; return; }
    $("view").innerHTML = scopeBar() + rows.map(function (e) {
      return '<article class="wa-ev' + (e.acked_at ? " is-acked" : "") + '">' +
        '<div class="wa-ev__head"><span class="mv-pill">' + esc(e.watcher_target) + "</span>" +
        '<a class="wa-ev__title" href="' + esc(e.link || "#") + '" target="_blank" rel="noopener">' + esc(e.title) + "</a></div>" +
        '<div class="wa-ev__meta"><span>' + ago(e.received_at) + "</span>" +
        (e.acked_at ? "<span>acked</span>" : "") + "</div>" +
        '<div class="wa-ev__acts">' +
        (e.acked_at ? "" : '<button class="wa-btn" data-act="ack" data-arg="' + e.id + '">ack</button>') +
        '<button class="wa-btn" data-act="onlywatcher" data-arg="' + e.watcher_id + '">only this</button></div></article>';
    }).join("");
  };

  var addForm = function () {
    if (!state.addOpen) {
      return '<div class="wa-form" style="grid-template-columns:1fr"><button class="wa-btn primary" data-act="openadd">add a watcher</button></div>';
    }
    var opts = Object.keys(state.kinds).map(function (k) {
      return '<option value="' + k + '">' + esc(state.kinds[k].label) + "</option>";
    }).join("");
    return '<form class="wa-form" id="addform">' +
      '<div class="wa-field"><label for="f-kind">source</label><select class="wa-select" id="f-kind">' + opts + "</select></div>" +
      '<div class="wa-field"><label for="f-target">target</label><input class="wa-input" id="f-target" placeholder="owner/repo, @handle, search terms…"></div>' +
      '<div class="wa-field wide"><label for="f-name">name</label><input class="wa-input" id="f-name" placeholder="optional display name"></div>' +
      '<div class="wa-field wide"><label for="f-spec">relevance spec</label>' +
      '<textarea class="wa-area" id="f-spec" placeholder="what counts as a real match — leave blank for no AI filter"></textarea></div>' +
      '<div class="wa-checks wide"><label><input type="checkbox" id="f-ack"> needs ack</label>' +
      '<label><input type="checkbox" id="f-push" checked> push to telegram</label>' +
      '<input class="wa-input" id="f-interval" style="max-width:11rem" placeholder="reminder secs (3600)"></div>' +
      '<div class="wa-ev__acts wide"><button class="wa-btn primary" type="submit">create</button>' +
      '<button class="wa-btn" type="button" data-act="canceladd">cancel</button></div></form>';
  };

  var renderWatchers = function () {
    var sorted = state.watchers.slice().sort(function (a, b) {
      var rank = function (w) {
        if (w.last_error) return 0;
        if (w.spec_lint && w.spec_lint.decidable === false) return 1;
        if (!w.enabled) return 2;
        return 3;
      };
      return rank(a) - rank(b) || b.event_count - a.event_count;
    });
    $("view").innerHTML = addForm() + sorted.map(function (w) {
      var open = state.selected === w.id;
      var panel = "";
      if (open) {
        panel = '<div class="wa-w__panel">' +
          (w.last_error ? '<p class="wa-w__err">' + esc(w.last_error) + "</p>" : "") +
          (w.spec_lint && w.spec_lint.decidable === false
            ? '<p class="wa-w__lint">spec lint: ' + esc(w.spec_lint.reason || "not decidable from this source") + "</p>" : "") +
          '<div class="wa-field"><label for="spec-' + w.id + '">relevance spec</label>' +
          '<textarea class="wa-area" id="spec-' + w.id + '">' + esc(w.ai_spec || "") + "</textarea></div>" +
          '<div class="wa-ev__acts">' +
          '<button class="wa-btn primary" data-act="savespec" data-arg="' + w.id + '">save spec</button>' +
          '<button class="wa-btn" data-act="poll" data-arg="' + w.id + '">poll now</button>' +
          '<button class="wa-btn" data-act="toggle" data-arg="' + w.id + '">' + (w.enabled ? "pause" : "resume") + "</button>" +
          '<button class="wa-btn" data-act="push" data-arg="' + w.id + '">' + (w.push ? "mute push" : "unmute push") + "</button>" +
          '<button class="wa-btn" data-act="reqack" data-arg="' + w.id + '">' + (w.requires_ack ? "stop nagging" : "require ack") + "</button>" +
          '<button class="wa-btn" data-act="onlywatcher" data-arg="' + w.id + '">view events</button>' +
          (w.unacked_count ? '<button class="wa-btn" data-act="ackall" data-arg="' + w.id + '">ack all ' + w.unacked_count + "</button>" : "") +
          '<button class="wa-btn danger" data-act="del" data-arg="' + w.id + '">delete</button>' +
          "</div></div>";
      }
      return '<div class="wa-w">' +
        '<button class="wa-w__row" data-act="select" data-arg="' + w.id + '" aria-expanded="' + open + '">' +
        '<span class="mv-dot ' + wState(w) + '"></span>' +
        '<span><span class="wa-w__name">' + esc(w.name || w.target) + "</span>" +
        '<span class="wa-w__target">' + esc(w.kind) + " · " + esc(w.target) + "</span>" +
        '<span class="wa-w__chips">' + wChips(w) + "</span></span>" +
        '<span class="wa-w__tail"><span>' + w.event_count + "</span><span>" + ago(w.last_polled_at) + "</span></span>" +
        "</button>" + panel + "</div>";
    }).join("");
  };

  var render = function () {
    renderFunnel();
    renderTabs();
    if (state.view === "inbox") renderInbox();
    else if (state.view === "releases") renderReleases();
    else renderWatchers();
    $("count").textContent = state.watchers.length + " watchers · " +
      (state.health ? state.health.events_24h + " events today" : "…");
  };

  var loadAll = function () {
    return Promise.all([
      api("GET", "/healthz"),
      api("GET", "/api/watchers"),
      api("GET", "/api/events?limit=300"),
      api("GET", "/api/kinds"),
      api("GET", "/api/events?kind=github_release&limit=120")
    ]).then(function (res) {
      state.health = res[0];
      state.watchers = res[1];
      state.events = res[2];
      state.kinds = res[3];
      state.releaseEvents = res[4];
      render();
    }).catch(function (err) {
      toast("could not load: " + err.message, true);
    });
  };

  var withBusy = function (promise, okMsg) {
    if (state.busy) return;
    state.busy = true;
    return promise
      .then(function () { if (okMsg) toast(okMsg); return loadAll(); })
      .catch(function (err) { toast(err.message || "failed", true); })
      .then(function () { state.busy = false; });
  };

  var ACTS = {
    seg: function (arg) { state.filter = arg; state.view = "inbox"; state.showHidden = false; render(); },
    unacked: function () { state.unackedOnly = !state.unackedOnly; render(); },
    clearwatcher: function () { state.watcherId = null; render(); },
    onlywatcher: function (arg) { state.watcherId = +arg; state.view = "inbox"; render(); },
    show: function () { state.showHidden = true; render(); },
    hide: function () { state.showHidden = false; render(); },
    select: function (arg) { state.selected = state.selected === +arg ? null : +arg; render(); },
    openadd: function () { state.addOpen = true; render(); },
    canceladd: function () { state.addOpen = false; render(); },
    ack: function (arg) { withBusy(api("POST", "/api/events/" + arg + "/ack"), "acked"); },
    rejudge: function (arg) { withBusy(api("POST", "/api/events/" + arg + "/judge"), "re-judged"); },
    poll: function (arg) { withBusy(api("POST", "/api/watchers/" + arg + "/poll"), "polled"); },
    ackall: function (arg) { withBusy(api("POST", "/api/watchers/" + arg + "/ack-all"), "all acked"); },
    toggle: function (arg) { withBusy(api("POST", "/api/watchers/" + arg + "/toggle")); },
    push: function (arg) {
      var w = state.watchers.filter(function (x) { return x.id === +arg; })[0];
      withBusy(api("PATCH", "/api/watchers/" + arg, { push: !w.push }));
    },
    reqack: function (arg) {
      var w = state.watchers.filter(function (x) { return x.id === +arg; })[0];
      withBusy(api("PATCH", "/api/watchers/" + arg, { requires_ack: !w.requires_ack }));
    },
    savespec: function (arg) {
      var box = $("spec-" + arg);
      withBusy(api("PATCH", "/api/watchers/" + arg, { ai_spec: box.value.trim() }), "spec saved");
    },
    del: function (arg) {
      var w = state.watchers.filter(function (x) { return x.id === +arg; })[0];
      if (!window.confirm("delete " + (w.name || w.target) + " and all its events?")) return;
      state.selected = null;
      withBusy(api("DELETE", "/api/watchers/" + arg), "deleted");
    }
  };

  document.addEventListener("click", function (ev) {
    var el = ev.target.closest("[data-act]");
    if (!el) return;
    var fn = ACTS[el.dataset.act];
    if (!fn) return;
    ev.preventDefault();
    fn(el.dataset.arg);
  });

  document.addEventListener("submit", function (ev) {
    if (ev.target.id !== "addform") return;
    ev.preventDefault();
    var payload = {
      kind: $("f-kind").value,
      target: $("f-target").value.trim(),
      name: $("f-name").value.trim(),
      ai_spec: $("f-spec").value.trim() || null,
      requires_ack: $("f-ack").checked,
      push: $("f-push").checked
    };
    var iv = parseInt($("f-interval").value, 10);
    if (iv) payload.reminder_interval = iv;
    if (!payload.target) { toast("target is required", true); return; }
    state.addOpen = false;
    withBusy(api("POST", "/api/watchers", payload), "watcher added");
  });

  Array.prototype.forEach.call(document.querySelectorAll(".wa-tab"), function (t) {
    t.addEventListener("click", function () { state.view = t.dataset.v; state.selected = null; render(); });
  });

  loadAll();
  setInterval(function () { if (document.visibilityState === "visible" && !state.busy) loadAll(); }, 60000);
})();
