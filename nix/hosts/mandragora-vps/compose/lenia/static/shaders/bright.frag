#version 300 es
precision highp float;
precision highp sampler2D;

uniform sampler2D uScene;
uniform float uThreshold;
uniform float uKnee;

in vec2 vUv;
out vec4 outColor;

void main() {
  vec3 c = texture(uScene, vUv).rgb;
  float brightness = max(c.r, max(c.g, c.b));
  float knee = max(uKnee, 1e-4);
  float soft = clamp(brightness - uThreshold + knee, 0.0, 2.0 * knee);
  soft = soft * soft / (4.0 * knee);
  float contribution = max(soft, brightness - uThreshold) / max(brightness, 1e-5);
  outColor = vec4(c * contribution, 1.0);
}
