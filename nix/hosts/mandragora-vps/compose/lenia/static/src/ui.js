function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function formatValue(value, step) {
  const decimals = step >= 1 ? 0 : String(step).split('.')[1]?.length ?? 2;
  return value.toFixed(decimals);
}

export class ControlPanel {
  constructor(root, params, onChange) {
    this.root = root;
    this.params = params;
    this.onChange = onChange;
    this.controls = new Map();
  }

  group(title, hint) {
    const section = element('section', 'group');
    const header = element('button', 'group-head');
    header.type = 'button';
    header.append(element('span', 'group-title', title));
    header.append(element('span', 'group-mark'));
    const body = element('div', 'group-body');
    if (hint) body.append(element('p', 'group-hint', hint));
    header.addEventListener('click', () => section.classList.toggle('collapsed'));
    section.append(header, body);
    this.root.append(section);
    this.currentBody = body;
    return this;
  }

  slider(key, label, min, max, step, options = {}) {
    const row = element('label', 'control');
    row.dataset.key = key;
    const head = element('div', 'control-head');
    head.append(element('span', 'control-label', label));
    const readout = element('span', 'control-value', formatValue(this.params[key], step));
    head.append(readout);
    const input = element('input', 'slider');
    input.type = 'range';
    input.min = min;
    input.max = max;
    input.step = step;
    input.value = this.params[key];
    input.addEventListener('input', () => {
      const value = parseFloat(input.value);
      this.params[key] = value;
      readout.textContent = formatValue(value, step);
      this.onChange(key, value, options);
    });
    row.append(head, input);
    this.currentBody.append(row);
    this.controls.set(key, { input, readout, step });
    return this;
  }

  choice(key, label, items, options = {}) {
    const row = element('label', 'control');
    row.dataset.key = key;
    const head = element('div', 'control-head');
    head.append(element('span', 'control-label', label));
    row.append(head);
    const select = element('select', 'select');
    items.forEach((item, index) => {
      const option = element('option', null, item.label ?? item);
      option.value = item.value ?? index;
      select.append(option);
    });
    select.value = this.params[key];
    select.addEventListener('change', () => {
      const value = isNaN(Number(select.value)) ? select.value : Number(select.value);
      this.params[key] = value;
      this.onChange(key, value, options);
    });
    row.append(select);
    this.currentBody.append(row);
    this.controls.set(key, { input: select });
    return this;
  }

  toggle(key, label, options = {}) {
    const row = element('label', 'control toggle-row');
    row.dataset.key = key;
    const text = element('span', 'control-label', label);
    const input = element('input', 'toggle-input');
    input.type = 'checkbox';
    input.checked = !!this.params[key];
    row.classList.toggle('on', input.checked);
    const track = element('span', 'toggle-track');
    track.append(element('span', 'toggle-knob'));
    input.addEventListener('change', () => {
      this.params[key] = input.checked;
      row.classList.toggle('on', input.checked);
      this.onChange(key, input.checked, options);
    });
    row.append(text, input, track);
    this.currentBody.append(row);
    this.controls.set(key, { input, row, kind: 'toggle' });
    return this;
  }

  readout(id, initial = '') {
    const line = element('p', 'group-readout', initial);
    line.id = id;
    this.currentBody.append(line);
    return this;
  }

  meter(id, height = 26) {
    const canvas = element('canvas', 'meter');
    canvas.id = id;
    canvas.style.height = `${height}px`;
    this.currentBody.append(canvas);
    return this;
  }

  swatches(id) {
    const row = element('div', 'swatches');
    row.id = id;
    this.currentBody.append(row);
    return this;
  }

  repopulate(key, items) {
    const control = this.controls.get(key);
    if (!control) return;
    const select = control.input;
    select.textContent = '';
    items.forEach((item, index) => {
      const option = element('option', null, item.label ?? item);
      option.value = item.value ?? index;
      select.append(option);
    });
    select.value = this.params[key];
  }

  actions(items) {
    const row = element('div', 'actions');
    items.forEach(({ label, key, hint }) => {
      const button = element('button', 'action', label);
      button.type = 'button';
      if (hint) button.title = hint;
      button.addEventListener('click', () => this.onChange(key, null, { action: true }));
      row.append(button);
    });
    this.currentBody.append(row);
    return this;
  }

  note(text) {
    this.currentBody.append(element('p', 'group-note', text));
    return this;
  }

  sync(key) {
    const control = this.controls.get(key);
    if (!control) return;
    const value = this.params[key];
    if (control.kind === 'toggle') { control.input.checked = !!value; control.row.classList.toggle('on', !!value); return; }
    control.input.value = value;
    if (control.readout) control.readout.textContent = formatValue(value, control.step);
  }

  syncAll() {
    this.controls.forEach((_, key) => this.sync(key));
  }
}

