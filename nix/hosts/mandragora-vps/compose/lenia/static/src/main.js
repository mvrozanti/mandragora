import { LeniaEngine } from './engine.js';
import { describeWebGL } from './gl.js';
import { ControlPanel, drawKernelProfile, drawGrowthProfile, drawBandMeter } from './ui.js';
import { PRESETS, DISCOVERED, PALETTES, GRID_SIZES, DEFAULTS, ART_PALETTE } from './presets.js';
import { kernelProfile } from './kernel.js';
import { createParams } from './params.js';
import { randomSpecies, mutateSpecies, speciesForTrack, hashString } from './species.js';
import { paletteFromImage, paletteFromSeed } from './artwork.js';
import { MpdLink } from './audio.js';

const canvas = document.getElementById('field');
const panelRoot = document.getElementById('panel-body');
const shell = document.querySelector('.shell');
const hud = {
  fps: document.getElementById('hud-fps'),
  gen: document.getElementById('hud-gen'),
  grid: document.getElementById('hud-grid'),
  taps: document.getElementById('hud-taps'),
  zoom: document.getElementById('hud-zoom'),
  precision: document.getElementById('hud-precision'),
  kernels: document.getElementById('hud-kernels')
};
const brushRing = document.getElementById('brush-ring');
const speciesName = document.getElementById('species-name');
const kernelCanvas = document.getElementById('kernel-plot');
const growthCanvas = document.getElementById('growth-plot');
const presetNote = document.getElementById('preset-note');

const params = createParams(PRESETS[DEFAULTS.preset]);
params.running = true;

const mpd = new MpdLink();

function accent() {
  if (params.palette === ART_PALETTE && params.artAccent) return params.artAccent;
  return PALETTES[Math.min(params.palette, PALETTES.length - 1)].accent;
}

function refreshPlots() {
  const resolved = params.resolveSpecies();
  drawKernelProfile(kernelCanvas, kernelProfile(resolved), accent());
  drawGrowthProfile(growthCanvas, resolved.kernels, accent());
}

function applyAccent() {
  document.documentElement.style.setProperty('--accent', accent());
}

const engine = new LeniaEngine(canvas, params);

function adoptSpecies(species) {
  params.adopt(species);
  presetNote.textContent = species.note;
  document.body.dataset.channels = String(species.channels);
  speciesName.textContent = species.name;
  panel.syncAll();
  engine.rebuildSpecies();
  engine.randomize();
  refreshPlots();
  updateHud(true);
}

function applyPreset(index) {
  adoptSpecies(PRESETS[index]);
}

function handleChange(key, value, options) {
  if (options?.action) {
    if (key === 'randomize') engine.randomize();
    if (key === 'solo') engine.seedSolo();
    if (key === 'clear') engine.clear();
    if (key === 'resetView') { engine.zoom = 1; engine.pan.x = 0; engine.pan.y = 0; }
    if (key === 'snapshot') snapshot();
    if (key === 'newSpecies') {
      adoptSpecies(randomSpecies(Math.random, { channels: params.channels(), name: 'Wild sample' }));
    }
    if (key === 'mutate') adoptSpecies(mutateSpecies(params.species, 0.2));
    if (key === 'toChannels1') adoptSpecies(randomSpecies(Math.random, { channels: 1, name: 'Wild sample · 1ch' }));
    if (key === 'toChannels3') adoptSpecies(randomSpecies(Math.random, { channels: 3, name: 'Wild sample · 3ch' }));
    return;
  }
  if (key === 'preset') { applyPreset(value); return; }
  if (key === 'size') { engine.resizeSimulation(value); engine.randomize(); updateHud(true); return; }
  if (key === 'renderScale') { engine.resizeView(); return; }
  if (key === 'precision') {
    engine.resizeSimulation(params.size);
    engine.randomize();
    updateHud(true);
    return;
  }
  if (key === 'palette') { applyAccent(); refreshPlots(); return; }
  if (key === 'paletteFromArt') {
    if (value && currentTrackKey) adoptTrackPalette(currentTrackKey);
    else if (!value) { params.palette = 0; panel.sync('palette'); applyAccent(); refreshPlots(); showSwatches([]); }
    return;
  }
  if (key === 'speciesPerTrack') {
    if (value && currentTrackKey) onTrackChange(currentTrackKey);
    return;
  }
  if (key === 'audioEnabled') {
    if (value) mpd.open(); else { mpd.close(); params.resetMod(); }
    document.body.dataset.audio = value ? 'on' : 'off';
    return;
  }
  if (key === 'radius' || key === 'muShift' || key === 'sigmaScale' || key === 'heightScale') {
    params.radius = Math.round(params.radius);
    engine.rebuildSpecies();
    refreshPlots();
    updateHud(true);
  }
}

