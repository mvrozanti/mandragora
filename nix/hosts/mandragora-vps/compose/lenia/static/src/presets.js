import { singleKernel, spectralSpecies } from './species.js';

export const CLASSIC = [
  singleKernel('Orbium', 'canonical single-ring Lenia; gliders and soft cell division',
    13, 10, 0.15, 0.017, [1]),
  singleKernel('Nebula', 'three-ring kernel; slow drifting filament clouds',
    16, 10, 0.26, 0.036, [1, 0.6667, 0.3333]),
  singleKernel('Coral', 'branching growth that thickens into reef structure',
    13, 10, 0.31, 0.048, [1, 0.75]),
  singleKernel('Filament', 'hollow ring kernel; long threads and travelling kinks',
    20, 12, 0.2, 0.028, [0.5, 1, 0.6667]),
  singleKernel('Plankton', 'small radius, fast clock; dense swarming solitons',
    10, 8, 0.14, 0.014, [1]),
  singleKernel('Foam', 'wide tolerance; filling filmy membranes with dark voids',
    14, 10, 0.35, 0.055, [1, 1, 0.3333]),
  singleKernel('Ember', 'narrow tolerance; sparse flickering cores over open dark',
    12, 12, 0.18, 0.014, [1, 0.5])
];

export const DISCOVERED = [
  {
    name: 'Medusa',
    note: 'found by parameter search — 18 bodies, patchiness 2.08, activity 0.423',
    channels: 3, R: 11, T: 13,
    kernels: [
      { src: 0, dst: 0, r: 0.678, b: [1], m: 0.4468, s: 0.0862, h: 0.235 },
      { src: 1, dst: 0, r: 0.982, b: [0.5, 1, 0.25], m: 0.3351, s: 0.1749, h: 0.805 },
      { src: 2, dst: 0, r: 0.468, b: [0.5, 1, 0.5], m: 0.052, s: 0.179, h: 0.308 },
      { src: 0, dst: 1, r: 0.839, b: [1, 0.25], m: 0.2129, s: 0.0907, h: 0.513 },
      { src: 1, dst: 2, r: 0.888, b: [1], m: 0.4525, s: 0.159, h: 0.402 },
      { src: 2, dst: 0, r: 0.729, b: [0.75, 0.75, 1], m: 0.4039, s: 0.0535, h: 0.684 },
      { src: 0, dst: 0, r: 0.988, b: [1, 0.5, 0.5], m: 0.439, s: 0.123, h: 0.087 },
      { src: 1, dst: 0, r: 0.73, b: [1, 0.75], m: 0.4696, s: 0.0519, h: 0.574 },
      { src: 2, dst: 0, r: 0.791, b: [1], m: 0.4477, s: 0.0724, h: 0.596 }
    ]
  },
  {
    name: 'Vermis',
    note: 'found by parameter search — 36 bodies, patchiness 1.93, activity 0.079',
    channels: 3, R: 15, T: 12,
    kernels: [
      { src: 0, dst: 2, r: 0.635, b: [0.25, 1], m: 0.5638, s: 0.0225, h: 0.058 },
      { src: 1, dst: 0, r: 0.473, b: [1], m: 0.2717, s: 0.1082, h: 0.201 },
      { src: 2, dst: 2, r: 0.745, b: [0.25, 1, 1], m: 0.551, s: 0.1416, h: 0.782 },
      { src: 0, dst: 2, r: 0.614, b: [0.25, 1, 0.25], m: 0.4139, s: 0.0548, h: 0.699 },
      { src: 1, dst: 2, r: 0.58, b: [0.5, 1], m: 0.387, s: 0.0427, h: 0.656 },
      { src: 2, dst: 2, r: 0.574, b: [1], m: 0.1229, s: 0.1378, h: 0.506 },
      { src: 0, dst: 1, r: 0.783, b: [0.75, 0.5, 1], m: 0.4587, s: 0.0213, h: 0.324 },
      { src: 1, dst: 1, r: 0.753, b: [1], m: 0.0846, s: 0.1303, h: 0.398 },
      { src: 2, dst: 1, r: 0.974, b: [0.75, 1, 0.25], m: 0.1385, s: 0.0767, h: 0.313 }
    ]
  },
  {
    name: 'Radiolaria',
    note: 'found by parameter search — 59 bodies, patchiness 1.37, activity 0.577',
    channels: 3, R: 14, T: 12,
    kernels: [
      { src: 0, dst: 2, r: 0.975, b: [1, 0.75], m: 0.1701, s: 0.0616, h: 0.407 },
      { src: 1, dst: 1, r: 0.893, b: [1], m: 0.0626, s: 0.1148, h: 0.491 },
      { src: 2, dst: 1, r: 0.398, b: [1, 0.5], m: 0.4628, s: 0.1225, h: 0.808 },
      { src: 0, dst: 2, r: 0.979, b: [1, 0.25, 1], m: 0.1568, s: 0.1633, h: 0.455 },
      { src: 1, dst: 0, r: 0.647, b: [1], m: 0.1558, s: 0.0223, h: 0.82 },
      { src: 2, dst: 2, r: 0.615, b: [1, 0.5], m: 0.2283, s: 0.0731, h: 0.165 },
      { src: 0, dst: 2, r: 0.523, b: [0.75, 0.5, 1], m: 0.4138, s: 0.1783, h: 0.365 },
      { src: 1, dst: 1, r: 0.569, b: [1, 0.5, 1], m: 0.0697, s: 0.1578, h: 0.278 },
      { src: 2, dst: 2, r: 0.834, b: [0.5, 1], m: 0.4133, s: 0.1005, h: 0.231 }
    ]
  },
  {
    name: 'Volvox',
    note: 'found by parameter search — 20 bodies, patchiness 1.99, activity 0.582',
    channels: 3, R: 14, T: 13,
    kernels: [
      { src: 0, dst: 0, r: 0.468, b: [0.25, 1, 0.75], m: 0.3664, s: 0.0563, h: 0.335 },
      { src: 1, dst: 0, r: 0.65, b: [0.5, 1, 0.25], m: 0.4145, s: 0.1223, h: 0.802 },
      { src: 2, dst: 2, r: 0.544, b: [0.75, 1], m: 0.2189, s: 0.009, h: 0.525 },
      { src: 0, dst: 2, r: 0.999, b: [1, 1], m: 0.3818, s: 0.1026, h: 0.438 },
      { src: 1, dst: 2, r: 0.41, b: [1, 0.25], m: 0.3155, s: 0.1765, h: 0.635 },
      { src: 2, dst: 2, r: 0.487, b: [1, 0.5], m: 0.2995, s: 0.0627, h: 0.417 },
      { src: 0, dst: 2, r: 0.746, b: [1], m: 0.144, s: 0.1597, h: 0.463 },
      { src: 1, dst: 1, r: 0.764, b: [1, 0.75], m: 0.1713, s: 0.0798, h: 0.274 },
      { src: 2, dst: 1, r: 0.74, b: [0.75, 1, 0.75], m: 0.3484, s: 0.1041, h: 0.584 }
    ]
  },
  {
    name: 'Spawn',
    note: 'found by parameter search — 30 bodies, patchiness 1.75, activity 0.162',
    channels: 3, R: 16, T: 12,
    kernels: [
      { src: 0, dst: 2, r: 0.734, b: [0.75, 1, 0.75], m: 0.3596, s: 0.0364, h: 0.166 },
      { src: 1, dst: 1, r: 0.675, b: [1, 0.5], m: 0.4459, s: 0.0292, h: 0.419 },
      { src: 2, dst: 1, r: 0.747, b: [1], m: 0.4501, s: 0.0761, h: 0.115 },
      { src: 0, dst: 0, r: 0.654, b: [1], m: 0.3612, s: 0.1625, h: 0.392 },
      { src: 1, dst: 0, r: 0.62, b: [1, 1, 0.75], m: 0.4035, s: 0.1393, h: 0.514 },
      { src: 2, dst: 1, r: 0.959, b: [1], m: 0.2731, s: 0.1167, h: 0.591 },
      { src: 0, dst: 2, r: 0.657, b: [1], m: 0.2683, s: 0.1156, h: 0.156 },
      { src: 1, dst: 2, r: 0.686, b: [1], m: 0.2534, s: 0.1132, h: 0.566 },
      { src: 2, dst: 0, r: 0.727, b: [1], m: 0.1375, s: 0.0921, h: 0.049 }
    ]
  },
  {
    name: 'Nacre',
    note: 'found by parameter search — 23 bodies, patchiness 1.71, activity 0.175',
    channels: 3, R: 12, T: 13,
    kernels: [
      { src: 0, dst: 1, r: 0.379, b: [1], m: 0.0723, s: 0.0068, h: 0.392 },
      { src: 1, dst: 2, r: 0.884, b: [0.5, 1], m: 0.4008, s: 0.027, h: 0.827 },
      { src: 2, dst: 0, r: 0.734, b: [0.25, 1, 0.5], m: 0.1796, s: 0.135, h: 0.121 },
      { src: 0, dst: 0, r: 1, b: [1, 0.75], m: 0.4799, s: 0.147, h: 0.621 },
      { src: 1, dst: 1, r: 0.695, b: [0.75, 1], m: 0.251, s: 0.1199, h: 0.522 },
      { src: 2, dst: 0, r: 0.766, b: [1, 0.5, 0.25], m: 0.4926, s: 0.2002, h: 0.683 },
      { src: 0, dst: 1, r: 0.968, b: [1, 0.25], m: 0.3754, s: 0.1852, h: 0.458 },
      { src: 1, dst: 2, r: 0.851, b: [1], m: 0.1765, s: 0.1816, h: 0.661 },
      { src: 2, dst: 0, r: 0.797, b: [0.75, 0.75, 1], m: 0.1566, s: 0.1037, h: 0.838 }
    ]
  },
  {
    name: 'Diatom',
    note: 'found by parameter search — 21 bodies, patchiness 2.00, activity 0.113',
    channels: 3, R: 12, T: 10,
    kernels: [
      { src: 0, dst: 1, r: 0.35, b: [0.25, 1], m: 0.1051, s: 0.0555, h: 0.592 },
      { src: 1, dst: 1, r: 0.414, b: [1, 0.5, 1], m: 0.4596, s: 0.0228, h: 0.747 },
      { src: 2, dst: 0, r: 0.713, b: [1], m: 0.2058, s: 0.159, h: 0.471 },
      { src: 0, dst: 1, r: 0.386, b: [1], m: 0.0702, s: 0.1742, h: 0.394 },
      { src: 1, dst: 1, r: 0.61, b: [1, 0.5], m: 0.3654, s: 0.1537, h: 0.68 },
      { src: 2, dst: 1, r: 0.516, b: [0.75, 1], m: 0.3303, s: 0.1686, h: 0.209 },
      { src: 0, dst: 2, r: 0.816, b: [1], m: 0.1197, s: 0.0493, h: 0.656 },
      { src: 1, dst: 1, r: 0.874, b: [1, 0.5], m: 0.2749, s: 0.0833, h: 0.946 },
      { src: 2, dst: 2, r: 0.41, b: [1], m: 0.4378, s: 0.1583, h: 0.943 }
    ]
  },
  {
    name: 'Cilia',
    note: 'found by parameter search — 17 bodies, patchiness 2.03, activity 0.127',
    channels: 3, R: 15, T: 13,
    kernels: [
      { src: 0, dst: 1, r: 0.436, b: [1, 0.75, 0.25], m: 0.246, s: 0.1366, h: 0.886 },
      { src: 1, dst: 2, r: 0.48, b: [1, 0.25], m: 0.4714, s: 0.1646, h: 0.927 },
      { src: 2, dst: 1, r: 0.768, b: [1, 1, 0.75], m: 0.0522, s: 0.1368, h: 0.455 },
      { src: 0, dst: 1, r: 0.455, b: [1], m: 0.4748, s: 0.1645, h: 0.112 },
      { src: 1, dst: 2, r: 0.612, b: [1], m: 0.2059, s: 0.0698, h: 0.746 },
      { src: 2, dst: 0, r: 0.641, b: [1, 0.25, 0.5], m: 0.419, s: 0.1554, h: 0.24 },
      { src: 0, dst: 2, r: 0.596, b: [1], m: 0.3129, s: 0.0482, h: 0.753 },
      { src: 1, dst: 1, r: 0.868, b: [1], m: 0.4486, s: 0.0765, h: 0.351 },
      { src: 2, dst: 2, r: 0.559, b: [1, 0.5], m: 0.1113, s: 0.1036, h: 0.617 }
    ]
  }
];

