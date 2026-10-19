#!/usr/bin/env python3
import json
import mimetypes
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
from urllib.parse import parse_qs, urlparse, quote

HOST = os.environ.get("YTDL_HOST", "0.0.0.0")
PORT = int(os.environ.get("YTDL_PORT", "6685"))
MUSIC_DIR = Path(os.environ.get("YTDL_MUSIC_DIR", os.path.expanduser("~/Music")))
VIDEO_DIR = Path(os.environ.get("YTDL_VIDEO_DIR", os.path.expanduser("~/Videos")))
TMP_DIR = os.environ.get("YTDL_TMP_DIR", "/tmp/ytdl-web")
YT_DLP = os.environ.get("YTDL_YT_DLP", shutil.which("yt-dlp") or "yt-dlp")
FFMPEG_LOCATION = os.environ.get("YTDL_FFMPEG_LOCATION", "")
CLAUDE_BIN = os.environ.get("YTDL_CLAUDE", shutil.which("claude") or "claude")
TAG_MODEL = os.environ.get("YTDL_TAG_MODEL", "haiku")
JOB_TTL = int(os.environ.get("YTDL_JOB_TTL", "86400"))
MAX_JOBS = 200
MODES = ("audio", "video")
MODE_ARGS = {
    "audio": ["--extract-audio", "--audio-format", "mp3"],
    "video": ["-t", "mp4"],
}
MODE_DIRS = {"audio": MUSIC_DIR, "video": VIDEO_DIR}
FILEPATH_MARK = "ytdl-web:filepath="

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


