registerProcessor("pcm-tap", class extends AudioWorkletProcessor {
  constructor() {
    super();
    this.size = Math.round(sampleRate * 0.02);
    this.buf = new Float32Array(this.size);
    this.fill = 0;
  }

  process(inputs) {
    const ch = inputs[0] && inputs[0][0];
    if (!ch) return true;
    let i = 0;
    while (i < ch.length) {
      const n = Math.min(ch.length - i, this.size - this.fill);
      this.buf.set(ch.subarray(i, i + n), this.fill);
      this.fill += n;
      i += n;
      if (this.fill === this.size) {
        this.port.postMessage(this.buf, [this.buf.buffer]);
        this.buf = new Float32Array(this.size);
        this.fill = 0;
      }
    }
    return true;
  }
});

registerProcessor("pcm-player", class extends AudioWorkletProcessor {
  constructor() {
    super();
    this.cap = 1 << 18;
    this.ring = new Float32Array(this.cap);
    this.w = 0;
    this.r = 0;
    this.rate = sampleRate;
    this.target = 0.08;
    this.chunk = 0;
    this.primed = false;
    this.underruns = 0;
    this.tick = 0;
    this.port.onmessage = (e) => this.receive(e.data);
  }

  receive(msg) {
    if (msg.target !== undefined) {
      this.target = msg.target;
      return;
    }
    const pcm = msg.pcm;
    if (msg.rate !== this.rate) {
      this.rate = msg.rate;
      this.w = 0;
      this.r = 0;
      this.primed = false;
      this.chunk = 0;
    }
    this.chunk = Math.max(pcm.length / this.rate, this.chunk * 0.98);
    const cap = this.cap;
    if (this.w + pcm.length - this.r > cap) this.r = this.w + pcm.length - cap;
    const pos = this.w % cap;
    const first = Math.min(pcm.length, cap - pos);
    this.ring.set(pcm.subarray(0, first), pos);
    if (first < pcm.length) this.ring.set(pcm.subarray(first), 0);
    this.w += pcm.length;
  }

  report(avail, frames) {
    this.tick += frames;
    if (this.tick < sampleRate / 4) return;
    this.tick = 0;
    this.port.postMessage({ buffered: avail / this.rate, underruns: this.underruns });
  }

  process(inputs, outputs) {
    const out = outputs[0][0];
    const rate = this.rate;
    const targetSamples = Math.max(this.target, this.chunk * 1.25) * rate;
    let avail = this.w - this.r;

    if (!this.primed) {
      if (avail < targetSamples) {
        out.fill(0);
        this.report(avail, out.length);
        return true;
      }
      this.primed = true;
    }

    if (avail > targetSamples * 2 + this.chunk * rate + rate * 0.06) {
      this.r = this.w - targetSamples;
      avail = targetSamples;
    }

    const excess = (avail - targetSamples) / rate;
    const nudge = Math.max(-0.01, Math.min(0.03, excess * 0.5));
    const step = (rate / sampleRate) * (1 + nudge);
    const ring = this.ring;
    const cap = this.cap;
    let r = this.r;
    for (let i = 0; i < out.length; i++) {
      if (this.w - r < 2) {
        out.fill(0, i);
        this.primed = false;
        this.underruns++;
        break;
      }
      const i0 = Math.floor(r);
      const f = r - i0;
      const a = ring[i0 % cap];
      const b = ring[(i0 + 1) % cap];
      out[i] = a + (b - a) * f;
      r += step;
    }
    this.r = r;
    this.report(this.w - r, out.length);
    return true;
  }
});

registerProcessor("pitch-shift", class extends AudioWorkletProcessor {
  static get parameterDescriptors() {
    return [{ name: "ratio", defaultValue: 1, minValue: 0.25, maxValue: 4, automationRate: "k-rate" }];
  }

  constructor() {
    super();
    this.win = Math.round(sampleRate * 0.05);
    this.size = 1 << 14;
    this.mask = this.size - 1;
    this.buf = new Float32Array(this.size);
    this.w = 0;
    this.phase = 0;
  }

  tap(delay) {
    const pos = this.w - delay;
    const i0 = Math.floor(pos);
    const f = pos - i0;
    const a = this.buf[i0 & this.mask];
    const b = this.buf[(i0 + 1) & this.mask];
    return a + (b - a) * f;
  }

  process(inputs, outputs, parameters) {
    const input = inputs[0] && inputs[0][0];
    const out = outputs[0][0];
    const win = this.win;
    const inc = (1 - parameters.ratio[0]) / win;
    const twoPi = 2 * Math.PI;
    for (let i = 0; i < out.length; i++) {
      this.buf[this.w & this.mask] = input ? input[i] : 0;
      const p1 = this.phase;
      const p2 = p1 + 0.5 < 1 ? p1 + 0.5 : p1 - 0.5;
      const g1 = 0.5 - 0.5 * Math.cos(twoPi * p1);
      out[i] = this.tap(p1 * win + 1) * g1 + this.tap(p2 * win + 1) * (1 - g1);
      let next = p1 + inc;
      if (next >= 1) next -= 1;
      else if (next < 0) next += 1;
      this.phase = next;
      this.w++;
    }
    return true;
  }
});
