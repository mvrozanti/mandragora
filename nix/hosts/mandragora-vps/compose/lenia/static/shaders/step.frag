#version 300 es
precision highp float;
precision highp int;
precision highp sampler2D;

uniform sampler2D uState;
uniform sampler2D uTaps;
uniform sampler2D uWeights;
uniform ivec2 uSize;
uniform int uSrc[NK];
uniform int uDst[NK];
uniform float uMu[NK];
uniform float uSigma[NK];
uniform float uH[NK];
uniform float uDt;
uniform float uTrailDecay;
uniform sampler2D uNutrient;
uniform float uNutrientAmount;
uniform float uStarve;
uniform vec3 uChannelDrive;

out vec4 outColor;

void main() {
  ivec2 p = ivec2(gl_FragCoord.xy);

  float potential[NK];
  for (int k = 0; k < NK; k++) potential[k] = 0.0;

  for (int i = 0; i < NTAPS; i++) {
    vec2 offset = texelFetch(uTaps, ivec2(i, 0), 0).xy;
    ivec2 q = (p + ivec2(offset) + uSize) % uSize;
    vec4 neighbour = texelFetch(uState, q, 0);
    for (int row = 0; row < KROWS; row++) {
      vec4 w = texelFetch(uWeights, ivec2(i, row), 0);
      for (int lane = 0; lane < 4; lane++) {
        int k = row * 4 + lane;
        if (k < NK) potential[k] += w[lane] * neighbour[uSrc[k]];
      }
    }
  }

  float delta[3];
  delta[0] = 0.0;
  delta[1] = 0.0;
  delta[2] = 0.0;

  for (int k = 0; k < NK; k++) {
    float d = potential[k] - uMu[k];
    float growth = 2.0 * exp(-(d * d) / (2.0 * uSigma[k] * uSigma[k])) - 1.0;
    delta[uDst[k]] += uH[k] * growth;
  }

  vec4 prev = texelFetch(uState, p, 0);
  vec3 food = texture(uNutrient, (vec2(p) + 0.5) / vec2(uSize)).rgb;
  float tissue = smoothstep(0.0, 0.06, max(prev.r, max(prev.g, prev.b)));
  vec3 audioTerm = (food * uNutrientAmount + uChannelDrive - vec3(uStarve)) * tissue;
  vec3 next = clamp(prev.rgb + uDt * (vec3(delta[0], delta[1], delta[2]) + audioTerm), 0.0, 1.0);
  float peak = max(next.r, max(next.g, next.b));
  float trail = max(peak, prev.a * uTrailDecay);
  outColor = vec4(next, trail);
}
