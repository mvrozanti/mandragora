#version 300 es
precision highp float;
precision highp sampler2D;

uniform sampler2D uSource;
uniform vec2 uTexel;
uniform float uRadius;

in vec2 vUv;
out vec4 outColor;

vec3 tap(vec2 o) { return texture(uSource, vUv + o * uTexel * uRadius).rgb; }

void main() {
  vec3 sum = tap(vec2(-1.0,  1.0)) * 1.0;
  sum += tap(vec2( 0.0,  1.0)) * 2.0;
  sum += tap(vec2( 1.0,  1.0)) * 1.0;
  sum += tap(vec2(-1.0,  0.0)) * 2.0;
  sum += tap(vec2( 0.0,  0.0)) * 4.0;
  sum += tap(vec2( 1.0,  0.0)) * 2.0;
  sum += tap(vec2(-1.0, -1.0)) * 1.0;
  sum += tap(vec2( 0.0, -1.0)) * 2.0;
  sum += tap(vec2( 1.0, -1.0)) * 1.0;
  outColor = vec4(sum / 16.0, 1.0);
}
