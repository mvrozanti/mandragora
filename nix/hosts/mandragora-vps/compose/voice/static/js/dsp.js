window.DSP = (function () {
  "use strict";

  const WORKLET = "/js/pitch-worklet.js";

  async function ensureWorklet(ctx) {
    if (!ctx.__voiceWorklet) {
      await ctx.audioWorklet.addModule(WORKLET);
      ctx.__voiceWorklet = true;
    }
  }

  function semitoneRatio(st) {
    return Math.pow(2, st / 12);
  }

  function softClipCurve() {
    const curve = new Float32Array(256);
    for (let i = 0; i < 256; i++) {
      const x = (i / 128) - 1;
      curve[i] = Math.tanh(x * 2);
    }
    return curve;
  }

  function reverbImpulse(ctx, seconds, decay) {
    const rate = ctx.sampleRate;
    const len = Math.floor(rate * seconds);
    const buf = ctx.createBuffer(2, len, rate);
    for (let ch = 0; ch < 2; ch++) {
      const data = buf.getChannelData(ch);
      for (let i = 0; i < len; i++) {
        data[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, decay);
      }
    }
    return buf;
  }

  function create(ctx) {
    const input = ctx.createGain();
    const output = ctx.createGain();
    const dry = ctx.createGain();
    dry.gain.value = 1;
    input.connect(dry);
    dry.connect(output);

    const DRY_LEVEL = { echo: 0.6, reverb: 0.4 };

    let wet = null;
    let pitchNode = null;

    function clearWet() {
      if (wet) {
        if (wet.__osc) { try { wet.__osc.stop(); } catch (e) {} }
        try { wet.disconnect(); } catch (e) {}
        wet = null;
      }
      pitchNode = null;
    }

    function pitchMode(st) {
      clearWet();
      pitchNode = new AudioWorkletNode(ctx, "pitch-shift", {
        numberOfInputs: 1,
        numberOfOutputs: 1,
        channelCount: 1,
        outputChannelCount: 1,
      });
      pitchNode.parameters.get("ratio").value = semitoneRatio(st);
      input.connect(pitchNode);
      pitchNode.connect(output);
      wet = pitchNode;
    }

    function robotMode() {
      clearWet();
      const osc = ctx.createOscillator();
      osc.type = "square";
      osc.frequency.value = 45;
      const depth = ctx.createGain();
      depth.gain.value = 0.5;
      osc.connect(depth);
      const ring = ctx.createGain();
      ring.gain.value = 0.5;
      depth.connect(ring.gain);
      const lowpass = ctx.createBiquadFilter();
      lowpass.type = "lowpass";
      lowpass.frequency.value = 1800;
      input.connect(ring);
      ring.connect(lowpass);
      lowpass.connect(output);
      osc.start();
      lowpass.__osc = osc;
      wet = lowpass;
    }

    function radioMode() {
      clearWet();
      const band = ctx.createBiquadFilter();
      band.type = "bandpass";
      band.frequency.value = 2000;
      band.Q.value = 0.7;
      const shaper = ctx.createWaveShaper();
      shaper.curve = softClipCurve();
      input.connect(band);
      band.connect(shaper);
      shaper.connect(output);
      wet = shaper;
    }

    function telephoneMode() {
      clearWet();
      const band = ctx.createBiquadFilter();
      band.type = "bandpass";
      band.frequency.value = 1000;
      band.Q.value = 1.5;
      input.connect(band);
      band.connect(output);
      wet = band;
    }

    function echoMode() {
      clearWet();
      const delay = ctx.createDelay(1.0);
      delay.delayTime.value = 0.25;
      const feedback = ctx.createGain();
      feedback.gain.value = 0.4;
      const mix = ctx.createGain();
      mix.gain.value = 0.7;
      input.connect(delay);
      delay.connect(feedback);
      feedback.connect(delay);
      delay.connect(mix);
      mix.connect(output);
      wet = mix;
    }

    function reverbMode() {
      clearWet();
      const conv = ctx.createConvolver();
      conv.buffer = reverbImpulse(ctx, 1.5, 3);
      const wetGain = ctx.createGain();
      wetGain.gain.value = 0.8;
      input.connect(conv);
      conv.connect(wetGain);
      wetGain.connect(output);
      wet = wetGain;
    }

    function setMode(mode, presetSt, sliderSt) {
      dry.gain.value = mode === "bypass" ? 1 : (DRY_LEVEL[mode] || 0);
      switch (mode) {
        case "bypass": clearWet(); break;
        case "pitch": pitchMode(sliderSt); break;
        case "deeper":
        case "higher":
        case "helium":
        case "demon": pitchMode(presetSt); break;
        case "robot": robotMode(); break;
        case "radio": radioMode(); break;
        case "telephone": telephoneMode(); break;
        case "echo": echoMode(); break;
        case "reverb": reverbMode(); break;
        default: clearWet(); break;
      }
    }

    function setPitch(st) {
      if (pitchNode) pitchNode.parameters.get("ratio").value = semitoneRatio(st);
    }

    function dispose() {
      clearWet();
      try { input.disconnect(); } catch (e) {}
      try { dry.disconnect(); } catch (e) {}
      try { output.disconnect(); } catch (e) {}
    }

    return { input, output, setMode, setPitch, dispose };
  }

  return { ensureWorklet, semitoneRatio, create };
})();
