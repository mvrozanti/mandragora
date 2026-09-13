(function () {
  var $ = function (id) { return document.getElementById(id); };
  var esc = function (v) {
    return String(v == null ? "" : v).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  };

  var state = {
    mode: "jump",
    home: "",
    zoxide: [],
    path: null,
    parent: null,
    entries: [],
    filter: "",
    active: 0,
    busy: false
  };

  var api = function (path, opts) {
    return fetch(path, Object.assign({ credentials: "same-origin", cache: "no-store" }, opts || {}))
      .then(function (r) {
        return r.json().then(function (body) {
          if (!r.ok || body.ok === false) throw new Error(body.error || body.msg || "request failed");
          return body;
        });
      });
  };

  var shortDir = function (p) {
    if (!p) return "";
    var parts = p.split("/").filter(Boolean);
    return parts.length ? parts[parts.length - 1] : "/";
  };

  var tilde = function (p) {
    if (state.home && p === state.home) return "~";
    if (state.home && p.indexOf(state.home + "/") === 0) return "~" + p.slice(state.home.length);
    return p;
  };

  var matchTerm = function (text, term) {
    var hay = term === term.toLowerCase() ? text.toLowerCase() : text;
    var pos = [];
    var at = 0;
    for (var i = 0; i < term.length; i++) {
      var found = hay.indexOf(term[i], at);
      if (found < 0) return null;
      pos.push(found);
      at = found + 1;
    }
    var back = pos[pos.length - 1];
    for (var j = term.length - 1; j >= 0; j--) {
      var tight = hay.lastIndexOf(term[j], back);
      pos[j] = tight;
      back = tight - 1;
    }
    return pos;
  };

  var fuzzy = function (text, query) {
    var terms = query.trim().split(/\s+/).filter(Boolean);
    if (!terms.length) return [];
    var hits = [];
    for (var i = 0; i < terms.length; i++) {
      var pos = matchTerm(text, terms[i]);
      if (!pos) return null;
      hits = hits.concat(pos);
    }
    return hits;
  };

  var mark = function (text, pos) {
    if (!pos || !pos.length) return esc(text);
    var on = {};
    pos.forEach(function (i) { on[i] = true; });
    var out = "";
    var open = false;
    for (var i = 0; i < text.length; i++) {
      if (on[i] && !open) { out += "<em>"; open = true; }
      else if (!on[i] && open) { out += "</em>"; open = false; }
      out += esc(text[i]);
    }
    return out + (open ? "</em>" : "");
  };

  var splitMark = function (label, pos) {
    var cut = label.lastIndexOf("/") + 1;
    var head = pos.filter(function (i) { return i < cut; });
    var tail = pos.filter(function (i) { return i >= cut; }).map(function (i) { return i - cut; });
    return '<span class="pre">' + mark(label.slice(0, cut), head) + "</span>" +
      '<span class="base">' + mark(label.slice(cut), tail) + "</span>";
  };

  var jumpRows = function () {
    var q = state.filter.trim();
    var out = [];
    state.zoxide.forEach(function (z) {
      var pos = q ? fuzzy(z.label, q) : [];
      if (pos === null) return;
      out.push({ kind: "zox", label: z.label, html: splitMark(z.label, pos), path: z.path, score: z.score });
    });
    return out;
  };

  var browseRows = function () {
    var q = state.filter.trim();
    var out = [];
    if (state.parent && !q) out.push({ kind: "up", label: "..", html: "..", path: state.parent });
    state.entries.forEach(function (e) {
      var pos = q ? fuzzy(e.name, q) : [];
      if (pos === null) return;
      out.push({
        kind: "dir",
        label: e.name,
        html: mark(e.name, pos),
        path: (state.path === "/" ? "" : state.path) + "/" + e.name
      });
    });
    return out;
  };

  var rows = function () { return state.mode === "jump" ? jumpRows() : browseRows(); };

  var activeRow = function () { return rows()[state.active] || null; };

  var subtitle = function (text) {
    var el = document.querySelector(".mv-topbar__count");
    if (el) el.textContent = text;
  };

  var modes = function () {
    return '<nav class="cw-modes" aria-label="picker mode">' +
      '<button data-mode="jump"' + (state.mode === "jump" ? ' class="is-on"' : "") + ">recent</button>" +
      '<button data-mode="browse"' + (state.mode === "browse" ? ' class="is-on"' : "") + ">browse</button>" +
      "</nav>";
  };

  var crumb = function () {
    var segs = (state.path || "").split("/").filter(Boolean);
    var html = '<button data-go="/">/</button>';
    var acc = "";
    segs.forEach(function (seg, i) {
      acc += "/" + seg;
      html += (i ? '<span class="sep">/</span>' : "") + '<button data-go="' + esc(acc) + '">' + esc(seg) + "</button>";
    });
    return '<nav class="cw-crumb" aria-label="path">' + html + "</nav>";
  };

  var launchLabel = function () {
    var row = state.mode === "jump" ? activeRow() : { path: state.path };
    var dir = row ? row.path : null;
    return '<button class="cw-launch" id="launch"' + (state.busy || !dir ? " disabled" : "") + ">" +
      "open a claude in <strong>" + esc(dir ? shortDir(dir) : "nothing") + "</strong>" +
      '<span class="kbd">' + (state.mode === "jump" ? "↵" : "ctrl + ↵") + "</span></button>";
  };

  var hints = function () {
    var items = state.mode === "jump"
      ? ["↑↓ move", "↵ open a claude here", "tab browse from here", state.zoxide.length + " known dirs"]
      : ["↑↓ move", "↵ enter directory", "tab open a claude there", "esc back to recent"];
    return '<div class="cw-hints">' + items.map(function (i) { return "<span>" + esc(i) + "</span>"; }).join("") + "</div>";
  };

  var render = function () {
    var placeholder = state.mode === "jump"
      ? "fuzzy-match your directories"
      : "filter, or browse with the crumb";
    subtitle(state.mode === "jump"
      ? "most-used directories, frecency ranked"
      : tilde(state.path || ""));

    $("view").innerHTML =
      (state.mode === "jump" ? modes() : modes() + crumb()) +
      launchLabel() +
      '<input class="cw-filter" id="filter" placeholder="' + esc(placeholder) + '" ' +
      'autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false" ' +
      'aria-label="fuzzy filter directories" value="' + esc(state.filter) + '">' +
      '<div class="cw-list" id="list"></div>' + hints();

    renderList();
    var f = $("filter");
    f.addEventListener("input", onFilter);
    f.addEventListener("keydown", onKeys);
    $("launch").addEventListener("click", function () {
      var row = state.mode === "jump" ? activeRow() : { path: state.path };
      if (row) launch(row.path);
    });
    document.querySelectorAll(".cw-modes button").forEach(function (b) {
      b.addEventListener("click", function () {
        if (b.dataset.mode === "jump") toJump();
        else toBrowse((state.mode === "jump" && activeRow() ? activeRow().path : state.path) || null);
      });
    });
    document.querySelectorAll(".cw-crumb button").forEach(function (b) {
      b.addEventListener("click", function () { go(b.dataset.go); });
    });
    if (!("ontouchstart" in window)) f.focus();
  };

  var renderList = function () {
    var list = rows();
    if (state.active >= list.length) state.active = Math.max(0, list.length - 1);
    $("list").innerHTML = list.length
      ? list.map(function (r, i) {
          var ico = r.kind === "up" ? "↑" : r.kind === "zox" ? "z" : "▸";
          var tail = r.kind === "zox" ? r.score.toFixed(1) : r.kind === "dir" ? "→" : "";
          return '<button class="cw-row ' + r.kind + (i === state.active ? " is-active" : "") +
            '" data-idx="' + i + '"><span class="ico">' + ico + "</span>" +
            '<span class="name">' + r.html + "</span>" +
            '<span class="tail">' + tail + "</span></button>";
        }).join("")
      : '<p class="mv-empty">' + (state.filter.trim() ? "no match" : "nothing here") + "</p>";
    $("list").querySelectorAll(".cw-row").forEach(function (b) {
      b.addEventListener("click", function () {
        state.active = +b.dataset.idx;
        choose(list[state.active]);
      });
    });
  };

  var choose = function (row) {
    if (!row) return;
    if (state.mode === "jump") launch(row.path);
    else go(row.path);
  };

  var alternate = function (row) {
    if (!row) return;
    if (state.mode === "jump") toBrowse(row.path);
    else launch(row.path);
  };

  var go = function (path) {
    state.filter = "";
    state.active = 0;
    load(path);
  };

  var toJump = function () {
    state.mode = "jump";
    state.filter = "";
    state.active = 0;
    render();
    loadZoxide();
  };

  var toBrowse = function (path) {
    state.mode = "browse";
    go(path);
  };

  var refreshLaunch = function () {
    if (state.mode !== "jump") return;
    var l = $("launch");
    var row = activeRow();
    l.disabled = state.busy || !row;
    l.innerHTML = "open a claude in <strong>" + esc(row ? shortDir(row.path) : "nothing") +
      '</strong><span class="kbd">↵</span>';
  };

  var syncActive = function () {
    renderList();
    refreshLaunch();
  };

  var onFilter = function (ev) {
    state.filter = ev.target.value;
    state.active = 0;
    syncActive();
  };

  var onKeys = function (ev) {
    var list = rows();
    if (ev.key === "ArrowDown") { state.active = Math.min(state.active + 1, list.length - 1); syncActive(); ev.preventDefault(); }
    else if (ev.key === "ArrowUp") { state.active = Math.max(state.active - 1, 0); syncActive(); ev.preventDefault(); }
    else if (ev.key === "Tab") { ev.preventDefault(); alternate(list[state.active]); }
    else if (ev.key === "Escape") {
      if (state.filter) { state.filter = ""; ev.target.value = ""; state.active = 0; syncActive(); }
      else if (state.mode === "browse") toJump();
    }
    else if (ev.key === "Enter") {
      ev.preventDefault();
      if (ev.ctrlKey || ev.metaKey) launch(state.mode === "jump" ? (list[state.active] || {}).path : state.path);
      else choose(list[state.active]);
    }
  };

  var status = function (glyph, cls, head, dir, extra) {
    $("view").innerHTML = '<div class="cw-status">' +
      '<div class="cw-status__mark ' + cls + '">' + glyph + "</div>" +
      '<div class="cw-status__head">' + esc(head) + "</div>" +
      (dir ? '<div class="cw-status__dir">' + esc(dir) + "</div>" : "") + (extra || "") + "</div>";
  };

  var launch = function (dir) {
    if (state.busy || !dir) return;
    state.busy = true;
    status("○", "pending", "starting a claude", tilde(dir));
    api("/api/launch", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ dir: dir })
    })
      .then(function (j) {
        status("✓", "", "claude is running", j.dir,
          '<p class="cw-status__hint">' + esc(j.msg || "") + " — attach from your tmux client</p>" +
          '<button class="cw-btn cw-again">open another</button>');
      })
      .catch(function (err) {
        status("!", "bad", "could not start it", tilde(dir),
          '<p class="cw-status__err">' + esc(err.message) + "</p>" +
          '<button class="cw-btn cw-again">try again</button>');
      })
      .then(function () {
        state.busy = false;
        var again = document.querySelector(".cw-again");
        if (again) again.addEventListener("click", toJump);
      });
  };

  var load = function (path) {
    var url = "/api/list" + (path ? "?path=" + encodeURIComponent(path) : "");
    return api(url)
      .then(function (j) {
        state.mode = "browse";
        state.path = j.path;
        state.parent = j.parent;
        state.entries = j.entries || [];
        render();
      })
      .catch(function (err) {
        status("!", "bad", "could not read that directory", path,
          '<p class="cw-status__err">' + esc(err.message) + "</p>");
      });
  };

  var loadZoxide = function () {
    return api("/api/zoxide")
      .then(function (j) {
        state.home = j.home || "";
        state.zoxide = (j.entries || []).map(function (e) {
          return { path: e.path, score: e.score, label: tilde(e.path) };
        });
        if (state.mode === "jump") render();
      })
      .catch(function () { state.zoxide = []; });
  };

  document.addEventListener("keydown", function (ev) {
    if ((ev.ctrlKey || ev.metaKey) && ev.key === "Enter" && !state.busy && document.activeElement !== $("filter")) {
      ev.preventDefault();
      launch(state.mode === "jump" ? (activeRow() || {}).path : state.path);
    }
  });

  loadZoxide().then(function () {
    if (!state.zoxide.length) toBrowse(null);
  });
})();