export const SPECTRAL = [
  {
    name: 'Spectrum 8',
    note: 'searched over 8 bands — holds 0.24 occupancy at 760 steps, 171 bodies, patchiness 0.88',
    channels: 8, R: 17, T: 18,
    kernels: [
      { src: 0, dst: 0, r: 1, b: [1], m: 0.1028, s: 0.0399, h: 0.4376 },
      { src: 1, dst: 1, r: 0.936, b: [1], m: 0.1206, s: 0.0377, h: 0.4376 },
      { src: 2, dst: 2, r: 0.871, b: [1], m: 0.1384, s: 0.0356, h: 0.4376 },
      { src: 3, dst: 3, r: 0.807, b: [1], m: 0.1562, s: 0.0334, h: 0.4376 },
      { src: 4, dst: 4, r: 0.743, b: [1], m: 0.1741, s: 0.0313, h: 0.4376 },
      { src: 5, dst: 5, r: 0.679, b: [1], m: 0.1919, s: 0.0291, h: 0.4376 },
      { src: 6, dst: 6, r: 0.614, b: [1], m: 0.2097, s: 0.027, h: 0.4376 },
      { src: 7, dst: 7, r: 0.55, b: [1], m: 0.2275, s: 0.0248, h: 0.4376 },
      { src: 0, dst: 1, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0954 },
      { src: 0, dst: 7, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.5973 },
      { src: 1, dst: 2, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0954 },
      { src: 1, dst: 0, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.5973 },
      { src: 2, dst: 3, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0954 },
      { src: 2, dst: 1, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.5973 },
      { src: 3, dst: 4, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0954 },
      { src: 3, dst: 2, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.5973 },
      { src: 4, dst: 5, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0954 },
      { src: 4, dst: 3, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.5973 },
      { src: 5, dst: 6, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0954 },
      { src: 5, dst: 4, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.5973 },
      { src: 6, dst: 7, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0954 },
      { src: 6, dst: 5, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.5973 },
      { src: 7, dst: 0, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0954 },
      { src: 7, dst: 6, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.5973 }
    ]
  },
  {
    name: 'Spectrum · drift 8',
    note: 'searched over 8 bands — holds 0.23 occupancy at 760 steps, 169 bodies, patchiness 0.82',
    channels: 8, R: 15, T: 15,
    kernels: [
      { src: 0, dst: 0, r: 1, b: [1], m: 0.1059, s: 0.0324, h: 0.6111 },
      { src: 1, dst: 1, r: 0.936, b: [1], m: 0.1091, s: 0.0298, h: 0.6111 },
      { src: 2, dst: 2, r: 0.871, b: [1], m: 0.1122, s: 0.0272, h: 0.6111 },
      { src: 3, dst: 3, r: 0.807, b: [1], m: 0.1153, s: 0.0246, h: 0.6111 },
      { src: 4, dst: 4, r: 0.743, b: [1], m: 0.1184, s: 0.022, h: 0.6111 },
      { src: 5, dst: 5, r: 0.679, b: [1], m: 0.1215, s: 0.0194, h: 0.6111 },
      { src: 6, dst: 6, r: 0.614, b: [1], m: 0.1247, s: 0.0168, h: 0.6111 },
      { src: 7, dst: 7, r: 0.55, b: [1], m: 0.1278, s: 0.0142, h: 0.6111 },
      { src: 0, dst: 1, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0719 },
      { src: 0, dst: 7, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.392 },
      { src: 1, dst: 2, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0719 },
      { src: 1, dst: 0, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.392 },
      { src: 2, dst: 3, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0719 },
      { src: 2, dst: 1, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.392 },
      { src: 3, dst: 4, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0719 },
      { src: 3, dst: 2, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.392 },
      { src: 4, dst: 5, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0719 },
      { src: 4, dst: 3, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.392 },
      { src: 5, dst: 6, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0719 },
      { src: 5, dst: 4, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.392 },
      { src: 6, dst: 7, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0719 },
      { src: 6, dst: 5, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.392 },
      { src: 7, dst: 0, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0719 },
      { src: 7, dst: 6, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.392 }
    ]
  },
  {
    name: 'Spectrum · dense 8',
    note: 'searched over 8 bands — holds 0.19 occupancy at 760 steps, 134 bodies, patchiness 0.67',
    channels: 8, R: 14, T: 9,
    kernels: [
      { src: 0, dst: 0, r: 1, b: [1], m: 0.105, s: 0.0364, h: 0.3318 },
      { src: 1, dst: 1, r: 0.936, b: [1], m: 0.116, s: 0.0327, h: 0.3318 },
      { src: 2, dst: 2, r: 0.871, b: [1], m: 0.127, s: 0.029, h: 0.3318 },
      { src: 3, dst: 3, r: 0.807, b: [1], m: 0.1381, s: 0.0254, h: 0.3318 },
      { src: 4, dst: 4, r: 0.743, b: [1], m: 0.1491, s: 0.0217, h: 0.3318 },
      { src: 5, dst: 5, r: 0.679, b: [1], m: 0.1601, s: 0.018, h: 0.3318 },
      { src: 6, dst: 6, r: 0.614, b: [1], m: 0.1711, s: 0.0143, h: 0.3318 },
      { src: 7, dst: 7, r: 0.55, b: [1], m: 0.1821, s: 0.0107, h: 0.3318 },
      { src: 0, dst: 1, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.134 },
      { src: 0, dst: 7, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.4233 },
      { src: 1, dst: 2, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.134 },
      { src: 1, dst: 0, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.4233 },
      { src: 2, dst: 3, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.134 },
      { src: 2, dst: 1, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.4233 },
      { src: 3, dst: 4, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.134 },
      { src: 3, dst: 2, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.4233 },
      { src: 4, dst: 5, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.134 },
      { src: 4, dst: 3, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.4233 },
      { src: 5, dst: 6, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.134 },
      { src: 5, dst: 4, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.4233 },
      { src: 6, dst: 7, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.134 },
      { src: 6, dst: 5, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.4233 },
      { src: 7, dst: 0, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.134 },
      { src: 7, dst: 6, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.4233 }
    ]
  },
  {
    name: 'Spectrum · sparse 8',
    note: 'searched over 8 bands — holds 0.24 occupancy at 760 steps, 170 bodies, patchiness 0.79',
    channels: 8, R: 17, T: 19,
    kernels: [
      { src: 0, dst: 0, r: 1, b: [1], m: 0.1285, s: 0.0347, h: 0.4663 },
      { src: 1, dst: 1, r: 0.936, b: [1], m: 0.1372, s: 0.0317, h: 0.4663 },
      { src: 2, dst: 2, r: 0.871, b: [1], m: 0.1459, s: 0.0287, h: 0.4663 },
      { src: 3, dst: 3, r: 0.807, b: [1], m: 0.1546, s: 0.0258, h: 0.4663 },
      { src: 4, dst: 4, r: 0.743, b: [1], m: 0.1633, s: 0.0228, h: 0.4663 },
      { src: 5, dst: 5, r: 0.679, b: [1], m: 0.1721, s: 0.0198, h: 0.4663 },
      { src: 6, dst: 6, r: 0.614, b: [1], m: 0.1808, s: 0.0168, h: 0.4663 },
      { src: 7, dst: 7, r: 0.55, b: [1], m: 0.1895, s: 0.0139, h: 0.4663 },
      { src: 0, dst: 1, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0394 },
      { src: 0, dst: 7, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.5291 },
      { src: 1, dst: 2, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0394 },
      { src: 1, dst: 0, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.5291 },
      { src: 2, dst: 3, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0394 },
      { src: 2, dst: 1, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.5291 },
      { src: 3, dst: 4, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0394 },
      { src: 3, dst: 2, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.5291 },
      { src: 4, dst: 5, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0394 },
      { src: 4, dst: 3, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.5291 },
      { src: 5, dst: 6, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0394 },
      { src: 5, dst: 4, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.5291 },
      { src: 6, dst: 7, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0394 },
      { src: 6, dst: 5, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.5291 },
      { src: 7, dst: 0, r: 0.85, b: [1, 0.4], m: 0.2, s: 0.045, h: 0.0394 },
      { src: 7, dst: 6, r: 0.45, b: [1], m: 0.16, s: 0.035, h: -0.5291 }
    ]
  }
];

