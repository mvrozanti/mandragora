(function () {
  "use strict";

  const $ = (id) => document.getElementById(id);

  const PRESET = { deeper: -5, higher: 3, helium: 8, demon: -8 };
  const PITCH_MODES = new Set(["pitch", "deeper", "higher", "helium", "demon"]);

  let ctx = null;
  let micStream = null;
  let micNode = null;
  let dsp = null;
  let latencyDelay = null;
  let masterGain = null;
  let analyser = null;
  let capture = null;
  let micVoice = null;
  let outVoice = null;
  let meterRaf = null;
  let muted = false;
  let micRunning = false;
  let outRunning = false;
  let lastSeq = -1;
  let drops = 0;

  function setStatus(text) { $("status").textContent = text; }

  function micError(e) {
    console.error("getUserMedia failed", e);
    if (e && e.name === "NotAllowedError") return "mic blocked — check browser permission";
    if (e && e.name === "SecurityError") return "mic blocked — insecure or policy";
    if (e && e.name === "OverconstrainedError") return "mic constraints unsupported";
    if (e && e.name === "NotFoundError") return "no microphone found";
    return "mic error: " + (e && e.name ? e.name : "unknown");
  }

  function ensureCtx() {
    if (ctx) return;
    ctx = new (window.AudioContext || window.webkitAudioContext)();
    analyser = ctx.createAnalyser();
    analyser.fftSize = 512;
    masterGain = ctx.createGain();
    latencyDelay = ctx.createDelay(1.0);
    const delayEl = $("delay");
    latencyDelay.delayTime.value = Number(delayEl ? delayEl.value : 150) / 1000;
    dsp = DSP.create(ctx);
    dsp.output.connect(latencyDelay);
    latencyDelay.connect(masterGain);
    masterGain.connect(ctx.destination);
  }

  function drawMeter() {
    if (!analyser) return;
    const data = new Float32Array(analyser.fftSize);
    analyser.getFloatTimeDomainData(data);
    let peak = 0;
    for (let i = 0; i < data.length; i++) peak = Math.max(peak, Math.abs(data[i]));
    $("level").value = peak;
    meterRaf = requestAnimationFrame(drawMeter);
  }

  function startMeter() {
    if (!meterRaf) meterRaf = requestAnimationFrame(drawMeter);
  }

  function stopMeter() {
    if (meterRaf) { cancelAnimationFrame(meterRaf); meterRaf = null; }
    if ($("level")) $("level").value = 0;
  }

  async function startMic() {
    if (micRunning) return;
    ensureCtx();
    await ctx.resume();
    micStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    micNode = ctx.createMediaStreamSource(micStream);
    micNode.connect(analyser);
    micVoice = Voice.connect("source", function () {}, wsPath());
    capture = ctx.createScriptProcessor(1024, 1, 1);
    capture.onaudioprocess = (ev) => {
      if (!micVoice.ready() || muted) return;
      micVoice.send(ev.inputBuffer.getChannelData(0).slice(), ctx.sampleRate);
    };
    const mute = ctx.createGain();
    mute.gain.value = 0;
    micNode.connect(capture);
    capture.connect(mute);
    mute.connect(ctx.destination);
    micRunning = true;
    muted = false;
    startMeter();
    $("micStart").textContent = "stop mic";
    $("micMute").disabled = false;
    setStatus("mic live — start output on the other device");
  }

  function stopMic() {
    if (micStream) micStream.getTracks().forEach((t) => t.stop());
    if (micVoice) { micVoice.close(); micVoice = null; }
    if (capture) { capture.disconnect(); capture.onaudioprocess = null; capture = null; }
    if (micNode) { micNode.disconnect(); micNode = null; }
    micStream = null;
    micRunning = false;
    stopMeter();
    $("micStart").textContent = "start mic";
    $("micMute").disabled = true;
    setStatus("idle");
  }

  function playPcm(pcm, sampleRate) {
    const buf = ctx.createBuffer(1, pcm.length, sampleRate);
    buf.copyToChannel(pcm, 0);
    const src = ctx.createBufferSource();
    src.buffer = buf;
    src.connect(dsp.input);
    src.start();
  }

  function onSinkFrame(frame) {
    if (lastSeq >= 0 && frame.seq > lastSeq + 1) drops += frame.seq - lastSeq - 1;
    lastSeq = frame.seq;
    $("drops").textContent = drops ? drops + " dropped" : "";
    setStatus("live — transforming voice");
    playPcm(frame.pcm, frame.sampleRate);
  }

  async function startOutput() {
    if (outRunning) return;
    ensureCtx();
    await ctx.resume();
    outVoice = Voice.connect("sink", onSinkFrame, wsPath());
    lastSeq = -1;
    drops = 0;
    $("drops").textContent = "";
    applyMode($("mode").value);
    outRunning = true;
    startMeter();
    $("outputStart").textContent = "stop output";
    setStatus("waiting for mic");
  }

  function stopOutput() {
    if (outVoice) { outVoice.close(); outVoice = null; }
    outRunning = false;
    $("drops").textContent = "";
    $("outputStart").textContent = "start output";
    setStatus("idle");
  }

  function wsPath() {
    return $("mode").value === "mcbaldiee" ? "/rvc" : "/ws";
  }

  function reconnectSource() {
    if (micVoice) micVoice.close();
    micVoice = Voice.connect("source", function () {}, wsPath());
  }

  function reconnectSink() {
    if (outVoice) outVoice.close();
    lastSeq = -1;
    outVoice = Voice.connect("sink", onSinkFrame, wsPath());
  }

  function applyMode(mode) {
    $("pitch").disabled = !PITCH_MODES.has(mode);
    if (!dsp) return;
    if (mode === "mcbaldiee") {
      dsp.setMode("bypass", 0, Number($("pitch").value));
    } else {
      dsp.setMode(mode, PRESET[mode] || 0, Number($("pitch").value));
    }
    if (micRunning) reconnectSource();
    if (outRunning) reconnectSink();
  }

  async function setOutput(deviceId) {
    if (!ctx || !ctx.setSinkId) return;
    const id = deviceId === "default" ? "" : deviceId;
    try { await ctx.setSinkId(id); } catch (e) { setStatus("output unavailable"); }
  }

  async function populateOutputs(unlock) {
    if (!navigator.mediaDevices || !navigator.mediaDevices.enumerateDevices) return;
    if (unlock) {
      try {
        const s = await navigator.mediaDevices.getUserMedia({ audio: true });
        s.getTracks().forEach((t) => t.stop());
      } catch (e) {}
    }
    const devices = await navigator.mediaDevices.enumerateDevices();
    const sel = $("output");
    const current = sel.value;
    sel.innerHTML = "";
    const outs = devices.filter((d) => d.kind === "audiooutput");
    let n = 0;
    for (const d of outs) {
      const opt = document.createElement("option");
      opt.value = d.deviceId;
      opt.textContent = d.label || ("output " + (++n));
      sel.appendChild(opt);
    }
    if (current) sel.value = current;
  }

  function boot() {
    $("micStart").addEventListener("click", () => {
      if (micRunning) { stopMic(); } else {
        startMic().catch((e) => setStatus(micError(e)));
      }
    });
    $("micMute").addEventListener("click", () => {
      muted = !muted;
      $("micMute").textContent = muted ? "unmute" : "mute";
      setStatus(muted ? "mic muted" : "mic live");
    });
    $("outputStart").addEventListener("click", () => {
      if (outRunning) { stopOutput(); } else {
        startOutput().catch(() => setStatus("output failed"));
      }
    });
    $("mode").addEventListener("change", () => applyMode($("mode").value));
    $("pitch").addEventListener("input", () => {
      $("pitchVal").textContent = $("pitch").value + " st";
      if (dsp && $("mode").value === "pitch") dsp.setPitch(Number($("pitch").value));
    });
    $("delay").addEventListener("input", () => {
      $("delayVal").textContent = $("delay").value + " ms";
      if (latencyDelay) latencyDelay.delayTime.value = Number($("delay").value) / 1000;
    });
    $("output").addEventListener("change", () => setOutput($("output").value));
    let outputsUnlocked = false;
    $("output").addEventListener("focus", () => {
      if (!outputsUnlocked) { outputsUnlocked = true; populateOutputs(true); }
    });
    populateOutputs(false);
  }

  boot();
})();
