#!/usr/bin/env python3
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import uuid
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

HOST = os.environ.get("YTDL_HOST", "0.0.0.0")
PORT = int(os.environ.get("YTDL_PORT", "6685"))
MUSIC_DIR = Path(os.environ.get("YTDL_MUSIC_DIR", os.path.expanduser("~/Music")))
YT_DLP = os.environ.get("YTDL_YT_DLP", shutil.which("yt-dlp") or "yt-dlp")
FFMPEG_LOCATION = os.environ.get("YTDL_FFMPEG_LOCATION", "")
CLAUDE_BIN = os.environ.get("YTDL_CLAUDE", shutil.which("claude") or "claude")
TAG_MODEL = os.environ.get("YTDL_TAG_MODEL", "haiku")
JOB_TTL = int(os.environ.get("YTDL_JOB_TTL", "86400"))
MAX_JOBS = 200

TAG_SCHEMA = '{"type":"object","properties":{"title":{"type":"string"},"artist":{"type":"string"}},"required":["title","artist"]}'
TAG_PROMPT = (
    "Extract the song title and performing artist from this YouTube video title. "
    "Strip junk like '(Official Video)', '[HD]', 'Lyrics', channel names. "
    "If artist is unclear, use best guess from the title. Title: "
)

URL_RE = re.compile(r"^https?://[^\s]+$")

jobs_lock = threading.Lock()
jobs = {}
job_order = deque()


def now():
    return time.time()


def make_job(url):
    jid = uuid.uuid4().hex[:12]
    job = {
        "id": jid,
        "url": url,
        "status": "queued",
        "started": now(),
        "finished": None,
        "filename": None,
        "title": None,
        "artist": None,
        "exit_code": None,
        "log": deque(maxlen=400),
    }
    with jobs_lock:
        jobs[jid] = job
        job_order.append(jid)
        while len(job_order) > MAX_JOBS:
            old = job_order.popleft()
            jobs.pop(old, None)
    return job


def gc_jobs():
    cutoff = now() - JOB_TTL
    with jobs_lock:
        stale = [jid for jid, j in jobs.items() if j["finished"] and j["finished"] < cutoff]
        for jid in stale:
            jobs.pop(jid, None)
            try:
                job_order.remove(jid)
            except ValueError:
                pass


def tag_mp3(job):
    fn = job.get("filename")
    if not fn:
        return
    path = MUSIC_DIR / fn
    if not path.is_file():
        return
    raw = path.stem
    try:
        proc = subprocess.run(
            [CLAUDE_BIN, "-p", "--model", TAG_MODEL, "--output-format", "json",
             "--json-schema", TAG_SCHEMA, TAG_PROMPT + raw],
            capture_output=True, text=True, timeout=120,
        )
    except Exception as exc:
        job["log"].append(f"tag: claude failed: {exc!r}")
        return
    if proc.returncode != 0:
        job["log"].append(f"tag: claude exit {proc.returncode}: {proc.stderr.strip()[:200]}")
        return
    try:
        data = json.loads(proc.stdout)
        so = data.get("structured_output") or {}
        title = so.get("title")
        artist = so.get("artist")
    except Exception as exc:
        job["log"].append(f"tag: parse failed: {exc!r}")
        return
    if not title or not artist:
        job["log"].append(f"tag: empty title/artist: {proc.stdout.strip()[:200]}")
        return
    ffmpeg = os.path.join(FFMPEG_LOCATION, "ffmpeg") if FFMPEG_LOCATION else "ffmpeg"
    tmp = path.with_suffix(".tagged.mp3")
    try:
        r = subprocess.run(
            [ffmpeg, "-y", "-loglevel", "error", "-i", str(path), "-map", "0",
             "-c", "copy", "-metadata", f"title={title}", "-metadata", f"artist={artist}", str(tmp)],
            capture_output=True, text=True, timeout=120,
        )
    except Exception as exc:
        job["log"].append(f"tag: ffmpeg failed: {exc!r}")
        return
    if r.returncode == 0 and tmp.is_file():
        os.replace(tmp, path)
        job["title"] = title
        job["artist"] = artist
        job["log"].append(f"tag: {artist} — {title}")
    else:
        try:
            tmp.unlink()
        except OSError:
            pass
        job["log"].append(f"tag: ffmpeg exit {r.returncode}: {r.stderr.strip()[:200]}")


