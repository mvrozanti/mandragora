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
  let historySig = "";
  let playing = null;
  let timer = null;
  let hintTimer = null;
  const activeNodes = new Map();

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
    q(".mv-meter").classList.toggle("is-busy", !known);
    q(".mv-meter__fill").style.width = `${known ? j.progress : 0}%`;
    setText(q(".mv-meter__label"), j.status === "tagging" ? "tag" : STAGE[j.stage] || (j.status === "queued" ? "wait" : "get"));
    setText(q(".mv-meter__value"), known ? `${Math.floor(j.progress)}%` : "…");
    setText(q(".yt-job__detail"), j.detail || (j.log_tail && j.log_tail.length ? j.log_tail[j.log_tail.length - 1] : ""));
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

  function card(j) {
    const id = esc(j.id);
    const acts = j.has_file
      ? [
          iconBtn("play", id, "▶", "play", "is-primary"),
          `<a class="mv-btn yt-icon" href="/api/jobs/${id}/file" download aria-label="save to this device" title="save to this device">↓</a>`,
        ]
      : [iconBtn("retry", id, "↻", "grab again")];
    acts.push(iconBtn("remove", id, "×", "remove from history"));
    const pill = j.status === "done" ? "" : `<span class="mv-pill ${TONE[j.status] || ""}">${esc(j.status)}</span> `;
    const log = j.status !== "done" && j.log_tail && j.log_tail.length
      ? `<details class="yt-log"><summary>log</summary><pre>${esc(j.log_tail.join("\n"))}</pre></details>`
      : "";
    return `<li class="mv-card yt-job yt-row" data-id="${id}">` +
      `<div class="yt-row__text"><span class="yt-job__name">${esc(displayName(j))}</span>` +
      `<div class="mv-card__meta">${pill}${esc(meta(j))}</div></div>` +
      `<div class="yt-row__acts">${acts.join("")}</div>${log}</li>`;
  }

  function markPlaying() {
    $history.querySelectorAll(".yt-job").forEach((li) => li.classList.toggle("is-playing", !!playing && li.dataset.id === playing.id));
  }

  function renderHistory(list) {
    setText($historyCount, String(list.length));
    const sig = JSON.stringify(list.map((j) => [j.id, j.status, j.has_file, j.gone, j.name, j.title, j.artist, j.filename, (j.log_tail || []).join("|")]));
    if (sig !== historySig) {
      historySig = sig;
      if (!list.length) {
        $history.innerHTML = '<p class="mv-empty">nothing yet · grabbed links land here</p>';
      } else {
        const days = [];
        for (const j of list) {
          const label = dayLabel(j.started);
          if (!days.length || days[days.length - 1].label !== label) days.push({ label, items: [] });
          days[days.length - 1].items.push(j);
        }
        $history.innerHTML = days.map((d) =>
          `<div class="yt-day"><h3 class="mv-label">${esc(d.label)}</h3><ul class="yt-list">${d.items.map(card).join("")}</ul></div>`
        ).join("");
      }
    }
    markPlaying();
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
        renderActive(active);
        renderHistory(done);
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

  function play(j) {
    const video = j.mode === "video";
    const el = video ? $dockVideo : $dockAudio;
    const other = video ? $dockAudio : $dockVideo;
    if (other.getAttribute("src")) stopMedia(other);
    other.hidden = true;
    el.hidden = false;
    if (!playing || playing.id !== j.id) el.src = `/api/jobs/${j.id}/stream`;
    playing = { id: j.id, title: j.title || displayName(j), artist: j.artist || "" };
    $dockTitle.textContent = playing.title;
    $dockSub.textContent = [j.artist, j.mode, j.to_client ? "device" : "desktop"].filter(Boolean).join(" · ");
    $dock.hidden = false;
    sizeDock();
    el.play().catch(() => {});
    markPlaying();
  }

  function closeDock() {
    [$dockAudio, $dockVideo].forEach((el) => { if (el.getAttribute("src")) stopMedia(el); });
    playing = null;
    $dock.hidden = true;
    sizeDock();
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

  const ACTIONS = { play, cancel, remove, retry };
  document.addEventListener("click", (e) => {
    const btn = e.target.closest("[data-act]");
    if (!btn) return;
    const j = jobsById.get(btn.dataset.id);
    const fn = ACTIONS[btn.dataset.act];
    if (j && fn) fn(j, btn);
  });

  refresh();
})();
