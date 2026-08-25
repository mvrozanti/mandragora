#version 300 es
precision highp float;
precision highp int;
precision highp sampler2D;

uniform sampler2D uState;
uniform ivec2 uSize;
uniform int uBlock;

out vec4 outColor;

void main() {
  ivec2 cell = ivec2(gl_FragCoord.xy);
  ivec2 base = cell * uBlock;
  vec4 total = vec4(0.0);
  for (int y = 0; y < uBlock; y++) {
    for (int x = 0; x < uBlock; x++) {
      ivec2 q = (base + ivec2(x, y)) % uSize;
      total += texelFetch(uState, q, 0);
    }
  }
  outColor = total / float(uBlock * uBlock);
}
