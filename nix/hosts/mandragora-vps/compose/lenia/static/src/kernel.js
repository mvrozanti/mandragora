const KERNEL_EPSILON = 1e-6;

function kernelCore(x) {
  if (x <= 0 || x >= 1) return 0;
  return Math.exp(4 - 1 / (x * (1 - x)));
}

export function buildSpecies(species) {
  const { R, kernels } = species;
  const count = kernels.length;
  const rows = Math.ceil(count / 4);
  const shells = kernels.map((k) => k.b.length);
  const reach = kernels.map((k) => Math.max(1e-3, k.r) * R);

  const offsets = [];
  const raw = kernels.map(() => []);
  const sums = new Float64Array(count);

  for (let dy = -R; dy <= R; dy++) {
    for (let dx = -R; dx <= R; dx++) {
      const distance = Math.sqrt(dx * dx + dy * dy);
      if (distance > R) continue;
      let any = false;
      const row = new Float64Array(count);
      for (let k = 0; k < count; k++) {
        const x = distance / reach[k];
        if (x >= 1) continue;
        const scaled = x * shells[k];
        const shell = Math.min(Math.floor(scaled), shells[k] - 1);
        const weight = kernels[k].b[shell] * kernelCore(scaled - shell);
        if (!(weight > KERNEL_EPSILON)) continue;
        row[k] = weight;
        sums[k] += weight;
        any = true;
      }
      if (!any) continue;
      offsets.push(dx, dy);
      for (let k = 0; k < count; k++) raw[k].push(row[k]);
    }
  }

  const taps = offsets.length / 2;
  const tapData = new Float32Array(taps * 4);
  for (let i = 0; i < taps; i++) {
    tapData[i * 4] = offsets[i * 2];
    tapData[i * 4 + 1] = offsets[i * 2 + 1];
  }

  const weightData = new Float32Array(taps * rows * 4);
  for (let k = 0; k < count; k++) {
    const total = sums[k] || 1;
    const row = Math.floor(k / 4);
    const lane = k % 4;
    const column = raw[k];
    for (let i = 0; i < taps; i++) {
      weightData[((row * taps) + i) * 4 + lane] = column[i] / total;
    }
  }

  return {
    taps,
    rows,
    count,
    tapData,
    weightData,
    src: new Int32Array(kernels.map((k) => k.src)),
    dst: new Int32Array(kernels.map((k) => k.dst)),
    mu: new Float32Array(kernels.map((k) => k.m)),
    sigma: new Float32Array(kernels.map((k) => k.s)),
    height: new Float32Array(kernels.map((k) => k.h))
  };
}

export function kernelProfile(species, samples = 128) {
  const { R, kernels } = species;
  const profile = new Float32Array(samples);
  let peak = 0;
  for (let i = 0; i < samples; i++) {
    const distance = ((i + 0.5) / samples) * R;
    let total = 0;
    for (const k of kernels) {
      const x = distance / Math.max(1e-3, k.r * R);
      if (x >= 1) continue;
      const scaled = x * k.b.length;
      const shell = Math.min(Math.floor(scaled), k.b.length - 1);
      total += Math.abs(k.h) * k.b[shell] * kernelCore(scaled - shell);
    }
    profile[i] = total;
    if (total > peak) peak = total;
  }
  if (peak > 0) for (let i = 0; i < samples; i++) profile[i] /= peak;
  return profile;
}

export function seedField(size, radius, coverage, density, channels = 4, planes = 1) {
  const data = new Float32Array(size * size * channels);
  const block = Math.max(1, Math.round(radius * 0.7));
  const patchRadius = Math.max(radius * 2.6, block * 4);
  const patchArea = Math.PI * patchRadius * patchRadius;
  const patches = Math.max(1, Math.round((coverage * size * size) / patchArea * 0.55));

  for (let p = 0; p < patches; p++) {
    const cx = Math.random() * size;
    const cy = Math.random() * size;
    const r = patchRadius * (0.7 + 0.9 * Math.random());
    const span = Math.ceil(r * 2);
    const across = Math.ceil(span / block) + 1;
    const noise = new Float32Array(across * across);
    for (let i = 0; i < noise.length; i++) {
      noise[i] = Math.random() < density ? 0.25 + 0.75 * Math.random() : 0;
    }
    const x0 = Math.round(cx - r);
    const y0 = Math.round(cy - r);
    for (let y = 0; y < span; y++) {
      const dy = y - r;
      for (let x = 0; x < span; x++) {
        const dx = x - r;
        if (dx * dx + dy * dy > r * r) continue;
        const gx = ((x0 + x) % size + size) % size;
        const gy = ((y0 + y) % size + size) % size;
        const value = noise[Math.floor(y / block) * across + Math.floor(x / block)];
        if (value <= 0) continue;
        const index = (gy * size + gx) * channels;
        for (let c = 0; c < planes; c++) {
          const jitter = planes === 1 ? value : value * (0.45 + 0.55 * Math.random());
          if (jitter > data[index + c]) data[index + c] = jitter;
        }
        if (channels === 4) data[index + 3] = data[index];
      }
    }
  }
  return data;
}
