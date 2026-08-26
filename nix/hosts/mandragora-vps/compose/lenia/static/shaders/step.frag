#version 300 es
precision highp float;
precision highp int;
precision highp sampler2D;
precision highp sampler2DArray;

uniform sampler2DArray uState;
uniform sampler2DArray uNutrient;
uniform sampler2D uTaps;
uniform sampler2D uWeights;
uniform ivec2 uSize;
uniform int uSrcLayer[NK];
uniform int uSrcComp[NK];
uniform int uDstIdx[NK];
uniform float uMu[NK];
uniform float uSigma[NK];
uniform float uH[NK];
uniform float uDt;
uniform float uTrailDecay;
uniform float uNutrientAmount;
uniform float uStarve;
uniform float uDensityBias;
uniform float uChannelDrive[NCH];

//__OUTPUTS__

void main() {
  ivec2 p = ivec2(gl_FragCoord.xy);

  float potential[NK];
  for (int k = 0; k < NK; k++) potential[k] = 0.0;

  for (int i = 0; i < NTAPS; i++) {
    vec2 offset = texelFetch(uTaps, ivec2(i, 0), 0).xy;
    ivec2 q = (p + ivec2(offset) + uSize) % uSize;

    vec4 nb[LAYERS];
    for (int l = 0; l < LAYERS; l++) nb[l] = texelFetch(uState, ivec3(q, l), 0);

    for (int row = 0; row < KROWS; row++) {
      vec4 w = texelFetch(uWeights, ivec2(i, row), 0);
      for (int lane = 0; lane < 4; lane++) {
        int k = row * 4 + lane;
        if (k < NK) potential[k] += w[lane] * nb[uSrcLayer[k]][uSrcComp[k]];
      }
    }
  }

  float delta[NCH];
  for (int c = 0; c < NCH; c++) delta[c] = 0.0;

  for (int k = 0; k < NK; k++) {
    float d = potential[k] - uMu[k];
    float bump = exp(-(d * d) / (2.0 * uSigma[k] * uSigma[k]));
    float growth = uH[k] < 0.0 ? bump : 2.0 * bump - 1.0;
    delta[uDstIdx[k]] += uH[k] * growth;
  }

  vec4 prev[LAYERS];
  for (int l = 0; l < LAYERS; l++) prev[l] = texelFetch(uState, ivec3(p, l), 0);
  vec4 food[LAYERS];
  for (int l = 0; l < LAYERS; l++) food[l] = texelFetch(uNutrient, ivec3(p * NUTRIENT_SIZE / uSize, l), 0);

  float peak = 0.0;
  for (int c = 0; c < NCH; c++) peak = max(peak, prev[c / 4][c % 4]);
  float tissue = smoothstep(0.0, 0.06, peak);

  float meanFood = 0.0;
  for (int c = 0; c < NCH; c++) meanFood += food[c / 4][c % 4];
  meanFood /= float(NCH);

  float next[NCH];
  float nextPeak = 0.0;
  for (int c = 0; c < NCH; c++) {
    float base = prev[c / 4][c % 4];
    float shaped = (food[c / 4][c % 4] - meanFood) * uNutrientAmount;
    float audio = (shaped + uChannelDrive[c] - uStarve + uDensityBias) * tissue;
    float v = clamp(base + uDt * (delta[c] + audio), 0.0, 1.0);
    next[c] = v;
    nextPeak = max(nextPeak, v);
  }

  float trail = max(nextPeak, texelFetch(uState, ivec3(p, LAYERS), 0).r * uTrailDecay);

//__WRITES__
}