def run_yt_dlp(job):
    job["status"] = "running"
    MUSIC_DIR.mkdir(parents=True, exist_ok=True)
    cmd = [
        YT_DLP,
        "-4",
        "-w",
        "--no-color",
        "--newline",
        "--progress",
        "--extract-audio",
        "--audio-format", "mp3",
        "-o", str(MUSIC_DIR / "%(title)s.%(ext)s"),
    ]
    if FFMPEG_LOCATION:
        cmd += ["--ffmpeg-location", FFMPEG_LOCATION]
    cmd.append(job["url"])
    job["log"].append(f"$ {' '.join(cmd)}")
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        for line in proc.stdout:
            line = line.rstrip()
            job["log"].append(line)
            m = re.search(r"\[ExtractAudio\] Destination: (.+)$", line)
            if m:
                job["filename"] = os.path.basename(m.group(1))
            m = re.search(r"\[download\] Destination: (.+)$", line)
            if m and not job["filename"]:
                job["filename"] = os.path.basename(m.group(1))
        rc = proc.wait()
        job["exit_code"] = rc
        if rc == 0:
            job["status"] = "tagging"
            try:
                tag_mp3(job)
            except Exception as exc:
                job["log"].append(f"tag: unexpected error: {exc!r}")
            job["status"] = "done"
        else:
            job["status"] = "failed"
    except Exception as exc:
        job["log"].append(f"ERROR: {exc!r}")
        job["status"] = "failed"
        job["exit_code"] = -1
    finally:
        job["finished"] = now()
        gc_jobs()


def start_job(url):
    job = make_job(url)
    t = threading.Thread(target=run_yt_dlp, args=(job,), daemon=True)
    t.start()
    return job


def job_snapshot(job, include_log=False):
    out = {k: v for k, v in job.items() if k != "log"}
    if include_log:
        out["log"] = list(job["log"])
    else:
        out["log_tail"] = list(job["log"])[-3:]
    return out


INDEX_HTML = """<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>ytdl · download</title>
<style>
:root { --bg:#050805; --panel:#0a0e0a; --fg:#b8ffc4; --accent:#00ff66; --dim:#4a6a4e; --hover:#0f1810; --line:#1a2418; --warn:#ffb347; --err:#ff6b6b; }
* { box-sizing:border-box; margin:0; padding:0; }
html, body { background:var(--bg); color:var(--fg); font-family:"Iosevka","JetBrains Mono","Fira Code",ui-monospace,monospace; min-height:100vh; }
body { padding:2rem 1.5rem; }
.wrap { max-width:880px; margin:0 auto; }
h1 { font-size:1.05rem; font-weight:normal; letter-spacing:0.02em; margin-bottom:1.4rem; }
h1::before { content:'$ '; color:var(--accent); }
form { display:flex; gap:0.5rem; margin-bottom:1.5rem; }
input[type=url] { flex:1; background:var(--panel); border:1px solid var(--line); color:var(--fg); padding:0.7rem 0.9rem; font:inherit; outline:none; }
input[type=url]:focus { border-color:var(--accent); }
button { background:var(--panel); border:1px solid var(--accent); color:var(--accent); padding:0.7rem 1.2rem; font:inherit; cursor:pointer; letter-spacing:0.08em; text-transform:uppercase; font-size:0.78rem; }
button:hover { background:var(--hover); }
.hint { font-size:0.72rem; color:var(--dim); margin-bottom:1.4rem; }
ul.jobs { list-style:none; display:flex; flex-direction:column; gap:0.5rem; }
li.job { background:var(--panel); border:1px solid var(--line); padding:0.7rem 0.9rem; display:flex; flex-direction:column; gap:0.35rem; }
.job .head { display:flex; gap:0.6rem; align-items:baseline; flex-wrap:wrap; }
.job .tag { font-size:0.62rem; letter-spacing:0.15em; text-transform:uppercase; padding:0.08rem 0.4rem; border:1px solid var(--dim); color:var(--dim); }
.job .tag.queued { color:var(--dim); border-color:var(--dim); }
.job .tag.running { color:var(--warn); border-color:var(--warn); }
.job .tag.tagging { color:var(--warn); border-color:var(--warn); }
.job .tag.done { color:var(--accent); border-color:var(--accent); }
.job .tag.failed { color:var(--err); border-color:var(--err); }
.job .url { font-size:0.72rem; color:var(--dim); word-break:break-all; flex:1 1 auto; min-width:0; }
.job .file { font-size:0.82rem; color:var(--fg); word-break:break-all; }
.job .meta { font-size:0.74rem; color:var(--accent); word-break:break-all; }
.job .tail { font-size:0.7rem; color:var(--dim); white-space:pre-wrap; word-break:break-all; max-height:4.2em; overflow:hidden; }
.empty { color:var(--dim); font-size:0.78rem; padding:1rem 0; text-align:center; }
footer { margin-top:2rem; padding-top:1rem; border-top:1px solid var(--line); color:var(--dim); font-size:0.7rem; display:flex; justify-content:space-between; }
footer a { color:var(--accent); text-decoration:none; }
</style></head><body><div class="wrap">
<h1>ytdl · download to ~/Music</h1>
<form id="f">
<input id="u" type="url" name="url" placeholder="https://..." required autofocus>
<button type="submit">grab</button>
</form>
<div class="hint">yt-dlp → mp3 → <code>~/Music/%(title)s.mp3</code></div>
<ul id="jobs" class="jobs"></ul>
<footer><a href="https://hub.mvr.ac">← hub</a><span>ytdl.mvr.ac</span></footer>
</div>
<script>
const $jobs = document.getElementById('jobs');
const $f = document.getElementById('f');
const $u = document.getElementById('u');
$f.addEventListener('submit', async (e) => {
  e.preventDefault();
  const url = $u.value.trim();
  if (!url) return;
  $u.disabled = true;
  try {
    const r = await fetch('/api/download', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({url})});
    if (!r.ok) throw new Error(await r.text());
    $u.value = '';
    await refresh();
  } catch (err) { alert(err.message || err); }
  finally { $u.disabled = false; $u.focus(); }
});
function esc(s){ return String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
function fmtTime(t){ if(!t) return ''; const d=new Date(t*1000); return d.toLocaleTimeString(); }
async function refresh(){
  try {
    const r = await fetch('/api/jobs', {cache:'no-store'});
    if (!r.ok) return;
    const data = await r.json();
    if (!data.length){ $jobs.innerHTML = '<div class="empty">no jobs yet</div>'; return; }
    $jobs.innerHTML = data.map(j => `
      <li class="job">
        <div class="head">
          <span class="tag ${j.status}">${j.status}</span>
          <span class="url">${esc(j.url)}</span>
          <span style="color:var(--dim);font-size:0.7rem">${fmtTime(j.started)}</span>
        </div>
        ${j.filename ? `<div class="file">${esc(j.filename)}</div>` : ''}
        ${j.artist && j.title ? `<div class="meta">♪ ${esc(j.artist)} — ${esc(j.title)}</div>` : ''}
        ${j.log_tail && j.log_tail.length ? `<div class="tail">${esc(j.log_tail.join('\\n'))}</div>` : ''}
      </li>
    `).join('');
  } catch (e) {}
}
refresh();
setInterval(refresh, 2000);
</script></body></html>
"""


