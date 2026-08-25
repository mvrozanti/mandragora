const SAMPLE = 72;
const CLUSTERS = 6;
const ITERATIONS = 12;

function loadImage(url) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = () => reject(new Error('image decode failed'));
    image.src = url;
  });
}

function luminance(c) {
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

function toHsl(c) {
  const max = Math.max(c[0], c[1], c[2]);
  const min = Math.min(c[0], c[1], c[2]);
  const l = (max + min) / 2;
  if (max === min) return [0, 0, l];
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  let h;
  if (max === c[0]) h = ((c[1] - c[2]) / d + (c[1] < c[2] ? 6 : 0)) / 6;
  else if (max === c[1]) h = ((c[2] - c[0]) / d + 2) / 6;
  else h = ((c[0] - c[1]) / d + 4) / 6;
  return [h, s, l];
}

function fromHsl([h, s, l]) {
  if (s === 0) return [l, l, l];
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  const channel = (t) => {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  };
  return [channel(h + 1 / 3), channel(h), channel(h - 1 / 3)];
}

const linear = (c) => c.map((v) => Math.pow(Math.max(0, Math.min(1, v)), 2.2));
const scale = (c, k) => c.map((v) => v * k);
const blend = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);

function cluster(pixels) {
  const sorted = [...pixels].sort((a, b) => luminance(a) - luminance(b));
  const centres = [];
  for (let i = 0; i < CLUSTERS; i++) {
    centres.push(sorted[Math.floor(((i + 0.5) / CLUSTERS) * (sorted.length - 1))].slice());
  }
  const counts = new Array(CLUSTERS).fill(0);
  for (let pass = 0; pass < ITERATIONS; pass++) {
    const sums = centres.map(() => [0, 0, 0]);
    counts.fill(0);
    for (const p of pixels) {
      let best = 0;
      let bestDistance = Infinity;
      for (let i = 0; i < CLUSTERS; i++) {
        const c = centres[i];
        const d = (p[0] - c[0]) ** 2 + (p[1] - c[1]) ** 2 + (p[2] - c[2]) ** 2;
        if (d < bestDistance) { bestDistance = d; best = i; }
      }
      sums[best][0] += p[0]; sums[best][1] += p[1]; sums[best][2] += p[2];
      counts[best]++;
    }
    for (let i = 0; i < CLUSTERS; i++) {
      if (!counts[i]) continue;
      centres[i] = [sums[i][0] / counts[i], sums[i][1] / counts[i], sums[i][2] / counts[i]];
    }
  }
  return centres.map((colour, i) => {
    const [h, s, l] = toHsl(colour);
    return { colour, weight: counts[i] / pixels.length, hue: h, saturation: s, lightness: l };
  }).filter((c) => c.weight > 0.01);
}

function separateHues(entries) {
  const ranked = [...entries].sort((a, b) =>
    (b.weight * (0.25 + b.saturation)) - (a.weight * (0.25 + a.saturation)));
  const picked = [];
  for (const entry of ranked) {
    if (picked.length === 3) break;
    const clash = picked.some((p) => {
      const d = Math.abs(p.hue - entry.hue);
      return Math.min(d, 1 - d) < 0.07;
    });
    if (!clash) picked.push(entry);
  }
  let step = 0;
  while (picked.length < 3) {
    const base = ranked[0] || { hue: 0, saturation: 0.6, lightness: 0.5 };
    picked.push({ ...base, hue: (base.hue + 0.33 * (++step)) % 1 });
  }
  return picked.map((entry) => {
    const s = Math.max(entry.saturation, 0.62);
    const l = Math.min(0.68, Math.max(0.46, entry.lightness));
    return linear(fromHsl([entry.hue, s, l]));
  });
}

function buildStops(entries) {
  const byLuma = [...entries].sort((a, b) => luminance(a.colour) - luminance(b.colour));
  const keyed = [...entries].sort((a, b) =>
    (b.weight * (0.3 + b.saturation)) - (a.weight * (0.3 + a.saturation)));
  const dark = byLuma[0].colour;
  const key = keyed[0].colour;
  const bright = byLuma[byLuma.length - 1].colour;
  const white = [1, 1, 1];
  return [
    linear(scale(dark, 0.14)),
    linear(scale(blend(dark, key, 0.55), 0.5)),
    linear(scale(key, 0.92)),
    linear(scale(blend(key, bright, 0.6), 1.1)),
    linear(scale(blend(bright, white, 0.45), 1.1))
  ];
}

const flatten = (list) => Float32Array.from(list.flat());
const css = (c) => '#' + c.map((v) =>
  Math.round(Math.min(1, Math.max(0, v)) * 255).toString(16).padStart(2, '0')).join('');

export async function paletteFromImage(url) {
  const image = await loadImage(url);
  const canvas = document.createElement('canvas');
  canvas.width = SAMPLE;
  canvas.height = SAMPLE;
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  ctx.drawImage(image, 0, 0, SAMPLE, SAMPLE);
  const { data } = ctx.getImageData(0, 0, SAMPLE, SAMPLE);

  const pixels = [];
  for (let i = 0; i < data.length; i += 4) {
    if (data[i + 3] < 128) continue;
    pixels.push([data[i] / 255, data[i + 1] / 255, data[i + 2] / 255]);
  }
  if (pixels.length < CLUSTERS) throw new Error('not enough pixels');

  const entries = cluster(pixels);
  const stops = buildStops(entries);
  const primaries = separateHues(entries);
  const ranked = [...entries].sort((a, b) =>
    (b.weight * (0.3 + b.saturation)) - (a.weight * (0.3 + a.saturation)));

  return {
    stops: flatten(stops),
    primaries: flatten(primaries),
    swatches: ranked.slice(0, 5).map((e) => css(e.colour)),
    accent: css(fromHsl([ranked[0].hue, Math.max(ranked[0].saturation, 0.6), 0.62]))
  };
}

export function paletteFromSeed(seed) {
  const hue = (seed % 1000) / 1000;
  const entries = [0, 0.33, 0.66].map((offset, i) => ({
    colour: fromHsl([(hue + offset) % 1, 0.7, 0.25 + i * 0.2]),
    weight: 0.3, hue: (hue + offset) % 1, saturation: 0.7, lightness: 0.25 + i * 0.2
  }));
  return {
    stops: flatten(buildStops(entries)),
    primaries: flatten(separateHues(entries)),
    swatches: entries.map((e) => css(e.colour)),
    accent: css(fromHsl([hue, 0.7, 0.62]))
  };
}
