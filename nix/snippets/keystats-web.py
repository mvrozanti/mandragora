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

TEXT_DB_KEY_FILE = os.environ.get("KEYSTATS_TEXT_DB_KEY_FILE", "").strip()
TEXT_DB_PATH = os.environ.get("KEYSTATS_TEXT_DB_PATH", "").strip()
TEXT_ENABLED = bool(TEXT_DB_KEY_FILE and TEXT_DB_PATH and Path(TEXT_DB_PATH).exists())

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
TEXT_KEY_HEX = ""


def load_text_key() -> str:
    raw = Path(TEXT_DB_KEY_FILE).read_text().strip()
    if not re.fullmatch(r"[0-9a-fA-F]{64}", raw):
        sys.exit(f"keystats: text db key at {TEXT_DB_KEY_FILE} must be 64 hex chars")
    return raw


def open_db_ro():
    conn = sqlcipher3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    cur = conn.cursor()
    cur.execute(f"PRAGMA key = \"x'{KEY_HEX}'\"")
    cur.execute("PRAGMA cipher_compatibility = 4")
    cur.execute("PRAGMA query_only = 1")
    return conn


def open_text_db_ro():
    conn = sqlcipher3.connect(f"file:{TEXT_DB_PATH}?mode=ro", uri=True)
    cur = conn.cursor()
    cur.execute(f"PRAGMA key = \"x'{TEXT_KEY_HEX}'\"")
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
    <div id="extras"></div>
  </section>

  <section>
    <h2>at a glance</h2>
    <div class="cards" id="cards"></div>
  </section>

  <section>
    <h2>hand balance</h2>
    <div id="handbar"></div>
  </section>

  <section>
    <h2>row distribution</h2>
    <div id="rowbar"></div>
  </section>

  <section>
    <h2>WPM (last 7 days, 5-min buckets)</h2>
    <svg id="wpm" viewBox="0 0 800 200" preserveAspectRatio="none"></svg>
  </section>

  <section>
    <h2>time of day (last 7 days)</h2>
    <svg id="tod" viewBox="0 0 800 120" preserveAspectRatio="none"></svg>
  </section>

  <section>
    <h2>weekday × hour heatmap</h2>
    <div id="weekday"></div>
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

  <section id="words-section" hidden>
    <h2>wordcloud</h2>
    <div id="words"></div>
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
  --dim: #9aa3b3;
  --accent: #9fd0e0;
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
#heatmap { display: grid; grid-template-columns: repeat(18, 1fr); gap: 3px; }
.k {
  background: var(--line);
  border: 1px solid transparent;
  padding: 6px 3px;
  text-align: center;
  font-size: 10px;
  border-radius: 3px;
  position: relative;
  overflow: hidden;
  min-height: 30px;
}
.k .lbl { display: block; color: var(--fg); text-shadow: 0 0 2px rgba(0,0,0,0.85); }
.k .cnt { display: block; color: var(--fg); opacity: 0.85; font-size: 8px; margin-top: 2px; text-shadow: 0 0 2px rgba(0,0,0,0.85); }
.k.dark .lbl, .k.dark .cnt { color: #0e0f12; text-shadow: 0 0 2px rgba(255,255,255,0.55); }
.k.gap { background: transparent; }
.k.w2 { grid-column: span 2; }
.k.w3 { grid-column: span 3; }
.k.w5 { grid-column: span 5; }
.k.w6 { grid-column: span 6; }
.k.w7 { grid-column: span 7; }
#extras { display: grid; grid-template-columns: repeat(auto-fill, minmax(60px, 1fr)); gap: 3px; margin-top: 8px; }
table { width: 100%; border-collapse: collapse; }
th, td { text-align: left; padding: 4px 8px; border-bottom: 1px solid var(--line); }
th { color: var(--dim); font-weight: 400; text-transform: uppercase; font-size: 11px; letter-spacing: 0.06em; }
td.num { text-align: right; font-variant-numeric: tabular-nums; color: var(--accent); }
svg text { fill: var(--dim); font-size: 10px; }
svg .bar { fill: var(--accent); }
svg .axis { stroke: var(--line); stroke-width: 1; }
svg .line { fill: none; stroke: var(--accent); stroke-width: 1.5; }
.cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 12px; }
.card { background: var(--line); border-radius: 4px; padding: 12px; }
.card .v { display: block; font-size: 22px; color: var(--accent); font-variant-numeric: tabular-nums; }
.card .l { display: block; font-size: 10px; color: var(--dim); text-transform: uppercase; letter-spacing: 0.06em; margin-top: 4px; }
.split { display: flex; height: 28px; border-radius: 3px; overflow: hidden; font-size: 11px; }
.split > div { display: flex; align-items: center; justify-content: center; font-weight: 600; }
.split .left  { background: var(--cool); color: #f5f7fa; }
.split .right { background: var(--warm); color: #0e0f12; }
.rowbars { display: flex; flex-direction: column; gap: 6px; }
.rowbars .row { display: grid; grid-template-columns: 80px 1fr 48px; align-items: center; gap: 8px; font-size: 11px; }
.rowbars .row .lbl { color: var(--dim); text-transform: uppercase; letter-spacing: 0.05em; }
.rowbars .row .track { background: var(--line); height: 14px; border-radius: 2px; overflow: hidden; }
.rowbars .row .fill { background: var(--accent); height: 100%; }
.rowbars .row .pct { color: var(--accent); text-align: right; font-variant-numeric: tabular-nums; }
#weekday { display: grid; grid-template-columns: 32px repeat(24, 1fr); gap: 2px; font-size: 9px; }
#weekday .dow { color: var(--dim); text-transform: uppercase; align-self: center; }
#weekday .h { color: var(--dim); text-align: center; padding-bottom: 2px; }
#weekday .cell { background: var(--line); aspect-ratio: 1; border-radius: 2px; }
#words { display: flex; flex-wrap: wrap; gap: 8px 12px; align-items: baseline; line-height: 1.1; }
#words .w { color: var(--fg); }
#words .w.hot { color: var(--hot); }
#words .w.warm { color: var(--warm); }
#words .w.cool { color: var(--cool); }
#words .w.dim { color: var(--dim); }
"""


APP_JS = r"""
const KC_NAMES = {
  1:"esc",2:"1",3:"2",4:"3",5:"4",6:"5",7:"6",8:"7",9:"8",10:"9",11:"0",12:"-",13:"=",14:"bksp",
  15:"tab",16:"q",17:"w",18:"e",19:"r",20:"t",21:"y",22:"u",23:"i",24:"o",25:"p",26:"[",27:"]",28:"enter",
  29:"ctrl",30:"a",31:"s",32:"d",33:"f",34:"g",35:"h",36:"j",37:"k",38:"l",39:";",40:"'",41:"`",42:"shift",
  43:"\\",44:"z",45:"x",46:"c",47:"v",48:"b",49:"n",50:"m",51:",",52:".",53:"/",54:"rshift",
  55:"kp*",56:"alt",57:"space",58:"caps",
  59:"F1",60:"F2",61:"F3",62:"F4",63:"F5",64:"F6",65:"F7",66:"F8",67:"F9",68:"F10",
  69:"num",70:"slk",
  71:"kp7",72:"kp8",73:"kp9",74:"kp-",75:"kp4",76:"kp5",77:"kp6",78:"kp+",
  79:"kp1",80:"kp2",81:"kp3",82:"kp0",83:"kp.",
  87:"F11",88:"F12",
  96:"kpEnt",97:"rctrl",98:"kp/",99:"prsc",100:"ralt",
  102:"home",103:"↑",104:"pgup",105:"←",106:"→",107:"end",108:"↓",109:"pgdn",110:"ins",111:"del",
  119:"pause",125:"super",126:"rsuper",127:"menu",
  113:"mute",114:"vol-",115:"vol+",163:"next",164:"play",165:"prev",
  142:"sleep",148:"calc",150:"www",217:"search",128:"stop",172:"home",173:"refresh"
};

const KB_ROWS = [
  [{gap:1},{c:142},{c:148},{c:150},{c:217},{gap:1},{c:165},{c:164},{c:163},{c:128},{gap:1},{c:113},{c:114},{c:115},{c:172},{c:173},{gap:2}],
  [{c:1},{c:59},{c:60},{c:61},{c:62},{gap:1},{c:63},{c:64},{c:65},{c:66},{gap:1},{c:67},{c:68},{c:87},{c:88},{c:99},{c:70},{c:119}],
  [{c:41},{c:2},{c:3},{c:4},{c:5},{c:6},{c:7},{c:8},{c:9},{c:10},{c:11},{c:12},{c:13},{c:14,w:2},{c:110},{c:102},{c:104}],
  [{c:15,w:2},{c:16},{c:17},{c:18},{c:19},{c:20},{c:21},{c:22},{c:23},{c:24},{c:25},{c:26},{c:27},{c:43},{c:111},{c:107},{c:109}],
  [{c:58,w:2},{c:30},{c:31},{c:32},{c:33},{c:34},{c:35},{c:36},{c:37},{c:38},{c:39},{c:40},{c:28,w:2},{gap:3}],
  [{c:42,w:3},{c:44},{c:45},{c:46},{c:47},{c:48},{c:49},{c:50},{c:51},{c:52},{c:53},{c:54,w:2},{gap:1},{c:103},{gap:1}],
  [{c:29,w:2},{c:125},{c:56},{c:57,w:6},{c:100},{c:127},{c:97,w:2},{gap:1},{c:105},{c:108},{c:106}]
];

function clamp01(x){return Math.max(0,Math.min(1,x));}
function esc(s){return String(s).replace(/[<>&"']/g, c=>({"<":"&lt;",">":"&gt;","&":"&amp;",'"':"&quot;","'":"&#39;"}[c]));}

function rgbFor(intensity){
  const c1 = [42,45,53];
  const c2 = [136,192,208];
  const c3 = [235,203,139];
  const c4 = [191,97,106];
  function lerp(a,b,t){return [a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t];}
  let rgb;
  if(intensity<0.33){rgb=lerp(c1,c2,intensity/0.33);}
  else if(intensity<0.66){rgb=lerp(c2,c3,(intensity-0.33)/0.33);}
  else{rgb=lerp(c3,c4,(intensity-0.66)/0.34);}
  return rgb.map(v=>Math.round(v));
}
function colorFor(intensity){
  return `rgb(${rgbFor(intensity).join(",")})`;
}
function needsDarkText(rgb){
  const lum = 0.2126*rgb[0] + 0.7152*rgb[1] + 0.0722*rgb[2];
  return lum > 150;
}

async function fetchJson(p){
  const r = await fetch(p);
  if(!r.ok) throw new Error(p+" "+r.status);
  return r.json();
}

function renderHeatmap(data){
  const el = document.getElementById("heatmap");
  const max = Math.max(1, ...Object.values(data).map(Number));
  const placed = new Set();
  const frag = document.createDocumentFragment();
  for(const row of KB_ROWS){
    for(const k of row){
      const d = document.createElement("div");
      if(k.gap){
        const w = k.gap;
        d.className = "k gap" + (w>1?" w"+w:"");
        d.innerHTML = "";
        frag.appendChild(d);
        continue;
      }
      const w = k.w||1;
      let cls = "k" + (w>1?" w"+w:"");
      const cnt = data[k.c]||0;
      placed.add(k.c);
      if(cnt>0){
        const rgb = rgbFor(clamp01(cnt/max));
        d.style.background = `rgb(${rgb.join(",")})`;
        if(needsDarkText(rgb)) cls += " dark";
      } else {
        d.style.background = "var(--line)";
      }
      d.className = cls;
      const name = KC_NAMES[k.c] || ("k"+k.c);
      d.innerHTML = `<span class="lbl">${name}</span><span class="cnt">${cnt}</span>`;
      frag.appendChild(d);
    }
  }
  el.innerHTML = "";
  el.appendChild(frag);

  const extras = document.getElementById("extras");
  if(extras){
    const extra = Object.entries(data)
      .map(([k,v])=>[parseInt(k),Number(v)])
      .filter(([k,v])=> v>0 && !placed.has(k))
      .sort((a,b)=>b[1]-a[1]);
    if(extra.length === 0){
      extras.innerHTML = '<div class="card"><span class="l">no off-layout keys</span></div>';
    } else {
      extras.innerHTML = extra.map(([k,v])=>{
        const name = KC_NAMES[k] || ("k"+k);
        const rgb = rgbFor(clamp01(v/max));
        const cls = "k" + (needsDarkText(rgb) ? " dark" : "");
        return `<div class="${cls}" style="background:rgb(${rgb.join(",")})"><span class="lbl">${name}</span><span class="cnt">${v}</span></div>`;
      }).join("");
    }
  }
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
    const bw=(r.count/max)*(w-pad-70);
    const y=pad+i*bh;
    s += `<text x="${pad-6}" y="${(y+bh/2+3).toFixed(0)}" text-anchor="end">${esc(labelFn(r))}</text>`;
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

function renderCards(ins){
  const cards=[
    ["backspace",   (ins.backspace_pct||0).toFixed(1)+"%"],
    ["modifiers",   (ins.modifier_pct||0).toFixed(1)+"%"],
    ["space",       (ins.space_pct||0).toFixed(1)+"%"],
    ["arrows",      (ins.arrow_pct||0).toFixed(1)+"%"],
    ["punctuation", (ins.punct_pct||0).toFixed(1)+"%"],
    ["same-finger bigrams", (ins.same_finger_bigram_pct||0).toFixed(1)+"%"],
    ["bigrams",     (ins.bigram_count||0).toLocaleString()],
    ["keys logged", (ins.total_keystrokes||0).toLocaleString()],
  ];
  document.getElementById("cards").innerHTML = cards.map(([l,v])=>`<div class="card"><span class="v">${v}</span><span class="l">${l}</span></div>`).join("");
}

function renderHandBar(ins){
  const l=ins.hand_balance.left_pct, r=ins.hand_balance.right_pct;
  document.getElementById("handbar").innerHTML = `<div class="split">
    <div class="left" style="width:${l}%">L ${l.toFixed(1)}%</div>
    <div class="right" style="width:${r}%">R ${r.toFixed(1)}%</div>
  </div>`;
}

function renderRowBar(ins){
  const rows=[
    ["number", ins.row_dist.num_pct],
    ["top",    ins.row_dist.top_pct],
    ["home",   ins.row_dist.home_pct],
    ["bottom", ins.row_dist.bottom_pct],
  ];
  const max=Math.max(1, ...rows.map(r=>r[1]));
  document.getElementById("rowbar").innerHTML = `<div class="rowbars">` + rows.map(([n,p])=>`
    <div class="row">
      <span class="lbl">${n}</span>
      <div class="track"><div class="fill" style="width:${(p/max*100).toFixed(1)}%"></div></div>
      <span class="pct">${p.toFixed(1)}%</span>
    </div>
  `).join("") + `</div>`;
}

function renderTOD(buckets){
  const svg=document.getElementById("tod");
  const w=800,h=120,pad=24;
  const max=Math.max(1,...buckets.map(b=>b.chars));
  const cellW=(w-2*pad)/24;
  let s='';
  buckets.forEach((b,i)=>{
    const bh=(b.chars/max)*(h-2*pad);
    const x=pad+i*cellW;
    const y=h-pad-bh;
    s += `<rect class="bar" x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${(cellW-1).toFixed(1)}" height="${bh.toFixed(1)}"/>`;
    if(i%3===0) s += `<text x="${(x+cellW/2).toFixed(1)}" y="${(h-6).toFixed(0)}" text-anchor="middle">${String(b.hour).padStart(2,"0")}h</text>`;
  });
  s += `<text x="${pad}" y="${pad-6}">${max.toLocaleString()} peak</text>`;
  svg.innerHTML = s;
}

function renderWeekday(grid){
  const DOW = ["sun","mon","tue","wed","thu","fri","sat"];
  let max=1;
  for(const row of grid){ for(const v of row){ if(v>max) max=v; } }
  let s = '<div class="h"></div>';
  for(let h=0;h<24;h++){ s += `<div class="h">${h%6===0?String(h).padStart(2,"0"):""}</div>`; }
  for(let d=0;d<7;d++){
    s += `<div class="dow">${DOW[d]}</div>`;
    for(let h=0;h<24;h++){
      const v = grid[d][h]||0;
      const intensity = clamp01(v/max);
      const bg = v>0 ? colorFor(intensity) : "var(--line)";
      s += `<div class="cell" style="background:${bg}" title="${DOW[d]} ${h}h · ${v}"></div>`;
    }
  }
  document.getElementById("weekday").innerHTML = s;
}

function renderWords(rows){
  const el = document.getElementById("words");
  if(!rows.length){ el.innerHTML = '<span class="w dim">no words yet — need ≥3 occurrences across distinct minute-buckets</span>'; return; }
  const max = Math.max(...rows.map(r=>r.count));
  const min = Math.min(...rows.map(r=>r.count));
  const span = Math.max(1, max - min);
  el.innerHTML = rows.map(r=>{
    const t = (r.count - min) / span;
    const px = (12 + t*36).toFixed(1);
    let cls = "w dim";
    if(t > 0.85) cls = "w hot";
    else if(t > 0.6) cls = "w warm";
    else if(t > 0.3) cls = "w cool";
    const w = esc(r.word);
    return `<span class="${cls}" style="font-size:${px}px" title="${r.count}">${w}</span>`;
  }).join("");
}

async function setupWords(){
  try{
    const rows = await fetchJson("/api/words");
    document.getElementById("words-section").hidden = false;
    renderWords(rows);
  }catch(e){ /* 404 = disabled, leave hidden */ }
}
setupWords();

async function refresh(){
  try{
    const [hm, wpm, top, bg, cls, sum, ins, tod, wkd] = await Promise.all([
      fetchJson("/api/heatmap"),
      fetchJson("/api/wpm"),
      fetchJson("/api/top-keys"),
      fetchJson("/api/bigrams"),
      fetchJson("/api/classes"),
      fetchJson("/api/summary"),
      fetchJson("/api/insights"),
      fetchJson("/api/time-of-day"),
      fetchJson("/api/weekday-heatmap")
    ]);
    renderHeatmap(hm);
    renderCards(ins);
    renderHandBar(ins);
    renderRowBar(ins);
    renderWPM(wpm);
    renderTOD(tod);
    renderWeekday(wkd);
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


LEFT_KEYS = {1, 2, 3, 4, 5, 6, 15, 16, 17, 18, 19, 20, 29, 30, 31, 32, 33, 34, 41, 42, 44, 45, 46, 47, 48, 58}
RIGHT_KEYS = {7, 8, 9, 10, 11, 12, 13, 14, 21, 22, 23, 24, 25, 26, 27, 35, 36, 37, 38, 39, 40, 43, 49, 50, 51, 52, 53, 54}
NUM_ROW = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14}
TOP_ROW = {15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 43}
HOME_ROW = {28, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 58}
BOTTOM_ROW = {42, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54}
MODIFIERS = {29, 42, 54, 56, 97, 100, 125, 126}
BACKSPACE = 14
SPACE = 57
PUNCT = {12, 13, 26, 27, 39, 40, 41, 43, 51, 52, 53}

FINGER = {}
for k in (1, 2, 15, 16, 30, 31, 44, 41, 42, 58):
    FINGER[k] = "LP"
for k in (3, 17, 32, 45):
    FINGER[k] = "LR"
for k in (4, 18, 33, 46):
    FINGER[k] = "LM"
for k in (5, 6, 19, 20, 34, 35, 47, 48):
    FINGER[k] = "LI"
for k in (7, 8, 21, 22, 36, 37, 49, 50):
    FINGER[k] = "RI"
for k in (9, 23, 38, 51):
    FINGER[k] = "RM"
for k in (10, 24, 39, 52):
    FINGER[k] = "RR"
for k in (11, 12, 13, 14, 25, 26, 27, 40, 43, 53, 54):
    FINGER[k] = "RP"


def q_insights(conn) -> dict:
    cur = conn.cursor()
    rows = cur.execute("SELECT keycode, count FROM keycode_count").fetchall()
    total = sum(c for _, c in rows) or 1
    left = sum(c for k, c in rows if k in LEFT_KEYS)
    right = sum(c for k, c in rows if k in RIGHT_KEYS)
    sided = left + right or 1
    rowed_keys = NUM_ROW | TOP_ROW | HOME_ROW | BOTTOM_ROW
    rowed_total = sum(c for k, c in rows if k in rowed_keys) or 1
    num = sum(c for k, c in rows if k in NUM_ROW)
    top = sum(c for k, c in rows if k in TOP_ROW)
    home = sum(c for k, c in rows if k in HOME_ROW)
    bottom = sum(c for k, c in rows if k in BOTTOM_ROW)
    mods = sum(c for k, c in rows if k in MODIFIERS)
    punct = sum(c for k, c in rows if k in PUNCT)
    bksp = next((c for k, c in rows if k == BACKSPACE), 0)
    space = next((c for k, c in rows if k == SPACE), 0)
    arrows = sum(c for k, c in rows if k in (103, 105, 106, 108))

    bg_rows = cur.execute("SELECT k1, k2, count FROM bigram_count").fetchall()
    bg_total = sum(c for _, _, c in bg_rows) or 1
    same_finger = sum(
        c for k1, k2, c in bg_rows
        if FINGER.get(k1) and FINGER.get(k1) == FINGER.get(k2) and k1 != k2
    )

    return {
        "total_keystrokes": total,
        "hand_balance": {
            "left_pct": round(100.0 * left / sided, 2),
            "right_pct": round(100.0 * right / sided, 2),
        },
        "row_dist": {
            "num_pct":    round(100.0 * num    / rowed_total, 2),
            "top_pct":    round(100.0 * top    / rowed_total, 2),
            "home_pct":   round(100.0 * home   / rowed_total, 2),
            "bottom_pct": round(100.0 * bottom / rowed_total, 2),
        },
        "modifier_pct":  round(100.0 * mods   / total, 2),
        "backspace_pct": round(100.0 * bksp   / total, 2),
        "space_pct":     round(100.0 * space  / total, 2),
        "punct_pct":     round(100.0 * punct  / total, 2),
        "arrow_pct":     round(100.0 * arrows / total, 2),
        "same_finger_bigram_pct": round(100.0 * same_finger / bg_total, 2),
        "bigram_count": bg_total,
    }


def q_time_of_day(conn) -> list:
    cur = conn.cursor()
    cutoff = int(time.time() // 60) - 7 * 24 * 60
    rows = cur.execute(
        "SELECT CAST(strftime('%H', minute_epoch * 60, 'unixepoch', 'localtime') AS INTEGER) AS hour, "
        "SUM(chars) AS chars "
        "FROM wpm_bucket WHERE minute_epoch >= ? "
        "GROUP BY hour ORDER BY hour",
        (cutoff,),
    ).fetchall()
    out = [{"hour": h, "chars": 0} for h in range(24)]
    for h, c in rows:
        out[h]["chars"] = c
    return out


def q_words() -> list:
    conn = open_text_db_ro()
    try:
        cur = conn.cursor()
        rows = cur.execute(
            "SELECT word, count FROM word_count ORDER BY count DESC LIMIT 200"
        ).fetchall()
        return [{"word": w, "count": c} for w, c in rows]
    finally:
        conn.close()


WEEKDAY_HEATMAP_SQL = (
    "SELECT CAST(strftime('%w', sec, 'unixepoch', 'localtime') AS INTEGER) AS dow, "
    "CAST(strftime('%H', sec, 'unixepoch', 'localtime') AS INTEGER) AS hour, "
    "SUM(chars) AS chars FROM ({src}) GROUP BY dow, hour"
)

WEEKDAY_HEATMAP_UNION_SRC = (
    "SELECT minute_epoch * 60 AS sec, chars FROM wpm_bucket "
    "UNION ALL "
    "SELECT hour_epoch * 3600 AS sec, chars FROM wpm_hourly"
)

WEEKDAY_HEATMAP_BUCKET_SRC = "SELECT minute_epoch * 60 AS sec, chars FROM wpm_bucket"


def q_weekday_heatmap(conn) -> list:
    cur = conn.cursor()
    try:
        rows = cur.execute(
            WEEKDAY_HEATMAP_SQL.format(src=WEEKDAY_HEATMAP_UNION_SRC)
        ).fetchall()
    except sqlcipher3.OperationalError:
        rows = cur.execute(
            WEEKDAY_HEATMAP_SQL.format(src=WEEKDAY_HEATMAP_BUCKET_SRC)
        ).fetchall()
    grid = [[0] * 24 for _ in range(7)]
    for dow, hour, chars in rows:
        if dow is None or hour is None:
            continue
        grid[int(dow)][int(hour)] = chars
    return grid


ROUTES = {
    "/api/summary": (q_summary, "json"),
    "/api/heatmap": (q_heatmap, "json"),
    "/api/wpm": (q_wpm, "json"),
    "/api/top-keys": (q_top_keys, "json"),
    "/api/bigrams": (q_bigrams, "json"),
    "/api/classes": (q_classes, "json"),
    "/api/insights": (q_insights, "json"),
    "/api/time-of-day": (q_time_of_day, "json"),
    "/api/weekday-heatmap": (q_weekday_heatmap, "json"),
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
        if path == "/api/words":
            if not TEXT_ENABLED:
                respond(self, 404, b"not enabled\n", "text/plain")
                return
            try:
                data = q_words()
            except sqlcipher3.DatabaseError as e:
                respond(self, 503, json_body({"error": str(e)}), "application/json")
                return
            respond(self, 200, json_body(data), "application/json")
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
    global KEY_HEX, TEXT_KEY_HEX
    KEY_HEX = load_key()
    if TEXT_ENABLED:
        TEXT_KEY_HEX = load_text_key()
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