const panel = new ControlPanel(panelRoot, params, handleChange);

panel
  .group('Organism', 'Kernel geometry and growth response. These define the species.')
  .choice('preset', 'Species', PRESETS.map((p, i) => ({ label: `${p.name}  ·  ${p.channels}ch`, value: i })))
  .actions([
    { label: 'Wild 1ch', key: 'toChannels1', hint: 'sample a random single-channel species' },
    { label: 'Wild 3ch', key: 'toChannels3', hint: 'sample a random three-channel species' },
    { label: 'Mutate', key: 'mutate', hint: 'perturb the current species' }
  ])
  .slider('radius', 'Kernel radius  R', 6, 26, 1)
  .slider('timescale', 'Timescale  T', 2, 30, 1)
  .slider('muShift', 'Growth centre shift  Δμ', -0.12, 0.12, 0.001)
  .slider('sigmaScale', 'Tolerance scale  ×σ', 0.4, 2.4, 0.01)
  .slider('heightScale', 'Kernel weight  ×h', 0.3, 1.8, 0.01)
  .slider('stepsPerFrame', 'Steps / frame', 0, 8, 1)
  .choice('size', 'Grid', GRID_SIZES.map((s) => ({ label: `${s} × ${s}`, value: s })))
  .actions([
    { label: 'Reseed', key: 'randomize', hint: 'R' },
    { label: 'Solo', key: 'solo', hint: 'one specimen in the centre (O)' },
    { label: 'Clear', key: 'clear', hint: 'C' }
  ])
  .slider('seedCoverage', 'Seed coverage', 0.1, 1, 0.01)
  .slider('seedDensity', 'Seed density', 0.1, 1, 0.01);

panel
  .group('Light', 'How the field becomes colour before anything glows.')
  .choice('palette', 'Palette', PALETTES.map((p, i) => ({ label: p.name, value: i })))
  .slider('glow', 'Emission', 0.2, 3, 0.01)
  .slider('contrast', 'Falloff', 0.3, 2.5, 0.01)
  .slider('channelSep', 'Channel separation', 1, 5, 0.05)
  .slider('edgeAmount', 'Growth rim', 0, 2, 0.01)
  .slider('trailAmount', 'Afterglow', 0, 1.5, 0.01)
  .slider('trailDecay', 'Afterglow decay', 0.5, 0.995, 0.001);

panel
  .group('Bloom', 'Progressive dual-filter chain over eight mip levels.')
  .slider('bloomIntensity', 'Intensity', 0, 3, 0.01)
  .slider('bloomThreshold', 'Threshold', 0, 1.5, 0.01)
  .slider('bloomKnee', 'Soft knee', 0.01, 1, 0.01)
  .slider('bloomRadius', 'Spread', 0.5, 3, 0.01)
  .slider('dispersion', 'Dispersion', 0, 4, 0.01);

panel
  .group('Frame', 'Final grade applied after tonemapping.')
  .slider('exposure', 'Exposure', 0.2, 3, 0.01)
  .slider('vignette', 'Vignette', 0, 1, 0.01)
  .slider('grain', 'Grain', 0, 0.06, 0.001)
  .slider('tonemap', 'Filmic tonemap', 0, 1, 0.01)
  .slider('renderScale', 'Render scale', 0.5, 1.5, 0.05)
  .choice('precision', 'State precision', [
    { label: 'float32 — exact', value: 'float32' },
    { label: 'float16 — faster', value: 'float16' }
  ])
  .slider('brushRadius', 'Brush radius', 4, 90, 1)
  .slider('brushStrength', 'Brush strength', 0.1, 1, 0.01)
  .actions([
    { label: 'Reset view', key: 'resetView' },
    { label: 'Save PNG', key: 'snapshot' }
  ]);

