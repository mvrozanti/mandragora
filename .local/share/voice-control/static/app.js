const DESC = {
  "voice-bypass":    "clean · no morph",
  "voice-deeper":    "pitch −3 · formant −1",
  "voice-higher":    "pitch +4 · formant +2",
  "voice-anime":     "pitch +6 · formant +3 · sparkle",
  "voice-demon":     "pitch −7 · saturation · hall",
  "voice-robot":     "vocoder · bitcrush",
  "voice-radio":     "telephone band · 300–3.4k",
  "voice-helium":    "pitch +10 · formant +5",
  "voice-broadcast": "denoise · deess · multiband",
};

const $ = (s) => document.querySelector(s);
const grid = $("#grid");
const activeEl = $("#active");
const eeEl = $("#ee");

async function refresh() {
  const s = await fetch("/api/status").then(r => r.json()).catch(() => null);
  if (!s) { eeEl.textContent = "unreachable"; eeEl.className = "value pill bad"; return; }
  activeEl.textContent = s.active || "—";
  activeEl.className = "value pill" + (s.active ? " ok" : "");
  eeEl.textContent = s.easyeffects ? "up" : "down";
  eeEl.className = "value pill " + (s.easyeffects ? "ok" : "bad");
  renderTiles(s.presets || [], s.active);
}

function renderTiles(presets, active) {
  grid.innerHTML = "";
  for (const p of presets) {
    const b = document.createElement("button");
    b.className = "tile" + (p === active ? " active" : "");
    b.innerHTML = `<div class="name">${p.replace(/^voice-/, "")}</div><div class="desc">${DESC[p] || ""}</div>`;
    b.onclick = async () => {
      b.disabled = true;
      const r = await fetch(`/api/preset/${encodeURIComponent(p)}`, { method: "POST" });
      b.disabled = false;
      if (!r.ok) {
        const j = await r.json().catch(() => ({}));
        alert("load failed: " + (j.error || r.status));
        return;
      }
      refresh();
    };
    grid.appendChild(b);
  }
}

$("#bypass").onclick = async () => {
  const r = await fetch("/api/bypass", { method: "POST" });
  if (!r.ok) alert("bypass failed");
  refresh();
};

let audioCtx, analyser, anim, mediaStream;
const picker = $("#device-picker");
const status = document.createElement("span");
status.className = "muted";
status.style.marginLeft = "8px";
$("#preview").after(status);

function refillPicker(devs, preferId) {
  picker.innerHTML = "";
  for (const d of devs) {
    const o = document.createElement("option");
    o.value = d.deviceId;
    o.textContent = d.label || `mic (${d.deviceId.slice(0, 8)})`;
    picker.appendChild(o);
  }
  if (preferId) picker.value = preferId;
}

async function listDevices() {
  const all = await navigator.mediaDevices.enumerateDevices();
  refillPicker(all.filter(d => d.kind === "audioinput"));
  refillOutputs(all.filter(d => d.kind === "audiooutput"));
  return all;
}

const outPicker = $("#output-picker");
function refillOutputs(devs) {
  outPicker.innerHTML = "";
  for (const d of devs) {
    const o = document.createElement("option");
    o.value = d.deviceId;
    o.textContent = d.label || `out (${d.deviceId.slice(0, 8)})`;
    outPicker.appendChild(o);
  }
}
outPicker.onchange = async () => {
  if (audioCtx && audioCtx.setSinkId) {
    try { await audioCtx.setSinkId(outPicker.value); status.textContent = `output → ${outPicker.selectedOptions[0]?.textContent}`; }
    catch (e) { alert("setSinkId failed: " + e.message); }
  }
};

$("#preview").onclick = async () => {
  if (audioCtx) { stopPreview(); return; }
  try {
    let stream = await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false },
    });
    const devs = (await navigator.mediaDevices.enumerateDevices()).filter(d => d.kind === "audioinput");
    const ee = devs.find(d => /easyeffects/i.test(d.label));
    const wantId = picker.value || ee?.deviceId;
    if (wantId && stream.getAudioTracks()[0]?.getSettings().deviceId !== wantId) {
      stream.getTracks().forEach(t => t.stop());
      stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          deviceId: { exact: wantId },
          echoCancellation: false, noiseSuppression: false, autoGainControl: false,
        },
      });
    }
    refillPicker(devs, stream.getAudioTracks()[0]?.getSettings().deviceId || wantId);
    mediaStream = stream;
    audioCtx = new AudioContext({ latencyHint: "interactive" });
    if (audioCtx.state === "suspended") await audioCtx.resume();
    if (outPicker.value && audioCtx.setSinkId) { try { await audioCtx.setSinkId(outPicker.value); } catch {} }
    const src = audioCtx.createMediaStreamSource(mediaStream);
    analyser = audioCtx.createAnalyser();
    analyser.fftSize = 1024;
    const gain = audioCtx.createGain();
    gain.gain.value = 1.0;
    src.connect(analyser);
    src.connect(gain).connect(audioCtx.destination);
    drawMeter();
    $("#preview").textContent = "stop ■";
    const lbl = mediaStream.getAudioTracks()[0]?.label || "(unknown)";
    status.textContent = `monitoring: ${lbl} · ctx=${audioCtx.state} · sr=${audioCtx.sampleRate}`;
  } catch (e) {
    alert("mic monitor blocked: " + e.message);
    status.textContent = "error: " + e.message;
  }
};

function stopPreview() {
  cancelAnimationFrame(anim);
  mediaStream?.getTracks().forEach(t => t.stop());
  audioCtx?.close();
  audioCtx = null;
  mediaStream = null;
  $("#preview").textContent = "monitor ▶";
  status.textContent = "";
  const ctx = $("#meter").getContext("2d");
  ctx.clearRect(0, 0, 320, 32);
}

picker.onchange = () => { if (audioCtx) { stopPreview(); $("#preview").click(); } };
listDevices();

function drawMeter() {
  const buf = new Uint8Array(analyser.fftSize);
  const ctx = $("#meter").getContext("2d");
  const tick = () => {
    analyser.getByteTimeDomainData(buf);
    let peak = 0;
    for (let i = 0; i < buf.length; i++) {
      const v = Math.abs(buf[i] - 128);
      if (v > peak) peak = v;
    }
    const w = (peak / 128) * 320;
    ctx.clearRect(0, 0, 320, 32);
    ctx.fillStyle = peak > 100 ? "#ef4444" : peak > 60 ? "#f59e0b" : "#8ab4f8";
    ctx.fillRect(0, 8, w, 16);
    anim = requestAnimationFrame(tick);
  };
  tick();
}

refresh();
setInterval(refresh, 4000);
