(function () {
  "use strict";

  const $ = (id) => document.getElementById(id);
  const params = new URLSearchParams(location.hash.slice(1));
  const isSource = params.get("role") === "source";
  const sessionFromUrl = (params.get("s") || "").toUpperCase();

  const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  const PRESET = { deeper: -5, higher: 3, helium: 8, demon: -8 };
  const PITCH_MODES = new Set(["pitch", "deeper", "higher", "helium", "demon"]);

  const statusId = isSource ? "sourceStatus" : "status";
  const levelId = isSource ? "sourceLevel" : "level";

  let ctx = null;
  let micStream = null;
  let micNode = null;
  let dsp = null;
  let latencyDelay = null;
  let masterGain = null;
  let analyser = null;
  let capture = null;
  let voice = null;
  let meterRaf = null;
  let muted = false;
  let running = false;
  let lastSeq = -1;
  let drops = 0;

  function setStatus(text) { $(statusId).textContent = text; }

  function micError(e) {
    console.error("getUserMedia failed", e);
    if (e && e.name === "NotAllowedError") return "mic blocked — check browser permission";
    if (e && e.name === "SecurityError") return "mic blocked — insecure or policy";
    if (e && e.name === "OverconstrainedError") return "mic constraints unsupported";
    if (e && e.name === "NotFoundError") return "no microphone found";
    return "mic error: " + (e && e.name ? e.name : "unknown");
  }

  function makeSession() {
    const rnd = new Uint32Array(6);
    crypto.getRandomValues(rnd);
    let out = "";
    for (let i = 0; i < 6; i++) out += ALPHABET[rnd[i] % ALPHABET.length];
    return out;
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
    $(levelId).value = peak;
    meterRaf = requestAnimationFrame(drawMeter);
  }

  function startMeter() {
    if (!meterRaf) meterRaf = requestAnimationFrame(drawMeter);
  }

  function stopMeter() {
    if (meterRaf) { cancelAnimationFrame(meterRaf); meterRaf = null; }
  }

  async function startSource() {
    if (running) return;
    const session = ($("sourceCode").value.trim() || sessionFromUrl).toUpperCase();
    if (!session) { setStatus("enter a session code"); return; }
    ensureCtx();
    await ctx.resume();
    micStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    micNode = ctx.createMediaStreamSource(micStream);
    micNode.connect(analyser);
    voice = Voice.connect(session, "source", function () {});
    capture = ctx.createScriptProcessor(1024, 1, 1);
    capture.onaudioprocess = (ev) => {
      if (!voice.ready() || muted) return;
      voice.send(ev.inputBuffer.getChannelData(0).slice(), ctx.sampleRate);
    };
    const mute = ctx.createGain();
    mute.gain.value = 0;
    micNode.connect(capture);
    capture.connect(mute);
    mute.connect(ctx.destination);
    running = true;
    muted = false;
    startMeter();
    $("sourceStart").textContent = "stop";
    $("sourceMute").disabled = false;
    setStatus("streaming to desktop");
  }

  function stopSource() {
    if (micStream) micStream.getTracks().forEach((t) => t.stop());
    if (voice) { voice.close(); voice = null; }
    if (capture) { capture.disconnect(); capture.onaudioprocess = null; capture = null; }
    if (micNode) { micNode.disconnect(); micNode = null; }
    micStream = null;
    running = false;
    stopMeter();
    $(levelId).value = 0;
    $("sourceStart").textContent = "start mic";
    $("sourceMute").disabled = true;
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
    if ($(statusId).textContent === "waiting for phone") setStatus("live · phone");
    playPcm(frame.pcm, frame.sampleRate);
  }

  async function startSink() {
    if (running) return;
    ensureCtx();
    await ctx.resume();
    const input = $("inputSource").value;
    if (input === "local") {
      micStream = await navigator.mediaDevices.getUserMedia({ audio: true });
      micNode = ctx.createMediaStreamSource(micStream);
      micNode.connect(dsp.input);
      micNode.connect(analyser);
      setStatus("live · local");
    } else {
      voice = Voice.connect($("sessionCode").textContent.trim(), "sink", onSinkFrame);
      lastSeq = -1;
      drops = 0;
      $("drops").textContent = "";
      setStatus("waiting for phone");
    }
    applyMode($("mode").value);
    running = true;
    startMeter();
    $("sinkStart").textContent = "stop";
    $("inputSource").disabled = true;
  }

  function stopSink() {
    if (micStream) micStream.getTracks().forEach((t) => t.stop());
    if (voice) { voice.close(); voice = null; }
    if (micNode) { micNode.disconnect(); micNode = null; }
    micStream = null;
    running = false;
    stopMeter();
    $(levelId).value = 0;
    $("drops").textContent = "";
    $("sinkStart").textContent = "start";
    $("inputSource").disabled = false;
    setStatus("idle");
  }

  function applyMode(mode) {
    $("pitch").disabled = !PITCH_MODES.has(mode);
    if (!dsp) return;
    dsp.setMode(mode, PRESET[mode] || 0, Number($("pitch").value));
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

  function inviteLink() {
    return location.origin + location.pathname + "#role=source&s=" + $("sessionCode").textContent.trim();
  }

  function boot() {
    if (isSource) {
      $("sourcePanel").classList.remove("hidden");
      if (sessionFromUrl) $("sourceCode").value = sessionFromUrl;
      $("sourceStart").addEventListener("click", () => {
        if (running) { stopSource(); } else {
          startSource().catch((e) => setStatus(micError(e)));
        }
      });
      $("sourceMute").addEventListener("click", () => {
        muted = !muted;
        $("sourceMute").textContent = muted ? "unmute" : "mute";
        setStatus(muted ? "muted" : "streaming to desktop");
      });
    } else {
      $("sinkPanel").classList.remove("hidden");
      $("sessionCode").textContent = sessionFromUrl || makeSession();
      $("sinkStart").addEventListener("click", () => {
        if (running) { stopSink(); } else {
          startSink().catch((e) => setStatus(micError(e)));
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
      $("copyLink").addEventListener("click", async () => {
        try {
          await navigator.clipboard.writeText(inviteLink());
          $("copyLink").textContent = "copied";
          setTimeout(() => { $("copyLink").textContent = "copy link"; }, 1500);
        } catch (e) {
          window.prompt("session link", inviteLink());
        }
      });
      populateOutputs(false);
    }
  }

  boot();
})();