panel
  .group('Audio', 'Drive the simulation from MPD. Reads the fifo output directly — no microphone.')
  .toggle('audioEnabled', 'React to MPD')
  .readout('audio-status', 'off')
  .meter('audio-meter', 28)
  .toggle('paletteFromArt', 'Palette from album art')
  .toggle('speciesPerTrack', 'Species per track')
  .toggle('homeostat', 'Never empty')
  .swatches('art-swatches')
  .slider('audioDrive', 'Drive', 0, 2, 0.01)
  .slider('audioBass', 'Bass → growth', 0, 1.5, 0.01)
  .slider('audioMid', 'Mid → bloom', 0, 2, 0.01)
  .slider('audioTreble', 'Treble → colour', 0, 2, 0.01)
  .slider('audioChannels', 'Bands → channels', 0, 2, 0.01)
  .slider('audioSpawn', 'Onset → creatures', 0, 1, 0.01)
  .slider('audioNutrient', 'Spectrum → nutrient', 0, 2, 0.01)
  .slider('audioStarve', 'Silence → starvation', 0, 1, 0.01);

const audioStatus = document.getElementById('audio-status');
const audioMeter = document.getElementById('audio-meter');
const artSwatches = document.getElementById('art-swatches');

let currentTrackKey = '';
let watchdog = null;

function showSwatches(list) {
  artSwatches.textContent = '';
  list.forEach((colour) => {
    const chip = document.createElement('span');
    chip.className = 'swatch';
    chip.style.background = colour;
    artSwatches.append(chip);
  });
}

function applyPalette(result) {
  params.customStops.set(result.stops);
  params.customPrimaries.set(result.primaries);
  params.artAccent = result.accent;
  params.palette = ART_PALETTE;
  panel.sync('palette');
  applyAccent();
  refreshPlots();
  showSwatches(result.swatches);
}

async function adoptTrackPalette(key) {
  let result = null;
  try {
    const response = await fetch(`mpd/art?k=${encodeURIComponent(key)}`, { cache: 'no-store' });
    if (!response.ok) throw new Error(String(response.status));
    const blob = await response.blob();
    const url = URL.createObjectURL(blob);
    try {
      result = await paletteFromImage(url);
    } finally {
      URL.revokeObjectURL(url);
    }
  } catch {
    result = null;
  }
  try {
    applyPalette(result || paletteFromSeed(hashString(key)));
  } catch (error) {
    console.warn('palette from track failed', error);
  }
}

function watchViability(fallback) {
  if (watchdog) clearInterval(watchdog);
  const started = engine.generation;
  watchdog = setInterval(() => {
    if (engine.generation - started > 900) { clearInterval(watchdog); watchdog = null; return; }
    if (engine.generation - started < 150) return;
    const reduced = engine.reduce();
    let sum = 0;
    for (let i = 0; i < reduced.length; i += 4) {
      sum += Math.max(reduced[i], Math.max(reduced[i + 1], reduced[i + 2]));
    }
    if (sum / (reduced.length / 4) < 0.01) {
      clearInterval(watchdog);
      watchdog = null;
      adoptSpecies(fallback);
    }
  }, 1200);
}

function onTrackChange(key) {
  if (params.paletteFromArt) adoptTrackPalette(key);
  if (params.speciesPerTrack) {
    const derived = speciesForTrack(DISCOVERED, key);
    adoptSpecies(derived);
    watchViability(derived.parent);
  }
}

function snapshot() {
  engine.draw(performance.now() / 1000);
  const link = document.createElement('a');
  link.href = canvas.toDataURL('image/png');
  link.download = `lenia-${PRESETS[params.preset].name.toLowerCase()}-${engine.generation}.png`;
  link.click();
}

let lastFrame = performance.now();
let fpsAccumulator = 0;
let fpsFrames = 0;

function updateHud(force) {
  hud.gen.textContent = String(engine.generation).padStart(6, '0');
  if (force) {
    hud.grid.textContent = `${engine.size}²`;
    hud.taps.textContent = String(engine.kernelTaps);
    hud.precision.textContent = engine.precision === 'float32' ? 'f32' : 'f16';
    hud.kernels.textContent = `${engine.kernelCount}×${params.channels()}ch`;
  }
  hud.zoom.textContent = `${engine.zoom.toFixed(2)}×`;
}

const NUTRIENT_SIZE = 64;
const nutrientField = new Float32Array(NUTRIENT_SIZE * NUTRIENT_SIZE * 4);
const BAND_RING = [0.12, 0.30, 0.48, 0.66, 0.84];
const BAND_CHANNELS = [
  [1.00, 0.05, 0.00],
  [0.65, 0.35, 0.00],
  [0.05, 1.00, 0.05],
  [0.00, 0.35, 0.65],
  [0.00, 0.05, 1.00]
];

