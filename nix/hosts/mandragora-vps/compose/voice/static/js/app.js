(function () {
  "use strict";

  const $ = (id) => document.getElementById(id);

  const PROTOCOL = 2;
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
  const LOST = {
    taken: "the mic moved to another device",
    dropped: "the other device stopped the mic",
  };
  const OUTPUT_KEY = "voice.output";
  const RELOAD_KEY = "voice.reloaded";
  const CHOOSE_OUTPUT = "__choose__";

  const state = {
    id: null,
    mic: null,
    peers: 0,
    blocked: 0,
    rvc: "off",
    settings: { mode: "bypass", pitch: 0, buffer: 80, gain: 100, muted: false },
  };

  let room = null;
  let online = false;
  let ctx = null;
  let modules = null;
  let mic = null;
  let micWanted = false;
  let notice = "";
  let noticeAt = 0;
  let wakeLock = null;
  let speaker = null;
  let speakerPending = null;
  let outputRestored = false;
  let reportedBlocked = null;
  let applied = { mode: null, pitch: null };
  let stats = { buffered: 0, underruns: 0 };
  let lastFrameAt = 0;
  let editing = { key: null, until: 0 };
  let pending = {};
  let sendTimer = null;
  let lastSent = 0;

  function role() {
    if (!state.mic || !state.id) return "idle";
    return state.mic === state.id ? "mic" : "speaker";
  }

  function reloadOnce() {
    let last = 0;
    try { last = Number(sessionStorage.getItem(RELOAD_KEY)) || 0; } catch (e) {}
    if (Date.now() - last < 30000) {
      notice = "this page is out of date — reload it";
      noticeAt = performance.now();
      render();
      return;
    }
    try { sessionStorage.setItem(RELOAD_KEY, String(Date.now())); } catch (e) {}
    location.reload();
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
        reportBlocked();
        render();
      };
    }
    if (ctx.state !== "running") ctx.resume().catch(function () {});
    return modules;
  }

  function wakeCtx() {
    if (ctx && ctx.state !== "running") ctx.resume().catch(function () {});
  }

  function reportBlocked() {
    const blocked = role() === "speaker" && !!ctx && ctx.state !== "running";
    if (blocked === reportedBlocked || !room) return;
    reportedBlocked = blocked;
    room.send({ t: "status", blocked: blocked });
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

  async function capture() {
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
      if (!state.settings.muted && role() === "mic") room.sendPcm(e.data, ctx.sampleRate);
    };
    const track = stream.getAudioTracks()[0];
    if (track) track.addEventListener("ended", onTrackEnded);
    mic = { stream: stream, source: source, tap: tap, silent: silent, analyser: analyser };
  }

  async function startMic() {
    notice = "";
    await capture();
    micWanted = true;
    room.send({ t: "claim" });
    holdWakeLock();
    render();
  }

  function stopCapture() {
    if (!mic) return;
    mic.stream.getTracks().forEach(function (t) {
      t.removeEventListener("ended", onTrackEnded);
      t.stop();
    });
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

  function onTrackEnded() {
    if (!micWanted) return;
    stopCapture();
    capture().then(function () {
      room.send({ t: "claim" });
      holdWakeLock();
      render();
    }).catch(function () {
      micWanted = false;
      room.send({ t: "release" });
      notice = "the mic was interrupted — press start mic again";
      noticeAt = performance.now();
      render();
    });
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
      reportBlocked();
      render();
    }).catch(function (e) {
      console.error("speaker setup failed", e);
      notice = "audio engine failed: " + (e && e.message ? e.message : e);
      noticeAt = performance.now();
      render();
    }).finally(function () { speakerPending = null; });
    return speakerPending;
  }

  function onFrame(frame) {
    if (!speaker || role() !== "speaker") return;
    lastFrameAt = performance.now();
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
        noticeAt = performance.now();
      }
    } catch (e) {
      console.error("output switch failed", e);
      notice = "output unavailable: " + (e && e.name ? e.name : e);
      noticeAt = performance.now();
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
    const wait = 40 - (performance.now() - lastSent);
    if (wait <= 0) flushSettings();
    else if (!sendTimer) sendTimer = setTimeout(flushSettings, wait);
  }

  function flushSettings() {
    if (sendTimer) { clearTimeout(sendTimer); sendTimer = null; }
    lastSent = performance.now();
    room.send({ t: "set", settings: pending });
    pending = {};
  }

  function onMessage(msg) {
    if (msg.t === "hello") {
      if (msg.v !== PROTOCOL) { reloadOnce(); return; }
      state.id = msg.id;
      reportedBlocked = null;
      return;
    }
    if (msg.t === "lost") {
      micWanted = false;
      stopCapture();
      notice = LOST[msg.why] || "";
      noticeAt = performance.now();
      render();
      return;
    }
    if (msg.t !== "state") return;
    const before = role();
    const incoming = Object.assign({}, msg.settings);
    for (const key of Object.keys(pending)) incoming[key] = state.settings[key];
    if (editing.key && performance.now() < editing.until) incoming[editing.key] = state.settings[editing.key];
    state.mic = msg.mic;
    state.peers = msg.peers;
    state.blocked = msg.blocked || 0;
    state.rvc = msg.rvc;
    state.settings = Object.assign(state.settings, incoming);
    const r = role();
    if (!mic && r === "mic") room.send({ t: "release" });
    if (r === "speaker") ensureSpeaker();
    if (r === "speaker" && before !== "speaker") lastFrameAt = performance.now();
    reportBlocked();
    applySettings();
    render();
  }

  function detailFor(r) {
    if (!online) return "reconnecting…";
    const others = Math.max(0, state.peers - 1);
    const muted = state.settings.muted;
    if (r === "mic") {
      if (muted) return "muted — nothing is being sent";
      if (!others) return "no speaker yet — open this page on the output device and it plays automatically";
      if (state.blocked) return "the speaker tab is blocked from playing sound — click anywhere on it once";
      return "talk — " + (others === 1 ? "the other device plays" : others + " devices play") + " you";
    }
    if (r === "speaker") {
      if (muted) return "the mic is muted";
      if (ctx && ctx.state !== "running") return "sound is blocked here — click anywhere";
      if (performance.now() - lastFrameAt > 2500 && !(RVC_MODES.has(state.settings.mode) && state.rvc !== "ready")) {
        return "the mic is on but no audio is arriving";
      }
      return "playing the voice from the mic device";
    }
    return "press start mic on the device you talk into — every other open tab plays it";
  }

  function render() {
    const r = role();
    const card = $("roleCard");
    card.dataset.role = online ? r : "offline";
    $("roleTag").textContent = online ? r : "offline";
    $("roleDetail").textContent = detailFor(r);
    $("peers").textContent = online ? state.peers + (state.peers === 1 ? " device" : " devices") + " connected" : "";

    const s = state.settings;
    const toggle = $("micToggle");
    toggle.textContent = r === "mic" ? "stop mic" : (r === "speaker" ? "take the mic" : "start mic");
    toggle.disabled = !online;
    toggle.classList.toggle("ghost", r === "speaker");
    const mute = $("micMute");
    mute.hidden = r === "idle" || !online;
    mute.textContent = s.muted ? "unmute" : "mute";
    $("micDrop").hidden = r !== "speaker" || !online;

    $("unlock").hidden = !(r === "speaker" && ctx && ctx.state !== "running");
    $("outputField").hidden = r === "mic";

    if ($("mode").value !== s.mode) $("mode").value = s.mode;
    for (const key of Object.keys(FORMAT)) {
      const el = $(key);
      if (!(editing.key === key && performance.now() < editing.until) && Number(el.value) !== s[key]) el.value = s[key];
      $(key + "Val").textContent = FORMAT[key](s[key]);
    }
    const pitchOn = PITCH_MODES.has(s.mode);
    $("pitch").disabled = !pitchOn;
    $("pitchField").classList.toggle("off", !pitchOn);

    if (notice && performance.now() - noticeAt > 8000) notice = "";
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
      text = state.settings.muted ? "muted" : (ctx.sampleRate / 1000).toFixed(1) + " kHz out";
    }
    $("stats").textContent = text;
    $("roleDetail").textContent = detailFor(r);
    if (notice && performance.now() - noticeAt > 8000) render();
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
      authExpired: function () { location.reload(); },
      message: onMessage,
      frame: onFrame,
    });

    ["pointerdown", "keydown", "touchend"].forEach(function (ev) {
      document.addEventListener(ev, wakeCtx, { capture: true });
    });

    $("micToggle").addEventListener("click", function () {
      if (role() === "mic") { stopMic(); return; }
      startMic().catch(function (e) {
        micWanted = false;
        stopCapture();
        notice = micError(e);
        noticeAt = performance.now();
        render();
      });
    });
    $("micMute").addEventListener("click", function () {
      pushSetting({ muted: !state.settings.muted });
    });
    $("micDrop").addEventListener("click", function () {
      room.send({ t: "drop" });
    });
    $("unlock").addEventListener("click", wakeCtx);

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
      if (document.visibilityState !== "visible") return;
      wakeCtx();
      holdWakeLock();
      if (micWanted && mic && mic.stream.getAudioTracks().every(function (t) { return t.readyState === "ended"; })) {
        onTrackEnded();
      }
    });

    render();
    requestAnimationFrame(drawMeter);
  }

  boot();
})();
