#!/usr/bin/env python3
import json
import mimetypes
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import urllib.request
import uuid
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse, quote

HOST = os.environ.get("YTDL_HOST", "0.0.0.0")
PORT = int(os.environ.get("YTDL_PORT", "6685"))
MUSIC_DIR = Path(os.environ.get("YTDL_MUSIC_DIR", os.path.expanduser("~/Music")))
VIDEO_DIR = Path(os.environ.get("YTDL_VIDEO_DIR", os.path.expanduser("~/Videos")))
TMP_DIR = Path(os.environ.get("YTDL_TMP_DIR", "/tmp/ytdl-web"))
STATE_HOME = os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state"))
STATE_FILE = Path(os.environ.get("YTDL_STATE_FILE", os.path.join(STATE_HOME, "ytdl-web", "jobs.json")))
STATIC_DIR = Path(os.environ.get("YTDL_STATIC_DIR", Path(__file__).resolve().parent / "static"))
THEME_URL = os.environ.get("YTDL_THEME_URL", "http://127.0.0.1:6684/api/theme?colors=1")
YT_DLP = os.environ.get("YTDL_YT_DLP", shutil.which("yt-dlp") or "yt-dlp")
FFMPEG_LOCATION = os.environ.get("YTDL_FFMPEG_LOCATION", "")
CLAUDE_BIN = os.environ.get("YTDL_CLAUDE", shutil.which("claude") or "claude")
TAG_MODEL = os.environ.get("YTDL_TAG_MODEL", "haiku")
DEVICE_FILE_TTL = int(os.environ.get("YTDL_JOB_TTL", "86400"))
MAX_JOBS = 200
PERSISTED_LOG_LINES = 20
MODES = ("audio", "video")
MODE_ARGS = {
    "audio": ["--extract-audio", "--audio-format", "mp3"],
    "video": ["-t", "mp4"],
}
MODE_DIRS = {"audio": MUSIC_DIR, "video": VIDEO_DIR}
ACTIVE = ("queued", "running", "tagging")
CANCELLABLE = ("queued", "running")
MARK = "ytdl-web:"
STAGES = (
    ("[download] Destination:", "downloading"),
    ("[ExtractAudio]", "converting"),
    ("[Merger]", "merging"),
    ("[MoveFiles]", "moving"),
)
PROGRESS_RE = re.compile(r"^\[download\]\s+([\d.]+)%\s*(.*)$")
JOB_RE = re.compile(r"^/api/jobs/([0-9a-f]{12})(?:/(file|stream|cancel))?$")
PERSISTED = (
    "id", "url", "mode", "to_client", "status", "started", "finished",
    "name", "filename", "filepath", "title", "artist", "exit_code",
)

TAG_SCHEMA = '{"type":"object","properties":{"is_music":{"type":"boolean"},"title":{"type":"string"},"artist":{"type":"string"}},"required":["is_music","title","artist"]}'
TAG_PROMPT = (
    "Extract the song title and performing artist from this YouTube video title. "
    "Strip junk like '(Official Video)', '[HD]', 'Lyrics', channel names. "
    "If the artist is unclear but this is a song, give your best guess from the title. "
    "If it is not a song (lecture, talk, podcast, video essay, news), set is_music to false "
    "and artist to an empty string; never answer with a placeholder such as 'Unknown'. Title: "
)
PLACEHOLDER_ARTIST_RE = re.compile(r"^\W*(unknown( artist)?|n/?a|none|null|various( artists)?|not a (song|music)\b.*)\W*(\(.*\))?\W*$", re.I)

URL_RE = re.compile(r"^https?://[^\s]+$")

jobs_lock = threading.RLock()
jobs = {}
job_order = deque()
procs_lock = threading.Lock()
procs = {}


def now():
    return time.time()


def job_tmp(job):
    return TMP_DIR / job["id"]


def new_job(url, to_client, mode):
    return {
        "id": uuid.uuid4().hex[:12],
        "url": url,
        "mode": mode,
        "to_client": to_client,
        "status": "queued",
        "started": now(),
        "finished": None,
        "name": None,
        "filename": None,
        "filepath": None,
        "title": None,
        "artist": None,
        "exit_code": None,
        "log": deque(maxlen=400),
    }


def save_state():
    with jobs_lock:
        records = []
        for jid in job_order:
            job = jobs.get(jid)
            if not job:
                continue
            rec = {k: job.get(k) for k in PERSISTED}
            rec["log"] = list(job["log"])[-PERSISTED_LOG_LINES:]
            records.append(rec)
        STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        tmp = STATE_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(records))
        os.replace(tmp, STATE_FILE)


