import {
  createContext, loadShaderSources, createProgram, withDefines, withOutputs,
  createTarget, createLayeredTarget, bindLayered, destroyTarget, bindTarget,
  bindTextures, bindTexturesArray, drawQuad
} from './gl.js';
import { buildSpecies, seedChannels, splitLayers } from './kernel.js';

const SHADER_FILES = [
  'quad.vert', 'step.frag', 'paint.frag', 'render.frag',
  'bright.frag', 'downsample.frag', 'upsample.frag', 'composite.frag', 'reduce.frag'
];

const REDUCE_GRID = 32;

const MIN_MIP = 12;
const NUTRIENT_SIZE = 64;
const MAX_MIPS = 8;

export class LeniaEngine {
  constructor(canvas, params) {
    this.canvas = canvas;
    this.params = params;
    const { gl, capabilities } = createContext(canvas);
    this.gl = gl;
    this.capabilities = capabilities;
    this.shapePrograms = new Map();
    this.mips = [];
    this.state = null;
    this.scene = null;
    this.generation = 0;
    this.viewWidth = 0;
    this.viewHeight = 0;
    this.pan = { x: 0, y: 0 };
    this.zoom = 1;
  }

  async init() {
    const gl = this.gl;
    this.sources = await loadShaderSources(SHADER_FILES);
    this.vao = gl.createVertexArray();
    gl.bindVertexArray(this.vao);
    const vert = this.sources['quad.vert'];
    this.programs = {
      bright: createProgram(gl, vert, this.sources['bright.frag'], 'bright'),
      down: createProgram(gl, vert, this.sources['downsample.frag'], 'downsample'),
      up: createProgram(gl, vert, this.sources['upsample.frag'], 'upsample'),
      composite: createProgram(gl, vert, this.sources['composite.frag'], 'composite')
    };
    this.reduceTarget = createTarget(gl, REDUCE_GRID, REDUCE_GRID, gl.RGBA32F, gl.NEAREST);
    this.reduceBuffer = new Float32Array(REDUCE_GRID * REDUCE_GRID * 4);
    this.nutrientTexture = gl.createTexture();
    this.nutrientLayers = 0;
    this.tapTexture = gl.createTexture();
    this.weightTexture = gl.createTexture();
    this.rebuildSpecies();
    this.resizeSimulation(this.params.size);
    this.resizeView();
  }

  channelDriveArray() {
    const channels = this.params.channels();
    if (!this.driveBuffer || this.driveBuffer.length !== channels) {
      this.driveBuffer = new Float32Array(channels);
    }
    const cd = this.params.mod.channelDrive;
    for (let c = 0; c < channels; c++) this.driveBuffer[c] = cd[c] ?? 0;
    return this.driveBuffer;
  }

  shape() {
    const channels = this.params.channels();
    const layers = Math.ceil(channels / 4);
    return { channels, layers, total: layers + 1 };
  }

  shaped(name, source, extraDefines = {}, outputs = 0) {
    const { channels, layers, total } = this.shape();
    const key = `${name}:${channels}:${layers}:${JSON.stringify(extraDefines)}`;
    if (!this.shapePrograms.has(key)) {
      let src = withDefines(source, { NCH: channels, LAYERS: layers, NUTRIENT_SIZE: NUTRIENT_SIZE, ...extraDefines });
      if (outputs) src = withOutputs(src, total, channels);
      this.shapePrograms.set(key, createProgram(this.gl, this.sources['quad.vert'], src, key));
    }
    return this.shapePrograms.get(key);
  }

  stepProgram(taps, count, rows) {
    return this.shaped('step', this.sources['step.frag'],
      { NTAPS: taps, NK: count, KROWS: rows }, 1);
  }

