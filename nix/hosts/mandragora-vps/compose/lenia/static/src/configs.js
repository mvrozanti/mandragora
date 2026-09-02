export const CONFIGS = [
  {
    number: 0,
    name: 'Solitons',
    note: 'travelling creatures on empty black. Stable indefinitely. Onset spawning is off by default — raise it in Audio and it will eventually nucleate colonies.',
    mode: 3,
    species: 'Orbium',
    settings: {
      size: 512, targetDensity: 0.02, densityGain: 0, homeostat: false,
      audioSpawn: 0, audioNutrient: 0, audioChannels: 0, audioTimbre: 0,
      solitonCap: 26, solitonMass: 0.012, solitonCooldown: 320, stepsPerFrame: 2,
      speciesPerTrack: false, paletteFromArt: true,
      trailAmount: 0.5, trailDecay: 0.94, edgeAmount: 0.9,
      bloomIntensity: 1.3, contrast: 1.1, channelSep: 1
    }
  },
  {
    number: 1,
    name: 'Few, large',
    note: 'a handful of big organisms on black — detail per creature is readable',
    species: 'Spectrum 8',
    settings: {
      size: 288, radius: 21, timescale: 16,
      targetDensity: 0.07, densityGain: 1.8,
      audioSpawn: 0, audioNutrient: 0, audioChannels: 0.5, audioTimbre: 2,
      speciesPerTrack: false, paletteFromArt: true, homeostat: true, stepsPerFrame: 2,
      trailAmount: 0.4, trailDecay: 0.93, edgeAmount: 0.8,
      bloomIntensity: 1.2, contrast: 1.25, channelSep: 2.6
    }
  },
  {
    number: 2,
    name: 'Many, small',
    note: 'a swarming population — the motion of the crowd is the signal',
    species: 'Spectrum 8',
    settings: {
      size: 512, radius: 10, timescale: 13,
      targetDensity: 0.13, densityGain: 1.8,
      audioSpawn: 0, audioNutrient: 0, audioChannels: 0.5, audioTimbre: 2,
      speciesPerTrack: false, paletteFromArt: true, homeostat: true, stepsPerFrame: 2,
      trailAmount: 0.3, trailDecay: 0.90, edgeAmount: 0.7,
      bloomIntensity: 1.0, contrast: 1.35, channelSep: 3.0
    }
  },
  {
    number: 3,
    name: 'Full field',
    note: 'edge-to-edge living fabric that the music warps',
    species: 'Spectrum 8',
    settings: {
      size: 512, radius: 14, timescale: 14,
      targetDensity: 0.55, densityGain: 1.0,
      audioSpawn: 0, audioNutrient: 0, audioChannels: 0.5, audioTimbre: 2,
      speciesPerTrack: false, paletteFromArt: true, homeostat: true, stepsPerFrame: 2,
      trailAmount: 0.25, trailDecay: 0.88, edgeAmount: 0.55,
      bloomIntensity: 0.85, contrast: 1.5, channelSep: 3.4
    }
  }
];
