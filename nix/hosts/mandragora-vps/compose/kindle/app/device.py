import gzip
import io
import os
import shlex
import subprocess
import time

HOST = os.environ.get("KINDLE_HOST", "100.80.53.92").strip()
PORT = os.environ.get("KINDLE_PORT", "22").strip()
KEY = os.environ.get("KINDLE_SSH_KEY", "/run/kindle_key").strip()
TIMEOUT = float(os.environ.get("KINDLE_SSH_TIMEOUT", "25"))
SCREEN_TTL = float(os.environ.get("KINDLE_SCREEN_TTL", "10"))
ART_DIR = "/mnt/us/mandragora/art"
SCRIPTLET_DIR = "/mnt/us/mandragora/scriptlets"
DOCUMENTS = "/mnt/us/documents"

FB_W = 1272
FB_PAGE_H = 1696
FB_PAGES = 2

_screen_cache: dict = {"png": None, "at": 0.0, "error": None}


class DeviceError(RuntimeError):
    pass


def _ssh_argv() -> list[str]:
    argv = [
        "ssh", "-T", "-x",
        "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", f"ConnectTimeout={int(TIMEOUT)}",
        "-o", "ServerAliveInterval=5",
        "-p", PORT,
    ]
    if KEY and os.path.exists(KEY):
        argv += ["-i", KEY]
    return argv + [f"root@{HOST}"]


def run(command: str, timeout: float | None = None, binary: bool = False):
    argv = _ssh_argv() + [command]
    try:
        proc = subprocess.run(
            argv, capture_output=True, timeout=timeout or TIMEOUT, check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise DeviceError(f"timed out after {timeout or TIMEOUT}s") from exc
    except OSError as exc:
        raise DeviceError(str(exc)) from exc
    if proc.returncode != 0:
        detail = (proc.stderr or b"").decode(errors="replace").strip()[:200]
        raise DeviceError(detail or f"ssh exited {proc.returncode}")
    return proc.stdout if binary else proc.stdout.decode(errors="replace")


def put(remote_path: str, data: bytes, mode: str = "644") -> None:
    q = shlex.quote(remote_path)
    argv = _ssh_argv() + [f"cat > {q} && chmod {mode} {q}"]
    try:
        proc = subprocess.run(argv, input=data, capture_output=True, timeout=120, check=False)
    except subprocess.TimeoutExpired as exc:
        raise DeviceError("upload timed out") from exc
    if proc.returncode != 0:
        raise DeviceError((proc.stderr or b"").decode(errors="replace").strip()[:200])


STATUS_SCRIPT = r"""
M=/mnt/us/mandragora
printf 'battery\t%s\n' "$(cat /sys/class/power_supply/*_bat/capacity 2>/dev/null | head -1)"
printf 'charging\t%s\n' "$(cat /sys/class/power_supply/*_ac/online 2>/dev/null | head -1)"
printf 'firmware\t%s\n' "$(sed -n 's/.*Version: //p' /etc/version.txt 2>/dev/null | head -1)"
printf 'uptime\t%s\n' "$(uptime | sed 's/.*up //; s/,.*load.*//')"
printf 'free\t%s\n' "$(df -h /mnt/us | awk 'NR==2{print $4}')"
printf 'used_pct\t%s\n' "$(df /mnt/us | awk 'NR==2{gsub("%","",$5); print $5}')"
printf 'ip\t%s\n' "$(ip -4 addr show wlan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)"
printf 'tailnet\t%s\n' "$($M/bin/tailscale --socket=$M/state/tailscaled.sock ip -4 2>/dev/null | head -1)"
printf 'dropbear\t%s\n' "$(pgrep -f $M/bin/dropbear >/dev/null && echo up || echo down)"
printf 'tailscaled\t%s\n' "$(pgrep -f $M/bin/tailscaled >/dev/null && echo up || echo down)"
printf 'koreader\t%s\n' "$(pgrep -f koreader >/dev/null && echo up || echo down)"
printf 'art\t%s\n' "$(ls $M/art/*.png 2>/dev/null | wc -l | tr -d ' ')"
printf 'showing\t%s\n' "$(basename "$(cat $M/state/portrait.last 2>/dev/null)" 2>/dev/null)"
"""


def status() -> dict:
    out = run(STATUS_SCRIPT)
    info: dict = {}
    for line in out.splitlines():
        if "\t" not in line:
            continue
        key, _, value = line.partition("\t")
        info[key.strip()] = value.strip()
    for key in ("battery", "used_pct", "art"):
        try:
            info[key] = int(info.get(key) or 0)
        except ValueError:
            info[key] = 0
    info["charging"] = info.get("charging") == "1"
    info["online"] = True
    return info


def _pick_live_page(raw: bytes):
    from PIL import Image

    full = Image.frombytes("L", (FB_W, FB_PAGE_H * FB_PAGES), raw)
    best = None
    best_levels = -1
    for index in range(FB_PAGES):
        page = full.crop((0, index * FB_PAGE_H, FB_W, (index + 1) * FB_PAGE_H))
        levels = sum(1 for count in page.histogram() if count)
        if levels > best_levels:
            best, best_levels = page, levels
    return best


def screen_png(force: bool = False) -> tuple[bytes, float]:
    now = time.time()
    if not force and _screen_cache["png"] and now - _screen_cache["at"] < SCREEN_TTL:
        return _screen_cache["png"], _screen_cache["at"]
    expected = FB_W * FB_PAGE_H * FB_PAGES
    try:
        payload = run(
            f"dd if=/dev/fb0 bs={FB_W} count={FB_PAGE_H * FB_PAGES} 2>/dev/null | gzip -1",
            timeout=60, binary=True,
        )
        raw = gzip.decompress(payload)
    except Exception as exc:
        if _screen_cache["png"]:
            _screen_cache["error"] = str(exc)
            return _screen_cache["png"], _screen_cache["at"]
        raise DeviceError(f"framebuffer read failed: {exc}") from exc
    if len(raw) < expected:
        raw = raw.ljust(expected, b"\xff")
    page = _pick_live_page(raw[:expected])
    buf = io.BytesIO()
    page.save(buf, format="PNG", optimize=True)
    _screen_cache.update({"png": buf.getvalue(), "at": now, "error": None})
    return _screen_cache["png"], now


def screen_age() -> float | None:
    if not _screen_cache["at"]:
        return None
    return time.time() - _screen_cache["at"]


def print_line(text: str) -> None:
    text = text.replace("\n", " ").strip()[:120]
    if not text:
        raise DeviceError("nothing to print")
    run(f"/var/local/kmc/bin/fbink -q -y -2 -- {shlex.quote(text)}")


def scriptlets() -> list[dict]:
    out = run(f"ls {SCRIPTLET_DIR}/*.sh 2>/dev/null || true")
    found = []
    for path in out.split():
        name = os.path.basename(path)
        found.append({"name": name, "label": name.replace(".sh", "").replace("mandragora-", "")})
    return found


def run_scriptlet(name: str) -> str:
    if name not in {s["name"] for s in scriptlets()}:
        raise DeviceError(f"unknown scriptlet: {name}")
    path = f"{SCRIPTLET_DIR}/{name}"
    return run(f"/bin/sh {shlex.quote(path)} 2>&1 | head -40", timeout=90)


def push_document(filename: str, data: bytes) -> str:
    safe = os.path.basename(filename).replace("\x00", "")
    if not safe:
        raise DeviceError("bad filename")
    target = f"{DOCUMENTS}/{safe}"
    put(target, data, mode="644")
    return target
