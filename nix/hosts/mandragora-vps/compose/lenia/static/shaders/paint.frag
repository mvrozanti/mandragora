#version 300 es
precision highp float;
precision highp int;
precision highp sampler2D;

uniform sampler2D uState;
uniform ivec2 uSize;
uniform vec2 uFrom;
uniform vec2 uTo;
uniform float uRadius;
uniform float uRingRadius;
uniform float uStrength;
uniform float uSeed;
uniform int uMode;
uniform vec3 uChannelMix;

out vec4 outColor;

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
  float denom = max(dot(ab, ab), 1e-6);
  float t = clamp(dot(ap, ab) / denom, 0.0, 1.0);
  return length(ap - ab * t);
}

void main() {
  ivec2 ip = ivec2(gl_FragCoord.xy);
  vec4 prev = texelFetch(uState, ip, 0);
  vec2 p = vec2(ip) + 0.5;

  float falloff;
  if (uMode == 1) {
    float d = abs(length(wrappedDelta(p, uFrom)) - uRingRadius);
    falloff = smoothstep(uRadius, uRadius * 0.15, d);
  } else {
    float d = wrappedSegmentDistance(p, uFrom, uTo);
    falloff = smoothstep(uRadius, uRadius * 0.15, d);
  }

  vec3 grain = vec3(
    0.45 + 0.55 * hash(vec2(ip) + uSeed),
    0.45 + 0.55 * hash(vec2(ip) + uSeed + 17.0),
    0.45 + 0.55 * hash(vec2(ip) + uSeed + 43.0));

  vec3 value = clamp(prev.rgb + uStrength * falloff * grain * uChannelMix, 0.0, 1.0);
  float peak = max(value.r, max(value.g, value.b));
  outColor = vec4(value, max(peak, prev.a));
}
