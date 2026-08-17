import {
  TOK, CAT, clamp, timeCss, fmtTime, fmtHz,
  prepCanvas, path, strokePath, timePath, text, hline, vline,
  finiteExtent, quantile, heatmap,
} from "./draw.js";

const $ = id => document.getElementById(id);
const params = new URLSearchParams(location.search);
const slug = params.get("t");
if (!slug) location.replace("./");

const base = "tracks/" + encodeURIComponent(slug) + "/";
const audioEl = $("audio");
const RM = matchMedia("(prefers-reduced-motion: reduce)").matches;

const state = { t: 0, playing: false, duration: 0, useAudio: false, baseT: 0, baseNow: 0, pendingSeek: null };
const registry = [];
const subs = [];
const renders = [];
let lastTick = -1;
let D = null, META = null, EMO = null;
const playBtns = [];

function esc(s) {
  return String(s).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
}

function el(tag, cls, html) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (html != null) e.innerHTML = html;
  return e;
}

function sceneText(s) {
  return Array.isArray(s) ? s[0] : s;
}

function signed(v, digits = 2) {
  if (v == null || !isFinite(v)) return "·";
  const a = Math.abs(v).toFixed(digits);
  return (v < 0 ? "−" : "+") + a;
}

function debounce(fn, ms) {
  let h = null;
  return (...a) => {
    clearTimeout(h);
    h = setTimeout(() => fn(...a), ms);
  };
}

function curT() {
  if (state.useAudio) {
    if (audioEl.readyState < 1 && state.pendingSeek != null) return state.pendingSeek;
    return audioEl.currentTime || 0;
  }
  if (!state.playing) return state.baseT;
  return Math.min(state.duration, state.baseT + (performance.now() - state.baseNow) / 1000);
}

function setPlaying(p) {
  if (!state.useAudio) {
    if (p) {
      if (state.baseT >= state.duration) state.baseT = 0;
      state.baseNow = performance.now();
    } else {
      state.baseT = curT();
    }
  } else if (p) {
    audioEl.play().catch(() => degradeToClock(true));
  } else {
    audioEl.pause();
  }
  state.playing = p;
  document.documentElement.classList.toggle("is-playing", p);
  for (const b of playBtns) b.setAttribute("aria-label", p ? "pause" : "play");
}

function degradeToClock(keepPlaying) {
  const t = curT();
  state.useAudio = false;
  state.baseT = t;
  state.baseNow = performance.now();
  state.playing = !!keepPlaying;
  document.documentElement.classList.toggle("is-playing", state.playing);
  visualNote();
}

function seek(t) {
  t = clamp(t, 0, state.duration);
  if (state.useAudio) {
    if (audioEl.readyState >= 1) {
      try { audioEl.currentTime = t; } catch (e) { state.pendingSeek = t; }
    } else {
      state.pendingSeek = t;
      audioEl.load();
    }
  }
  state.baseT = t;
  state.baseNow = performance.now();
  tick(true);
}

function registerTA(container, t0 = 0, t1 = null, seekable = true) {
  if (t1 == null) t1 = state.duration;
  container.classList.add("ta");
  const cur = el("div", "playcursor");
  container.appendChild(cur);
  registry.push({ container, cur, t0, t1 });
  if (seekable) {
    container.addEventListener("pointerdown", ev => {
      if (ev.button !== 0) return;
      ev.preventDefault();
      try { container.setPointerCapture(ev.pointerId); } catch (e) {}
      const move = e2 => {
        const r = container.getBoundingClientRect();
        const f = clamp((e2.clientX - r.left) / r.width, 0, 1);
        seek(t0 + f * (t1 - t0));
      };
      const up = () => {
        container.removeEventListener("pointermove", move);
        container.removeEventListener("pointerup", up);
        container.removeEventListener("pointercancel", up);
      };
      container.addEventListener("pointermove", move);
      container.addEventListener("pointerup", up);
      container.addEventListener("pointercancel", up);
      move(ev);
    });
  }
  return container;
}

function tick(force) {
  const t = curT();
  if (state.playing && !state.useAudio && t >= state.duration) setPlaying(false);
  if (!force && t === lastTick) return;
  lastTick = t;
  state.t = t;
  for (const e of registry) {
    const w = e.container.clientWidth;
    const f = (t - e.t0) / (e.t1 - e.t0);
    if (f < 0 || f > 1) {
      e.cur.style.opacity = "0";
    } else {
      e.cur.style.opacity = "1";
      e.cur.style.transform = "translateX(" + (f * w).toFixed(1) + "px)";
    }
  }
  for (const s of subs) s(t, force);
}

function loop() {
  tick(false);
  requestAnimationFrame(loop);
}

function panel(parent, label) {
  const p = el("div", "panel");
  if (label) p.appendChild(el("p", "plabel", esc(label)));
  parent.appendChild(p);
  return p;
}

function legendRow(pairs) {
  const d = el("div", "legend");
  for (const [name, color] of pairs) {
    d.appendChild(el("span", "lg", '<i style="background:' + color + '"></i>' + esc(name)));
  }
  return d;
}

function taBlock(parent, { t0 = 0, t1 = null, seekable = true, narrow = false } = {}) {
  const wrap = el("div", "scrollwrap" + (narrow ? " narrow" : ""));
  const inner = el("div", "ta-inner");
  wrap.appendChild(inner);
  parent.appendChild(wrap);
  registerTA(inner, t0, t1, seekable);
  return inner;
}

function imgURL(meta) {
  const f = String(meta.file);
  return base + (f.includes("/") ? f : "images/" + f);
}

function yDesc(meta) {
  const y = meta.y || {};
  if (y.scale === "bpm") return Math.round(y.min) + "-" + Math.round(y.max) + " bpm";
  if (y.scale === "mfcc") return "coefficients " + Math.round(y.min) + "-" + Math.round(y.max);
  if (y.max > 100) return (y.scale || "") + " " + fmtHz(y.min || 0) + "-" + fmtHz(y.max) + " Hz";
  return (y.scale || "") + " " + y.min + "-" + y.max;
}

