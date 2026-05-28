#!/usr/bin/env python3
import json
import os
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

import sqlcipher3

DB_PATH = Path(os.environ["KEYSTATS_DB_PATH"])
DB_KEY_FILE = Path(os.environ["KEYSTATS_DB_KEY_FILE"])
HOST = os.environ.get("KEYSTATS_WEB_HOST", "0.0.0.0")
PORT = int(os.environ.get("KEYSTATS_WEB_PORT", "6900"))

CSP = (
    "default-src 'self'; "
    "script-src 'self'; "
    "style-src 'self' 'unsafe-inline'; "
    "connect-src 'self'; "
    "img-src 'self' data:; "
    "object-src 'none'; "
    "base-uri 'none'; "
    "frame-ancestors 'none'"
)


def load_key() -> str:
    raw = DB_KEY_FILE.read_text().strip()
    if not re.fullmatch(r"[0-9a-fA-F]{64}", raw):
        sys.exit(f"keystats: db key at {DB_KEY_FILE} must be 64 hex chars")
    return raw


KEY_HEX = ""


def open_db_ro():
    conn = sqlcipher3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    cur = conn.cursor()
    cur.execute(f"PRAGMA key = \"x'{KEY_HEX}'\"")
    cur.execute("PRAGMA cipher_compatibility = 4")
    cur.execute("PRAGMA query_only = 1")
    return conn


INDEX_HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>kl · keystroke stats</title>
<link rel="stylesheet" href="/static/style.css">
</head>
<body>
<header>
  <h1>kl <span class="sub">keystroke stats</span></h1>
  <nav>
    <span id="summary"></span>
  </nav>
</header>
<main>
  <section>
    <h2>heatmap</h2>
    <div id="heatmap"></div>
  </section>
  <section>
    <h2>WPM (last 7 days, 5-min buckets)</h2>
    <svg id="wpm" viewBox="0 0 800 200" preserveAspectRatio="none"></svg>
  </section>
  <section>
    <h2>top keys</h2>
    <svg id="topkeys" viewBox="0 0 800 300" preserveAspectRatio="xMidYMid meet"></svg>
  </section>
  <section>
    <h2>top bigrams</h2>
    <table id="bigrams"><thead><tr><th>k1</th><th>k2</th><th>count</th></tr></thead><tbody></tbody></table>
  </section>
  <section>
    <h2>by window class</h2>
    <svg id="classes" viewBox="0 0 800 240" preserveAspectRatio="xMidYMid meet"></svg>
  </section>