def make_job(url, to_client=False, mode="audio"):
    jid = uuid.uuid4().hex[:12]
    job = {
        "id": jid,
        "url": url,
        "to_client": to_client,
        "mode": mode,
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


def _cleanup_job(job):
    if not job or not job.get("to_client"):
        return
    fp = job.get("filepath")
    if fp:
        try:
            Path(fp).unlink()
        except OSError:
            pass
    d = job.get("dir")
    if d and d not in {str(x) for x in MODE_DIRS.values()}:
        try:
            Path(d).rmdir()
        except OSError:
            pass


def gc_jobs():
    cutoff = now() - JOB_TTL
    with jobs_lock:
        stale = [jid for jid, j in jobs.items() if j["finished"] and j["finished"] < cutoff]
        for jid in stale:
            job = jobs.pop(jid, None)
            _cleanup_job(job)
            try:
                job_order.remove(jid)
            except ValueError:
                pass


def tag_mp3(job):
    fn = job.get("filename")
    if not fn:
        return
    path = Path(job.get("dir") or str(MUSIC_DIR)) / fn
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
    outdir = Path(TMP_DIR) / job["id"] if job.get("to_client") else MODE_DIRS[job["mode"]]
    outdir.mkdir(parents=True, exist_ok=True)
    job["dir"] = str(outdir)
    cmd = [
        YT_DLP,
        "-4",
        "-w",
        "--no-color",
        "--newline",
        "--progress",
        "--no-quiet",
        "-O", f"after_move:{FILEPATH_MARK}%(filepath)s",
        *MODE_ARGS[job["mode"]],
        "-o", str(outdir / "%(title)s.%(ext)s"),
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
            if line.startswith(FILEPATH_MARK):
                job["filename"] = os.path.basename(line[len(FILEPATH_MARK):])
                continue
            job["log"].append(line)
        rc = proc.wait()
        job["exit_code"] = rc
        if rc == 0:
            if job["mode"] == "audio":
                job["status"] = "tagging"
                try:
                    tag_mp3(job)
                except Exception as exc:
                    job["log"].append(f"tag: unexpected error: {exc!r}")
            job["status"] = "done"
            if job.get("to_client") and job.get("filename"):
                p = Path(job["dir"]) / job["filename"]
                if p.is_file():
                    job["filepath"] = str(p)
        else:
            job["status"] = "failed"
    except Exception as exc:
        job["log"].append(f"ERROR: {exc!r}")
        job["status"] = "failed"
        job["exit_code"] = -1
    finally:
        job["finished"] = now()
        gc_jobs()


def start_job(url, to_client=False, mode="audio"):
    job = make_job(url, to_client, mode)
    t = threading.Thread(target=run_yt_dlp, args=(job,), daemon=True)
    t.start()
    return job


def job_snapshot(job, include_log=False):
    out = {k: v for k, v in job.items() if k not in ("log", "dir", "filepath")}
    out["has_file"] = bool(job.get("filepath") and Path(job["filepath"]).is_file())
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
.opts { display:flex; gap:1.2rem; flex-wrap:wrap; align-items:center; margin-bottom:0.6rem; }
.opts label { display:flex; gap:0.45rem; align-items:center; font-size:0.78rem; color:var(--fg); cursor:pointer; }
.opts input { accent-color:var(--accent); }
.job .dl { color:var(--accent); text-decoration:underline; }
.job .frow { display:flex; gap:0.6rem; align-items:center; flex-wrap:wrap; }
.job .fname { font-size:0.78rem; color:var(--dim); word-break:break-all; }
.job audio { width:100%; height:2.4rem; margin-top:0.2rem; }
.job video { width:100%; max-height:70vh; margin-top:0.2rem; background:#000; }
.job .time { color:var(--dim); font-size:0.7rem; }
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
<h1>ytdl · download</h1>
<form id="f">
<input id="u" type="url" name="url" placeholder="https://..." required autofocus>
<button type="submit">grab</button>
</form>
<div class="opts">
<label><input type="radio" name="mode" value="audio" checked> audio</label>
<label><input type="radio" name="mode" value="video"> video + audio</label>
<label><input id="toc" type="checkbox"> to this device (play / save)</label>
</div>
<div class="hint">audio → <code>~/Music/%(title)s.mp3</code> · video → <code>~/Videos/%(title)s.mp4</code> · to this device = play + save here, nothing kept on the desktop · lock-screen listening: pick audio</div>
<div id="empty" class="empty" hidden>no jobs yet</div>
<ul id="jobs" class="jobs"></ul>
<footer><a href="https://hub.mvr.ac">← hub</a><span>ytdl.mvr.ac</span></footer>
</div>
<script>
const $jobs = document.getElementById('jobs');
const $empty = document.getElementById('empty');
const $f = document.getElementById('f');
const $u = document.getElementById('u');
const $toc = document.getElementById('toc');
const $modes = [...document.querySelectorAll('input[name=mode]')];
const PREFS = 'ytdl-web:prefs';
try {
  const saved = JSON.parse(localStorage.getItem(PREFS) || '{}');
  if (typeof saved.to_client === 'boolean') $toc.checked = saved.to_client;
  const m = $modes.find(x => x.value === saved.mode);
  if (m) m.checked = true;
} catch (e) {}
const mode = () => ($modes.find(x => x.checked) || $modes[0]).value;
const savePrefs = () => { try { localStorage.setItem(PREFS, JSON.stringify({mode: mode(), to_client: $toc.checked})); } catch (e) {} };
$toc.addEventListener('change', savePrefs);
$modes.forEach(x => x.addEventListener('change', savePrefs));
$f.addEventListener('submit', async (e) => {
  e.preventDefault();
  const url = $u.value.trim();
  if (!url) return;
  $u.disabled = true;
  try {
    const r = await fetch('/api/download', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({url, mode: mode(), to_client: $toc.checked})});
    if (!r.ok) throw new Error(await r.text());
    $u.value = '';
    await refresh();
  } catch (err) { alert(err.message || err); }
  finally { $u.disabled = false; $u.focus(); }
});
function fmtTime(t){ if(!t) return ''; const d=new Date(t*1000); return d.toLocaleTimeString(); }
document.addEventListener('play', (e) => {
  const a = e.target;
  if (!a || !(a instanceof HTMLMediaElement) || !('mediaSession' in navigator)) return;
  const title = a.dataset.title || a.dataset.artist || 'ytdl';
  const artist = a.dataset.artist || '';
  navigator.mediaSession.metadata = new MediaMetadata({ title, artist, album: 'ytdl.mvr.ac' });
  navigator.mediaSession.setActionHandler('play', () => a.play());
  navigator.mediaSession.setActionHandler('pause', () => a.pause());
  navigator.mediaSession.setActionHandler('seekbackward', (d) => { a.currentTime = Math.max(0, a.currentTime - (d.seekOffset || 10)); });
  navigator.mediaSession.setActionHandler('seekforward', (d) => { a.currentTime += (d.seekOffset || 10); });
  navigator.mediaSession.setActionHandler('seekto', (d) => { a.currentTime = d.seekTime; });
}, true);
function el(tag, cls, text){
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
}
function setText(e, text){
  if (e.textContent !== text) e.textContent = text;
  e.hidden = !text;
}
function build(j){
  const li = el('li', 'job');
  const head = el('div', 'head');
  li.$tag = el('span', 'tag');
  head.append(li.$tag, el('span', 'url', j.url), el('span', 'time', fmtTime(j.started)));
  li.$file = el('div', 'file');
  li.$meta = el('div', 'meta');
  li.$tail = el('div', 'tail');
  li.append(head, li.$file, li.$meta, li.$tail);
  return li;
}
function attachFile(li, j){
  const row = el('div', 'frow');
  const save = el('a', 'dl', '↓ save');
  save.href = `/api/jobs/${j.id}/file`;
  save.download = '';
  row.append(save, el('span', 'fname', j.filename));
  li.$file.replaceChildren(row);
  if (j.to_client) {
    const m = el(j.mode === 'video' ? 'video' : 'audio');
    m.controls = true;
    m.preload = 'metadata';
    m.playsInline = true;
    m.dataset.title = j.title || j.filename || '';
    m.dataset.artist = j.artist || '';
    m.src = `/api/jobs/${j.id}/stream`;
    li.$file.append(m);
  }
  li.$file.hidden = false;
  li.attached = true;
}
function patch(li, j){
  li.$tag.className = `tag ${j.status}`;
  setText(li.$tag, j.status);
  if (j.has_file && !li.attached) attachFile(li, j);
  else if (!li.attached) setText(li.$file, j.filename || '');
  setText(li.$meta, j.artist && j.title ? `♪ ${j.artist} — ${j.title}` : '');
  setText(li.$tail, (j.log_tail || []).join('\\n'));
}
const nodes = new Map();
async function refresh(){
  try {
    const r = await fetch('/api/jobs', {cache:'no-store'});
    if (!r.ok) return;
    const data = await r.json();
    $empty.hidden = data.length > 0;
    const live = new Set(data.map(j => j.id));
    for (const [id, li] of nodes) if (!live.has(id)) { li.remove(); nodes.delete(id); }
    data.forEach((j, i) => {
      let li = nodes.get(j.id);
      if (!li) { li = build(j); nodes.set(j.id, li); }
      patch(li, j);
      if ($jobs.children[i] !== li) $jobs.insertBefore(li, $jobs.children[i] || null);
    });
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
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _send_file(self, path, attachment=True):
        path = Path(path)
        name = path.name
        size = path.stat().st_size
        ascii_name = name.encode("ascii", "ignore").decode("ascii").replace('"', "") or f"download{path.suffix}"
        ctype = mimetypes.guess_type(name)[0] or "application/octet-stream"
        utf8_name = quote(name, safe="")

        start, end = 0, size - 1
        status = 200
        range_header = self.headers.get("Range")
        if range_header and size:
            m = re.match(r"bytes=(\d*)-(\d*)", range_header)
            if m:
                a, b = m.group(1), m.group(2)
                if a:
                    start = int(a)
                    if b:
                        end = min(int(b), size - 1)
                elif b:
                    start = max(0, size - int(b))
                if start > end or start >= size:
                    self.send_response(416)
                    self.send_header("Content-Range", f"bytes */{size}")
                    self.end_headers()
                    return
                status = 206
        length = end - start + 1

        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Accept-Ranges", "bytes")
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Content-Length", str(length))
        if attachment:
            self.send_header("Content-Disposition",
                             f'attachment; filename="{ascii_name}"; filename*=UTF-8\'\'{utf8_name}')
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            with open(path, "rb") as f:
                f.seek(start)
                remaining = length
                while remaining > 0:
                    chunk = f.read(min(65536, remaining))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    remaining -= len(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass

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
        if p.path.startswith("/api/jobs/") and p.path.endswith("/file"):
            jid = p.path[len("/api/jobs/"):-len("/file")]
            with jobs_lock:
                job = jobs.get(jid)
            if not job or not job.get("filepath"):
                self._send_json(404, {"error": "not found"})
                return
            path = Path(job["filepath"])
            if not path.is_file():
                self._send_json(410, {"error": "gone"})
                return
            self._send_file(path)
            return
        if p.path.startswith("/api/jobs/") and p.path.endswith("/stream"):
            jid = p.path[len("/api/jobs/"):-len("/stream")]
            with jobs_lock:
                job = jobs.get(jid)
            if not job or not job.get("filepath"):
                self._send_json(404, {"error": "not found"})
                return
            path = Path(job["filepath"])
            if not path.is_file():
                self._send_json(410, {"error": "gone"})
                return
            self._send_file(path, attachment=False)
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
            to_client = False
            mode = "audio"
            try:
                if ctype.startswith("application/json"):
                    data = json.loads(raw.decode("utf-8"))
                    url = data.get("url")
                    to_client = bool(data.get("to_client"))
                    mode = data.get("mode") or mode
                else:
                    qs = parse_qs(raw.decode("utf-8"))
                    url = qs.get("url", [None])[0]
                    to_client = qs.get("to_client", ["0"])[0] in ("1", "true", "on")
                    mode = qs.get("mode", [mode])[0]
            except Exception:
                pass
            if not url or not URL_RE.match(url):
                self._send_json(400, {"error": "invalid url"})
                return
            if mode not in MODES:
                self._send_json(400, {"error": f"mode must be one of {', '.join(MODES)}"})
                return
            job = start_job(url, to_client, mode)
            self._send_json(202, job_snapshot(job))
            return
        self.send_error(404)


def main():
    for d in MODE_DIRS.values():
        d.mkdir(parents=True, exist_ok=True)
    if not shutil.which(YT_DLP) and not os.path.isfile(YT_DLP):
        print(f"ytdl-web: yt-dlp not found at {YT_DLP}", file=sys.stderr)
        sys.exit(1)
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"ytdl-web: listening on {HOST}:{PORT}, audio -> {MUSIC_DIR}, video -> {VIDEO_DIR}", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
