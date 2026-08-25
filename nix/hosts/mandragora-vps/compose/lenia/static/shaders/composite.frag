#version 300 es
precision highp float;
precision highp sampler2D;

uniform sampler2D uScene;
uniform sampler2D uBloom;
uniform float uBloomIntensity;
uniform float uDispersion;
uniform float uExposure;
uniform float uVignette;
uniform float uGrain;
uniform float uTonemap;
uniform float uTime;

in vec2 vUv;
out vec4 outColor;

float hash(vec2 p) {
  p = fract(p * vec2(443.897, 441.423));
  p += dot(p, p + 19.19);
  return fract(p.x * p.y);
}

vec3 sampleBloom(vec2 uv) {
  vec2 dir = uv - 0.5;
  float k = uDispersion * 0.0035;
  float r = texture(uBloom, uv + dir * k).r;
  float g = texture(uBloom, uv).g;
  float b = texture(uBloom, uv - dir * k).b;
  return vec3(r, g, b);
}

vec3 aces(vec3 x) {
  const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

void main() {
  vec3 scene = texture(uScene, vUv).rgb;
  vec3 bloom = sampleBloom(vUv);
  vec3 color = scene + bloom * uBloomIntensity;

  float d = length(vUv - 0.5);
  color *= mix(1.0, smoothstep(0.95, 0.25, d), uVignette);
  color *= uExposure;

  color = mix(clamp(color, 0.0, 1.0), aces(color), uTonemap);
  color = pow(color, vec3(1.0 / 2.2));

  float n = hash(gl_FragCoord.xy + fract(uTime) * 91.7) - 0.5;
  color += n * uGrain;

  outColor = vec4(color, 1.0);
}