def load_state():
    try:
        records = json.loads(STATE_FILE.read_text())
    except (OSError, ValueError):
        return
    with jobs_lock:
        for rec in records:
            if not isinstance(rec, dict) or not rec.get("id") or rec.get("mode") not in MODES:
                continue
            job = new_job(rec.get("url") or "", bool(rec.get("to_client")), rec["mode"])
            job.update({k: rec.get(k) for k in PERSISTED})
            job["artist"] = real_artist(job["artist"])
            job["log"].extend(rec.get("log") or [])
            if job["status"] in ACTIVE:
                job["status"] = "interrupted"
                job["finished"] = job["finished"] or now()
                job["log"].append("interrupted: ytdl-web restarted mid-download")
                purge_files(job)
            jobs[job["id"]] = job
            job_order.append(job["id"])


def purge_files(job):
    tmp = job_tmp(job)
    if job["to_client"] and job["status"] == "done":
        shutil.rmtree(tmp / "part", ignore_errors=True)
    else:
        shutil.rmtree(tmp, ignore_errors=True)


def gc_jobs():
    cutoff = now() - DEVICE_FILE_TTL
    with jobs_lock:
        for job in jobs.values():
            if job["to_client"] and job["finished"] and job["finished"] < cutoff and job_tmp(job).exists():
                shutil.rmtree(job_tmp(job), ignore_errors=True)
        while len(job_order) > MAX_JOBS:
            old = jobs.pop(job_order.popleft(), None)
            if old:
                shutil.rmtree(job_tmp(old), ignore_errors=True)
    save_state()


def set_status(job, status):
    job["status"] = status
    save_state()


def real_artist(artist):
    artist = (artist or "").strip()
    return artist if artist and not PLACEHOLDER_ARTIST_RE.match(artist) else None


def tag_mp3(job):
    path = Path(job.get("filepath") or "")
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
        artist = real_artist(so.get("artist"))
        is_music = so.get("is_music", True)
    except Exception as exc:
        job["log"].append(f"tag: parse failed: {exc!r}")
        return
    if not is_music or not artist:
        job["log"].append(f"tag: skipped, not a song: {proc.stdout.strip()[:200]}")
        return
    if not title:
        job["log"].append(f"tag: empty title: {proc.stdout.strip()[:200]}")
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


def read_output(job, proc):
    for line in proc.stdout:
        line = line.rstrip()
        if line.startswith(MARK):
            key, _, value = line[len(MARK):].partition("=")
            if key == "name":
                job["name"] = value
                save_state()
            elif key == "filepath":
                job["filepath"] = value
                job["filename"] = os.path.basename(value)
            continue
        m = PROGRESS_RE.match(line)
        if m:
            job["progress"] = float(m.group(1))
            job["detail"] = " ".join(m.group(2).split())
            continue
        for prefix, stage in STAGES:
            if line.startswith(prefix):
                job["stage"] = stage
                job["progress"] = None if stage != "downloading" else 0.0
                job["detail"] = ""
        job["log"].append(line)


def run_yt_dlp(job):
    tmp = job_tmp(job)
    part = tmp / "part"
    home = tmp if job["to_client"] else MODE_DIRS[job["mode"]]
    part.mkdir(parents=True, exist_ok=True)
    home.mkdir(parents=True, exist_ok=True)
    cmd = [
        YT_DLP,
        "-4",
        "-w",
        "--no-color",
        "--newline",
        "--progress",
        "--no-quiet",
        "-O", f"before_dl:{MARK}name=%(title)s",
        "-O", f"after_move:{MARK}filepath=%(filepath)s",
        *MODE_ARGS[job["mode"]],
        "-P", f"home:{home}",
        "-P", f"temp:{part}",
        "-o", "%(title)s.%(ext)s",
    ]
    if FFMPEG_LOCATION:
        cmd += ["--ffmpeg-location", FFMPEG_LOCATION]
    cmd.append(job["url"])
    job["log"].append(f"$ {' '.join(cmd)}")
    try:
        with procs_lock:
            if job.get("cancel"):
                raise InterruptedError
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                start_new_session=True,
            )
            procs[job["id"]] = proc
        set_status(job, "running")
        read_output(job, proc)
        rc = proc.wait()
        job["exit_code"] = rc
        has_file = bool(job["filepath"]) and Path(job["filepath"]).is_file()
        if job.get("cancel"):
            job["status"] = "cancelled"
        elif rc == 0 and has_file:
            if job["mode"] == "audio":
                set_status(job, "tagging")
                try:
                    tag_mp3(job)
                except Exception as exc:
                    job["log"].append(f"tag: unexpected error: {exc!r}")
            job["status"] = "done"
        else:
            job["status"] = "failed"
    except InterruptedError:
        job["status"] = "cancelled"
    except Exception as exc:
        job["log"].append(f"ERROR: {exc!r}")
        job["status"] = "failed"
        job["exit_code"] = -1
    finally:
        with procs_lock:
            procs.pop(job["id"], None)
        if job["status"] == "cancelled":
            job["log"].append("cancelled")
        for k in ("progress", "detail", "stage"):
            job.pop(k, None)
        job["finished"] = now()
        purge_files(job)
        gc_jobs()


