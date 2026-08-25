#version 300 es
precision highp float;
precision highp int;
precision highp sampler2DArray;

uniform sampler2DArray uState;
uniform ivec2 uSize;
uniform int uBlock;

out vec4 outColor;

void main() {
  ivec2 cell = ivec2(gl_FragCoord.xy);
  ivec2 base = cell * uBlock;
  float total = 0.0;
  float lowTotal = 0.0;
  float highTotal = 0.0;
  for (int y = 0; y < uBlock; y++) {
    for (int x = 0; x < uBlock; x++) {
      ivec2 q = (base + ivec2(x, y)) % uSize;
      float peak = 0.0;
      for (int c = 0; c < NCH; c++) peak = max(peak, texelFetch(uState, ivec3(q, c / 4), 0)[c % 4]);
      total += peak;
      lowTotal += texelFetch(uState, ivec3(q, 0), 0).r;
      highTotal += texelFetch(uState, ivec3(q, (NCH - 1) / 4), 0)[(NCH - 1) % 4];
    }
  }
  float n = float(uBlock * uBlock);
  outColor = vec4(total / n, lowTotal / n, highTotal / n, 1.0);
}
