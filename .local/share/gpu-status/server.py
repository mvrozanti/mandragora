"""hub.mvr.ac /api/gpu — JSON snapshot of gpu-lock holder + nvidia-smi.

Listens on $GPU_STATUS_HOST:$GPU_STATUS_PORT (default 0.0.0.0:6684) on
the tailscale0 interface; reached from the VPS via socat-tailnet@6684,
proxied by Caddy as the `/api/gpu` path under hub.mvr.ac. The hub HTML
polls this endpoint every few seconds to render a live status strip.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, "/etc/nixos/mandragora/.local/share/gpu-lock")
from gpu_lock import gpu_lock


NVIDIA_SMI_FIELDS = [
    "utilization.gpu",
    "memory.used",
    "memory.total",
    "temperature.gpu",
    "power.draw",
]


def query_nvidia_smi() -> dict:
    out = subprocess.run(
        [
            "nvidia-smi",
            f"--query-gpu={','.join(NVIDIA_SMI_FIELDS)}",
            "--format=csv,noheader,nounits",
        ],
        capture_output=True,
        text=True,
        check=True,
        timeout=5,
    ).stdout.strip().splitlines()
    parts = [v.strip() for v in out[0].split(",")]
    return {
        "utilization_pct": float(parts[0]),
        "memory_used_mib": float(parts[1]),
        "memory_total_mib": float(parts[2]),
        "temperature_c": float(parts[3]),
        "power_w": float(parts[4]),
    }


def query_holder() -> dict | None:
    holder = gpu_lock.current_holder()
    if not holder:
        return None
    now = time.time()
    since = holder.get("since", now)
    expected = holder.get("expected_seconds")
    remaining = None
    if expected is not None:
        remaining = max(0.0, since + expected - now)
    return {
        "name": holder.get("name"),
        "pid": holder.get("pid"),
        "since": since,
        "held_for_s": now - since,
        "expected_seconds": expected,
        "expected_remaining_s": remaining,
    }


def snapshot() -> dict:
    try:
        gpu = query_nvidia_smi()
        gpu_error = None
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError, ValueError) as e:
        gpu = None
        gpu_error = f"{type(e).__name__}: {e}"
    return {
        "ts": time.time(),
        "lock": {"holder": query_holder()},
        "gpu": gpu,
        "gpu_error": gpu_error,
    }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args, **_kwargs):
        return

    def do_GET(self):
        if self.path in ("/health", "/healthz"):
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", "3")
            self.end_headers()
            self.wfile.write(b"ok\n")
            return

        payload = json.dumps(snapshot()).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(payload)


def main() -> int:
    host = os.environ.get("GPU_STATUS_HOST", "0.0.0.0")
    port = int(os.environ.get("GPU_STATUS_PORT", "6684"))
    srv = ThreadingHTTPServer((host, port), Handler)
    print(f"gpu-status listening on http://{host}:{port}", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        srv.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
