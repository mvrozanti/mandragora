"use strict";

// Noise filter — ported from ~/.ai-shared/rules/cve-scan.md triage.
// Packages flagged by vulnix but known false positives (name collisions).
const NOISE_SUFFIX = ["-tex"];
const NOISE_EXACT = new Set([
  "ShellCheck|CVE-2021-28794", // VS Code extension, not the binary
  "kitty|CVE-2016-2563",       // PuTTY/KiTTY SSH client, not the terminal
  "hyper|CVE-2024-23741",      // Hyper terminal macOS, not Rust HTTP lib
  "snappy|CVE-2023-28115",     // PHP knp-snappy, not C snappy
  "snappy|CVE-2023-41330",
  "memcached|CVE-2022-26635",  // PHP-Memcached, not the daemon
]);

function isNoise(e) {
  if (NOISE_SUFFIX.some((s) => e.pname.endsWith(s))) return true;
  if (!e.cves.length) return false;
  return e.cves.every((c) => NOISE_EXACT.has(`${e.pname}|${c.id}`));
}

function sevOf(score) {
  if (score >= 9.0) return "crit";
  if (score >= 7.0) return "high";
  if (score >= 4.0) return "med";
  if (score > 0) return "low";
  return "unk";
}
const SEV_LABEL = { crit: "critical ≥9", high: "high 7–9", med: "medium 4–7", low: "low <4", unk: "unscored" };

let STATE = { entries: [], showNoise: false, filter: "" };

function nvdUrl(id) { return `https://nvd.nist.gov/vuln/detail/${id}`; }

function render() {
  const real = STATE.entries.filter((e) => !e.noise);
  const buckets = { crit: [], high: [], med: [], low: [], unk: [] };
  for (const e of real) buckets[sevOf(e.max)].push(e);

  const cards = [
    { k: "crit", label: "critical", n: buckets.crit.length },
    { k: "high", label: "high", n: buckets.high.length },
    { k: "med", label: "medium", n: buckets.med.length },
    { k: "low", label: "low", n: buckets.low.length },
  ];
  const total = real.length;
  const summary = document.getElementById("summary");
  const clean = total === 0;
  summary.innerHTML =
    `<div class="card ${clean ? "clean" : ""}"><div class="n">${total}</div><div class="k">flagged pkgs</div></div>` +
    cards.map((c) => `<div class="card ${c.k}"><div class="n">${c.n}</div><div class="k">${c.label}</div></div>`).join("") +
    `<div class="card"><div class="n">${STATE.entries.length - total}</div><div class="k">suppressed</div></div>`;

  const q = STATE.filter.trim().toLowerCase();
  let shown = STATE.entries.slice();
  if (!STATE.showNoise) shown = shown.filter((e) => !e.noise);
  if (q) shown = shown.filter((e) =>
    e.pname.toLowerCase().includes(q) || e.cves.some((c) => c.id.toLowerCase().includes(q)));
  shown.sort((a, b) => b.max - a.max || a.pname.localeCompare(b.pname));

  const list = document.getElementById("list");
  if (!shown.length) {
    list.innerHTML = clean && !STATE.showNoise
      ? `<div class="empty">✓ no known vulnerabilities in the current system closure.</div>`
      : `<div class="empty">no matches.</div>`;
    return;
  }
  list.innerHTML = shown.map((e) => {
    const sev = e.noise ? "noise" : sevOf(e.max);
    const scoreCls = sevOf(e.max);
    const cves = e.cves.slice().sort((a, b) => b.score - a.score).map((c) =>
      `<li class="cve"><a href="${nvdUrl(c.id)}" target="_blank" rel="noopener">${c.id}</a>` +
      `<span class="cs"> ${c.score ? c.score.toFixed(1) : "—"}</span>` +
      `${c.desc ? " · " + escapeHtml(c.desc) : ""}</li>`).join("");
    return `<div class="pkg ${sev}">
      <div class="pkg-head">
        <span class="score ${scoreCls}">${e.max ? e.max.toFixed(1) : "—"}</span>
        <span class="pname">${escapeHtml(e.pname)}</span>
        <span class="ver">${escapeHtml(e.version || "")}</span>
        ${e.noise ? '<span class="badge">suppressed</span>' : ""}
      </div>
      <ul class="cves">${cves}</ul>
    </div>`;
  }).join("");
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

async function load() {
  const meta = document.getElementById("meta");
  try {
    const res = await fetch("report.json", { cache: "no-store" });
    if (!res.ok) throw new Error(res.status);
    const data = await res.json();
    STATE.entries = (data.entries || []).map((e) => ({ ...e, noise: isNoise(e) }));
    document.getElementById("foot-host").textContent = data.host || "unknown";
    meta.textContent = `generated ${data.generated || "?"} · ${data.host || ""}`;
  } catch (err) {
    meta.textContent = "no report yet — run cve-scan + vuln-publish";
    document.getElementById("list").innerHTML =
      `<div class="empty">report.json not found (${escapeHtml(String(err.message || err))}).<br>` +
      `on the desktop: <code>systemctl --user start cve-scan.service &amp;&amp; vuln-publish</code></div>`;
    return;
  }
  render();
}

document.getElementById("show-noise").addEventListener("change", (e) => { STATE.showNoise = e.target.checked; render(); });
document.getElementById("filter").addEventListener("input", (e) => { STATE.filter = e.target.value; render(); });
load();
