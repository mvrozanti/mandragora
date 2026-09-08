"""Tiny HTTP endpoint that publishes a JSON snapshot of host state for hub.mvr.ac.

Snapshot fields
---------------
- locked: bool — whether gpu_lock is currently held by another process
- holder: dict | null — pid/name/since/expected_seconds (and derived
  held_for, expected_remaining) read from gpu_lock's sidecar file
- gpu: dict | null — nvidia-smi util_pct, mem_used_mb, mem_total_mb,
  mem_pct, temp_c, power_w (null if nvidia-smi fails)
- cpu: dict | null — host-wide util_pct from /proc/stat (delta over a
  short sample window)
- disk: dict | null — used_gb, total_gb, used_pct for DISK_PATH (the
  meaningful persistent FS on impermanence hosts)
- ts: float — unix timestamp of the snapshot

Also serves /api/theme: the matugen palette setbg generated from the current
wallpaper, so every mvr.ac surface can wear the colours of the desk.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from gpu_lock import _holder_with_derived as read_holder

NVIDIA_SMI = os.environ.get("NVIDIA_SMI", "nvidia-smi")
DISK_PATH = os.environ.get("DISK_PATH", "/persistent")
CPU_SAMPLE_SECONDS = float(os.environ.get("CPU_SAMPLE_SECONDS", "0.1"))
THEME_FILE = os.path.expanduser(
    os.environ.get("HUB_THEME_FILE", "~/.cache/matugen/hub-theme.json")
)
ALLOWED_ORIGIN = re.compile(r"^https://([a-z0-9-]+\.)*mvr\.ac$")
QUERY_FIELDS = [
    "utilization.gpu",
    "utilization.memory",
    "memory.used",
    "memory.total",
    "temperature.gpu",
    "power.draw",
    "name",
]


def read_gpu() -> dict | None:
    smi = shutil.which(NVIDIA_SMI) or NVIDIA_SMI
    try:
        out = subprocess.check_output(
            [smi, f"--query-gpu={','.join(QUERY_FIELDS)}", "--format=csv,noheader,nounits"],
            stderr=subprocess.STDOUT,
            timeout=3,
        ).decode("utf-8", "replace").strip().splitlines()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        return None
    if not out:
        return None
    parts = [p.strip() for p in out[0].split(",")]
    if len(parts) < len(QUERY_FIELDS):
        return None
    def _f(s: str) -> float | None:
        try:
            return float(s)
        except ValueError:
            return None
    util = _f(parts[0])
    mem_util = _f(parts[1])
    mem_used = _f(parts[2])
    mem_total = _f(parts[3])
    mem_pct = (mem_used / mem_total * 100.0) if mem_used is not None and mem_total else None
    return {
        "name": parts[6] or None,
        "util_pct": util,
        "mem_util_pct": mem_util,
        "mem_used_mb": mem_used,
        "mem_total_mb": mem_total,
        "mem_pct": mem_pct,
        "temp_c": _f(parts[4]),
        "power_w": _f(parts[5]),
    }


def _read_proc_stat() -> list[int] | None:
    try:
        with open("/proc/stat", "r") as f:
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


def read_disk(path: str = DISK_PATH) -> dict | None:
    try:
        s = os.statvfs(path)
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
    holder = read_holder()
    return {
        "locked": holder is not None,
        "holder": holder,
        "gpu": read_gpu(),
        "cpu": read_cpu(),
        "disk": read_disk(),
        "ts": time.time(),
    }


def read_theme() -> dict | None:
    try:
        with open(THEME_FILE, "r") as f:
            return json.load(f)
    except (FileNotFoundError, PermissionError, ValueError, OSError):
        return None


class _Handler(BaseHTTPRequestHandler):
    def _cors_headers(self) -> None:
        origin = self.headers.get("Origin")
        if origin and ALLOWED_ORIGIN.match(origin):
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Access-Control-Allow-Credentials", "true")
        self.send_header("Vary", "Origin")

    def _respond(self, code: int, payload: bytes | None) -> None:
        self.send_response(code)
        self._cors_headers()
        if payload is None:
            self.send_header("Content-Length", "0")
        else:
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        if payload is not None:
            self.wfile.write(payload)

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self._cors_headers()
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self) -> None:
        path = self.path.split("?")[0].rstrip("/")
        if path == "/api/theme":
            theme = read_theme()
            self._respond(
                503 if theme is None else 200,
                None if theme is None else json.dumps(theme).encode("utf-8"),
            )
            return
        if path not in ("", "/status", "/api/gpu"):
            self._respond(404, None)
            return
        self._respond(200, json.dumps(snapshot()).encode("utf-8"))

    def log_message(self, format: str, *args) -> None:
        return


def main() -> None:
    host = os.environ.get("GPU_STATUS_HOST", "0.0.0.0")
    port = int(os.environ.get("GPU_STATUS_PORT", "6684"))
    server = ThreadingHTTPServer((host, port), _Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
