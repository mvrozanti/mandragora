window.DSP = (function () {
  "use strict";

  function semitoneRatio(st) {
    return Math.pow(2, st / 12);
  }

  function softClipCurve(drive) {
    const curve = new Float32Array(1024);
    for (let i = 0; i < curve.length; i++) {
      const x = (i / (curve.length / 2)) - 1;
      curve[i] = Math.tanh(x * drive) / Math.tanh(drive);
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
    input.connect(dry);
    dry.connect(output);

    const DRY_LEVEL = { bypass: 1, echo: 0.7, reverb: 0.6 };

    let nodes = [];
    let oscillators = [];
    let pitchNode = null;

    function chain(list) {
      for (let i = 0; i < list.length - 1; i++) list[i].connect(list[i + 1]);
      nodes = nodes.concat(list.filter((n) => n !== input && n !== output));
    }

    function clearWet() {
      for (const osc of oscillators) { try { osc.stop(); } catch (e) {} }
      for (const node of nodes) { try { node.disconnect(); } catch (e) {} }
      try { input.disconnect(); } catch (e) {}
      input.connect(dry);
      nodes = [];
      oscillators = [];
      pitchNode = null;
    }

    function shifter(st) {
      const node = new AudioWorkletNode(ctx, "pitch-shift", {
        numberOfInputs: 1,
        numberOfOutputs: 1,
        channelCount: 1,
        channelCountMode: "explicit",
        outputChannelCount: [1],
      });
      node.parameters.get("ratio").value = semitoneRatio(st);
      return node;
    }

    function pitchMode(st) {
      pitchNode = shifter(st);
      chain([input, pitchNode, output]);
    }

    function demonMode(st) {
      pitchNode = shifter(st);
      const low = ctx.createBiquadFilter();
      low.type = "lowshelf";
      low.frequency.value = 220;
      low.gain.value = 8;
      const grit = ctx.createWaveShaper();
      grit.curve = softClipCurve(2.5);
      grit.oversample = "2x";
      const trim = ctx.createGain();
      trim.gain.value = 0.7;
      chain([input, pitchNode, low, grit, trim, output]);
    }

    function robotMode() {
      const ring = ctx.createGain();
      ring.gain.value = 0;
      const osc = ctx.createOscillator();
      osc.type = "sine";
      osc.frequency.value = 55;
      osc.connect(ring.gain);
      osc.start();
      oscillators.push(osc);
      const comb = ctx.createDelay(0.05);
      comb.delayTime.value = 0.008;
      const feedback = ctx.createGain();
      feedback.gain.value = 0.45;
      comb.connect(feedback);
      feedback.connect(comb);
      const band = ctx.createBiquadFilter();
      band.type = "highpass";
      band.frequency.value = 180;
      chain([input, ring, band, output]);
      chain([band, comb, output]);
      nodes.push(osc, feedback);
    }

    function radioMode() {
      const hp = ctx.createBiquadFilter();
      hp.type = "highpass";
      hp.frequency.value = 500;
      const lp = ctx.createBiquadFilter();
      lp.type = "lowpass";
      lp.frequency.value = 3500;
      const shaper = ctx.createWaveShaper();
      shaper.curve = softClipCurve(4);
      const trim = ctx.createGain();
      trim.gain.value = 0.8;
      chain([input, hp, lp, shaper, trim, output]);
    }

    function telephoneMode() {
      const hp = ctx.createBiquadFilter();
      hp.type = "highpass";
      hp.frequency.value = 400;
      hp.Q.value = 0.9;
      const lp = ctx.createBiquadFilter();
      lp.type = "lowpass";
      lp.frequency.value = 3000;
      lp.Q.value = 0.9;
      const shaper = ctx.createWaveShaper();
      shaper.curve = softClipCurve(1.5);
      chain([input, hp, lp, shaper, output]);
    }

    function echoMode() {
      const delay = ctx.createDelay(1.0);
      delay.delayTime.value = 0.28;
      const feedback = ctx.createGain();
      feedback.gain.value = 0.45;
      const damp = ctx.createBiquadFilter();
      damp.type = "lowpass";
      damp.frequency.value = 4000;
      const mix = ctx.createGain();
      mix.gain.value = 0.6;
      chain([input, delay, damp, feedback, delay]);
      chain([damp, mix, output]);
    }

    function reverbMode() {
      const conv = ctx.createConvolver();
      conv.buffer = reverbImpulse(ctx, 2.2, 3);
      const wetGain = ctx.createGain();
      wetGain.gain.value = 0.7;
      chain([input, conv, wetGain, output]);
    }

    function setMode(mode, st) {
      clearWet();
      dry.gain.value = DRY_LEVEL[mode] !== undefined ? DRY_LEVEL[mode] : 0;
      switch (mode) {
        case "pitch":
        case "deeper":
        case "higher":
        case "helium": pitchMode(st); break;
        case "demon": demonMode(st); break;
        case "robot": robotMode(); break;
        case "radio": radioMode(); break;
        case "telephone": telephoneMode(); break;
        case "echo": echoMode(); break;
        case "reverb": reverbMode(); break;
        default: dry.gain.value = 1; break;
      }
    }

    function setPitch(st) {
      if (pitchNode) pitchNode.parameters.get("ratio").value = semitoneRatio(st);
    }

    return { input, output, setMode, setPitch };
  }

  return { create };
})();
