(function () {
  var $ = function (id) { return document.getElementById(id); };
  var esc = function (v) {
    return String(v == null ? "" : v).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  };

  var state = {
    filter: "all",
    open: null,
    watchers: [],
    kinds: {},
    health: null,
    triggers: {},
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
  var until = function (iso) {
    var mins = (Date.parse(iso) - Date.now()) / 60000;
    if (!isFinite(mins) || mins <= 0) return "shortly";
    if (mins < 60) return "in " + Math.round(mins) + "m";
    return "in " + Math.round(mins / 60) + "h";
  };

  var backingOff = function (w) {
    return w.retry_after && Date.parse(w.retry_after) > Date.now();
  };

  var chips = function (w) {
    var out = [];
    if (w.last_error) out.push('<span class="mv-pill is-down">failing</span>');
    if (backingOff(w)) out.push('<span class="mv-pill is-warn">retrying ' + until(w.retry_after) + "</span>");
    if (!w.enabled) out.push('<span class="mv-pill">paused</span>');
    if (w.push) out.push('<span class="mv-pill">notifies</span>');
    if (w.requires_ack) out.push('<span class="mv-pill is-warn">nags hourly</span>');
    if (!w.ai_spec) out.push('<span class="mv-pill">everything passes</span>');
    if (w.spec_lint && w.spec_lint.decidable === false) {
      var why = (w.spec_lint.problems || []).join(" · ") || "open the watcher for detail";
      out.push('<span class="mv-pill is-warn" title="' + esc(why) + '">spec unanswerable</span>');
    }
    return out.join("");
  };

  var stateDot = function (w) {
    if (w.last_error) return "is-down";
    if (w.state === "triggered") return "is-ok";
    if (w.state === "done") return "is-unknown";
    return "is-warn";
  };
  var stateWord = function (w) {
    if (w.state === "triggered") return w.open_trigger_count + " to review";
    if (w.state === "done") return "done";
    return "waiting";
  };

  var FILTERS = [
    { id: "waiting", label: "waiting" },
    { id: "triggered", label: "triggered" },
    { id: "done", label: "done" },
    { id: "all", label: "all" }
  ];
  var matching = function () {
    return state.watchers.filter(function (w) {
      return state.filter === "all" || w.state === state.filter;
    });
  };

  var renderAlerts = function () {
    var out = [];
    var h = state.health;
    if (h) {
      Object.keys(h.tasks || {}).forEach(function (name) {
        if (h.tasks[name] !== "alive") out.push('<div class="wa-alert is-down"><b>' + name + " is not running</b> — nothing will fire until it is back</div>");
      });
      if (!h.telegram_enabled) out.push('<div class="wa-alert"><b>telegram is not configured</b> — nothing can notify you</div>');
    }
    var broken = state.watchers.filter(function (w) { return w.last_error; });
    if (broken.length) {
      out.push('<div class="wa-alert"><b>' + broken.length + " watch" + (broken.length > 1 ? "es are" : " is") +
        " failing</b> — " + esc(broken.map(function (w) { return w.name || w.target; }).slice(0, 3).join(", ")) +
        (broken.length > 3 ? " and " + (broken.length - 3) + " more" : "") + "</div>");
    }
    $("alerts").innerHTML = out.join("");
  };

  var renderFilters = function () {
    $("filters").innerHTML = FILTERS.map(function (f) {
      var n = f.id === "all" ? state.watchers.length
        : state.watchers.filter(function (w) { return w.state === f.id; }).length;
      return '<button class="wa-filter" role="tab" data-act="filter" data-arg="' + f.id +
        '" aria-selected="' + (state.filter === f.id) + '">' + f.label + '<span class="n">' + n + "</span></button>";
    }).join("");
  };

  var triggerHTML = function (t) {
    return '<div class="wa-trig' + (t.acked_at ? " is-accepted" : "") + '">' +
      '<a class="wa-trig__title" href="' + esc(t.link || "#") + '" target="_blank" rel="noopener">' + esc(t.title) + "</a>" +
      '<div class="wa-trig__meta"><span>' + ago(t.received_at) + "</span>" +
      (t.acked_at ? "<span>accepted</span>" : "") + "</div>" +
      (t.ai_reason ? '<div class="wa-trig__reason">' + esc(t.ai_reason) + "</div>" : "") +
      (t.acked_at ? "" : '<div class="wa-acts"><button class="wa-btn primary" data-act="accept" data-arg="' +
        t.id + '">accept as a real trigger</button></div>') + "</div>";
  };

  var panelHTML = function (w) {
    var kind = state.kinds[w.kind] || {};
    var lint = w.spec_lint || {};
    var loaded = state.triggers[w.id];
    var trig = !w.trigger_count
      ? '<p class="mv-empty" style="padding:var(--mv-space-4) 0">nothing has fired yet</p>'
      : loaded
        ? loaded.map(triggerHTML).join("")
        : '<p class="mv-empty" style="padding:var(--mv-space-4) 0">loading</p>';

    var lintBlock = "";
    if (w.ai_spec && lint.decidable === false) {
      lintBlock = '<div class="wa-lint"><p class="wa-lint__head">this question cannot be answered from what the source gives us</p>' +
        ((lint.problems || []).length ? '<ul class="wa-lint__probs">' +
          lint.problems.map(function (x) { return "<li>" + esc(x) + "</li>"; }).join("") + "</ul>" : "") +
        (lint.suggestion ? '<p class="wa-panel__label">an answerable rewrite</p><p class="wa-lint__sugg">' +
          esc(lint.suggestion) + "</p>" +
          '<div class="wa-acts"><button class="wa-btn primary" data-act="uselint" data-arg="' + w.id +
          '">use this rewrite</button></div>' : "") + "</div>";
    } else if (w.ai_spec && lint.decidable) {
      lintBlock = '<p class="wa-lint__ok">this question is answerable from what the source gives us</p>';
    }

    return '<div class="wa-panel">' +
      (w.last_error ? '<p class="wa-err">' + esc(w.last_error) +
        (backingOff(w) ? " · backing off, retrying " + until(w.retry_after) : "") + "</p>" : "") +
      '<div><p class="wa-panel__label">what fired it</p>' + trig + "</div>" +
      (kind.emits ? '<p class="wa-emits"><b>this source gives us</b> ' + esc(kind.emits) + "</p>" : "") +
      lintBlock +
      '<div class="wa-field"><label for="must-' + w.id + '">must mention</label>' +
      '<input class="wa-input" id="must-' + w.id + '" value="' + esc(w.must_mention || "") +
      '" placeholder="e.g. electrum — a trigger is refused unless the text names this">' +
      '<p class="wa-emits">Checked literally against the title, summary and fetched article. ' +
      'This is what stops the judge asserting a subject the source never named.</p></div>' +
      '<div class="wa-field"><label for="spec-' + w.id + '">what counts as a trigger</label>' +
      '<textarea class="wa-area" id="spec-' + w.id + '" placeholder="leave blank and everything this source emits counts">' +
      esc(w.ai_spec || "") + "</textarea></div>" +
      '<div class="wa-acts">' +
      '<button class="wa-btn primary" data-act="savespec" data-arg="' + w.id + '">save</button>' +
      (w.ai_spec ? '<button class="wa-btn" data-act="relint" data-arg="' + w.id + '">re-check</button>' : "") +
      '<button class="wa-btn" data-act="poll" data-arg="' + w.id + '">check now</button>' +
      '<button class="wa-btn" data-act="toggle" data-arg="' + w.id + '">' + (w.enabled ? "pause" : "resume") + "</button>" +
      '<button class="wa-btn" data-act="push" data-arg="' + w.id + '">' + (w.push ? "stop notifying" : "notify me") + "</button>" +
      '<button class="wa-btn" data-act="reqack" data-arg="' + w.id + '">' +
      (w.requires_ack ? "stop nagging" : "nag hourly until accepted") + "</button>" +
      (w.open_trigger_count ? '<button class="wa-btn" data-act="acceptall" data-arg="' + w.id +
        '">accept all ' + w.open_trigger_count + "</button>" : "") +
      '<button class="wa-btn danger" data-act="del" data-arg="' + w.id + '">delete</button>' +
      "</div></div>";
  };

  var renderGrid = function () {
    var rows = matching();
    if (!rows.length) { $("grid").innerHTML = '<p class="mv-empty">nothing ' + state.filter + "</p>"; return; }
    $("grid").innerHTML = rows.map(function (w) {
      var open = state.open === w.id;
      return '<article class="wa-tile' + (open ? " is-open" : "") + '">' +
        '<div class="wa-tile__head" role="button" tabindex="0" data-act="open" data-arg="' + w.id +
        '" aria-expanded="' + open + '">' +
        '<span class="mv-dot wa-tile__dot ' + stateDot(w) + '"></span>' +
        '<span><span class="wa-tile__name">' + esc(w.name || w.target) + "</span>" +
        '<span class="wa-tile__src">' + esc(w.kind) + " · " + esc(w.target) + "</span>" +
        '<span class="wa-tile__chips">' + chips(w) + "</span></span>" +
        '<span class="wa-tile__state ' + w.state + '">' + stateWord(w) + "</span>" +
        "</div>" + (open ? panelHTML(w) : "") + "</article>";
    }).join("");
  };

  var renderAdd = function () {
    if (!state.addOpen) {
      $("add").innerHTML = '<div class="wa-acts" style="margin-bottom:var(--mv-space-3)">' +
        '<button class="wa-btn primary" data-act="openadd">add a watch</button></div>';
      return;
    }
    var opts = Object.keys(state.kinds).map(function (k) {
      return '<option value="' + k + '">' + esc(state.kinds[k].label) + "</option>";
    }).join("");
    $("add").innerHTML = '<form class="wa-form" id="addform">' +
      '<div class="wa-field"><label for="f-kind">source</label><select class="wa-select" id="f-kind">' + opts + "</select></div>" +
      '<div class="wa-field"><label for="f-target">target</label><input class="wa-input" id="f-target" placeholder="owner/repo, @handle, search terms…"></div>' +
      '<div class="wa-field wide"><label for="f-name">what are you waiting for</label><input class="wa-input" id="f-name" placeholder="e.g. severance s3 gets a date"></div>' +
      '<div class="wa-field wide"><label for="f-must">must mention</label>' +
      '<input class="wa-input" id="f-must" placeholder="a literal the text must contain — blank to skip"></div>' +
      '<div class="wa-field wide"><label for="f-spec">what counts as a trigger</label>' +
      '<textarea class="wa-area" id="f-spec" placeholder="leave blank and everything this source emits counts"></textarea></div>' +
      '<div class="wa-checks wide"><label><input type="checkbox" id="f-push" checked> notify me on telegram when it fires</label>' +
      '<label><input type="checkbox" id="f-ack"> keep nagging hourly until I accept it <span class="wa-hint">— urgent security only</span></label></div>' +
      '<div class="wa-acts wide"><button class="wa-btn primary" type="submit">add</button>' +
      '<button class="wa-btn" type="button" data-act="canceladd">cancel</button></div></form>';
  };

  var render = function () {
    renderAlerts();
    renderFilters();
    renderAdd();
    renderGrid();
    $("count").textContent = state.watchers.length + " watches";
  };

  var loadTriggers = function (wid) {
    return api("GET", "/api/watchers/" + wid + "/triggers?limit=50").then(function (rows) {
      state.triggers[wid] = rows;
      render();
    }).catch(function () {});
  };

  var loadAll = function () {
    return Promise.all([
      api("GET", "/api/watchers"),
      api("GET", "/api/kinds"),
      api("GET", "/healthz").catch(function () { return null; })
    ]).then(function (res) {
      state.watchers = res[0];
      state.kinds = res[1];
      state.health = res[2];
      render();
      if (state.open != null) loadTriggers(state.open);
    }).catch(function (err) {
      toast("could not load: " + err.message, true);
    });
  };

  var withBusy = function (promise, okMsg) {
    if (state.busy) return;
    state.busy = true;
    return promise
      .then(function () { if (okMsg) toast(okMsg); state.triggers = {}; return loadAll(); })
      .catch(function (err) { toast(err.message || "failed", true); })
      .then(function () { state.busy = false; });
  };

  var find = function (id) {
    return state.watchers.filter(function (x) { return x.id === +id; })[0];
  };

  var ACTS = {
    filter: function (arg) { state.filter = arg; render(); },
    open: function (arg) {
      state.open = state.open === +arg ? null : +arg;
      render();
      if (state.open != null && !state.triggers[state.open]) loadTriggers(state.open);
    },
    openadd: function () { state.addOpen = true; render(); },
    canceladd: function () { state.addOpen = false; render(); },
    accept: function (arg) { withBusy(api("POST", "/api/events/" + arg + "/ack"), "accepted"); },
    acceptall: function (arg) { withBusy(api("POST", "/api/watchers/" + arg + "/ack-all"), "all accepted"); },
    poll: function (arg) { withBusy(api("POST", "/api/watchers/" + arg + "/poll"), "checked"); },
    relint: function (arg) { withBusy(api("POST", "/api/watchers/" + arg + "/lint"), "re-checked"); },
    toggle: function (arg) { withBusy(api("POST", "/api/watchers/" + arg + "/toggle")); },
    push: function (arg) { withBusy(api("PATCH", "/api/watchers/" + arg, { push: !find(arg).push })); },
    reqack: function (arg) {
      var w = find(arg);
      withBusy(api("PATCH", "/api/watchers/" + arg, {
        requires_ack: !w.requires_ack,
        reminder_interval: 3600
      }));
    },
    uselint: function (arg) {
      var w = find(arg);
      var box = $("spec-" + arg);
      if (box && w && w.spec_lint && w.spec_lint.suggestion) {
        box.value = w.spec_lint.suggestion;
        box.focus();
        toast("rewrite loaded — read it, then save");
      }
    },
    savespec: function (arg) {
      withBusy(api("PATCH", "/api/watchers/" + arg, {
        ai_spec: $("spec-" + arg).value.trim(),
        must_mention: $("must-" + arg).value.trim()
      }), "saved");
    },
    del: function (arg) {
      var w = find(arg);
      if (!window.confirm("delete " + (w.name || w.target) + " and everything it caught?")) return;
      state.open = null;
      withBusy(api("DELETE", "/api/watchers/" + arg), "deleted");
    }
  };

  var fire = function (el) {
    var fn = ACTS[el.dataset.act];
    if (fn) fn(el.dataset.arg);
  };

  document.addEventListener("click", function (ev) {
    var el = ev.target.closest("[data-act]");
    if (!el) return;
    if (ev.target.closest("a")) return;
    var sel = window.getSelection();
    if (el.dataset.act === "open" && sel && !sel.isCollapsed) return;
    ev.preventDefault();
    fire(el);
  });

  document.addEventListener("keydown", function (ev) {
    if (ev.key !== "Enter" && ev.key !== " ") return;
    var el = ev.target.closest('[role="button"][data-act]');
    if (!el) return;
    ev.preventDefault();
    fire(el);
  });

  document.addEventListener("submit", function (ev) {
    if (ev.target.id !== "addform") return;
    ev.preventDefault();
    var payload = {
      kind: $("f-kind").value,
      target: $("f-target").value.trim(),
      name: $("f-name").value.trim(),
      ai_spec: $("f-spec").value.trim() || null,
      must_mention: $("f-must").value.trim() || null,
      requires_ack: $("f-ack").checked,
      push: $("f-push").checked
    };
    if (payload.requires_ack) payload.reminder_interval = 3600;
    if (!payload.target) { toast("target is required", true); return; }
    state.addOpen = false;
    withBusy(api("POST", "/api/watchers", payload), "added");
  });

  loadAll();
  setInterval(function () {
    if (document.visibilityState === "visible" && !state.busy) loadAll();
  }, 60000);
})();
