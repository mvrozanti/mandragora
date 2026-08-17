export const TOK = {
  bg: "#07090d",
  panel: "#0d1117",
  ink: "#e6edf3",
  muted: "#8b949e",
  accent: "#c084fc",
  grid: "rgba(139,148,158,0.14)",
};

export const CAT = ["#c084fc", "#22d3ee", "#fb7185", "#a3e635", "#fbbf24", "#f472b6", "#38bdf8", "#34d399"];

export const MONO = 'ui-monospace,"SFMono-Regular","Cascadia Mono",Menlo,Consolas,monospace';

const MAGMA = [
  [0, 0, 4], [28, 16, 68], [79, 18, 123], [129, 37, 129], [181, 54, 122],
  [229, 80, 100], [251, 135, 97], [254, 194, 135], [252, 253, 191],
];

export function clamp(v, a, b) {
  return v < a ? a : v > b ? b : v;
}

export function magma(t) {
  t = clamp(t, 0, 1);
  const s = t * (MAGMA.length - 1);
  const i = Math.min(Math.floor(s), MAGMA.length - 2);
  const f = s - i;
  const a = MAGMA[i], b = MAGMA[i + 1];
  return [
    Math.round(a[0] + (b[0] - a[0]) * f),
    Math.round(a[1] + (b[1] - a[1]) * f),
    Math.round(a[2] + (b[2] - a[2]) * f),
  ];
}

export function magmaCss(t, alpha = 1) {
  const [r, g, b] = magma(t);
  return `rgba(${r},${g},${b},${alpha})`;
}

export function timeCss(f, alpha = 1) {
  return magmaCss(0.16 + 0.74 * clamp(f, 0, 1), alpha);
}

export function fmtTime(s) {
  if (!isFinite(s)) return "0:00";
  s = Math.max(0, Math.round(s));
  const m = Math.floor(s / 60);
  const r = s % 60;
  return m + ":" + String(r).padStart(2, "0");
}

export function fmtHz(v) {
  return v >= 1000 ? (v / 1000).toFixed(v >= 10000 ? 0 : 1).replace(/\.0$/, "") + "k" : String(Math.round(v));
}

export function prepCanvas(canvas, hCss) {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const host = canvas.parentElement;
  const w = Math.max(40, canvas.clientWidth || (host ? host.clientWidth : 0));
  canvas.style.height = hCss + "px";
  canvas.width = Math.max(1, Math.round(w * dpr));
  canvas.height = Math.max(1, Math.round(hCss * dpr));
  const ctx = canvas.getContext("2d");
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, w, hCss);
  return { ctx, w, h: hCss };
}

export function path(ctx, n, fx, fy) {
  ctx.beginPath();
  let started = false;
  for (let i = 0; i < n; i++) {
    const x = fx(i), y = fy(i);
    if (!isFinite(x) || !isFinite(y)) { started = false; continue; }
    if (started) ctx.lineTo(x, y);
    else { ctx.moveTo(x, y); started = true; }
  }
}

export function strokePath(ctx, color, width = 1.5, dash = null) {
  ctx.save();
  ctx.strokeStyle = color;
  ctx.lineWidth = width;
  ctx.lineJoin = "round";
  if (dash) ctx.setLineDash(dash);
  ctx.stroke();
  ctx.restore();
}

export function timePath(ctx, n, fx, fy, { width = 2, alpha = 0.9 } = {}) {
  ctx.save();
  ctx.lineWidth = width;
  ctx.lineCap = "round";
  for (let i = 1; i < n; i++) {
    const x0 = fx(i - 1), y0 = fy(i - 1), x1 = fx(i), y1 = fy(i);
    if (!isFinite(x0) || !isFinite(y0) || !isFinite(x1) || !isFinite(y1)) continue;
    ctx.strokeStyle = timeCss(i / (n - 1), alpha);
    ctx.beginPath();
    ctx.moveTo(x0, y0);
    ctx.lineTo(x1, y1);
    ctx.stroke();
  }
  ctx.restore();
}

export function text(ctx, s, x, y, { color = TOK.muted, align = "left", baseline = "alphabetic", size = 10 } = {}) {
  ctx.save();
  ctx.font = size + "px " + MONO;
  ctx.fillStyle = color;
  ctx.textAlign = align;
  ctx.textBaseline = baseline;
  ctx.fillText(s, x, y);
  ctx.restore();
}

export function hline(ctx, y, w, color = TOK.grid, dash = null) {
  ctx.save();
  ctx.strokeStyle = color;
  ctx.lineWidth = 1;
  if (dash) ctx.setLineDash(dash);
  ctx.beginPath();
  ctx.moveTo(0, y + 0.5);
  ctx.lineTo(w, y + 0.5);
  ctx.stroke();
  ctx.restore();
}

export function vline(ctx, x, h, color = TOK.grid, dash = null) {
  ctx.save();
  ctx.strokeStyle = color;
  ctx.lineWidth = 1;
  if (dash) ctx.setLineDash(dash);
  ctx.beginPath();
  ctx.moveTo(x + 0.5, 0);
  ctx.lineTo(x + 0.5, h);
  ctx.stroke();
  ctx.restore();
}

export function finiteExtent(arr) {
  let lo = Infinity, hi = -Infinity;
  for (const v of arr) {
    if (v == null || !isFinite(v)) continue;
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  if (lo > hi) { lo = 0; hi = 1; }
  return [lo, hi];
}

export function quantile(arr, q) {
  const s = arr.filter(v => v != null && isFinite(v)).slice().sort((a, b) => a - b);
  if (!s.length) return 0;
  const i = clamp(Math.floor(q * (s.length - 1)), 0, s.length - 1);
  return s[i];
}

export function heatmap(canvas, matrix, { flipY = true, gain = 1 } = {}) {
  const n = matrix.length;
  if (!n) return;
  const rows = matrix[0].length;
  canvas.width = n;
  canvas.height = rows;
  const ctx = canvas.getContext("2d");
  const img = ctx.createImageData(n, rows);
  let mx = 0;
  for (const col of matrix) for (const v of col) if (isFinite(v) && v > mx) mx = v;
  if (!mx) mx = 1;
  for (let i = 0; i < n; i++) {
    const col = matrix[i];
    for (let p = 0; p < rows; p++) {
      const v = clamp((col[p] || 0) / mx * gain, 0, 1);
      const [r, g, b] = magma(v);
      const y = flipY ? rows - 1 - p : p;
      const o = (y * n + i) * 4;
      img.data[o] = r;
      img.data[o + 1] = g;
      img.data[o + 2] = b;
      img.data[o + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
}
