export function describeWebGL() {
  const probe = document.createElement('canvas');
  const report = { context: false, error: '', renderer: '', full: false, half: false, linear: false };
  let gl = null;
  try {
    gl = probe.getContext('webgl2');
  } catch (error) {
    report.error = String(error && error.message ? error.message : error);
  }
  if (!gl) return report;
  report.context = true;
  const info = gl.getExtension('WEBGL_debug_renderer_info');
  report.renderer = info
    ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL)
    : gl.getParameter(gl.RENDERER);
  report.full = !!gl.getExtension('EXT_color_buffer_float');
  report.half = !!gl.getExtension('EXT_color_buffer_half_float');
  report.linear = !!gl.getExtension('OES_texture_float_linear');
  const lose = gl.getExtension('WEBGL_lose_context');
  if (lose) lose.loseContext();
  return report;
}

export function createContext(canvas) {
  const gl = canvas.getContext('webgl2', {
    alpha: false,
    antialias: false,
    depth: false,
    stencil: false,
    premultipliedAlpha: false,
    preserveDrawingBuffer: false,
    powerPreference: 'high-performance'
  });
  if (!gl) {
    throw new Error('This browser did not return a WebGL2 context. Hardware acceleration may be disabled, or WebGL may be blocked for this site.');
  }
  const full = !!gl.getExtension('EXT_color_buffer_float');
  const half = !!gl.getExtension('EXT_color_buffer_half_float');
  gl.getExtension('OES_texture_float_linear');
  if (!full && !half) {
    throw new Error('This WebGL2 driver can render to neither 32-bit nor 16-bit float textures, which the simulation requires.');
  }
  gl.disable(gl.DEPTH_TEST);
  gl.disable(gl.BLEND);
  return { gl, capabilities: { full, half } };
}

export async function loadShaderSources(names, base = 'shaders/') {
  const entries = await Promise.all(names.map(async (name) => {
    const response = await fetch(`${base}${name}`, { cache: 'no-cache' });
    if (!response.ok) throw new Error(`Failed to load shader ${name}: ${response.status}`);
    return [name, await response.text()];
  }));
  return Object.fromEntries(entries);
}

function compile(gl, type, source, label) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    const log = gl.getShaderInfoLog(shader);
    gl.deleteShader(shader);
    throw new Error(`Shader compile failed (${label}):\n${log}`);
  }
  return shader;
}

export function withDefines(source, defines) {
  if (!defines) return source;
  const lines = Object.entries(defines).map(([key, value]) => `#define ${key} ${value}`);
  const marker = source.indexOf('\n');
  return `${source.slice(0, marker + 1)}${lines.join('\n')}\n${source.slice(marker + 1)}`;
}

export function createProgram(gl, vertexSource, fragmentSource, label = 'program') {
  const vertex = compile(gl, gl.VERTEX_SHADER, vertexSource, `${label}.vert`);
  const fragment = compile(gl, gl.FRAGMENT_SHADER, fragmentSource, `${label}.frag`);
  const program = gl.createProgram();
  gl.attachShader(program, vertex);
  gl.attachShader(program, fragment);
  gl.linkProgram(program);
  gl.deleteShader(vertex);
  gl.deleteShader(fragment);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    const log = gl.getProgramInfoLog(program);
    gl.deleteProgram(program);
    throw new Error(`Program link failed (${label}):\n${log}`);
  }
  const uniforms = {};
  const count = gl.getProgramParameter(program, gl.ACTIVE_UNIFORMS);
  for (let i = 0; i < count; i++) {
    const info = gl.getActiveUniform(program, i);
    const name = info.name.replace(/\[0\]$/, '');
    uniforms[name] = gl.getUniformLocation(program, name);
  }
  return { program, uniforms, label };
}

