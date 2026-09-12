(function () {
  "use strict";

  const $ = (id) => document.getElementById(id);

  const startBtn = $("start");
  const statusEl = $("status");
  const modeSel = $("mode");
  const pitchInput = $("pitch");
  const pitchVal = $("pitchVal");
  const delayInput = $("delay");
  const delayVal = $("delayVal");
  const levelEl = $("level");
  const rttEl = $("rtt");

  const PRESET = { deeper: -5, higher: 3, helium: 8, demon: -8 };
  const PITCH_MODES = new Set(["pitch", "deeper", "higher", "helium", "demon"]);

  let ctx = null;
  let stream = null;
  let source = null;
  let dsp = null;
  let latencyDelay = null;
  let masterGain = null;
  let analyser = null;
  let ai = null;
  let captureNode = null;
  let captureMute = null;
  let pendingRtt = new Map();
  let meterRaf = null;

  function setStatus(text) { statusEl.textContent = text; }

  async function startMic() {
    if (ctx) return;
    stream = await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false },
    });
    ctx = new (window.AudioContext || window.webkitAudioContext)();
    await DSP.ensureWorklet(ctx);

    source = ctx.createMediaStreamSource(stream);
    masterGain = ctx.createGain();
    latencyDelay = ctx.createDelay(1.0);
    latencyDelay.delayTime.value = Number(delayInput.value) / 1000;
    analyser = ctx.createAnalyser();
    analyser.fftSize = 512;

    dsp = DSP.create(ctx);
    source.connect(dsp.input);
    dsp.output.connect(latencyDelay);
    latencyDelay.connect(masterGain);
    masterGain.connect(ctx.destination);
    source.connect(analyser);

    applyMode(modeSel.value);

    meterRaf = requestAnimationFrame(drawMeter);
    startBtn.textContent = "stop mic";
    setStatus("live");
  }

  function stopMic() {
    stopAI();
    if (stream) stream.getTracks().forEach((t) => t.stop());
    if (dsp) dsp.dispose();
    if (ctx) ctx.close();
    if (meterRaf) cancelAnimationFrame(meterRaf);
    ctx = stream = source = dsp = latencyDelay = masterGain = analyser = ai = captureNode = captureMute = null;
    pendingRtt.clear();
    levelEl.value = 0;
    rttEl.textContent = "";
    startBtn.textContent = "start mic";
    setStatus("idle");
  }

  function applyMode(mode) {
    pitchInput.disabled = !PITCH_MODES.has(mode);
    if (!ctx) return;
    if (mode === "ai") {
      startAI();
    } else {
      stopAI();
      dsp.setMode(mode, PRESET[mode] || 0, Number(pitchInput.value));
    }
  }

  function startAI() {
    if (ai) return;
    dsp.setMode("bypass", 0, 0);
    dsp.output.disconnect(latencyDelay);

    ai = AI.channel(onAIFrame);
    ai.open();

    captureNode = ctx.createScriptProcessor(2048, 1, 1);
    captureNode.onaudioprocess = (ev) => {
      if (!ai.ready()) return;
      const pcm = ev.inputBuffer.getChannelData(0).slice();
      const seq = ai.send(pcm);
      if (seq >= 0) pendingRtt.set(seq, performance.now());
    };
    captureMute = ctx.createGain();
    captureMute.gain.value = 0;
    source.connect(captureNode);
    captureNode.connect(captureMute);
    captureMute.connect(ctx.destination);
    setStatus("live · ai");
  }

  function stopAI() {
    if (captureNode) {
      captureNode.disconnect();
      captureNode.onaudioprocess = null;
      captureNode = null;
    }
    if (captureMute) { captureMute.disconnect(); captureMute = null; }
    if (ai) { ai.close(); ai = null; }
    pendingRtt.clear();
    rttEl.textContent = "";
    if (dsp && latencyDelay) dsp.output.connect(latencyDelay);
  }

  function onAIFrame({ seq, pcm }) {
    if (pendingRtt.has(seq)) {
      const rtt = Math.round(performance.now() - pendingRtt.get(seq));
      rttEl.textContent = `rtt ${rtt} ms`;
      pendingRtt.delete(seq);
    }
    const buf = ctx.createBuffer(1, pcm.length, ctx.sampleRate);
    buf.copyToChannel(pcm, 0);
    const src = ctx.createBufferSource();
    src.buffer = buf;
    src.connect(latencyDelay);
    src.start();
  }

  function drawMeter() {
    if (!analyser) return;
    const data = new Float32Array(analyser.fftSize);
    analyser.getFloatTimeDomainData(data);
    let peak = 0;
    for (let i = 0; i < data.length; i++) peak = Math.max(peak, Math.abs(data[i]));
    levelEl.value = peak;
    meterRaf = requestAnimationFrame(drawMeter);
  }

  startBtn.addEventListener("click", () => {
    if (ctx) { stopMic(); } else {
      startMic().catch(() => setStatus("mic denied"));
    }
  });
  modeSel.addEventListener("change", () => applyMode(modeSel.value));
  pitchInput.addEventListener("input", () => {
    pitchVal.textContent = `${pitchInput.value} st`;
    if (dsp && modeSel.value === "pitch") dsp.setPitch(Number(pitchInput.value));
  });
  delayInput.addEventListener("input", () => {
    delayVal.textContent = `${delayInput.value} ms`;
    if (latencyDelay) latencyDelay.delayTime.value = Number(delayInput.value) / 1000;
  });
})();
