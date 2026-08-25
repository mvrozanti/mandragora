#version 300 es
precision highp float;
precision highp int;
precision highp sampler2D;

uniform sampler2D uState;
uniform ivec2 uSize;
uniform vec2 uPan;
uniform float uZoom;
uniform float uAspect;
uniform int uPalette;
uniform int uChannels;
uniform float uGlow;
uniform float uTrailAmount;
uniform float uEdgeAmount;
uniform float uContrast;
uniform float uChannelSep;
uniform vec3 uCustomStops[5];
uniform vec3 uCustomPrimaries[3];

in vec2 vUv;
out vec4 outColor;

vec4 fetchWrapped(ivec2 p) {
  return texelFetch(uState, (p + uSize) % uSize, 0);
}

float peakOf(vec4 s) {
  return uChannels == 1 ? s.r : max(s.r, max(s.g, s.b));
}

vec4 gField;
float gRange;

void sampleField(vec2 uv) {
  vec2 t = fract(uv) * vec2(uSize) - 0.5;
  vec2 f = fract(t);
  ivec2 b = ivec2(floor(t));
  vec4 s00 = fetchWrapped(b);
  vec4 s10 = fetchWrapped(b + ivec2(1, 0));
  vec4 s01 = fetchWrapped(b + ivec2(0, 1));
  vec4 s11 = fetchWrapped(b + ivec2(1, 1));
  vec2 g = f * f * (3.0 - 2.0 * f);
  gField = mix(mix(s00, s10, g.x), mix(s01, s11, g.x), g.y);
  float p00 = peakOf(s00);
  float p10 = peakOf(s10);
  float p01 = peakOf(s01);
  float p11 = peakOf(s11);
  gRange = max(max(p00, p10), max(p01, p11)) - min(min(p00, p10), min(p01, p11));
}

vec3 gradient(float t, vec3 c0, vec3 c1, vec3 c2, vec3 c3, vec3 c4) {
  t = clamp(t, 0.0, 1.0) * 4.0;
  vec3 c = mix(c0, c1, clamp(t, 0.0, 1.0));
  c = mix(c, c2, clamp(t - 1.0, 0.0, 1.0));
  c = mix(c, c3, clamp(t - 2.0, 0.0, 1.0));
  c = mix(c, c4, clamp(t - 3.0, 0.0, 1.0));
  return c;
}

vec3 gradient6(float t, vec3 c0, vec3 c1, vec3 c2, vec3 c3, vec3 c4, vec3 c5) {
  t = clamp(t, 0.0, 1.0) * 5.0;
  vec3 c = mix(c0, c1, clamp(t, 0.0, 1.0));
  c = mix(c, c2, clamp(t - 1.0, 0.0, 1.0));
  c = mix(c, c3, clamp(t - 2.0, 0.0, 1.0));
  c = mix(c, c4, clamp(t - 3.0, 0.0, 1.0));
  c = mix(c, c5, clamp(t - 4.0, 0.0, 1.0));
  return c;
}

vec3 jet(float t) {
  return gradient6(t,
    vec3(0.000, 0.000, 0.000),
    vec3(0.000, 0.000, 0.443),
    vec3(0.000, 0.585, 1.000),
    vec3(0.030, 0.668, 0.000),
    vec3(1.000, 0.727, 0.000),
    vec3(0.668, 0.000, 0.000));
}