  uploadKernelTexture(texture, width, height, data) {
    const gl = this.gl;
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA32F, width, height, 0, gl.RGBA, gl.FLOAT, data);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.bindTexture(gl.TEXTURE_2D, null);
  }

  growthArrays() {
    const kernels = this.params.species.kernels;
    const mod = this.params.mod;
    if (!this.growth || this.growth.mu.length !== kernels.length) {
      this.growth = {
        mu: new Float32Array(kernels.length),
        sigma: new Float32Array(kernels.length),
        height: new Float32Array(kernels.length)
      };
    }
    for (let i = 0; i < kernels.length; i++) {
      const k = kernels[i];
      this.growth.mu[i] = Math.min(0.9, Math.max(0.005, k.m + this.params.muShift + mod.mu));
      this.growth.sigma[i] = Math.min(0.3, Math.max(0.002, k.s * this.params.sigmaScale));
      this.growth.height[i] = k.h * this.params.heightScale * mod.height;
    }
    return this.growth;
  }

  rebuildSpecies() {
    if (this.state && this.state.read.layers !== this.shape().total) {
      this.resizeSimulation(this.size);
    }
    const built = buildSpecies(this.params.resolveSpecies());
    this.built = built;
    this.kernelTaps = built.taps;
    this.kernelCount = built.count;
    this.uploadKernelTexture(this.tapTexture, built.taps, 1, built.tapData);
    this.uploadKernelTexture(this.weightTexture, built.taps, built.rows, built.weightData);
    this.stepProgram(built.taps, built.count, built.rows);
  }

  stateFormat() {
    this.precision = 'float32';
    return this.gl.RGBA32F;
  }

  resizeSimulation(size) {
    const gl = this.gl;
    const previous = this.state;
    this.size = size;
    this.stateFormat();
    const total = this.shape().total;
    this.state = {
      read: createLayeredTarget(gl, size, total),
      write: createLayeredTarget(gl, size, total)
    };
    if (previous) {
      destroyTarget(gl, previous.read);
      destroyTarget(gl, previous.write);
    }
    this.clear();
  }

  resizeView() {
    const gl = this.gl;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const scale = this.params.renderScale;
    const width = Math.max(2, Math.round(this.canvas.clientWidth * dpr * scale));
    const height = Math.max(2, Math.round(this.canvas.clientHeight * dpr * scale));
    if (width === this.viewWidth && height === this.viewHeight) return;
    this.viewWidth = width;
    this.viewHeight = height;
    this.canvas.width = width;
    this.canvas.height = height;

    destroyTarget(gl, this.scene);
    this.scene = createTarget(gl, width, height, gl.RGBA16F, gl.LINEAR);
    this.mips.forEach((mip) => destroyTarget(gl, mip));
    this.mips = [];
    let w = Math.max(1, width >> 1);
    let h = Math.max(1, height >> 1);
    for (let i = 0; i < MAX_MIPS; i++) {
      this.mips.push(createTarget(gl, w, h, gl.RGBA16F, gl.LINEAR));
      if (w <= MIN_MIP || h <= MIN_MIP) break;
      w = Math.max(1, w >> 1);
      h = Math.max(1, h >> 1);
    }
  }

  swap() {
    const t = this.state.read;
    this.state.read = this.state.write;
    this.state.write = t;
  }

  clear() {
    const gl = this.gl;
    for (const target of [this.state.read, this.state.write]) {
      bindLayered(gl, target);
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);
    }
    this.generation = 0;
  }

  uploadState(target, layerBuffers) {
    const gl = this.gl;
    gl.bindTexture(gl.TEXTURE_2D_ARRAY, target.texture);
    layerBuffers.forEach((buf, layer) => {
      gl.texSubImage3D(gl.TEXTURE_2D_ARRAY, 0, 0, 0, layer, this.size, this.size, 1,
        gl.RGBA, gl.FLOAT, buf);
    });
    gl.bindTexture(gl.TEXTURE_2D_ARRAY, null);
  }

  randomize() {
    const { channels, layers } = this.shape();
    this.clear();
    const data = seedChannels(this.size, this.params.radius, this.params.seedCoverage,
                              this.params.seedDensity, channels);
    this.uploadState(this.state.read, splitLayers(data, this.size, channels, layers));
    this.generation = 0;
  }

  stamp({ from, to, radius, ringRadius = 0, strength, mode = 0, mix = null }) {
    const gl = this.gl;
    const { program, uniforms } = this.shaped('paint', this.sources['paint.frag'], {}, 1);
    const channels = this.params.channels();
    const channelMix = new Float32Array(channels);
    for (let c = 0; c < channels; c++) channelMix[c] = mix ? (mix[c] ?? mix[c % mix.length]) : 1;
    gl.useProgram(program);
    bindLayered(gl, this.state.write);
    bindTexturesArray(gl, uniforms, [['uState', this.state.read.texture]], ['uState']);
    gl.uniform2i(uniforms.uSize, this.size, this.size);
    gl.uniform2f(uniforms.uFrom, from.x, from.y);
    gl.uniform2f(uniforms.uTo, to.x, to.y);
    gl.uniform1f(uniforms.uRadius, radius);
    gl.uniform1f(uniforms.uRingRadius, ringRadius);
    gl.uniform1f(uniforms.uStrength, strength);
    gl.uniform1i(uniforms.uMode, mode);
    gl.uniform1fv(uniforms.uChannelMix, channelMix);
    gl.uniform1f(uniforms.uSeed, Math.random() * 1000);
    drawQuad(gl);
    this.swap();
  }

  paint(from, to, strength) {
    this.stamp({ from, to, radius: this.params.brushRadius, strength });
  }

  spawnRing(centre, ringRadius, width, strength, mix = null) {
    this.stamp({ from: centre, to: centre, radius: width, ringRadius, strength, mode: 1, mix });
  }

  spawnSeed(centre, scale, strength, mix = null) {
    const R = Math.max(6, Math.round(this.params.radius)) * scale;
    this.spawnRing(centre, R * 2.4, R * 1.2, strength, mix);
    this.spawnRing(centre, R * 0.9, R * 0.9, strength * 0.85, mix);
  }

  seedSolo() {
    this.clear();
    this.spawnSeed({ x: this.size / 2, y: this.size / 2 }, 0.7, 0.95);
  }

  ensureNutrient(layers) {
    const gl = this.gl;
    if (this.nutrientLayers === layers) return;
    gl.bindTexture(gl.TEXTURE_2D_ARRAY, this.nutrientTexture);
    gl.texImage3D(gl.TEXTURE_2D_ARRAY, 0, gl.RGBA32F, NUTRIENT_SIZE, NUTRIENT_SIZE, layers, 0,
      gl.RGBA, gl.FLOAT, new Float32Array(NUTRIENT_SIZE * NUTRIENT_SIZE * 4 * layers));
    gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.bindTexture(gl.TEXTURE_2D_ARRAY, null);
    this.nutrientLayers = layers;
  }

  setNutrient(channelField) {
    const gl = this.gl;
    const { channels, layers } = this.shape();
    this.ensureNutrient(layers);
    const buffers = splitLayers(channelField, NUTRIENT_SIZE, channels, layers);
    gl.bindTexture(gl.TEXTURE_2D_ARRAY, this.nutrientTexture);
    buffers.forEach((buf, layer) => {
      gl.texSubImage3D(gl.TEXTURE_2D_ARRAY, 0, 0, 0, layer, NUTRIENT_SIZE, NUTRIENT_SIZE, 1,
        gl.RGBA, gl.FLOAT, buf);
    });
    gl.bindTexture(gl.TEXTURE_2D_ARRAY, null);
  }

  step(count) {
    const gl = this.gl;
    const built = this.built;
    const { program, uniforms } = this.stepProgram(built.taps, built.count, built.rows);
    gl.useProgram(program);
    gl.uniform2i(uniforms.uSize, this.size, this.size);
    gl.uniform1iv(uniforms.uSrcLayer, built.srcLayer);
    gl.uniform1iv(uniforms.uSrcComp, built.srcComp);
    gl.uniform1iv(uniforms.uDstIdx, built.dst);
    const growth = this.growthArrays();
    gl.uniform1fv(uniforms.uMu, growth.mu);
    gl.uniform1fv(uniforms.uSigma, growth.sigma);
    gl.uniform1fv(uniforms.uH, growth.height);
    gl.uniform1f(uniforms.uDt, 1 / this.params.timescale);
    gl.uniform1f(uniforms.uTrailDecay, this.params.trailDecay);
    gl.uniform1f(uniforms.uNutrientAmount, this.params.mod.nutrient);
    gl.uniform1f(uniforms.uStarve, this.params.mod.starve);
    gl.uniform1fv(uniforms.uChannelDrive, this.channelDriveArray());
    this.ensureNutrient(this.shape().layers);
    for (let i = 0; i < count; i++) {
      bindLayered(gl, this.state.write);
      bindTexturesArray(gl, uniforms, [
        ['uState', this.state.read.texture],
        ['uTaps', this.tapTexture],
        ['uWeights', this.weightTexture],
        ['uNutrient', this.nutrientTexture]
      ], ['uState', 'uNutrient']);
      drawQuad(gl);
      this.swap();
      this.generation++;
    }
  }

  renderScene() {
    const gl = this.gl;
    const { program, uniforms } = this.shaped('render', this.sources['render.frag']);
    gl.useProgram(program);
    bindTarget(gl, this.scene);
    bindTexturesArray(gl, uniforms, [['uState', this.state.read.texture]], ['uState']);
    gl.uniform2i(uniforms.uSize, this.size, this.size);
    gl.uniform2f(uniforms.uPan, this.pan.x, this.pan.y);
    gl.uniform1f(uniforms.uZoom, this.zoom);
    gl.uniform1f(uniforms.uAspect, this.viewWidth / this.viewHeight);
    gl.uniform1i(uniforms.uPalette, this.params.palette);
    gl.uniform3fv(uniforms.uCustomStops, this.params.customStops);
    gl.uniform3fv(uniforms.uCustomPrimaries, this.params.customPrimaries);
    gl.uniform1i(uniforms.uChannels, this.params.channels());
    gl.uniform1f(uniforms.uGlow, this.params.glow * this.params.mod.glow);
    gl.uniform1f(uniforms.uTrailAmount, this.params.trailAmount);
    gl.uniform1f(uniforms.uEdgeAmount, this.params.edgeAmount * this.params.mod.edge);
    gl.uniform1f(uniforms.uContrast, this.params.contrast);
    gl.uniform1f(uniforms.uChannelSep, this.params.channelSep * this.params.mod.separation);
    drawQuad(gl);
  }

  renderBloom() {
    const gl = this.gl;
    const bright = this.programs.bright;
    gl.useProgram(bright.program);
    bindTarget(gl, this.mips[0]);
    bindTextures(gl, bright.uniforms, [['uScene', this.scene.texture]]);
    gl.uniform1f(bright.uniforms.uThreshold, this.params.bloomThreshold);
    gl.uniform1f(bright.uniforms.uKnee, this.params.bloomKnee);
    drawQuad(gl);

    const down = this.programs.down;
    gl.useProgram(down.program);
    for (let i = 1; i < this.mips.length; i++) {
      const source = this.mips[i - 1];
      bindTarget(gl, this.mips[i]);
      bindTextures(gl, down.uniforms, [['uSource', source.texture]]);
      gl.uniform2f(down.uniforms.uTexel, 1 / source.width, 1 / source.height);
      gl.uniform1f(down.uniforms.uKaris, i === 1 ? 1 : 0);
      drawQuad(gl);
    }

    const up = this.programs.up;
    gl.useProgram(up.program);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.ONE, gl.ONE);
    for (let i = this.mips.length - 1; i > 0; i--) {
      const source = this.mips[i];
      bindTarget(gl, this.mips[i - 1]);
      bindTextures(gl, up.uniforms, [['uSource', source.texture]]);
      gl.uniform2f(up.uniforms.uTexel, 1 / source.width, 1 / source.height);
      gl.uniform1f(up.uniforms.uRadius, this.params.bloomRadius);
      drawQuad(gl);
    }
    gl.disable(gl.BLEND);
  }

  composite(time) {
    const gl = this.gl;
    const { program, uniforms } = this.programs.composite;
    gl.useProgram(program);
    bindTarget(gl, null);
    bindTextures(gl, uniforms, [
      ['uScene', this.scene.texture],
      ['uBloom', this.mips[0].texture]
    ]);
    const levels = Math.max(1, this.mips.length - 1);
    gl.uniform1f(uniforms.uBloomIntensity, this.params.bloomIntensity * this.params.mod.bloom / levels);
    gl.uniform1f(uniforms.uDispersion, this.params.dispersion);
    gl.uniform1f(uniforms.uExposure, this.params.exposure * this.params.mod.exposure);
    gl.uniform1f(uniforms.uVignette, this.params.vignette);
    gl.uniform1f(uniforms.uGrain, this.params.grain);
    gl.uniform1f(uniforms.uTonemap, this.params.tonemap);
    gl.uniform1f(uniforms.uTime, time);
    drawQuad(gl);
  }

  draw(time) {
    this.renderScene();
    this.renderBloom();
    this.composite(time);
  }

  reduce() {
    const gl = this.gl;
    const { program, uniforms } = this.shaped('reduce', this.sources['reduce.frag']);
    gl.useProgram(program);
    bindTarget(gl, this.reduceTarget);
    bindTexturesArray(gl, uniforms, [['uState', this.state.read.texture]], ['uState']);
    gl.uniform2i(uniforms.uSize, this.size, this.size);
    gl.uniform1i(uniforms.uBlock, Math.max(1, Math.floor(this.size / REDUCE_GRID)));
    drawQuad(gl);
    gl.readPixels(0, 0, REDUCE_GRID, REDUCE_GRID, gl.RGBA, gl.FLOAT, this.reduceBuffer);
    return this.reduceBuffer;
  }

  screenToField(clientX, clientY) {
    const rect = this.canvas.getBoundingClientRect();
    const nx = (clientX - rect.left) / rect.width;
    const ny = 1 - (clientY - rect.top) / rect.height;
    const aspect = this.viewWidth / this.viewHeight;
    const cx = (nx - 0.5) * aspect;
    const cy = ny - 0.5;
    const u = cx / this.zoom + 0.5 + this.pan.x;
    const v = cy / this.zoom + 0.5 + this.pan.y;
    return { x: u * this.size, y: v * this.size };
  }
}
