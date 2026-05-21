"""Tiny HTTP endpoint that publishes a JSON snapshot of host CPU + disk.

Runs as a sidecar container next to the hub. Reads the host's /proc/stat
(via `pid: host` on the container) and statvfs of DISK_PATH (the host
rootfs bind-mounted in).
"""
from __future__ import annotations

import json
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DISK_PATH = os.environ.get("DISK_PATH", "/host/rootfs")
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


def snapshot() -> dict:
    return {
        "cpu": read_cpu(),
        "disk": read_disk(),
        "ts": time.time(),
    }


class _Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        if self.path.rstrip("/") not in ("", "/status", "/api/vps"):
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        payload = json.dumps(snapshot()).encode("utf-8")
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
    server = ThreadingHTTPServer((host, port), _Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
