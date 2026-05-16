"""Tiny HTTP endpoint that publishes a single JSON snapshot of GPU state.

Snapshot fields
---------------
- locked: bool — whether gpu_lock is currently held by another process
- holder: dict | null — pid/name/since/expected_seconds (and derived
  held_for, expected_remaining) read from gpu_lock's sidecar file
- gpu: dict | null — nvidia-smi util_pct, mem_used_mb, mem_total_mb,
  mem_pct, temp_c, power_w (null if nvidia-smi fails)
- ts: float — unix timestamp of the snapshot

Consumers
---------
- hub.mvr.ac dashboard tile polls every few seconds. The endpoint is
  intentionally cheap (one subprocess per request) and stateless.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

LOCK_DIR = Path(os.environ.get("GPU_LOCK_DIR", "/dev/shm/gpu-lock"))
HOLDER_FILE = LOCK_DIR / "gpu.lock.holder"
NVIDIA_SMI = os.environ.get("NVIDIA_SMI", "nvidia-smi")
QUERY_FIELDS = [
    "utilization.gpu",
    "utilization.memory",
    "memory.used",
    "memory.total",
    "temperature.gpu",
    "power.draw",
    "name",
]


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def read_holder() -> dict | None:
    try:
        raw = HOLDER_FILE.read_text()
    except FileNotFoundError:
        return None
    try:
        holder = json.loads(raw)
    except json.JSONDecodeError:
        return None
    pid = holder.get("pid")
    if isinstance(pid, int) and not _pid_alive(pid):
        return None
    since = holder.get("since")
    expected = holder.get("expected_seconds")
    now = time.time()
    if isinstance(since, (int, float)):
        holder["held_for"] = max(0.0, now - since)
        if isinstance(expected, (int, float)):
            holder["expected_remaining"] = max(0.0, since + expected - now)
    return holder


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


def snapshot() -> dict:
    holder = read_holder()
    return {
        "locked": holder is not None,
        "holder": holder,
        "gpu": read_gpu(),
        "ts": time.time(),
    }


class _Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        if self.path.rstrip("/") not in ("", "/status", "/api/gpu"):
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
