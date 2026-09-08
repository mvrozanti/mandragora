(function () {
  var $ = function (id) { return document.getElementById(id); };
  var esc = function (v) {
    return String(v == null ? "" : v).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  };

  var state = { path: null, parent: null, entries: [], zoxide: [], filter: "", active: 0, busy: false };

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

  var rows = function () {
    var out = [];
    var q = state.filter.trim().toLowerCase();
    if (state.parent && !q) out.push({ kind: "up", label: "..", path: state.parent });
    state.zoxide.forEach(function (z) {
      out.push({ kind: "zox", label: z.path, path: z.path, score: z.score });
    });
    state.entries.forEach(function (e) {
      if (q && e.name.toLowerCase().indexOf(q) < 0) return;
      out.push({ kind: "dir", label: e.name, path: (state.path === "/" ? "" : state.path) + "/" + e.name });
    });
    return out;
  };

  var renderBrowser = function () {
    var segs = (state.path || "").split("/").filter(Boolean);
    var crumb = '<button data-go="/">/</button>';
    var acc = "";
    segs.forEach(function (seg, i) {
      acc += "/" + seg;
      crumb += (i ? '<span class="sep">/</span>' : "") + '<button data-go="' + esc(acc) + '">' + esc(seg) + "</button>";
    });

    $("view").innerHTML =
      '<nav class="cw-crumb" aria-label="path">' + crumb + "</nav>" +
      '<button class="cw-launch" id="launch"' + (state.busy ? " disabled" : "") + '>' +
      "open a claude in <strong>" + esc(shortDir(state.path)) + "</strong>" +
      '<span class="kbd">ctrl + ↵</span></button>' +
      '<input class="cw-filter" id="filter" placeholder="filter, or type to jump anywhere" ' +
      'autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false" ' +
      'aria-label="filter directories or fuzzy-jump" value="' + esc(state.filter) + '">' +
      '<div class="cw-list" id="list"></div>' +
      '<div class="cw-hints"><span>↑↓ move</span><span>↵ enter directory</span><span>ctrl+↵ open here</span></div>';

    renderList();
    var f = $("filter");
    f.addEventListener("input", onFilter);
    f.addEventListener("keydown", onKeys);
    $("launch").addEventListener("click", launch);
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
            '<span class="name">' + esc(r.label) + "</span>" +
            '<span class="tail">' + tail + "</span></button>";
        }).join("")
      : '<p class="mv-empty">nothing here</p>';
    $("list").querySelectorAll(".cw-row").forEach(function (b) {
      b.addEventListener("click", function () { choose(list[+b.dataset.idx]); });
    });
  };

  var choose = function (row) {
    if (!row) return;
    go(row.path);
  };

  var go = function (path) {
    state.filter = "";
    state.zoxide = [];
    state.active = 0;
    load(path);
  };

  var zoxTimer = null;
  var onFilter = function (ev) {
    state.filter = ev.target.value;
    state.active = 0;
    renderList();
    clearTimeout(zoxTimer);
    var q = state.filter.trim();
    if (!q) { state.zoxide = []; renderList(); return; }
    zoxTimer = setTimeout(function () {
      api("/api/zoxide?q=" + encodeURIComponent(q))
        .then(function (j) { state.zoxide = j.entries || []; renderList(); })
        .catch(function () {});
    }, 180);
  };

  var onKeys = function (ev) {
    var list = rows();
    if (ev.key === "ArrowDown") { state.active = Math.min(state.active + 1, list.length - 1); renderList(); ev.preventDefault(); }
    else if (ev.key === "ArrowUp") { state.active = Math.max(state.active - 1, 0); renderList(); ev.preventDefault(); }
    else if (ev.key === "Escape") { state.filter = ""; state.zoxide = []; ev.target.value = ""; renderList(); }
    else if (ev.key === "Enter") {
      ev.preventDefault();
      if (ev.ctrlKey || ev.metaKey) launch();
      else choose(list[state.active]);
    }
  };

  var status = function (mark, cls, head, dir, extra) {
    $("view").innerHTML = '<div class="cw-status">' +
      '<div class="cw-status__mark ' + cls + '">' + mark + "</div>" +
      '<div class="cw-status__head">' + esc(head) + "</div>" +
      (dir ? '<div class="cw-status__dir">' + esc(dir) + "</div>" : "") + (extra || "") + "</div>";
  };

  var launch = function () {
    if (state.busy) return;
    state.busy = true;
    var dir = state.path;
    status("○", "pending", "starting a claude", dir);
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
        status("!", "bad", "could not start it", dir,
          '<p class="cw-status__err">' + esc(err.message) + "</p>" +
          '<button class="cw-btn cw-again">try again</button>');
      })
      .then(function () {
        state.busy = false;
        var again = document.querySelector(".cw-again");
        if (again) again.addEventListener("click", function () { load(dir); });
      });
  };

  var load = function (path) {
    var url = "/api/list" + (path ? "?path=" + encodeURIComponent(path) : "");
    return api(url)
      .then(function (j) {
        state.path = j.path;
        state.parent = j.parent;
        state.entries = j.entries || [];
        renderBrowser();
      })
      .catch(function (err) {
        status("!", "bad", "could not read that directory", path,
          '<p class="cw-status__err">' + esc(err.message) + "</p>");
      });
  };

  document.addEventListener("keydown", function (ev) {
    if ((ev.ctrlKey || ev.metaKey) && ev.key === "Enter" && state.path && !state.busy) {
      ev.preventDefault();
      launch();
    }
  });

  load(null);
})();