function buildNutrient(bands) {
  const sigma = 0.11;
  const inv = 1 / (2 * sigma * sigma);
  for (let y = 0; y < NUTRIENT_SIZE; y++) {
    const dy = (y + 0.5) / NUTRIENT_SIZE - 0.5;
    for (let x = 0; x < NUTRIENT_SIZE; x++) {
      const dx = (x + 0.5) / NUTRIENT_SIZE - 0.5;
      const r = Math.sqrt(dx * dx + dy * dy) * 2;
      let cr = 0, cg = 0, cb = 0;
      for (let b = 0; b < 5; b++) {
        const energy = bands[b];
        if (energy < 0.02) continue;
        const d = r - BAND_RING[b];
        const w = energy * Math.exp(-d * d * inv);
        cr += w * BAND_CHANNELS[b][0];
        cg += w * BAND_CHANNELS[b][1];
        cb += w * BAND_CHANNELS[b][2];
      }
      const i = (y * NUTRIENT_SIZE + x) * 4;
      nutrientField[i] = cr;
      nutrientField[i + 1] = cg;
      nutrientField[i + 2] = cb;
    }
  }
  return nutrientField;
}

function spawnCreature(bands) {
  let band = 0;
  for (let b = 1; b < 5; b++) if (bands[b] > bands[band]) band = b;
  const angle = Math.random() * Math.PI * 2;
  const fieldRadius = BAND_RING[band] * engine.size * 0.5;
  const centre = {
    x: engine.size / 2 + Math.cos(angle) * fieldRadius,
    y: engine.size / 2 + Math.sin(angle) * fieldRadius
  };
  const mix = params.channels() === 1 ? [1, 0, 0] : BAND_CHANNELS[band].map((v) => 0.55 + 0.45 * v);
  engine.spawnSeed(centre, 1.05 - band * 0.09, Math.min(1, params.audioSpawn * 1.5), mix);
}

function applyAudio(dtSeconds) {
  if (!params.audioEnabled) return;
  const fired = mpd.advance(Math.min(dtSeconds, 0.25));
  const drive = params.audioDrive;
  const b = mpd.bands;
  const bass = Math.max(b[0], b[1] * 0.6);
  const mid = Math.max(b[2], b[1] * 0.5);
  const treble = Math.max(b[4], b[3] * 0.7);
  const level = mpd.smoothLevel;

  params.mod.mu = -params.audioBass * drive * bass * 0.022;
  params.mod.height = 1 + params.audioBass * drive * bass * 0.28;
  params.mod.bloom = 1 + params.audioMid * drive * mid * 1.1;
  params.mod.glow = 1 + params.audioMid * drive * level * 0.55;
  params.mod.separation = 1 + params.audioTreble * drive * treble * 1.3;
  params.mod.edge = 1 + params.audioTreble * drive * treble * 0.9;
  params.mod.exposure = 1 + drive * level * 0.22;

  const playing = mpd.live && mpd.playing;
  const bucket = [
    Math.max(b[0], b[1] * 0.7),
    Math.max(b[1] * 0.4, b[2], b[3] * 0.5),
    Math.max(b[3] * 0.6, b[4])
  ];
  const cd = params.mod.channelDrive;
  if (playing && params.channels() === 3) {
    const meanBucket = (bucket[0] + bucket[1] + bucket[2]) / 3;
    for (let c = 0; c < 3; c++) {
      cd[c] = params.audioChannels * drive * (bucket[c] - meanBucket) * 0.16;
    }
  } else if (playing) {
    cd[0] = params.audioChannels * drive * (level - 0.4) * 0.06;
    cd[1] = cd[2] = 0;
  } else {
    cd[0] = cd[1] = cd[2] = 0;
  }
  params.mod.nutrient = playing ? params.audioNutrient * drive * 0.35 : 0;
  params.mod.starve = playing ? params.audioStarve * drive * Math.max(0, 0.55 - level) * 0.5 : 0;
  if (playing) engine.setNutrient(buildNutrient(b));

  if (fired && params.audioSpawn > 0) spawnCreature(b);

  const key = mpd.trackKey;
  if (mpd.live && key && key !== currentTrackKey) {
    currentTrackKey = key;
    onTrackChange(key);
  }

  audioStatus.textContent = mpd.describe();
  audioStatus.dataset.live = String(mpd.live && mpd.playing);
  drawBandMeter(audioMeter, mpd.bands, level, accent(), mpd.live && mpd.playing);
}

let homeostatCountdown = 60;