function rasterBlock(parent, id, label, { narrow = false } = {}) {
  const meta = D.images && D.images[id];
  const p = panel(parent, label);
  if (!meta) {
    p.appendChild(el("p", "missing", "raster " + esc(id) + " unavailable"));
    return null;
  }
  const inner = taBlock(p, { t0: meta.t0 ?? 0, t1: meta.t1 ?? state.duration, narrow });
  const img = el("img", "raster");
  img.alt = label || id;
  img.loading = "lazy";
  img.decoding = "async";
  img.draggable = false;
  img.src = imgURL(meta);
  inner.appendChild(img);
  return img;
}

function squareImg(parent, id, label) {
  const meta = D.images && D.images[id];
  const p = panel(parent, label);
  if (!meta) {
    p.appendChild(el("p", "missing", "raster " + esc(id) + " unavailable"));
    return;
  }
  const img = el("img", "square-img");
  img.alt = label || id;
  img.loading = "lazy";
  img.decoding = "async";
  img.src = imgURL(meta);
  p.appendChild(img);
}

function canvasBlock(parent, h, { label, legend, t0 = 0, t1 = null, seekable = true } = {}) {
  const p = panel(parent, label);
  if (legend) p.appendChild(legendRow(legend));
  const inner = taBlock(p, { t0, t1, seekable });
  const c = el("canvas");
  c.style.height = h + "px";
  inner.appendChild(c);
  return c;
}

function fitToggle(sec) {
  const head = sec.querySelector(".chhead");
  const b = el("button", "fit-toggle mono", "1:1");
  b.addEventListener("click", () => {
    const nat = sec.classList.toggle("native");
    b.textContent = nat ? "fit" : "1:1";
    tick(true);
  });
  head.appendChild(b);
}

function chip(label, value) {
  return '<span class="chip">' + (label ? "<i>" + esc(label) + "</i>" : "") + "<b>" + esc(value) + "</b></span>";
}

