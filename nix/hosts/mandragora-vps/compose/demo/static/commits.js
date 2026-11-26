(() => {
  "use strict";

  const API = "/api/gource/stats";
  const DAY_NAMES = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
  const MONTH_NAMES = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];

  const el = (id) => document.getElementById(id);
  const fmt = new Intl.NumberFormat("en-US");

  function num(n) {
    return fmt.format(n || 0);
  }

  function levelFor(n) {
    if (n <= 0) return 0;
    if (n <= 2) return 1;
    if (n <= 6) return 2;
    if (n <= 12) return 3;
    return 4;
  }

  function isoWeekday(iso) {
    const [y, m, d] = iso.split("-").map(Number);
    return (new Date(Date.UTC(y, m - 1, d)).getUTCDay() + 6) % 7;
  }

  function addDays(iso, n) {
    const [y, m, d] = iso.split("-").map(Number);
    const t = new Date(Date.UTC(y, m - 1, d + n));
    return t.toISOString().slice(0, 10);
  }

  function weekStart(iso) {
    return addDays(iso, -isoWeekday(iso));
  }

  function renderHero(s) {
    const authorEmails = new Set(s.authors.map((a) => a.email));
    const tiles = [
      { k: "commits", v: num(s.commits), sub: s.days_active + " active days" },
      { k: "authors", v: String(authorEmails.size), sub: "by email" },
      { k: "insertions", v: num(s.insertions), sub: "lines added", tone: "ins" },
      { k: "deletions", v: num(s.deletions), sub: "lines removed", tone: "del" },
      { k: "files", v: num(s.files), sub: "paths touched" },
      { k: "span", v: s.first ? s.first.slice(0, 4) + "–" + s.last.slice(0, 4) : "—", sub: "first to last" },
    ];
    el("hero").replaceChildren(...tiles.map((t) => {
      const d = document.createElement("div");
      d.className = "stats-tile" + (t.tone ? " is-" + t.tone : "");
      d.innerHTML =
        '<span class="stats-tile__v">' + t.v + '</span>' +
        '<span class="stats-tile__k mv-label">' + t.k + '</span>' +
        '<span class="stats-tile__sub">' + t.sub + "</span>";
      return d;
    }));
  }

  function renderHeatmap(s) {
    const counts = new Map(Object.entries(s.daily).map(([d, v]) => [d, v.c]));
    const dates = Object.keys(s.daily).sort();
    if (!dates.length) return;
    const wrap = el("heatmap");
    wrap.replaceChildren();

    const firstYear = Number(dates[0].slice(0, 4));
    const lastYear = Number(dates[dates.length - 1].slice(0, 4));

    for (let y = firstYear; y <= lastYear; y++) {
      const jan1 = y + "-01-01";
      const start = weekStart(jan1);
      const block = document.createElement("div");
      block.className = "heatmap__year";
      const label = document.createElement("span");
      label.className = "heatmap__year-label mv-mono";
      label.textContent = String(y);
      const grid = document.createElement("div");
      grid.className = "heatmap__grid";

      let cursor = start;
      while (cursor < jan1) {
        const cell = document.createElement("span");
        cell.className = "heatmap__cell";
        cell.dataset.level = "0";
        grid.append(cell);
        cursor = addDays(cursor, 1);
      }
      const dec31 = y + "-12-31";
      while (cursor <= dec31) {
        const c = counts.get(cursor) || 0;
        const cell = document.createElement("span");
        cell.className = "heatmap__cell";
        cell.dataset.level = String(levelFor(c));
        const d = new Date(cursor + "T00:00:00Z");
        cell.title = d.toLocaleDateString("en-US", { weekday: "short", year: "numeric", month: "short", day: "numeric" }) + " — " + c + " commit" + (c === 1 ? "" : "s");
        grid.append(cell);
        cursor = addDays(cursor, 1);
      }

      block.append(label, grid);
      wrap.append(block);
    }
  }

  function renderPunch(s) {
    const rows = s.punch;
    let max = 0;
    let busyDay = 0;
    let busyHour = 0;
    rows.forEach((r, wd) => r.forEach((v, hr) => {
      if (v > max) { max = v; busyDay = wd; busyHour = hr; }
    }));

    const wrap = el("punch");
    wrap.replaceChildren();

    const corner = document.createElement("span");
    corner.className = "punch__label";
    wrap.append(corner);
    for (let h = 0; h < 24; h++) {
      const l = document.createElement("span");
      l.className = "punch__label punch__label--hour";
      l.textContent = h % 3 === 0 ? String(h).padStart(2, "0") : "";
      wrap.append(l);
    }
    rows.forEach((r, wd) => {
      const l = document.createElement("span");
      l.className = "punch__label punch__label--day";
      l.textContent = DAY_NAMES[wd];
      wrap.append(l);
      r.forEach((v, hr) => {
        const c = document.createElement("span");
        c.className = "punch__cell";
        c.dataset.level = String(levelFor(v));
        c.title = DAY_NAMES[wd] + " " + String(hr).padStart(2, "0") + ":00 — " + v + " commits";
        wrap.append(c);
      });
    });

    el("punch-busy").textContent = "busiest " + DAY_NAMES[busyDay] + " " + String(busyHour).padStart(2, "0") + ":00";
  }

  function renderAuthors(s) {
    const max = Math.max(1, ...s.authors.map((a) => a.commits));
    el("authors-sub").textContent = s.authors.length + " by email";
    el("authors").replaceChildren(...s.authors.map((a) => {
      const row = document.createElement("div");
      row.className = "author";
      const head = document.createElement("div");
      head.className = "author__head";
      const name = document.createElement("span");
      name.className = "author__name";
      name.textContent = a.name;
      const email = document.createElement("span");
      email.className = "author__email mv-mono";
      email.textContent = a.email;
      const count = document.createElement("span");
      count.className = "author__count mv-mono";
      count.textContent = num(a.commits);
      head.append(name, email, count);
      const bar = document.createElement("div");
      bar.className = "author__bar";
      const fill = document.createElement("span");
      fill.className = "author__fill";
      fill.style.width = (100 * a.commits / max).toFixed(1) + "%";
      bar.append(fill);
      const meta = document.createElement("div");
      meta.className = "author__meta mv-mono";
      meta.innerHTML =
        '<span class="is-ins">+' + num(a.insertions) + "</span>" +
        '<span class="is-del">−' + num(a.deletions) + "</span>" +
        '<span class="author__range">' + a.first.slice(0, 4) + "–" + a.last.slice(0, 4) + "</span>";
      row.append(head, bar, meta);
      return row;
    }));
  }

  function renderActivity(s) {
    const wrap = el("activity");
    wrap.replaceChildren();
    const data = s.monthly;
    if (!data.length) return;
    const max = Math.max(1, ...data.map((d) => d.c));
    data.forEach((d) => {
      const col = document.createElement("div");
      col.className = "activity__col";
      const bar = document.createElement("span");
      bar.className = "activity__bar";
      bar.style.height = (100 * d.c / max).toFixed(1) + "%";
      bar.title = d.m + " — " + d.c + " commits";
      col.append(bar);
      const [y, m] = d.m.split("-");
      const isJan = m === "01";
      const label = document.createElement("span");
      label.className = "activity__label mv-mono";
      label.textContent = isJan ? y : (parseInt(m, 10) % 3 === 0 ? MONTH_NAMES[parseInt(m, 10) - 1] : "");
      col.append(label);
      wrap.append(col);
    });
  }

  function renderFiles(s) {
    el("files-sub").textContent = "top " + s.files.length + " by change count";
    const max = Math.max(1, ...s.files.map((f) => f.changes));
    el("files").replaceChildren(...s.files.map((f) => {
      const row = document.createElement("div");
      row.className = "file";
      const path = document.createElement("span");
      path.className = "file__path mv-mono";
      path.textContent = f.path;
      path.title = f.path;
      const bar = document.createElement("div");
      bar.className = "file__bar";
      const fill = document.createElement("span");
      fill.className = "file__fill";
      fill.style.width = (100 * f.changes / max).toFixed(1) + "%";
      bar.append(fill);
      const n = document.createElement("span");
      n.className = "file__n mv-mono";
      n.textContent = num(f.changes);
      row.append(path, bar, n);
      return row;
    }));
  }

  async function load() {
    try {
      const r = await fetch(API, { cache: "no-store" });
      if (!r.ok) throw new Error("HTTP " + r.status);
      const s = await r.json();
      renderHero(s);
      renderHeatmap(s);
      renderPunch(s);
      renderAuthors(s);
      renderActivity(s);
      renderFiles(s);
    } catch (e) {
      el("hero").textContent = "could not load commit stats: " + e.message;
    }
  }

  load();
})();
