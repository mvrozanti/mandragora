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

// host -> { generated, entries: [{pname, version, max, cves, noise}] }
let STATE = { reports: {}, hosts: [], view: "all", showNoise: false, filter: "" };

function nvdUrl(id) { return `https://nvd.nist.gov/vuln/detail/${id}`; }

// For the "all" view: merge the same package across hosts into one row,
// unioning CVEs and tracking which hosts are affected.
function mergedEntries() {
  const byKey = new Map();
  for (const host of STATE.hosts) {
    const rep = STATE.reports[host];
    if (!rep) continue;
    for (const e of rep.entries) {
      const key = `${e.pname} ${e.version}`;
      let m = byKey.get(key);
      if (!m) { m = { pname: e.pname, version: e.version, max: 0, cveMap: new Map(), hosts: new Set() }; byKey.set(key, m); }
      m.max = Math.max(m.max, e.max);
      m.hosts.add(host);
      for (const c of e.cves) {
        const prev = m.cveMap.get(c.id);
        if (!prev || c.score > prev.score) m.cveMap.set(c.id, c);
      }
    }
  }
  return [...byKey.values()].map((m) => {
    const cves = [...m.cveMap.values()];
    const entry = { pname: m.pname, version: m.version, max: m.max, cves, hosts: [...m.hosts].sort() };
    entry.noise = isNoise(entry);
    return entry;
  });
}

function currentEntries() {
  if (STATE.view === "all") return mergedEntries();
  const rep = STATE.reports[STATE.view];
  if (!rep) return [];
  return rep.entries.map((e) => ({ ...e, hosts: [STATE.view] }));
}

function worstSevForHost(host) {
  const rep = STATE.reports[host];
  if (!rep) return "unk";
  let worst = 0;
  for (const e of rep.entries) if (!e.noise) worst = Math.max(worst, e.max);
  return sevOf(worst);
}

function renderTabs() {
  const tabs = document.getElementById("tabs");
  const mk = (id, label, sev, count) =>
    `<button class="tab ${STATE.view === id ? "active" : ""} sev-${sev}" data-host="${id}">` +
    `<span class="dot"></span>${escapeHtml(label)}<span class="cnt">${count}</span></button>`;
  const allReal = mergedEntries().filter((e) => !e.noise);
  let allWorst = 0; for (const e of allReal) allWorst = Math.max(allWorst, e.max);
  let html = mk("all", "all hosts", sevOf(allWorst), allReal.length);
  for (const host of STATE.hosts) {
    const rep = STATE.reports[host];
    const n = rep ? rep.entries.filter((e) => !e.noise).length : 0;
    html += mk(host, host, worstSevForHost(host), n);
  }
  tabs.innerHTML = html;
  tabs.querySelectorAll(".tab").forEach((b) =>
    b.addEventListener("click", () => { STATE.view = b.dataset.host; render(); }));
}

function render() {
  renderTabs();

  const all = currentEntries();
  const real = all.filter((e) => !e.noise);
  const buckets = { crit: [], high: [], med: [], low: [], unk: [] };
  for (const e of real) buckets[sevOf(e.max)].push(e);

  const summary = document.getElementById("summary");
  const clean = real.length === 0;
  summary.innerHTML =
    `<div class="card ${clean ? "clean" : ""}"><div class="n">${real.length}</div><div class="k">flagged pkgs</div></div>` +
    `<div class="card crit"><div class="n">${buckets.crit.length}</div><div class="k">critical</div></div>` +
    `<div class="card high"><div class="n">${buckets.high.length}</div><div class="k">high</div></div>` +
    `<div class="card med"><div class="n">${buckets.med.length}</div><div class="k">medium</div></div>` +
    `<div class="card low"><div class="n">${buckets.low.length}</div><div class="k">low</div></div>` +
    `<div class="card"><div class="n">${all.length - real.length}</div><div class="k">suppressed</div></div>`;

  const q = STATE.filter.trim().toLowerCase();
  let shown = all.slice();
  if (!STATE.showNoise) shown = shown.filter((e) => !e.noise);
  if (q) shown = shown.filter((e) =>
    e.pname.toLowerCase().includes(q) || e.cves.some((c) => c.id.toLowerCase().includes(q)));
  shown.sort((a, b) => b.max - a.max || a.pname.localeCompare(b.pname));

  const list = document.getElementById("list");
  if (!shown.length) {
    list.innerHTML = clean && !STATE.showNoise
      ? `<div class="empty">✓ no known vulnerabilities in this closure.</div>`
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
    const hostBadges = (STATE.view === "all" && e.hosts)
      ? e.hosts.map((h) => `<span class="host-badge">${escapeHtml(h)}</span>`).join("") : "";
    return `<div class="pkg ${sev}">
      <div class="pkg-head">
        <span class="score ${scoreCls}">${e.max ? e.max.toFixed(1) : "—"}</span>
        <span class="pname">${escapeHtml(e.pname)}</span>
        <span class="ver">${escapeHtml(e.version || "")}</span>
        ${hostBadges}
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

async function fetchHostList() {
  try {
    const res = await fetch("hosts.json", { cache: "no-store" });
    if (res.ok) {
      const arr = await res.json();
      if (Array.isArray(arr) && arr.length) return arr;
    }
  } catch (_) { /* fall through */ }
  return null;
}

async function fetchReport(host) {
  const res = await fetch(`report-${host}.json`, { cache: "no-store" });
  if (!res.ok) throw new Error(`report-${host}.json ${res.status}`);
  const data = await res.json();
  return { generated: data.generated || "?", entries: (data.entries || []).map((e) => ({ ...e, noise: isNoise(e) })) };
}

async function load() {
  const meta = document.getElementById("meta");
  const hosts = await fetchHostList();

  // Back-compat: pre-multihost publishers wrote a single report.json.
  if (!hosts) {
    try {
      const res = await fetch("report.json", { cache: "no-store" });
      if (res.ok) {
        const data = await res.json();
        const h = data.host || "system";
        STATE.reports[h] = { generated: data.generated || "?", entries: (data.entries || []).map((e) => ({ ...e, noise: isNoise(e) })) };
        STATE.hosts = [h];
        STATE.view = "all";
        meta.textContent = `${h} · generated ${data.generated || "?"}`;
        render();
        return;
      }
    } catch (_) { /* fall through */ }
    meta.textContent = "no reports yet — run cve-scan + vuln-publish on a host";
    document.getElementById("list").innerHTML =
      `<div class="empty">no host reports found.<br>on any mandragora host: ` +
      `<code>systemctl --user start cve-scan.service &amp;&amp; vuln-publish</code></div>`;
    return;
  }

  const results = await Promise.allSettled(hosts.map(fetchReport));
  const okHosts = [];
  results.forEach((r, i) => {
    if (r.status === "fulfilled") { STATE.reports[hosts[i]] = r.value; okHosts.push(hosts[i]); }
  });
  STATE.hosts = okHosts.sort();
  if (!STATE.hosts.length) {
    meta.textContent = "host manifest present but no reports fetched";
    document.getElementById("list").innerHTML = `<div class="empty">hosts.json listed ${escapeHtml(hosts.join(", "))} but none loaded.</div>`;
    return;
  }
  const stamps = STATE.hosts.map((h) => `${h} ${STATE.reports[h].generated}`).join(" · ");
  meta.textContent = `${STATE.hosts.length} host(s) · ${stamps}`;
  render();
}

document.getElementById("show-noise").addEventListener("change", (e) => { STATE.showNoise = e.target.checked; render(); });
document.getElementById("filter").addEventListener("input", (e) => { STATE.filter = e.target.value; render(); });
load();