</main>
<script src="/static/app.js"></script>
</body>
</html>
"""


STYLE_CSS = r"""
:root {
  --bg: #0e0f12;
  --fg: #d8dee9;
  --dim: #6b7080;
  --accent: #88c0d0;
  --hot: #bf616a;
  --warm: #ebcb8b;
  --cool: #5e81ac;
  --line: #2a2d35;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  background: var(--bg);
  color: var(--fg);
  font: 14px/1.4 -apple-system, "Iosevka", "JetBrains Mono", monospace;
  padding: 24px;
  max-width: 1100px;
  margin: 0 auto;
}
header { display: flex; justify-content: space-between; align-items: baseline; padding-bottom: 12px; border-bottom: 1px solid var(--line); margin-bottom: 24px; }
header h1 { font-weight: 500; font-size: 24px; }
header .sub { color: var(--dim); font-weight: 400; font-size: 14px; margin-left: 8px; }
nav { color: var(--dim); font-size: 12px; }
section { margin-bottom: 36px; }
h2 { font-weight: 400; font-size: 13px; text-transform: uppercase; letter-spacing: 0.08em; color: var(--dim); margin-bottom: 12px; }
#heatmap { display: grid; grid-template-columns: repeat(15, 1fr); gap: 4px; }
.k {
  background: var(--line);
  border: 1px solid transparent;
  padding: 8px 4px;
  text-align: center;
  font-size: 11px;
  border-radius: 3px;
  position: relative;
  overflow: hidden;
}
.k .lbl { display: block; color: var(--fg); }
.k .cnt { display: block; color: var(--dim); font-size: 9px; margin-top: 2px; }
.k.w2 { grid-column: span 2; }
.k.w3 { grid-column: span 3; }
.k.w5 { grid-column: span 5; }
.k.w7 { grid-column: span 7; }
table { width: 100%; border-collapse: collapse; }
th, td { text-align: left; padding: 4px 8px; border-bottom: 1px solid var(--line); }
th { color: var(--dim); font-weight: 400; text-transform: uppercase; font-size: 11px; letter-spacing: 0.06em; }
td.num { text-align: right; font-variant-numeric: tabular-nums; color: var(--accent); }
svg text { fill: var(--dim); font-size: 10px; }
svg .bar { fill: var(--accent); }
svg .axis { stroke: var(--line); stroke-width: 1; }
svg .line { fill: none; stroke: var(--accent); stroke-width: 1.5; }
"""


APP_JS = r"""
const KC_NAMES = {
  1:"esc",2:"1",3:"2",4:"3",5:"4",6:"5",7:"6",8:"7",9:"8",10:"9",11:"0",12:"-",13:"=",14:"bksp",
  15:"tab",16:"q",17:"w",18:"e",19:"r",20:"t",21:"y",22:"u",23:"i",24:"o",25:"p",26:"[",27:"]",28:"enter",
  29:"ctrl",30:"a",31:"s",32:"d",33:"f",34:"g",35:"h",36:"j",37:"k",38:"l",39:";",40:"'",41:"`",42:"shift",
  43:"\\",44:"z",45:"x",46:"c",47:"v",48:"b",49:"n",50:"m",51:",",52:".",53:"/",54:"rshift",
  56:"alt",57:"space",58:"caps",
  100:"ralt",97:"rctrl",
  103:"↑",105:"←",106:"→",108:"↓",
  102:"home",107:"end",104:"pgup",109:"pgdn",110:"ins",111:"del"
};

const KB_ROWS = [
  [{c:1},{c:2},{c:3},{c:4},{c:5},{c:6},{c:7},{c:8},{c:9},{c:10},{c:11},{c:12},{c:13},{c:14,w:2}],
  [{c:15,w:2},{c:16},{c:17},{c:18},{c:19},{c:20},{c:21},{c:22},{c:23},{c:24},{c:25},{c:26},{c:27},{c:43}],
  [{c:58,w:2},{c:30},{c:31},{c:32},{c:33},{c:34},{c:35},{c:36},{c:37},{c:38},{c:39},{c:40},{c:28,w:2}],
  [{c:42,w:3},{c:44},{c:45},{c:46},{c:47},{c:48},{c:49},{c:50},{c:51},{c:52},{c:53},{c:54,w:3}],
  [{c:29,w:2},{c:125,w:1},{c:56},{c:57,w:7},{c:100},{c:127},{c:97,w:2}]
];

function clamp01(x){return Math.max(0,Math.min(1,x));}

function colorFor(intensity){
  const c1 = [42,45,53];
  const c2 = [136,192,208];
  const c3 = [235,203,139];
  const c4 = [191,97,106];
  function lerp(a,b,t){return [a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t];}
  let rgb;
  if(intensity<0.33){rgb=lerp(c1,c2,intensity/0.33);}
  else if(intensity<0.66){rgb=lerp(c2,c3,(intensity-0.33)/0.33);}
  else{rgb=lerp(c3,c4,(intensity-0.66)/0.34);}
  return `rgb(${rgb.map(v=>Math.round(v)).join(",")})`;
}

async function fetchJson(p){
  const r = await fetch(p);
  if(!r.ok) throw new Error(p+" "+r.status);
  return r.json();
}

function renderHeatmap(data){
  const el = document.getElementById("heatmap");
  const max = Math.max(1, ...Object.values(data));
  const frag = document.createDocumentFragment();
  for(const row of KB_ROWS){
    for(const k of row){
      const d = document.createElement("div");
      const w = k.w||1;
      d.className = "k" + (w>1?" w"+w:"");
      const cnt = data[k.c]||0;
      d.style.background = cnt>0 ? colorFor(clamp01(cnt/max)) : "var(--line)";
      const name = KC_NAMES[k.c] || ("k"+k.c);
      d.innerHTML = `<span class="lbl">${name}</span><span class="cnt">${cnt}</span>`;
      frag.appendChild(d);
    }
  }
  el.innerHTML = "";
  el.appendChild(frag);
}