export function createTarget(gl, width, height, internalFormat, filter) {
  const texture = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texStorage2D(gl.TEXTURE_2D, 1, internalFormat, width, height);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filter);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filter);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  const framebuffer = gl.createFramebuffer();
  gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
  gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
  const status = gl.checkFramebufferStatus(gl.FRAMEBUFFER);
  gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  gl.bindTexture(gl.TEXTURE_2D, null);
  if (status !== gl.FRAMEBUFFER_COMPLETE) {
    throw new Error(`Incomplete framebuffer (${width}x${height}): 0x${status.toString(16)}`);
  }
  return { texture, framebuffer, width, height };
}

export function createLayeredTarget(gl, size, layers) {
  const texture = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D_ARRAY, texture);
  gl.texStorage3D(gl.TEXTURE_2D_ARRAY, 1, gl.RGBA32F, size, size, layers);
  gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

  const framebuffer = gl.createFramebuffer();
  gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
  const buffers = [];
  for (let i = 0; i < layers; i++) {
    gl.framebufferTextureLayer(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0 + i, texture, 0, i);
    buffers.push(gl.COLOR_ATTACHMENT0 + i);
  }
  gl.drawBuffers(buffers);
  const status = gl.checkFramebufferStatus(gl.FRAMEBUFFER);
  gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  gl.bindTexture(gl.TEXTURE_2D_ARRAY, null);
  if (status !== gl.FRAMEBUFFER_COMPLETE) {
    throw new Error(`Incomplete layered framebuffer (${size}, ${layers} layers): 0x${status.toString(16)}`);
  }
  return { texture, framebuffer, buffers, width: size, height: size, layers, layered: true };
}

export function bindLayered(gl, target) {
  gl.bindFramebuffer(gl.FRAMEBUFFER, target.framebuffer);
  gl.drawBuffers(target.buffers);
  gl.viewport(0, 0, target.width, target.height);
}

export function withOutputs(source, layers, channels) {
  const decls = [];
  const writes = [];
  for (let l = 0; l < layers; l++) {
    decls.push(`layout(location = ${l}) out vec4 outLayer${l};`);
  }
  for (let l = 0; l < layers - 1; l++) {
    const comps = [0, 1, 2, 3].map((i) => {
      const c = l * 4 + i;
      return c < channels ? `next[${c}]` : '0.0';
    });
    writes.push(`  outLayer${l} = vec4(${comps.join(', ')});`);
  }
  writes.push(`  outLayer${layers - 1} = vec4(trail, 0.0, 0.0, 1.0);`);
  return source
    .replace('//__OUTPUTS__', decls.join('\n'))
    .replace('//__WRITES__', writes.join('\n'));
}

export function destroyTarget(gl, target) {
  if (!target) return;
  gl.deleteTexture(target.texture);
  gl.deleteFramebuffer(target.framebuffer);
}

export function bindTarget(gl, target) {
  if (target) {
    gl.bindFramebuffer(gl.FRAMEBUFFER, target.framebuffer);
    gl.viewport(0, 0, target.width, target.height);
  } else {
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight);
  }
}

export function bindTextures(gl, uniforms, bindings) {
  bindings.forEach(([name, texture], index) => {
    gl.activeTexture(gl.TEXTURE0 + index);
    gl.bindTexture(gl.TEXTURE_2D, texture);
    if (uniforms[name] !== undefined) gl.uniform1i(uniforms[name], index);
  });
}

export function bindTexturesArray(gl, uniforms, bindings, arrayNames = []) {
  const arrays = new Set(arrayNames);
  bindings.forEach(([name, texture], index) => {
    gl.activeTexture(gl.TEXTURE0 + index);
    gl.bindTexture(arrays.has(name) ? gl.TEXTURE_2D_ARRAY : gl.TEXTURE_2D, texture);
    if (uniforms[name] !== undefined) gl.uniform1i(uniforms[name], index);
  });
}

export function drawQuad(gl) {
  gl.drawArrays(gl.TRIANGLES, 0, 3);
}