vec3 palette(float t) {
  if (uPalette == 6) return jet(t);
  if (uPalette == 5) {
    return gradient(t, uCustomStops[0], uCustomStops[1], uCustomStops[2],
                       uCustomStops[3], uCustomStops[4]);
  }
  if (uPalette == 0) {
    return gradient(t, vec3(0.015, 0.000, 0.035), vec3(0.130, 0.018, 0.170),
                       vec3(0.460, 0.045, 0.260), vec3(0.880, 0.200, 0.430),
                       vec3(1.000, 0.520, 0.700));
  } else if (uPalette == 1) {
    return gradient(t, vec3(0.030, 0.008, 0.000), vec3(0.170, 0.048, 0.008),
                       vec3(0.560, 0.150, 0.020), vec3(0.960, 0.460, 0.120),
                       vec3(1.000, 0.780, 0.420));
  } else if (uPalette == 2) {
    return gradient(t, vec3(0.000, 0.016, 0.045), vec3(0.018, 0.095, 0.200),
                       vec3(0.050, 0.300, 0.560), vec3(0.250, 0.630, 0.900),
                       vec3(0.620, 0.880, 1.000));
  } else if (uPalette == 3) {
    return gradient(t, vec3(0.000, 0.028, 0.012), vec3(0.028, 0.140, 0.055),
                       vec3(0.110, 0.420, 0.160), vec3(0.420, 0.800, 0.450),
                       vec3(0.720, 1.000, 0.700));
  }
  return gradient(t, vec3(0.040, 0.000, 0.090), vec3(0.100, 0.045, 0.450),
                     vec3(0.050, 0.450, 0.600), vec3(0.550, 0.850, 0.350),
                     vec3(1.000, 0.880, 0.520));
}

void channelPrimaries(out vec3 a, out vec3 b, out vec3 c) {
  if (uPalette == 5) {
    a = uCustomPrimaries[0]; b = uCustomPrimaries[1]; c = uCustomPrimaries[2];
  } else if (uPalette == 0) {
    a = vec3(1.00, 0.18, 0.42); b = vec3(0.52, 0.24, 1.00); c = vec3(1.00, 0.68, 0.34);
  } else if (uPalette == 1) {
    a = vec3(1.00, 0.34, 0.06); b = vec3(1.00, 0.80, 0.20); c = vec3(0.88, 0.12, 0.30);
  } else if (uPalette == 2) {
    a = vec3(0.12, 0.52, 1.00); b = vec3(0.18, 0.96, 0.86); c = vec3(0.68, 0.42, 1.00);
  } else if (uPalette == 3) {
    a = vec3(0.32, 1.00, 0.38); b = vec3(0.88, 1.00, 0.22); c = vec3(0.16, 0.78, 0.74);
  } else if (uPalette == 6) {
    a = vec3(0.90, 0.10, 0.05); b = vec3(0.10, 0.80, 0.20); c = vec3(0.05, 0.30, 1.00);
  } else {
    a = vec3(1.00, 0.28, 0.32); b = vec3(0.28, 0.95, 0.45); c = vec3(0.32, 0.54, 1.00);
  }
}

void main() {
  vec2 centered = (vUv - 0.5) * vec2(uAspect, 1.0);
  vec2 uv = centered / uZoom + 0.5 + uPan;
  sampleField(uv);

  vec4 s = gField;
  float value = peakOf(s);
  float trail = s.a;

  vec3 col;
  if (uPalette == 6) {
    float shaped = pow(uChannels == 1 ? value : max(s.r, max(s.g, s.b)), uContrast);
    col = palette(shaped) * step(0.004, shaped);
  } else if (uChannels == 1) {
    float shaped = pow(value, uContrast);
    col = palette(shaped) * (0.10 + 1.05 * shaped);
  } else {
    vec3 shaped = pow(max(s.rgb, 0.0), vec3(uContrast));
    float average = (shaped.r + shaped.g + shaped.b) / 3.0;
    vec3 spread = max(average + (shaped - average) * uChannelSep, 0.0);
    vec3 c0, c1, c2;
    channelPrimaries(c0, c1, c2);
    col = c0 * spread.r + c1 * spread.g + c2 * spread.b;
    col *= 0.62;
    float overlap = min(shaped.r, min(shaped.g, shaped.b));
    col += vec3(1.0, 0.95, 0.90) * overlap * overlap * 0.28;
  }

  float ghost = max(trail - value, 0.0);
  col += palette(0.30) * ghost * ghost * uTrailAmount;

  float rim = gRange * smoothstep(0.03, 0.35, value);
  col += palette(0.80) * rim * uEdgeAmount * 1.6;

  float core = smoothstep(0.72, 1.0, value);
  col += vec3(1.0, 0.95, 0.90) * core * core * 0.12;

  col *= uGlow;
  outColor = vec4(col, 1.0);
}