def hard_kill(proc):
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def cancel_job(job):
    job["cancel"] = True
    with procs_lock:
        proc = procs.get(job["id"])
    if proc and proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        threading.Timer(5, hard_kill, (proc,)).start()


def forget_job(job):
    with jobs_lock:
        jobs.pop(job["id"], None)
        try:
            job_order.remove(job["id"])
        except ValueError:
            pass
    if job["to_client"]:
        shutil.rmtree(job_tmp(job), ignore_errors=True)
    save_state()


def start_job(url, to_client=False, mode="audio"):
    job = new_job(url, to_client, mode)
    with jobs_lock:
        jobs[job["id"]] = job
        job_order.append(job["id"])
    save_state()
    threading.Thread(target=run_yt_dlp, args=(job,), daemon=True).start()
    return job


def job_snapshot(job, include_log=False):
    out = {k: job.get(k) for k in PERSISTED if k != "filepath"}
    for k in ("progress", "detail", "stage"):
        if k in job:
            out[k] = job[k]
    out["cancelling"] = bool(job.get("cancel")) and job["status"] in ACTIVE
    out["has_file"] = bool(job.get("filepath")) and Path(job["filepath"]).is_file()
    out["gone"] = job["status"] == "done" and not out["has_file"]
    if include_log:
        out["log"] = list(job["log"])
    else:
        out["log_tail"] = list(job["log"])[-3:]
    return out


class Handler(BaseHTTPRequestHandler):
    server_version = "ytdl-web/2"

    def log_message(self, format, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), format % args))

    def _send_bytes(self, code, data, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _send_json(self, code, payload):
        self._send_bytes(code, json.dumps(payload).encode("utf-8"), "application/json")

    def _send_static(self, name):
        path = STATIC_DIR / name
        if "/" in name or name.startswith(".") or not path.is_file():
            self.send_error(404)
            return
        ctype = mimetypes.guess_type(name)[0] or "application/octet-stream"
        if ctype.startswith("text/") or ctype.endswith("javascript"):
            ctype += "; charset=utf-8"
        self._send_bytes(200, path.read_bytes(), ctype)

    def _send_theme(self):
        try:
            with urllib.request.urlopen(THEME_URL, timeout=2) as r:
                body = r.read()
        except Exception:
            self.send_response(204)
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            return
        self._send_bytes(200, body, "application/json")

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

    def _job_route(self, path):
        m = JOB_RE.match(path)
        if not m:
            return None, None
        with jobs_lock:
            job = jobs.get(m.group(1))
        if not job:
            self._send_json(404, {"error": "not found"})
            return False, None
        return job, m.group(2)

    def do_GET(self):
        p = urlparse(self.path)
        if p.path in ("/", "/index.html"):
            self._send_static("index.html")
            return
        if p.path.startswith("/static/"):
            self._send_static(p.path[len("/static/"):])
            return
        if p.path == "/api/theme":
            self._send_theme()
            return
        if p.path == "/api/jobs":
            with jobs_lock:
                ordered = list(reversed([jobs[j] for j in job_order if j in jobs]))
            self._send_json(200, [job_snapshot(j) for j in ordered])
            return
        if p.path == "/healthz":
            self._send_json(200, {"ok": True})
            return
        job, action = self._job_route(p.path)
        if job is False:
            return
        if job is None or action == "cancel":
            self.send_error(404)
            return
        if action is None:
            self._send_json(200, job_snapshot(job, include_log=True))
            return
        path = Path(job.get("filepath") or "")
        if not job.get("filepath") or not path.is_file():
            self._send_json(410, {"error": "gone"})
            return
        self._send_file(path, attachment=action == "file")

    def do_POST(self):
        p = urlparse(self.path)
        if p.path == "/api/download":
            self._post_download()
            return
        job, action = self._job_route(p.path)
        if job is False:
            return
        if job is None or action != "cancel":
            self.send_error(404)
            return
        if job["status"] not in CANCELLABLE:
            self._send_json(409, {"error": f"cannot cancel a {job['status']} job"})
            return
        cancel_job(job)
        self._send_json(202, job_snapshot(job))

    def do_DELETE(self):
        job, action = self._job_route(urlparse(self.path).path)
        if job is False:
            return
        if job is None or action is not None:
            self.send_error(404)
            return
        if job["status"] in ACTIVE:
            self._send_json(409, {"error": "cancel it first"})
            return
        forget_job(job)
        self._send_json(200, {"ok": True})

    def _post_download(self):
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


def main():
    for d in (*MODE_DIRS.values(), TMP_DIR):
        d.mkdir(parents=True, exist_ok=True)
    if not shutil.which(YT_DLP) and not os.path.isfile(YT_DLP):
        print(f"ytdl-web: yt-dlp not found at {YT_DLP}", file=sys.stderr)
        sys.exit(1)
    load_state()
    gc_jobs()
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"ytdl-web: listening on {HOST}:{PORT}, audio -> {MUSIC_DIR}, video -> {VIDEO_DIR}, history -> {STATE_FILE}", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
