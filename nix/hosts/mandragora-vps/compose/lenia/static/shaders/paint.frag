#version 300 es
precision highp float;
precision highp int;
precision highp sampler2DArray;

uniform sampler2DArray uState;
uniform ivec2 uSize;
uniform vec2 uFrom;
uniform vec2 uTo;
uniform float uRadius;
uniform float uRingRadius;
uniform float uStrength;
uniform float uSeed;
uniform int uMode;
uniform float uChannelMix[NCH];

//__OUTPUTS__

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

vec2 wrappedDelta(vec2 p, vec2 q) {
  vec2 field = vec2(uSize);
  vec2 d = p - q;
  return d - field * floor(d / field + 0.5);
}

float wrappedSegmentDistance(vec2 p, vec2 a, vec2 b) {
  vec2 field = vec2(uSize);
  vec2 ab = b - a;
  ab -= field * floor(ab / field + 0.5);
  vec2 ap = wrappedDelta(p, a);
  float t = clamp(dot(ap, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
  return length(ap - ab * t);
}

void main() {
  ivec2 ip = ivec2(gl_FragCoord.xy);
  vec2 p = vec2(ip) + 0.5;

  float falloff;
  if (uMode == 1) {
    float d = abs(length(wrappedDelta(p, uFrom)) - uRingRadius);
    falloff = smoothstep(uRadius, uRadius * 0.15, d);
  } else {
    falloff = smoothstep(uRadius, uRadius * 0.15, wrappedSegmentDistance(p, uFrom, uTo));
  }

  vec4 prev[LAYERS];
  for (int l = 0; l < LAYERS; l++) prev[l] = texelFetch(uState, ivec3(ip, l), 0);

  float next[NCH];
  float peak = 0.0;
  for (int c = 0; c < NCH; c++) {
    float grain = 0.45 + 0.55 * hash(vec2(ip) + uSeed + float(c) * 17.0);
    float v = clamp(prev[c / 4][c % 4] + uStrength * falloff * grain * uChannelMix[c], 0.0, 1.0);
    next[c] = v;
    peak = max(peak, v);
  }
  float trail = max(peak, texelFetch(uState, ivec3(ip, LAYERS), 0).r);

//__WRITES__
}
