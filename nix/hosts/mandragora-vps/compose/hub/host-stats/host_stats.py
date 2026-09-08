"""Tiny HTTP endpoint that publishes host CPU + disk and probes every vhost.

Runs as a sidecar container next to the hub. Reads the host's /proc/stat
(via `pid: host` on the container) and statvfs of DISK_PATH (the host
rootfs bind-mounted in).
"""
from __future__ import annotations

import json
import os
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DISK_PATH = os.environ.get("DISK_PATH", "/host/rootfs")
SERVICES_FILE = os.environ.get("SERVICES_FILE", "/app/services.json")
PROBE_INTERVAL = float(os.environ.get("PROBE_INTERVAL", "60"))
PROBE_TIMEOUT = float(os.environ.get("PROBE_TIMEOUT", "8"))
PROBE_WORKERS = int(os.environ.get("PROBE_WORKERS", "6"))
PROBE_SLOW_MS = float(os.environ.get("PROBE_SLOW_MS", "5000"))
GATE_CODES = (401, 403)
PROBE_AGENT = "mandragora-hub-probe"
CPU_SAMPLE_SECONDS = float(os.environ.get("CPU_SAMPLE_SECONDS", "0.1"))
PROC_STAT = os.environ.get("PROC_STAT", "/proc/stat")


def _read_proc_stat() -> list[int] | None:
    try:
        with open(PROC_STAT, "r") as f:
            line = f.readline().split()
    except (FileNotFoundError, PermissionError):
        return None
    if not line or line[0] != "cpu":
        return None
    try:
        return [int(x) for x in line[1:]]
    except ValueError:
        return None


def read_cpu() -> dict | None:
    a = _read_proc_stat()
    if a is None:
        return None
    time.sleep(CPU_SAMPLE_SECONDS)
    b = _read_proc_stat()
    if b is None or len(a) < 5 or len(b) < 5:
        return None
    idle_delta = (b[3] + b[4]) - (a[3] + a[4])
    total_delta = sum(b) - sum(a)
    if total_delta <= 0:
        return None
    util_pct = max(0.0, min(100.0, 100.0 * (1.0 - idle_delta / total_delta)))
    return {"util_pct": util_pct}


def read_disk() -> dict | None:
    try:
        s = os.statvfs(DISK_PATH)
    except (FileNotFoundError, OSError):
        return None
    total = s.f_blocks * s.f_frsize
    free = s.f_bavail * s.f_frsize
    used = total - free
    if total <= 0:
        return None
    return {
        "used_gb": used / (1024 ** 3),
        "total_gb": total / (1024 ** 3),
        "used_pct": used / total * 100.0,
    }


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_opener = urllib.request.build_opener(_NoRedirect)
_health: dict = {"ts": 0.0, "services": {}}
_health_lock = threading.Lock()


def read_targets() -> list[tuple[str, str]]:
    try:
        with open(SERVICES_FILE) as f:
            doc = json.load(f)
    except (FileNotFoundError, PermissionError, ValueError, OSError):
        return []
    targets = []
    for svc in doc.get("services", []):
        host = svc.get("host")
        if host:
            targets.append((host, svc.get("probe", "/")))
    return targets


def probe_once(url: str) -> tuple[int, float]:
    request = urllib.request.Request(url, headers={"User-Agent": PROBE_AGENT})
    started = time.monotonic()
    code = 0
    try:
        with _opener.open(request, timeout=PROBE_TIMEOUT) as resp:
            code = resp.status
    except urllib.error.HTTPError as exc:
        code = exc.code
    except Exception:
        code = 0
    return code, (time.monotonic() - started) * 1000.0


def probe(target: tuple[str, str]) -> tuple[str, dict]:
    host, path = target
    url = "https://" + host + path
    code, elapsed_ms = probe_once(url)
    if code == 0 or code >= 500:
        code, elapsed_ms = probe_once(url)
    if code == 0 or code >= 500:
        state = "down"
    elif code >= 400 and code not in GATE_CODES:
        state = "warn"
    elif elapsed_ms >= PROBE_SLOW_MS:
        state = "warn"
    else:
        state = "ok"
    return host, {"code": code, "ms": round(elapsed_ms), "state": state}


def probe_round() -> None:
    targets = read_targets()
    if not targets:
        return
    with ThreadPoolExecutor(max_workers=PROBE_WORKERS) as pool:
        results = dict(pool.map(probe, targets))
    with _health_lock:
        _health["ts"] = time.time()
        _health["services"] = results


def probe_loop() -> None:
    while True:
        try:
            probe_round()
        except Exception:
            pass
        time.sleep(PROBE_INTERVAL)


def health() -> dict:
    with _health_lock:
        return {"ts": _health["ts"], "services": dict(_health["services"])}


def snapshot() -> dict:
    return {
        "cpu": read_cpu(),
        "disk": read_disk(),
        "ts": time.time(),
    }


class _Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        path = self.path.split("?")[0].rstrip("/")
        if path == "/api/health":
            body = health()
        elif path in ("", "/status", "/api/vps"):
            body = snapshot()
        else:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        payload = json.dumps(body).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format: str, *args) -> None:
        return


def main() -> None:
    host = os.environ.get("HOST_STATS_HOST", "0.0.0.0")
    port = int(os.environ.get("HOST_STATS_PORT", "8081"))
    threading.Thread(target=probe_loop, daemon=True).start()
    server = ThreadingHTTPServer((host, port), _Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