function homeostat() {
  if (!params.homeostat || !params.running || params.stepsPerFrame === 0) return;
  if (--homeostatCountdown > 0) return;
  homeostatCountdown = 45;
  const reduced = engine.reduce();
  let sum = 0;
  const n = reduced.length / 4;
  for (let i = 0; i < n; i++) {
    sum += Math.max(reduced[i * 4], Math.max(reduced[i * 4 + 1], reduced[i * 4 + 2]));
  }
  const mean = sum / n;
  if (mean < 0.012) {
    const seeds = mean < 0.002 ? 3 : 1;
    for (let i = 0; i < seeds; i++) {
      engine.spawnSeed(
        { x: Math.random() * engine.size, y: Math.random() * engine.size },
        0.85 + Math.random() * 0.4, 0.9);
    }
  } else if (mean > 0.82) {
    engine.stamp({
      from: { x: Math.random() * engine.size, y: Math.random() * engine.size },
      to: { x: Math.random() * engine.size, y: Math.random() * engine.size },
      radius: engine.size * 0.22, strength: -0.5
    });
  }
}

function frame(now) {
  const dt = now - lastFrame;
  lastFrame = now;
  fpsAccumulator += dt;
  fpsFrames++;
  if (fpsAccumulator > 400) {
    hud.fps.textContent = (1000 / (fpsAccumulator / fpsFrames)).toFixed(0);
    fpsAccumulator = 0;
    fpsFrames = 0;
  }

  engine.resizeView();
  applyAudio(dt / 1000);
  homeostat();
  if (params.running && params.stepsPerFrame > 0) engine.step(params.stepsPerFrame);
  engine.draw(now / 1000);
  updateHud(false);
  requestAnimationFrame(frame);
}

const pointer = { active: false, mode: null, last: null };

function updateBrushRing(event, erasing) {
  const rect = canvas.getBoundingClientRect();
  const pixels = params.brushRadius * rect.height * engine.zoom / engine.size;
  brushRing.style.width = `${pixels * 2}px`;
  brushRing.style.height = `${pixels * 2}px`;
  brushRing.style.left = `${event.clientX}px`;
  brushRing.style.top = `${event.clientY}px`;
  brushRing.classList.toggle('erasing', erasing);
}

canvas.addEventListener('pointerenter', () => brushRing.classList.add('visible'));
canvas.addEventListener('pointerleave', () => brushRing.classList.remove('visible'));

canvas.addEventListener('pointerdown', (event) => {
  canvas.setPointerCapture(event.pointerId);
  pointer.active = true;
  pointer.last = { clientX: event.clientX, clientY: event.clientY };
  if (event.button === 1 || event.altKey) {
    pointer.mode = 'pan';
  } else {
    pointer.mode = (event.button === 2 || event.shiftKey) ? 'erase' : 'draw';
    const p = engine.screenToField(event.clientX, event.clientY);
    pointer.field = p;
    engine.paint(p, p, pointer.mode === 'erase' ? -params.brushStrength : params.brushStrength);
  }
  event.preventDefault();
});

canvas.addEventListener('pointermove', (event) => {
  const erasing = event.shiftKey || (event.buttons & 2) !== 0;
  updateBrushRing(event, erasing);
  brushRing.classList.toggle('visible', pointer.mode !== 'pan');
  if (!pointer.active) return;
  if (pointer.mode === 'pan') {
    const rect = canvas.getBoundingClientRect();
    const aspect = engine.viewWidth / engine.viewHeight;
    const dx = (event.clientX - pointer.last.clientX) / rect.width * aspect / engine.zoom;
    const dy = (event.clientY - pointer.last.clientY) / rect.height / engine.zoom;
    engine.pan.x -= dx;
    engine.pan.y += dy;
  } else {
    const p = engine.screenToField(event.clientX, event.clientY);
    engine.paint(pointer.field ?? p, p, pointer.mode === 'erase' ? -params.brushStrength : params.brushStrength);
    pointer.field = p;
  }
  pointer.last = { clientX: event.clientX, clientY: event.clientY };
});

function endPointer(event) {
  pointer.active = false;
  pointer.mode = null;
  pointer.field = null;
  if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
}
canvas.addEventListener('pointerup', endPointer);
canvas.addEventListener('pointercancel', endPointer);
canvas.addEventListener('contextmenu', (event) => event.preventDefault());

