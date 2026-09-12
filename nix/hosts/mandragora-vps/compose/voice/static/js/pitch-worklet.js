registerProcessor("pitch-shift", class extends AudioWorkletProcessor {
  static get parameterDescriptors() {
    return [{ name: "ratio", defaultValue: 1.0, minValue: 0.25, maxValue: 4.0, automationRate: "k-rate" }];
  }

  constructor() {
    super();
    this.size = 4096;
    this.fade = 512;
    this.buf = new Float32Array(this.size);
    this.write = 0;
    this.read = 0;
  }

  process(inputs, outputs, parameters) {
    const input = inputs[0] && inputs[0][0];
    const output = outputs[0][0];
    if (!input) return true;

    const ratio = parameters.ratio[0];
    const size = this.size;
    const fade = this.fade;
    const buf = this.buf;

    for (let i = 0; i < output.length; i++) {
      buf[this.write] = input[i] || 0;
      this.write = (this.write + 1) % size;

      const r = this.read;
      const i0 = Math.floor(r);
      const frac = r - i0;
      const a = buf[i0];
      const b = buf[(i0 + 1) % size];
      const s1 = a + (b - a) * frac;

      const r2 = (r + size / 2) % size;
      const j0 = Math.floor(r2);
      const frac2 = r2 - j0;
      const c = buf[j0];
      const d = buf[(j0 + 1) % size];
      const s2 = c + (d - c) * frac2;

      let w = 1;
      if (r < fade) w = r / fade;
      else if (r > size - fade) w = (size - r) / fade;

      output[i] = s1 * w + s2 * (1 - w);
      this.read = (this.read + ratio) % size;
    }
    return true;
  }
});