class Handler(BaseHTTPRequestHandler):
    server_version = "ytdl-web/1"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _send_json(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, body):
        data = body.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        p = urlparse(self.path)
        if p.path in ("/", "/index.html"):
            self._send_html(INDEX_HTML)
            return
        if p.path == "/api/jobs":
            with jobs_lock:
                ordered = list(reversed([jobs[j] for j in job_order if j in jobs]))
            self._send_json(200, [job_snapshot(j) for j in ordered])
            return
        if p.path.startswith("/api/jobs/"):
            jid = p.path[len("/api/jobs/"):]
            with jobs_lock:
                job = jobs.get(jid)
            if not job:
                self._send_json(404, {"error": "not found"})
                return
            self._send_json(200, job_snapshot(job, include_log=True))
            return
        if p.path == "/healthz":
            self._send_json(200, {"ok": True})
            return
        self.send_error(404)

    def do_POST(self):
        p = urlparse(self.path)
        if p.path == "/api/download":
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length) if length else b""
            ctype = self.headers.get("Content-Type", "")
            url = None
            try:
                if ctype.startswith("application/json"):
                    url = json.loads(raw.decode("utf-8")).get("url")
                else:
                    url = parse_qs(raw.decode("utf-8")).get("url", [None])[0]
            except Exception:
                pass
            if not url or not URL_RE.match(url):
                self._send_json(400, {"error": "invalid url"})
                return
            job = start_job(url)
            self._send_json(202, job_snapshot(job))
            return
        self.send_error(404)


def main():
    MUSIC_DIR.mkdir(parents=True, exist_ok=True)
    if not shutil.which(YT_DLP) and not os.path.isfile(YT_DLP):
        print(f"ytdl-web: yt-dlp not found at {YT_DLP}", file=sys.stderr)
        sys.exit(1)
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"ytdl-web: listening on {HOST}:{PORT}, music -> {MUSIC_DIR}", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
