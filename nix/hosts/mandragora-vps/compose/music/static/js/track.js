import {
  TOK, CAT, MONO, clamp, timeCss, magmaCss, fmtTime, fmtHz,
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
let D = null, META = null, EMO = null, GRAMMAR = null, LLM = null, CLAPW = null;
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
      if (ev.pointerType === "touch" && !container.classList.contains("seekbar")) {
        const sx = ev.clientX, sy = ev.clientY, st = performance.now();
        const tup = e2 => {
          container.removeEventListener("pointerup", tup);
          container.removeEventListener("pointercancel", tcancel);
          if (Math.abs(e2.clientX - sx) < 12 && Math.abs(e2.clientY - sy) < 12
              && performance.now() - st < 500) {
            const r = container.getBoundingClientRect();
            const f = clamp((e2.clientX - r.left) / r.width, 0, 1);
            seek(t0 + f * (t1 - t0));
          }
        };
        const tcancel = () => {
          container.removeEventListener("pointerup", tup);
          container.removeEventListener("pointercancel", tcancel);
        };
        container.addEventListener("pointerup", tup);
        container.addEventListener("pointercancel", tcancel);
        return;
      }
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
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), 6000);
  try {
    const r = await fetch("audio/" + encodeURIComponent(slug) + ".mp3",
      { method: "HEAD", redirect: "manual", signal: ac.signal });
    return r.ok;
  } catch (e) {
    return false;
  } finally {
    clearTimeout(timer);
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
  if (params.get("debug")) {
    for (const ev of ["seeking", "seeked", "stalled", "waiting", "suspend", "error", "canplay", "playing"]) {
      audioEl.addEventListener(ev, () => {
        const br = [];
        for (let i = 0; i < audioEl.buffered.length; i++) br.push(audioEl.buffered.start(i).toFixed(1) + "-" + audioEl.buffered.end(i).toFixed(1));
        console.log("[audio]", ev, "t=" + audioEl.currentTime.toFixed(2), "rs=" + audioEl.readyState, "ns=" + audioEl.networkState, "buf=" + br.join(","));
      });
    }
  }
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
  return { slug, artist: "", title: words.join(" ") };
}

function buildHero() {
  const m = META;
  $("h-artist").textContent = m.artist || "";
  $("h-title").textContent = m.title || slug;
  document.title = (m.artist ? m.artist + " — " : "") + (m.title || slug) + " · music.mvr.ac";
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

function sectionSpans() {
  if (GRAMMAR && GRAMMAR.sections && GRAMMAR.sections.length) return GRAMMAR.sections;
  return (D.structure.segments || []).map(s => ({ t0: s.start, t1: s.end, label: s.label }));
}

function letterIdx(l) {
  return Math.max(0, String(l).charCodeAt(0) - 65);
}

function beatIndexAt(t) {
  const bt = D.beats.times;
  let lo = 0, hi = bt.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (bt[mid] <= t) lo = mid; else hi = mid - 1;
  }
  return lo;
}

let DBOFF = null;
function downbeatOffset() {
  if (DBOFF != null) return DBOFF;
  DBOFF = 0;
  if (!GRAMMAR) return DBOFF;
  const bt = D.beats.times;
  const mass = [0, 0, 0, 0];
  for (const tok of GRAMMAR.tokens) {
    if (!tok.family || tok.family[0] !== "K") continue;
    const bi = beatIndexAt(tok.t0);
    const span = (bt[bi + 1] || bt[bi] + 0.42) - bt[bi];
    if ((tok.t0 - bt[bi]) / span < 0.25) mass[bi % 4]++;
  }
  let best = 0;
  for (let o = 1; o < 4; o++) if (mass[o] > mass[best]) best = o;
  DBOFF = best;
  return DBOFF;
}