function renderWPM(buckets){
  const svg = document.getElementById("wpm");
  if(!buckets.length){svg.innerHTML='<text x="10" y="20">no data yet</text>';return;}
  const w=800,h=200,pad=24;
  const xs=buckets.map(b=>b.epoch);
  const ys=buckets.map(b=>b.wpm);
  const xmin=Math.min(...xs),xmax=Math.max(...xs);
  const ymax=Math.max(1,...ys);
  const xscale=v=>pad+(v-xmin)/(xmax-xmin||1)*(w-2*pad);
  const yscale=v=>h-pad-v/ymax*(h-2*pad);
  const pts=buckets.map(b=>`${xscale(b.epoch).toFixed(1)},${yscale(b.wpm).toFixed(1)}`).join(" ");
  svg.innerHTML=`
    <polyline class="line" points="${pts}"/>
    <line class="axis" x1="${pad}" y1="${h-pad}" x2="${w-pad}" y2="${h-pad}"/>
    <line class="axis" x1="${pad}" y1="${pad}" x2="${pad}" y2="${h-pad}"/>
    <text x="${pad}" y="${pad-6}">${ymax.toFixed(1)} WPM peak</text>
  `;
}

function renderBars(svgId, rows, labelFn){
  const svg = document.getElementById(svgId);
  if(!rows.length){svg.innerHTML='<text x="10" y="20">no data yet</text>';return;}
  const w=800,h=300,pad=80;
  const max=Math.max(1,...rows.map(r=>r.count));
  const bh=(h-2*pad)/rows.length;
  let s='';
  rows.forEach((r,i)=>{
    const bw=(r.count/max)*(w-pad-20);
    const y=pad+i*bh;
    s += `<text x="${pad-6}" y="${(y+bh/2+3).toFixed(0)}" text-anchor="end">${labelFn(r)}</text>`;
    s += `<rect class="bar" x="${pad}" y="${(y+2).toFixed(0)}" width="${bw.toFixed(1)}" height="${(bh-4).toFixed(1)}"/>`;
    s += `<text x="${(pad+bw+4).toFixed(0)}" y="${(y+bh/2+3).toFixed(0)}">${r.count}</text>`;
  });
  svg.innerHTML=s;
}

function renderBigrams(rows){
  const tb=document.querySelector("#bigrams tbody");
  tb.innerHTML=rows.map(r=>`<tr><td>${KC_NAMES[r.k1]||r.k1}</td><td>${KC_NAMES[r.k2]||r.k2}</td><td class="num">${r.count}</td></tr>`).join("");
}

function renderSummary(s){
  const el=document.getElementById("summary");
  const total=(s.total_keys||0).toLocaleString();
  const dropped=(s.dropped||0).toLocaleString();
  el.textContent=`${total} keys logged · ${dropped} gated · ${s.sessions||0} sessions`;
}