function withAlpha(colour, alpha) {
  const hex = String(colour).trim();
  const short = /^#([0-9a-f])([0-9a-f])([0-9a-f])$/i.exec(hex);
  const long = /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex);
  const rgb = /^rgba?\(([^)]+)\)$/i.exec(hex);
  let parts;
  if (long) parts = [1, 2, 3].map((i) => parseInt(long[i], 16));
  else if (short) parts = [1, 2, 3].map((i) => parseInt(short[i] + short[i], 16));
  else if (rgb) parts = rgb[1].split(',').slice(0, 3).map((v) => parseFloat(v));
  else parts = [224, 86, 127];
  return `rgba(${parts[0]}, ${parts[1]}, ${parts[2]}, ${alpha})`;
}

export function drawKernelProfile(canvas, profile, accent) {
  const ctx = canvas.getContext('2d');
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const w = canvas.clientWidth;
  const h = canvas.clientHeight;
  canvas.width = w * dpr;
  canvas.height = h * dpr;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, w, h);

  ctx.strokeStyle = 'rgba(255,255,255,0.07)';
  ctx.lineWidth = 1;
  for (let i = 1; i < 4; i++) {
    const x = (w * i) / 4;
    ctx.beginPath();
    ctx.moveTo(x, 0);
    ctx.lineTo(x, h);
    ctx.stroke();
  }

  const gradient = ctx.createLinearGradient(0, 0, 0, h);
  gradient.addColorStop(0, withAlpha(accent, 0.33));
  gradient.addColorStop(1, withAlpha(accent, 0));
  ctx.beginPath();
  ctx.moveTo(0, h);
  for (let i = 0; i < profile.length; i++) {
    const x = (i / (profile.length - 1)) * w;
    const y = h - profile[i] * (h - 3) - 1;
    ctx.lineTo(x, y);
  }
  ctx.lineTo(w, h);
  ctx.closePath();
  ctx.fillStyle = gradient;
  ctx.fill();

  ctx.beginPath();
  for (let i = 0; i < profile.length; i++) {
    const x = (i / (profile.length - 1)) * w;
    const y = h - profile[i] * (h - 3) - 1;
    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
  }
  ctx.strokeStyle = accent;
  ctx.lineWidth = 1.5;
  ctx.stroke();
}

export function drawGrowthProfile(canvas, kernels, accent) {
  const ctx = canvas.getContext('2d');
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const w = canvas.clientWidth;
  const h = canvas.clientHeight;
  canvas.width = w * dpr;
  canvas.height = h * dpr;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, w, h);

  const mid = h / 2;
  ctx.strokeStyle = 'rgba(255,255,255,0.12)';
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(0, mid);
  ctx.lineTo(w, mid);
  ctx.stroke();

  const samples = 150;
  const many = kernels.length > 1;
  kernels.forEach((k, index) => {
    ctx.beginPath();
    for (let i = 0; i <= samples; i++) {
      const u = i / samples;
      const d = u - k.m;
      const g = 2 * Math.exp(-(d * d) / (2 * k.s * k.s)) - 1;
      const x = u * w;
      const y = mid - g * (mid - 2) * Math.min(1, Math.abs(k.h));
      if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    }
    ctx.strokeStyle = many ? withAlpha(accent, Math.min(0.9, 0.28 + 1.2 / kernels.length)) : accent;
    ctx.lineWidth = many ? 1 : 1.5;
    ctx.stroke();
  });

  ctx.strokeStyle = 'rgba(255,255,255,0.22)';
  ctx.setLineDash([2, 3]);
  kernels.forEach((k) => {
    const x = k.m * w;
    ctx.beginPath();
    ctx.moveTo(x, mid - 4);
    ctx.lineTo(x, mid + 4);
    ctx.stroke();
  });
  ctx.setLineDash([]);
}

export function drawBandMeter(canvas, bands, level, accent, active) {
  const ctx = canvas.getContext('2d');
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const w = canvas.clientWidth;
  const h = canvas.clientHeight;
  canvas.width = w * dpr;
  canvas.height = h * dpr;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, w, h);

  const gap = 3;
  const barWidth = (w - gap * (bands.length - 1)) / bands.length;
  bands.forEach((value, i) => {
    const x = i * (barWidth + gap);
    ctx.fillStyle = 'rgba(190,205,235,0.07)';
    ctx.fillRect(x, 0, barWidth, h);
    const bar = Math.max(1, value * h);
    ctx.fillStyle = active ? accent : 'rgba(190,205,235,0.22)';
    ctx.fillRect(x, h - bar, barWidth, bar);
  });

  ctx.fillStyle = active ? accent : 'rgba(190,205,235,0.3)';
  ctx.globalAlpha = 0.5;
  ctx.fillRect(0, h - Math.max(1, level * h), w, 1);
  ctx.globalAlpha = 1;
}
