(function () {
  "use strict";

  const $ = (id) => document.getElementById(id);

  const PRESET = { deeper: -5, higher: 3, helium: 8, demon: -8 };
  const PITCH_MODES = new Set(["pitch", "deeper", "higher", "helium", "demon"]);
  const RVC_MODES = new Set(["mcbaldiee"]);
  const RVC_NOTE = {
    loading: ["loading voice model…", ""],
    ready: ["voice model ready", ""],
    unavailable: ["voice model unavailable — GPU busy with something else", "warn"],
    down: ["voice converter offline — retrying", "warn"],
  };
  const FORMAT = {
    pitch: (v) => (v > 0 ? "+" : "") + v + " st",
    buffer: (v) => v + " ms",
    gain: (v) => v + "%",
  };
  const OUTPUT_KEY = "voice.output";
  const CHOOSE_OUTPUT = "__choose__";

  const state = {
    id: null,
    mic: null,
    peers: 0,
    rvc: "off",
    settings: { mode: "bypass", pitch: 0, buffer: 80, gain: 100 },
  };

  let room = null;
  let online = false;
  let ctx = null;
  let modules = null;
  let mic = null;
  let micWanted = false;
  let notice = "";
  let muted = false;
  let wakeLock = null;
  let speaker = null;
  let speakerPending = null;
  let outputRestored = false;
  let applied = { mode: null, pitch: null };
  let stats = { buffered: 0, underruns: 0 };
  let editing = { key: null, until: 0 };
  let pending = {};
  let sendTimer = null;

  function role() {
    if (!state.mic || !state.id) return "idle";
    return state.mic === state.id ? "mic" : "speaker";
  }

  function micError(e) {
    console.error("getUserMedia failed", e);
    if (e && e.name === "NotAllowedError") return "mic blocked — check browser permission";
    if (e && e.name === "SecurityError") return "mic blocked — insecure or policy";
    if (e && e.name === "NotFoundError") return "no microphone found";
    return "mic error: " + (e && e.name ? e.name : String(e));
  }

  function ensureCtx() {
    if (!ctx) {
      ctx = new (window.AudioContext || window.webkitAudioContext)({ latencyHint: "interactive" });
      modules = ctx.audioWorklet.addModule("/js/worklets.js?v=3");
      ctx.onstatechange = function () {
        if (ctx.state === "running") restoreOutput();
        render();
      };
    }
    if (ctx.state !== "running") ctx.resume().catch(function () {});
    return modules;
  }

  async function holdWakeLock() {
    if (!navigator.wakeLock || wakeLock || !mic) return;
    try {
      wakeLock = await navigator.wakeLock.request("screen");
      wakeLock.addEventListener("release", function () { wakeLock = null; });
    } catch (e) {}
  }

  function dropWakeLock() {
    if (wakeLock) wakeLock.release().catch(function () {});
    wakeLock = null;
  }

  async function startMic() {
    const ready = ensureCtx();
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    await ready;
    if (ctx.state !== "running") await ctx.resume();
    const source = ctx.createMediaStreamSource(stream);
    const tap = new AudioWorkletNode(ctx, "pcm-tap", {
      numberOfInputs: 1,
      numberOfOutputs: 1,
      channelCount: 1,
      channelCountMode: "explicit",
      outputChannelCount: [1],
    });
    const silent = ctx.createGain();
    silent.gain.value = 0;
    const analyser = ctx.createAnalyser();
    analyser.fftSize = 1024;
    source.connect(tap);
    source.connect(analyser);
    tap.connect(silent);
    silent.connect(ctx.destination);
    tap.port.onmessage = function (e) {
      if (!muted && role() === "mic") room.sendPcm(e.data, ctx.sampleRate);
    };
    mic = { stream: stream, source: source, tap: tap, silent: silent, analyser: analyser };
    micWanted = true;
    muted = false;
    notice = "";
    room.send({ t: "claim" });
    holdWakeLock();
    render();
  }

  function stopCapture() {
    if (!mic) return;
    mic.stream.getTracks().forEach(function (t) { t.stop(); });
    mic.tap.port.onmessage = null;
    for (const node of [mic.source, mic.tap, mic.silent]) {
      try { node.disconnect(); } catch (e) {}
    }
    mic = null;
    dropWakeLock();
  }

  function stopMic() {
    micWanted = false;
    stopCapture();
    room.send({ t: "release" });
    render();
  }

  function ensureSpeaker() {
    if (speaker) return Promise.resolve();
    if (speakerPending) return speakerPending;
    speakerPending = ensureCtx().then(function () {
      const player = new AudioWorkletNode(ctx, "pcm-player", {
        numberOfInputs: 0,
        numberOfOutputs: 1,
        outputChannelCount: [1],
      });
      const dsp = DSP.create(ctx);
      const gain = ctx.createGain();
      const analyser = ctx.createAnalyser();
      analyser.fftSize = 1024;
      player.connect(dsp.input);
      dsp.output.connect(gain);
      gain.connect(analyser);
      gain.connect(ctx.destination);
      player.port.onmessage = function (e) { stats = e.data; };
      speaker = { player: player, dsp: dsp, gain: gain, analyser: analyser, route: null };
      applied = { mode: null, pitch: null };
      applySettings();
      if (ctx.state === "running") restoreOutput();
      render();
    }).catch(function (e) {
      console.error("speaker setup failed", e);
      notice = "audio engine failed: " + (e && e.message ? e.message : e);
      render();
    }).finally(function () { speakerPending = null; });
    return speakerPending;
  }

  function onFrame(frame) {
    if (!speaker || role() !== "speaker") return;
    speaker.player.port.postMessage({ pcm: frame.pcm, rate: frame.sampleRate }, [frame.pcm.buffer]);
  }

  function applySettings() {
    if (!speaker) return;
    const s = state.settings;
    const mode = RVC_MODES.has(s.mode) ? "bypass" : s.mode;
    try {
      if (mode !== applied.mode) {
        speaker.dsp.setMode(mode, s.pitch);
        applied = { mode: mode, pitch: s.pitch };
      } else if (s.pitch !== applied.pitch) {
        speaker.dsp.setPitch(s.pitch);
        applied.pitch = s.pitch;
      }
    } catch (e) {
      console.error("effect failed", e);
      applied.mode = null;
    }
    speaker.gain.gain.setTargetAtTime(s.gain / 100, ctx.currentTime, 0.02);
    speaker.player.port.postMessage({ target: s.buffer / 1000 });
  }

  function savedOutput() {
    try { return localStorage.getItem(OUTPUT_KEY) || "default"; } catch (e) { return "default"; }
  }

  function routeThroughElement(id) {
    if (!speaker.route) {
      const dest = ctx.createMediaStreamDestination();
      const el = new Audio();
      el.srcObject = dest.stream;
      speaker.gain.disconnect(ctx.destination);
      speaker.gain.connect(dest);
      speaker.route = { dest: dest, el: el };
    }
    const el = speaker.route.el;
    return el.setSinkId(id).then(function () { return el.play(); });
  }

  function unroute() {
    if (!speaker.route) return;
    speaker.gain.disconnect(speaker.route.dest);
    speaker.gain.connect(ctx.destination);
    speaker.route.el.srcObject = null;
    speaker.route = null;
  }

  async function setOutput(deviceId) {
    try { localStorage.setItem(OUTPUT_KEY, deviceId); } catch (e) {}
    if (!speaker) return;
    const id = deviceId === "default" ? "" : deviceId;
    try {
      if (ctx.setSinkId) {
        await ctx.setSinkId(id);
      } else if (!id) {
        unroute();
      } else if (HTMLMediaElement.prototype.setSinkId) {
        await routeThroughElement(id);
      } else {
        notice = "this browser cannot switch outputs";
      }
    } catch (e) {
      console.error("output switch failed", e);
      notice = "output unavailable: " + (e && e.name ? e.name : e);
    }
    render();
  }

  function restoreOutput() {
    if (outputRestored || !speaker) return;
    outputRestored = true;
    const id = savedOutput();
    if (id !== "default") setOutput(id);
  }

  async function populateOutputs(unlock) {
    if (!navigator.mediaDevices || !navigator.mediaDevices.enumerateDevices) return;
    if (unlock && !navigator.mediaDevices.selectAudioOutput) {
      try {
        const s = await navigator.mediaDevices.getUserMedia({ audio: true });
        s.getTracks().forEach(function (t) { t.stop(); });
      } catch (e) {}
    }
    const devices = await navigator.mediaDevices.enumerateDevices();
    const sel = $("output");
    const want = savedOutput();
    sel.innerHTML = "";
    const def = document.createElement("option");
    def.value = "default";
    def.textContent = "system default";
    sel.appendChild(def);
    let n = 0;
    for (const d of devices) {
      if (d.kind !== "audiooutput" || d.deviceId === "default" || !d.deviceId) continue;
      const opt = document.createElement("option");
      opt.value = d.deviceId;
      opt.textContent = d.label || ("output " + (++n));
      sel.appendChild(opt);
    }
    if (navigator.mediaDevices.selectAudioOutput) {
      const opt = document.createElement("option");
      opt.value = CHOOSE_OUTPUT;
      opt.textContent = "choose another output…";
      sel.appendChild(opt);
    }
    sel.value = [...sel.options].some(function (o) { return o.value === want; }) ? want : "default";
  }

  async function chooseOutput() {
    try {
      const device = await navigator.mediaDevices.selectAudioOutput();
      try { localStorage.setItem(OUTPUT_KEY, device.deviceId); } catch (e) {}
      await populateOutputs(false);
      await setOutput(device.deviceId);
    } catch (e) {
      await populateOutputs(false);
    }
  }

  function pushSetting(patch) {
    Object.assign(state.settings, patch);
    Object.assign(pending, patch);
    applySettings();
    render();
    if (!sendTimer) sendTimer = setTimeout(flushSettings, 60);
  }

  function flushSettings() {
    sendTimer = null;
    room.send({ t: "set", settings: pending });
    pending = {};
  }

  function onMessage(msg) {
    if (msg.t === "hello") {
      state.id = msg.id;
      return;
    }
    if (msg.t !== "state") return;
    const incoming = Object.assign({}, msg.settings);
    for (const key of Object.keys(pending)) incoming[key] = state.settings[key];
    if (editing.key && performance.now() < editing.until) incoming[editing.key] = state.settings[editing.key];
    state.mic = msg.mic;
    state.peers = msg.peers;
    state.rvc = msg.rvc;
    state.settings = Object.assign(state.settings, incoming);
    const r = role();
    if (mic && r !== "mic") {
      if (state.mic) {
        stopCapture();
        micWanted = false;
        notice = "the mic moved to another device";
      } else if (micWanted) {
        room.send({ t: "claim" });
      }
    }
    if (!mic && r === "mic") room.send({ t: "release" });
    if (r === "speaker") ensureSpeaker();
    applySettings();
    render();
  }

  function detailFor(r) {
    if (!online) return "reconnecting…";
    const others = Math.max(0, state.peers - 1);
    if (r === "mic") {
      if (muted) return "muted — nothing is being sent";
      if (!others) return "talk away — but no speaker is open; load this page on the output device";
      return "talk — " + (others === 1 ? "the other device plays" : others + " devices play") + " you";
    }
    if (r === "speaker") return "playing the voice from the mic device";
    return "press start mic on the device you talk into — every other open tab plays it";
  }

  function render() {
    const r = role();
    const card = $("roleCard");
    card.dataset.role = online ? r : "offline";
    $("roleTag").textContent = online ? r : "offline";
    $("roleDetail").textContent = detailFor(r);
    $("peers").textContent = online ? state.peers + (state.peers === 1 ? " device" : " devices") + " connected" : "";

    const toggle = $("micToggle");
    toggle.textContent = r === "mic" ? "stop mic" : (r === "speaker" ? "take the mic" : "start mic");
    toggle.disabled = !online;
    toggle.classList.toggle("ghost", r === "speaker");
    const mute = $("micMute");
    mute.hidden = r !== "mic";
    mute.textContent = muted ? "unmute" : "mute";

    $("unlock").hidden = !(r === "speaker" && ctx && ctx.state !== "running");
    $("outputField").hidden = r === "mic";

    const s = state.settings;
    if ($("mode").value !== s.mode) $("mode").value = s.mode;
    for (const key of Object.keys(FORMAT)) {
      const el = $(key);
      if (!(editing.key === key && performance.now() < editing.until) && Number(el.value) !== s[key]) el.value = s[key];
      $(key + "Val").textContent = FORMAT[key](s[key]);
    }
    const pitchOn = PITCH_MODES.has(s.mode);
    $("pitch").disabled = !pitchOn;
    $("pitchField").classList.toggle("off", !pitchOn);

    $("notice").hidden = !notice;
    $("notice").textContent = notice;

    const note = $("rvcStatus");
    const rvc = RVC_MODES.has(s.mode) ? (RVC_NOTE[state.rvc] || (state.mic ? null : ["starts when a mic is live", ""])) : null;
    note.hidden = !rvc;
    if (rvc) {
      note.textContent = rvc[0];
      note.dataset.level = rvc[1];
    }
  }

  function drawMeter() {
    const r = role();
    const analyser = r === "mic" ? (mic && mic.analyser) : (speaker && speaker.analyser);
    let peak = 0;
    if (analyser) {
      const data = new Float32Array(analyser.fftSize);
      analyser.getFloatTimeDomainData(data);
      for (let i = 0; i < data.length; i++) peak = Math.max(peak, Math.abs(data[i]));
    }
    $("level").value = Math.min(1, peak);
    let text = "";
    if (r === "speaker") {
      text = Math.round(stats.buffered * 1000) + " ms buf";
      if (stats.underruns) text += " · " + stats.underruns + " gaps";
    } else if (r === "mic" && ctx) {
      text = muted ? "muted" : (ctx.sampleRate / 1000).toFixed(1) + " kHz out";
    }
    $("stats").textContent = text;
    requestAnimationFrame(drawMeter);
  }

  function boot() {
    room = Room.connect({
      open: function () {
        online = true;
        if (micWanted && mic) room.send({ t: "claim" });
        render();
      },
      close: function () {
        online = false;
        state.id = null;
        render();
      },
      message: onMessage,
      frame: onFrame,
    });

    ["pointerdown", "keydown", "touchend"].forEach(function (ev) {
      document.addEventListener(ev, function () { ensureCtx(); }, { capture: true });
    });

    $("micToggle").addEventListener("click", function () {
      if (role() === "mic") { stopMic(); return; }
      notice = "";
      startMic().catch(function (e) {
        micWanted = false;
        stopCapture();
        notice = micError(e);
        render();
      });
    });
    $("micMute").addEventListener("click", function () {
      muted = !muted;
      render();
    });
    $("unlock").addEventListener("click", function () { ensureCtx(); });

    $("mode").addEventListener("change", function () {
      const mode = $("mode").value;
      const patch = { mode: mode };
      if (PRESET[mode] !== undefined) patch.pitch = PRESET[mode];
      pushSetting(patch);
    });
    for (const key of Object.keys(FORMAT)) {
      const el = $(key);
      el.addEventListener("input", function () {
        editing = { key: key, until: performance.now() + 600 };
        const patch = {};
        patch[key] = Number(el.value);
        pushSetting(patch);
      });
    }

    const out = $("output");
    out.addEventListener("change", function () {
      if (out.value === CHOOSE_OUTPUT) { chooseOutput(); return; }
      setOutput(out.value);
    });
    let outputsUnlocked = false;
    out.addEventListener("focus", function () {
      if (!outputsUnlocked) { outputsUnlocked = true; populateOutputs(true); }
    });
    populateOutputs(false);

    document.addEventListener("visibilitychange", function () {
      if (document.visibilityState === "visible") holdWakeLock();
    });

    ensureSpeaker();
    render();
    requestAnimationFrame(drawMeter);
  }

  boot();
})();
