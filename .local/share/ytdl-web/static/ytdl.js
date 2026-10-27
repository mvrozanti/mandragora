(function () {
  "use strict";

  const $ = (id) => document.getElementById(id);
  const $form = $("grab");
  const $url = $("url");
  const $paste = $("paste");
  const $go = $("go");
  const $hint = $("hint");
  const $device = $("device");
  const $modes = [...document.querySelectorAll("[data-mode]")];
  const $count = $("count");
  const $active = $("active");
  const $activeList = $("active-list");
  const $activeCount = $("active-count");
  const $history = $("history");
  const $historyCount = $("history-count");
  const $dock = $("dock");
  const $dockTitle = $("dock-title");
  const $dockSub = $("dock-sub");
  const $dockAudio = $("dock-audio");
  const $dockVideo = $("dock-video");
  const $dockToggle = $("dock-toggle");
  const $dockMore = $("dock-more");
  const $dockBody = $("dock-body");
  const $dockTime = $("dock-time");

  const PREFS = "ytdl-web:prefs";
  const ACTIVE = new Set(["queued", "running", "tagging"]);
  const TONE = { done: "is-ok", failed: "is-down", queued: "is-warn", running: "is-warn", tagging: "is-warn" };
  const STAGE = { downloading: "get", converting: "mp3", merging: "mux", moving: "move" };
  const HINTS = {
    "audio:desk": "mp3 → ~/Music on the desktop, tagged with title and artist",
    "video:desk": "mp4 (h264 + aac) → ~/Videos on the desktop",
    "audio:here": "mp3 → plays here and keeps going with the screen locked · nothing kept on the desktop · gone after 24 h",
    "video:here": "mp4 → plays here · nothing kept on the desktop · gone after 24 h · to listen with the screen locked, pick audio",
  };

  const opts = { mode: "audio", toClient: false };
  let jobsById = new Map();
  let playing = null;
  let expanded = false;
  let timer = null;
  let hintTimer = null;
  const activeNodes = new Map();
  const rows = new Map();
  const openRows = new Set();

  try {
    const saved = JSON.parse(localStorage.getItem(PREFS) || "{}");
    if (saved.mode === "audio" || saved.mode === "video") opts.mode = saved.mode;
    if (typeof saved.to_client === "boolean") opts.toClient = saved.to_client;
  } catch (e) {}

  const esc = (s) => String(s == null ? "" : s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  const setText = (el, text) => { if (el.textContent !== text) el.textContent = text; };

  function syncOpts() {
    $modes.forEach((c) => c.setAttribute("aria-pressed", String(c.dataset.mode === opts.mode)));
    $device.setAttribute("aria-pressed", String(opts.toClient));
    clearTimeout(hintTimer);
    hintTimer = null;
    $hint.classList.remove("is-error");
    $hint.textContent = HINTS[`${opts.mode}:${opts.toClient ? "here" : "desk"}`];
    try { localStorage.setItem(PREFS, JSON.stringify({ mode: opts.mode, to_client: opts.toClient })); } catch (e) {}
  }

  function flash(msg) {
    clearTimeout(hintTimer);
    $hint.classList.add("is-error");
    $hint.textContent = msg;
    hintTimer = setTimeout(syncOpts, 4000);
  }

  $modes.forEach((c) => c.addEventListener("click", () => { opts.mode = c.dataset.mode; syncOpts(); }));
  $device.addEventListener("click", () => { opts.toClient = !opts.toClient; syncOpts(); });
  $url.addEventListener("focus", () => document.body.classList.add("is-typing"));
  $url.addEventListener("blur", () => document.body.classList.remove("is-typing"));
  syncOpts();

  const linkIn = (text) => { const m = String(text || "").match(/https?:\/\/\S+/); return m ? m[0] : null; };

  if (navigator.clipboard && navigator.clipboard.readText) {
    $paste.hidden = false;
    $paste.addEventListener("click", async () => {
      try {
        const text = await navigator.clipboard.readText();
        $url.value = linkIn(text) || text.trim();
      } catch (e) {
        flash("clipboard blocked · long-press the field to paste");
      }
    });
  }

  async function submit(url, mode, toClient) {
    const r = await fetch("/api/download", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ url, mode, to_client: toClient }),
    });
    if (!r.ok) {
      const body = await r.json().catch(() => ({}));
      throw new Error(body.error || `${r.status} ${r.statusText}`);
    }
  }

  $form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const url = linkIn($url.value);
    if (!url) { flash("that does not look like a link"); return; }
    $go.disabled = true;
    try {
      await submit(url, opts.mode, opts.toClient);
      $url.value = "";
      $url.blur();
      await refresh();
    } catch (err) {
      flash(err.message);
    } finally {
      $go.disabled = false;
    }
  });

  function displayName(j) {
    if (j.artist && j.title) return `${j.artist} — ${j.title}`;
    if (j.name) return j.name;
    if (j.filename) return j.filename.replace(/\.[^.]+$/, "");
    try { const u = new URL(j.url); return u.hostname.replace(/^www\./, "") + u.pathname + u.search; } catch (e) { return j.url; }
  }

  const clock = (t) => new Date(t * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

  function dayLabel(t) {
    const d = new Date(t * 1000);
    const today = new Date();
    const yesterday = new Date();
    yesterday.setDate(today.getDate() - 1);
    if (d.toDateString() === today.toDateString()) return "today";
    if (d.toDateString() === yesterday.toDateString()) return "yesterday";
    const o = { weekday: "short", day: "numeric", month: "short" };
    if (d.getFullYear() !== today.getFullYear()) o.year = "numeric";
    return d.toLocaleDateString([], o);
  }

  function meta(j) {
    const bits = [j.mode, j.to_client ? "device" : "desktop", clock(j.started)];
    if (j.gone) bits.push(j.to_client ? "expired" : "file moved or deleted");
    return bits.join(" · ");
  }

  function rate(detail) {
    const d = String(detail || "");
    const size = /of\s+~?\s*([\d.]+\s*[KMGT]?i?B)\b/.exec(d);
    const speed = /at\s+([\d.]+\s*[KMGT]?i?B\/s)/.exec(d);
    const eta = /ETA\s+([\d:]+)/.exec(d);
    const bits = [size && size[1], speed && speed[1], eta && `${eta[1].replace(/^0(?=\d)/, "")} left`].filter(Boolean);
    return bits.length ? bits.join(" · ") : d;
  }

  function buildActive(j) {
    const li = document.createElement("li");
    li.className = "mv-card yt-job";
    li.innerHTML =
      '<div class="yt-job__top"><span class="yt-job__name"></span><span class="mv-pill"></span></div>' +
      '<div class="mv-card__meta"></div>' +
      '<div class="mv-meter"><span class="mv-meter__label"></span><span class="mv-meter__track"><span class="mv-meter__fill"></span></span><span class="mv-meter__value"></span></div>' +
      '<div class="yt-job__detail"></div>' +
      `<div class="yt-job__acts"><button type="button" class="mv-btn" data-act="cancel" data-id="${esc(j.id)}">cancel</button></div>`;
    return li;
  }

  function patchActive(li, j) {
    const q = (s) => li.querySelector(s);
    setText(q(".yt-job__name"), displayName(j));
    const pill = q(".mv-pill");
    pill.className = `mv-pill ${TONE[j.status] || ""}`;
    setText(pill, j.cancelling ? "cancelling" : j.status);
    setText(q(".mv-card__meta"), meta(j));
    const known = typeof j.progress === "number";
    const queued = j.status === "queued";
    q(".mv-meter").classList.toggle("is-queued", queued);
    q(".mv-meter").classList.toggle("is-busy", !known && !queued);
    q(".mv-meter__fill").style.width = `${known ? j.progress : 0}%`;
    setText(q(".mv-meter__label"), j.status === "tagging" ? "tag" : STAGE[j.stage] || (j.status === "queued" ? "wait" : "get"));
    setText(q(".mv-meter__value"), known ? `${Math.floor(j.progress)}%` : "…");
    setText(q(".yt-job__detail"), rate(j.detail) || (j.log_tail && j.log_tail.length ? j.log_tail[j.log_tail.length - 1] : ""));
    const btn = q("[data-act=cancel]");
    btn.disabled = j.cancelling || j.status === "tagging";
    setText(btn, j.cancelling ? "cancelling…" : j.status === "tagging" ? "tagging…" : "cancel");
  }

  function renderActive(list) {
    $active.hidden = list.length === 0;
    setText($activeCount, String(list.length));
    const live = new Set(list.map((j) => j.id));
    for (const [id, li] of activeNodes) {
      if (!live.has(id)) { li.remove(); activeNodes.delete(id); }
    }
    list.forEach((j, i) => {
      let li = activeNodes.get(j.id);
      if (!li) { li = buildActive(j); activeNodes.set(j.id, li); }
      patchActive(li, j);
      if ($activeList.children[i] !== li) $activeList.insertBefore(li, $activeList.children[i] || null);
    });
  }

  function iconBtn(act, id, glyph, label, extra) {
    return `<button type="button" class="mv-btn yt-icon ${extra || ""}" data-act="${act}" data-id="${id}" aria-label="${label}" title="${label}">${glyph}</button>`;
  }

  function rowHTML(j) {
    const id = esc(j.id);
    const acts = j.has_file
      ? [
          iconBtn("play", id, "▶", "play", "is-primary"),
          `<a class="mv-btn yt-icon" href="/api/jobs/${id}/file" download aria-label="save to this device" title="save to this device">↓</a>`,
        ]
      : [iconBtn("retry", id, "↻", "grab again")];
    const pill = j.status === "done" ? "" : `<span class="mv-pill ${TONE[j.status] || ""}">${esc(j.status)}</span> `;
    const src = /^https?:\/\//.test(j.url || "")
      ? `<a class="yt-row__src" href="${esc(j.url)}" target="_blank" rel="noopener noreferrer">${esc(j.url)}</a>`
      : "";
    const log = j.status !== "done" && j.log_tail && j.log_tail.length ? `<pre>${esc(j.log_tail.join("\n"))}</pre>` : "";
    return `<button type="button" class="yt-row__text" data-act="toggle" data-id="${id}" aria-expanded="false">` +
      `<span class="yt-job__name">${esc(displayName(j))}</span>` +
      `<span class="mv-card__meta">${pill}${esc(meta(j))}<span class="yt-row__chev" aria-hidden="true">▾</span></span></button>` +
      `<div class="yt-row__acts">${acts.join("")}</div>` +
      `<div class="yt-row__more" hidden>${src}${log}<button type="button" class="mv-btn" data-act="remove" data-id="${id}">remove from history</button></div>`;
  }

  const rowSig = (j) => JSON.stringify([j.status, j.has_file, j.gone, j.name, j.title, j.artist, j.filename, j.mode, j.to_client, (j.log_tail || []).join("|")]);

  function applyOpen(li, id) {
    const open = openRows.has(id);
    li.classList.toggle("is-open", open);
    li.querySelector(".yt-row__text").setAttribute("aria-expanded", String(open));
    li.querySelector(".yt-row__more").hidden = !open;
  }

  function rowFor(j) {
    const sig = rowSig(j);
    let r = rows.get(j.id);
    if (!r) {
      const li = document.createElement("li");
      li.className = "mv-card yt-job yt-row";
      li.dataset.id = j.id;
      r = { li, sig: null };
      rows.set(j.id, r);
    }
    if (r.sig !== sig) {
      r.li.innerHTML = rowHTML(j);
      r.sig = sig;
    }
    applyOpen(r.li, j.id);
    return r.li;
  }

  function markPlaying() {
    $history.querySelectorAll(".yt-job").forEach((li) => li.classList.toggle("is-playing", !!playing && li.dataset.id === playing.id));
  }

  function renderHistory(list) {
    setText($historyCount, String(list.length));
    const live = new Set(list.map((j) => j.id));
    for (const [id, r] of rows) {
      if (!live.has(id)) { r.li.remove(); rows.delete(id); openRows.delete(id); }
    }
    if (!list.length) {
      $history.innerHTML = '<p class="mv-empty">nothing yet · grabbed links land here</p>';
      markPlaying();
      return;
    }
    $history.querySelectorAll(":scope > .mv-empty").forEach((el) => el.remove());
    const days = [];
    for (const j of list) {
      const label = dayLabel(j.started);
      if (!days.length || days[days.length - 1].label !== label) days.push({ label, items: [] });
      days[days.length - 1].items.push(j);
    }
    const spare = new Map([...$history.querySelectorAll(":scope > .yt-day")].map((el) => [el.dataset.day, el]));
    days.forEach((d, i) => {
      let el = spare.get(d.label);
      spare.delete(d.label);
      if (!el) {
        el = document.createElement("div");
        el.className = "yt-day";
        el.dataset.day = d.label;
        el.innerHTML = '<h3 class="mv-label"></h3><ul class="yt-list"></ul>';
        el.firstChild.textContent = d.label;
      }
      if ($history.children[i] !== el) $history.insertBefore(el, $history.children[i] || null);
      const ul = el.lastChild;
      d.items.forEach((j, k) => {
        const li = rowFor(j);
        if (ul.children[k] !== li) ul.insertBefore(li, ul.children[k] || null);
      });
      while (ul.children.length > d.items.length) ul.lastElementChild.remove();
    });
    spare.forEach((el) => el.remove());
    markPlaying();
  }

  function pinView() {
    if (window.scrollY < 1) return null;
    return [...document.querySelectorAll(".yt .yt-job")]
      .map((el) => ({ el, top: el.getBoundingClientRect().top }))
      .filter((a) => a.top + a.el.offsetHeight > 0 && a.top < window.innerHeight);
  }

  function restoreView(pins) {
    const pin = pins && pins.find((a) => a.el.isConnected);
    if (!pin) return;
    const delta = pin.el.getBoundingClientRect().top - pin.top;
    if (Math.abs(delta) > 0.5) window.scrollBy(0, delta);
  }

  async function refresh() {
    clearTimeout(timer);
    let busy = false;
    try {
      const r = await fetch("/api/jobs", { cache: "no-store" });
      if (r.ok) {
        const data = await r.json();
        jobsById = new Map(data.map((j) => [j.id, j]));
        const active = data.filter((j) => ACTIVE.has(j.status));
        const done = data.filter((j) => !ACTIVE.has(j.status));
        busy = active.length > 0;
        const pins = pinView();
        renderActive(active);
        renderHistory(done);
        restoreView(pins);
        setText($count, busy ? `${active.length} running · ${done.length} in history` : `${done.length} in history`);
      }
    } catch (e) {}
    if (!document.hidden) timer = setTimeout(refresh, busy ? 1500 : 15000);
  }

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) clearTimeout(timer);
    else refresh();
  });

  function stopMedia(el) {
    el.pause();
    el.removeAttribute("src");
    el.load();
  }

  function sizeDock() {
    document.documentElement.style.setProperty("--yt-dock-h", $dock.hidden ? "0px" : `${$dock.offsetHeight}px`);
  }
  if ("ResizeObserver" in window) new ResizeObserver(sizeDock).observe($dock);

  const media = () => (playing ? (playing.video ? $dockVideo : $dockAudio) : null);

  function setExpanded(v) {
    expanded = v;
    $dockBody.hidden = !v;
    $dockMore.setAttribute("aria-expanded", String(v));
    $dockMore.setAttribute("aria-label", v ? "hide player" : "show player");
    $dockMore.textContent = v ? "▾" : "▴";
    sizeDock();
  }
  $dockMore.addEventListener("click", () => setExpanded(!expanded));

  function syncToggle() {
    const el = media();
    const paused = !el || el.paused;
    $dockToggle.textContent = paused ? "▶" : "❚❚";
    $dockToggle.setAttribute("aria-label", paused ? "play" : "pause");
  }
  $dockToggle.addEventListener("click", () => {
    const el = media();
    if (!el) return;
    if (el.paused) el.play().catch(() => {});
    else el.pause();
  });

  [$dockAudio, $dockVideo].forEach((el) => {
    ["play", "pause", "ended", "emptied"].forEach((t) => el.addEventListener(t, syncToggle));
    el.addEventListener("timeupdate", () => {
      if (el === media()) $dockTime.style.width = el.duration ? `${(100 * el.currentTime) / el.duration}%` : "0";
    });
  });

  function play(j) {
    const video = j.mode === "video";
    const el = video ? $dockVideo : $dockAudio;
    const other = video ? $dockAudio : $dockVideo;
    if (other.getAttribute("src")) stopMedia(other);
    other.hidden = true;
    el.hidden = false;
    const fresh = !playing || playing.id !== j.id;
    if (fresh) {
      el.src = `/api/jobs/${j.id}/stream`;
      $dockTime.style.width = "0";
    }
    playing = { id: j.id, title: j.title || displayName(j), artist: j.artist || "", video };
    $dockTitle.textContent = playing.title;
    $dockSub.textContent = [j.artist, j.mode, j.to_client ? "device" : "desktop"].filter(Boolean).join(" · ");
    $dock.hidden = false;
    if (fresh && video) setExpanded(true);
    else sizeDock();
    el.play().catch(() => {});
    syncToggle();
    markPlaying();
  }

  function closeDock() {
    [$dockAudio, $dockVideo].forEach((el) => { if (el.getAttribute("src")) stopMedia(el); });
    playing = null;
    $dock.hidden = true;
    setExpanded(false);
    if ("mediaSession" in navigator) navigator.mediaSession.metadata = null;
    markPlaying();
  }
  $("dock-close").addEventListener("click", closeDock);

  function bindSession(el) {
    if (!("mediaSession" in navigator) || !playing) return;
    const ms = navigator.mediaSession;
    ms.metadata = new MediaMetadata({ title: playing.title, artist: playing.artist, album: "ytdl.mvr.ac" });
    const handlers = {
      play: () => el.play(),
      pause: () => el.pause(),
      stop: closeDock,
      seekbackward: (d) => { el.currentTime = Math.max(0, el.currentTime - (d.seekOffset || 10)); },
      seekforward: (d) => { el.currentTime = el.currentTime + (d.seekOffset || 10); },
      seekto: (d) => { el.currentTime = d.seekTime; },
    };
    for (const [action, fn] of Object.entries(handlers)) {
      try { ms.setActionHandler(action, fn); } catch (e) {}
    }
  }
  [$dockAudio, $dockVideo].forEach((el) => el.addEventListener("play", () => bindSession(el)));

  async function cancel(j, btn) {
    btn.disabled = true;
    setText(btn, "cancelling…");
    await fetch(`/api/jobs/${j.id}/cancel`, { method: "POST" }).catch(() => {});
    refresh();
  }

  async function remove(j) {
    if (j.to_client && j.has_file && !confirm("Remove from history? The file only lives here, so it goes too. Save it first to keep it.")) return;
    if (playing && playing.id === j.id) closeDock();
    openRows.delete(j.id);
    const r = await fetch(`/api/jobs/${j.id}`, { method: "DELETE" }).catch(() => null);
    if (!r || !r.ok) flash("could not remove it");
    refresh();
  }

  async function retry(j, btn) {
    btn.disabled = true;
    try {
      await submit(j.url, j.mode, j.to_client);
      window.scrollTo({ top: 0, behavior: "smooth" });
    } catch (err) {
      flash(err.message);
    }
    refresh();
  }

  function toggle(j, btn) {
    if (openRows.has(j.id)) openRows.delete(j.id);
    else openRows.add(j.id);
    applyOpen(btn.closest(".yt-row"), j.id);
  }

  const ACTIONS = { play, cancel, remove, retry, toggle };
  document.addEventListener("click", (e) => {
    const btn = e.target.closest("[data-act]");
    if (!btn) return;
    const j = jobsById.get(btn.dataset.id);
    const fn = ACTIONS[btn.dataset.act];
    if (j && fn) fn(j, btn);
  });

  refresh();
})();
