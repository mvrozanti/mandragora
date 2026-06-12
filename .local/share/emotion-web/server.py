#!/usr/bin/env python3
"""emotion-web: HTTP UI for ~/Music emotion tagging."""
from __future__ import annotations

import hashlib
import http.server
import json
import os
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
from pathlib import Path
from queue import Queue
from uuid import uuid4

HOME_MUSIC = Path(os.environ.get("EMOTION_HOME", os.path.expanduser("~/Music")))
EMOTION_DIR = HOME_MUSIC / ".emotion"
CACHE_DIR = EMOTION_DIR / "cache"
JOBS_PATH = EMOTION_DIR / "jobs.json"
RANK_PY = EMOTION_DIR / "rank.py"

STATIC_DIR = Path(os.environ.get(
    "EMOTION_WEB_STATIC_DIR",
    str(Path(__file__).resolve().parent / "static"),
))

LISTEN_HOST = os.environ.get("EMOTION_WEB_LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("EMOTION_WEB_LISTEN_PORT", "8094"))
NIX_SHELL = os.environ.get("EMOTION_NIX_SHELL", shutil.which("nix-shell") or "/run/current-system/sw/bin/nix-shell")
GPU_LOCK = os.environ.get("EMOTION_GPU_LOCK", shutil.which("gpu-lock") or "/run/current-system/sw/bin/gpu-lock")

EXTS = {".mp3", ".m4a", ".flac", ".ogg", ".opus", ".wav", ".aac", ".wma"}
CACHE_VERSION = "v2-scene-vocab"
MOOD_KEYS = [
    "mood_acoustic", "mood_aggressive", "mood_electronic",
    "mood_happy", "mood_party", "mood_relaxed", "mood_sad",
]

state_lock = threading.Lock()
jobs: dict[str, dict] = {}
queue: Queue = Queue()


def log(msg: str) -> None:
    print(f"[emotion-web] {msg}", file=sys.stderr, flush=True)


def cache_key(path: Path) -> Path:
    st = path.stat()
    h = hashlib.sha1(
        f"{CACHE_VERSION}|{path}|{st.st_mtime_ns}|{st.st_size}".encode()
    ).hexdigest()
    return CACHE_DIR / f"{h}.json"


def discover() -> list[Path]:
    if not HOME_MUSIC.exists():
        return []
    files = []
    for p in HOME_MUSIC.iterdir():
        if p.is_file() and p.suffix.lower() in EXTS:
            files.append(p)
    files.sort()
    return files


def load_cached(path: Path) -> dict | None:
    ck = cache_key(path)
    if not ck.exists():
        return None
    try:
        return json.loads(ck.read_text())
    except Exception:
        return None


def gpu_lock_status() -> dict:
    try:
        r = subprocess.run([GPU_LOCK, "status"], capture_output=True, text=True, timeout=5)
        out = (r.stdout or r.stderr or "").strip()
        if "(none)" in out.lower() or out.upper().startswith("HOLDER: (NONE)"):
            return {"held": False, "raw": out}
        return {"held": True, "raw": out}
    except FileNotFoundError:
        return {"held": None, "error": "gpu-lock not found"}
    except Exception as e:
        return {"held": None, "error": str(e)}


def ollama_ok() -> bool:
    try:
        urllib.request.urlopen("http://127.0.0.1:11434/api/tags", timeout=2).read()
        return True
    except Exception:
        return False


def persist_jobs() -> None:
    try:
        JOBS_PATH.write_text(json.dumps(list(jobs.values())))
    except Exception:
        pass


def run_job(job_id: str) -> None:
    job = jobs[job_id]
    job["state"] = "running"
    job["started_at"] = time.time()
    persist_jobs()
    log_path = EMOTION_DIR / "logs" / f"job-{job_id}.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    job["log"] = str(log_path)

    only_file = EMOTION_DIR / "logs" / f"job-{job_id}.list"
    only_file.write_text("\n".join(job["filenames"]) + "\n")

    shellcmd = (
        f"cd '{EMOTION_DIR}' && "
        f"{GPU_LOCK} run --name emotion-web-{job_id} --expect 7200 -- "
        f"{NIX_SHELL} --run \"uv run rank.py --only-file '{only_file}'\" && "
        f"{NIX_SHELL} --run \"uv run rank.py --rewrite-outputs\""
    )

    try:
        with log_path.open("w") as logf:
            proc = subprocess.run(
                ["bash", "-lc", shellcmd],
                stdout=logf, stderr=subprocess.STDOUT, env={**os.environ, "HOME": os.environ.get("HOME", "/home/m")},
            )
            job["exit_code"] = proc.returncode
        job["state"] = "done" if proc.returncode == 0 else "failed"
    except Exception as e:
        job["state"] = "failed"
        job["error"] = str(e)
    finally:
        job["ended_at"] = time.time()
        persist_jobs()


def worker_thread() -> None:
    while True:
        job_id = queue.get()
        if job_id is None:
            break
        try:
            run_job(job_id)
        except Exception as e:
            log(f"worker crashed: {e}")


def _mood_top(ess: dict) -> str | None:
    items = [(k, ess[k]) for k in MOOD_KEYS if k in ess]
    if not items:
        return None
    name, _ = max(items, key=lambda kv: kv[1])
    return name.replace("mood_", "")


def _songs_summary() -> dict:
    rows = []
    files = discover()
    for f in files:
        d = load_cached(f) or {}
        ess = d.get("essentia") or {}
        clap = d.get("clap") or {}
        top = sorted(clap.items(), key=lambda kv: kv[1], reverse=True)[:3] if clap else []
        rows.append({
            "filename": f.name,
            "cached": bool(d) and not d.get("error"),
            "valence": ess.get("valence"),
            "arousal": ess.get("arousal"),
            "mood_top": _mood_top(ess),
            "mood_top_score": max((ess[k] for k in MOOD_KEYS if k in ess), default=None),
            "scene_top": [{"phrase": p, "score": s} for p, s in top],
            "error": d.get("error"),
        })
    return {"songs": rows}


def _status_payload() -> dict:
    files = discover()
    cached = 0
    for f in files:
        d = load_cached(f)
        if not d:
            continue
        if not d.get("error"):
            cached += 1
    current = next((j for j in jobs.values() if j.get("state") in ("queued", "running")), None)
    return {
        "totals": {"audio_files": len(files), "cached": cached},
        "gpu_lock": gpu_lock_status(),
        "ollama": ollama_ok(),
        "queue_len": queue.qsize(),
        "current_job": current,
        "cache_version": CACHE_VERSION,
    }


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "emotion-web/0.1"

    def log_message(self, fmt, *args):
        log(f"{self.address_string()} {fmt % args}")

    def _send_json(self, code: int, body) -> None:
        data = json.dumps(body, default=str).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(data)

    def _send_file(self, path: Path, ctype: str | None = None) -> None:
        if not path.exists() or not path.is_file():
            self.send_error(404)
            return
        data = path.read_bytes()
        if ctype is None:
            ctype = {
                ".html": "text/html; charset=utf-8",
                ".css": "text/css",
                ".js": "application/javascript",
                ".csv": "text/csv",
                ".tsv": "text/tab-separated-values",
                ".json": "application/json",
                ".svg": "image/svg+xml",
            }.get(path.suffix.lower(), "application/octet-stream")
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        p = u.path or "/"
        if p == "/" or p == "/index.html":
            self._send_file(STATIC_DIR / "index.html")
            return
        if p == "/api/status":
            self._send_json(200, _status_payload())
            return
        if p == "/api/songs":
            self._send_json(200, _songs_summary())
            return
        if p.startswith("/api/song/"):
            name = urllib.parse.unquote(p[len("/api/song/"):])
            for f in discover():
                if f.name == name:
                    return self._send_json(200, {"filename": name, "cache": load_cached(f)})
            return self._send_json(404, {"error": "not found"})
        if p == "/api/jobs":
            return self._send_json(200, {"jobs": list(jobs.values())})
        if p.startswith("/api/jobs/"):
            jid = p[len("/api/jobs/"):]
            j = jobs.get(jid)
            if not j:
                return self._send_json(404, {"error": "not found"})
            log_tail = ""
            log_p = j.get("log")
            if log_p and Path(log_p).exists():
                log_tail = Path(log_p).read_bytes()[-12000:].decode("utf-8", errors="replace")
            return self._send_json(200, {**j, "log_tail": log_tail})
        if p.startswith("/data/"):
            return self._send_file(STATIC_DIR / "data" / p[len("/data/"):])
        if p.startswith("/static/"):
            return self._send_file(STATIC_DIR / p[len("/static/"):])
        self.send_error(404)

    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        p = u.path or "/"
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length else b""
        try:
            data = json.loads(body) if body else {}
        except Exception:
            return self._send_json(400, {"error": "invalid json"})
        if p == "/api/tag":
            filenames = data.get("filenames") or []
            if not isinstance(filenames, list) or not filenames:
                return self._send_json(400, {"error": "filenames required"})
            all_files = {f.name for f in discover()}
            unknown = [f for f in filenames if f not in all_files]
            if unknown:
                return self._send_json(400, {"error": f"unknown filenames", "unknown": unknown[:5]})
            job_id = uuid4().hex[:12]
            with state_lock:
                jobs[job_id] = {
                    "id": job_id,
                    "filenames": filenames,
                    "state": "queued",
                    "queued_at": time.time(),
                }
                persist_jobs()
            queue.put(job_id)
            return self._send_json(200, jobs[job_id])
        self.send_error(404)


class ThreadingServer(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def server_bind(self):
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        super().server_bind()


def main() -> int:
    EMOTION_DIR.mkdir(parents=True, exist_ok=True)
    CACHE_DIR.mkdir(parents=True, exist_ok=True)

    if JOBS_PATH.exists():
        try:
            for j in json.loads(JOBS_PATH.read_text()):
                if j.get("state") in ("queued", "running"):
                    j["state"] = "interrupted"
                jobs[j["id"]] = j
        except Exception:
            pass

    threading.Thread(target=worker_thread, daemon=True).start()

    log(f"STATIC_DIR={STATIC_DIR}")
    log(f"EMOTION_DIR={EMOTION_DIR}")
    log(f"serving on http://{LISTEN_HOST}:{LISTEN_PORT}")
    srv = ThreadingServer((LISTEN_HOST, LISTEN_PORT), Handler)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        log("interrupt — shutting down")
    return 0


if __name__ == "__main__":
    sys.exit(main())