function buildPump() {
  const b = $("b2");
  const wf = D.waveform;
  const bt = (D.beats && D.beats.times) || [];
  if (bt.length < 16) {
    const c0 = canvasBlock(b, 140, { label: "level · rms" });
    renders.push(() => {
      const { ctx, w, h } = prepCanvas(c0, 140);
      const n = wf.rms.length;
      const [, mx] = finiteExtent(wf.rms);
      path(ctx, n, i => i / (n - 1) * w, i => h - 6 - clamp(wf.rms[i] / (mx || 1), 0, 1) * (h - 12));
      strokePath(ctx, TOK.accent, 1.4);
    });
    return;
  }
  const P = 32;
  const rows = [];
  for (const sec of sectionSpans()) {
    let k0 = beatIndexAt(sec.t0);
    if (bt[k0] < sec.t0 - 0.01) k0++;
    const shape = new Float64Array(P);
    let nb = 0;
    for (let k = k0; k + 1 < bt.length && bt[k + 1] <= sec.t1 + 0.01; k++) {
      const a = bt[k], span = bt[k + 1] - a;
      if (span <= 0) continue;
      for (let j = 0; j < P; j++) {
        const idx = (a + span * (j + 0.5) / P) * wf.pps;
        const i0 = Math.min(Math.floor(idx), wf.rms.length - 2);
        const f = idx - i0;
        shape[j] += wf.rms[i0] * (1 - f) + wf.rms[i0 + 1] * f;
      }
      nb++;
    }
    if (nb < 8) continue;
    let pk = 1e-9;
    for (let j = 0; j < P; j++) { shape[j] /= nb; if (shape[j] > pk) pk = shape[j]; }
    const db = [];
    for (let j = 0; j < P; j++) db.push(clamp(20 * Math.log10(shape[j] / pk + 1e-6), -18, 0));
    rows.push({ sec, db, nb });
  }
  if (rows.length) {
    const p = panel(b, "the pump · each section's beat folded on itself, dB below its own peak");
    const gridEl = el("div", "pump");
    const labCol = el("div", "pump-labels");
    const cwrap = el("div", "pump-canvas");
    const c = el("canvas");
    const rowH = 22;
    const hCss = rows.length * rowH + 6;
    c.style.height = hCss + "px";
    cwrap.appendChild(c);
    const tick = el("div", "pump-tick");
    cwrap.appendChild(tick);
    gridEl.appendChild(labCol);
    gridEl.appendChild(cwrap);
    p.appendChild(gridEl);
    const labs = [];
    rows.forEach(r => {
      const lb = el("button", "pump-label", esc(r.sec.label) + " <i>" + fmtTime(r.sec.t0) + "</i>");
      lb.style.height = rowH + "px";
      lb.addEventListener("click", () => { seek(r.sec.t0); if (!state.playing) setPlaying(true); });
      labCol.appendChild(lb);
      labs.push(lb);
    });
    renders.push(() => {
      const { ctx, w } = prepCanvas(c, hCss);
      const cw = w / P;
      rows.forEach((r, ri) => {
        for (let j = 0; j < P; j++) {
          ctx.fillStyle = magmaCss(clamp(1 + r.db[j] / 18, 0, 1) * 0.92, 1);
          ctx.fillRect(j * cw, ri * rowH + 3, cw - 1, rowH - 5);
        }
      });
    });
    let liveRow = -1;
    subs.push(t => {
      let idx = -1;
      for (let i = 0; i < rows.length; i++) if (t >= rows[i].sec.t0 && t < rows[i].sec.t1) { idx = i; break; }
      if (idx !== liveRow) {
        if (liveRow >= 0) labs[liveRow].classList.remove("on");
        if (idx >= 0) labs[idx].classList.add("on");
        liveRow = idx;
      }
      if (idx >= 0 && state.playing) {
        const bi = beatIndexAt(t);
        const span = (bt[bi + 1] || bt[bi] + 0.42) - bt[bi];
        const ph = clamp((t - bt[bi]) / span, 0, 1);
        tick.style.opacity = "1";
        tick.style.left = (ph * 100) + "%";
        tick.style.top = (idx * rowH + 2) + "px";
        tick.style.height = (rowH - 4) + "px";
      } else {
        tick.style.opacity = "0";
      }
    });
    p.appendChild(el("p", "caption", "dark cells are the duck of the sidechain; a flat bright row does not pump · click a section to hear it"));
  }
  const c2 = canvasBlock(b, 120, { label: "punch · crest factor per beat, dB" });
  renders.push(() => {
    const { ctx, w, h } = prepCanvas(c2, 120);
    hline(ctx, h - 8, w, TOK.grid);
    for (let k = 0; k + 1 < bt.length; k++) {
      const i0 = Math.floor(bt[k] * wf.pps);
      const i1 = Math.max(i0 + 1, Math.floor(bt[k + 1] * wf.pps));
      let pk = 1e-9, rs = 0, n = 0;
      for (let i = i0; i < Math.min(i1, wf.rms.length); i++) {
        const a = Math.max(Math.abs(wf.min[i] || 0), Math.abs(wf.max[i] || 0));
        if (a > pk) pk = a;
        rs += wf.rms[i] || 0;
        n++;
      }
      if (!n || rs <= 0) continue;
      const crest = clamp(20 * Math.log10(pk / (rs / n)), 3, 15);
      const norm = (crest - 3) / 12;
      const x0 = bt[k] / state.duration * w;
      const x1 = bt[k + 1] / state.duration * w;
      ctx.fillStyle = "rgba(192,132,252," + (0.25 + 0.6 * norm).toFixed(3) + ")";
      ctx.fillRect(x0, h - 8 - norm * (h - 18), Math.max(0.8, x1 - x0 - 0.3), norm * (h - 18));
    }
    text(ctx, "15", 4, 14, { size: 9 });
    text(ctx, "3", 4, h - 12, { size: 9 });
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

  buildPianoRoll(b);
}

function buildPianoRoll(b) {
  if (!GRAMMAR) return;
  const toks = GRAMMAR.tokens.filter(t => t.family && "BLP".includes(t.stream));
  if (!toks.length) return;
  const { rows } = laneLayout();
  let lo = Infinity, hi = -Infinity;
  for (const t of toks) { if (t.pitch_bin < lo) lo = t.pitch_bin; if (t.pitch_bin > hi) hi = t.pitch_bin; }
  lo = Math.max(0, lo - 2); hi = hi + 2;
  const c = canvasBlock(b, 300, {
    label: "piano roll · bass, lead and air as played, semitones above C1",
    legend: [["bass", STREAM_HUES.B], ["lead", STREAM_HUES.L], ["pad-fx", STREAM_HUES.P]],
  });
  c.classList.add("wide-min");
  renders.push(() => {
    const { ctx, w, h } = prepCanvas(c, 300);
    const semi = (h - 18) / Math.max(hi - lo, 1);
    const y = bin => h - 10 - (bin - lo) * semi;
    for (let bin = Math.ceil(lo / 12) * 12; bin <= hi; bin += 12) {
      hline(ctx, y(bin), w, "rgba(139,148,158,0.22)");
      text(ctx, "C" + (1 + bin / 12), 4, y(bin) - 3, { size: 9, color: TOK.muted });
    }
    const x = t => t / state.duration * w;
    for (const tok of toks) {
      const r = rows[tok.family];
      if (!r) continue;
      const alpha = 0.25 + 0.75 * clamp((tok.peak_db + 45) / 45, 0.05, 1);
      ctx.fillStyle = famColor(tok.family, r.idx, r.nfam, alpha);
      ctx.fillRect(x(tok.t0), y(tok.pitch_bin) - Math.max(semi * 0.8, 2) / 2,
        Math.max(x(tok.t1) - x(tok.t0), 1.5), Math.max(semi * 0.8, 2));
    }
  });
}

function buildSequencer(b) {
  if (!GRAMMAR || !D.beats || D.beats.times.length < 16) return;
  const bt = D.beats.times;
  const off = downbeatOffset();
  const { rows } = laneLayout();
  const famList = GRAMMAR.devices.map(d => d.id);
  const secs = [];
  for (const sec of sectionSpans()) {
    let k0 = beatIndexAt(sec.t0);
    if (bt[k0] < sec.t0 - 0.01) k0++;
    let k1 = k0;
    while (k1 + 1 < bt.length && bt[k1 + 1] <= sec.t1 + 0.01) k1++;
    const bars = Math.floor((k1 - k0) / 4);
    if (bars < 4) continue;
    secs.push({ sec, k0, k1, bars, occ: {} });
  }
  if (!secs.length) return;
  for (const tok of GRAMMAR.tokens) {
    if (!tok.family) continue;
    const bi = beatIndexAt(tok.t0);
    const span = (bt[bi + 1] || bt[bi] + 0.42) - bt[bi];
    const six = clamp(Math.floor((tok.t0 - bt[bi]) / span * 4), 0, 3);
    const step = (((bi - off) % 4 + 4) % 4) * 4 + six;
    for (const sc of secs) {
      if (bi >= sc.k0 && bi < sc.k1) {
        if (!sc.occ[tok.family]) sc.occ[tok.family] = new Float64Array(16);
        sc.occ[tok.family][step] += 1;
        break;
      }
    }
  }
  const active = famList.filter(f => secs.some(sc => sc.occ[f]));
  if (!active.length) return;
  const p = panel(b, "sequencer · what the machine plays, one 16-step bar per section");
  const wrap = el("div", "scrollwrap");
  const holder = el("div", "seq-holder");
  wrap.appendChild(holder);
  p.appendChild(wrap);
  const c = el("canvas");
  const LAB = 44, SEC_W = 148, ROW_H = 13, HDR = 20;
  const totalW = LAB + secs.length * SEC_W;
  const hCss = HDR + active.length * ROW_H + 6;
  c.style.width = totalW + "px";
  c.style.height = hCss + "px";
  holder.style.width = totalW + "px";
  holder.appendChild(c);
  const cur = el("div", "seq-cur");
  holder.appendChild(cur);
  renders.push(() => {
    const { ctx } = prepCanvas(c, hCss);
    active.forEach((f, ri) => {
      const r = rows[f];
      ctx.fillStyle = famColor(f, r.idx, r.nfam, 1);
      ctx.font = "9px " + MONO;
      ctx.fillText(f, 4, HDR + ri * ROW_H + ROW_H - 4);
    });
    secs.forEach((sc, si) => {
      const x0 = LAB + si * SEC_W;
      text(ctx, sc.sec.label + " " + fmtTime(sc.sec.t0), x0 + 2, 12, { size: 9, color: TOK.muted });
      const cellW = (SEC_W - 10) / 16;
      for (let st = 0; st < 16; st++) {
        if (st % 4 === 0) {
          ctx.fillStyle = "rgba(139,148,158,0.14)";
          ctx.fillRect(x0 + st * cellW, HDR - 3, 1, active.length * ROW_H + 4);
        }
      }
      active.forEach((f, ri) => {
        const r = rows[f];
        const occ = sc.occ[f];
        for (let st = 0; st < 16; st++) {
          const v = occ ? clamp(occ[st] / sc.bars, 0, 1) : 0;
          ctx.fillStyle = v > 0.04 ? famColor(f, r.idx, r.nfam, 0.15 + 0.85 * v)
            : "rgba(139,148,158,0.06)";
          ctx.fillRect(x0 + st * cellW + 0.5, HDR + ri * ROW_H + 1, cellW - 1.5, ROW_H - 2.5);
        }
      });
    });
  });
  wrap.addEventListener("pointerdown", ev => {
    if (ev.button !== 0) return;
    const sx = ev.clientX, sy = ev.clientY, st = performance.now();
    const go = e2 => {
      wrap.removeEventListener("pointerup", go);
      if (Math.abs(e2.clientX - sx) > 12 || Math.abs(e2.clientY - sy) > 12
          || performance.now() - st > 500) return;
      const r = holder.getBoundingClientRect();
      const px = e2.clientX - r.left - LAB;
      if (px < 0) return;
      const si = Math.floor(px / SEC_W);
      if (secs[si]) { seek(secs[si].sec.t0); if (!state.playing) setPlaying(true); }
    };
    wrap.addEventListener("pointerup", go);
  });
  subs.push(t => {
    let si = -1;
    for (let i = 0; i < secs.length; i++) if (t >= secs[i].sec.t0 && t < secs[i].sec.t1) { si = i; break; }
    if (si < 0 || !state.playing) { cur.style.opacity = "0"; return; }
    const bi = beatIndexAt(t);
    const span = (bt[bi + 1] || bt[bi] + 0.42) - bt[bi];
    const six = clamp(Math.floor((t - bt[bi]) / span * 4), 0, 3);
    const step = (((bi - off) % 4 + 4) % 4) * 4 + six;
    const cellW = (SEC_W - 10) / 16;
    cur.style.opacity = "1";
    cur.style.left = (LAB + si * SEC_W + step * cellW) + "px";
    cur.style.width = cellW + "px";
    cur.style.top = (HDR - 3) + "px";
    cur.style.height = (active.length * ROW_H + 4) + "px";
  });
  p.appendChild(el("p", "caption", "cell brightness is how often that device hits that 16th across the section's bars · click a block to hear its section"));
}

function buildMicrotiming(b) {
  if (!GRAMMAR || !D.beats || D.beats.times.length < 16) return;
  const bt = D.beats.times;
  const devs = [];
  for (const tok of GRAMMAR.tokens) {
    if (!tok.family) continue;
    const bi = beatIndexAt(tok.t0);
    const span = (bt[bi + 1] || bt[bi] + 0.42) - bt[bi];
    const pos = (tok.t0 - bt[bi]) / span * 4;
    const near = Math.round(pos);
    const dev = (pos - near) * span / 4 * 1000;
    if (Math.abs(dev) <= 60) {
      if (!devs[bi]) devs[bi] = [];
      devs[bi].push(dev);
    }
  }
  const c = canvasBlock(b, 110, {
    label: "microtiming · median push (early) and drag (late) per beat, ms",
    legend: [["early", "#38bdf8"], ["late", "#fb7185"]],
  });
  renders.push(() => {
    const { ctx, w, h } = prepCanvas(c, 110);
    const mid = h / 2;
    hline(ctx, mid, w, TOK.grid);
    text(ctx, "+20", 4, 14, { size: 9 });
    text(ctx, "-20", 4, h - 6, { size: 9 });
    for (let k = 0; k < bt.length; k++) {
      const arr = devs[k];
      if (!arr || !arr.length) continue;
      arr.sort((a, b2) => a - b2);
      const med = arr[arr.length >> 1];
      const x0 = bt[k] / state.duration * w;
      const hgt = clamp(Math.abs(med) / 20, 0, 1) * (mid - 10);
      ctx.fillStyle = med < 0 ? "rgba(56,189,248,0.8)" : "rgba(251,113,133,0.8)";
      if (med < 0) ctx.fillRect(x0, mid - hgt, 1.4, hgt);
      else ctx.fillRect(x0, mid, 1.4, hgt);
    }
  });
}

function buildRhythm() {
  fitToggle($("ch5"));
  const b = $("b5");
  const tmeta = D.images && D.images.tempogram;
  rasterBlock(b, "tempogram", "tempogram" + (tmeta ? " · " + yDesc(tmeta) : "") +
    " · global " + (Math.round((D.beats.bpm || 0) * 10) / 10) + " bpm");

  buildSequencer(b);
  buildMicrotiming(b);
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

  const spans = sectionSpans();
  const p = panel(b, "sections · " + spans.length + " blocks from the device stream, letters name repeated material");
  const ribbon = el("div", "ribbon");
  p.appendChild(ribbon);
  registerTA(ribbon);
  const blocks = [];
  for (const s of spans) {
    const sb = el("div", "segblock");
    sb.style.setProperty("--c", CAT[letterIdx(s.label) % 8]);
    sb.style.left = (s.t0 / state.duration * 100) + "%";
    sb.style.width = (Math.max(0, s.t1 - s.t0) / state.duration * 100) + "%";
    sb.title = s.label + " · " + fmtTime(s.t0) + "-" + fmtTime(s.t1);
    sb.innerHTML = '<span class="kl">' + esc(s.label) + "</span>";
    ribbon.appendChild(sb);
    blocks.push({ el: sb, s });
  }
  let liveSeg = -1;
  subs.push(t => {
    let idx = -1;
    for (let i = 0; i < blocks.length; i++) {
      if (t >= blocks[i].s.t0 && t < blocks[i].s.t1) { idx = i; break; }
    }
    if (idx !== liveSeg) {
      if (liveSeg >= 0) blocks[liveSeg].el.classList.remove("on");
      if (idx >= 0) blocks[idx].el.classList.add("on");
      liveSeg = idx;
    }
  });

  const nv = D.novelty;
  const arr = GRAMMAR && GRAMMAR.arrangement && GRAMMAR.arrangement.curve && GRAMMAR.arrangement.curve.length ? GRAMMAR.arrangement : null;
  const c1 = canvasBlock(b, 140, {
    label: "novelty · timbre-harmony novelty filled, device-stream change on top, rules at section starts",
    legend: [["timbre novelty", "rgba(139,148,158,.6)"], ["arrangement change", TOK.accent]],
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
    if (arr) {
      const m = arr.curve.length;
      const [, amx] = finiteExtent(arr.curve);
      path(ctx, m, i => i / (m - 1) * w, i => h - 5 - clamp((arr.curve[i] || 0) / (amx || 1), 0, 1) * (h - 10));
      strokePath(ctx, TOK.accent, 1.6);
    }
    for (const sec of sectionSpans().slice(1)) {
      vline(ctx, sec.t0 / state.duration * w, h, "rgba(192,132,252,0.55)", [3, 3]);
    }
  });

  const mo = D.motifs && D.motifs.pairs || [];
  const c2 = canvasBlock(b, 220, {
    label: "repeated phrases · arcs join recurrences of the same device pattern",
    legend: [["compound phrase", "rgba(230,237,243,.5)"], ["section repeat", TOK.accent]],
  });
  renders.push(() => {
    const { ctx, w, h } = prepCanvas(c2, 220);
    const baseY = h - 14;
    hline(ctx, baseY + 7, w, TOK.grid);
    const x = t => t / state.duration * w;
    if (GRAMMAR && GRAMMAR.compounds && GRAMMAR.compounds.length) {
      for (const comp of GRAMMAR.compounds.slice(0, 12)) {
        const tally = {};
        for (const fid of comp.pattern) tally[fid[0]] = (tally[fid[0]] || 0) + 1;
        let sid = comp.pattern[0][0];
        for (const k2 in tally) if (tally[k2] > tally[sid]) sid = k2;
        const rgb = hexRgb(STREAM_HUES[sid] || "#8b949e");
        ctx.strokeStyle = "rgba(" + rgb[0] + "," + rgb[1] + "," + rgb[2] + ",0.32)";
        ctx.lineWidth = 1 + 0.4 * comp.pattern.length;
        for (let i = 0; i + 1 < comp.at.length; i++) {
          const xa = x(comp.at[i]), xb = x(comp.at[i + 1]);
          const lift = clamp(20 + Math.abs(xb - xa) * 0.5, 20, (baseY - 12) * 2);
          ctx.beginPath();
          ctx.moveTo(xa, baseY);
          ctx.quadraticCurveTo((xa + xb) / 2, baseY - lift, xb, baseY);
          ctx.stroke();
        }
      }
      const seen = {};
      ctx.strokeStyle = "rgba(192,132,252,0.5)";
      ctx.lineWidth = 2.5;
      for (const sec of sectionSpans()) {
        const mid = (sec.t0 + sec.t1) / 2;
        if (seen[sec.label] != null) {
          const xa = x(seen[sec.label]), xb = x(mid);
          const lift = clamp(30 + Math.abs(xb - xa) * 0.55, 30, (baseY - 12) * 2);
          ctx.beginPath();
          ctx.moveTo(xa, baseY);
          ctx.quadraticCurveTo((xa + xb) / 2, baseY - lift, xb, baseY);
          ctx.stroke();
        }
        seen[sec.label] = mid;
      }
      for (const sec of sectionSpans()) {
        ctx.fillStyle = "rgba(230,237,243,0.5)";
        ctx.fillRect(x(sec.t0), baseY + 2, 1.5, 5);
      }
      return;
    }
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

  buildLiveGonio(b);
}

function buildLiveGonio(b) {
  const st = D.stereo;
  const frames = st.lissajous || [];
  const p = panel(b, "goniometer · live while playing, nearest sampled instant when paused");
  const c = el("canvas", "gonio-live");
  p.appendChild(c);
  const ga = { tried: false, ready: false, side: 0, lastFrame: -2 };
  function size() {
    const side = Math.min(c.clientWidth || 420, 460);
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    c.width = Math.round(side * dpr);
    c.height = Math.round(side * dpr);
    const ctx = c.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ga.side = side;
    return ctx;
  }
  function cross(ctx, s) {
    ctx.strokeStyle = TOK.grid;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(8, s - 8);
    ctx.lineTo(s - 8, 8);
    ctx.moveTo(8, 8);
    ctx.lineTo(s - 8, s - 8);
    ctx.stroke();
    text(ctx, "L", 10, 18, { size: 9, color: TOK.muted });
    text(ctx, "R", s - 16, 18, { size: 9, color: TOK.muted });
  }
  function drawStatic(fi) {
    const ctx = size();
    const s = ga.side;
    ctx.clearRect(0, 0, s, s);
    cross(ctx, s);
    const fr = frames[fi];
    if (!fr) return;
    ctx.fillStyle = "rgba(230,237,243,0.55)";
    for (let i = 0; i < fr.x.length; i++) {
      const px = s / 2 + clamp(fr.x[i], -1, 1) * (s / 2 - 10);
      const py = s / 2 - clamp(fr.y[i], -1, 1) * (s / 2 - 10);
      ctx.fillRect(px, py, 1.4, 1.4);
    }
    text(ctx, fmtTime(fr.t), s / 2, s - 6, { align: "center", size: 9, color: TOK.muted });
  }
  renders.push(() => { ga.lastFrame = -2; ga.sized = false; });
  subs.push(t => {
    if (state.playing && state.useAudio && !RM) {
      if (!ga.tried) {
        ga.tried = true;
        try {
          const AC = window.AudioContext || window.webkitAudioContext;
          const actx = new AC();
          const src = actx.createMediaElementSource(audioEl);
          const split = actx.createChannelSplitter(2);
          const anL = actx.createAnalyser();
          const anR = actx.createAnalyser();
          anL.fftSize = 2048;
          anR.fftSize = 2048;
          src.connect(split);
          split.connect(anL, 0);
          split.connect(anR, 1);
          src.connect(actx.destination);
          ga.actx = actx;
          ga.anL = anL;
          ga.anR = anR;
          ga.bufL = new Float32Array(anL.fftSize);
          ga.bufR = new Float32Array(anR.fftSize);
          ga.ready = true;
        } catch (e) {}
      }
      if (ga.actx && ga.actx.state === "suspended") ga.actx.resume();
      if (ga.ready) {
        let ctx;
        if (!ga.sized) { ctx = size(); ga.sized = true; ctx.clearRect(0, 0, ga.side, ga.side); }
        else ctx = c.getContext("2d");
        const s = ga.side;
        ctx.globalCompositeOperation = "destination-out";
        ctx.fillStyle = "rgba(0,0,0,0.14)";
        ctx.fillRect(0, 0, s, s);
        ctx.globalCompositeOperation = "source-over";
        cross(ctx, s);
        ga.anL.getFloatTimeDomainData(ga.bufL);
        ga.anR.getFloatTimeDomainData(ga.bufR);
        ctx.fillStyle = "rgba(230,237,243,0.6)";
        for (let i = 0; i < ga.bufL.length; i += 2) {
          const px = s / 2 + clamp(ga.bufL[i], -1, 1) * (s / 2 - 10);
          const py = s / 2 - clamp(ga.bufR[i], -1, 1) * (s / 2 - 10);
          ctx.fillRect(px, py, 1.4, 1.4);
        }
        ga.lastFrame = -2;
        return;
      }
    }
    if (!frames.length) return;
    let best = 0, bd = Infinity;
    for (let i = 0; i < frames.length; i++) {
      const d = Math.abs(frames[i].t - t);
      if (d < bd) { bd = d; best = i; }
    }
    if (best !== ga.lastFrame) {
      ga.lastFrame = best;
      ga.sized = false;
      drawStatic(best);
    }
  });
}

function buildNicheMap(b) {
  const toks = GRAMMAR.tokens;
  const { rows } = laneLayout();
  const fLo = 30, fHi = 11025;
  const c = canvasBlock(b, 260, {
    label: "niche map · who owns which band, when",
    legend: GRAMMAR.streams.map(s => [s.id + " · " + s.name, STREAM_HUES[s.id]]),
  });
  c.classList.add("wide-min");
  renders.push(() => {
    const { ctx, w, h } = prepCanvas(c, 260);
    const y = f => h - 12 - Math.log(clamp(f, fLo, fHi) / fLo) / Math.log(fHi / fLo) * (h - 20);
    for (const g of [100, 1000, 10000]) {
      hline(ctx, y(g), w, "rgba(139,148,158,0.2)");
      text(ctx, fmtHz(g), 4, y(g) - 3, { size: 9, color: TOK.muted });
    }
    const x = t => t / state.duration * w;
    for (const tok of toks) {
      if (!tok.family) continue;
      const r = rows[tok.family];
      if (!r) continue;
      const f = tok.centroid_hz || r.dev.register_hz.med;
      const alpha = 0.18 + 0.62 * clamp((tok.peak_db + 45) / 45, 0.05, 1);
      ctx.fillStyle = famColor(tok.family, r.idx, r.nfam, alpha);
      ctx.fillRect(x(tok.t0), y(f) - 1.5, Math.max(x(tok.t1) - x(tok.t0), 1.2), 3);
    }
  });
}

function buildInteractionMatrix(b) {
  const toks = GRAMMAR.tokens.filter(t => t.family);
  const ids = GRAMMAR.devices.map(d => d.id);
  const idx = {};
  ids.forEach((f, i) => { idx[f] = i; });
  const n = ids.length;
  const counts = new Float64Array(n * n);
  const firsts = {};
  for (let i = 0; i < toks.length; i++) {
    const aT = toks[i];
    for (let j = i + 1; j < toks.length; j++) {
      const lag = toks[j].t0 - aT.t0;
      if (lag > 0.25) break;
      if (lag < 0.03) continue;
      const bF = toks[j].family;
      if (bF === aT.family) continue;
      const key = idx[aT.family] * n + idx[bF];
      counts[key]++;
      if (!firsts[key]) firsts[key] = [];
      if (firsts[key].length < 3) firsts[key].push(aT.t0);
    }
  }
  const pairs = [];
  let mxNet = 0;
  for (let a = 0; a < n; a++) {
    for (let b2 = a + 1; b2 < n; b2++) {
      const ab = counts[a * n + b2], ba = counts[b2 * n + a];
      const tot = ab + ba;
      if (tot < 30) continue;
      const net = Math.abs(ab - ba);
      if (net > mxNet) mxNet = net;
      const li = ab >= ba ? a : b2;
      const fi = ab >= ba ? b2 : a;
      pairs.push({ lead: li, follow: fi, tot, asym: Math.max(ab, ba) / tot,
        key: li * n + fi });
    }
  }
  if (!pairs.length) return;
  const { rows } = laneLayout();
  const p = panel(b, "interplay · blue: row leads column within a 16th, red: column leads, faint: balanced");
  const CELL = 16, LB = 34;
  const side = LB + n * CELL + 4;
  const c = el("canvas", "matrix-canvas");
  c.style.width = side + "px";
  c.style.height = side + "px";
  const mwrap = el("div", "matrix-wrap");
  mwrap.appendChild(c);
  p.appendChild(mwrap);
  renders.push(() => {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    c.width = Math.round(side * dpr);
    c.height = Math.round(side * dpr);
    const ctx = c.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ids.forEach((f, i) => {
      const r = rows[f];
      ctx.fillStyle = famColor(f, r.idx, r.nfam, 1);
      ctx.font = "8px " + MONO;
      ctx.fillText(f, 2, LB + i * CELL + CELL - 4);
      ctx.save();
      ctx.translate(LB + i * CELL + CELL - 4, LB - 4);
      ctx.rotate(-Math.PI / 2);
      ctx.fillText(f, 0, 0);
      ctx.restore();
    });
    for (let a = 0; a < n; a++) {
      for (let b2 = 0; b2 < n; b2++) {
        if (a === b2) continue;
        const ab = counts[a * n + b2], ba = counts[b2 * n + a];
        const net = ab - ba;
        const mag = clamp(Math.abs(net) / (mxNet || 1), 0, 1);
        ctx.fillStyle = (ab + ba) < 30 ? "rgba(139,148,158,0.05)"
          : net >= 0 ? "rgba(56,189,248," + (0.08 + 0.8 * mag).toFixed(3) + ")"
          : "rgba(251,113,133," + (0.08 + 0.8 * mag).toFixed(3) + ")";
        ctx.fillRect(LB + b2 * CELL, LB + a * CELL, CELL - 1, CELL - 1);
      }
    }
  });
  const addRow = (list, pr, arrow, extra) => {
    const item = el("span", "gitem");
    item.appendChild(el("b", "gtok", esc(ids[pr.lead]) + " " + arrow + " " + esc(ids[pr.follow])));
    item.appendChild(el("span", "garrow", "×" + pr.tot));
    item.appendChild(el("span", "gtok dim", extra));
    for (const t of (firsts[pr.key] || []).slice(0, 2)) {
      const btn = el("button", "gseek", fmtTime(t));
      btn.addEventListener("click", () => { seek(t); if (!state.playing) setPlaying(true); });
      item.appendChild(btn);
    }
    list.appendChild(item);
  };
  const directed = pairs.filter(pr => pr.asym >= 0.62)
    .sort((x, y) => (2 * y.asym - 1) * y.tot - (2 * x.asym - 1) * x.tot);
  if (directed.length) {
    const lp = panel(b, "who leads · consistently first, not just co-present");
    const list = el("div", "glist");
    lp.appendChild(list);
    for (const pr of directed.slice(0, 8)) {
      addRow(list, pr, "→", "leads " + Math.round(pr.asym * 100) + "%");
    }
  }
  const locked = pairs.filter(pr => pr.asym < 0.62).sort((x, y) => y.tot - x.tot);
  if (locked.length) {
    const lp = panel(b, "tightest interlocks · the grid's couples, no leader");
    const list = el("div", "glist");
    lp.appendChild(list);
    for (const pr of locked.slice(0, 6)) {
      addRow(list, pr, "↔", Math.round(pr.asym * 100) + "/" + Math.round(100 - pr.asym * 100));
    }
  }
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

function opColor(name) {
  const MAP = {
    repeat: CAT[6],
    transpose: CAT[0],
    dilate: CAT[1],
    echo: CAT[7],
    fragment: CAT[4],
    ornament: CAT[5],
    accel_run: CAT[3],
    climb: CAT[1],
    rupture: CAT[2],
  };
  return MAP[name] || TOK.muted;
}

function grammarBars(parent, label, rows, legend, caption) {
  const p = panel(parent, label);
  if (legend) p.appendChild(legendRow(legend));
  const g = el("div", "gbars");
  const labCol = el("div", "glabel-col");
  const tracks = el("div", "gtracks");
  g.appendChild(labCol);
  g.appendChild(tracks);
  p.appendChild(g);
  registerTA(tracks);
  const lanes = [];
  for (const row of rows) {
    labCol.appendChild(el("span", "glabel", esc(row.label)));
    const spans = el("div", "gspans");
    spans.style.setProperty("--c", row.color);
    for (const s of row.spans) {
      const b = el("span", "gspan");
      b.style.left = (s.t0 / state.duration * 100) + "%";
      const w = (s.t1 - s.t0) / state.duration * 100;
      b.style.width = Math.max(0.1, w) + "%";
      if (s.t1 - s.t0 < 1.5) b.classList.add("pt");
      b.title = s.title;
      spans.appendChild(b);
    }
    tracks.appendChild(spans);
    lanes.push(spans);
  }
  if (caption) p.appendChild(el("p", "caption", caption));
  subs.push(t => {
    for (let i = 0; i < rows.length; i++) {
      lanes[i].classList.toggle("live", rows[i].spans.some(s => t >= s.t0 && t < s.t1));
    }
  });
  return p;
}

function parseMoment(str) {
  const m = String(str).match(/(\d+):(\d+)/);
  return m ? parseInt(m[1], 10) * 60 + parseInt(m[2], 10) : null;
}

const STREAM_HUES = { K: "#fb7185", S: "#fbbf24", H: "#a3e635", B: "#38bdf8", L: "#34d399", P: "#c084fc" };
const STREAM_ORDER = ["P", "H", "L", "S", "K", "B"];
const loopState = { on: false, t0: 0, t1: 0 };

function hexRgb(hex) {
  return [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16));
}

function famColor(fid, idx, nfam, alpha) {
  const [r, g, b] = hexRgb(STREAM_HUES[fid[0]]);
  const f = 1 - 0.45 * (idx / Math.max(nfam - 1, 1));
  return "rgba(" + Math.round(r * f) + "," + Math.round(g * f) + "," +
    Math.round(b * f) + "," + alpha.toFixed(3) + ")";
}

function laneLayout() {
  const byStream = {};
  for (const d of GRAMMAR.devices) {
    (byStream[d.id[0]] = byStream[d.id[0]] || []).push(d);
  }
  const rows = {};
  let y = 0;
  for (const sid of STREAM_ORDER) {
    const fams = byStream[sid] || [];
    fams.forEach((d, i) => {
      rows[d.id] = { y: y++, idx: i, nfam: fams.length, dev: d };
    });
    if (fams.length) y += 0.6;
  }
  return { rows, height: y };
}

function drawLanes(c, hCss, t0, t1, opts) {
  const { rows, height } = laneLayout();
  const rowH = (hCss - 14) / height;
  const beats = (D.beats && D.beats.times) || [];
  renders.push(() => {
    const { ctx, w } = prepCanvas(c, hCss);
    const x = t => (t - t0) / (t1 - t0) * w;
    const secW = w / (t1 - t0);
    if (secW > 12) {
      for (let i = 0; i < beats.length; i++) {
        const bt = beats[i];
        if (bt < t0 || bt > t1) continue;
        ctx.fillStyle = i % 4 === 0 ? "rgba(139,148,158,0.18)" : "rgba(139,148,158,0.07)";
        ctx.fillRect(x(bt), 0, 1, hCss);
      }
    }
    for (const tok of GRAMMAR.tokens) {
      if (!tok.family || tok.t1 < t0 || tok.t0 > t1) continue;
      const r = rows[tok.family];
      if (!r) continue;
      const pb = r.dev.pitch_bin;
      const rng = Math.max(pb.max - pb.min, 1);
      const off = "BLP".includes(tok.family[0])
        ? ((tok.pitch_bin - pb.min) / rng - 0.5) * 0.5 * rowH
        : 0;
      const alpha = 0.25 + 0.75 * clamp((tok.peak_db + 45) / 45, 0.05, 1);
      ctx.fillStyle = famColor(tok.family, r.idx, r.nfam, alpha);
      const px0 = x(tok.t0);
      const pw = Math.max(x(tok.t1) - px0, 1.5);
      ctx.fillRect(px0, 6 + r.y * rowH - off, pw, Math.max(rowH * 0.8, 2));
    }
    if (!opts || opts.labels !== false) {
      ctx.save();
      ctx.shadowColor = "rgba(0,0,0,0.9)";
      ctx.shadowBlur = 3;
      for (const fid in rows) {
        const r = rows[fid];
        text(ctx, fid + " (" + r.dev.n + ")", 4, 6 + r.y * rowH + rowH * 0.65,
          { size: 9, color: STREAM_HUES[fid[0]] });
      }
      ctx.restore();
    }
  });
}

function buildDeviceLanes(b) {
  const g = GRAMMAR;
  const legend = g.streams.map(s => [s.id + " · " + s.name, STREAM_HUES[s.id]]);
  const { height } = laneLayout();
  const hCss = Math.max(180, Math.round(height * 13) + 14);
  const c1 = canvasBlock(b, hCss,
    { label: "device lanes · " + g.n_families + " families over " +
      g.n_gestures + " sound events", legend });
  drawLanes(c1, hCss, 0, state.duration);
  c1.parentElement.parentElement.parentElement.appendChild(
    el("p", "caption", "every mark is one gesture in one source lane · " +
      "vertical offset inside harmonic lanes is pitch · opacity is loudness · " +
      "0:00 — " + fmtTime(state.duration)));

  const p = panel(b, "device lanes · detail (scroll, click to hear)");
  const loopBtn = el("button", "fit-toggle mono", "loop: off");
  loopBtn.addEventListener("click", () => {
    loopState.on = !loopState.on;
    if (!loopState.on) loopState.t1 = 0;
    loopBtn.textContent = loopState.on ? "loop: 8 beats" : "loop: off";
    loopBtn.classList.toggle("active", loopState.on);
  });
  p.querySelector(".plabel").appendChild(loopBtn);
  const inner = taBlock(p, {});
  const c2 = el("canvas");
  const pxPerS = 24;
  const wide = Math.min(Math.round(state.duration * pxPerS), 16000);
  c2.style.width = wide + "px";
  c2.style.height = hCss + "px";
  inner.style.width = wide + "px";
  inner.appendChild(c2);
  const loopMark = el("div", "loopmark");
  inner.appendChild(loopMark);
  const labWrap = el("div", "lane-labels");
  const ll = laneLayout();
  const rowH2 = (hCss - 14) / ll.height;
  for (const fid in ll.rows) {
    const sp = el("span", null, esc(fid));
    sp.style.top = (6 + ll.rows[fid].y * rowH2) + "px";
    sp.style.color = STREAM_HUES[fid[0]];
    labWrap.appendChild(sp);
  }
  inner.insertBefore(labWrap, c2);
  drawLanes(c2, hCss, 0, state.duration, { labels: false });
  const beatDur = D.beats && D.beats.bpm ? 60 / D.beats.bpm : 0.42;
  inner.addEventListener("pointerdown", ev => {
    if (!loopState.on || ev.button !== 0) return;
    const r = inner.getBoundingClientRect();
    const f = clamp((ev.clientX - r.left) / r.width, 0, 1);
    loopState.t0 = f * state.duration;
    loopState.t1 = loopState.t0 + 8 * beatDur;
    loopMark.style.left = (f * 100) + "%";
    loopMark.style.width = (8 * beatDur / state.duration * 100) + "%";
    loopMark.style.opacity = "1";
  });
  subs.push(t => {
    if (loopState.on && loopState.t1 && t > loopState.t1) seek(loopState.t0);
    if (!loopState.on) loopMark.style.opacity = "0";
  });
  p.appendChild(el("p", "caption",
    "24 px/s · beat grid behind the marks · toggle loop, then click a spot to cycle 8 beats"));
}

function buildDeviceCards(b) {
  const llmArt = {};
  for (const a of (LLM && LLM.artifacts) || []) llmArt[a.id] = a;
  const clapDev = (CLAPW && CLAPW.devices) || {};
  const cp = panel(b, "device inventory · what each family is");
  const cards = el("div", "gcards");
  cp.appendChild(cards);
  const { rows } = laneLayout();
  for (const d of GRAMMAR.devices) {
    const r = rows[d.id];
    const l = llmArt[d.id];
    const card = el("div", "gcard");
    card.style.setProperty("--c", famColor(d.id, r.idx, r.nfam, 1));
    const head = el("div", "ghead");
    head.appendChild(el("span", "galias", esc(l && l.alias ? l.alias : d.stream + " device")));
    head.appendChild(el("span", "gid mono", esc(d.id)));
    card.appendChild(head);
    if (l && l.description) card.appendChild(el("p", "gdesc", esc(l.description)));
    const props = el("div", "gprops");
    props.appendChild(el("span", "gprop", "<i>events</i> " + d.n));
    props.appendChild(el("span", "gprop", "<i>dur</i> " + d.dur_s.min.toFixed(2) + "-" + d.dur_s.max.toFixed(2) + "s"));
    props.appendChild(el("span", "gprop", "<i>register</i> " + fmtHz(d.register_hz.min) + "-" + fmtHz(d.register_hz.max)));
    props.appendChild(el("span", "gprop", "<i>peak</i> " + d.peak_db.med.toFixed(0) + " dB"));
    card.appendChild(props);
    const clap = clapDev[d.id];
    if (clap && clap.top && clap.top.length) {
      card.appendChild(el("p", "gkeep", "<i>machine hears</i> " +
        clap.top.slice(0, 3).map(x => esc(x[0])).join(" · ")));
    }
    if (l && l.invariant) card.appendChild(el("p", "gkeep", "<i>invariant</i> " + esc(l.invariant)));
    if (l && l.variable) card.appendChild(el("p", "gkeep", "<i>variable</i> " + esc(l.variable)));
    const exes = el("div", "gprops");
    d.exemplars.forEach((ex, i) => {
      const btn = el("button", "gseek", "hear " + (i + 1) + " · " + fmtTime(ex.t0));
      btn.addEventListener("click", () => {
        if (loopState.on) {
          loopState.t0 = Math.max(ex.t0 - 0.1, 0);
          loopState.t1 = ex.t1 + 1.5;
        }
        seek(Math.max(ex.t0 - 0.1, 0));
        if (!state.playing) setPlaying(true);
      });
      exes.appendChild(btn);
    });
    card.appendChild(exes);
    cards.appendChild(card);
  }
}

function buildOperatorLanes(b) {
  const ops = GRAMMAR.operators || {};
  const names = Object.keys(ops).filter(n => ops[n].count > 0);
  if (!names.length) return;
  const total = names.reduce((s, n) => s + ops[n].count, 0);
  const rows = names.map(n => ({
    label: n + " ×" + ops[n].count,
    color: opColor(n),
    spans: ops[n].instances.map(o => ({
      t0: o.t0,
      t1: Math.max(o.t1 != null ? o.t1 : o.t0, o.t0 + 0.1),
      title: n + " · " + fmtTime(o.t0) +
        (o.family ? " · " + o.family : "") +
        (o.semitones != null ? " · " + (o.semitones > 0 ? "+" : "") + o.semitones + " st" : "") +
        (o.ratio != null ? " · ×" + o.ratio : "") +
        (o.n != null ? " · n=" + o.n : "") +
        (o.drop_db != null ? " · -" + o.drop_db + " dB" : ""),
    })),
  }));
  grammarBars(b, "transformations · " + total + " operator instances (sampled lanes)", rows,
    names.map(n => [n, opColor(n)]),
    "each lane shows up to 40 sampled instances · 0:00 — " + fmtTime(state.duration));

  if (LLM && LLM.operators && LLM.operators.length) {
    const cp = panel(b, "operator effects · input → output");
    const cards = el("div", "gcards");
    cp.appendChild(cards);
    for (const o of LLM.operators) {
      const card = el("div", "gcard");
      card.style.setProperty("--c", opColor(o.name));
      const head = el("div", "ghead");
      head.appendChild(el("span", "galias", esc(o.name)));
      head.appendChild(el("span", "gid mono", o.preserves_identity ? "preserves identity" : "changes identity"));
      card.appendChild(head);
      card.appendChild(el("p", "gdesc", esc(o.input) + " → " + esc(o.output)));
      if (o.effect) card.appendChild(el("p", "gkeep", "<i>effect</i> " + esc(o.effect)));
      cards.appendChild(card);
    }
  }
}

function buildCompounds(b) {
  const comps = GRAMMAR.compounds || [];
  if (!comps.length) return;
  const p = panel(b, "compounds · recurring multi-device phrases");
  const list = el("div", "glist");
  p.appendChild(list);
  for (const c of comps.slice(0, 16)) {
    const item = el("span", "gitem");
    item.appendChild(el("b", "gtok", esc(c.pattern.join(" → "))));
    item.appendChild(el("span", "garrow", "×" + c.count));
    c.at.slice(0, 4).forEach(t => {
      const btn = el("button", "gseek", fmtTime(t));
      btn.addEventListener("click", () => { seek(t); if (!state.playing) setPlaying(true); });
      item.appendChild(btn);
    });
    list.appendChild(item);
  }
}

function buildPairs(b) {
  const ss = GRAMMAR.self_similarity || [];
  if (!ss.length) return;
  const p = panel(b, "long-range self-similarity · the same gesture, far apart");
  const list = el("div", "glist");
  p.appendChild(list);
  for (const t of ss.slice(0, 18)) {
    const item = el("span", "gitem");
    const a = el("button", "gseek", fmtTime(t.a_t0));
    a.addEventListener("click", () => { seek(t.a_t0); if (!state.playing) setPlaying(true); });
    const d = el("button", "gseek", fmtTime(t.b_t0));
    d.addEventListener("click", () => { seek(t.b_t0); if (!state.playing) setPlaying(true); });
    item.appendChild(a);
    item.appendChild(el("span", "garrow", "→"));
    item.appendChild(el("span", "gtok dim",
      esc(t.kind + (t.kind === "transpose" ? " " + (t.semitones > 0 ? "+" : "") + t.semitones + " st"
        : (t.kind === "dilate" ? " ×" + t.dur_ratio : "")))));
    item.appendChild(el("span", "garrow", "→"));
    item.appendChild(d);
    item.appendChild(el("b", "gtok", esc(t.family_a)));
    list.appendChild(item);
  }
}

function buildGrammarText(b) {
  const g = LLM.grammar;
  const p = panel(b, "generative grammar · bnf");
  if (g.start) {
    p.appendChild(el("p", "gkeep", "<i>start</i> <span class=\"gtok\">" + esc(g.start) + "</span>"));
  }
  const pre = el("pre", "bnf");
  pre.textContent = g.rules.join("\n");
  p.appendChild(pre);
}

function buildDerivations(b) {
  const p = panel(b, "derivations · click a moment to hear it");
  const steps = el("div", "gsteps");
  p.appendChild(steps);
  for (const d of LLM.derivations) {
    const card = el("div", "gstep");
    const sec = parseMoment(d.moment);
    const tag = sec != null
      ? el("button", "gseek", esc(d.moment))
      : el("span", "gseek", esc(d.moment));
    if (sec != null) tag.addEventListener("click", () => seek(sec));
    card.appendChild(tag);
    const ol = el("ol", "gsteplist");
    for (const s of d.steps) ol.appendChild(el("li", null, esc(s)));
    card.appendChild(ol);
    steps.appendChild(card);
  }
}

function buildGrammar() {
  const b = $("b11");

  if (LLM && LLM.hypothesis) {
    const p = panel(b, "executive hypothesis · the latent generative device");
    p.appendChild(el("p", "gprose", esc(LLM.hypothesis)));
    if (LLM.identity_invariants) {
      p.appendChild(el("p", "gkeep", "<i>identity invariants</i> " + esc(LLM.identity_invariants)));
    }
  }

  buildDeviceLanes(b);
  buildNicheMap(b);
  buildDeviceCards(b);
  buildInteractionMatrix(b);
  buildOperatorLanes(b);
  buildCompounds(b);
  buildPairs(b);
  if (LLM && LLM.grammar && LLM.grammar.rules && LLM.grammar.rules.length) buildGrammarText(b);
  if (LLM && LLM.derivations && LLM.derivations.length) buildDerivations(b);
}

async function boot() {
  const failed = [];
  let data, mf, emo, grammar, llm, clapw;
  try {
    [mf, data, emo, grammar, llm, clapw] = await Promise.all([
      fetch("tracks/manifest.json").then(r => r.ok ? r.json() : null).catch(() => null),
      fetch(base + "data.json").then(r => {
        if (!r.ok) throw new Error(String(r.status));
        return r.json();
      }),
      fetch(base + "emotion.json").then(r => r.ok ? r.json() : null).catch(() => null),
      fetch(base + "grammar.json").then(r => r.ok ? r.json() : null).catch(() => null),
      fetch(base + "grammar_llm.json").then(r => r.ok ? r.json() : null).catch(() => null),
      fetch(base + "grammar_clap.json").then(r => r.ok ? r.json() : null).catch(() => null),
    ]);
  } catch (e) {
    $("status").textContent = "this track could not be read";
    return;
  }
  D = data;
  EMO = emo && emo.times && emo.times.length ? emo : null;
  GRAMMAR = grammar && grammar.schema === 2 && grammar.devices?.length ? grammar : null;
  CLAPW = clapw && clapw.devices ? clapw : null;
  LLM = llm && (llm.hypothesis || llm.artifacts?.length || llm.grammar?.rules?.length) ? llm : null;
  META = ((mf && mf.tracks) || []).find(t => t.slug === slug) || fallbackMeta();
  state.duration = D.duration || META.duration || 1;

  $("status").remove();
  $("essay").hidden = false;

  const chapters = [
    ["hero", buildHero],
    ["pump", buildPump],
    ["spectrum", buildSpectrum],
    ["harmony", buildHarmony],
    ["rhythm", buildRhythm],
    ["texture", buildTexture],
    ["structure", buildStructure],
    ["stereo", buildStereo],
    ["feeling", () => { if (EMO) buildFeeling(); else $("ch9").remove(); }],
    ["chaos", buildChaos],
    ["grammar", () => { if (GRAMMAR) buildGrammar(); else $("ch11").remove(); }],
    ["toc", buildToc],
  ];
  for (const [name, fn] of chapters) {
    try {
      fn();
    } catch (e) {
      console.error("[chapter " + name + "]", e);
      failed.push(name);
    }
  }

  probeAudio().then(setupAudio).catch(() => setupAudio(false));

  for (const r of renders) {
    try {
      r();
    } catch (e) {
      console.error("[render]", e);
    }
  }
  if (failed.length && params.get("debug")) {
    const n = el("p", "banner", "chapters failed: " + esc(failed.join(", ")));
    document.querySelector(".masthead").appendChild(n);
  }
  addEventListener("resize", debounce(() => {
    for (const r of renders) {
      try {
        r();
      } catch (e) {
        console.error("[render]", e);
      }
    }
    tick(true);
  }, 160));

  tick(true);
  requestAnimationFrame(loop);
}

boot();
