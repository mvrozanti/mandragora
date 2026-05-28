(() => {
  "use strict";

  const API = "/api/gource";
  const form = document.getElementById("render-form");
  const submitBtn = document.getElementById("submit-btn");
  const statusEl = document.getElementById("status");
  const videoWrap = document.getElementById("video-wrap");
  const video = document.getElementById("video");
  const downloadLink = document.getElementById("download-link");
  const metaText = document.getElementById("video-meta-text");

  let pollTimer = null;
  let currentJob = null;

  function showStatus(html) {
    statusEl.innerHTML = html;
    statusEl.classList.add("visible");
  }

  function hideVideo() {
    videoWrap.classList.remove("visible");
    video.removeAttribute("src");
    video.load();
  }

  function showVideo(url, meta) {
    video.src = url;
    downloadLink.href = url;
    metaText.textContent = meta || "";
    videoWrap.classList.add("visible");
    video.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }

  function setSubmitting(submitting) {
    submitBtn.disabled = submitting;
    submitBtn.textContent = submitting ? "rendering…" : "render";
  }

  function toIsoDate(s) {
    if (!s) return null;
    const m = s.trim().match(/^(\d{4})[\/\-](\d{2})[\/\-](\d{2})$/);
    if (!m) throw new Error(`bad date "${s}" — expected yyyy/MM/dd`);
    return `${m[1]}-${m[2]}-${m[3]}`;
  }

  function readForm() {
    const dateMin = toIsoDate(form.date_min.value);
    const dateMax = toIsoDate(form.date_max.value);
    const lengthS = parseInt(form.length_s.value, 10) || 60;
    const [w, h] = form.resolution.value.split("x").map((n) => parseInt(n, 10));
    return {
      date_min: dateMin,
      date_max: dateMax,
      length_s: lengthS,
      width: w,
      height: h,
    };
  }

  function attachDateMask(input) {
    input.addEventListener("input", (ev) => {
      const start = input.selectionStart;
      const before = input.value;
      const digits = before.replace(/\D/g, "").slice(0, 8);
      let out = digits;
      if (digits.length > 4) out = digits.slice(0, 4) + "/" + digits.slice(4);
      if (digits.length > 6) out = digits.slice(0, 4) + "/" + digits.slice(4, 6) + "/" + digits.slice(6);
      if (out !== before) {
        input.value = out;
        const delta = out.length - before.length;
        const pos = Math.max(0, (start ?? out.length) + Math.max(0, delta));
        input.setSelectionRange(pos, pos);
      }
    });
  }
  attachDateMask(form.date_min);
  attachDateMask(form.date_max);

  function fmtBackend(b) {
    if (!b) return "";
    if (b === "desktop") return "rendered on desktop";
    if (b === "vps") return "rendered on vps (fallback)";
    if (b === "cache") return "cache hit";
    return b;
  }

  async function postRender(params) {
    const res = await fetch(`${API}/render`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(params),
    });
    if (res.status === 429) {
      const retry = res.headers.get("Retry-After") || "60";
      throw new Error(`rate limited — retry in ${retry}s`);
    }
    if (!res.ok) {
      let detail = `http ${res.status}`;
      try {
        const j = await res.json();
        if (j.detail) detail = typeof j.detail === "string" ? j.detail : JSON.stringify(j.detail);
      } catch (_) {}
      throw new Error(detail);
    }
    return res.json();
  }

  async function getStatus(jobId) {
    const res = await fetch(`${API}/status/${encodeURIComponent(jobId)}`);
    if (!res.ok) throw new Error(`status http ${res.status}`);
    return res.json();
  }

  function paint(s) {
    const pct = typeof s.progress === "number" ? Math.max(0, Math.min(100, Math.round(s.progress * 100))) : null;
    const stateClass = s.state === "failed" ? "failed" : s.state === "done" ? "done" : "";
    let html = `<span class="state ${stateClass}">${s.state}</span>`;
    if (s.message) html += ` — ${s.message}`;
    if (pct !== null && s.state !== "done") html += `<progress max="100" value="${pct}"></progress>`;
    if (s.queue_position && s.state === "queued") html += `<span class="meta">queue position: ${s.queue_position}</span>`;
    if (s.backend) html += `<span class="meta">${fmtBackend(s.backend)}</span>`;
    if (s.error) html += `<span class="meta">error: ${s.error}</span>`;
    showStatus(html);
  }

  function stopPolling() {
    if (pollTimer) {
      clearTimeout(pollTimer);
      pollTimer = null;
    }
  }

  function scheduleNext(jobId, delay) {
    pollTimer = setTimeout(() => pollOnce(jobId), delay);
  }

  async function pollOnce(jobId) {
    if (currentJob !== jobId) return;
    try {
      const s = await getStatus(jobId);
      paint(s);
      if (s.state === "done") {
        setSubmitting(false);
        showVideo(s.video_url || `${API}/video/${jobId}`, fmtBackend(s.backend));
        return;
      }
      if (s.state === "failed") {
        setSubmitting(false);
        return;
      }
      scheduleNext(jobId, 1500);
    } catch (err) {
      paint({ state: "failed", error: String(err.message || err) });
      setSubmitting(false);
    }
  }

  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    stopPolling();
    hideVideo();
    setSubmitting(true);
    showStatus(`<span class="state">submitting…</span>`);
    let params;
    try {
      params = readForm();
    } catch (err) {
      paint({ state: "failed", error: String(err.message || err) });
      setSubmitting(false);
      return;
    }
    try {
      const r = await postRender(params);
      currentJob = r.job_id;
      paint(r);
      if (r.state === "done") {
        setSubmitting(false);
        showVideo(r.video_url || `${API}/video/${r.job_id}`, fmtBackend(r.backend));
        return;
      }
      scheduleNext(r.job_id, 800);
    } catch (err) {
      paint({ state: "failed", error: String(err.message || err) });
      setSubmitting(false);
    }
  });

  window.addEventListener("beforeunload", stopPolling);
})();