canvas.addEventListener('wheel', (event) => {
  event.preventDefault();
  const rect = canvas.getBoundingClientRect();
  const nx = (event.clientX - rect.left) / rect.width;
  const ny = 1 - (event.clientY - rect.top) / rect.height;
  const aspect = engine.viewWidth / engine.viewHeight;
  const cx = (nx - 0.5) * aspect;
  const cy = ny - 0.5;
  const target = { x: cx / engine.zoom + 0.5 + engine.pan.x, y: cy / engine.zoom + 0.5 + engine.pan.y };
  const factor = Math.exp(-event.deltaY * 0.0015);
  engine.zoom = Math.min(40, Math.max(0.25, engine.zoom * factor));
  engine.pan.x = target.x - cx / engine.zoom - 0.5;
  engine.pan.y = target.y - cy / engine.zoom - 0.5;
}, { passive: false });

window.addEventListener('keydown', (event) => {
  if (event.target instanceof HTMLInputElement || event.target instanceof HTMLSelectElement) return;
  const key = event.key.toLowerCase();
  if (key === ' ') { params.running = !params.running; shell.dataset.paused = String(!params.running); event.preventDefault(); }
  else if (key === 'r') engine.randomize();
  else if (key === 'c') engine.clear();
  else if (key === 'h') shell.classList.toggle('bare');
  else if (key === 'f') { if (document.fullscreenElement) document.exitFullscreen(); else document.documentElement.requestFullscreen(); }
  else if (key === 'v') { engine.zoom = 1; engine.pan.x = 0; engine.pan.y = 0; }
  else if (key >= '1' && key <= String(PRESETS.length)) {
    params.preset = Number(key) - 1;
    panel.sync('preset');
    applyPreset(params.preset);
  }
});

document.getElementById('panel-toggle').addEventListener('click', () => shell.classList.toggle('bare'));

let fatalShown = false;

function showFatal(error) {
  if (fatalShown) return;
  fatalShown = true;
  const report = describeWebGL();
  const rows = [
    ['WebGL2 context', report.context ? 'available' : `unavailable${report.error ? ` — ${report.error}` : ''}`, report.context],
    ['Renderer', report.renderer || 'unreported', !!report.renderer],
    ['EXT_color_buffer_float', report.full ? 'yes' : 'no', report.full],
    ['EXT_color_buffer_half_float', report.half ? 'yes' : 'no', report.half],
    ['OES_texture_float_linear', report.linear ? 'yes' : 'no', report.linear]
  ];
  const list = document.getElementById('fatal-report');
  list.textContent = '';
  rows.forEach(([label, value, ok]) => {
    const dt = document.createElement('dt');
    dt.textContent = label;
    const dd = document.createElement('dd');
    dd.textContent = value;
    dd.className = ok ? 'yes' : 'no';
    list.append(dt, dd);
  });
  document.getElementById('fatal-title').textContent = report.context
    ? 'The simulation failed to start'
    : 'This browser cannot run the simulation';
  document.getElementById('fatal-message').textContent = error.message;
  document.getElementById('fatal-stack').textContent = error.stack && error.stack !== error.message ? error.stack : '';
  document.getElementById('fatal').hidden = false;
  document.getElementById('boot').classList.add('gone');
}

async function boot() {
  try {
    await engine.init();
  } catch (error) {
    showFatal(error);
    throw error;
  }
  applyAccent();
  applyPreset(params.preset);
  const bridge = await mpd.probe();
  document.body.dataset.bridge = bridge === true ? 'on' : (bridge === 'auth' ? 'auth' : 'off');
  if (bridge !== true) {
    params.audioEnabled = false;
    params.paletteFromArt = false;
    params.speciesPerTrack = false;
    panel.syncAll();
    audioStatus.textContent = mpd.describe();
  }
  document.body.dataset.audio = params.audioEnabled ? 'on' : 'off';
  if (params.audioEnabled) mpd.open();
  shell.dataset.paused = 'false';
  document.getElementById('boot').classList.add('gone');
  window.lenia = { engine, params, panel, applyPreset, adoptSpecies, mpd, tick: frame, setAudio: (on) => { params.audioEnabled = on; panel.sync('audioEnabled'); handleChange('audioEnabled', on, {}); } };
  requestAnimationFrame(frame);
}

window.addEventListener('resize', () => refreshPlots());
window.addEventListener('error', (event) => showFatal(event.error || new Error(event.message)));
window.addEventListener('unhandledrejection', (event) => {
  const reason = event.reason;
  showFatal(reason instanceof Error ? reason : new Error(String(reason)));
});
await boot();
