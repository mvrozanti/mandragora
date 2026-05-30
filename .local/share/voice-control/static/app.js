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

async function populateDevices(preferLabel = /easyeffects/i) {
  try { await navigator.mediaDevices.getUserMedia({ audio: true }).then(s => s.getTracks().forEach(t => t.stop())); } catch {}
  const devs = (await navigator.mediaDevices.enumerateDevices()).filter(d => d.kind === "audioinput");
  picker.innerHTML = "";
  for (const d of devs) {
    const o = document.createElement("option");
    o.value = d.deviceId;
    o.textContent = d.label || `mic (${d.deviceId.slice(0, 8)})`;
    picker.appendChild(o);
  }
  const ee = devs.find(d => preferLabel.test(d.label));
  if (ee) picker.value = ee.deviceId;
}

$("#preview").onclick = async () => {
  if (audioCtx) { stopPreview(); return; }
  try {
    const deviceId = picker.value || undefined;
    mediaStream = await navigator.mediaDevices.getUserMedia({
      audio: {
        deviceId: deviceId ? { exact: deviceId } : undefined,
        echoCancellation: false, noiseSuppression: false, autoGainControl: false,
      },
    });
    audioCtx = new AudioContext();
    const src = audioCtx.createMediaStreamSource(mediaStream);
    analyser = audioCtx.createAnalyser();
    analyser.fftSize = 1024;
    const gain = audioCtx.createGain();
    gain.gain.value = 1.0;
    src.connect(analyser);
    src.connect(gain).connect(audioCtx.destination);
    drawMeter();
    $("#preview").textContent = "stop ■";
    populateDevices();
  } catch (e) {
    alert("mic monitor blocked: " + e.message);
  }
};

function stopPreview() {
  cancelAnimationFrame(anim);
  mediaStream?.getTracks().forEach(t => t.stop());
  audioCtx?.close();
  audioCtx = null;
  mediaStream = null;
  $("#preview").textContent = "monitor ▶";
  const ctx = $("#meter").getContext("2d");
  ctx.clearRect(0, 0, 320, 32);
}

picker.onchange = () => { if (audioCtx) { stopPreview(); $("#preview").click(); } };
populateDevices();

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
