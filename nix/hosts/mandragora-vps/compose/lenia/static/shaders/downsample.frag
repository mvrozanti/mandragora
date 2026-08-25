#version 300 es
precision highp float;
precision highp sampler2D;

uniform sampler2D uSource;
uniform vec2 uTexel;
uniform float uKaris;

in vec2 vUv;
out vec4 outColor;

float karisWeight(vec3 c) {
  float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
  return mix(1.0, 1.0 / (1.0 + luma), uKaris);
}

vec3 group(vec3 a, vec3 b, vec3 c, vec3 d) {
  float wa = karisWeight(a), wb = karisWeight(b), wc = karisWeight(c), wd = karisWeight(d);
  return (a * wa + b * wb + c * wc + d * wd) / max(wa + wb + wc + wd, 1e-5);
}

vec3 tap(vec2 o) { return texture(uSource, vUv + o * uTexel).rgb; }

void main() {
  vec3 a = tap(vec2(-2.0,  2.0));
  vec3 b = tap(vec2( 0.0,  2.0));
  vec3 c = tap(vec2( 2.0,  2.0));
  vec3 d = tap(vec2(-2.0,  0.0));
  vec3 e = tap(vec2( 0.0,  0.0));
  vec3 f = tap(vec2( 2.0,  0.0));
  vec3 g = tap(vec2(-2.0, -2.0));
  vec3 h = tap(vec2( 0.0, -2.0));
  vec3 i = tap(vec2( 2.0, -2.0));
  vec3 j = tap(vec2(-1.0,  1.0));
  vec3 k = tap(vec2( 1.0,  1.0));
  vec3 l = tap(vec2(-1.0, -1.0));
  vec3 m = tap(vec2( 1.0, -1.0));

  vec3 result = group(j, k, l, m) * 0.5;
  result += group(a, b, d, e) * 0.125;
  result += group(b, c, e, f) * 0.125;
  result += group(d, e, g, h) * 0.125;
  result += group(e, f, h, i) * 0.125;
  outColor = vec4(result, 1.0);
}
