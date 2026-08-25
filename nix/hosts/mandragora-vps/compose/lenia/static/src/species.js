export function singleKernel(name, note, R, T, m, s, b) {
  return {
    name, note, channels: 1, R, T,
    kernels: [{ src: 0, dst: 0, r: 1, b, m, s, h: 1 }]
  };
}

export function cloneSpecies(species) {
  return {
    ...species,
    kernels: species.kernels.map((k) => ({ ...k, b: k.b.slice() }))
  };
}

function pick(rng, list) {
  return list[Math.floor(rng() * list.length)];
}

function range(rng, lo, hi) {
  return lo + rng() * (hi - lo);
}

export function randomSpecies(rng = Math.random, options = {}) {
  const channels = options.channels ?? 3;
  const count = options.count ?? (channels === 1 ? 3 : 3 * channels);
  const R = options.R ?? Math.round(range(rng, options.Rmin ?? 12, options.Rmax ?? 20));
  const kernels = [];
  for (let i = 0; i < count; i++) {
    const shells = 1 + Math.floor(rng() * 3);
    const b = [];
    for (let j = 0; j < shells; j++) b.push(Math.round(range(rng, 0.2, 1) * 4) / 4 || 1);
    b[Math.floor(rng() * shells)] = 1;
    kernels.push({
      src: channels === 1 ? 0 : i % channels,
      dst: channels === 1 ? 0 : Math.floor(rng() * channels),
      r: range(rng, 0.35, 1),
      b,
      m: range(rng, 0.05, 0.5),
      s: range(rng, 0.005, 0.18),
      h: range(rng, 0.05, 1)
    });
  }
  return {
    name: options.name ?? 'Unnamed',
    note: options.note ?? 'randomly sampled parameter set',
    channels, R,
    T: options.T ?? Math.round(range(rng, 6, 16)),
    kernels
  };
}

export function mutateSpecies(species, amount = 0.15, rng = Math.random) {
  const next = cloneSpecies(species);
  next.name = `${species.name.replace(/ ·.*$/, '')} · mutated`;
  next.note = 'mutated from a parent parameter set';
  next.kernels.forEach((k) => {
    k.m = Math.min(0.6, Math.max(0.02, k.m * (1 + (rng() * 2 - 1) * amount)));
    k.s = Math.min(0.25, Math.max(0.003, k.s * (1 + (rng() * 2 - 1) * amount)));
    k.h = Math.min(1.5, Math.max(0.02, k.h * (1 + (rng() * 2 - 1) * amount)));
    k.r = Math.min(1, Math.max(0.2, k.r * (1 + (rng() * 2 - 1) * amount * 0.6)));
  });
  return next;
}

export function speciesSignature(species) {
  const parts = species.kernels.map((k) =>
    `${k.src}>${k.dst}:${k.r.toFixed(2)}:${k.b.map((v) => v.toFixed(2)).join('/')}:${k.m.toFixed(3)}:${k.s.toFixed(3)}:${k.h.toFixed(2)}`
  );
  return `${species.channels}|${species.R}|${species.T}|${parts.join(',')}`;
}

export function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function hashString(text) {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h >>> 0;
}

export function speciesForTrack(pool, key, amount = 0.16) {
  const seed = hashString(key);
  const rng = mulberry32(seed);
  const base = pool[seed % pool.length];
  const child = mutateSpecies(base, amount, rng);
  child.name = base.name;
  child.note = `derived from this track — ${base.name} strain #${(seed % 9973).toString(36)}`;
  child.parent = base;
  child.seed = seed;
  return child;
}
