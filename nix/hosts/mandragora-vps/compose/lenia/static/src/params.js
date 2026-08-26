import { cloneSpecies } from './species.js';
import { DEFAULTS } from './presets.js';

export function createParams(species, overrides = {}) {
  const params = { ...DEFAULTS, ...overrides };
  params.species = cloneSpecies(species);
  params.radius = params.species.R;
  params.timescale = params.species.T;
  params.muShift = 0;
  params.sigmaScale = 1;
  params.heightScale = 1;
  params.customStops = new Float32Array([
    0.015, 0.000, 0.035, 0.130, 0.018, 0.170, 0.460, 0.045, 0.260,
    0.880, 0.200, 0.430, 1.000, 0.520, 0.700
  ]);
  params.customPrimaries = new Float32Array([
    1.00, 0.18, 0.42, 0.52, 0.24, 1.00, 1.00, 0.68, 0.34
  ]);
  params.mod = { mu: 0, height: 1, glow: 1, bloom: 1, separation: 1, edge: 1, exposure: 1, nutrient: 0, starve: 0, density: 0, channelDrive: [0, 0, 0] };
  params.resetMod = () => Object.assign(params.mod,
    { mu: 0, height: 1, glow: 1, bloom: 1, separation: 1, edge: 1, exposure: 1, nutrient: 0, starve: 0, density: 0 });
  params.mod.channelDrive = [0, 0, 0];

  params.channels = () => params.species.channels;
  params.resolveSpecies = () => ({
    R: Math.max(4, Math.round(params.radius)),
    kernels: params.species.kernels.map((k) => ({
      ...k,
      m: Math.min(0.9, Math.max(0.005, k.m + params.muShift)),
      s: Math.min(0.3, Math.max(0.002, k.s * params.sigmaScale)),
      h: k.h * params.heightScale
    }))
  });

  params.adopt = (next) => {
    params.species = cloneSpecies(next);
    params.radius = next.R;
    params.timescale = next.T;
    params.muShift = 0;
    params.sigmaScale = 1;
    params.heightScale = 1;
  params.customStops = new Float32Array([
    0.015, 0.000, 0.035, 0.130, 0.018, 0.170, 0.460, 0.045, 0.260,
    0.880, 0.200, 0.430, 1.000, 0.520, 0.700
  ]);
  params.customPrimaries = new Float32Array([
    1.00, 0.18, 0.42, 0.52, 0.24, 1.00, 1.00, 0.68, 0.34
  ]);
  params.mod = { mu: 0, height: 1, glow: 1, bloom: 1, separation: 1, edge: 1, exposure: 1, nutrient: 0, starve: 0, density: 0, channelDrive: [0, 0, 0] };
  params.resetMod = () => Object.assign(params.mod,
    { mu: 0, height: 1, glow: 1, bloom: 1, separation: 1, edge: 1, exposure: 1, nutrient: 0, starve: 0, density: 0 });
  params.mod.channelDrive = [0, 0, 0];
  };

  return params;
}
