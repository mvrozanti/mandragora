import http from "node:http";
import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const staticDir = path.join(here, "..", "static");
const fx = (name) => JSON.parse(readFileSync(path.join(here, "fixtures", name), "utf8"));

const scenario = process.env.SCENARIO || "fresh";
const port = Number(process.env.PORT || 8790);
const AGE = { fresh: 25, stale: 200, silent: 7800 };
const STEP = 300;

const sample = fx("status-sample.json");
const probes = fx("probes-2026-10-10.json");
const meta = fx("hosts-meta.json");
const theme = fx("theme.json");

function build() {
  const now = Math.floor(Date.now() / 1000);
  const generated = now - AGE[scenario];
  const shift = Math.round((generated - sample.generated) / STEP) * STEP;
  const status = JSON.parse(JSON.stringify(sample));
  status.generated = generated;
  status.start += shift;
  status.end += shift;
  status.probes = { source: "desktop", step: STEP, start: probes.start + shift, end: probes.end + shift, hosts: probes.hosts };
  const ringStart = Math.round((now - 6 * 3600) / STEP) * STEP;
  const ringEnd = Math.floor(now / STEP) * STEP;
  const n = (ringEnd - ringStart) / STEP + 1;
  const silentBuckets = scenario === "silent" ? Math.ceil(AGE.silent / STEP) : 0;
  const hosts = {};
  for (const [h, s] of Object.entries(probes.hosts)) {
    let states = "";
    for (let i = 0; i < n; i++) {
      const t = ringStart + i * STEP;
      const k = Math.round((t - status.probes.start) / STEP);
      let c = k >= 0 && k < s.length ? s[k] : "o";
      if (meta[h] && meta[h].where === "desk" && i >= n - silentBuckets) c = "d";
      states += c;
    }
    const last = states[states.length - 1];
    const state = last === "d" ? "down" : last === "w" ? "warn" : "ok";
    hosts[h] = { ...(meta[h] || {}), states, now: { state, code: state === "down" ? 502 : 200, ms: 40 + (h.length * 7) % 80 } };
  }
  const desk = status.hosts.vps;
  const fact = (k) => (desk.facts.find((f) => f.key === k) || {}).value;
  const cpu = desk.series.find((s) => s.key === "cpu").values.filter((v) => v != null).pop();
  const used = fact("rootSize") - fact("rootFree");
  return {
    "/data/status.json": status,
    "/data/theme.json": theme,
    "/data/pull.json": scenario === "fresh" ? { ok_at: generated, fail_at: null, error: null } : { ok_at: generated, fail_at: now - 20, error: "connect timeout" },
    "/api/status-probes": { ts: now, step: STEP, start: ringStart, end: ringEnd, hosts },
    "/api/vps": { cpu: { util_pct: cpu }, disk: { used_gb: used, total_gb: fact("rootSize"), used_pct: (used * 100) / fact("rootSize") }, ts: now }
  };
}

const TYPES = { ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".json": "application/json" };

http.createServer((req, res) => {
  const url = new URL(req.url, "http://localhost");
  const routes = build();
  if (routes[url.pathname]) {
    res.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-store" });
    return res.end(JSON.stringify(routes[url.pathname]));
  }
  if (url.pathname === "/__hold") {
    return setTimeout(() => { res.writeHead(204); res.end(); }, 1500);
  }
  const file = path.join(staticDir, url.pathname === "/" ? "index.html" : url.pathname);
  if (!file.startsWith(staticDir) || !existsSync(file)) { res.writeHead(404); return res.end("not found"); }
  let body = readFileSync(file);
  if (file.endsWith("index.html") && process.env.HOLD) body = Buffer.from(String(body).replace("</body>", '<img src="/__hold" alt="" width="1" height="1"></body>'));
  res.writeHead(200, { "Content-Type": TYPES[path.extname(file)] || "application/octet-stream" });
  res.end(body);
}).listen(port, "127.0.0.1", () => console.log(`status preview (${scenario}) on http://127.0.0.1:${port}/`));