function keyColor(name) {
  const PC = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
  const m = String(name).match(/^([A-G][#b]?)/);
  if (!m) return TOK.muted;
  let tonic = m[1];
  const FLAT = { Db: "C#", Eb: "D#", Gb: "F#", Ab: "G#", Bb: "A#", Cb: "B", Fb: "E" };
  tonic = FLAT[tonic] || tonic;
  const i = PC.indexOf(tonic);
  return i < 0 ? TOK.muted : CAT[i % 8];
}

async function probeAudio() {
  try {
    const r = await fetch("audio/" + encodeURIComponent(slug) + ".mp3", { method: "HEAD", redirect: "manual" });
    return r.ok;
  } catch (e) {
    return false;
  }
}

function visualNote() {
  const n = $("audio-note");
  const rd = encodeURIComponent(location.href);
  n.innerHTML = 'visuals-only — <a href="https://auth.mvr.ac/?rd=' + rd + '">log in for audio</a>';
  n.hidden = false;
}

function setupAudio(ok) {
  if (!ok) {
    visualNote();
    return;
  }
  state.useAudio = true;
  audioEl.preload = "metadata";
  audioEl.src = "audio/" + encodeURIComponent(slug) + ".mp3";
  audioEl.addEventListener("ended", () => setPlaying(false));
  audioEl.addEventListener("error", () => degradeToClock(state.playing));
  audioEl.addEventListener("loadedmetadata", () => {
    if (state.pendingSeek != null) {
      try { audioEl.currentTime = state.pendingSeek; } catch (e) {}
      state.pendingSeek = null;
    }
  });
}

function fallbackMeta() {
  const words = slug.split("-").map(w => w ? w[0].toUpperCase() + w.slice(1) : w);
  return { slug, artist: "", title: words.join(" "), scenes: [] };
}

function buildHero() {
  const m = META;
  $("h-artist").textContent = m.artist || "";
  $("h-title").textContent = m.title || slug;
  document.title = (m.artist ? m.artist + " — " : "") + (m.title || slug) + " · music.mvr.ac";
  const scenes = (m.scenes || []).map(sceneText).filter(Boolean);
  $("h-scenes").textContent = scenes.join(" / ");
  if (!scenes.length) $("h-scenes").hidden = true;

  const disc = $("disc");
  const dmeta = D.images && (D.images.polar || D.images.polar_thumb);
  if (dmeta) {
    disc.src = imgURL(dmeta);
    disc.hidden = false;
  } else if (m.cover) {
    disc.src = m.cover;
    disc.hidden = false;
  }

  const bpm = D.beats && D.beats.bpm || m.bpm;
  const key = D.key && D.key.global || m.key;
  const lufs = D.loudness ? D.loudness.integrated : null;
  let chips = chip("time", fmtTime(state.duration));
  if (bpm) chips += chip("bpm", (Math.round(bpm * 10) / 10).toFixed(1));
  if (key) chips += chip("key", key);
  if (lufs != null && isFinite(lufs)) chips += chip("lufs", lufs.toFixed(1));
  chips += chip("val", signed(m.valence));
  chips += chip("aro", signed(m.arousal));
  $("h-chips").innerHTML = chips;

  $("t-dur").textContent = fmtTime(state.duration);
  $("dock-title").textContent = (m.artist ? m.artist + " — " : "") + (m.title || slug);

  playBtns.push($("play"), $("dock-play"));
  for (const b of playBtns) b.addEventListener("click", () => setPlaying(!state.playing));

  registerTA($("seek"));
  registerTA($("dock-seek"));
  const fills = [$("seek-fill"), $("dock-seek-fill")];
  const nows = [$("t-now"), $("dock-now")];
  let shown = "";
  subs.push(t => {
    const f = state.duration ? t / state.duration : 0;
    for (const fill of fills) fill.style.transform = "scaleX(" + f.toFixed(4) + ")";
    const s = fmtTime(t);
    if (s !== shown) {
      shown = s;
      for (const n of nows) n.textContent = s;
    }
  });

  const io = new IntersectionObserver(en => {
    $("dock").hidden = en[0].isIntersecting;
  });
  io.observe($("transport"));

  addEventListener("keydown", e => {
    if (e.target && e.target.closest && e.target.closest("input,textarea,select,[contenteditable]")) return;
    if (e.code === "Space") {
      if (e.target.tagName === "BUTTON") return;
      e.preventDefault();
      setPlaying(!state.playing);
    } else if (e.code === "ArrowRight") {
      e.preventDefault();
      seek(curT() + 5);
    } else if (e.code === "ArrowLeft") {
      e.preventDefault();
      seek(curT() - 5);
    }
  });
}

function buildToc() {
  const toc = $("toc");
  for (const sec of document.querySelectorAll("main .chapter:not(.hero)")) {
    const num = sec.querySelector(".chnum");
    const h2 = sec.querySelector("h2");
    if (!num || !h2) continue;
    toc.appendChild(el("a", null, "<b>" + esc(num.textContent) + "</b>" + esc(h2.textContent))).href = "#" + sec.id;
  }
}

function columnStats(arr, i0, i1, mode) {
  let v = mode === "min" ? Infinity : -Infinity;
  for (let i = i0; i < i1 && i < arr.length; i++) {
    const x = arr[i];
    if (x == null || !isFinite(x)) continue;
    if (mode === "min") { if (x < v) v = x; }
    else if (x > v) v = x;
  }
  return isFinite(v) ? v : 0;
}

function buildWave() {
  const b = $("b2");
  const wf = D.waveform;
  const c1 = canvasBlock(b, 190, {
    label: "waveform",
    legend: [["peak envelope", "rgba(230,237,243,.35)"], ["rms core", TOK.accent]],
  });
  renders.push(() => {
    const { ctx, w, h } = prepCanvas(c1, 190);
    const n = wf.max.length;
    const mid = h / 2, amp = h / 2 - 8;
    hline(ctx, mid, w, TOK.grid);
    ctx.beginPath();
    for (let x = 0; x < w; x++) {
      const i0 = Math.floor(x / w * n), i1 = Math.max(i0 + 1, Math.floor((x + 1) / w * n));
      const hi = columnStats(wf.max, i0, i1, "max");
      ctx.lineTo(x, mid - clamp(hi, 0, 1) * amp);
    }
    for (let x = w - 1; x >= 0; x--) {
      const i0 = Math.floor(x / w * n), i1 = Math.max(i0 + 1, Math.floor((x + 1) / w * n));
      const lo = columnStats(wf.min, i0, i1, "min");
      ctx.lineTo(x, mid - clamp(lo, -1, 0) * amp);
    }
    ctx.closePath();
    ctx.fillStyle = "rgba(230,237,243,0.26)";
    ctx.fill();
    ctx.beginPath();
    for (let x = 0; x < w; x++) {
      const i0 = Math.floor(x / w * n), i1 = Math.max(i0 + 1, Math.floor((x + 1) / w * n));
      const r = columnStats(wf.rms, i0, i1, "max");
      ctx.lineTo(x, mid - clamp(r, 0, 1) * amp);
    }
    for (let x = w - 1; x >= 0; x--) {
      const i0 = Math.floor(x / w * n), i1 = Math.max(i0 + 1, Math.floor((x + 1) / w * n));
      const r = columnStats(wf.rms, i0, i1, "max");
      ctx.lineTo(x, mid + clamp(r, 0, 1) * amp);
    }
    ctx.closePath();
    ctx.fillStyle = "rgba(192,132,252,0.55)";
    ctx.fill();
  });

  const ld = D.loudness;
  const c2 = canvasBlock(b, 150, {
    label: "loudness · lufs",
    legend: [["momentary", "rgba(139,148,158,.8)"], ["short-term", TOK.accent], ["integrated " + ld.integrated.toFixed(1), TOK.ink]],
  });
  renders.push(() => {
    const { ctx, w, h } = prepCanvas(c2, 150);
    const [lm] = finiteExtent(ld.momentary);
    const [ls] = finiteExtent(ld.short_term);
    const lo = clamp(Math.floor(Math.min(lm, ls, ld.integrated) / 10) * 10, -70, -20);
    const hi = 0;
    const y = v => h - 4 - (clamp(v, lo, hi) - lo) / (hi - lo) * (h - 14);
    for (let g = hi; g >= lo; g -= 10) {
      hline(ctx, y(g), w);
      text(ctx, String(g), 4, y(g) - 3, { size: 9 });
    }
    const n = ld.momentary.length;
    const x = i => i / (n - 1) * w;
    path(ctx, n, x, i => isFinite(ld.momentary[i]) ? y(ld.momentary[i]) : NaN);
    strokePath(ctx, "rgba(139,148,158,0.65)", 1);
    path(ctx, n, x, i => isFinite(ld.short_term[i]) ? y(ld.short_term[i]) : NaN);
    strokePath(ctx, TOK.accent, 2);
    hline(ctx, y(ld.integrated), w, "rgba(230,237,243,0.8)", [5, 4]);
  });
}

function buildSpectrum() {
  fitToggle($("ch3"));
  const b = $("b3");
  for (const id of ["stft", "mel", "cqt"]) {
    const meta = D.images && D.images[id];
    rasterBlock(b, id, id + (meta ? " · " + yDesc(meta) : ""));
  }
}

function mergeKeyRuns() {
  const per = D.key && D.key.per_segment || [];
  const segs = D.structure && D.structure.segments || [];
  const runs = [];
  const push = (start, end, key) => {
    const last = runs[runs.length - 1];
    if (last && last.key === key && Math.abs(last.end - start) < 0.6) last.end = end;
    else runs.push({ start, end, key });
  };
  if (per.length && typeof per[0] === "object" && per[0] !== null && "key" in per[0]) {
    for (const p of per) push(p.start, p.end, p.key);
  } else if (per.length && segs.length) {
    for (let i = 0; i < segs.length; i++) push(segs[i].start, segs[i].end, per[i] ?? "");
  }
  return runs;
}

function buildHarmony() {
  const b = $("b4");
  const p1 = panel(b, "chromagram · pitch class energy");
  const grid = el("div", "chroma-grid");
  const PC = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
  grid.appendChild(el("div", "pc-labels", PC.slice().reverse().map(p => "<span>" + esc(p) + "</span>").join("")));
  const wrap = el("div", "scrollwrap");
  const inner = el("div", "ta-inner");
  wrap.appendChild(inner);
  grid.appendChild(wrap);
  p1.appendChild(grid);
  registerTA(inner);
  const cc = el("canvas", "pix");
  cc.style.height = "216px";
  inner.appendChild(cc);
  heatmap(cc, D.chroma.matrix, { gain: 1.15 });

  const p2 = panel(b, "key · global " + (D.key && D.key.global || "?") +
    (D.key && D.key.confidence != null ? " · confidence " + D.key.confidence.toFixed(2) : ""));
  const strip = el("div", "keystrip");
  p2.appendChild(strip);
  registerTA(strip);
  for (const run of mergeKeyRuns()) {
    const kb = el("div", "keyblock");
    const c = keyColor(run.key);
    kb.style.setProperty("--c", c);
    kb.style.left = (run.start / state.duration * 100) + "%";
    kb.style.width = (Math.max(0, run.end - run.start) / state.duration * 100) + "%";
    kb.title = run.key + " · " + fmtTime(run.start) + "-" + fmtTime(run.end);
    kb.innerHTML = '<span class="kl">' + esc(run.key) + '</span><span class="ks">' + fmtTime(run.start) + "</span>";
    strip.appendChild(kb);
  }

  const duo = el("div", "duo");
  b.appendChild(duo);
  const p3 = panel(duo, "tonnetz trajectory · dims 0-1, fifths plane, dark to bright is start to end");
  const tc = el("canvas");
  tc.style.height = "420px";
  p3.appendChild(tc);
  renders.push(() => {
    const { ctx, w, h } = prepCanvas(tc, 420);
    const dims = D.tonnetz.dims;
    const n = dims.length;
    let ext = 0.01;
    for (const d of dims) {
      ext = Math.max(ext, Math.abs(d[0]), Math.abs(d[1]));
    }
    ext *= 1.15;
    const side = Math.min(w - 16, h - 16);
    const cx = w / 2, cy = h / 2;
    const px = v => cx + v / ext * side / 2;
    const py = v => cy - v / ext * side / 2;
    ctx.strokeStyle = TOK.grid;
    ctx.strokeRect(cx - side / 2 + 0.5, cy - side / 2 + 0.5, side, side);
    ctx.beginPath();
    ctx.moveTo(cx - side / 2, cy);
    ctx.lineTo(cx + side / 2, cy);
    ctx.moveTo(cx, cy - side / 2);
    ctx.lineTo(cx, cy + side / 2);
    ctx.stroke();
    const step = Math.max(1, Math.floor(n / 2400));
    const m = Math.floor(n / step);
    timePath(ctx, m, i => px(dims[i * step][0]), i => py(dims[i * step][1]), { width: 1.6, alpha: 0.55 });
    const a = dims[0], z = dims[n - 1];
    ctx.fillStyle = TOK.ink;
    ctx.beginPath();
    ctx.arc(px(a[0]), py(a[1]), 3.5, 0, 7);
    ctx.fill();
    ctx.fillStyle = TOK.accent;
    ctx.beginPath();
    ctx.arc(px(z[0]), py(z[1]), 3.5, 0, 7);
    ctx.fill();
    text(ctx, "start", px(a[0]) + 7, py(a[1]) + 3, { color: TOK.ink, size: 9 });
    text(ctx, "end", px(z[0]) + 7, py(z[1]) + 3, { color: TOK.accent, size: 9 });
  });
  squareImg(duo, "helix", "chroma helix · the song wound around the circle of pitch");
}

function buildRhythm() {
  fitToggle($("ch5"));
  const b = $("b5");
  const tmeta = D.images && D.images.tempogram;
  rasterBlock(b, "tempogram", "tempogram" + (tmeta ? " · " + yDesc(tmeta) : "") +
    " · global " + (Math.round((D.beats.bpm || 0) * 10) / 10) + " bpm");

  const on = D.onsets, bt = D.beats;
  const clusterLegend = [];
  for (let k = 0; k < Math.min(bt.n_clusters || 5, 8); k++) clusterLegend.push(["cluster " + (k + 1), CAT[k % 8]]);
  const c1 = canvasBlock(b, 160, {
    label: "onset strength · ticks are beats, colored by timbre cluster",
    legend: clusterLegend,
  });
  renders.push(() => {
    const { ctx, w, h } = prepCanvas(c1, 160);
    const n = on.strength.length;
    const [, mx] = finiteExtent(on.strength);
    const x = i => i / (n - 1) * w;
    const y = v => h - 22 - clamp(v / (mx || 1), 0, 1) * (h - 30);
    ctx.beginPath();
    ctx.moveTo(0, h - 22);
    for (let i = 0; i < n; i++) ctx.lineTo(x(i), y(on.strength[i] || 0));
    ctx.lineTo(w, h - 22);
    ctx.closePath();
    ctx.fillStyle = "rgba(139,148,158,0.28)";
    ctx.fill();
    hline(ctx, h - 22, w, TOK.grid);
    ctx.lineWidth = 1;
    for (let i = 0; i < bt.times.length; i++) {
      const bx = bt.times[i] / state.duration * w;
      ctx.strokeStyle = CAT[(bt.clusters[i] ?? 0) % 8];
      ctx.globalAlpha = 0.85;
      ctx.beginPath();
      ctx.moveTo(bx, h - 18);
      ctx.lineTo(bx, h - 4);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  });

  const c2 = canvasBlock(b, 64, { label: "timbre barcode · one stripe per beat" });
  renders.push(() => {
    const { ctx, w, h } = prepCanvas(c2, 64);
    const times = bt.times, cl = bt.clusters;
    const dtb = times.length > 1 ? times[1] - times[0] : 0.4;
    for (let i = 0; i < times.length; i++) {
      const x0 = times[i] / state.duration * w;
      const x1 = ((times[i + 1] ?? times[i] + dtb)) / state.duration * w;
      ctx.fillStyle = CAT[(cl[i] ?? 0) % 8];
      ctx.fillRect(x0, 4, Math.max(0.6, x1 - x0 - 0.4), h - 8);
    }
  });

  const p3 = panel(b, "ioi poincare · interval n against interval n+1, dark to bright is start to end");
  const c3 = el("canvas");
  c3.style.height = "380px";
  p3.appendChild(c3);
  renders.push(() => {
    const { ctx, w, h } = prepCanvas(c3, 380);
    const t = on.times;
    const iois = [];
    for (let i = 1; i < t.length; i++) {
      const d = t[i] - t[i - 1];
      if (d > 0.02 && d < 2.5) iois.push(d);
    }
    const hi = Math.max(0.2, quantile(iois, 0.98) * 1.15);
    const side = Math.min(w - 60, h - 44);
    const ox = (w - side) / 2 + 14, oy = 12;
    const px = v => ox + clamp(v / hi, 0, 1) * side;
    const py = v => oy + side - clamp(v / hi, 0, 1) * side;
    ctx.strokeStyle = TOK.grid;
    ctx.strokeRect(ox + 0.5, oy + 0.5, side, side);
    ctx.beginPath();
    ctx.moveTo(px(0), py(0));
    ctx.lineTo(px(hi), py(hi));
    ctx.stroke();
    for (let i = 0; i + 1 < iois.length; i++) {
      ctx.fillStyle = timeCss(i / (iois.length - 1), 0.55);
      ctx.beginPath();
      ctx.arc(px(iois[i]), py(iois[i + 1]), 2.2, 0, 7);
      ctx.fill();
    }
    text(ctx, "ioi n (s)", ox + side / 2, oy + side + 16, { align: "center", size: 9 });
    text(ctx, "0", ox - 4, py(0) + 3, { align: "right", size: 9 });
    text(ctx, hi.toFixed(2), ox - 4, py(hi) + 3, { align: "right", size: 9 });
    text(ctx, hi.toFixed(2), px(hi), oy + side + 16, { align: "center", size: 9 });
  });
}

function buildTexture() {
  fitToggle($("ch6"));
  const b = $("b6");
  const mm = D.images && D.images.mfcc;
  rasterBlock(b, "mfcc", "mfcc" + (mm ? " · " + yDesc(mm) : ""));
  rasterBlock(b, "hpss_h", "harmonic skeleton");
  rasterBlock(b, "hpss_p", "percussive skeleton");

  const sp = D.spectral;
  const c1 = canvasBlock(b, 220, {
    label: "spectral descriptors · hz, log scale",
    legend: [["centroid", TOK.accent], ["rolloff", "#22d3ee"], ["bandwidth around centroid", "rgba(139,148,158,.5)"]],
  });
  renders.push(() => {
    const { ctx, w, h } = prepCanvas(c1, 220);
    const lo = 40;
    const hi = Math.max(8000, quantile(sp.rolloff, 0.99) * 1.2);
    const y = v => h - 6 - (Math.log(clamp(v, lo, hi)) - Math.log(lo)) / (Math.log(hi) - Math.log(lo)) * (h - 14);
    for (const g of [100, 1000, 10000]) {
      if (g > hi) continue;
      hline(ctx, y(g), w);
      text(ctx, fmtHz(g), 4, y(g) - 3, { size: 9 });
    }
    const n = sp.centroid.length;
    const x = i => i / (n - 1) * w;
    ctx.beginPath();
    for (let i = 0; i < n; i++) ctx.lineTo(x(i), y((sp.centroid[i] || lo) + (sp.bandwidth[i] || 0) / 2));
    for (let i = n - 1; i >= 0; i--) ctx.lineTo(x(i), y(Math.max(lo, (sp.centroid[i] || lo) - (sp.bandwidth[i] || 0) / 2)));
    ctx.closePath();
    ctx.fillStyle = "rgba(139,148,158,0.18)";
    ctx.fill();
    path(ctx, n, x, i => y(sp.rolloff[i] || lo));
    strokePath(ctx, "#22d3ee", 1.3);
    path(ctx, n, x, i => y(sp.centroid[i] || lo));
    strokePath(ctx, TOK.accent, 2);
  });

  const c2 = canvasBlock(b, 140, {
    label: "noisiness · normalized",
    legend: [["flatness", "#fbbf24"], ["flux", "#fb7185"]],
  });
  renders.push(() => {
    const { ctx, w, h } = prepCanvas(c2, 140);
    const norm = arr => {
      const [lo, hi] = finiteExtent(arr);
      const d = hi - lo || 1;
      return v => (clamp(v, lo, hi) - lo) / d;
    };
    const nf = norm(sp.flatness), nx = norm(sp.flux);
    const n = sp.flatness.length;
    const x = i => i / (n - 1) * w;
    const y = f => h - 6 - f * (h - 12);
    hline(ctx, y(0), w, TOK.grid);
    path(ctx, n, x, i => y(nx(sp.flux[i] || 0)));
    strokePath(ctx, "rgba(251,113,133,0.75)", 1);
    path(ctx, n, x, i => y(nf(sp.flatness[i] || 0)));
    strokePath(ctx, "#fbbf24", 1.6);
  });
}

function buildStructure() {
  const b = $("b7");
  rasterBlock(b, "ssm", "self-similarity · both axes are time, bright blocks repeat", { narrow: true });
  rasterBlock(b, "timelag", "time-lag view · horizontal streaks are repeats at a fixed offset", { narrow: true });

  const segs = D.structure.segments || [];
  const p = panel(b, "sections · " + segs.length + " segments, letters name repeated material");
  const ribbon = el("div", "ribbon");
  p.appendChild(ribbon);
  registerTA(ribbon);
  const blocks = [];
  for (const s of segs) {
    const sb = el("div", "segblock");
    sb.style.setProperty("--c", CAT[(s.cluster ?? 0) % 8]);
    sb.style.left = (s.start / state.duration * 100) + "%";
    sb.style.width = (Math.max(0, s.end - s.start) / state.duration * 100) + "%";
    sb.title = s.label + " · " + fmtTime(s.start) + "-" + fmtTime(s.end);
    sb.innerHTML = '<span class="kl">' + esc(s.label) + "</span>";
    ribbon.appendChild(sb);
    blocks.push({ el: sb, s });
  }
  let liveSeg = -1;
  subs.push(t => {
    let idx = -1;
    for (let i = 0; i < blocks.length; i++) {
      if (t >= blocks[i].s.start && t < blocks[i].s.end) { idx = i; break; }
    }
    if (idx !== liveSeg) {
      if (liveSeg >= 0) blocks[liveSeg].el.classList.remove("on");
      if (idx >= 0) blocks[idx].el.classList.add("on");
      liveSeg = idx;
    }
  });

  const nv = D.novelty;
  const c1 = canvasBlock(b, 140, {
    label: "novelty · vertical rules are detected boundaries",
  });
  renders.push(() => {
    const { ctx, w, h } = prepCanvas(c1, 140);
    const n = nv.curve.length;
    const [, mx] = finiteExtent(nv.curve);
    const x = i => i / (n - 1) * w;
    const y = v => h - 5 - clamp(v / (mx || 1), 0, 1) * (h - 10);
    ctx.beginPath();
    ctx.moveTo(0, h - 5);
    for (let i = 0; i < n; i++) ctx.lineTo(x(i), y(nv.curve[i] || 0));
    ctx.lineTo(w, h - 5);
    ctx.closePath();
    ctx.fillStyle = "rgba(139,148,158,0.3)";
    ctx.fill();
    for (const bd of D.structure.boundaries || []) {
      if (bd < 0.5 || bd > state.duration - 0.5) continue;
      vline(ctx, bd / state.duration * w, h, "rgba(192,132,252,0.55)", [3, 3]);
    }
  });

  const mo = D.motifs && D.motifs.pairs || [];
  const c2 = canvasBlock(b, 220, {
    label: "repeated material · an arc joins a passage to its echo",
    legend: [["passage", "rgba(230,237,243,.55)"], ["echo", TOK.accent], ["arc, brighter is stronger", "#fb7185"]],
  });
  renders.push(() => {
    const { ctx, w, h } = prepCanvas(c2, 220);
    const baseY = h - 14;
    hline(ctx, baseY + 7, w, TOK.grid);
    const x = t => t / state.duration * w;
    for (const pr of mo) {
      const xa = x((pr.a_start + pr.a_end) / 2);
      const xb = x((pr.b_start + pr.b_end) / 2);
      const span = Math.abs(xb - xa);
      const lift = clamp(26 + span * 0.55, 26, (baseY - 12) * 2);
      ctx.strokeStyle = "rgba(251,113,133," + (0.15 + 0.6 * clamp(pr.score, 0, 1)) + ")";
      ctx.lineWidth = 1 + clamp(pr.score, 0, 1) * 1.6;
      ctx.beginPath();
      ctx.moveTo(xa, baseY);
      ctx.quadraticCurveTo((xa + xb) / 2, baseY - lift, xb, baseY);
      ctx.stroke();
    }
    for (const pr of mo) {
      ctx.fillStyle = "rgba(230,237,243,0.5)";
      ctx.fillRect(x(pr.a_start), baseY + 2, Math.max(1.5, x(pr.a_end) - x(pr.a_start)), 5);
      ctx.fillStyle = "rgba(192,132,252,0.75)";
      ctx.fillRect(x(pr.b_start), baseY + 2, Math.max(1.5, x(pr.b_end) - x(pr.b_start)), 5);
    }
  });
}

function buildStereo() {
  const b = $("b8");
  const st = D.stereo;
  const c1 = canvasBlock(b, 150, { label: "channel correlation · +1 mono, 0 wide, -1 out of phase" });
  renders.push(() => {
    const { ctx, w, h } = prepCanvas(c1, 150);
    const y = v => h / 2 - clamp(v, -1, 1) * (h / 2 - 8);
    hline(ctx, y(1), w);
    hline(ctx, y(0), w, "rgba(139,148,158,0.3)");
    hline(ctx, y(-1), w);
    text(ctx, "+1", 4, y(1) + 10, { size: 9 });
    text(ctx, "0", 4, y(0) - 3, { size: 9 });
    text(ctx, "-1", 4, y(-1) - 3, { size: 9 });
    const n = st.correlation.length;
    const x = i => i / (n - 1) * w;
    ctx.beginPath();
    ctx.moveTo(0, y(0));
    for (let i = 0; i < n; i++) ctx.lineTo(x(i), y(st.correlation[i] || 0));
    ctx.lineTo(w, y(0));
    ctx.closePath();
    ctx.fillStyle = "rgba(192,132,252,0.15)";
    ctx.fill();
    path(ctx, n, x, i => y(st.correlation[i] || 0));
    strokePath(ctx, TOK.accent, 1.6);
  });

  const c2 = canvasBlock(b, 160, {
    label: "mid and side · db",
    legend: [["mid", "#38bdf8"], ["side", "#f472b6"]],
  });
  renders.push(() => {
    const { ctx, w, h } = prepCanvas(c2, 160);
    const [m0, m1] = finiteExtent(st.mid_db);
    const [s0, s1] = finiteExtent(st.side_db);
    const lo = Math.floor(Math.min(m0, s0) / 5) * 5;
    const hi = Math.ceil(Math.max(m1, s1) / 5) * 5;
    const y = v => h - 6 - (clamp(v, lo, hi) - lo) / (hi - lo || 1) * (h - 14);
    for (let g = hi; g >= lo; g -= 10) {
      hline(ctx, y(g), w);
      text(ctx, String(g), 4, y(g) - 3, { size: 9 });
    }
    const n = st.mid_db.length;
    const x = i => i / (n - 1) * w;
    path(ctx, n, x, i => isFinite(st.mid_db[i]) ? y(st.mid_db[i]) : NaN);
    strokePath(ctx, "#38bdf8", 1.6);
    path(ctx, n, x, i => isFinite(st.side_db[i]) ? y(st.side_db[i]) : NaN);
    strokePath(ctx, "#f472b6", 1.6);
  });

  const frames = st.lissajous || [];
  const p = panel(b, "goniometer · twenty-four instants, the lit frame is now");
  const grid = el("div", "gonio-grid");
  p.appendChild(grid);
  const cells = [];
  for (const fr of frames) {
    const btn = el("button", "gframe");
    btn.title = "seek to " + fmtTime(fr.t);
    const c = el("canvas");
    c.width = 120;
    c.height = 120;
    btn.appendChild(c);
    btn.appendChild(el("span", null, fmtTime(fr.t)));
    btn.addEventListener("click", () => seek(fr.t));
    grid.appendChild(btn);
    cells.push({ btn, fr });
    const ctx = c.getContext("2d");
    ctx.strokeStyle = TOK.grid;
    ctx.beginPath();
    ctx.moveTo(10, 110);
    ctx.lineTo(110, 10);
    ctx.moveTo(10, 10);
    ctx.lineTo(110, 110);
    ctx.stroke();
    ctx.fillStyle = "rgba(230,237,243,0.5)";
    for (let i = 0; i < fr.x.length; i++) {
      const px = 60 + clamp(fr.x[i], -1, 1) * 55;
      const py = 60 - clamp(fr.y[i], -1, 1) * 55;
      ctx.fillRect(px, py, 1.4, 1.4);
    }
  }
  let liveG = -1;
  subs.push(t => {
    let best = -1, bd = Infinity;
    for (let i = 0; i < cells.length; i++) {
      const d = Math.abs(cells[i].fr.t - t);
      if (d < bd) { bd = d; best = i; }
    }
    if (best !== liveG) {
      if (liveG >= 0) cells[liveG].btn.classList.remove("live");
      if (best >= 0) cells[best].btn.classList.add("live");
      liveG = best;
    }
  });
}

function moodLabel(k) {
  return k.replace(/^mood_/, "");
}

function buildFeeling() {
  $("ch9").hidden = false;
  const b = $("b9");
  const times = EMO.times;
  const n = times.length;
  const hop = EMO.hop_sec || (n > 1 ? times[1] - times[0] : 5);

  const duo = el("div", "duo");
  b.appendChild(duo);

  const p1 = panel(duo, "valence and arousal · the path is the song from dark start to bright end");
  const wrap = el("div", "plane-wrap");
  p1.appendChild(wrap);
  const cBase = el("canvas");
  const cDot = el("canvas", "overlay");
  wrap.appendChild(cBase);
  wrap.appendChild(cDot);
  let plane = null;
  renders.push(() => {
    const s = Math.max(200, wrap.clientWidth);
    const { ctx, w, h } = prepCanvas(cBase, s);
    prepCanvas(cDot, s);
    let r = 1.05;
    for (let i = 0; i < n; i++) r = Math.max(r, Math.abs(EMO.valence[i]), Math.abs(EMO.arousal[i]));
    const g = EMO.global || {};
    if (isFinite(g.valence)) r = Math.max(r, Math.abs(g.valence));
    if (isFinite(g.arousal)) r = Math.max(r, Math.abs(g.arousal));
    r *= 1.12;
    const px = v => w / 2 + v / r * (w / 2 - 14);
    const py = v => h / 2 - v / r * (h / 2 - 14);
    plane = { px, py };
    ctx.strokeStyle = TOK.grid;
    ctx.strokeRect(px(-r) + 0.5, py(r) + 0.5, px(r) - px(-r), py(-r) - py(r));
    ctx.beginPath();
    ctx.moveTo(px(-r), py(0));
    ctx.lineTo(px(r), py(0));
    ctx.moveTo(px(0), py(-r));
    ctx.lineTo(px(0), py(r));
    ctx.stroke();
    text(ctx, "valence +", px(r) - 4, py(0) + 12, { align: "right", size: 9 });
    text(ctx, "valence -", px(-r) + 4, py(0) + 12, { size: 9 });
    text(ctx, "arousal +", px(0) + 5, py(r) + 10, { size: 9 });
    text(ctx, "arousal -", px(0) + 5, py(-r) - 5, { size: 9 });
    timePath(ctx, n, i => px(EMO.valence[i]), i => py(EMO.arousal[i]), { width: 1.8, alpha: 0.75 });
    if (isFinite(g.valence) && isFinite(g.arousal)) {
      const gx = px(g.valence), gy = py(g.arousal);
      ctx.strokeStyle = "rgba(230,237,243,0.85)";
      ctx.lineWidth = 1.2;
      ctx.beginPath();
      ctx.moveTo(gx - 5, gy);
      ctx.lineTo(gx + 5, gy);
      ctx.moveTo(gx, gy - 5);
      ctx.lineTo(gx, gy + 5);
      ctx.stroke();
      text(ctx, "global", gx + 7, gy - 5, { color: TOK.ink, size: 9 });
    }
  });
  const emoAt = t => {
    const f = clamp((t - times[0]) / hop, 0, n - 1);
    const i = Math.floor(f), fr = f - i;
    const j = Math.min(i + 1, n - 1);
    return {
      v: EMO.valence[i] + (EMO.valence[j] - EMO.valence[i]) * fr,
      a: EMO.arousal[i] + (EMO.arousal[j] - EMO.arousal[i]) * fr,
      i: clamp(Math.round(f), 0, n - 1),
    };
  };
  subs.push(t => {
    if (!plane) return;
    const dpr = Math.min(devicePixelRatio || 1, 2);
    const ctx = cDot.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, cDot.width, cDot.height);
    const e = emoAt(t);
    const x = plane.px(e.v), y = plane.py(e.a);
    ctx.fillStyle = TOK.accent;
    ctx.beginPath();
    ctx.arc(x, y, 4.5, 0, 7);
    ctx.fill();
    ctx.strokeStyle = "rgba(192,132,252,0.5)";
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.arc(x, y, 9, 0, 7);
    ctx.stroke();
  });

  const p2 = panel(duo, "seven moods · probability through time");
  const moodsEl = el("div", "moods");
  p2.appendChild(moodsEl);
  const moodKeys = Object.keys(EMO.moods || {});
  const moodCells = [];
  for (const k of moodKeys) {
    const cell = el("div", "mood");
    cell.innerHTML = '<div class="mhead"><span class="mname">' + esc(moodLabel(k)) + '</span><span class="mval">·</span></div>';
    const c = el("canvas");
    cell.appendChild(c);
    moodsEl.appendChild(cell);
    moodCells.push({ c, k, val: cell.querySelector(".mval") });
  }
  const drawMood = (cell, idx) => {
    const { ctx, w, h } = prepCanvas(cell.c, 42);
    const arr = EMO.moods[cell.k];
    const x = i => i / (n - 1) * w;
    const y = v => h - 3 - clamp(v, 0, 1) * (h - 6);
    hline(ctx, y(0), w, TOK.grid);
    path(ctx, n, x, i => y(arr[i] || 0));
    strokePath(ctx, TOK.accent, 1.3);
    if (idx >= 0) {
      ctx.fillStyle = TOK.ink;
      ctx.beginPath();
      ctx.arc(x(idx), y(arr[idx] || 0), 2.6, 0, 7);
      ctx.fill();
      cell.val.textContent = (arr[idx] || 0).toFixed(2);
    }
  };
  let lastWin = -1;
  renders.push(() => {
    for (const cell of moodCells) drawMood(cell, lastWin);
  });
  subs.push(t => {
    const i = clamp(Math.round((t - times[0]) / hop), 0, n - 1);
    if (i === lastWin) return;
    lastWin = i;
    for (const cell of moodCells) drawMood(cell, i);
  });

  const p3 = panel(b, "what the model saw · the leading scene phrase along the song");
  const river = el("div", "river");
  p3.appendChild(river);
  registerTA(river);
  const scenes = EMO.scenes || [];
  const spans = [];
  for (const sc of scenes) {
    const phrase = sc.top && sc.top[0] ? sceneText(sc.top[0][0] != null ? sc.top[0][0] : sc.top[0]) : "";
    const last = spans[spans.length - 1];
    if (last && last.phrase === phrase) last.end = sc.t + hop;
    else spans.push({ phrase, start: Math.max(0, sc.t - hop / 2), end: sc.t + hop });
  }
  const spanEls = [];
  spans.forEach((sp, i) => {
    const frac = (sp.end - sp.start) / state.duration;
    const d = el("div", "rspan lane" + (i % 2 + 1) + (frac < 0.012 ? " tiny" : ""));
    d.style.left = (sp.start / state.duration * 100) + "%";
    d.style.width = (Math.max(0.5, frac * 100)) + "%";
    d.textContent = sp.phrase;
    d.title = sp.phrase + " · " + fmtTime(sp.start);
    river.appendChild(d);
    spanEls.push({ el: d, sp });
  });
  let liveSpan = -1;
  subs.push(t => {
    let idx = -1;
    for (let i = 0; i < spanEls.length; i++) {
      if (t >= spanEls[i].sp.start && t < spanEls[i].sp.end) { idx = i; break; }
    }
    if (idx !== liveSpan) {
      if (liveSpan >= 0) spanEls[liveSpan].el.classList.remove("live");
      if (idx >= 0) spanEls[idx].el.classList.add("live");
      liveSpan = idx;
    }
  });
}

function buildChaos() {
  const b = $("b10");
  const duo = el("div", "duo");
  b.appendChild(duo);
  squareImg(duo, "phase", "phase portrait · the signal against its own delay");

  const cx = D.complexity;
  const sp = D.spectral;
  const p = panel(duo, "complexity");
  p.appendChild(legendRow([["lz76, normalized", TOK.accent], ["spectral flatness, normalized", "#fbbf24"]]));
  const inner = taBlock(p);
  const c = el("canvas");
  c.style.height = "180px";
  inner.appendChild(c);
  renders.push(() => {
    const { ctx, w, h } = prepCanvas(c, 180);
    const norm = arr => {
      const [lo, hi] = finiteExtent(arr);
      const d = hi - lo || 1;
      return v => (clamp(v, lo, hi) - lo) / d;
    };
    const y = f => h - 6 - f * (h - 12);
    hline(ctx, y(0), w, TOK.grid);
    hline(ctx, y(1), w, TOK.grid);
    const nfl = norm(sp.flatness);
    const nn = sp.flatness.length;
    path(ctx, nn, i => i / (nn - 1) * w, i => y(nfl(sp.flatness[i] || 0)));
    strokePath(ctx, "rgba(251,191,36,0.6)", 1);
    const nlz = norm(cx.lz76);
    const m = cx.lz76.length;
    path(ctx, m, i => i / (m - 1) * w, i => y(nlz(cx.lz76[i] || 0)));
    strokePath(ctx, TOK.accent, 2);
  });
}

async function boot() {
  let data, mf, emo;
  try {
    [mf, data, emo] = await Promise.all([
      fetch("tracks/manifest.json").then(r => r.ok ? r.json() : null).catch(() => null),
      fetch(base + "data.json").then(r => {
        if (!r.ok) throw new Error(String(r.status));
        return r.json();
      }),
      fetch(base + "emotion.json").then(r => r.ok ? r.json() : null).catch(() => null),
    ]);
  } catch (e) {
    $("status").textContent = "this track could not be read";
    return;
  }
  D = data;
  EMO = emo && emo.times && emo.times.length ? emo : null;
  META = ((mf && mf.tracks) || []).find(t => t.slug === slug) || fallbackMeta();
  state.duration = D.duration || META.duration || 1;

  const ok = await probeAudio();
  setupAudio(ok);

  $("status").remove();
  $("essay").hidden = false;

  buildHero();
  buildWave();
  buildSpectrum();
  buildHarmony();
  buildRhythm();
  buildTexture();
  buildStructure();
  buildStereo();
  if (EMO) buildFeeling();
  else $("ch9").remove();
  buildChaos();
  buildToc();

  for (const r of renders) r();
  addEventListener("resize", debounce(() => {
    for (const r of renders) r();
    tick(true);
  }, 160));

  tick(true);
  requestAnimationFrame(loop);
}

boot();
