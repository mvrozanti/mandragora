"""Tiny HTTP endpoint that publishes host CPU + disk, probes every vhost, and
counts tile clicks so the hub can order itself by use across every device.

Runs as a sidecar container next to the hub. Reads the host's /proc/stat
(via `pid: host` on the container) and statvfs of DISK_PATH (the host
rootfs bind-mounted in).
"""
from __future__ import annotations

import json
import os
import re
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
PROBE_AGENT = "mandragora-hub-probe"
CLICKS_FILE = os.environ.get("CLICKS_FILE", "/state/clicks.json")
CLICK_HOST_RE = re.compile(r"^(?:[a-z0-9-]+\.)*mvr\.ac$")
CPU_SAMPLE_SECONDS = float(os.environ.get("CPU_SAMPLE_SECONDS", "0.1"))
PROC_STAT = os.environ.get("PROC_STAT", "/proc/stat")
RING_FILE = os.environ.get("RING_FILE", "/state/probe-ring.json")
RING_STEP = 300
RING_SIZE = 288
STATE_CHAR = {"ok": "o", "warn": "w", "down": "d"}
CHAR_RANK = {".": 0, "o": 1, "w": 2, "d": 3}


def _probe_rules() -> tuple[float, tuple[int, ...]]:
    try:
        with open(SERVICES_FILE) as f:
            rules = json.load(f).get("probe", {})
    except (FileNotFoundError, PermissionError, ValueError, OSError, AttributeError):
        rules = {}
    return float(rules.get("slow_ms", 5000)), tuple(rules.get("gate_codes", (401, 403)))


PROBE_SLOW_MS, GATE_CODES = _probe_rules()


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


_ring: dict = {"end": 0, "hosts": {}}
_ring_lock = threading.Lock()


def _bucket_end(ts: float) -> int:
    return -(-int(ts) // RING_STEP) * RING_STEP


def load_ring() -> None:
    try:
        with open(RING_FILE) as f:
            stored = json.load(f)
        end = int(stored["end"])
        hosts = {
            str(h): str(s)[-RING_SIZE:].rjust(RING_SIZE, ".")
            for h, s in stored["hosts"].items()
        }
    except (FileNotFoundError, PermissionError, ValueError, OSError, KeyError, TypeError, AttributeError):
        return
    with _ring_lock:
        _ring["end"] = end
        _ring["hosts"] = hosts


def save_ring(snapshot: dict) -> None:
    tmp = RING_FILE + ".tmp"
    try:
        os.makedirs(os.path.dirname(RING_FILE), exist_ok=True)
        with open(tmp, "w") as f:
            json.dump(snapshot, f)
        os.replace(tmp, RING_FILE)
    except OSError:
        pass


def _ring_advance(end: int) -> None:
    gap = (end - _ring["end"]) // RING_STEP if _ring["end"] else RING_SIZE
    if gap <= 0:
        return
    pad = "." * min(gap, RING_SIZE)
    _ring["hosts"] = {h: (s + pad)[-RING_SIZE:] for h, s in _ring["hosts"].items()}
    _ring["end"] = end


def ring_record(results: dict, ts: float) -> None:
    with _ring_lock:
        _ring_advance(_bucket_end(ts))
        hosts = _ring["hosts"]
        for host, result in results.items():
            states = hosts.get(host, "." * RING_SIZE)
            new = STATE_CHAR.get(result.get("state"), ".")
            if CHAR_RANK[new] > CHAR_RANK[states[-1]]:
                states = states[:-1] + new
            hosts[host] = states
        snapshot = {"end": _ring["end"], "hosts": dict(hosts)}
    save_ring(snapshot)


_clicks: dict[str, int] = {}
_clicks_lock = threading.Lock()


def load_clicks() -> None:
    try:
        with open(CLICKS_FILE) as f:
            stored = json.load(f)
    except (FileNotFoundError, PermissionError, ValueError, OSError):
        return
    if not isinstance(stored, dict):
        return
    with _clicks_lock:
        for host, count in stored.items():
            if isinstance(count, int) and CLICK_HOST_RE.match(str(host)):
                _clicks[host] = count


def save_clicks(snapshot: dict[str, int]) -> None:
    tmp = CLICKS_FILE + ".tmp"
    try:
        os.makedirs(os.path.dirname(CLICKS_FILE), exist_ok=True)
        with open(tmp, "w") as f:
            json.dump(snapshot, f)
        os.replace(tmp, CLICKS_FILE)
    except OSError:
        pass


def record_click(host: str) -> bool:
    if not CLICK_HOST_RE.match(host or ""):
        return False
    with _clicks_lock:
        _clicks[host] = _clicks.get(host, 0) + 1
        snapshot = dict(_clicks)
    save_clicks(snapshot)
    return True


def clicks() -> dict:
    with _clicks_lock:
        return {"clicks": dict(_clicks)}


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
    ring_record(results, time.time())


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


def read_roster() -> dict:
    try:
        with open(SERVICES_FILE) as f:
            doc = json.load(f)
    except (FileNotFoundError, PermissionError, ValueError, OSError):
        return {}
    roster = {}
    for svc in doc.get("services", []):
        host = svc.get("host")
        if host:
            roster[host] = {k: svc.get(k) for k in ("name", "group", "where", "access")}
    return roster


def status_probes() -> dict:
    now = time.time()
    roster = read_roster()
    with _ring_lock:
        _ring_advance(_bucket_end(now))
        end = _ring["end"]
        rings = dict(_ring["hosts"])
    with _health_lock:
        live = dict(_health["services"])
    hosts = {
        host: dict(meta, states=rings.get(host, "." * RING_SIZE), now=live.get(host))
        for host, meta in roster.items()
    }
    return {
        "ts": now,
        "step": RING_STEP,
        "start": end - (RING_SIZE - 1) * RING_STEP,
        "end": end,
        "hosts": hosts,
    }


def snapshot() -> dict:
    return {
        "cpu": read_cpu(),
        "disk": read_disk(),
        "ts": time.time(),
    }


class _Handler(BaseHTTPRequestHandler):
    def _respond(self, code: int, payload: bytes | None) -> None:
        self.send_response(code)
        if payload is None:
            self.send_header("Content-Length", "0")
        else:
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        if payload is not None:
            self.wfile.write(payload)

    def do_POST(self) -> None:
        if self.path.split("?")[0].rstrip("/") != "/api/clicks":
            self._respond(404, None)
            return
        try:
            length = int(self.headers.get("Content-Length") or 0)
            payload = json.loads(self.rfile.read(min(length, 512)) or b"{}")
        except (ValueError, OSError):
            payload = {}
        ok = record_click(str(payload.get("host", "")))
        self._respond(200 if ok else 400, json.dumps({"ok": ok}).encode("utf-8"))

    def do_GET(self) -> None:
        path = self.path.split("?")[0].rstrip("/")
        if path == "/api/clicks":
            self._respond(200, json.dumps(clicks()).encode("utf-8"))
            return
        if path == "/api/health":
            body = health()
        elif path == "/api/status-probes":
            body = status_probes()
        elif path in ("", "/status", "/api/vps"):
            body = snapshot()
        else:
            self._respond(404, None)
            return
        self._respond(200, json.dumps(body).encode("utf-8"))

    def log_message(self, format: str, *args) -> None:
        return


def main() -> None:
    host = os.environ.get("HOST_STATS_HOST", "0.0.0.0")
    port = int(os.environ.get("HOST_STATS_PORT", "8081"))
    load_clicks()
    load_ring()
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