export const PRESETS = [...CLASSIC, ...DISCOVERED, ...SPECTRAL];

export const PALETTES = [
  { name: 'Magenta Deep', accent: '#e0567f' },
  { name: 'Ember', accent: '#e8913f' },
  { name: 'Abyss', accent: '#4f9ee0' },
  { name: 'Chlorophyll', accent: '#6fc98a' },
  { name: 'Spectral', accent: '#8fa4ff' },
  { name: 'Album art', accent: '#e0567f' },
  { name: 'Jet — specimen', accent: '#ff9a3d' }
];

export const ART_PALETTE = 5;

export const GRID_SIZES = [128, 192, 256, 384, 512, 768, 1024];

export const DEFAULTS = {
  mode: 1,
  patch: '',
  bands: 8,
  preset: 0,
  size: 512,
  stepsPerFrame: 1,
  palette: 0,
  glow: 1.0,
  contrast: 1.30,
  channelSep: 2.2,
  trailDecay: 0.90,
  trailAmount: 0.35,
  edgeAmount: 0.7,
  bloomIntensity: 1.1,
  bloomThreshold: 0.70,
  bloomKnee: 0.25,
  bloomRadius: 1.4,
  dispersion: 0.35,
  exposure: 1.0,
  vignette: 0.5,
  grain: 0.012,
  brushRadius: 26,
  brushStrength: 0.9,
  seedCoverage: 0.30,
  seedDensity: 0.55,
  renderScale: 1,
  precision: 'float32',
  audioEnabled: true,
  audioDrive: 1,
  audioBass: 0.6,
  audioMid: 0.7,
  audioTreble: 0.6,
  audioSpawn: 0.45,
  audioNutrient: 1.1,
  audioChannels: 0.9,
  homeostat: true,
  targetDensity: 0.20,
  densityGain: 0.9,
  audioStarve: 0.35,
  tonemap: 1,
  paletteFromArt: true,
  speciesPerTrack: true,
  artAccent: null
};