async function refresh(){
  try{
    const [hm, wpm, top, bg, cls, sum] = await Promise.all([
      fetchJson("/api/heatmap"),
      fetchJson("/api/wpm"),
      fetchJson("/api/top-keys"),
      fetchJson("/api/bigrams"),
      fetchJson("/api/classes"),
      fetchJson("/api/summary")
    ]);
    renderHeatmap(hm);
    renderWPM(wpm);
    renderBars("topkeys", top.map(r=>({count:r.count,name:KC_NAMES[r.keycode]||("k"+r.keycode)})), r=>r.name);
    renderBigrams(bg);
    renderBars("classes", cls, r=>r.window_class||"(unknown)");
    renderSummary(sum);
  }catch(e){
    document.getElementById("summary").textContent="error: "+e.message;
  }
}
refresh();
setInterval(refresh, 30000);
"""


def respond(handler: BaseHTTPRequestHandler, status: int, body: bytes, ctype: str) -> None:
    handler.send_response(status)
    handler.send_header("Content-Type", ctype)
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Content-Security-Policy", CSP)
    handler.send_header("X-Content-Type-Options", "nosniff")
    handler.send_header("Referrer-Policy", "no-referrer")
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(body)


def json_body(obj) -> bytes:
    return json.dumps(obj, separators=(",", ":")).encode()


def q_summary(conn) -> dict:
    cur = conn.cursor()
    total = cur.execute("SELECT COALESCE(SUM(count),0) FROM keycode_count").fetchone()[0]
    dropped = cur.execute("SELECT COALESCE(SUM(dropped),0) FROM session").fetchone()[0]
    sessions = cur.execute("SELECT COUNT(*) FROM session").fetchone()[0]
    return {"total_keys": total, "dropped": dropped, "sessions": sessions}


def q_heatmap(conn) -> dict:
    cur = conn.cursor()
    rows = cur.execute("SELECT keycode, count FROM keycode_count").fetchall()
    return {str(k): c for k, c in rows}


def q_wpm(conn) -> list:
    cur = conn.cursor()
    cutoff = int(time.time() // 60) - 7 * 24 * 60
    rows = cur.execute(
        "SELECT (minute_epoch / 5) * 5 AS bucket, "
        "SUM(chars) AS c, SUM(words) AS w "
        "FROM wpm_bucket WHERE minute_epoch >= ? "
        "GROUP BY bucket ORDER BY bucket",
        (cutoff,),
    ).fetchall()
    out = []
    for bucket, c, w in rows:
        wpm = (w or 0) / 5.0
        out.append({"epoch": bucket * 60, "wpm": wpm, "chars": c})
    return out


def q_top_keys(conn) -> list:
    cur = conn.cursor()
    rows = cur.execute(
        "SELECT keycode, count FROM keycode_count ORDER BY count DESC LIMIT 20"
    ).fetchall()
    return [{"keycode": k, "count": c} for k, c in rows]


def q_bigrams(conn) -> list:
    cur = conn.cursor()
    rows = cur.execute(
        "SELECT k1, k2, count FROM bigram_count ORDER BY count DESC LIMIT 30"
    ).fetchall()
    return [{"k1": a, "k2": b, "count": c} for a, b, c in rows]


def q_classes(conn) -> list:
    cur = conn.cursor()
    rows = cur.execute(
        "SELECT window_class, count FROM class_count ORDER BY count DESC LIMIT 15"
    ).fetchall()
    return [{"window_class": w, "count": c} for w, c in rows]


ROUTES = {
    "/api/summary": (q_summary, "json"),
    "/api/heatmap": (q_heatmap, "json"),
    "/api/wpm": (q_wpm, "json"),
    "/api/top-keys": (q_top_keys, "json"),
    "/api/bigrams": (q_bigrams, "json"),
    "/api/classes": (q_classes, "json"),
}


class Handler(BaseHTTPRequestHandler):
    server_version = "keystats/1"

    def log_message(self, fmt, *args):
        pass

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/", "/index.html"):
            respond(self, 200, INDEX_HTML.encode(), "text/html; charset=utf-8")
            return
        if path == "/static/style.css":
            respond(self, 200, STYLE_CSS.encode(), "text/css; charset=utf-8")
            return
        if path == "/static/app.js":
            respond(self, 200, APP_JS.encode(), "application/javascript; charset=utf-8")
            return
        if path in ROUTES:
            handler_fn, _ = ROUTES[path]
            try:
                conn = open_db_ro()
                try:
                    data = handler_fn(conn)
                finally:
                    conn.close()
            except sqlcipher3.DatabaseError as e:
                respond(self, 503, json_body({"error": str(e)}), "application/json")
                return
            respond(self, 200, json_body(data), "application/json")
            return
        if path == "/healthz":
            respond(self, 200, b"ok", "text/plain")
            return
        respond(self, 404, b"not found\n", "text/plain")


def main() -> None:
    global KEY_HEX
    KEY_HEX = load_key()
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"keystats-web listening on {HOST}:{PORT}", file=sys.stderr)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()


if __name__ == "__main__":
    main()
